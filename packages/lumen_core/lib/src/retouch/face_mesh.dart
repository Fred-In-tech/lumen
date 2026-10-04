/// MediaPipe Face Landmarker (FaceMesh V2, 478 points) index map.
///
/// Source: research 07 §1.3 (cycle-ordered from `face_mesh_connections.py`
/// and checked against `canonical_face_model.obj`). "Right" means the
/// subject's right, which is on the image's LEFT in a non-mirrored photo.
/// Pair sides through these named lists, never by guessing from names.
library;

abstract final class FaceMesh {
  static const int landmarkCount = 478;

  /// Closed loop, clockwise on screen from the top (10 = mid-forehead, not
  /// the hairline; 152 = menton).
  static const List<int> faceOval = [
    10, 338, 297, 332, 284, 251, 389, 356, 454, 323, 361, 288, //
    397, 365, 379, 378, 400, 377, 152, 148, 176, 149, 150, 136,
    172, 58, 132, 93, 234, 127, 162, 21, 54, 103, 67, 109,
  ];
  static const int foreheadTop = 10;
  static const int menton = 152;

  /// Eye loops: upper lid outer → inner corner, then lower lid inner → outer.
  static const List<int> rightEye = [
    33, 246, 161, 160, 159, 158, 157, 173, 133, //
    155, 154, 153, 145, 144, 163, 7,
  ];
  static const List<int> leftEye = [
    263, 466, 388, 387, 386, 385, 384, 398, 362, //
    382, 381, 380, 374, 373, 390, 249,
  ];

  /// Lower lid from the outer corner to the inner corner (inclusive).
  static const List<int> rightLowerLid = [
    33, 7, 163, 144, 145, 153, 154, 155, 133, //
  ];
  static const List<int> leftLowerLid = [
    263, 249, 390, 373, 374, 380, 381, 382, 362, //
  ];

  static const int rightIrisCenter = 468;
  static const List<int> rightIrisRing = [469, 470, 471, 472];
  static const int leftIrisCenter = 473;
  static const List<int> leftIrisRing = [474, 475, 476, 477];

  /// Under-eye rings, outer → inner; they move down and out monotonically.
  static const List<int> rightUnderEye2 = [
    130, 25, 110, 24, 23, 22, 26, 112, 243, //
  ];
  static const List<int> leftUnderEye2 = [
    359, 255, 339, 254, 253, 252, 256, 341, 463, //
  ];
  static const List<int> rightUnderEye3 = [
    226, 31, 228, 229, 230, 231, 232, 233, 244, //
  ];
  static const List<int> leftUnderEye3 = [
    446, 261, 448, 449, 450, 451, 452, 453, 464, //
  ];
  static const List<int> rightUnderEye4 = [
    35, 111, 117, 118, 119, 120, 121, 128, 245, //
  ];
  static const List<int> leftUnderEye4 = [
    265, 340, 346, 347, 348, 349, 350, 357, 465, //
  ];

  /// Brow polygon = lower edge + upper edge reversed (outer → inner each).
  static const List<int> rightBrowLower = [46, 53, 52, 65, 55];
  static const List<int> rightBrowUpper = [70, 63, 105, 66, 107];
  static const List<int> leftBrowLower = [276, 283, 282, 295, 285];
  static const List<int> leftBrowUpper = [300, 293, 334, 296, 336];

  /// Lips: corners 61 / 291 (outer) and 78 / 308 (inner).
  static const List<int> lipsOuter = [
    61, 185, 40, 39, 37, 0, 267, 269, 270, 409, 291, //
    375, 321, 405, 314, 17, 84, 181, 91, 146,
  ];

  /// Mouth opening (teeth candidate region).
  static const List<int> lipsInner = [
    78, 191, 80, 81, 82, 13, 312, 311, 310, 415, 308, //
    324, 318, 402, 317, 14, 87, 178, 88, 95,
  ];

  static const List<int> noseRidge = [168, 6, 197, 195, 5, 4, 1];
  static const List<int> noseTip = [1, 4];
  static const List<int> noseBase = [98, 97, 2, 326, 327];
  static const List<int> rightAlar = [4, 45, 220, 115, 48, 64, 98];
  static const List<int> leftAlar = [4, 275, 440, 344, 278, 294, 327];
  static const List<int> rightBridgeSide = [193, 122, 196, 3, 51];
  static const List<int> leftBridgeSide = [417, 351, 419, 248, 281];

  /// Nose outline (slimming and smoothing exclusion; 🔶 validate visually).
  static const List<int> nose = [
    168, 417, 351, 419, 248, 281, 275, 440, 344, 278, 294, 327, 326, //
    2, 97, 98, 64, 48, 115, 220, 45, 51, 3, 196, 122, 193,
  ];

  /// Nostrils: an ellipse is fitted to these four points.
  static const List<int> rightNostril = [98, 64, 48, 115];
  static const List<int> leftNostril = [327, 294, 278, 344];

  static const List<int> forehead = [
    54, 103, 67, 109, 10, 338, 297, 332, 284, 301, 300, //
    293, 334, 296, 336, 9, 107, 66, 105, 63, 70, 71,
  ];
  static const List<int> glabella = [55, 107, 9, 336, 285, 8];

  /// Crow's-feet zones (use the convex hull).
  static const List<int> rightCrowsFeet = [
    130, 113, 124, 156, 139, 34, 143, 111, 31, //
  ];
  static const List<int> leftCrowsFeet = [
    359, 342, 353, 383, 368, 264, 372, 340, 261, //
  ];

  /// Polylines (draw as 0.10 IOD-wide strokes).
  static const List<int> rightNasolabial = [129, 203, 206, 216, 212];
  static const List<int> leftNasolabial = [358, 423, 426, 436, 432];
  static const List<int> rightMarionette = [57, 43, 202, 210, 169];
  static const List<int> leftMarionette = [287, 273, 422, 430, 394];

  /// Cheek apple (blush centre) and its axis (from → toward).
  static const int rightCheekApple = 50;
  static const List<int> rightCheekAxis = [205, 123];
  static const int leftCheekApple = 280;
  static const List<int> leftCheekAxis = [425, 352];

  static const List<int> rightJaw = [93, 132, 58, 172, 136, 150, 149, 176, 148];
  static const List<int> leftJaw = [
    323,
    361,
    288,
    397,
    365,
    379,
    378,
    400,
    377,
  ];
  static const List<int> chinCenterLine = [175, 199, 200];
  static const List<int> rightChin = [171, 140, 32, 208];
  static const List<int> leftChin = [396, 369, 262, 428];

  /// Forehead-centre sampling point for the skin colour model: between the
  /// glabella top (9) and the mid-forehead (10).
  static const int glabellaTop = 9;
}
