/// Builds [RetouchMaps] once per photo (research 07 §3.0, §6.3).
///
/// [computeRetouchMaps] is a pure top-level function on plain data, so it
/// can run in `Isolate.run` unchanged.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import '../model/face_analysis.dart';
import '../render/aux_maps.dart';
import '../render/rgba_buffer.dart';
import 'backdrop_build.dart';
import 'backdrop_maps.dart';
import 'blemish_types.dart';
import 'face_frame.dart';
import 'face_maps.dart';
import 'face_mesh.dart';
import 'kernel_constants.dart';
import 'face_parsing_input.dart';
import 'lab_planes.dart';
import 'retouch_maps.dart';
import 'wrinkle_map.dart';

/// `Rres` long-edge bounds (§3.0) and the IOD the smallest face should get.
const int kRetouchMinLongEdge = 1024;
const int kRetouchMaxLongEdge = 2048;
const double kRetouchTargetIod = 160;

/// `Rres` long edge for a source of [srcLong] pixels whose smallest face
/// has an IOD of [minIodSrc] source pixels (never above the source).
int retouchMapLongEdge(int srcLong, double minIodSrc) {
  final want = minIodSrc > 0
      ? srcLong * kRetouchTargetIod / minIodSrc
      : kRetouchMinLongEdge.toDouble();
  final clamped = want.clamp(kRetouchMinLongEdge, kRetouchMaxLongEdge).ceil();
  return math.min(srcLong, clamped);
}

/// Computes the retouch maps of [source] for the first
/// [kMaxRetouchFaces] faces of [analysis]. [parsing] planes are matched by
/// face id; [longEdge] overrides the `Rres` choice (tests). With
/// [backdrop] (person / hair rasters) the image-scope backdrop maps are
/// built too, even when the photo has no faces.
RetouchMaps computeRetouchMaps(
  RgbaBuffer source,
  FaceAnalysis analysis, {
  List<FaceParsingPlanes>? parsing,
  int? longEdge,
  BlemishOverrides overrides = BlemishOverrides.none,
  BackdropInput? backdrop,
}) {
  final bd = computeBackdropMaps(source, backdrop);
  final srcLong = math.max(source.width, source.height);
  final slots = math.min(kMaxRetouchFaces, analysis.faces.length);
  final probe = [
    for (var k = 0; k < slots; k++)
      FaceFrame.tryCreate(
        analysis.faces[k],
        k,
        source.width,
        source.height,
        minIod: kMinFaceIodSourcePx,
      ),
  ].whereType<FaceFrame>().toList();
  if (probe.isEmpty) return RetouchMaps.empty(backdrop: bd);
  final minIod = probe.map((f) => f.iod).reduce(math.min);
  final grid = AuxMaps.proxy(
    source,
    longEdge: longEdge ?? retouchMapLongEdge(srcLong, minIod),
  );
  final frames = [
    for (final p in probe)
      FaceFrame.tryCreate(
        analysis.faces[p.slot],
        p.slot,
        grid.width,
        grid.height,
      ),
  ].whereType<FaceFrame>().where((f) => !f.rect.isEmpty).toList();
  final planes = [
    for (final f in frames)
      computeFaceMaps(
        f,
        grid,
        parsing: parsing?.where((p) => p.faceId == f.faceId).firstOrNull,
        overrides: overrides,
      ),
  ];
  return _assemble(grid, frames, planes, bd);
}

RetouchMaps _assemble(
  RgbaBuffer grid,
  List<FaceFrame> frames,
  List<FaceMapPlanes> planes,
  BackdropMaps backdrop,
) {
  final w = grid.width, h = grid.height, n = w * h * 4;
  final b1 = _opaqueCopy(grid.data), b2 = _opaqueCopy(grid.data);
  final b3 = _opaqueCopy(grid.data);
  final bh = Uint8List(2 * n)..fillRange(0, 2 * n, 128);
  final ra = Uint8List(2 * n), rb = Uint8List(2 * n);
  for (var i = 3; i < 2 * n; i += 4) {
    bh[i] = 255;
    ra[i] = 255;
    rb[i] = 255;
  }
  final owner = _owners(frames, w, h);
  for (final p in planes) {
    final slot = p.frame.slot;
    p.b1.writeSrgb(b1, w, owner, slot, seed: kDitherSeedB1);
    p.b2.writeSrgb(b2, w, owner, slot, seed: kDitherSeedB2);
    p.b3.writeSrgb(b3, w, owner, slot, seed: kDitherSeedB3);
    _writeFace(p, w, owner, bh, ra, rb);
  }
  return RetouchMaps(
    width: w,
    height: h,
    b1: b1,
    b2: b2,
    b3: b3,
    bh: bh,
    regionA: ra,
    regionB: rb,
    faces: [
      for (final p in planes)
        RetouchFaceInfo(
          slot: p.frame.slot,
          faceId: p.frame.faceId,
          rect: p.frame.rect,
          iod: p.frame.iod,
          teethCapL: p.regions.teethCapL,
          skinMeanL: p.regions.skinModel.meanL,
          lipGlossL: p.regions.makeup.glossL,
          lipChromaGain: p.regions.makeup.lipChromaGain,
          lipShiftL: p.regions.makeup.lipShiftL,
          blushA: p.regions.makeup.blushA,
          blushB: p.regions.makeup.blushB,
          hasForcedSpots: p.hasForcedSpots,
          eyeRightX: p.frame.xs[FaceMesh.rightIrisCenter],
          eyeRightY: p.frame.ys[FaceMesh.rightIrisCenter],
          eyeLeftX: p.frame.xs[FaceMesh.leftIrisCenter],
          eyeLeftY: p.frame.ys[FaceMesh.leftIrisCenter],
        ),
    ],
    backdrop: backdrop,
    blemishes: List.unmodifiable([for (final p in planes) ...p.blemishes]),
  );
}

