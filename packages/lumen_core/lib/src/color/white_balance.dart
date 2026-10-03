import 'dart:math' as math;

import '../render/engine_constants.dart';

/// Per-channel linear-light gains for white balance.
class WbGains {
  const WbGains(this.r, this.g, this.b);

  static const neutral = WbGains(1, 1, 1);

  final double r;
  final double g;
  final double b;

  @override
  String toString() => 'WbGains($r, $g, $b)';
}

/// Relative temp/tint (−100…100) → linear RGB gains (research 01 §6.2):
/// `R·2^(+κt·t/200)`, `B·2^(−κt·t/200)`, `G·2^(−κg·τ/100)`.
///
/// Positive temp warms, positive tint is magenta.
WbGains whiteBalanceGains(double temp, double tint) {
  final t = temp.clamp(-100, 100).toDouble();
  final tau = tint.clamp(-100, 100).toDouble();
  if (t == 0 && tau == 0) return WbGains.neutral;
  final rb = kWbKappaT * t / 200;
  return WbGains(
    math.pow(2, rb).toDouble(),
    math.pow(2, -kWbKappaG * tau / 100).toDouble(),
    math.pow(2, -rb).toDouble(),
  );
}
