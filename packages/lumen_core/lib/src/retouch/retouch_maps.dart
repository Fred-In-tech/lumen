/// Retouch analysis textures (research 07 §3.0, §2.3), CPU-built and
/// sampled in source uv by both `applyRetouch` and `retouch.frag`.
///
/// Every texture is RGBA8888 with **A = 255** (never packed, so
/// premultiplication cannot corrupt data) and is sampled with
/// `FilterQuality.none` plus a manual 4-tap bilinear at texel centres (like
/// `sampleAux`), so CPU and GPU read the same bytes.
///
/// | Sampler | Size | R | G | B |
/// |---|---|---|---|---|
/// | `uB1` | W×H | B1 sRGB | | |
/// | `uB2` | W×H | B2 sRGB | | |
/// | `uB3` | W×H | B3 sRGB | | |
/// | `uBh` left tile | 2W×H | ΔL low | Δa low | Δb low |
/// | `uBh` right tile | | ΔL high | Δa high | Δb high |
/// | `uRegionA` left tile | 2W×H | skin | under-eye | lash |
/// | `uRegionA` right tile | | mouth | sclera | iris |
/// | `uRegionB` left tile | 2W×H | lips | blush | wrinkle |
/// | `uRegionB` right tile | | face id* | spot code* | 0 (spare) |
///
/// `*` = sample the nearest texel (no interpolation): face id is
/// `slot + 1` (0 = none), spot code see [encodeSpotCode]. Heal deltas
/// are signed (see [encodeSigned]); low heals the `B1` band, high the fine
/// band (research 07 §3.3).
library;

import 'dart:typed_data';

import 'blemish_types.dart';
import 'map_rect.dart';

/// Faces with their own uniform row (more faces are not retouched).
const int kMaxRetouchFaces = 8;

/// Signed encoding ranges of the heal deltas (OkLab L, a, b).
const double kHealRangeL = 0.25;
const double kHealRangeA = 0.1;
const double kHealRangeB = 0.1;

/// Signed delta → byte: `128 + 127·clamp(v / range)`; 128 is exactly 0.
int encodeSigned(double v, double range) {
  final t = v / range;
  if (t.isNaN) return 128;
  if (t <= -1) return 1;
  if (t >= 1) return 255;
  return (128.5 + 127 * t).floor();
}

/// Inverse of [encodeSigned] for a (possibly interpolated) byte value.
double decodeSigned(double byteValue, double range) =>
    (byteValue - 128) / 127 * range;

/// Logical channels of the region atlases.
enum RetouchChannel {
  skin(0, 0, 0),
  underEye(0, 0, 1),
  lash(0, 0, 2),
  mouth(0, 1, 0),
  sclera(0, 1, 1),
  iris(0, 1, 2),
  lips(1, 0, 0),
  blush(1, 0, 1),
  wrinkle(1, 0, 2),
  faceId(1, 1, 0),
  spotCode(1, 1, 1);

  const RetouchChannel(this.texture, this.tile, this.channel);

  /// 0 = `regionA`, 1 = `regionB`.
  final int texture;

  /// 0 = left tile, 1 = right tile.
  final int tile;

  /// 0 = R, 1 = G, 2 = B.
  final int channel;
}

/// Per-face analysis that travels with the maps (not slider state).
class RetouchFaceInfo {
  const RetouchFaceInfo({
    required this.slot,
    required this.faceId,
    required this.rect,
    required this.iod,
    required this.teethCapL,
    required this.skinMeanL,
  });

  final int slot;
  final String faceId;

  /// Work rect on the map grid.
  final MapRect rect;

  /// IOD in map pixels.
  final double iod;

  /// Sclera P90 OkLab L (teeth cap, §3.6).
  final double teethCapL;
  final double skinMeanL;
}

/// Output of `computeRetouchMaps`: plain data, safe to send between
/// isolates. See the library doc for the texture layout.
class RetouchMaps {
  RetouchMaps({
    required this.width,
    required this.height,
    required this.b1,
    required this.b2,
    required this.b3,
    required this.bh,
    required this.regionA,
    required this.regionB,
    this.faces = const [],
    this.blemishes = const [],
  }) {
    final n = width * height * 4;
    for (final t in [b1, b2, b3]) {
      if (t.length != n) throw ArgumentError('texture ${t.length} != $n');
    }
    for (final t in [bh, regionA, regionB]) {
      if (t.length != 2 * n) {
        throw ArgumentError('atlas ${t.length} != ${2 * n}');
      }
    }
  }

