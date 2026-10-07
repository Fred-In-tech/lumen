/// Retouch analysis textures (research 09 §4, 07 §3.0), CPU-built once
/// per photo and sampled in source uv by both `applyRetouch` and
/// `retouch.frag`.
///
/// Every texture is RGBA8888 with **A = 255** (never packed, so
/// premultiplication cannot corrupt data) and is sampled with
/// `FilterQuality.none` plus a manual 4-tap bilinear at texel centres (like
/// `sampleAux`), so CPU and GPU read the same bytes.
///
/// | Sampler | Size | R | G | B |
/// |---|---|---|---|---|
/// | `uLow` | W×H | low-pass sRGB (Texture slider) | | |
/// | `uDeltaA` left tile | 2W×H | Smooth ΔL | Δa | Δb |
/// | `uDeltaA` right tile | | Shine ΔL | Δa | Δb |
/// | `uDeltaB` left tile | 2W×H | heal ΔL | Δa | Δb |
/// | `uDeltaB` right tile | | dark circles ΔL | Δa | Δb |
/// | `uDeltaC` left tile | 2W×H | eye bags ΔL | Even Δa | Even Δb |
/// | `uDeltaC` right tile | | iris ΔL | vein Δa | vein ΔL |
/// | `uRegionA` left tile | 2W×H | skin | under-eye | lash |
/// | `uRegionA` right tile | | mouth | sclera | iris |
/// | `uRegionB` left tile | 2W×H | lips | blush | wrinkle ΔL |
/// | `uRegionB` right tile | | face id* | spot code* | wrinkle zone* |
///
/// `*` = sample the nearest texel (no interpolation): face id is
/// `slot + 1` (0 = none), spot code see [encodeSpotCode] (kind 3 = clipped
/// shine core / glasses glare), wrinkle zone see `wrinkle_zones.dart`.
///
/// Each delta is the OkLab change its slider makes at 100, signed
/// ([encodeSignedDithered] with the ranges of [RetouchDelta]); the pass is
/// `out = src + Σ slider · mask · Δ`. Deltas are built from the bands
/// above the pore band (`band_split.dart`), so they are smooth: sampling
/// them at any output size gives the same result in preview and export,
/// and detail finer than the map grid is never touched. Wrinkle ΔL is
/// unsigned (`decodeWrinkle`): the L lift that fills every detected
/// wrinkle.
///
/// The image-scope backdrop atlas (`uBackdropMap`, 8th sampler) is
/// [BackdropMaps], on its own grid.
library;

import 'dart:typed_data';

import 'backdrop_maps.dart';
import 'blemish_types.dart';
import 'map_rect.dart';
import 'retouch_uniforms.dart';
import 'skin_deltas.dart' show SkinMeasure;

/// Faces with their own uniform row (more faces are not retouched).
const int kMaxRetouchFaces = 8;

/// Texels the nearest-texel lookup of `RetouchMaps.locate` (and the
/// shader's `LOCATE`) is shifted by, off exact texel edges.
const double kLocateBias = 0.01;

/// Floats of [RetouchMaps.packInfo]: `uMapInfo`, 3 vec4 per face, then
/// the backdrop info (2 vec4).
const int kRetouchInfoFloats = 4 + 12 * kMaxRetouchFaces + kBackdropInfoFloats;

/// Floats of [RetouchMaps.packFaceMaps]: 2 vec4 per face (transform and
/// tile bounds).
const int kRetouchFaceMapFloats = 8 * kMaxRetouchFaces;

/// Signed encoding ranges of the heal deltas (OkLab L, a, b).
const double kHealRangeL = 0.5;
const double kHealRangeA = 0.15;
const double kHealRangeB = 0.15;

/// A delta tile: its atlas (0 = `deltaA`, 1 = `deltaB`, 2 = `deltaC`),
/// tile (0 = left, 1 = right) and the signed range of each channel.
enum RetouchDelta {
  smooth(0, 0, 0.125, 0.05, 0.05),
  shine(0, 1, 0.4, 0.12, 0.12),
  heal(1, 0, kHealRangeL, kHealRangeA, kHealRangeB),
  darkCircles(1, 1, 0.2, 0.08, 0.08),

  /// R = eye bags ΔL, G / B = Even tone Δa / Δb.
  bagEven(2, 0, 0.1, 0.08, 0.08),

  /// R = iris ΔL, G = vein Δa, B = vein ΔL.
  eyes(2, 1, 0.1, 0.1, 0.1);

  const RetouchDelta(this.atlas, this.tile, this.r0, this.r1, this.r2);
  final int atlas;
  final int tile;
  final double r0;
  final double r1;
  final double r2;
}

