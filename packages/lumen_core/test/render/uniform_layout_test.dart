import 'dart:math' as math;

import 'package:lumen_core/lumen_core.dart';
import 'package:test/test.dart';

const _ctx = DevelopContext(
  outWidth: 300,
  outHeight: 200,
  sourceWidth: 300,
  sourceHeight: 200,
  auxWidth: 150,
  auxHeight: 100,
);

void main() {
  group('DevelopUniforms', () {
    test('packs exactly kDevelopFloatCount (198) floats', () {
      expect(kDevelopFloatCount, 198);
      expect(DevelopUniforms.pack(DevelopSettings.defaults, _ctx).length, 198);
    });

    test('index table matches PLAN.md §1.6 and is contiguous', () {
      final expected = {
        'uOutSize': (0, 2),
        'uTile': (2, 4),
        'uCrop': (6, 4),
        'uGeom': (10, 4),
        'uSrc': (14, 4),
        'uWbExp': (18, 4),
        'uLocal': (22, 4),
        'uHaze': (26, 4),
        'uColor': (30, 4),
        'uHslHue0': (34, 4),
        'uHslHue1': (38, 4),
        'uHslSat0': (42, 4),
        'uHslSat1': (46, 4),
        'uHslLum0': (50, 4),
        'uHslLum1': (54, 4),
        'uGradeShadows': (58, 4),
        'uGradeMidtones': (62, 4),
        'uGradeHighlights': (66, 4),
        'uGradeGlobal': (70, 4),
        'uGradeParams': (74, 4),
        'uBwMix0': (78, 4),
        'uBwMix1': (82, 4),
        'uVignette': (86, 4),
        'uVignette2': (90, 4),
        'uMaskGrid': (94, 4),
        for (var i = 0; i < 8; i++) ...{
          'uMask${i}A': (98 + 12 * i, 4),
          'uMask${i}B': (102 + 12 * i, 4),
          'uMask${i}C': (106 + 12 * i, 4),
        },
        'uWarpInfo': (194, 4),
      };
      var next = 0;
      for (final u in DevelopUniforms.table) {
        expect(expected[u.name], (u.index, u.length), reason: u.name);
        expect(u.index, next, reason: '${u.name} must follow the previous');
        next += u.length;
      }
      expect(next, kDevelopFloatCount);
      expect(DevelopUniforms.table.length, expected.length);
    });

    test('defaults pack to neutral values', () {
      final f = DevelopUniforms.pack(DevelopSettings.defaults, _ctx);
      expect(f.sublist(0, 2), [300, 200]);
      expect(f.sublist(2, 6), [0, 0, 300, 200]);
      expect(f.sublist(6, 10), [0, 0, 1, 1]);
      expect(f.sublist(10, 14), [0, 0, 0, 0]);
      expect(f.sublist(14, 18), [300, 200, 150, 100]);
      expect(f.sublist(18, 22), [1, 1, 1, 1]);
      expect(f.sublist(22, 26), [0, 0, 0, 0]);
      expect(f[26], 0);
      expect(f.sublist(30, 34), [0, 0, 0, 0]);
      expect(f.sublist(34, 74).every((v) => v == 0), isTrue);
      expect(f.sublist(74, 78), [0.5, 0, 0, 0]);
      expect(f.sublist(78, 86).every((v) => v == 0), isTrue);
      expect(f.sublist(86, 90), [0, 0.5, 0, 0.5]);
      expect(f[90], 0);
      expect(f[91], closeTo(1.5, 1e-6));
      expect(f[92], 0);
      expect(f.sublist(94, 98), [1, 1, 0, 0]);
      expect(f.sublist(98, 194).every((v) => v == 0), isTrue);
      expect(f.sublist(194, 198), [1, 1, 0, 0]); // no warp
    });

    test('maps slider units to shader units', () {
      final s = DevelopSettings.defaults
          .withValues({
            P.exposure: 1,
            P.temp: 100,
            P.highlights: -50,
            P.dehaze: 40,
            P.vibrance: 20,
            P.hsl(HslBand.blue, HslChannel.sat): -60,
            P.bw(HslBand.magenta): 30,
            P.grade(GradeZone.shadows, 'hue'): 90,
            P.grade(GradeZone.shadows, 'sat'): 100,
            P.grade(GradeZone.shadows, 'lum'): -40,
            P.vignetteAmount: -70,
          })
          .copyWith(
            treatment: Treatment.bw,
            geometry: Geometry.none.copyWith(
              angle: 10,
              rotate90: 1,
              flipH: true,
            ),
          );
      final f = DevelopUniforms.pack(
        s,
        const DevelopContext(
          outWidth: 300,
          outHeight: 200,
          sourceWidth: 300,
          sourceHeight: 200,
          auxWidth: 150,
          auxHeight: 100,
          airlight: Rgb(0.9, 0.8, 0.7),
          showClipping: true,
        ),
      );
      expect(f[DevelopIndex.wbExp + 3], 2);
      expect(
        f[DevelopIndex.wbExp] / f[DevelopIndex.wbExp + 2],
        closeTo(2, 1e-6),
      );
      expect(f[DevelopIndex.local], closeTo(-0.5, 1e-7));
      expect(f[DevelopIndex.haze], closeTo(0.4, 1e-7));
      expect(f[DevelopIndex.haze + 1], closeTo(0.9, 1e-7));
      expect(f[DevelopIndex.color], closeTo(0.2, 1e-7));
      expect(f[DevelopIndex.color + 2], 1);
      expect(f[DevelopIndex.hslSat + 5], closeTo(-0.6, 1e-7));
      expect(f[DevelopIndex.bwMix + 7], closeTo(0.3, 1e-7));
      expect(f[DevelopIndex.gradeShadows], closeTo(0, 1e-7));
      expect(f[DevelopIndex.gradeShadows + 1], closeTo(kGradeMaxChroma, 1e-7));
      expect(f[DevelopIndex.gradeShadows + 2], closeTo(-0.4, 1e-7));
      expect(f[DevelopIndex.geom], closeTo(10 * math.pi / 180, 1e-7));
      expect(f.sublist(DevelopIndex.geom + 1, DevelopIndex.geom + 4), [
        1,
        1,
        0,
      ]);
      expect(f[DevelopIndex.vignette], closeTo(-0.7, 1e-7));
      expect(f[DevelopIndex.vignette2 + 2], 1);
    });

    test('curvesActive flag follows the R/G/B curves', () {
      final s = DevelopSettings.defaults.copyWith(
        curves: CurveSet.identity.withChannel(
          CurveChannel.green,
          const ToneCurve([CurvePoint(0, 10), CurvePoint(255, 255)]),
        ),
      );
      expect(DevelopUniforms.pack(s, _ctx)[DevelopIndex.color + 3], 1);
    });

    test('tile context is honored', () {
      final f = DevelopUniforms.pack(
        DevelopSettings.defaults,
        const DevelopContext(
          outWidth: 64,
          outHeight: 32,
          tileX: 128,
          tileY: 96,
          fullWidth: 1000,
          fullHeight: 500,
          sourceWidth: 1000,
          sourceHeight: 500,
          auxWidth: 512,
          auxHeight: 256,
        ),
      );
      expect(f.sublist(0, 6), [64, 32, 128, 96, 1000, 500]);
      expect(f[DevelopIndex.vignette2 + 1], 2);
    });
  });

  group('mask uniforms', () {
    LocalMask mask(String id, Map<String, double> adj) =>
        LocalMask(id: id, name: id, kind: MaskKind.radial, adjustments: adj);

    test('pack the 12 local params per mask in kLocalParams order', () {
      final s = DevelopSettings.defaults.copyWith(
        masks: [
          mask('a', {P.exposure: 1.5, P.temp: 40, P.blacks: -20}),
          mask('b', {}),
          mask('c', {P.clarity: 60, P.dehaze: -10, P.saturation: 25}),
        ],
      );
      final f = DevelopUniforms.pack(
        s,
        const DevelopContext(
          outWidth: 10,
          outHeight: 10,
          sourceWidth: 10,
          sourceHeight: 10,
          auxWidth: 1,
          auxHeight: 1,
          maskWidth: 640,
          maskHeight: 480,
        ),
      );
      expect(f.sublist(DevelopIndex.maskGrid, DevelopIndex.maskGrid + 4), [
        640,
        480,
        3,
        0,
      ]);
      final a = DevelopIndex.mask(0);
      expect(f[a], 1.5); // exposure in EV
      expect(f[a + 1], closeTo(0.4, 1e-7)); // temp
      expect(f[a + 11], closeTo(-0.2, 1e-7)); // blacks
      expect(
        f
            .sublist(DevelopIndex.mask(1), DevelopIndex.mask(2))
            .every((v) => v == 0),
        isTrue,
      );
      final c = DevelopIndex.mask(2);
      expect(f[c + 3], closeTo(0.25, 1e-7)); // saturation
      expect(f[c + 6], closeTo(0.6, 1e-7)); // clarity
      expect(f[c + 8], closeTo(-0.1, 1e-7)); // dehaze
    });

    test('masks without adjustments are inactive (count 0)', () {
      final s = DevelopSettings.defaults.copyWith(masks: [mask('a', {})]);
      final f = DevelopUniforms.pack(s, _ctx);
      expect(f[DevelopIndex.maskGrid + 2], 0);
    });

    test('only the first 8 masks are packed', () {
      final s = DevelopSettings.defaults.copyWith(
        masks: [
          for (var i = 0; i < 10; i++) mask('m$i', {P.exposure: 0.1 * (i + 1)}),
        ],
      );
      final f = DevelopUniforms.pack(s, _ctx);
      expect(f[DevelopIndex.maskGrid + 2], 8);
      expect(f[DevelopIndex.mask(7)], closeTo(0.8, 1e-6));
      expect(f.length, kDevelopFloatCount);
    });
  });

  group('FinishUniforms', () {
    test('packs kFinishFloatCount floats with neutral defaults', () {
      final f = FinishUniforms.pack(
        DevelopSettings.defaults,
        const FinishContext(width: 100, height: 50, seed: 3),
      );
      expect(f.length, kFinishFloatCount);
      expect(f.sublist(0, 6), [100, 50, 0, 0, 100, 50]);
      expect(f[FinishIndex.sharpen], 0);
      expect(f[FinishIndex.sharpen + 1], 1);
      expect(f[FinishIndex.grain], 0);
      expect(f[FinishIndex.grain + 3], 3);
      expect(FinishUniforms.isIdentity(DevelopSettings.defaults), isTrue);
    });

    test('sharpen and grain map to shader units', () {
      final s = DevelopSettings.defaults.withValues({
        P.sharpenAmount: 150,
        P.sharpenRadius: 2,
        P.sharpenDetail: 50,
        P.grainAmount: 40,
      });
      final f = FinishUniforms.pack(
        s,
        const FinishContext(width: 10, height: 10),
      );
      expect(f[FinishIndex.sharpen], closeTo(1.5, 1e-7));
      expect(f[FinishIndex.sharpen + 1], 2);
      expect(f[FinishIndex.sharpen + 2], closeTo(0.5, 1e-7));
      expect(f[FinishIndex.grain], closeTo(0.4, 1e-7));
      expect(FinishUniforms.isIdentity(s), isFalse);
    });

    test('grain seed is a stable function of the asset id', () {
      expect(FinishUniforms.seedFor('abc'), FinishUniforms.seedFor('abc'));
      expect(
        FinishUniforms.seedFor('abc'),
        isNot(FinishUniforms.seedFor('abd')),
      );
      expect(FinishUniforms.seedFor('abc'), inInclusiveRange(0, 1000));
    });
  });

  group('DenoiseUniforms', () {
    test('packs strengths and identity check', () {
      final s = DevelopSettings.defaults.withValue(P.noiseLuminance, 60);
      final f = DenoiseUniforms.pack(s, 20, 10);
      expect(f.length, kDenoiseFloatCount);
      expect(f.sublist(0, 4), [20, 10, closeTo(0.6, 1e-7), 0]);
      expect(DenoiseUniforms.isIdentity(s), isFalse);
      expect(DenoiseUniforms.isIdentity(DevelopSettings.defaults), isTrue);
    });
  });

  test('uWarpInfo carries the warp grid, range and the enabled flag', () {
    final f = DevelopUniforms.pack(
      DevelopSettings.defaults,
      const DevelopContext(
        outWidth: 10,
        outHeight: 10,
        sourceWidth: 10,
        sourceHeight: 10,
        auxWidth: 1,
        auxHeight: 1,
        warpWidth: 512,
        warpHeight: 384,
        warpRange: 0.03,
      ),
    );
    expect(f.sublist(DevelopIndex.warpInfo, DevelopIndex.warpInfo + 4), [
      512,
      384,
      closeTo(0.03, 1e-7),
      1,
    ]);
  });
}