  /// 1×1 neutral maps (no faces).
  factory RetouchMaps.empty() {
    Uint8List px(int v) => Uint8List.fromList([v, v, v, 255]);
    return RetouchMaps(
      width: 1,
      height: 1,
      b1: px(0),
      b2: px(0),
      b3: px(0),
      bh: Uint8List.fromList([128, 128, 128, 255, 128, 128, 128, 255]),
      regionA: Uint8List.fromList([0, 0, 0, 255, 0, 0, 0, 255]),
      regionB: Uint8List.fromList([0, 0, 0, 255, 0, 0, 0, 255]),
    );
  }

  /// Size of one tile (the `Rres` grid).
  final int width;
  final int height;
  final Uint8List b1;
  final Uint8List b2;
  final Uint8List b3;

  /// 2W×H atlases.
  final Uint8List bh;
  final Uint8List regionA;
  final Uint8List regionB;

  /// Faces that have maps, in slot order.
  final List<RetouchFaceInfo> faces;

  /// Detected spots of every face (for keep/remove UI).
  final List<BlemishCandidate> blemishes;

  bool get hasFaces => faces.isNotEmpty;

  RetouchFaceInfo? faceInSlot(int slot) {
    for (final f in faces) {
      if (f.slot == slot) return f;
    }
    return null;
  }

  /// Bilinear RGB of a W×H texture at uv, in byte units (0..255), into
  /// `out[o..o+2]`. Mirrors the shader's manual 4-tap sampler.
  void sampleRgb(Uint8List tex, double u, double v, List<double> out, int o) =>
      _bilinear(tex, width, 0, u, v, out, o);

  /// Bilinear RGB of atlas [atlas] tile [tile], in byte units.
  void sampleTile(
    Uint8List atlas,
    int tile,
    double u,
    double v,
    List<double> out,
    int o,
  ) => _bilinear(atlas, 2 * width, tile * width, u, v, out, o);

  /// Nearest texel byte of [c] at uv (for the face id and spot code).
  int nearest(RetouchChannel c, double u, double v) {
    final x = _ci((u * width).floor(), width);
    final y = _ci((v * height).floor(), height);
    final tex = c.texture == 0 ? regionA : regionB;
    return tex[(y * 2 * width + c.tile * width + x) * 4 + c.channel];
  }

  void _bilinear(
    Uint8List tex,
    int stride,
    int x0off,
    double u,
    double v,
    List<double> out,
    int o,
  ) {
    final px = u * width - 0.5, py = v * height - 0.5;
    final fx0 = px.floorToDouble(), fy0 = py.floorToDouble();
    final fx = px - fx0, fy = py - fy0;
    final ix = fx0.toInt(), iy = fy0.toInt();
    final xa = _ci(ix, width) + x0off, xb = _ci(ix + 1, width) + x0off;
    final ya = _ci(iy, height), yb = _ci(iy + 1, height);
    final o00 = (ya * stride + xa) * 4, o10 = (ya * stride + xb) * 4;
    final o01 = (yb * stride + xa) * 4, o11 = (yb * stride + xb) * 4;
    final w00 = (1 - fx) * (1 - fy), w10 = fx * (1 - fy);
    final w01 = (1 - fx) * fy, w11 = fx * fy;
    for (var c = 0; c < 3; c++) {
      out[o + c] =
          tex[o00 + c] * w00 +
          tex[o10 + c] * w10 +
          tex[o01 + c] * w01 +
          tex[o11 + c] * w11;
    }
  }

  /// Clamp-to-edge texel index (no `num.clamp`: hot path).
  static int _ci(int i, int size) => i < 0 ? 0 : (i >= size ? size - 1 : i);

  /// Analysis uniforms for `retouch.frag` (changes only when the maps are
  /// rebuilt): `uMapInfo` = (W, H, face count, 0), then per slot
  /// `uFaceInfo[k]` = (teethCapL, has maps 0/1, IOD in map px, 0).
  Float32List packInfo() {
    final out = Float32List(4 + 4 * kMaxRetouchFaces);
    out[0] = width.toDouble();
    out[1] = height.toDouble();
    out[2] = faces.length.toDouble();
    for (var k = 0; k < kMaxRetouchFaces; k++) {
      final f = faceInSlot(k);
      out[4 + 4 * k] = f?.teethCapL ?? 1;
      out[5 + 4 * k] = f == null ? 0 : 1;
      out[6 + 4 * k] = f?.iod ?? 0;
    }
    return out;
  }
}
