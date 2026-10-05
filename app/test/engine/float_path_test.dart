import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/engine/aux_cache.dart';
import 'package:lumen/engine/backdrop_textures.dart';
import 'package:lumen/engine/gpu_pass.dart';
import 'package:lumen/engine/hbd_capability.dart';
import 'package:lumen/engine/retouch_textures.dart';
import 'package:lumen/engine/shader_library.dart';
import 'package:lumen_core/lumen_core.dart';

import '../support/test_images.dart';
import 'backdrop_harness.dart';
import 'engine_harness.dart';
import 'float_harness.dart';
import 'retouch_harness.dart';

/// The float editing path on the GPU (docs/HIGH_BIT_DEPTH.md): storage,
/// GPU-vs-CPU parity of the float develop path (§6.3 thresholds: max ≤
/// 3/255, mean ≤ 1/255), headroom and precision, and the float pre-passes.
///
///   flutter test --enable-impeller test/engine/float_path_test.dart
///
/// Skipped (not failed) where float targets do not exist.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final scenes = TestScenes.parityScenes(128, 96);

  group('capability', () {
    tearDown(() => HbdCapability.override = null);

    test('the probe answers once and never throws', () async {
      final shaders = await ShaderLibrary.load();
      final a = await HbdCapability.probe(shaders);
      final b = await HbdCapability.probe(shaders);
      expect(a, b);
      expect(await HbdCapability.available(), a);
      result('float path available in this renderer: $a');
      expect(EngineImages.live, 0);
    });

    test('override forces the answer without touching the GPU', () async {
      final shaders = await ShaderLibrary.load();
      HbdCapability.override = false;
      expect(await HbdCapability.probe(shaders), isFalse);
      expect(await HbdCapability.available(), isFalse);
      HbdCapability.override = true;
      expect(await HbdCapability.probe(shaders), isTrue);
    });
  });

  group('storage', () {
    test('float upload and readback keep extended values exactly', () async {
      if (!await floatPathOrSkip()) return;
      final px = Float32List.fromList([
        4, -0.5, 1000, 1, //
        1e-5, 0.18, 0.5 + 1 / 65536, 1,
      ]);
      final img = await uploadFloat(px, 2, 1);
      expect(await readFloat(img), px);
      EngineImages.dispose(img);
      expect(() => uploadFloat(px, 3, 1), throwsArgumentError);
    });

    test('two float passes keep every level of a 65 536-level ramp', () async {
      if (!await floatPathOrSkip()) return;
      final shaders = await ShaderLibrary.load();
      const n = 256;
      final ramp = FloatBuffer(n, n);
      for (var i = 0; i < n * n; i++) {
        final v = i / (n * n - 1) * 2; // 0..2: half of it above white
        ramp.setPixel(i % n, i ~/ n, v, v, v);
      }
      final src = await imageFromFloat(ramp);
      final floats = DenoiseUniforms.pack(DevelopSettings.defaults, n, n);
      final a = runDenoise(shaders, floats: floats, image: src, float: true);
      final b = runDenoise(shaders, floats: floats, image: a, float: true);
      final out = await readFloat(b);
      final levels = <double>{};
      var worst = 0.0;
      for (var i = 0; i < n * n; i++) {
        levels.add(out[i * 4]);
        worst = math.max(worst, (out[i * 4] - ramp.data[i * 4]).abs());
      }
      result(
        'float chain: ${levels.length} of ${n * n} levels, max err $worst',
      );
      expect(levels.length, greaterThan(n * n * 0.99));
      expect(worst, lessThan(1e-5));
      for (final i in [src, a, b]) {
        EngineImages.dispose(i);
      }
    });
  });

  group('float develop parity (GPU vs renderReferenceFloat)', () {
    Future<void> check(
      String name,
      StageGen gen, {
      HbdProfile profile = HbdProfile.none,
      bool spatial = false,
    }) async {
      if (!await floatPathOrSkip()) return;
      final rnd = math.Random(name.hashCode & 0xffff);
      var worst = 0, meanSum = 0.0, n = 0;
      for (final scene in scenes) {
        final src = hotScene(scene);
        final aux = AuxMaps.computeFloat(src);
        for (var k = 0; k < 2; k++) {
          final s = gen(rnd);
          final gpu = await gpuRenderFloat(src, s, aux: aux, profile: profile);
          final cpu = renderReferenceFloat(
            src,
            s,
            aux: aux,
            profile: profile,
          ).toRgba();
          final d = diffStats(gpu, cpu);
          worst = math.max(worst, d.max);
          meanSum += d.mean;
          n++;
          expect(d.max, lessThanOrEqualTo(3), reason: '$name $s');
          expect(d.mean, lessThanOrEqualTo(1), reason: '$name $s');
        }
      }
      result(
        'float parity $name${profile.isNone ? '' : ' (raw profile)'}: max '
        '$worst/255, mean ${(meanSum / n).toStringAsFixed(3)}/255',
      );
      expect(spatial || worst <= 3, isTrue);
    }

    test('identity', () => check('identity', (_) => DevelopSettings.defaults));
    for (final e in pointStages.entries) {
      test(e.key, () => check(e.key, e.value));
    }
    for (final e in spatialStages.entries) {
      test('spatial ${e.key}', () => check(e.key, e.value, spatial: true));
    }
    test(
      'raw profile: shoulder and exposure',
      () => check(
        'shoulder',
        pointStages['wb+exposure']!,
        profile: HbdProfile.rawExtended,
      ),
    );
    test(
      'raw profile: shoulder and tone LUT',
      () => check(
        'shoulder tone',
        pointStages['tone lut']!,
        profile: HbdProfile.rawExtended,
      ),
    );
    test(
      'raw profile: highlights and shadows with the extra range',
      () => check(
        'shoulder highlights',
        spatialStages['shadows+highlights']!,
        profile: HbdProfile.rawExtended,
        spatial: true,
      ),
    );
    test('all point ops, 3 scenes x 6 random settings', () async {
      if (!await floatPathOrSkip()) return;
      final rnd = math.Random(2027);
      var worst = 0;
      for (final scene in scenes.take(3)) {
        final src = hotScene(scene);
        for (var k = 0; k < 6; k++) {
          final s = randomPointSettings(rnd);
          final d = diffStats(
            await gpuRenderFloat(src, s, profile: HbdProfile.rawExtended),
            renderReferenceFloat(
              src,
              s,
              profile: HbdProfile.rawExtended,
            ).toRgba(),
          );
          worst = math.max(worst, d.max);
          expect(d.max, lessThanOrEqualTo(3), reason: '$s');
          expect(d.mean, lessThanOrEqualTo(1), reason: '$s');
        }
      }
      result('float parity all point ops: max $worst/255');
      expect(EngineImages.live, 0);
    });

    test('a float32 develop target holds the unquantised output', () async {
      if (!await floatPathOrSkip()) return;
      final shaders = await ShaderLibrary.load();
      final src = hotScene(scenes.first);
      final s = DevelopSettings.defaults.withValue(P.exposure, -1.3);
      final cpu = renderReferenceFloat(src, s);
      final image = await imageFromFloat(src);
      final aux = await AuxTextures.fromMaps(AuxMaps.neutral());
      final lut = await uploadRgba(ToneLut.bake(s).toRgba(), kToneLutSize, 4);
      final out = runDevelop(
        shaders,
        floats: DevelopUniforms.pack(
          s,
          DevelopContext(
            outWidth: src.width,
            outHeight: src.height,
            sourceWidth: src.width,
            sourceHeight: src.height,
            auxWidth: 1,
            auxHeight: 1,
          ),
        ),
        source: image,
        auxA: aux.auxA,
        auxB: aux.auxB,
        lut: lut,
        width: src.width,
        height: src.height,
        float: true,
      );
      final gpu = await readFloat(out);
      var worst = 0.0;
      for (var i = 0; i < gpu.length; i++) {
        worst = math.max(worst, (gpu[i] - cpu.data[i]).abs());
      }
      result(
        'float develop target vs CPU: max |d| ${worst.toStringAsFixed(6)}',
      );
      // The 1024-entry tone LUT is 16-bit packed: a float tolerance.
      expect(worst, lessThan(2e-3));
      for (final i in [out, lut, image]) {
        EngineImages.dispose(i);
      }
      aux.dispose();
    });
  });

  group('8-bit-equivalent float sources', () {
    test('render like the 8-bit graph (within 1/255)', () async {
      if (!await floatPathOrSkip()) return;
      final rnd = math.Random(11);
      for (final scene in scenes.take(3)) {
        final aux = AuxMaps.compute(scene);
        for (final gen in [
          pointStages['wb+exposure']!,
          pointStages['tone lut']!,
          spatialStages['shadows+highlights']!,
        ]) {
          final s = gen(rnd);
          final bytes = await gpuRender(scene, s, aux: aux);
          final float = await gpuRenderFloat(
            FloatBuffer.fromRgba(scene),
            s,
            aux: aux,
          );
          expect(diffStats(float, bytes).max, lessThanOrEqualTo(1));
        }
      }
    });

    test('with denoise the float chain only differs by the 8-bit rounding '
        'the byte chain adds between passes', () async {
      if (!await floatPathOrSkip()) return;
      final scene = TestScenes.noisyFlat(96, 96);
      final s = DevelopSettings.defaults.withValues({
        P.noiseLuminance: 40,
        P.exposure: 0.7,
        P.contrast: 30,
      });
      final d = diffStats(
        await gpuRenderFloat(FloatBuffer.fromRgba(scene), s),
        await gpuRender(scene, s),
      );
      result(
        'float vs byte chain with denoise: max ${d.max}/255, mean '
        '${d.mean.toStringAsFixed(3)}/255',
      );
      expect(d.max, lessThanOrEqualTo(3));
      expect(d.mean, lessThanOrEqualTo(0.6));
    });
  });

  group('headroom and precision on the GPU', () {
    final top = linearToSrgbExtended(4);

    test('exposure -2 EV recovers a ramp above white without banding; the '
        '8-bit rendition of it stays flat', () async {
      if (!await floatPathOrSkip()) return;
      final hot = floatRamp(1024, 4, 1, top);
      final s = DevelopSettings.defaults.withValue(P.exposure, -2);
      final float = await gpuRenderFloat(hot, s);
      final bytes = await gpuRender(hot.toRgba(), s);
      final lf = rowLevels(float, 2), lb = rowLevels(bytes, 2);
      result('ramp 1x..4x white at -2 EV: float $lf levels, 8-bit $lb levels');
      expect(lb, 1);
      expect(lf, greaterThan(110));
      for (var x = 1; x < 1024; x++) {
        expect(float.g(x, 2), greaterThanOrEqualTo(float.g(x - 1, 2)));
      }
      expect(float.g(1023, 2), greaterThan(250));
    });

    test('Highlights -100 brings back detail above white', () async {
      if (!await floatPathOrSkip()) return;
      final wide = floatRamp(512, 16, 0.6, top);
      final s = DevelopSettings.defaults.withValue(P.highlights, -100);
      final float = await gpuRenderFloat(
        wide,
        s,
        profile: HbdProfile.rawExtended,
      );
      final bytes = await gpuRender(wide.toRgba(), s);
      final lf = rowLevels(float, 8, 256), lb = rowLevels(bytes, 8, 256);
      result(
        'ramp to 4x white at Highlights -100: float $lf levels in the '
        'top half, 8-bit $lb',
      );
      expect(lb, lessThanOrEqualTo(3));
      expect(lf, greaterThan(40));
      expect(float.g(511, 8), lessThan(255));
    });

    test('+3 EV keeps far more shadow levels than the 8-bit path', () async {
      if (!await floatPathOrSkip()) return;
      final dark = floatRamp(1024, 4, 0, 0.02);
      final s = DevelopSettings.defaults.withValue(P.exposure, 3);
      final float = await gpuRenderFloat(dark, s);
      final bytes = await gpuRender(dark.toRgba(), s);
      final lf = rowLevels(float, 2), lb = rowLevels(bytes, 2);
      result('darkest 2 % at +3 EV: float $lf levels, 8-bit $lb levels');
      expect(lb, lessThanOrEqualTo(7));
      expect(lf, greaterThan(4 * lb));
    });
  });

  group('float pre-passes', () {
    test('denoise keeps highlights above white and matches the 8-bit pass '
        'on 8-bit data', () async {
      if (!await floatPathOrSkip()) return;
      final shaders = await ShaderLibrary.load();
      final scene = TestScenes.noisyFlat(96, 96);
      final s = DevelopSettings.defaults.withValues({
        P.noiseLuminance: 60,
        P.noiseColor: 50,
      });
      final floats = DenoiseUniforms.pack(s, 96, 96);
      final src8 = await imageFromBuffer(scene);
      final srcF = await imageFromFloat(FloatBuffer.fromRgba(scene));
      final out8 = runDenoise(shaders, floats: floats, image: src8);
      final outF = runDenoise(
        shaders,
        floats: floats,
        image: srcF,
        float: true,
      );
      final d = diffStats(
        (await floatFromImage(outF)).toRgba(),
        await bufferFromImage(out8),
      );
      expect(d.max, lessThanOrEqualTo(1));
      // The same scene three times brighter: still three times brighter.
      final hot = FloatBuffer.fromRgba(scene);
      for (var i = 0; i < hot.data.length; i++) {
        if (i % 4 != 3) hot.data[i] *= 3;
      }
      final srcH = await imageFromFloat(hot);
      final outH = runDenoise(
        shaders,
        floats: floats,
        image: srcH,
        float: true,
      );
      final h = await readFloat(outH);
      var peak = 0.0;
      for (var i = 0; i < h.length; i += 4) {
        peak = math.max(peak, h[i]);
      }
      result('float denoise peak ${peak.toStringAsFixed(3)} (input x3)');
      expect(peak, greaterThan(1.2));
      for (final i in [src8, srcF, out8, outF, srcH, outH]) {
        EngineImages.dispose(i);
      }
    });

    test('retouch: 8-bit data gives the 8-bit result; untouched highlights '
        'pass through', () async {
      if (!await floatPathOrSkip()) return;
      final shaders = await ShaderLibrary.load();
      final one = onePortrait();
      final u = RetouchUniforms.fromSettings(
        portraitOf({'skin.softening': 70, 'skin.even': 50}),
        one.p.analysis,
      );
      final expected = await gpuRetouch(one.p.image, one.maps, u);
      final hot = FloatBuffer.fromRgba(one.p.image);
      // A highlight patch in a corner (outside every face).
      for (var y = 0; y < 8; y++) {
        for (var x = 0; x < 8; x++) {
          hot.setPixel(x, y, 2.5, 2.25, 2);
        }
      }
      final src = await imageFromFloat(hot);
      final textures = await RetouchTextures.upload(one.maps);
      final out = runRetouchPass(
        shaders,
        source: src,
        textures: textures,
        uniforms: u,
        float: true,
      )!;
      final got = await floatFromImage(out);
      expect(got.data.sublist(0, 3), [2.5, 2.25, 2]);
      final bytes = got.toRgba();
      var worst = 0, changed = 0;
      for (var y = 8; y < bytes.height; y++) {
        for (var x = 0; x < bytes.width; x++) {
          final o = bytes.offset(x, y);
          for (var c = 0; c < 3; c++) {
            worst = math.max(
              worst,
              (bytes.data[o + c] - expected.data[o + c]).abs(),
            );
            if (expected.data[o + c] != one.p.image.data[o + c]) changed++;
          }
        }
      }
      result(
        'float retouch vs 8-bit retouch: max $worst/255, $changed '
        'changed channels',
      );
      expect(changed, greaterThan(1000));
      expect(worst, lessThanOrEqualTo(1));
      EngineImages.dispose(out);
      EngineImages.dispose(src);
      textures.dispose();
    });

    test('backdrop: 8-bit data gives the 8-bit result; subject highlights '
        'keep their range', () async {
      if (!await floatPathOrSkip()) return;
      final shaders = await ShaderLibrary.load();
      final scene = SwapScene.make();
      final base = BackdropBase.build(scene.image, people: scene.people);
      const b = BackdropChange(mode: BackdropMode.color, spill: 60);
      final assets = BackdropAssets.build(base, b);
      final expected = await gpuBackdrop(scene.image, assets, b);
      final hot = FloatBuffer.fromRgba(scene.image);
      final cx = scene.cx.floor(), cy = scene.cy.floor();
      hot.setPixel(cx, cy, 3, 2.5, 2.25);
      final src = await imageFromFloat(hot);
      final textures = await BackdropTextures.upload(assets);
      final out = runBackdropPass(
        shaders,
        source: src,
        textures: textures,
        change: b,
        float: true,
      )!;
      final got = await floatFromImage(out);
      final o = got.offset(cx, cy);
      expect(got.data.sublist(o, o + 3), [3, 2.5, 2.25]);
      got.setPixel(cx, cy, 0, 0, 0);
      final want = expected.copy()..setPixel(cx, cy, 0, 0, 0);
      final d = diffStats(got.toRgba(), want);
      result('float backdrop vs 8-bit backdrop: max ${d.max}/255');
      expect(d.max, lessThanOrEqualTo(1));
      EngineImages.dispose(out);
      EngineImages.dispose(src);
      textures.dispose();
    });

    test(
      'heal overlay: the GPU composite equals composeOverlayFloat',
      () async {
        if (!await floatPathOrSkip()) return;
        final patch = RgbaBuffer(40, 30);
        for (var y = 0; y < 30; y++) {
          for (var x = 0; x < 40; x++) {
            final a = (255 * (1 - ((x - 20).abs() / 20))).round();
            patch.setPixel(x, y, 200, 90, 30, a);
          }
        }
        final ops = [
          const HealOp(
            id: 'a',
            bbox: PixelBox(30, 20, 40, 30),
            srcWidth: 128,
            srcHeight: 96,
            patch: 'retouch/a.png',
          ),
        ];
        final overlay = composeHealOverlay(
          128,
          96,
          ops,
          MapPatchLookup({'retouch/a.png': patch}),
        );
        final src = hotScene(scenes.first, peak: 2.5);
        final cpu = composeOverlayFloat(src, overlay);
        final base = await imageFromFloat(src);
        final over = await imageFromBuffer(overlay);
        final out = compositeOverlay(base, over);
        final gpu = await readFloat(out);
        var worst = 0.0;
        for (var i = 0; i < gpu.length; i++) {
          worst = math.max(worst, (gpu[i] - cpu.data[i]).abs());
        }
        result('heal overlay GPU vs CPU: max |d| ${worst.toStringAsFixed(6)}');
        expect(worst, lessThan(1.5 / 255));
        // Outside the patch the float values are untouched.
        expect(gpu[0], src.data[0]);
        for (final i in [base, over, out]) {
          EngineImages.dispose(i);
        }
        expect(EngineImages.live, 0);
      },
    );
  });
}
