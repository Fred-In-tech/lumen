/// One async GPU value at a time, rebuilt when its key changes (the
/// MaskAtlasCache / RetouchMapsCache pattern, generic).
///
/// * `obtain(key, build)`: the value for [key]; concurrent callers with the
///   same key (by [same]) share one build. A replaced value is released
///   only after its replacement is ready, so frames recorded with it stay
///   valid. A null value (nothing to build) is allowed.
/// * `builds`: number of builds (cache diagnostics, tests).
/// * `dispose()`: synchronous when the value already resolved.
library;

class SwapCache<K, V extends Object> {
  SwapCache({required this.same, required this.release});

  final bool Function(K a, K b) same;
  final void Function(V value) release;

  K? _key;
  Future<V?>? _current;
  V? _ready;
  bool _disposed = false;
  int _builds = 0;

  int get builds => _builds;

  Future<V?> obtain(K key, Future<V?> Function() build) {
    if (_disposed) throw StateError('SwapCache disposed');
    final current = _current;
    if (current != null && same(key, _key as K)) return current;
    _key = key;
    _ready = null;
    _builds++;
    final next = build();
    _current = next;
    next.then((v) {
      if (identical(_current, next)) _ready = v;
    }, onError: (Object _) {}).ignore();
    if (current != null) {
      next
          .whenComplete(() => current.then(_release, onError: (Object _) {}))
          .ignore();
    }
    return next;
  }

  void _release(V? v) {
    if (v != null) release(v);
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    final ready = _ready;
    if (ready != null) {
      release(ready);
    } else {
      _current?.then(_release, onError: (Object _) {}).ignore();
    }
    _current = null;
    _ready = null;
  }
}
