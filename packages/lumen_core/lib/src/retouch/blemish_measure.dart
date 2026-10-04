/// Per-spot measurements for blemish detection (research 07 §3.3 step 4).
library;

import 'dart:math' as math;
import 'dart:typed_data';

/// Visible radius = this × the half-maximum radius (2σ of a Gaussian spot).
const double kRadiusPerHalfMax = 1.7;

/// A spot whose darkest (or reddest) ring sector stands out from the
/// median sector by more than this fraction of the spot's own contrast
/// continues into a larger structure (a line end, a fold): not a blemish.
const double kMaxSectorContrast = 0.5;

const int _sectors = 8;

/// Spot statistics in the normalized crop.
typedef SpotMeasure = ({
  double depthL,
  double deltaA,
  double deltaB,
  double radius,
  bool isolated,
});

/// Measures the spot at `(x, y)` whose DoG scale suggests radius [rS]
/// (pixels). [red] selects a* (red spot) instead of L (dark spot) as the
/// channel that defines its profile. Returns null without enough ring.
SpotMeasure? measureSpot(
  Float32List l,
  Float32List a,
  Float32List b,
  Float32List valid,
  int w,
  int h,
  int x,
  int y,
  double rS, {
  required bool red,
}) {
  final rc = math.max(1.0, 0.5 * rS), r0 = 1.5 * rS, r1 = 2.5 * rS;
  final rMax = 2 * rS;
  final kMax = rMax.ceil() + 1;
  final annSum = Float64List(kMax + 1), annN = Int32List(kMax + 1);
  final secSum = Float64List(_sectors), secN = Int32List(_sectors);
  var cl = 0.0, ca = 0.0, cb = 0.0, cn = 0;
  var ol = 0.0, oa = 0.0, ob = 0.0, on = 0;
  final ext = r1.ceil();
  for (var yy = math.max(0, y - ext); yy <= math.min(h - 1, y + ext); yy++) {
    for (var xx = math.max(0, x - ext); xx <= math.min(w - 1, x + ext); xx++) {
      final dx = (xx - x).toDouble(), dy = (yy - y).toDouble();
      final d = math.sqrt(dx * dx + dy * dy);
      final i = yy * w + xx;
      final v = red ? a[i] : l[i];
      if (d <= rc) {
        cl += l[i];
        ca += a[i];
        cb += b[i];
        cn++;
      }
      if (d <= rMax) {
        final k = d.round();
        annSum[k] += v;
        annN[k]++;
      }
      if (d >= r0 && d <= r1 && valid[i] > 0) {
        ol += l[i];
        oa += a[i];
        ob += b[i];
        on++;
        final s = _octant(dx, dy);
        secSum[s] += v;
        secN[s]++;
      }
    }
  }
  if (cn == 0 || on < 4) return null;
  final bg = red ? oa / on : ol / on;
  double contrast(double mean) => red ? mean - bg : bg - mean;
  // Half-maximum radius of the radial profile.
  final peak = contrast(
    (annSum[0] + annSum[1]) / math.max(1, annN[0] + annN[1]),
  );
  var radius = 1.6 * rS;
  if (peak > 0) {
    var prev = peak;
    for (var k = 1; k <= kMax; k++) {
      if (annN[k] == 0) continue;
      final c = contrast(annSum[k] / annN[k]);
      if (c < 0.5 * peak) {
        final t = prev > c ? (prev - 0.5 * peak) / (prev - c) : 0.0;
        radius = (kRadiusPerHalfMax * (k - 1 + t)).clamp(0.6 * rS, 1.6 * rS);
        break;
      }
      prev = c;
    }
  }
  // Isolation: no ring sector much darker (redder) than the median one.
  final means = <double>[
    for (var s = 0; s < _sectors; s++)
      if (secN[s] >= 2) contrast(secSum[s] / secN[s]),
  ]..sort();
  final isolated =
      means.length < 3 ||
      means.last - means[means.length ~/ 2] <=
          kMaxSectorContrast * math.max(peak, 0.0);
  return (
    depthL: ol / on - cl / cn,
    deltaA: ca / cn - oa / on,
    deltaB: cb / cn - ob / on,
    radius: radius,
    isolated: isolated,
  );
}

/// Octant 0..7 of the direction `(dx, dy)` without trigonometry.
int _octant(double dx, double dy) {
  final ax = dx.abs(), ay = dy.abs();
  final steep = ay > ax ? 1 : 0;
  if (dx >= 0) {
    return dy >= 0 ? steep : 7 - steep;
  }
  return dy >= 0 ? 3 - steep : 4 + steep;
}
