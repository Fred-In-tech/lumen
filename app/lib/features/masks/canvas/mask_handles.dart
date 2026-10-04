import 'dart:math' as math;
import 'dart:ui';

import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/features/editor/canvas_mapping.dart';

/// What dragging a handle does.
enum HandleRole {
  linearStart,
  linearEnd,
  linearMove,
  radialMove,
  radialRx,
  radialRxNeg,
  radialRy,
  radialRyNeg,
  radialRotate,
  radialFeather,

  /// Another mask's pin: tap to select it.
  pin;

  bool get moves => this == linearMove || this == radialMove;

  /// History verb for a finished drag.
  String get verb => switch (this) {
    linearMove || radialMove => 'Move',
    radialRx || radialRxNeg || radialRy || radialRyNeg => 'Resize',
    radialRotate => 'Rotate',
    radialFeather => 'Feather',
    linearStart || linearEnd || pin => 'Shape',
  };
}

/// A draggable point in view coordinates.
class MaskHandle {
  const MaskHandle(this.role, this.at, {this.maskId});

  final HandleRole role;
  final Offset at;

  /// Set for [HandleRole.pin]: the mask the pin selects.
  final String? maskId;
}

/// A linear gradient on screen: full effect at [a], none at [b], three
/// guide lines perpendicular to a→b (Lightroom style).
class LinearGuide {
  LinearGuide._(this.a, this.b, this.normal);

  factory LinearGuide.of(LinearShape s, CanvasMapping map) {
    final a = map.toView(s.x0, s.y0), b = map.toView(s.x1, s.y1);
    final d = b - a;
    final len = d.distance;
    // Perpendicular to a→b in view space (= in source pixel space, since
    // the mapping is a similarity).
    final n = len < 1e-9 ? const Offset(1, 0) : Offset(-d.dy / len, d.dx / len);
    return LinearGuide._(a, b, n);
  }

  final Offset a;
  final Offset b;

  /// Unit vector along the guide lines.
  final Offset normal;

  Offset get mid => (a + b) / 2;

  /// The guide line through `a + t·(b − a)`, [half] pixels each way.
  (Offset, Offset) lineAt(double t, double half) {
    final c = a + (b - a) * t;
    return (c - normal * half, c + normal * half);
  }
}

/// A radial gradient on screen: [center] and the two semi-axis vectors
/// ([xAxis] along the shape's angle). The inner (solid) ellipse is scaled
/// by `1 − feather`.
class RadialGuide {
  RadialGuide._(this.center, this.xAxis, this.yAxis, this.feather);

  factory RadialGuide.of(RadialShape s, CanvasMapping map) {
    final src = map.source;
    final a = s.angle * math.pi / 180;
    final ca = math.cos(a), sa = math.sin(a);
    final c = map.toView(s.cx, s.cy);
    // Axis endpoints in source pixels → uv → view.
    final xr = s.rx * src.width, yr = s.ry * src.height;
    final x = map.toView(
      s.cx + xr * ca / src.width,
      s.cy + xr * sa / src.height,
    );
    final y = map.toView(
      s.cx - yr * sa / src.width,
      s.cy + yr * ca / src.height,
    );
    return RadialGuide._(c, x - c, y - c, s.feather);
  }

  final Offset center;
  final Offset xAxis;
  final Offset yAxis;
  final double feather;

  double get rotation => math.atan2(xAxis.dy, xAxis.dx);
  double get rx => xAxis.distance;
  double get ry => yAxis.distance;

  /// Point at parameter [t] (radians) on the ellipse scaled by [k].
  Offset point(double t, [double k = 1]) =>
      center + xAxis * (k * math.cos(t)) + yAxis * (k * math.sin(t));

  /// Unit vector from the centre towards the −y axis handle.
  Offset get up {
    final d = ry;
    return d < 1e-9 ? const Offset(0, -1) : -yAxis / d;
  }
}

