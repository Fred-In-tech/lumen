import 'dart:math' as math;
import 'dart:typed_data';

import 'package:lumen_core/lumen_core.dart';
import 'package:test/test.dart';

import 'support/warp_faces.dart';

const _w = 800, _h = 600;
final _one = synthAnalysis(_w, _h, [face('a', 400, 250, 120)]);

WarpField _build(Map<String, double> values, {FaceAnalysis? faces}) =>
    buildWarpField(
      WarpRequest(
        sourceWidth: _w,
        sourceHeight: _h,
        faces: faces ?? _one,
        portrait: shapes(values),
      ),
    );

/// Displacement in source pixels at image pixel ([x], [y]).
(double, double) _dpx(WarpField f, double x, double y) {
  final (du, dv) = f.sample(x / _w, y / _h);
  return (du * _w, dv * _h);
}

void main() {
  group('WarpField', () {
    test('identity: no edits give the 1x1 identity field', () {
      final f = _build({});
      expect(f.isIdentity, isTrue);
      expect(f.sample(0.3, 0.7), (0.0, 0.0));
      expect(
        buildWarpField(const WarpRequest(sourceWidth: 10, sourceHeight: 10))
            .isIdentity,
        isTrue,
      );
    });

    test('grid is at most kWarpLongEdge, same aspect as the source', () {
      final f = _build({PortraitIds.faceWidth: 50});
      expect(math.max(f.width, f.height), kWarpLongEdge);
      expect(f.width / f.height, closeTo(_w / _h, 0.01));
    });

    test('packing is 16-bit exact: zero stays exactly zero', () {
      final dx = Float32List(4)..[1] = 0.01;
      final dy = Float32List(4)..[2] = -0.02;
      final f = WarpField(2, 2, dx, dy);
      final rgba = f.packRgba();
      expect(rgba.length, 2 * 2 * 2 * 4);
      for (var i = 3; i < rgba.length; i += 4) {
        expect(rgba[i], 255);
      }
      // Texel centres return the quantized values; texel 0 is exactly 0.
      expect(f.sample(0.25, 0.25), (0.0, 0.0));
      expect(f.sample(0.75, 0.25).$1, closeTo(0.01, 2 * f.range / 32767));
      expect(f.sample(0.25, 0.75).$2, closeTo(-0.02, 2 * f.range / 32767));
      expect(f.range, greaterThanOrEqualTo(0.02));
    });
  });

  group('face reshape', () {
    test('zero outside the feather ring, exactly', () {
      final f = _build({PortraitIds.faceWidth: 100, PortraitIds.chin: 100});
      expect(f.isIdentity, isFalse);
      // Far corners and a point 2.5 face radii away.
      for (final (x, y) in [
        (5.0, 5.0),
        (795.0, 595.0),
        (40.0, 250.0),
        (760.0, 260.0),
      ]) {
        expect(_dpx(f, x, y), (0.0, 0.0), reason: '($x, $y)');
      }
    });

    test('face width +100 moves the jaw outward, -100 inward', () {
      final wide = _build({PortraitIds.faceWidth: 100});
      final slim = _build({PortraitIds.faceWidth: -100});
      // Image-left jaw edge (subject's right) around local (-1.0, 0.9).
      const x = 400 - 1.05 * 120, y = 250 + 0.9 * 120;
      // Backward map: a wider face samples from closer to the axis.
      expect(_dpx(wide, x, y).$1, greaterThan(1));
      expect(_dpx(slim, x, y).$1, lessThan(-1));
    });

    test('effect grows monotonically with the slider', () {
      var last = 0.0;
      for (final v in [20.0, 50.0, 80.0, 100.0]) {
        final d = _dpx(
          _build({PortraitIds.faceWidth: v}),
          400 - 1.05 * 120,
          250 + 0.9 * 120,
        ).$1;
        expect(d, greaterThan(last));
        last = d;
      }
    });

    test('no fold-over at ±100 for every slider (Jacobian > 0)', () {
      for (final id in kFaceShapeIds) {
        for (final v in [-100.0, 100.0]) {
          final f = _build({id: v});
          expect(f.minJacobian(), greaterThan(0.2), reason: '$id $v');
        }
      }
      final all = _build({for (final id in kFaceShapeIds) id: 100});
      expect(all.minJacobian(), greaterThan(0.2));
    });

    test('symmetric for a symmetric face', () {
      final f = _build({
        PortraitIds.faceWidth: 70,
        PortraitIds.vShape: 60,
        PortraitIds.eyeSize: 80,
        PortraitIds.noseWidth: -50,
        PortraitIds.mouthSize: 40,
        PortraitIds.chin: 30,
      });
      for (final (lx, ly) in [
        (0.9, 0.8),
        (0.5, 0.0),
        (0.2, 0.7),
        (0.3, 1.1),
        (1.1, 0.3),
      ]) {
        final r = _dpx(f, 400 - lx * 120, 250 + ly * 120);
        final l = _dpx(f, 400 + lx * 120, 250 + ly * 120);
        expect(
          l.$1,
          closeTo(-r.$1, 0.1 + 0.05 * r.$1.abs()),
          reason: '($lx, $ly) x',
        );
        expect(
          l.$2,
          closeTo(r.$2, 0.1 + 0.05 * r.$2.abs()),
          reason: '($lx, $ly) y',
        );
      }
    });

    test('eye size +100 magnifies around the iris (samples move inward)', () {
      final f = _build({PortraitIds.eyeSize: 100});
      // A point right of the image-left iris centre (-0.5, 0).
      final d = _dpx(f, 400 - 0.5 * 120 + 12, 250);
      expect(d.$1, lessThan(-1));
    });

    test('per-face values follow group and individual settings', () {
      final two = synthAnalysis(1200, 500, [
        face('f', 300, 200, 100, group: FaceGroup.female),
        face('m', 900, 200, 100, personId: 'bob'),
      ]);
      final s = PortraitSettings.empty
          .withGroupValue(FaceGroup.female, PortraitIds.faceWidth, 100)
          .withIndividualValue('bob', PortraitIds.faceWidth, -100);
      final f = buildWarpField(
        WarpRequest(
          sourceWidth: 1200,
          sourceHeight: 500,
          faces: two,
          portrait: s,
        ),
      );
      (double, double) at(double x, double y) {
        final (u, v) = f.sample(x / 1200, y / 500);
        return (u * 1200, v * 500);
      }

      // Image-left jaw of each face: wide face samples inward (+x), slim -x.
      expect(at(300 - 105, 290).$1, greaterThan(1));
      expect(at(900 - 105, 290).$1, lessThan(-1));
      expect(
        warpShapeKey(s, two),
        isNot(warpShapeKey(PortraitSettings.empty, two)),
      );
    });

    test('hasWarpEdits sees shape values and liquify strokes', () {
      expect(hasWarpEdits(DevelopSettings.defaults, _one), isFalse);
      expect(
        hasWarpEdits(
          DevelopSettings.defaults.copyWith(
            portrait: shapes({PortraitIds.chin: 10}),
          ),
          _one,
        ),
        isTrue,
      );
      expect(
        hasWarpEdits(
          DevelopSettings.defaults.copyWith(
            portrait: shapes({PortraitIds.chin: 10}),
          ),
          null,
        ),
        isFalse,
      );
      expect(
        hasWarpEdits(
          DevelopSettings.defaults.copyWith(
            liquify: const [
              LiquifyStroke(
                tool: LiquifyTool.bloat,
                points: [(0.5, 0.5)],
                radius: 0.1,
              ),
            ],
          ),
          null,
        ),
        isTrue,
      );
    });
  });
}
