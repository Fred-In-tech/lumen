import 'dart:math' as math;
import 'dart:typed_data';

import '../model/face_analysis.dart';
import '../render/rgba_buffer.dart';
import '../vision/guided_filter.dart';
import '../vision/mesh_keypoints.dart';
import '../vision/tensor_sampling.dart';

/// Long edge regions are resampled to before measuring sharpness, so faces
/// of different sizes (and photos of different resolutions) compare.
const kSharpnessSize = 160;

/// Contrast-normalized sharpness of [region] (default: the whole image):
/// variance of the 4-neighbour Laplacian of luma divided by the luma
/// variance (+ a floor so flat regions read as soft), after area-resampling
/// the region to a long edge of at most [maxSize]. Blur lowers it steeply;
/// higher is sharper.
double sharpnessScore(
  RgbaBuffer img, {
  PixelRegion? region,
  int maxSize = kSharpnessSize,
}) {
  final r = region ?? (left: 0, top: 0, width: img.width, height: img.height);
  final s = math.min(1.0, maxSize / math.max(r.width, r.height));
  final w = math.max(3, (r.width * s).round());
  final h = math.max(3, (r.height * s).round());
  final l = lumaPlane(img, width: w, height: h, region: r);
  var sum = 0.0, sum2 = 0.0, lap = 0.0, lap2 = 0.0;
  var n = 0;
  for (var i = 0; i < l.length; i++) {
    sum += l[i];
    sum2 += l[i] * l[i];
  }
  for (var y = 1; y < h - 1; y++) {
    for (var x = 1; x < w - 1; x++) {
      final i = y * w + x;
      final v = 4 * l[i] - l[i - 1] - l[i + 1] - l[i - w] - l[i + w];
      lap += v;
      lap2 += v * v;
      n++;
    }
  }
  final mean = sum / l.length;
  final lumaVar = math.max(0.0, sum2 / l.length - mean * mean);
  final lapMean = lap / n;
  final lapVar = math.max(0.0, lap2 / n - lapMean * lapMean);
  return lapVar / (lumaVar + 1e-3);
}

/// Pixel region of a normalized [box] grown by [scale] about its centre,
/// clamped to the image.
PixelRegion faceBoxRegion(
  FaceBox box,
  int width,
  int height, {
  double scale = 1,
}) {
  final w = box.width * width * scale, h = box.height * height * scale;
  final l = (box.centerX * width - w / 2).round().clamp(0, width - 1);
  final t = (box.centerY * height - h / 2).round().clamp(0, height - 1);
  final r = (box.centerX * width + w / 2).round().clamp(l + 1, width);
  final b = (box.centerY * height + h / 2).round().clamp(t + 1, height);
  return (left: l, top: t, width: r - l, height: b - t);
}

/// Eye aspect ratio of one eye from normalized mesh [landmarks]
/// ([MeshKeypoints.rightEyeEar] / [MeshKeypoints.leftEyeEar] order),
/// measured in source pixels. ≈ 0.25–0.35 open, < 0.15 closed.
double eyeAspectRatio(
  List<double> landmarks,
  List<int> eye, {
  required int imageWidth,
  required int imageHeight,
}) {
  double d(int a, int b) {
    final dx = (landmarks[2 * a] - landmarks[2 * b]) * imageWidth;
    final dy = (landmarks[2 * a + 1] - landmarks[2 * b + 1]) * imageHeight;
    return math.sqrt(dx * dx + dy * dy);
  }

  final width = d(eye[0], eye[3]);
  if (width <= 0) return 0;
  return (d(eye[1], eye[5]) + d(eye[2], eye[4])) / (2 * width);
}

/// Exposure measurements of an analysis proxy.
typedef ExposureSignal = ({
  double highlightClip,
  double shadowClip,
  double meanLuma,
  double faceHighlightClip,
});

/// Share of clipped highlights (any channel ≥ 250) and crushed shadows
/// (luma ≤ 4), mean luma, and the highlight share inside [faces].
ExposureSignal measureExposure(
  RgbaBuffer img, {
  List<FaceBox> faces = const [],
}) {
  final d = img.data, w = img.width, h = img.height;
  var hi = 0, lo = 0, faceHi = 0, faceN = 0;
  var lumaSum = 0.0;
  final regions = [for (final f in faces) faceBoxRegion(f, w, h)];
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final o = (y * w + x) * 4;
      final r = d[o], g = d[o + 1], b = d[o + 2];
      final luma = 0.2126 * r + 0.7152 * g + 0.0722 * b;
      lumaSum += luma;
      final clipped = r >= 250 || g >= 250 || b >= 250;
      if (clipped) hi++;
      if (luma <= 4) lo++;
      for (final rg in regions) {
        if (x >= rg.left &&
            x < rg.left + rg.width &&
            y >= rg.top &&
            y < rg.top + rg.height) {
          faceN++;
          if (clipped) faceHi++;
          break;
        }
      }
    }
  }
  final n = w * h;
  return (
    highlightClip: hi / n,
    shadowClip: lo / n,
    meanLuma: lumaSum / (n * 255),
    faceHighlightClip: faceN == 0 ? 0.0 : faceHi / faceN,
  );
}

/// 64-bit difference hash (dHash): luma on a 9×8 grid, one bit per
/// horizontal neighbour pair (left brighter than right), as 16 hex digits.
/// Near-duplicates differ in a few bits; unrelated photos in about 32.
String differenceHash(RgbaBuffer img) {
  final l = lumaPlane(img, width: 9, height: 8);
  final bytes = Uint8List(8);
  for (var y = 0; y < 8; y++) {
    var byte = 0;
    for (var x = 0; x < 8; x++) {
      if (l[y * 9 + x] > l[y * 9 + x + 1]) byte |= 1 << (7 - x);
    }
    bytes[y] = byte;
  }
  return [for (final b in bytes) b.toRadixString(16).padLeft(2, '0')].join();
}

/// Number of differing bits between two [differenceHash]es (64 when the
/// hashes are malformed or of different length).
int hammingDistance(String a, String b) {
  if (a.length != b.length || a.length.isOdd) return 64;
  var bits = 0;
  for (var i = 0; i < a.length; i += 2) {
    final x = int.tryParse(a.substring(i, i + 2), radix: 16);
    final y = int.tryParse(b.substring(i, i + 2), radix: 16);
    if (x == null || y == null) return 64;
    var v = x ^ y;
    while (v != 0) {
      bits += v & 1;
      v >>= 1;
    }
  }
  return bits;
}