/// Signed delta → byte: `128 + 127·clamp(v / range)`; 128 is exactly 0.
int encodeSigned(double v, double range) {
  final t = v / range;
  if (t.isNaN) return 128;
  if (t <= -1) return 1;
  if (t >= 1) return 255;
  return (128.5 + 127 * t).floor();
}

/// [encodeSigned] rounding up or down at random ([d] ∈ [0, 1), e.g.
/// `ditherAt`), so smooth signed fields do not band at 8 bits.
int encodeSignedDithered(double v, double range, double d) {
  final t = v / range;
  if (t.isNaN) return 128;
  if (t <= -1) return 1;
  if (t >= 1) return 255;
  final x = 128 + 127 * t;
  final lo = x.floorToDouble();
  final b = (x - lo > d ? lo + 1 : lo).toInt();
  return b < 1 ? 1 : (b > 255 ? 255 : b);
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
  spotCode(1, 1, 1),
  wrinkleZone(1, 1, 2);

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
    this.lipGlossL = 1,
    this.lipChromaGain = 1,
    this.lipShiftL = 0,
    this.blushA = 0,
    this.blushB = 0,
    this.hasForcedSpots = false,
    this.eyeRightX = 0,
    this.eyeRightY = 0,
    this.eyeLeftX = 0,
    this.eyeLeftY = 0,
    this.centerX = 0,
    this.centerY = 0,
    this.skin = const SkinMeasure(),
    this.mapScaleX,
    this.mapScaleY,
    this.mapOffsetX = 0,
    this.mapOffsetY = 0,
  });

  /// Source uv → map pixels of this face: `x = u · mapScaleX + mapOffsetX`
  /// (likewise y). Null scales mean the whole-frame grid (`W`, `H`). A
  /// per-face tile (`face_tiles.dart`) has its own scale and offset.
  final double? mapScaleX;
  final double? mapScaleY;
  final double mapOffsetX;
  final double mapOffsetY;

  /// Measured state of this face's skin (inputs of Auto Retouch).
  final SkinMeasure skin;

  final int slot;
  final String faceId;

  /// Work rect on the map grid.
  final MapRect rect;

  /// IOD in map pixels.
  final double iod;

  /// User-forced spot removals exist on this face (active at identity).
  final bool hasForcedSpots;

  /// Sclera P90 OkLab L (teeth cap, §3.6).
  final double teethCapL;
  final double skinMeanL;

  /// Lip P95 L: brighter lip pixels are gloss and keep their colour.
  final double lipGlossL;

  /// Lip chroma scale and L offset at Lip colour 100 (§3.9).
  final double lipChromaGain;
  final double lipShiftL;

  /// Blush at 100: OkLab a, b shift (target minus this face's skin).
  final double blushA;
  final double blushB;

  /// Iris centres (landmarks 468 / 473) in map pixels (red-eye discs).
  final double eyeRightX;
  final double eyeRightY;
  final double eyeLeftX;
  final double eyeLeftY;

  /// Ownership centre (≈ the nose, map px): overlapping work rects go to
  /// the face whose centre is nearest in IOD units (`face_ids.dart`).
  final double centerX;
  final double centerY;
}

/// Output of `computeRetouchMaps`: plain data, safe to send between
/// isolates. See the library doc for the texture layout.
class RetouchMaps {
  RetouchMaps({
    required this.width,
    required this.height,
    required this.low,
    required this.deltaA,
    required this.deltaB,
    required this.deltaC,
    required this.regionA,
    required this.regionB,
    this.faces = const [],
    this.blemishes = const [],
    BackdropMaps? backdrop,
  }) : backdrop = backdrop ?? BackdropMaps.none(BackdropState.notRequested) {
    final n = width * height * 4;
    if (low.length != n) throw ArgumentError('texture ${low.length} != $n');
    for (final t in [deltaA, deltaB, deltaC, regionA, regionB]) {
      if (t.length != 2 * n) {
        throw ArgumentError('atlas ${t.length} != ${2 * n}');
      }
    }
  }

  /// 1×1 neutral face maps (no faces), optionally with [backdrop] maps.
  factory RetouchMaps.empty({BackdropMaps? backdrop}) {
    Uint8List zero() =>
        Uint8List.fromList([128, 128, 128, 255, 128, 128, 128, 255]);
    return RetouchMaps(
      width: 1,
      height: 1,
      low: Uint8List.fromList([0, 0, 0, 255]),
      deltaA: zero(),
      deltaB: zero(),
      deltaC: zero(),
      regionA: Uint8List.fromList([0, 0, 0, 255, 0, 0, 0, 255]),
      regionB: Uint8List.fromList([0, 0, 0, 255, 0, 0, 0, 255]),
      backdrop: backdrop,
    );
  }

