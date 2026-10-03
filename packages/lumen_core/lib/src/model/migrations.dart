/// Edit-document schema migrations: version n → n+1, applied in order.
///
/// v0 (pre-release prototype) stored scalar values directly under `settings`.
Map<String, Object?> migrateEditJson(Map<String, Object?> json) {
  var out = Map<String, Object?>.of(json);
  var version = (out['schemaVersion'] as num?)?.toInt() ?? 1;
  while (version < 1) {
    out = _migrations[version]!(out);
    version++;
  }
  out['schemaVersion'] = version;
  return out;
}

final Map<int, Map<String, Object?> Function(Map<String, Object?>)>
_migrations = {
  0: (json) {
    final s = json['settings'];
    final settings = s is Map && !s.containsKey('values') ? {'values': s} : s;
    return {...json, 'settings': settings, 'engineVersion': 'lumen-1'};
  },
};
