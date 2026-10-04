/// The few MediaPipe Face Mesh (478-point) indices the vision pipeline needs
/// for alignment, rejection and derived geometry (research 07 §1.2).
///
/// "Right"/"left" are the subject's sides: the subject's right appears on the
/// image's left in a non-mirrored photo. The full region map (eyes, lips,
/// forehead…) is owned by `src/retouch/`.
abstract final class MeshKeypoints {
  /// 468 mesh points + 10 iris points.
  static const pointCount = 478;

  /// The mesh without the iris refinement.
  static const basePointCount = 468;

  static const rightIrisCenter = 468;
  static const rightIrisRing = [469, 470, 471, 472];
  static const leftIrisCenter = 473;
  static const leftIrisRing = [474, 475, 476, 477];

  /// Outer eye corners; roll is the angle of [rightEyeOuter] → [leftEyeOuter].
  static const rightEyeOuter = 33;
  static const leftEyeOuter = 263;

  static const noseTip = 1;
  static const chin = 152;

  /// Mid-forehead (top of the mesh; the hairline is above it).
  static const foreheadTop = 10;

  /// Face oval extremes at cheek height (face width).
  static const rightCheekEdge = 234;
  static const leftCheekEdge = 454;

  /// Eye aspect ratio points (Soukupová & Čech): p1 and p4 are the
  /// corners, p2/p3 the upper lid, p6/p5 the lower lid, so
  /// EAR = (|p2−p6| + |p3−p5|) / (2·|p1−p4|).
  static const rightEyeEar = [33, 160, 158, 133, 153, 144];
  static const leftEyeEar = [362, 385, 387, 263, 373, 380];
}