  /// Image-scope backdrop maps (neutral unless requested and solid).
  final BackdropMaps backdrop;

  /// These maps with new region atlases (everything else shared, so
  /// unchanged textures can be reused).
  RetouchMaps withRegions(Uint8List regionA, Uint8List regionB) => RetouchMaps(
    width: width,
    height: height,
    low: low,
    deltaA: deltaA,
    deltaB: deltaB,
    deltaC: deltaC,
    regionA: regionA,
    regionB: regionB,
    faces: faces,
    blemishes: blemishes,
    backdrop: backdrop,
  );

  /// Backdrop effects can run ([BackdropState.ready]).
  bool get hasBackdrop => backdrop.isReady;

  /// Clothes effects can run.
  bool get hasClothes => backdrop.clothesReady;

  /// Anything to retouch with: faces, a ready backdrop or clothes.
  bool get isUsable => hasFaces || hasBackdrop || hasClothes;

  /// Size of one tile (the `Rres` grid).
  final int width;
  final int height;

  /// W×H low-pass of the source (sRGB, dithered).
  final Uint8List low;

  /// 2W×H signed delta atlases (see [RetouchDelta]).
  final Uint8List deltaA;
  final Uint8List deltaB;
  final Uint8List deltaC;

  /// 2W×H region atlases.
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

  /// Bilinear signed delta [d] at uv into `out[o..o+2]` (decoded).
  void sampleDelta(
    RetouchDelta d,
    double u,
    double v,
    List<double> out,
    int o,
  ) {
    final atlas = d.atlas == 0 ? deltaA : (d.atlas == 1 ? deltaB : deltaC);
    _bilinear(atlas, 2 * width, d.tile * width, u, v, out, o);
    out[o] = decodeSigned(out[o], d.r0);
    out[o + 1] = decodeSigned(out[o + 1], d.r1);
    out[o + 2] = decodeSigned(out[o + 2], d.r2);
  }

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

  /// Map-pixel transform of [f]: `(scaleX, scaleY, offsetX, offsetY)`.
  ({double sx, double sy, double tx, double ty}) transformOf(
    RetouchFaceInfo f,
  ) => (
    sx: f.mapScaleX ?? width.toDouble(),
    sy: f.mapScaleY ?? height.toDouble(),
    tx: f.mapOffsetX,
    ty: f.mapOffsetY,
  );

  /// The face whose tile holds source uv `(u, v)` and owns it (its face id
  /// is there), or -1; with a face, [out] gets the map uv to sample at
  /// (`out[0..1]`) and the nearest texel (`out[2..3]`, for the face id,
  /// spot code and wrinkle zone). Mirrors `LOCATE` in `retouch.frag`:
  /// faces in slot order, the first tile whose bounds contain the point
  /// and whose nearest face-id texel is that face wins. The nearest texel
  /// is taken [kLocateBias] texels on: a tile finer than the image puts
  /// pixel centres exactly on texel edges, where float32 (GPU) and
  /// float64 (CPU) would round to different texels.
  int locate(double u, double v, List<double> out) {
    for (final f in faces) {
      final t = transformOf(f);
      final x = u * t.sx + t.tx, y = v * t.sy + t.ty;
      final r = f.rect;
      if (x < r.x0 || y < r.y0 || x >= r.x1 || y >= r.y1) continue;
      final qx = _ci((x + kLocateBias).floor(), width);
      final qy = _ci((y + kLocateBias).floor(), height);
      if (nearestTexel(RetouchChannel.faceId, qx, qy) != f.slot + 1) continue;
      out[0] = x / width;
      out[1] = y / height;
      if (out.length >= 4) {
        out[2] = qx.toDouble();
        out[3] = qy.toDouble();
      }
      return f.slot;
    }
    return -1;
  }

  /// Byte of [c] at texel `(x, y)` of its tile.
  int nearestTexel(RetouchChannel c, int x, int y) {
    final tex = c.texture == 0 ? regionA : regionB;
    return tex[(y * 2 * width + c.tile * width + x) * 4 + c.channel];
  }

  /// [nearest] of [c] at *source* uv `(u, v)`: 0 where no face owns the
  /// point (UI hit tests, tests).
  int sourceNearest(RetouchChannel c, double u, double v) {
    final uv = Float64List(4);
    if (locate(u, v, uv) < 0) return 0;
    return nearestTexel(c, uv[2].toInt(), uv[3].toInt());
  }

  /// Bilinear byte value (0..255) of region channel [c] at *source* uv
  /// `(u, v)`: 0 where no face owns the point.
  double sourceRegion(RetouchChannel c, double u, double v) {
    final uv = Float64List(4), out = Float64List(3);
    if (locate(u, v, uv) < 0) return 0;
    sampleTile(
      c.texture == 0 ? regionA : regionB,
      c.tile,
      uv[0],
      uv[1],
      out,
      0,
    );
    return out[c.channel];
  }

