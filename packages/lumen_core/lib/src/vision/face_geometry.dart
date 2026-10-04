import 'dart:math' as math;

import 'mesh_keypoints.dart';

/// Size class that picks the retouch band sigmas (research 07 §1.2).
enum FaceSizeClass {
  /// IOD < 60 px.
  small,
  medium,

  /// IOD > 250 px.
  large;

  static FaceSizeClass forIod(double iodPx) => iodPx < 60
      ? small
      : iodPx > 250
      ? large
      : medium;
}

/// Ratio of the nose-tip protrusion (in front of the outer-eye-corner plane)
/// to the outer-corner distance. Anthropometric estimate 🔶; tune against
/// the canonical face model once the mesh runs.
const kNoseDepthToEyeSpan = 0.4;

/// Geometry derived from one face's 478 landmarks, in source pixels.
class FaceGeometry {
  const FaceGeometry({
    required this.iod,
    required this.roll,
    required this.yawDegrees,
    required this.irisRadiusRight,
    required this.irisRadiusLeft,
  });

  /// [landmarks]: flat normalized (x, y); [imageWidth]/[imageHeight]: the
  /// source (original) size, so lengths come out in source pixels even when
  /// the analysis ran on a downscaled copy.
  factory FaceGeometry.fromLandmarks(
    List<double> landmarks, {
    required int imageWidth,
    required int imageHeight,
  }) {
    if (landmarks.length < MeshKeypoints.pointCount * 2) {
      throw ArgumentError(
        'need ${MeshKeypoints.pointCount} points, got ${landmarks.length ~/ 2}',
      );
    }
    double x(int i) => landmarks[2 * i] * imageWidth;
    double y(int i) => landmarks[2 * i + 1] * imageHeight;
    double dist(int i, int j) =>
        math.sqrt(math.pow(x(i) - x(j), 2) + math.pow(y(i) - y(j), 2));
    double irisRadius(int center, List<int> ring) =>
        ring.map((r) => dist(center, r)).reduce((a, b) => a + b) / ring.length;

    const re = MeshKeypoints.rightEyeOuter;
    const le = MeshKeypoints.leftEyeOuter;
    final ex = x(le) - x(re);
    final ey = y(le) - y(re);
    final span = math.sqrt(ex * ex + ey * ey);
    var yaw = 0.0;
    if (span > 0) {
      // Signed offset of the nose tip from the eye midpoint along the eye
      // line; under yaw ψ it is depth·sin ψ while the span shrinks by cos ψ.
      final mx = (x(le) + x(re)) / 2;
      final my = (y(le) + y(re)) / 2;
      final off =
          ((x(MeshKeypoints.noseTip) - mx) * ex +
              (y(MeshKeypoints.noseTip) - my) * ey) /
          span;
      yaw = math.atan2(off, kNoseDepthToEyeSpan * span) * 180 / math.pi;
    }
    return FaceGeometry(
      iod: dist(MeshKeypoints.rightIrisCenter, MeshKeypoints.leftIrisCenter),
      roll: math.atan2(ey, ex),
      yawDegrees: yaw,
      irisRadiusRight: irisRadius(
        MeshKeypoints.rightIrisCenter,
        MeshKeypoints.rightIrisRing,
      ),
      irisRadiusLeft: irisRadius(
        MeshKeypoints.leftIrisCenter,
        MeshKeypoints.leftIrisRing,
      ),
    );
  }

  /// Inter-ocular distance (iris centres 468 ↔ 473), source px.
  final double iod;

  /// Angle of 33 → 263 in radians (image coordinates, y down).
  final double roll;

  /// Estimated from the nose-tip offset; positive toward the subject's left.
  final double yawDegrees;
  final double irisRadiusRight;
  final double irisRadiusLeft;

  double get irisRadius => (irisRadiusRight + irisRadiusLeft) / 2;
  FaceSizeClass get sizeClass => FaceSizeClass.forIod(iod);
}

/// Why a face gets no automatic retouch (masks and manual tools still work).
enum FaceRejectReason {
  /// Landmark model's face flag < threshold (probably not a face).
  lowPresence,

  /// IOD under the minimum in source pixels.
  tooSmall,

  /// Head turned too far for the mesh to be trusted.
  extremeYaw;

  static FaceRejectReason? fromName(Object? v) =>
      values.where((r) => r.name == v).firstOrNull;
}

/// Reject thresholds (research 07 §1.2 step 5).
class FaceRejectRules {
  const FaceRejectRules({
    this.minPresence = 0.5,
    this.minIodPx = 24,
    this.maxYawDegrees = 60,
  });

  final double minPresence;
  final double minIodPx;
  final double maxYawDegrees;

  /// The first failing rule, or null when the face is accepted.
  FaceRejectReason? evaluate({
    required double presence,
    required FaceGeometry geometry,
  }) {
    if (presence < minPresence) return FaceRejectReason.lowPresence;
    if (geometry.iod < minIodPx) return FaceRejectReason.tooSmall;
    if (geometry.yawDegrees.abs() > maxYawDegrees) {
      return FaceRejectReason.extremeYaw;
    }
    return null;
  }
}
