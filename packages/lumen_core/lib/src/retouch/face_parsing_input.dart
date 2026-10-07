import 'dart:convert';
import 'dart:typed_data';

import '../vision/tensor_sampling.dart' show Letterbox;
import 'face_tiles.dart';

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

  /// Planes from one Selfie Multiclass run over the whole tile of [plan],
  /// letterboxed into a `width × height` tensor: [probs] are
  /// `[height, width, channels]` class probabilities (model order =
  /// [ParsingClass] order). Only the tile area inside the [letterbox] is
  /// kept, so the planes cover exactly the tile's source uv rect.
  factory FaceParsingPlanes.fromTile(
    FaceTilePlan plan,
    Float32List probs, {
    required int width,
    required int height,
    required int channels,
    required Letterbox letterbox,
  }) {
    if (probs.length != width * height * channels) {
      throw ArgumentError('probs ${probs.length} != $width×$height×$channels');
    }
    final x0 = (letterbox.left * width).round();
    final x1 = width - (letterbox.right * width).round();
    final y0 = (letterbox.top * height).round();
    final y1 = height - (letterbox.bottom * height).round();
    final w = x1 - x0, h = y1 - y0;
    if (w <= 0 || h <= 0) throw ArgumentError('letterbox leaves no image');
    final planes = [
      for (var c = 0; c < ParsingClass.values.length; c++) Uint8List(w * h),
    ];
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final o = ((y + y0) * width + x + x0) * channels;
        for (var c = 0; c < channels && c < planes.length; c++) {
          final v = probs[o + c];
          planes[c][y * w + x] = v <= 0
              ? 0
              : (v >= 1 ? 255 : (v * 255 + 0.5).toInt());
        }
      }
    }
    return FaceParsingPlanes(
      faceId: plan.faceId,
      cropX: plan.u0,
      cropY: plan.v0,
      cropWidth: plan.u1 - plan.u0,
      cropHeight: plan.v1 - plan.v0,
      width: w,
      height: h,
      background: planes[0],
      hair: planes[1],
      bodySkin: planes[2],
      faceSkin: planes[3],
      clothes: planes[4],
      accessories: planes[5],
    );
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

/// Magic and version of [encodeParsingPlanes] (local cache files only:
/// parsing is derived face data and never goes into edit documents).
const String kParsingMagic = 'LPRS';
const int kParsingVersion = 1;

/// Serialises [list] (little-endian: magic, version, count, then per face
/// the id, the crop rect as float64, the size and the six planes).
Uint8List encodeParsingPlanes(List<FaceParsingPlanes> list) {
  final b = BytesBuilder(copy: false)..add(ascii.encode(kParsingMagic));
  void u32(int v) =>
      b.add((ByteData(4)..setUint32(0, v, Endian.little)).buffer.asUint8List());
  void f64(double v) => b.add(
    (ByteData(8)..setFloat64(0, v, Endian.little)).buffer.asUint8List(),
  );
  u32(kParsingVersion);
  u32(list.length);
  for (final p in list) {
    final id = utf8.encode(p.faceId);
    u32(id.length);
    b.add(id);
    f64(p.cropX);
    f64(p.cropY);
    f64(p.cropWidth);
    f64(p.cropHeight);
    u32(p.width);
    u32(p.height);
    for (final plane in p.planes) {
      b.add(plane);
    }
  }
  return b.takeBytes();
}

/// Inverse of [encodeParsingPlanes]; null for another version or a
/// malformed file (the cache is rebuildable).
List<FaceParsingPlanes>? decodeParsingPlanes(Uint8List bytes) {
  final d = ByteData.sublistView(bytes);
  var o = 0;
  bool has(int n) => o + n <= bytes.length;
  int u32() {
    final v = d.getUint32(o, Endian.little);
    o += 4;
    return v;
  }

  double f64() {
    final v = d.getFloat64(o, Endian.little);
    o += 8;
    return v;
  }

  if (!has(12) ||
      ascii.decode(bytes.sublist(0, 4), allowInvalid: true) != kParsingMagic) {
    return null;
  }
  o = 4;
  if (u32() != kParsingVersion) return null;
  final count = u32();
  final out = <FaceParsingPlanes>[];
  for (var k = 0; k < count; k++) {
    if (!has(4)) return null;
    final idLen = u32();
    if (!has(idLen + 40)) return null;
    final String id;
    try {
      id = utf8.decode(bytes.sublist(o, o + idLen));
    } on FormatException {
      return null;
    }
    o += idLen;
    final cx = f64(), cy = f64(), cw = f64(), ch = f64();
    final w = u32(), h = u32(), n = w * h;
    if (n <= 0 || !(cw > 0) || !(ch > 0) || !has(6 * n)) return null;
    Uint8List next() {
      final p = Uint8List.fromList(bytes.sublist(o, o + n));
      o += n;
      return p;
    }

    out.add(
      FaceParsingPlanes(
        faceId: id,
        cropX: cx,
        cropY: cy,
        cropWidth: cw,
        cropHeight: ch,
        width: w,
        height: h,
        background: next(),
        hair: next(),
        bodySkin: next(),
        faceSkin: next(),
        clothes: next(),
        accessories: next(),
      ),
    );
  }
  return o == bytes.length ? out : null;
}
