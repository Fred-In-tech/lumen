/// Uniforms of the GPU retouch pass `R` (`app/shaders/retouch.frag`), the
/// shader twin of `applyRetouch` (`retouch/retouch_kernel.dart`).
///
/// Layout (270 floats = `vec2` + 67 `vec4`, set in declaration order):
///
/// | floats | uniform | contents |
/// |---|---|---|
/// | 0–1 | `uSize` | pass size (px) |
/// | 2–5 | `uTile` | pass offset x, y in the source; full source w, h |
/// | 6–9 | `uMapInfo` | map grid W, H, face count, 0 (`RetouchMaps.packInfo`) |
/// | 10 + 8k | `uFaceInfo{2k}` | teeth cap L, **active**, IOD (map px), lip gloss L |
/// | 14 + 8k | `uFaceInfo{2k+1}` | lip chroma gain, lip L shift, blush a, blush b |
/// | 74–77 | `uRetouch` | face count, any active, spot ramp, 0 |
/// | 78 + 24k | `uFace{6k..6k+5}` | the face row (`RetouchUniforms.pack`) |
///
/// "active" (slot has maps and a non-identity row) replaces the "has maps"
/// float of `packInfo`, so the shader can keep untouched pixels bit-exact
/// exactly where the CPU kernel returns early.
library;

import 'dart:typed_data';

import '../retouch/blemish_types.dart';
import '../retouch/retouch_maps.dart';
import '../retouch/retouch_uniforms.dart';

const int kRetouchPassFloatCount =
    6 + kRetouchInfoFloats + kRetouchUniformFloats;

abstract final class RetouchPassIndex {
  static const size = 0;
  static const tile = 2;
  static const mapInfo = 6;
  static int faceInfo(int slot) => 10 + 8 * slot;
  static int makeupInfo(int slot) => 14 + 8 * slot;
  static const header = 6 + kRetouchInfoFloats;
  static const rows = header + kRetouchHeaderFloats;
}

abstract final class RetouchPassUniforms {
  /// True when face [slot] has maps and a non-identity row.
  static bool slotActive(RetouchMaps maps, RetouchUniforms u, int slot) =>
      !u.row(slot).isIdentity && maps.faceInSlot(slot) != null;

  /// True when the pass changes at least one pixel (otherwise skip it).
  static bool isActive(RetouchMaps maps, RetouchUniforms u) {
    if (u.isIdentity || !maps.hasFaces) return false;
    for (var k = 0; k < kMaxRetouchFaces; k++) {
      if (slotActive(maps, u, k)) return true;
    }
    return false;
  }

  /// Packs the pass uniforms for a [width]×[height] pass at ([tileX],
  /// [tileY]) of a [fullWidth]×[fullHeight] source (defaults: whole image).
  static Float32List pack(
    RetouchMaps maps,
    RetouchUniforms u, {
    required int width,
    required int height,
    double tileX = 0,
    double tileY = 0,
    double? fullWidth,
    double? fullHeight,
  }) {
    final f = Float32List(kRetouchPassFloatCount)
      ..[0] = width.toDouble()
      ..[1] = height.toDouble()
      ..[2] = tileX
      ..[3] = tileY
      ..[4] = fullWidth ?? width.toDouble()
      ..[5] = fullHeight ?? height.toDouble();
    final info = maps.packInfo();
    f.setRange(RetouchPassIndex.mapInfo, RetouchPassIndex.header, info);
    var any = false;
    for (var k = 0; k < kMaxRetouchFaces; k++) {
      final active = slotActive(maps, u, k);
      any = any || active;
      f[RetouchPassIndex.faceInfo(k) + 1] = active ? 1 : 0;
    }
    final rows = u.pack();
    f
      ..[RetouchPassIndex.header] = rows[0]
      ..[RetouchPassIndex.header + 1] = any ? 1 : 0
      ..[RetouchPassIndex.header + 2] = kSpotRamp
      ..setRange(
        RetouchPassIndex.rows,
        kRetouchPassFloatCount,
        rows.sublist(kRetouchHeaderFloats),
      );
    return f;
  }
}
