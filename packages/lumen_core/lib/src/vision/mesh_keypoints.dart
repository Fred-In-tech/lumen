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
}
