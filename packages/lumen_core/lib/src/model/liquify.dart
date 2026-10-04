/// Manual liquify strokes (Phase 2b warp). Stored in `DevelopSettings.liquify`
/// as vectors and replayed deterministically into the warp field
/// (`warp/liquify.dart`). Never part of presets; paste group "Liquify".
library;

import 'package:collection/collection.dart';

/// push = forward warp (content follows the brush), reconstruct = brush the
/// field back toward identity, pucker = shrink toward the brush centre,
/// bloat = magnify.
enum LiquifyTool { push, reconstruct, pucker, bloat }

/// One brush stroke in normalized source uv. [radius] is a fraction of the
/// source long edge (0.002..0.5), [strength] 0..1.
class LiquifyStroke {
  const LiquifyStroke({
    required this.tool,
    required this.points,
    required this.radius,
    this.strength = 0.5,
  });

  /// Null for unknown tools or malformed JSON.
  static LiquifyStroke? fromJson(Object? json) {
    if (json is! Map) return null;
    final tool = LiquifyTool.values.where((t) => t.name == json['tool']);
    if (tool.isEmpty) return null;
    final pts = <(double, double)>[];
    final raw = json['points'];
    if (raw is List) {
      for (final p in raw) {
        if (p is List && p.length >= 2 && p[0] is num && p[1] is num) {
          pts.add((
            (p[0] as num).toDouble().clamp(0.0, 1.0),
            (p[1] as num).toDouble().clamp(0.0, 1.0),
          ));
        }
      }
    }
    double num_(String k, double d) =>
        json[k] is num ? (json[k] as num).toDouble() : d;
    return LiquifyStroke(
      tool: tool.first,
      points: List.unmodifiable(pts),
      radius: num_('radius', 0.05).clamp(0.002, 0.5),
      strength: num_('strength', 0.5).clamp(0.0, 1.0),
    );
  }

  final LiquifyTool tool;
  final List<(double, double)> points;
  final double radius;
  final double strength;

  /// A copy with [p] appended (live strokes grow point by point).
  LiquifyStroke withPoint((double, double) p) => LiquifyStroke(
    tool: tool,
    points: List.unmodifiable([...points, p]),
    radius: radius,
    strength: strength,
  );

  Map<String, Object?> toJson() => {
    'tool': tool.name,
    'points': [
      for (final p in points) [p.$1, p.$2],
    ],
    'radius': radius,
    'strength': strength,
  };

  @override
  bool operator ==(Object other) =>
      other is LiquifyStroke &&
      other.tool == tool &&
      other.radius == radius &&
      other.strength == strength &&
      const ListEquality<(double, double)>().equals(other.points, points);

  @override
  int get hashCode => Object.hash(
    tool,
    radius,
    strength,
    const ListEquality<(double, double)>().hash(points),
  );
}

/// Parses a JSON list of strokes, skipping invalid entries.
List<LiquifyStroke> parseLiquify(Object? json) => json is List
    ? List.unmodifiable(json.map(LiquifyStroke.fromJson).nonNulls)
    : const [];
