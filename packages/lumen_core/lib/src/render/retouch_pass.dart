/// Uniforms of the GPU retouch pass `R` (`app/shaders/retouch.frag`), the
/// shader twin of `applyRetouch` (`retouch/retouch_kernel.dart`).
///
/// Layout (206 floats = `vec2` + 51 `vec4`, set in declaration order):
///
/// | floats | uniform | contents |
/// |---|---|---|
/// | 0–1 | `uSize` | pass size (px) |
/// | 2–5 | `uTile` | pass offset x, y in the source; full source w, h |
/// | 6–9 | `uMapInfo` | map grid W, H, face count, 0 (`RetouchMaps.packInfo`) |
/// | 10 + 4k | `uFaceInfo{k}` | teeth cap L, has maps, IOD (map px), **active** |
/// | 42–45 | `uRetouch` | face count, any active, spot ramp, 0 |
/// | 46 + 20k | `uFace{5k..5k+4}` | the face row (`RetouchUniforms.pack`) |
///
/// "active" (slot has maps and a non-identity row) replaces the spare 4th
/// float of `packInfo`, so the shader can keep untouched pixels bit-exact
/// exactly where the CPU kernel returns early.
library;

import 'dart:typed_data';

import '../retouch/blemish_types.dart';
import '../retouch/retouch_maps.dart';
import '../retouch/retouch_uniforms.dart';

const int kRetouchPassFloatCount = 206;

abstract final class RetouchPassIndex {
  static const size = 0;
  static const tile = 2;
  static const mapInfo = 6;
  static int faceInfo(int slot) => 10 + 4 * slot;
  static const header = 42;
  static const rows = 46;
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
      f[RetouchPassIndex.faceInfo(k) + 3] = active ? 1 : 0;
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
