import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/engine/gpu_pass.dart';
import 'package:lumen/engine/shader_library.dart';
import 'package:lumen_core/lumen_core.dart';

import '../support/test_images.dart';

/// PLAN.md §0.2 spikes S1 (local #include) and S4 (packed exactness).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('S1: shaders using #include "lib/common.glsl" load', () async {
    final lib = await ShaderLibrary.load();
    expect(lib.develop, isNotNull);
    expect(lib.finish, isNotNull);
    expect(lib.denoise, isNotNull);
  });

  test('develop.frag exposes exactly kDevelopFloatCount floats', () async {
    final lib = await ShaderLibrary.load();
    final s = lib.develop.fragmentShader();
    s.setFloat(kDevelopFloatCount - 1, 0);
    expect(() => s.setFloat(kDevelopFloatCount, 0), throwsA(anything));
    s.dispose();
    final f = lib.finish.fragmentShader();
    f.setFloat(kFinishFloatCount - 1, 0);
    expect(() => f.setFloat(kFinishFloatCount, 0), throwsA(anything));
    f.dispose();
    final d = lib.denoise.fragmentShader();
    d.setFloat(kDenoiseFloatCount - 1, 0);
    expect(() => d.setFloat(kDenoiseFloatCount, 0), throwsA(anything));
    d.dispose();
  });

  test('S4: packed 16-bit texels upload and read back exactly', () async {
    // Every high byte and a sweep of low bytes, A = 255.
    final values = Float64List.fromList([
      for (var i = 0; i < 1024; i++) i / 1023,
    ]);
    final bytes = packPlane16(values);
    final img = await uploadRgba(bytes, 1024, 1);
    final back = await readRgba(img);
    expect(back, bytes);
    EngineImages.dispose(img);
  });

  test(
    'S4: LUT texture sampled at texel centers via the develop pass',
    () async {
      // A strong curve makes the LUT path visible: GPU must match the CPU
      // reference within 1/255 on a full 0..255 ramp.
      final lib = await ShaderLibrary.load();
      final ramp = RgbaBuffer(256, 4);
      for (var x = 0; x < 256; x++) {
        for (var y = 0; y < 4; y++) {
          ramp.setPixel(x, y, x, x, x);
        }
      }
      final s = DevelopSettings.defaults.withValues({
        P.contrast: 80,
        P.blacks: -40,
      });
      final lut = ToneLut.bake(s);
      final src = await imageFromBuffer(ramp);
      final lutImg = await uploadRgba(lut.toRgba(), kToneLutSize, kToneLutRows);
      final neutral = AuxMaps.neutral();
      final auxA = await uploadRgba(neutral.auxA, 1, 1);
      final auxB = await uploadRgba(neutral.auxB, 1, 1);
      final out = runDevelop(
        lib,
        floats: DevelopUniforms.pack(
          s,
          const DevelopContext(
            outWidth: 256,
            outHeight: 4,
            sourceWidth: 256,
            sourceHeight: 4,
            auxWidth: 1,
            auxHeight: 1,
          ),
        ),
        source: src,
        auxA: auxA,
        auxB: auxB,
        lut: lutImg,
        width: 256,
        height: 4,
      );
      final gpu = await bufferFromImage(out);
      final cpu = renderReference(ramp, s, aux: neutral);
      final d = diffStats(gpu, cpu);
      expect(d.max, lessThanOrEqualTo(1), reason: 'mean ${d.mean}');
      for (final i in [src, lutImg, auxA, auxB, out]) {
        EngineImages.dispose(i);
      }
      expect(EngineImages.live, 0);
    },
  );

  test('render targets are 8-bit RGBA (dontCare format)', () async {
    final img = await uploadRgba(Uint8List.fromList([1, 2, 3, 255]), 1, 1);
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawImage(img, ui.Offset.zero, ui.Paint());
    final pic = recorder.endRecording();
    final copy = pic.toImageSync(1, 1);
    expect(await readRgba(copy), [1, 2, 3, 255]);
    copy.dispose();
    pic.dispose();
    EngineImages.dispose(img);
  });
}
