import 'package:lumen_core/lumen_core.dart';
import 'package:test/test.dart';

import 'cull_fixtures.dart';

void main() {
  group('sharpnessScore', () {
    test('falls steadily with blur', () {
      final t = texture(400, 300);
      final scores = [
        for (final s in [0.0, 1.0, 2.0, 3.0, 5.0])
          sharpnessScore(blurred(t, s)),
      ];
      for (var i = 1; i < scores.length; i++) {
        expect(scores[i], lessThan(scores[i - 1] * 0.8), reason: '$scores');
      }
      expect(scores.first / scores.last, greaterThan(100));
    });

    test('is normalized by size: the same scene at 4× resolution agrees', () {
      final small = sharpnessScore(texture(400, 300, block: 3));
      final big = sharpnessScore(texture(1600, 1200, block: 12));
      expect(big, closeTo(small, small * 0.25));
    });

    test('a region measures only that region; flat reads as soft', () {
      final img = texture(400, 300);
      final flat = RgbaBuffer.filled(400, 300, 128, 128, 128);
      expect(sharpnessScore(flat), lessThan(1e-3));
      // Blur only the right half.
      final half = blurred(img, 4);
      for (var y = 0; y < 300; y++) {
        for (var x = 0; x < 200; x++) {
          final o = img.offset(x, y);
          half.setPixel(x, y, img.data[o], img.data[o + 1], img.data[o + 2]);
        }
      }
      final left = sharpnessScore(
        half,
        region: (left: 0, top: 0, width: 190, height: 300),
      );
      final right = sharpnessScore(
        half,
        region: (left: 210, top: 0, width: 190, height: 300),
      );
      expect(left, greaterThan(right * 10));
    });
  });

  group('eyeAspectRatio', () {
    test('matches the opening of the fixture eyes', () {
      for (final open in [0.05, 0.15, 0.3]) {
        final lm = eyeLandmarks(openness: open);
        for (final eye in [
          MeshKeypoints.rightEyeEar,
          MeshKeypoints.leftEyeEar,
        ]) {
          expect(
            eyeAspectRatio(lm, eye, imageWidth: 1000, imageHeight: 800),
            closeTo(open, 1e-9),
          );
        }
      }
    });

    test('eye states from the default thresholds', () {
      const c = CullConfig();
      expect(c.eyeState(0.3), EyeState.open);
      expect(c.eyeState(0.18), EyeState.halfOpen);
      expect(c.eyeState(0.08), EyeState.closed);
    });
  });

  group('measureExposure', () {
    test('counts clipped highlights, crushed shadows and face clipping', () {
      final img = RgbaBuffer.filled(100, 100, 128, 128, 128);
      for (var y = 0; y < 100; y++) {
        for (var x = 0; x < 30; x++) {
          img.setPixel(x, y, 255, 255, 255);
        }
        for (var x = 90; x < 100; x++) {
          img.setPixel(x, y, 0, 0, 0);
        }
      }
      final e = measureExposure(
        img,
        faces: const [FaceBox(0, 0, 0.2, 0.2), FaceBox(0.6, 0.6, 0.1, 0.1)],
      );
      expect(e.highlightClip, closeTo(0.3, 1e-9));
      expect(e.shadowClip, closeTo(0.1, 1e-9));
      expect(e.faceHighlightClip, closeTo(400 / 500, 1e-9));
      expect(e.meanLuma, closeTo((0.3 * 255 + 0.6 * 128) / 255, 1e-3));
    });
  });

  group('differenceHash', () {
    test('identical → 0; small changes → a few bits; other scenes → many', () {
      final a = texture(320, 240, block: 40, seed: 1);
      final h = differenceHash(a);
      expect(h, hasLength(16));
      expect(hammingDistance(h, differenceHash(a.copy())), 0);
      // Brighter and slightly blurred: same shot.
      final b = blurred(a, 2);
      for (var i = 0; i < b.data.length; i += 4) {
        b.data[i] = (b.data[i] + 10).clamp(0, 255);
        b.data[i + 1] = (b.data[i + 1] + 10).clamp(0, 255);
        b.data[i + 2] = (b.data[i + 2] + 10).clamp(0, 255);
      }
      expect(hammingDistance(h, differenceHash(b)), lessThanOrEqualTo(6));
      final other = differenceHash(texture(320, 240, block: 40, seed: 9));
      expect(hammingDistance(h, other), greaterThan(16));
    });

    test('malformed hashes are maximally distant', () {
      expect(hammingDistance('00', '0000'), 64);
      expect(hammingDistance('zz', '00'), 64);
      expect(hammingDistance('ff', '0f'), 4);
    });
  });

  group('computeCullSignals', () {
    test('measures faces, eyes, exposure and the hash; JSON round-trips', () {
      final img = texture(1000, 800, block: 4);
      final face = DetectedFace(
        id: 'f32_25',
        box: const FaceBox(0.4, 0.4, 0.2, 0.25),
        landmarks: eyeLandmarks(openness: 0.08),
      );
      final s = computeCullSignals(
        img,
        faces: [face],
        rejected: const [
          RejectedFace(
            id: 'low',
            box: FaceBox(0, 0, 0.1, 0.1),
            reason: FaceRejectReason.lowPresence,
          ),
          RejectedFace(
            id: 'tiny',
            box: FaceBox(0.8, 0.8, 0.05, 0.05),
            reason: FaceRejectReason.tooSmall,
          ),
        ],
        capturedAt: DateTime.utc(2026, 10, 3, 12),
      );
      expect(s.faces.map((f) => f.faceId), ['f32_25', 'tiny']);
      expect(s.mainFace!.faceId, 'f32_25');
      expect(s.mainFace!.ear, closeTo(0.08, 1e-9));
      expect(s.faces.last.ear, isNull);
      expect(s.mainFace!.sharpness, greaterThan(1));
      expect(s.dHash, hasLength(16));
      final back = CullSignals.tryFromJson(s.toJson())!;
      expect(back, s);
      expect(CullSignals.tryFromJson({'v': 99}), isNull);
    });
  });
}
