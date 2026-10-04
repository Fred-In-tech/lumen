import 'dart:typed_data';

/// MediaPipe Selfie Multiclass (256×256) classes, in model output order.
enum ParsingClass { background, hair, bodySkin, faceSkin, clothes, accessories }

/// Optional segmentation for one face: the multiclass planes of a face
/// crop (research 07 §2.2 step 1). When absent, the skin map falls back to
/// landmark polygons × the colour skin model.
///
/// Each plane is `width × height` bytes (0 = 0 %, 255 = 100 % probability),
/// row-major, covering the crop rect given in normalized source
/// coordinates ([cropX], [cropY], [cropWidth], [cropHeight]).
class FaceParsingPlanes {
  FaceParsingPlanes({
    required this.faceId,
    required this.cropX,
    required this.cropY,
    required this.cropWidth,
    required this.cropHeight,
    required this.width,
    required this.height,
    required this.background,
    required this.hair,
    required this.bodySkin,
    required this.faceSkin,
    required this.clothes,
    required this.accessories,
  }) {
    if (width <= 0 || height <= 0 || cropWidth <= 0 || cropHeight <= 0) {
      throw ArgumentError('empty parsing crop');
    }
    for (final p in planes) {
      if (p.length != width * height) {
        throw ArgumentError('plane length ${p.length} != ${width * height}');
      }
    }
  }

  /// [DetectedFace.id] these planes belong to.
  final String faceId;
  final double cropX;
  final double cropY;
  final double cropWidth;
  final double cropHeight;
  final int width;
  final int height;
  final Uint8List background;
  final Uint8List hair;
  final Uint8List bodySkin;
  final Uint8List faceSkin;
  final Uint8List clothes;
  final Uint8List accessories;

  List<Uint8List> get planes => [
    background,
    hair,
    bodySkin,
    faceSkin,
    clothes,
    accessories,
  ];

  Uint8List plane(ParsingClass c) => planes[c.index];

  /// Bilinear probability (0..1) of class [c] at normalized source `(u, v)`;
  /// 0 outside the crop.
  double sample(ParsingClass c, double u, double v) {
    final cu = (u - cropX) / cropWidth, cv = (v - cropY) / cropHeight;
    if (cu < 0 || cu > 1 || cv < 0 || cv > 1) return 0;
    final p = plane(c);
    final px = cu * width - 0.5, py = cv * height - 0.5;
    final fx0 = px.floorToDouble(), fy0 = py.floorToDouble();
    final fx = px - fx0, fy = py - fy0;
    final x0 = fx0.toInt().clamp(0, width - 1);
    final x1 = (fx0.toInt() + 1).clamp(0, width - 1);
    final y0 = fy0.toInt().clamp(0, height - 1);
    final y1 = (fy0.toInt() + 1).clamp(0, height - 1);
    final top = p[y0 * width + x0] * (1 - fx) + p[y0 * width + x1] * fx;
    final bot = p[y1 * width + x0] * (1 - fx) + p[y1 * width + x1] * fx;
    return (top * (1 - fy) + bot * fy) / 255;
  }
}