/// Everything the mask canvas draws and hit-tests for one frame.
class MaskScene {
  MaskScene._(this.linear, this.radial, this.handles, this.pins);

  factory MaskScene.build(
    List<LocalMask> masks,
    LocalMask? selected,
    CanvasMapping map, {
    required bool touch,
  }) {
    LinearGuide? linear;
    RadialGuide? radial;
    final handles = <MaskHandle>[];
    if (selected != null && selected.isSupported) {
      switch (selected.kind) {
        case MaskKind.linear:
          final g = linear = LinearGuide.of(selected.linear, map);
          handles.addAll([
            MaskHandle(HandleRole.linearMove, g.mid),
            MaskHandle(HandleRole.linearStart, g.a),
            MaskHandle(HandleRole.linearEnd, g.b),
          ]);
        case MaskKind.radial:
          final g = radial = RadialGuide.of(selected.radial, map);
          handles.addAll([
            MaskHandle(HandleRole.radialMove, g.center),
            MaskHandle(HandleRole.radialRx, g.center + g.xAxis),
            MaskHandle(HandleRole.radialRxNeg, g.center - g.xAxis),
            MaskHandle(HandleRole.radialRy, g.center + g.yAxis),
            MaskHandle(HandleRole.radialRyNeg, g.center - g.yAxis),
            MaskHandle(HandleRole.radialRotate, rotateKnob(g, touch: touch)),
            MaskHandle(HandleRole.radialFeather, featherKnob(g, touch: touch)),
          ]);
        case _:
          break;
      }
    }
    final pins = <MaskHandle>[
      for (final m in masks)
        if (m.id != selected?.id && m.isSupported)
          if (pinOf(m, map) case final p?)
            MaskHandle(HandleRole.pin, p, maskId: m.id),
    ];
    return MaskScene._(linear, radial, handles, pins);
  }

  final LinearGuide? linear;
  final RadialGuide? radial;
  final List<MaskHandle> handles;
  final List<MaskHandle> pins;

  /// The topmost handle within [radius] of [p] (nearest wins), else a pin.
  MaskHandle? hit(Offset p, double radius) =>
      nearest(handles, p, radius) ?? nearest(pins, p, radius);
}

/// Distance of the rotate knob beyond the −y handle.
double rotateKnobOffset({required bool touch}) => touch ? 44 : 28;

Offset rotateKnob(RadialGuide g, {required bool touch}) =>
    g.center + g.up * (g.ry + rotateKnobOffset(touch: touch));

/// The feather knob sits on the inner ellipse at 45°, kept clear of the
/// centre handle so both stay grabbable.
Offset featherKnob(RadialGuide g, {required bool touch}) {
  const t = math.pi / 4;
  final outer = (g.point(t) - g.center).distance;
  final minPx = touch ? 48.0 : 26.0;
  final k = outer < 1e-9 ? 0.0 : math.max(1 - g.feather, minPx / outer);
  return g.point(t, math.min(k, 1));
}

/// Where another mask's selection pin sits, or null (AI, empty brush).
Offset? pinOf(LocalMask m, CanvasMapping map) => switch (m.kind) {
  MaskKind.linear => LinearGuide.of(m.linear, map).mid,
  MaskKind.radial => map.toView(m.radial.cx, m.radial.cy),
  MaskKind.brush
      when m.strokes.isNotEmpty && m.strokes.first.points.isNotEmpty =>
    map.toView(
      m.strokes.first.points.first.$1,
      m.strokes.first.points.first.$2,
    ),
  _ => null,
};

MaskHandle? nearest(List<MaskHandle> hs, Offset p, double radius) {
  MaskHandle? best;
  var bestD = radius;
  for (final h in hs) {
    final d = (h.at - p).distance;
    if (d <= bestD) {
      best = h;
      bestD = d;
    }
  }
  return best;
}

