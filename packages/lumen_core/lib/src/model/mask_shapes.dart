/// Typed views of `LocalMask.shape` and brush strokes. All positions are
/// normalized source uv (0..1); brush radii are fractions of the source long
/// edge.
library;

import 'package:collection/collection.dart';

double _num(Map<String, Object?> j, String k, double d) =>
    (j[k] is num) ? (j[k] as num).toDouble() : d;

/// Linear gradient: full effect at (x0, y0), fading to none at (x1, y1).
class LinearShape {
  const LinearShape({this.x0 = 0.5, this.y0 = 0, this.x1 = 0.5, this.y1 = 0.5});

  factory LinearShape.fromJson(Map<String, Object?> j) => LinearShape(
    x0: _num(j, 'x0', 0.5),
    y0: _num(j, 'y0', 0),
    x1: _num(j, 'x1', 0.5),
    y1: _num(j, 'y1', 0.5),
  );

  final double x0;
  final double y0;
  final double x1;
  final double y1;

  Map<String, Object?> toJson() => {'x0': x0, 'y0': y0, 'x1': x1, 'y1': y1};
}

/// Elliptical gradient. [rx]/[ry] are radii as fractions of the source
/// width/height, [angle] in degrees (rotation in pixel space), [feather]
/// 0..1 is the soft fraction of the radius. [inverted] puts the effect
/// outside the ellipse.
class RadialShape {
  const RadialShape({
    this.cx = 0.5,
    this.cy = 0.5,
    this.rx = 0.25,
    this.ry = 0.25,
    this.angle = 0,
    this.feather = 0.5,
    this.inverted = false,
  });

  factory RadialShape.fromJson(Map<String, Object?> j) => RadialShape(
    cx: _num(j, 'cx', 0.5),
    cy: _num(j, 'cy', 0.5),
    rx: _num(j, 'rx', 0.25),
    ry: _num(j, 'ry', 0.25),
    angle: _num(j, 'angle', 0),
    feather: _num(j, 'feather', 0.5).clamp(0.0, 1.0),
    inverted: j['inverted'] == true,
  );

  final double cx;
  final double cy;
  final double rx;
  final double ry;
  final double angle;
  final double feather;
  final bool inverted;

  Map<String, Object?> toJson() => {
    'cx': cx,
    'cy': cy,
    'rx': rx,
    'ry': ry,
    'angle': angle,
    'feather': feather,
    'inverted': inverted,
  };
}

/// AI raster mask: an 8-bit PNG at [maskRef] (relative to `assets/<id>/`).
class AiShape {
  const AiShape({this.maskRef = '', this.model = '', this.modelVersion = ''});

  factory AiShape.fromJson(Map<String, Object?> j) => AiShape(
    maskRef: j['maskRef'] is String ? j['maskRef'] as String : '',
    model: j['model'] is String ? j['model'] as String : '',
    modelVersion: j['modelVersion'] is String
        ? j['modelVersion'] as String
        : '',
  );

  final String maskRef;
  final String model;
  final String modelVersion;

  Map<String, Object?> toJson() => {
    'maskRef': maskRef,
    'model': model,
    'modelVersion': modelVersion,
  };
}

/// One brush stroke: a polyline of uv [points] painted with a round brush.
/// [radius] is a fraction of the source long edge, [hardness] 0..1 is the
/// solid fraction of the radius, [flow] 0..1 the stroke strength; [erase]
/// removes coverage instead of adding it.
class BrushStroke {
  const BrushStroke({
    required this.points,
    required this.radius,
    this.hardness = 0.5,
    this.flow = 1,
    this.erase = false,
  });

  factory BrushStroke.fromJson(Map<String, Object?> j) {
    final pts = <(double, double)>[];
    final raw = j['points'];
    if (raw is List) {
      for (final p in raw) {
        if (p is List && p.length >= 2 && p[0] is num && p[1] is num) {
          pts.add(((p[0] as num).toDouble(), (p[1] as num).toDouble()));
        }
      }
    }
    return BrushStroke(
      points: List.unmodifiable(pts),
      radius: _num(j, 'radius', 0.02).clamp(0.0005, 1.0),
      hardness: _num(j, 'hardness', 0.5).clamp(0.0, 1.0),
      flow: _num(j, 'flow', 1).clamp(0.0, 1.0),
      erase: j['erase'] == true,
    );
  }

  final List<(double, double)> points;
  final double radius;
  final double hardness;
  final double flow;
  final bool erase;

  Map<String, Object?> toJson() => {
    'points': [
      for (final p in points) [p.$1, p.$2],
    ],
    'radius': radius,
    'hardness': hardness,
    'flow': flow,
    'erase': erase,
  };

  @override
  bool operator ==(Object other) =>
      other is BrushStroke &&
      const ListEquality<(double, double)>().equals(other.points, points) &&
      other.radius == radius &&
      other.hardness == hardness &&
      other.flow == flow &&
      other.erase == erase;

  @override
  int get hashCode => Object.hash(
    const ListEquality<(double, double)>().hash(points),
    radius,
    hardness,
    flow,
    erase,
  );
}
