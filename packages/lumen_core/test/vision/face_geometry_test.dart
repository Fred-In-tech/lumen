import 'dart:math' as math;

import 'package:lumen_core/lumen_core.dart';
import 'package:test/test.dart';

import 'synthetic_face.dart';

FaceGeometry geometry({
  double iod = 100,
  double yaw = 0,
  double roll = 0,
  int w = 1000,
  int h = 800,
}) => FaceGeometry.fromLandmarks(
  syntheticLandmarks(
    imageWidth: w,
    imageHeight: h,
    iod: iod,
    yawDegrees: yaw,
    rollDegrees: roll,
  ),
  imageWidth: w,
  imageHeight: h,
);

void main() {
  group('FaceGeometry', () {
    test('IOD from iris centres, roll from 33→263, iris radius', () {
      final g = geometry(iod: 120, roll: -15);
      expect(g.iod, closeTo(120, 1e-6));
      expect(g.roll * 180 / math.pi, closeTo(-15, 1e-6));
      expect(g.irisRadius, closeTo(6, 1e-6));
      expect(g.yawDegrees, closeTo(0, 1e-6));
    });

    test('yaw is recovered from the nose-tip offset', () {
      for (final yaw in [-70.0, -40.0, 20.0, 55.0, 65.0]) {
        expect(geometry(yaw: yaw).yawDegrees, closeTo(yaw, 1e-6));
      }
      // Roll does not leak into yaw.
      expect(geometry(yaw: 30, roll: 25).yawDegrees, closeTo(30, 1e-6));
    });

    test('lengths are in source pixels even for a downscaled analysis', () {
      final lm = syntheticLandmarks(imageWidth: 1000, imageHeight: 800);
      final g = FaceGeometry.fromLandmarks(
        lm,
        imageWidth: 4000,
        imageHeight: 3200,
      );
      expect(g.iod, closeTo(400, 1e-6));
    });

    test('size classes', () {
      expect(FaceSizeClass.forIod(59), FaceSizeClass.small);
      expect(FaceSizeClass.forIod(60), FaceSizeClass.medium);
      expect(FaceSizeClass.forIod(250), FaceSizeClass.medium);
      expect(FaceSizeClass.forIod(251), FaceSizeClass.large);
      expect(geometry(iod: 300).sizeClass, FaceSizeClass.large);
    });

    test('needs all 478 points', () {
      expect(
        () => FaceGeometry.fromLandmarks(
          const [0.5, 0.5],
          imageWidth: 10,
          imageHeight: 10,
        ),
        throwsArgumentError,
      );
    });
  });

  group('FaceRejectRules', () {
    const rules = FaceRejectRules();

    test('accepts a frontal, large-enough, confident face', () {
      expect(rules.evaluate(presence: 0.9, geometry: geometry()), isNull);
      expect(
        rules.evaluate(presence: 0.5, geometry: geometry(iod: 24.0001)),
        isNull,
        reason: 'presence and IOD thresholds are inclusive',
      );
      expect(
        rules.evaluate(presence: 0.9, geometry: geometry(yaw: 59.9)),
        isNull,
      );
    });

    test('face flag < 0.5 → lowPresence', () {
      expect(
        rules.evaluate(presence: 0.49, geometry: geometry()),
        FaceRejectReason.lowPresence,
      );
    });

    test('IOD < 24 px → tooSmall', () {
      expect(
        rules.evaluate(presence: 0.9, geometry: geometry(iod: 23)),
        FaceRejectReason.tooSmall,
      );
    });

    test('|yaw| > 60° → extremeYaw', () {
      expect(
        rules.evaluate(presence: 0.9, geometry: geometry(yaw: 61)),
        FaceRejectReason.extremeYaw,
      );
      expect(
        rules.evaluate(presence: 0.9, geometry: geometry(yaw: -75)),
        FaceRejectReason.extremeYaw,
      );
    });

    test('reason names round-trip', () {
      for (final r in FaceRejectReason.values) {
        expect(FaceRejectReason.fromName(r.name), r);
      }
      expect(FaceRejectReason.fromName('nope'), isNull);
    });
  });
}
