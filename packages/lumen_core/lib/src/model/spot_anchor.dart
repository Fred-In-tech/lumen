/// A user decision about one skin spot, stored by position (normalized source
/// uv + radius in IOD units) because detected candidate ids are not stable
/// across re-analysis at another resolution.
class SpotAnchor {
  const SpotAnchor(this.u, this.v, this.radiusIod);

  /// Lenient parse; null for malformed entries.
  static SpotAnchor? tryFromJson(Object? json) {
    if (json is! Map) return null;
    final u = json['u'], v = json['v'], r = json['r'];
    if (u is! num || v is! num || r is! num) return null;
    if (!u.isFinite || !v.isFinite || !r.isFinite || r <= 0) return null;
    return SpotAnchor(u.toDouble(), v.toDouble(), r.toDouble());
  }

  factory SpotAnchor.fromJson(Map<String, Object?> json) =>
      tryFromJson(json) ?? (throw FormatException('Bad spot anchor: $json'));

  final double u;
  final double v;
  final double radiusIod;

  /// Rounded to 1e-5 of the image side and 1e-3 IOD.
  Map<String, Object?> toJson() => {
    'u': _round(u, 1e5),
    'v': _round(v, 1e5),
    'r': _round(radiusIod, 1e3),
  };

  static double _round(double x, double scale) => (x * scale).round() / scale;

  @override
  bool operator ==(Object other) =>
      other is SpotAnchor &&
      other.u == u &&
      other.v == v &&
      other.radiusIod == radiusIod;

  @override
  int get hashCode => Object.hash(u, v, radiusIod);
}

/// Per-photo spot decisions: [keep] spots are never healed, [remove] spots
/// always are (even with every slider at 0). Image-specific: never part of
/// presets, and paste keeps the target's own decisions.
class PortraitSpots {
  const PortraitSpots({this.keep = const [], this.remove = const []});

  factory PortraitSpots.fromJson(Object? json) {
    if (json is! Map) return none;
    List<SpotAnchor> read(Object? list) => List.unmodifiable(
      (list is List ? list : const <Object?>[])
          .map(SpotAnchor.tryFromJson)
          .whereType<SpotAnchor>(),
    );
    return PortraitSpots(
      keep: read(json['keep']),
      remove: read(json['remove']),
    );
  }

  static const none = PortraitSpots();

  final List<SpotAnchor> keep;
  final List<SpotAnchor> remove;

  bool get isEmpty => keep.isEmpty && remove.isEmpty;

  /// Marks the spot at [a] as kept (drops any removal of the same anchor).
  PortraitSpots withKeep(SpotAnchor a) => PortraitSpots(
    keep: List.unmodifiable([...keep.where((k) => k != a), a]),
    remove: List.unmodifiable(remove.where((r) => r != a)),
  );

  /// Marks the spot at [a] for removal (drops any keep of the same anchor).
  PortraitSpots withRemove(SpotAnchor a) => PortraitSpots(
    keep: List.unmodifiable(keep.where((k) => k != a)),
    remove: List.unmodifiable([...remove.where((r) => r != a), a]),
  );

  /// Forgets any decision about [a] (back to the sliders).
  PortraitSpots without(SpotAnchor a) => PortraitSpots(
    keep: List.unmodifiable(keep.where((k) => k != a)),
    remove: List.unmodifiable(remove.where((r) => r != a)),
  );

  Map<String, Object?> toJson() => {
    'keep': [for (final a in keep) a.toJson()],
    'remove': [for (final a in remove) a.toJson()],
  };

  @override
  bool operator ==(Object other) =>
      other is PortraitSpots &&
      _listEq(other.keep, keep) &&
      _listEq(other.remove, remove);

  @override
  int get hashCode => Object.hash(Object.hashAll(keep), Object.hashAll(remove));

  static bool _listEq(List<SpotAnchor> a, List<SpotAnchor> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
