import 'dart:math' as math;
import 'dart:typed_data';

import 'package:lumen_core/lumen_core.dart';
import 'package:test/test.dart';

import 'synthetic_face.dart';

void expectRoundTrip(Affine2x3 m, double x, double y) {
  final (u, v) = m.apply(x, y);
  final (bx, by) = m.inverse().apply(u, v);
  expect(bx, closeTo(x, 1e-6));
  expect(by, closeTo(y, 1e-6));
}

void main() {
  group('Affine2x3', () {
    test('forward/inverse round-trip < 1e-6 (similarity and general)', () {
      final rnd = math.Random(7);
      for (var i = 0; i < 50; i++) {
        final sim = Affine2x3.similarity(
          scale: 0.1 + rnd.nextDouble() * 20,
          rotation: (rnd.nextDouble() - 0.5) * 2 * math.pi,
          tx: rnd.nextDouble() * 4000,
          ty: rnd.nextDouble() * 3000,
        );
        expectRoundTrip(sim, rnd.nextDouble() * 6000, rnd.nextDouble() * 4000);
      }
      const general = Affine2x3(1.3, 0.2, -40, -0.4, 0.9, 12);
      expectRoundTrip(general, 123.4, -56.7);
    });

    test('then() equals applying in sequence; identity is neutral', () {
      final a = Affine2x3.similarity(scale: 2, rotation: 0.3, tx: 5, ty: -1);
      const b = Affine2x3(0.5, 0.1, 3, -0.2, 1.5, 7);
      final (x1, y1) = b.apply(a.apply(10, 20).$1, a.apply(10, 20).$2);
      final (x2, y2) = a.then(b).apply(10, 20);
      expect(x2, closeTo(x1, 1e-12));
      expect(y2, closeTo(y1, 1e-12));
      expect(a.then(Affine2x3.identity), a);
    });

    test('singular transforms throw', () {
      expect(
        () => const Affine2x3(1, 2, 0, 2, 4, 0).inverse(),
        throwsStateError,
      );
    });
  });

  group('AlignedCrop', () {
    test('from a detection: 1.5x square, eyes level, centred', () {
      // Eyes 100 px apart, the left eye 100·tan(30°) px lower: roll 30°.
      const w = 1000, h = 800;
      final dy = 100 * math.tan(math.pi / 6);
      final det = FaceDetection(
        xMin: 0.4,
        yMin: 0.35,
        width: 0.2,
        height: 0.3,
        keypoints: [
          0.45, 0.45, // right eye (image left)
          0.55, 0.45 + dy / h, // left eye
          0.5, 0.5, 0.5, 0.55, 0.4, 0.45, 0.6, 0.45,
        ],
        score: 0.9,
      );
      final crop = AlignedCrop.fromDetection(
        det,
        imageWidth: w,
        imageHeight: h,
      );
      expect(crop.rotation, closeTo(math.pi / 6, 1e-12));
      expect(crop.side, closeTo(math.max(0.2 * w, 0.3 * h) * 1.5, 1e-9));
      final m = crop.sourceToCrop;
      final (cu, cv) = m.apply(500, 0.5 * h);
      expect(cu, closeTo(128, 1e-9));
      expect(cv, closeTo(128, 1e-9));
      final (_, rv) = m.apply(0.45 * w, 0.45 * h);
      final (_, lv) = m.apply(0.55 * w, 0.45 * h + dy);
      expect(lv, closeTo(rv, 1e-9), reason: 'eyes level in the crop');
      expectRoundTrip(crop.cropToSource, 17.5, 240.25);
    });

    test('landmarks map back through the inverse affine', () {
      const w = 1200, h = 900;
      const crop = AlignedCrop(
        centerX: 600,
        centerY: 420,
        side: 300,
        rotation: -0.4,
      );
      final src = [(550.0, 400.0), (650.0, 380.0), (600.0, 500.0)];
      final toCrop = crop.sourceToCrop;
      final raw = Float32List(src.length * 3);
      for (var i = 0; i < src.length; i++) {
        final (u, v) = toCrop.apply(src[i].$1, src[i].$2);
        raw[i * 3] = u;
        raw[i * 3 + 1] = v;
        raw[i * 3 + 2] = -5; // z is dropped
      }
      final norm = landmarksToSource(raw, crop, imageWidth: w, imageHeight: h);
      expect(norm, hasLength(6));
      for (var i = 0; i < src.length; i++) {
        expect(norm[2 * i], closeTo(src[i].$1 / w, 1e-5));
        expect(norm[2 * i + 1], closeTo(src[i].$2 / h, 1e-5));
      }
    });

    test('refine crop from landmarks: bbox centre, roll from 33→263', () {
      const w = 1000, h = 1000;
      final lm = syntheticLandmarks(
        imageWidth: w,
        imageHeight: h,
        cx: 400,
        cy: 300,
        rollDegrees: 12,
      );
      final crop = AlignedCrop.fromLandmarks(lm, imageWidth: w, imageHeight: h);
      expect(crop.rotation * 180 / math.pi, closeTo(12, 1e-9));
      expect(crop.side, greaterThan(0));
      expect(
        () => AlignedCrop.fromLandmarks(
          const [0.1, 0.2],
          imageWidth: w,
          imageHeight: h,
        ),
        throwsArgumentError,
      );
    });
  });
}
