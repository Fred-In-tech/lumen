import 'dart:math' as math;
import 'dart:typed_data';

import 'package:lumen_core/lumen_core.dart';

/// A textured "photo": random grey blocks of [block] px (natural-ish
/// edges at every scale the sharpness measure sees).
RgbaBuffer texture(int w, int h, {int block = 3, int seed = 1}) {
  final rnd = math.Random(seed);
  final bw = (w / block).ceil(), bh = (h / block).ceil();
  final cells = [for (var i = 0; i < bw * bh; i++) 40 + rnd.nextInt(180)];
  final img = RgbaBuffer(w, h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final v = cells[(y ~/ block) * bw + x ~/ block];
      img.setPixel(x, y, v, v, v);
    }
  }
  return img;
}

/// Blur of roughly Gaussian [sigma] px (three box passes of radius
/// round(sigma)).
RgbaBuffer blurred(RgbaBuffer src, double sigma) {
  if (sigma <= 0) return src.copy();
  final r = math.max(1, sigma.round());
  final w = src.width, h = src.height;
  final planes = [
    for (var c = 0; c < 3; c++)
      Float32List.fromList([
        for (var i = 0; i < w * h; i++) src.data[i * 4 + c].toDouble(),
      ]),
  ];
  final out = RgbaBuffer(w, h);
  for (var c = 0; c < 3; c++) {
    var p = planes[c];
    for (var k = 0; k < 3; k++) {
      p = boxMean(p, w, h, r);
    }
    for (var i = 0; i < w * h; i++) {
      out.data[i * 4 + c] = p[i].round().clamp(0, 255);
      out.data[i * 4 + 3] = 255;
    }
  }
  return out;
}

/// 478 landmarks with the eye-aspect-ratio points of both eyes opened to
/// [openness] × the eye width (EAR = openness), on a 1000×800 image.
List<double> eyeLandmarks({
  double openness = 0.3,
  int imageWidth = 1000,
  int imageHeight = 800,
}) {
  final pts = List<(double, double)>.filled(MeshKeypoints.pointCount, (
    500,
    400,
  ));
  void eye(List<int> idx, double cx) {
    const width = 60.0;
    final half = openness * width / 2;
    pts[idx[0]] = (cx - width / 2, 380);
    pts[idx[3]] = (cx + width / 2, 380);
    pts[idx[1]] = (cx - width / 6, 380 - half);
    pts[idx[2]] = (cx + width / 6, 380 - half);
    pts[idx[5]] = (cx - width / 6, 380 + half);
    pts[idx[4]] = (cx + width / 6, 380 + half);
  }

  eye(MeshKeypoints.rightEyeEar, 440);
  eye(MeshKeypoints.leftEyeEar, 560);
  return [
    for (final (x, y) in pts) ...[x / imageWidth, y / imageHeight],
  ];
}

/// Signals with the given knobs (for scoring and clustering tests).
CullSignals signals({
  double sharp = 0.3,
  String hash = '0000000000000000',
  DateTime? at,
  double? ear,
  double hiClip = 0,
  double loClip = 0,
  int faces = 1,
}) => CullSignals(
  sharpness: sharp,
  highlightClip: hiClip,
  shadowClip: loClip,
  meanLuma: 0.5,
  dHash: hash,
  capturedAt: at,
  faces: [
    for (var i = 0; i < faces; i++)
      FaceCullSignal(
        faceId: 'f$i',
        area: 0.05 - i * 0.001,
        sharpness: sharp,
        earRight: ear,
        earLeft: ear,
      ),
  ],
);
