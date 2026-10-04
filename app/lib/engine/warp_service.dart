/// Keeps the warp field of the open photo in step with its settings.
///
/// Public API:
/// * `WarpFieldService({sourceWidth, sourceHeight, onField, debounce, build})`
/// * `faces` (setter): the photo's `FaceAnalysis` (face-shape sliders need
///   it; liquify does not). Changing it rebuilds.
/// * `update(settings)`: call on every settings change.
///   - Face-shape changes rebuild the whole field off the UI isolate
///     (`build`, default `compute(buildWarpWithPrefix)`), debounced
///     [debounce] (80 ms); the previous field stays published meanwhile.
///   - Liquify strokes that extend the current list (a growing live stroke,
///     a new stroke, undo of the last one) are applied synchronously on top
///     of the cached prefix field: no isolate, no debounce.
///   - Other stroke edits rebuild at once (no debounce).
///   - Settings without warp edits publish `null` (warp off, bit-exact).
/// * `onField(WarpField?)` receives every new field (set it on the
///   `RenderGraph` and re-render).
/// * `field`: the last published field.
/// * `fieldFor(settings)`: the exact field for any settings (thumbnails);
///   identity when there is nothing to warp.
/// * `dispose()`.
library;

import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:lumen_core/lumen_core.dart';

typedef WarpBuild = Future<WarpBuildResult> Function(WarpRequest request);

Future<WarpBuildResult> _isolateBuild(WarpRequest r) =>
    compute(buildWarpWithPrefix, r);

class WarpFieldService {
  WarpFieldService({
    required this.sourceWidth,
    required this.sourceHeight,
    required this.onField,
    this.debounce = const Duration(milliseconds: 80),
    WarpBuild? build,
  }) : _build = build ?? _isolateBuild;

  final int sourceWidth;
  final int sourceHeight;
  final void Function(WarpField? field) onField;
  final Duration debounce;
  final WarpBuild _build;

  FaceAnalysis? _faces;
  DevelopSettings? _last;
  int? _shapeKey;
  WarpField? _prefix;
  List<LiquifyStroke> _prefixStrokes = const [];
  LiquifyLive? _live; // the last stroke, applied on [_prefix]
  WarpField? _field;
  List<LiquifyStroke> _fieldStrokes = const [];
  Timer? _timer;
  int _gen = 0;
  bool _disposed = false;

  static const _eq = ListEquality<LiquifyStroke>();

  WarpField? get field => _field;

  FaceAnalysis? get faces => _faces;

  set faces(FaceAnalysis? value) {
    if (identical(value, _faces)) return;
    _faces = value;
    _shapeKey = null;
    final last = _last;
    if (last != null) update(last);
  }

  void update(DevelopSettings s) {
    if (_disposed) return;
    _last = s;
    if (!hasWarpEdits(s, _faces)) {
      _cancel();
      _shapeKey = null;
      _prefix = null;
      _live = null;
      _publish(null, const []);
      return;
    }
    final key = warpShapeKey(s.portrait, _faces);
    if (key == _shapeKey && _prefix != null && _timer == null) {
      if (_advance(s.liquify)) return;
      _schedule(s, Duration.zero);
      return;
    }
    if (key == _shapeKey && _timer != null) return; // a build is coming
    _schedule(s, debounce);
  }

  /// Applies strokes that extend the cached prefix; false if they do not.
  /// A growing last stroke only costs its new dabs ([LiquifyLive]).
  bool _advance(List<LiquifyStroke> strokes) {
    if (_eq.equals(strokes, _fieldStrokes)) return true;
    final p = _prefixStrokes;
    final n = strokes.length;
    if (n < p.length || !_eq.equals(strokes.sublist(0, p.length), p)) {
      return false;
    }
    if (n == p.length) {
      _live = null;
      _publish(_prefix, strokes);
      return true;
    }
    var prefix = _prefix!;
    var live = _live;
    var i = p.length;
    if (i < n - 1) {
      // Strokes finished since the last update move into the prefix.
      if (live != null && live.canExtend(strokes[i])) {
        live.extend(strokes[i]);
        prefix = live.snapshot();
        i++;
      }
      for (; i < n - 1; i++) {
        prefix = _apply(prefix, [strokes[i]]);
      }
      live = null;
      _prefix = prefix;
      _prefixStrokes = List.unmodifiable(strokes.sublist(0, n - 1));
    }
    final last = strokes.last;
    if (live != null && live.canExtend(last)) {
      live.extend(last);
    } else {
      live = LiquifyLive(prefix, last);
    }
    _live = live;
    _publish(live.snapshot(), strokes);
    return true;
  }

  WarpField _apply(WarpField f, List<LiquifyStroke> strokes) =>
      applyLiquifyStrokes(
        f,
        strokes,
        sourceWidth: sourceWidth,
        sourceHeight: sourceHeight,
      );

  void _schedule(DevelopSettings s, Duration delay) {
    _cancel();
    final gen = ++_gen;
    _timer = Timer(delay, () => unawaited(_rebuild(s, gen)));
  }

  Future<void> _rebuild(DevelopSettings s, int gen) async {
    final faces = _faces;
    final WarpBuildResult r;
    try {
      r = await _build(_request(s, faces));
    } finally {
      if (gen == _gen) _timer = null;
    }
    if (_disposed || gen != _gen) return;
    _shapeKey = warpShapeKey(s.portrait, faces);
    final n = s.liquify.length;
    _prefix = r.prefix;
    _live = null;
    _prefixStrokes = List.unmodifiable(
      n == 0 ? const <LiquifyStroke>[] : s.liquify.sublist(0, n - 1),
    );
    _publish(r.full, s.liquify);
    final last = _last;
    if (last != null && !identical(last, s)) update(last);
  }

  WarpRequest _request(DevelopSettings s, FaceAnalysis? faces) =>
      WarpRequest.fromSettings(
        s,
        faces,
        sourceWidth: sourceWidth,
        sourceHeight: sourceHeight,
      );

  void _publish(WarpField? f, List<LiquifyStroke> strokes) {
    _fieldStrokes = strokes;
    if (identical(f, _field)) return;
    _field = f;
    onField(f);
  }

  /// The exact field for [s] (identity when it warps nothing).
  Future<WarpField> fieldFor(DevelopSettings s) async {
    if (!hasWarpEdits(s, _faces)) return WarpField.identity();
    final current = _field;
    if (current != null &&
        warpShapeKey(s.portrait, _faces) == _shapeKey &&
        _eq.equals(s.liquify, _fieldStrokes)) {
      return current;
    }
    return (await _build(_request(s, _faces))).full;
  }

  void _cancel() {
    _timer?.cancel();
    _timer = null;
    _gen++;
  }

  void dispose() {
    _disposed = true;
    _cancel();
  }
}