/// The new shape JSON after dragging [role] from [startUv] to [curUv]
/// (source uv). Every edit is relative to the drag start, so grabbing a
/// handle off-centre never makes it jump. [source] is the source pixel
/// size (radii and angles live in source pixel space).
Map<String, Object?> dragShape(
  HandleRole role,
  MaskKind kind,
  Map<String, Object?> startShape,
  (double, double) startUv,
  (double, double) curUv,
  Size source,
) {
  final du = curUv.$1 - startUv.$1, dv = curUv.$2 - startUv.$2;
  if (kind == MaskKind.linear) {
    final s = LinearShape.fromJson(startShape);
    final moveA = role == HandleRole.linearStart || role.moves;
    final moveB = role == HandleRole.linearEnd || role.moves;
    return LinearShape(
      x0: s.x0 + (moveA ? du : 0),
      y0: s.y0 + (moveA ? dv : 0),
      x1: s.x1 + (moveB ? du : 0),
      y1: s.y1 + (moveB ? dv : 0),
    ).toJson();
  }
  if (kind != MaskKind.radial) return startShape;
  final s = RadialShape.fromJson(startShape);
  final w = source.width, h = source.height;
  final a = s.angle * math.pi / 180;
  final ax = Offset(math.cos(a), math.sin(a)); // x axis, source pixels
  final ay = Offset(-math.sin(a), math.cos(a)); // y axis
  final c = Offset(s.cx * w, s.cy * h);
  final p0 = Offset(startUv.$1 * w, startUv.$2 * h);
  final p1 = Offset(curUv.$1 * w, curUv.$2 * h);
  double dot(Offset u, Offset v) => u.dx * v.dx + u.dy * v.dy;
  const minRadiusPx = 2.0;
  RadialShape out;
  switch (role) {
    case HandleRole.radialMove:
      out = _radial(s, cx: s.cx + du, cy: s.cy + dv);
    case HandleRole.radialRx || HandleRole.radialRxNeg:
      final sign = role == HandleRole.radialRx ? 1.0 : -1.0;
      final r = s.rx * w + sign * dot(p1 - p0, ax);
      out = _radial(s, rx: math.max(r, minRadiusPx) / w);
    case HandleRole.radialRy || HandleRole.radialRyNeg:
      final sign = role == HandleRole.radialRy ? 1.0 : -1.0;
      final r = s.ry * h + sign * dot(p1 - p0, ay);
      out = _radial(s, ry: math.max(r, minRadiusPx) / h);
    case HandleRole.radialRotate:
      final d0 = p0 - c, d1 = p1 - c;
      final turn = math.atan2(d1.dy, d1.dx) - math.atan2(d0.dy, d0.dx);
      out = _radial(
        s,
        angle: _normalizeDegrees(s.angle + turn * 180 / math.pi),
      );
    case HandleRole.radialFeather:
      double e(Offset p) {
        final q = p - c;
        final qx = dot(q, ax) / math.max(s.rx * w, 1e-9);
        final qy = dot(q, ay) / math.max(s.ry * h, 1e-9);
        return math.sqrt(qx * qx + qy * qy);
      }
      final inner = (1 - s.feather) + e(p1) - e(p0);
      out = _radial(s, feather: (1 - inner).clamp(0.0, 1.0));
    case _:
      out = s;
  }
  return out.toJson();
}

RadialShape _radial(
  RadialShape s, {
  double? cx,
  double? cy,
  double? rx,
  double? ry,
  double? angle,
  double? feather,
}) => RadialShape(
  cx: cx ?? s.cx,
  cy: cy ?? s.cy,
  rx: rx ?? s.rx,
  ry: ry ?? s.ry,
  angle: angle ?? s.angle,
  feather: feather ?? s.feather,
  inverted: s.inverted,
);

double _normalizeDegrees(double d) {
  var x = d % 360;
  if (x > 180) x -= 360;
  if (x <= -180) x += 360;
  return x;
}
