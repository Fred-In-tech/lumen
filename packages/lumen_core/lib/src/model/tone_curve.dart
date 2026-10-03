import 'dart:math' as math;

import 'package:collection/collection.dart';

/// A tone-curve control point in 0..255 space.
class CurvePoint {
  const CurvePoint(this.x, this.y);

  final double x;
  final double y;

  @override
  bool operator ==(Object other) =>
      other is CurvePoint && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);

  List<double> toJson() => [x, y];
}

/// Monotone cubic (Fritsch–Carlson) point curve, 2–16 points, x strictly increasing.
class ToneCurve {
  const ToneCurve(this.points);

  /// Sorts, clamps to 0..255, removes duplicate x (first wins), caps at 16 points.
  factory ToneCurve.normalized(List<CurvePoint> raw) {
    final clamped =
        raw
            .map(
              (p) => CurvePoint(
                p.x.clamp(0, 255).toDouble(),
                p.y.clamp(0, 255).toDouble(),
              ),
            )
            .toList()
          ..sort((a, b) => a.x.compareTo(b.x));
    final out = <CurvePoint>[];
    for (final p in clamped) {
      if (out.isEmpty || p.x - out.last.x > 1e-6) out.add(p);
    }
    while (out.length > kMaxPoints) {
      out.removeAt(out.length ~/ 2);
    }
    if (out.length < 2) return identity;
    return ToneCurve(List.unmodifiable(out));
  }

  factory ToneCurve.fromJson(Object? json) {
    if (json is! List) return identity;
    final pts = <CurvePoint>[];
    for (final e in json) {
      if (e is List && e.length >= 2 && e[0] is num && e[1] is num) {
        pts.add(CurvePoint((e[0] as num).toDouble(), (e[1] as num).toDouble()));
      }
    }
    return ToneCurve.normalized(pts);
  }

  static const int kMaxPoints = 16;
  static const identity = ToneCurve([CurvePoint(0, 0), CurvePoint(255, 255)]);

  final List<CurvePoint> points;

  bool get isIdentity =>
      points.every((p) => (p.x - p.y).abs() < 1e-6) &&
      points.first.x == 0 &&
      points.last.x == 255;

  List<List<double>> toJson() => [for (final p in points) p.toJson()];

  /// Evaluate y(x) for x in 0..255 (clamped outside the point range).
  double evaluate(double x) {
    final pts = points;
    if (x <= pts.first.x) return pts.first.y;
    if (x >= pts.last.x) return pts.last.y;
    final n = pts.length;
    if (n == 2) {
      final t = (x - pts[0].x) / (pts[1].x - pts[0].x);
      return pts[0].y + t * (pts[1].y - pts[0].y);
    }
    final tangents = _tangents();
    var i = 0;
    while (i < n - 2 && x > pts[i + 1].x) {
      i++;
    }
    final p0 = pts[i], p1 = pts[i + 1];
    final h = p1.x - p0.x;
    final t = (x - p0.x) / h;
    final t2 = t * t, t3 = t2 * t;
    final h00 = 2 * t3 - 3 * t2 + 1;
    final h10 = t3 - 2 * t2 + t;
    final h01 = -2 * t3 + 3 * t2;
    final h11 = t3 - t2;
    final y =
        h00 * p0.y +
        h10 * h * tangents[i] +
        h01 * p1.y +
        h11 * h * tangents[i + 1];
    return y.clamp(0, 255).toDouble();
  }

  List<double> _tangents() {
    final pts = points;
    final n = pts.length;
    final d = List<double>.generate(
      n - 1,
      (i) => (pts[i + 1].y - pts[i].y) / (pts[i + 1].x - pts[i].x),
    );
    final m = List<double>.filled(n, 0);
    m[0] = d[0];
    m[n - 1] = d[n - 2];
    for (var i = 1; i < n - 1; i++) {
      m[i] = d[i - 1] * d[i] <= 0 ? 0 : (d[i - 1] + d[i]) / 2;
    }
    for (var i = 0; i < n - 1; i++) {
      if (d[i] == 0) {
        m[i] = 0;
        m[i + 1] = 0;
        continue;
      }
      final a = m[i] / d[i], b = m[i + 1] / d[i];
      final s = a * a + b * b;
      if (s > 9) {
        final tau = 3 / math.sqrt(s);
        m[i] = tau * a * d[i];
        m[i + 1] = tau * b * d[i];
      }
    }
    return m;
  }

  @override
  bool operator ==(Object other) =>
      other is ToneCurve &&
      const ListEquality<CurvePoint>().equals(points, other.points);

  @override
  int get hashCode => const ListEquality<CurvePoint>().hash(points);
}

enum CurveChannel { master, red, green, blue }

/// Master + per-channel point curves. Identity curves are stored as null in JSON.
class CurveSet {
  const CurveSet({
    this.master = ToneCurve.identity,
    this.red = ToneCurve.identity,
    this.green = ToneCurve.identity,
    this.blue = ToneCurve.identity,
  });

  factory CurveSet.fromJson(Object? json) {
    if (json is! Map) return identity;
    ToneCurve read(String k) =>
        json[k] == null ? ToneCurve.identity : ToneCurve.fromJson(json[k]);
    return CurveSet(
      master: read('master'),
      red: read('red'),
      green: read('green'),
      blue: read('blue'),
    );
  }

  static const identity = CurveSet();

  final ToneCurve master;
  final ToneCurve red;
  final ToneCurve green;
  final ToneCurve blue;

  bool get isIdentity =>
      master.isIdentity &&
      red.isIdentity &&
      green.isIdentity &&
      blue.isIdentity;

  ToneCurve channel(CurveChannel c) => switch (c) {
    CurveChannel.master => master,
    CurveChannel.red => red,
    CurveChannel.green => green,
    CurveChannel.blue => blue,
  };

  CurveSet withChannel(CurveChannel c, ToneCurve curve) => CurveSet(
    master: c == CurveChannel.master ? curve : master,
    red: c == CurveChannel.red ? curve : red,
    green: c == CurveChannel.green ? curve : green,
    blue: c == CurveChannel.blue ? curve : blue,
  );

  Map<String, Object?> toJson() => {
    for (final c in CurveChannel.values)
      c.name: channel(c).isIdentity ? null : channel(c).toJson(),
  };

  @override
  bool operator ==(Object other) =>
      other is CurveSet &&
      other.master == master &&
      other.red == red &&
      other.green == green &&
      other.blue == blue;

  @override
  int get hashCode => Object.hash(master, red, green, blue);
}