/// Per grid pixel, the slot of the face that owns it (−1 = none): among
/// the faces whose work rect contains the pixel, the one whose
/// size-normalized centre is nearest; ties go to the larger face.
Int8List _owners(List<FaceFrame> frames, int w, int h) {
  final owner = Int8List(w * h)..fillRange(0, w * h, -1);
  final dist = Float32List(w * h)..fillRange(0, w * h, double.infinity);
  final bySize = [...frames]..sort((a, b) => b.iod.compareTo(a.iod));
  for (final f in bySize) {
    final r = f.rect;
    for (var y = r.y0; y < r.y1; y++) {
      for (var x = r.x0; x < r.x1; x++) {
        final i = y * w + x, d = f.ownershipDistance(x, y);
        if (d < dist[i]) {
          dist[i] = d;
          owner[i] = f.slot;
        }
      }
    }
  }
  return owner;
}

Uint8List _opaqueCopy(Uint8List src) {
  final out = Uint8List(src.length)..setRange(0, src.length, src);
  for (var i = 3; i < out.length; i += 4) {
    out[i] = 255;
  }
  return out;
}

/// 0..1 → byte without `num.clamp` (hot loop).
int _byte(double v) => v <= 0 ? 0 : (v >= 1 ? 255 : (v * 255 + 0.5).toInt());

void _writeFace(
  FaceMapPlanes p,
  int w,
  Int8List owner,
  Uint8List bh,
  Uint8List ra,
  Uint8List rb,
) {
  final rect = p.frame.rect, r = p.regions, heal = p.heal;
  final wr = p.wrinkles, slot = p.frame.slot;
  // Texels where an effect can apply get the face id (dilated by one
  // texel so bilinear fringes of the region maps keep their face).
  final active = Uint8List(rect.area);
  for (var y = rect.y0; y < rect.y1; y++) {
    var i = (y - rect.y0) * rect.w;
    for (var x = rect.x0; x < rect.x1; x++, i++) {
      if (owner[y * w + x] != slot) continue;
      final left = (y * 2 * w + x) * 4, right = left + w * 4;
      bh[left] = encodeSigned(heal.lowL[i], kHealRangeL);
      bh[left + 1] = encodeSigned(heal.lowA[i], kHealRangeA);
      bh[left + 2] = encodeSigned(heal.lowB[i], kHealRangeB);
      bh[right] = encodeSigned(heal.highL[i], kHealRangeL);
      bh[right + 1] = encodeSigned(heal.highA[i], kHealRangeA);
      bh[right + 2] = encodeSigned(heal.highB[i], kHealRangeB);
      final skin = _byte(r.skin[i]), under = _byte(r.underEye[i]);
      final mouth = _byte(r.mouth[i]), sclera = _byte(r.sclera[i]);
      final iris = _byte(r.iris[i]), lips = _byte(r.lips[i]);
      final blush = _byte(r.blush[i]), wrinkle = encodeWrinkle(wr.delta[i]);
      ra[left] = skin;
      ra[left + 1] = under;
      ra[left + 2] = _byte(r.lash[i]);
      ra[right] = mouth;
      ra[right + 1] = sclera;
      ra[right + 2] = iris;
      rb[left] = lips;
      rb[left + 1] = blush;
      rb[left + 2] = wrinkle;
      final code = heal.spotCode[i];
      rb[right + 1] = code;
      rb[right + 2] = wrinkle == 0 ? 0 : wr.zone[i];
      final any =
          skin | under | mouth | sclera | iris | lips | blush | wrinkle | code;
      if (any != 0 ||
          _healed(bh, left) ||
          _healed(bh, right) ||
          _inEyeDisc(p.frame, x + 0.5, y + 0.5)) {
        active[i] = 1;
      }
    }
  }
  final grown = _grow(active, rect.w, rect.h);
  final id = slot + 1;
  for (var y = rect.y0; y < rect.y1; y++) {
    var i = (y - rect.y0) * rect.w;
    for (var x = rect.x0; x < rect.x1; x++, i++) {
      if (grown[i] != 0 && owner[y * w + x] == slot) {
        rb[(y * 2 * w + w + x) * 4] = id;
      }
    }
  }
}

/// Inside a red-eye disc ([kRedEyeRadiusIod] around an iris centre).
bool _inEyeDisc(FaceFrame f, double x, double y) {
  final r = kRedEyeRadiusIod * f.iod;
  for (final c in [FaceMesh.rightIrisCenter, FaceMesh.leftIrisCenter]) {
    final dx = x - f.xs[c], dy = y - f.ys[c];
    if (dx * dx + dy * dy <= r * r) return true;
  }
  return false;
}

bool _healed(Uint8List bh, int o) =>
    bh[o] != 128 || bh[o + 1] != 128 || bh[o + 2] != 128;

/// 3×3 binary dilation (separable max of radius 1).
Uint8List _grow(Uint8List m, int w, int h) {
  final row = Uint8List(m.length), out = Uint8List(m.length);
  for (var y = 0; y < h; y++) {
    final base = y * w;
    for (var x = 0; x < w; x++) {
      if (m[base + x] != 0 ||
          (x > 0 && m[base + x - 1] != 0) ||
          (x < w - 1 && m[base + x + 1] != 0)) {
        row[base + x] = 1;
      }
    }
  }
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = y * w + x;
      if (row[i] != 0 ||
          (y > 0 && row[i - w] != 0) ||
          (y < h - 1 && row[i + w] != 0)) {
        out[i] = 1;
      }
    }
  }
  return out;
}
