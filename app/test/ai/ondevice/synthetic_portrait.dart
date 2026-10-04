import 'dart:math' as math;

import 'package:lumen_core/lumen_core.dart';

/// Where the drawn features are, in pixels (for assertions).
typedef PortraitLayout = ({
  double cx,
  double cy,
  double scale,
  (double, double) rightEye,
  (double, double) leftEye,
  (double, double) mouth,
});

/// A drawn, cartoon-like frontal face: hair, skin oval with shading, eyes
/// with sclera/iris/pupil, brows, nostrils, lips, neck and torso, softened
/// by a blur. No real person; exercises the real detector, mesh and
/// segmenter.
(RgbaBuffer, PortraitLayout) syntheticPortrait({
  int width = 640,
  int height = 480,
  double scale = 260,
}) {
  final (img, faces) = syntheticGroupPortrait(
    width: width,
    height: height,
    faces: [(width / 2, height / 2 + 10, scale)],
  );
  return (img, faces.single);
}

/// Several drawn faces ([faces] = centre x, centre y, scale in pixels).
(RgbaBuffer, List<PortraitLayout>) syntheticGroupPortrait({
  required int width,
  required int height,
  required List<(double, double, double)> faces,
}) {
  final img = RgbaBuffer(width, height);
  final layouts = [
    for (final (cx, cy, s) in faces)
      (
        cx: cx,
        cy: cy,
        scale: s,
        rightEye: (cx - 0.16 * s, cy - 0.06 * s),
        leftEye: (cx + 0.16 * s, cy - 0.06 * s),
        mouth: (cx, cy + 0.26 * s),
      ),
  ];
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final fx = x + 0.5, fy = y + 0.5;
      // Background: cool grey gradient.
      var c = (150 - y * 40 / height, 160 - y * 40 / height, 175.0);
      for (final l in layouts) {
        c = _paintFace(c, fx, fy, l);
      }
      img.setPixel(x, y, c.$1.round(), c.$2.round(), c.$3.round());
    }
  }
  final s = faces.map((f) => f.$3).reduce(math.max);
  _blur(img, math.max(1, (s / 120).round()));
  return (img, layouts);
}

bool _inEllipse(
  double x,
  double y,
  double ex,
  double ey,
  double rx,
  double ry,
) {
  final dx = (x - ex) / rx, dy = (y - ey) / ry;
  return dx * dx + dy * dy <= 1;
}

typedef _Rgb = (double, double, double);

_Rgb _paintFace(_Rgb c, double fx, double fy, PortraitLayout l) {
  final cx = l.cx, cy = l.cy, s = l.scale;
  if ((fx - cx).abs() > 1.0 * s || fy < cy - 0.7 * s) return c;
  var (r, g, b) = c;
  if (fy > cy + 0.62 * s && (fx - cx).abs() < 0.9 * s) {
    (r, g, b) = (70, 90, 130); // shirt
  }
  if (_inEllipse(fx, fy, cx, cy - 0.12 * s, 0.46 * s, 0.56 * s)) {
    (r, g, b) = (60, 40, 28); // hair
  }
  if (fy > cy + 0.3 * s && fy <= cy + 0.62 * s && (fx - cx).abs() < 0.17 * s) {
    (r, g, b) = (205, 150, 120); // neck
  }
  if (_inEllipse(fx, fy, cx, cy, 0.36 * s, 0.48 * s)) {
    final dx = (fx - cx) / (0.36 * s), dy = (fy - cy) / (0.48 * s);
    final shade = 1 - 0.18 * (dx * dx + dy * dy);
    (r, g, b) = (228 * shade, 176 * shade, 146 * shade);
    if ((fx - cx).abs() < 0.035 * s && fy > cy && fy < cy + 0.13 * s) {
      (r, g, b) = (r * 0.9, g * 0.88, b * 0.88); // nose shadow
    }
  }
  for (final e in [l.rightEye, l.leftEye]) {
    if (_inEllipse(fx, fy, e.$1, e.$2 - 0.09 * s, 0.08 * s, 0.018 * s)) {
      (r, g, b) = (70, 48, 34); // brow
    }
    if (_inEllipse(fx, fy, e.$1, e.$2, 0.075 * s, 0.035 * s)) {
      (r, g, b) = (240, 238, 232); // sclera
      if (_inEllipse(fx, fy, e.$1, e.$2, 0.032 * s, 0.032 * s)) {
        (r, g, b) = (90, 60, 40); // iris
      }
      if (_inEllipse(fx, fy, e.$1, e.$2, 0.013 * s, 0.013 * s)) {
        (r, g, b) = (15, 10, 10); // pupil
      }
    }
  }
  for (final side in [-1, 1]) {
    final nx = cx + side * 0.03 * s;
    if (_inEllipse(fx, fy, nx, cy + 0.14 * s, 0.018 * s, 0.01 * s)) {
      (r, g, b) = (120, 70, 60); // nostril
    }
  }
  final m = l.mouth;
  if (_inEllipse(fx, fy, m.$1, m.$2, 0.11 * s, 0.03 * s)) {
    (r, g, b) = (185, 80, 90); // lips
    if ((fy - m.$2).abs() < 0.004 * s) (r, g, b) = (110, 40, 50);
  }
  return (r, g, b);
}

/// Two passes of a separable box blur (running sums, O(1) per pixel).
void _blur(RgbaBuffer img, int radius) {
  for (var pass = 0; pass < 2; pass++) {
    _boxPass(img, radius, horizontal: true);
    _boxPass(img, radius, horizontal: false);
  }
}

void _boxPass(RgbaBuffer img, int r, {required bool horizontal}) {
  final w = img.width, h = img.height, d = img.data;
  final lines = horizontal ? h : w, len = horizontal ? w : h;
  final buf = List<int>.filled(len * 3, 0);
  for (var line = 0; line < lines; line++) {
    int at(int i) => horizontal ? (line * w + i) * 4 : (i * w + line) * 4;
    for (var i = 0; i < len; i++) {
      final o = at(i);
      buf[i * 3] = d[o];
      buf[i * 3 + 1] = d[o + 1];
      buf[i * 3 + 2] = d[o + 2];
    }
    var sr = 0, sg = 0, sb = 0;
    for (var i = -r; i <= r; i++) {
      final k = i.clamp(0, len - 1) * 3;
      sr += buf[k];
      sg += buf[k + 1];
      sb += buf[k + 2];
    }
    final n = 2 * r + 1;
    for (var i = 0; i < len; i++) {
      final o = at(i);
      d[o] = sr ~/ n;
      d[o + 1] = sg ~/ n;
      d[o + 2] = sb ~/ n;
      final add = (i + r + 1).clamp(0, len - 1) * 3;
      final sub = (i - r).clamp(0, len - 1) * 3;
      sr += buf[add] - buf[sub];
      sg += buf[add + 1] - buf[sub + 1];
      sb += buf[add + 2] - buf[sub + 2];
    }
  }
}
