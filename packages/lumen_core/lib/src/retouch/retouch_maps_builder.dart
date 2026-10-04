/// Builds [RetouchMaps] once per photo (research 07 §3.0, §6.3).
///
/// [computeRetouchMaps] is a pure top-level function on plain data, so it
/// can run in `Isolate.run` unchanged.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import '../model/face_analysis.dart';
import '../model/mask_shapes.dart';
import '../render/aux_maps.dart';
import '../render/rgba_buffer.dart';
import 'backdrop_build.dart';
import 'backdrop_maps.dart';
import 'blemish_types.dart';
import 'face_frame.dart';
import 'face_ids.dart';
import 'face_maps.dart';
import 'face_mesh.dart';
import 'face_parsing_input.dart';
import 'lab_planes.dart';
import 'retouch_maps.dart';
import 'skin_pen.dart';
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
/// built too, even when the photo has no faces. [skinPen] (Manual Tuning
/// Pen strokes) is applied last, exactly like `applySkinPen` on the
/// pen-free maps.
RetouchMaps computeRetouchMaps(
  RgbaBuffer source,
  FaceAnalysis analysis, {
  List<FaceParsingPlanes>? parsing,
  int? longEdge,
  BlemishOverrides overrides = BlemishOverrides.none,
  BackdropInput? backdrop,
  List<BrushStroke> skinPen = const [],
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
  return applySkinPen(_assemble(grid, frames, planes, bd), skinPen);
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
  final faces = [for (final p in planes) _info(p)];
  final owner = faceOwners(faces, w, h);
  for (var k = 0; k < planes.length; k++) {
    final p = planes[k], slot = p.frame.slot;
    p.b1.writeSrgb(b1, w, owner, slot, seed: kDitherSeedB1);
    p.b2.writeSrgb(b2, w, owner, slot, seed: kDitherSeedB2);
    p.b3.writeSrgb(b3, w, owner, slot, seed: kDitherSeedB3);
    _writeFace(p, w, owner, bh, ra, rb);
    assignFaceIds(faces[k], w, owner, bh, ra, rb);
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
    faces: faces,
    backdrop: backdrop,
    blemishes: List.unmodifiable([for (final p in planes) ...p.blemishes]),
  );
}

RetouchFaceInfo _info(FaceMapPlanes p) {
  final f = p.frame;
  return RetouchFaceInfo(
    slot: f.slot,
    faceId: f.faceId,
    rect: f.rect,
    iod: f.iod,
    teethCapL: p.regions.teethCapL,
    skinMeanL: p.regions.skinModel.meanL,
    lipGlossL: p.regions.makeup.glossL,
    lipChromaGain: p.regions.makeup.lipChromaGain,
    lipShiftL: p.regions.makeup.lipShiftL,
    blushA: p.regions.makeup.blushA,
    blushB: p.regions.makeup.blushB,
    hasForcedSpots: p.hasForcedSpots,
    eyeRightX: f.xs[FaceMesh.rightIrisCenter],
    eyeRightY: f.ys[FaceMesh.rightIrisCenter],
    eyeLeftX: f.xs[FaceMesh.leftIrisCenter],
    eyeLeftY: f.ys[FaceMesh.leftIrisCenter],
    // FaceFrame.ownershipDistance: the nose, 0.45 IOD below the eyes.
    centerX: f.eyeMid.x + kOwnershipCenterIod * f.iod * f.axis.x,
    centerY: f.eyeMid.y + kOwnershipCenterIod * f.iod * f.axis.y,
  );
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
    }
  }
}

// Face ids: face_ids.dart (shared with the Manual Tuning Pen).
