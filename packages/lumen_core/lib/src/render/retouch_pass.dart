/// Uniforms of the GPU retouch pass `R` (`app/shaders/retouch.frag`), the
/// shader twin of `applyRetouch` (`retouch/retouch_kernel.dart`).
///
/// Layout (382 floats = `vec2` + 95 `vec4`, set in declaration order):
///
/// | floats | uniform | contents |
/// |---|---|---|
/// | 0–1 | `uSize` | pass size (px) |
/// | 2–5 | `uTile` | pass offset x, y in the source; full source w, h |
/// | 6–9 | `uMapInfo` | map grid W, H, face count (`RetouchMaps.packInfo`), **source is the pass window** (0/1) |
/// | 10 + 12k | `uFaceInfo{3k}` | teeth cap L, **active**, IOD (map px), lip gloss L |
/// | 14 + 12k | `uFaceInfo{3k+1}` | lip chroma gain, lip L shift, blush Δa, blush Δb |
/// | 18 + 12k | `uFaceInfo{3k+2}` | right iris x, y, left iris x, y (map px) |
/// | 106–109 | `uBackdropInfo0` | backdrop W, H, **active**, τL |
/// | 110–113 | `uBackdropInfo1` | median backdrop L, a, b, τC |
/// | 114–117 | `uRetouch` | face count, any active, spot ramp, 0 |
/// | 118 + 24k | `uFace{6k..6k+5}` | the face row (`RetouchUniforms.pack`) |
/// | 310–313 | `uBackdropParams` | clean, unify, luminance, strays |
/// | 314–317 | `uClothesParams` | wrinkles, lint, **active**, 0 |
/// | 318 + 8k | `uFaceMap{2k}` | face k: source uv → map px scale x, y, offset x, y (`RetouchMaps.packFaceMaps`) |
/// | 322 + 8k | `uFaceMap{2k+1}` | face k: tile bounds x0, y0, x1, y1 (map px) |
///
/// "active" (slot has maps and a non-identity row; backdrop / clothes
/// ready and one of their values set) replaces the "has maps" / "ready" floats of
/// `packInfo`, so the shader keeps untouched pixels bit-exact exactly
/// where the CPU kernel returns early.
library;

import 'dart:typed_data';

import '../retouch/backdrop_maps.dart';
import '../retouch/blemish_types.dart';
import '../retouch/retouch_maps.dart';
import '../retouch/retouch_uniforms.dart';

const int kRetouchPassFloatCount =
    6 + kRetouchInfoFloats + kRetouchUniformFloats + kRetouchFaceMapFloats;

abstract final class RetouchPassIndex {
  static const size = 0;
  static const tile = 2;
  static const mapInfo = 6;

  /// `uMapInfo.w`: 1 when the source texture is the pass window itself.
  static const sourceIsWindow = 9;
  static int faceInfo(int slot) => 10 + 12 * slot;
  static int makeupInfo(int slot) => 14 + 12 * slot;
  static int eyeInfo(int slot) => 18 + 12 * slot;
  static const backdropInfo = 6 + kRetouchInfoFloats - kBackdropInfoFloats;
  static const header = 6 + kRetouchInfoFloats;
  static const rows = header + kRetouchHeaderFloats;
  static const faceMaps = 6 + kRetouchInfoFloats + kRetouchUniformFloats;
  static const backdropParams = faceMaps - 8;
  static const clothesParams = faceMaps - 4;
}

abstract final class RetouchPassUniforms {
  /// True when face [slot] has maps and something to do.
  static bool slotActive(RetouchMaps maps, RetouchUniforms u, int slot) =>
      retouchSlotActive(maps, u, slot);

  /// True when the pass changes at least one pixel (otherwise skip it).
  static bool isActive(RetouchMaps maps, RetouchUniforms u) =>
      retouchPassActive(maps, u);

  /// Packs the pass uniforms for a [width]×[height] pass at ([tileX],
  /// [tileY]) of a [fullWidth]×[fullHeight] source (defaults: whole image).
  ///
  /// [sourceIsWindow]: the source texture holds exactly the pass rectangle
  /// (a window of the full source, as in the float export) instead of the
  /// whole source; the maps are still sampled at the full-source uv.
  static Float32List pack(
    RetouchMaps maps,
    RetouchUniforms u, {
    required int width,
    required int height,
    double tileX = 0,
    double tileY = 0,
    double? fullWidth,
    double? fullHeight,
    bool sourceIsWindow = false,
  }) {
    final f = Float32List(kRetouchPassFloatCount)
      ..[0] = width.toDouble()
      ..[1] = height.toDouble()
      ..[2] = tileX
      ..[3] = tileY
      ..[4] = fullWidth ?? width.toDouble()
      ..[5] = fullHeight ?? height.toDouble();
    f.setRange(
      RetouchPassIndex.mapInfo,
      RetouchPassIndex.header,
      maps.packInfo(),
    );
    f[RetouchPassIndex.sourceIsWindow] = sourceIsWindow ? 1 : 0;
    var any = false;
    for (var k = 0; k < kMaxRetouchFaces; k++) {
      final active = slotActive(maps, u, k);
      any = any || active;
      f[RetouchPassIndex.faceInfo(k) + 1] = active ? 1 : 0;
    }
    final backdrop = retouchBackdropActive(maps, u);
    final clothes = retouchClothesActive(maps, u);
    f[RetouchPassIndex.backdropInfo + 2] = backdrop ? 1 : 0;
    final rows = u.pack();
    f
      ..[RetouchPassIndex.header] = rows[0]
      ..[RetouchPassIndex.header + 1] = any || backdrop || clothes ? 1 : 0
      ..[RetouchPassIndex.header + 2] = kSpotRamp
      ..setRange(
        RetouchPassIndex.rows,
        RetouchPassIndex.faceMaps,
        rows.sublist(kRetouchHeaderFloats),
      )
      ..setRange(
        RetouchPassIndex.faceMaps,
        kRetouchPassFloatCount,
        maps.packFaceMaps(),
      )
      ..[RetouchPassIndex.clothesParams + 2] = clothes ? 1 : 0;
    return f;
  }
}