  /// Face map uniforms for `retouch.frag` ([kRetouchFaceMapFloats]): per
  /// slot k, `uFaceMap[2k]` = (scaleX, scaleY, offsetX, offsetY) and
  /// `uFaceMap[2k+1]` = tile bounds (x0, y0, x1, y1), all in map px.
  /// Empty slots are zero (their bounds contain nothing).
  Float32List packFaceMaps() {
    final out = Float32List(kRetouchFaceMapFloats);
    for (final f in faces) {
      final t = transformOf(f), o = 8 * f.slot, r = f.rect;
      out
        ..[o] = t.sx
        ..[o + 1] = t.sy
        ..[o + 2] = t.tx
        ..[o + 3] = t.ty
        ..[o + 4] = r.x0.toDouble()
        ..[o + 5] = r.y0.toDouble()
        ..[o + 6] = r.x1.toDouble()
        ..[o + 7] = r.y1.toDouble();
    }
    return out;
  }

  /// Analysis uniforms for `retouch.frag` (change only when the maps are
  /// rebuilt), [kRetouchInfoFloats] floats:
  ///
  /// | floats | vec4 | contents |
  /// |---|---|---|
  /// | 0–3 | `uMapInfo` | W, H, face count, 0 |
  /// | 4 + 12k + 0–3 | `uFaceInfo[3k]` | teethCapL, has maps (0/1), IOD (map px), lipGlossL |
  /// | 4 + 12k + 4–7 | `uFaceInfo[3k+1]` | lipChromaGain, lipShiftL, blush Δa, blush Δb |
  /// | 4 + 12k + 8–11 | `uFaceInfo[3k+2]` | right iris x, y, left iris x, y (map px) |
  /// | 100–103 | `uBackdropInfo0` | backdrop W, H, ready (0/1), τL |
  /// | 104–107 | `uBackdropInfo1` | median backdrop L, a, b, τC |
  Float32List packInfo() {
    final out = Float32List(kRetouchInfoFloats);
    out[0] = width.toDouble();
    out[1] = height.toDouble();
    out[2] = faces.length.toDouble();
    for (var k = 0; k < kMaxRetouchFaces; k++) {
      final f = faceInSlot(k), o = 4 + 12 * k;
      out[o] = f?.teethCapL ?? 1;
      out[o + 1] = f == null ? 0 : 1;
      out[o + 2] = f?.iod ?? 0;
      out[o + 3] = f?.lipGlossL ?? 1;
      out[o + 4] = f?.lipChromaGain ?? 1;
      out[o + 5] = f?.lipShiftL ?? 0;
      out[o + 6] = f?.blushA ?? 0;
      out[o + 7] = f?.blushB ?? 0;
      out[o + 8] = f?.eyeRightX ?? 0;
      out[o + 9] = f?.eyeRightY ?? 0;
      out[o + 10] = f?.eyeLeftX ?? 0;
      out[o + 11] = f?.eyeLeftY ?? 0;
    }
    out.setRange(
      kRetouchInfoFloats - kBackdropInfoFloats,
      kRetouchInfoFloats,
      backdrop.packInfo(),
    );
    return out;
  }
}

/// True when face [slot] has maps and something to do: a non-identity
/// slider row or user-forced spot removals.
bool retouchSlotActive(RetouchMaps maps, RetouchUniforms u, int slot) {
  final face = maps.faceInSlot(slot);
  return face != null && (!u.row(slot).isIdentity || face.hasForcedSpots);
}

/// True when the backdrop maps are ready and a backdrop value is set.
bool retouchBackdropActive(RetouchMaps maps, RetouchUniforms u) =>
    maps.hasBackdrop && !u.backdrop.backdropIdentity;

/// True when the clothes maps are ready and a clothes value is set.
bool retouchClothesActive(RetouchMaps maps, RetouchUniforms u) =>
    maps.hasClothes && !u.backdrop.clothesIdentity;

/// True when pass R changes at least one pixel (otherwise it is skipped
/// and the source is used bit-exact).
bool retouchPassActive(RetouchMaps maps, RetouchUniforms u) {
  if (retouchBackdropActive(maps, u) || retouchClothesActive(maps, u)) {
    return true;
  }
  if (!maps.hasFaces) return false;
  for (var k = 0; k < kMaxRetouchFaces; k++) {
    if (retouchSlotActive(maps, u, k)) return true;
  }
  return false;
}

extension RetouchMapsForced on RetouchMaps {
  /// Any face carries user-forced spot removals.
  bool get hasForcedSpots => faces.any((f) => f.hasForcedSpots);
}
