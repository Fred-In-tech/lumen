import 'dart:typed_data';

import 'package:lumen_core/lumen_core.dart';
import 'package:test/test.dart';

RetouchMaps _maps({List<int> slots = const [0, 2]}) {
  const w = 4, h = 2;
  Uint8List tex(int width) =>
      Uint8List(width * h * 4)..fillRange(0, width * h * 4, 255);
  return RetouchMaps(
    width: w,
    height: h,
    b1: tex(w),
    b2: tex(w),
    b3: tex(w),
    bh: tex(2 * w),
    regionA: tex(2 * w),
    regionB: tex(2 * w),
    faces: [
      for (final s in slots)
        RetouchFaceInfo(
          slot: s,
          faceId: 'f$s',
          rect: const MapRect(0, 0, 4, 2),
          iod: 30.0 + s,
          teethCapL: 0.8 + s / 100,
          skinMeanL: 0.6,
        ),
    ],
  );
}

void main() {
  test('packs size, tile, map info, face info and rows (206 floats)', () {
    const smooth = FaceRetouchParams(smooth: 0.5);
    const u = RetouchUniforms([smooth, FaceRetouchParams.identity, smooth]);
    final f = RetouchPassUniforms.pack(
      _maps(),
      u,
      width: 64,
      height: 32,
      tileX: 128,
      tileY: 96,
      fullWidth: 1000,
      fullHeight: 500,
    );
    expect(kRetouchPassFloatCount, 206);
    expect(f.length, kRetouchPassFloatCount);
    expect(f.sublist(0, 6), [64, 32, 128, 96, 1000, 500]);
    expect(f.sublist(6, 9), [4, 2, 2]); // map W, H, face count
    // uFaceInfo[k] = teethCapL, has maps, IOD, active.
    final i0 = RetouchPassIndex.faceInfo(0);
    expect(f[i0], closeTo(0.8, 1e-6));
    expect(f.sublist(i0 + 1, i0 + 4), [1, 30, 1]);
    final i1 = RetouchPassIndex.faceInfo(1);
    expect(f.sublist(i1 + 1, i1 + 4), [0, 0, 0]); // no maps, identity row
    final i2 = RetouchPassIndex.faceInfo(2);
    expect(f[i2 + 3], 1);
    // uRetouch: face count, any active, spot ramp.
    expect(f.sublist(RetouchPassIndex.header, RetouchPassIndex.header + 3), [
      3,
      1,
      closeTo(kSpotRamp, 1e-7),
    ]);
    expect(
      f.sublist(
        RetouchPassIndex.rows,
        RetouchPassIndex.rows + kRetouchUniformFloats - 4,
      ),
      u.pack().sublist(4),
    );
  });

  test('a non-identity row without maps is inactive', () {
    const u = RetouchUniforms([
      FaceRetouchParams.identity,
      FaceRetouchParams(shine: 1),
    ]);
    final f = RetouchPassUniforms.pack(
      _maps(slots: [0]),
      u,
      width: 8,
      height: 8,
    );
    expect(f[RetouchPassIndex.faceInfo(1) + 3], 0);
    expect(f[RetouchPassIndex.header + 1], 0);
    expect(RetouchPassUniforms.isActive(_maps(slots: [0]), u), isFalse);
    expect(RetouchPassUniforms.isActive(_maps(slots: [1]), u), isTrue);
  });

  test('defaults: full size = pass size, identity is inactive', () {
    final f = RetouchPassUniforms.pack(
      RetouchMaps.empty(),
      RetouchUniforms.identity,
      width: 10,
      height: 20,
    );
    expect(f.sublist(0, 6), [10, 20, 0, 0, 10, 20]);
    expect(f[RetouchPassIndex.header + 1], 0);
  });
}
