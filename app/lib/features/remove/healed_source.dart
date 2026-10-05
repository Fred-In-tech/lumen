import 'dart:collection';
import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/data/patch_store.dart';
import 'package:lumen/features/editor/renderer/image_bridge.dart';
import 'package:lumen/features/remove/remove_providers.dart';
import 'package:lumen/import/photo_decoder.dart';
import 'package:lumen/platform/background.dart';

/// A preview with the photo's heal patches drawn in: what the renderer
/// should develop instead of the raw preview.
class HealedSource {
  const HealedSource({
    required this.buffer,
    required this.healed,
    required this.needsAuxRecompute,
  });

  /// The composited pixels; the input preview itself when nothing is drawn.
  final RgbaBuffer buffer;

  /// At least one patch was drawn.
  final bool healed;

  /// The healed area is large enough (≥ 0.5 % of the frame, union of the
  /// visible boxes) that the AuxMaps built from the unhealed source (clarity
  /// base, guided-filter coefficients, dark channel) are stale: rebuild
  /// them from [buffer]. Below that, the old maps are indistinguishable.
  final bool needsAuxRecompute;
}

/// Loads one decoded patch by ref (null when missing).
typedef PatchLoader = Future<RgbaBuffer?> Function(String ref);

/// Composites heal ops onto preview buffers, cached per preview size.
///
/// A hit needs the same preview instance and the same heal list (identical,
/// or equal after an undo/redo round trip), so slider drags never
/// re-composite. Decoded patches are kept only for the ops last composited.
class HealedSourceCache {
  HealedSourceCache(this._loadPatch, {this.maxSizes = 3});

  final PatchLoader _loadPatch;

  /// Preview sizes kept at once (e.g. full preview + interactive proxy).
  final int maxSizes;

  final LinkedHashMap<(int, int), _Entry> _entries = LinkedHashMap();
  final Map<String, RgbaBuffer> _patches = {};
  final Map<String, Future<RgbaBuffer?>> _loading = {};

  /// The cached result for [preview] + [ops], or null (call [compose]).
  /// Synchronous, for render paths that cannot wait.
  HealedSource? peek(RgbaBuffer preview, List<HealOp> ops) {
    final e = _entries[(preview.width, preview.height)];
    return e != null && e.matches(preview, ops) ? e.result : null;
  }

  /// [preview] with [ops] composited (bboxes scale from each op's source
  /// size to the preview's). Missing patches are skipped.
  Future<HealedSource> compose(RgbaBuffer preview, List<HealOp> ops) async {
    final hit = peek(preview, ops);
    if (hit != null) return hit;
    final result = await _composite(preview, ops);
    _keepOnly(ops);
    final key = (preview.width, preview.height);
    _entries.remove(key);
    _entries[key] = _Entry(preview, ops, result);
    while (_entries.length > maxSizes) {
      _entries.remove(_entries.keys.first);
    }
    return result;
  }

  Future<HealedSource> _composite(RgbaBuffer preview, List<HealOp> ops) async {
    final visible = [
      for (final op in ops)
        if (!op.hidden && op.isRenderable) op,
    ];
    final patches = await _patchesFor(visible);
    final drawn = [
      for (final op in visible)
        if (patches.containsKey(op.patch)) op,
    ];
    return drawn.isEmpty
        ? HealedSource(buffer: preview, healed: false, needsAuxRecompute: false)
        : HealedSource(
            buffer: composeHealed(preview, drawn, MapPatchLookup(patches)),
            healed: true,
            needsAuxRecompute: needsAuxRecompute(drawn),
          );
  }

  /// The patches of [ops] alone as a premultiplied [width]×[height]
  /// overlay (`composeHealOverlay`), or null when nothing draws. The float
  /// editing path draws it over the float source, whose pixels a
  /// [RgbaBuffer] cannot hold. Composed off the UI isolate, not cached.
  Future<RgbaBuffer?> overlay(int width, int height, List<HealOp> ops) async {
    final visible = [
      for (final op in ops)
        if (!op.hidden && op.isRenderable) op,
    ];
    final patches = await _patchesFor(visible);
    final drawn = [
      for (final op in visible)
        if (patches.containsKey(op.patch)) op,
    ];
    if (drawn.isEmpty) return null;
    return runInBackground(
      () => composeHealOverlay(width, height, drawn, MapPatchLookup(patches)),
    );
  }

  /// Like [compose] but stores no result: for one-off buffers (thumbnails,
  /// style previews, histogram proxies) that would only evict the preview
  /// entries. Decoded patches are still shared.
  Future<HealedSource> composeOnce(RgbaBuffer buffer, List<HealOp> ops) async {
    final hit = peek(buffer, ops);
    if (hit != null) return hit;
    return _composite(buffer, ops);
  }

  /// Drops every cached result and patch (e.g. after patches were rebuilt).
  void clear() {
    _entries.clear();
    _patches.clear();
  }

  Future<Map<String, RgbaBuffer>> _patchesFor(List<HealOp> ops) async {
    final out = <String, RgbaBuffer>{};
    final missing = <String>[];
    for (final op in ops) {
      final cached = _patches[op.patch];
      if (cached != null) {
        out[op.patch] = cached;
      } else if (!missing.contains(op.patch)) {
        missing.add(op.patch);
      }
    }
    // A few decodes at a time: each one is a background isolate.
    for (var i = 0; i < missing.length; i += 4) {
      final batch = missing.sublist(i, (i + 4).clamp(0, missing.length));
      final loaded = await Future.wait([for (final r in batch) _load(r)]);
      for (var j = 0; j < batch.length; j++) {
        final patch = loaded[j];
        if (patch != null) out[batch[j]] = _patches[batch[j]] = patch;
      }
    }
    return out;
  }

  /// One load per ref at a time, shared by concurrent [compose] calls.
  Future<RgbaBuffer?> _load(String ref) =>
      _loading[ref] ??= _loadPatch(ref).whenComplete(() {
        // A block body: returning the removed future would make this
        // future wait for itself.
        _loading.remove(ref);
      });

  /// Bounds memory to the patches of the current list (hidden ones too,
  /// since toggling visibility is common).
  void _keepOnly(List<HealOp> ops) {
    final live = {for (final op in ops) op.patch};
    _patches.removeWhere((ref, _) => !live.contains(ref));
  }
}

class _Entry {
  _Entry(this.preview, this.ops, this.result);

  final RgbaBuffer preview;
  final List<HealOp> ops;
  final HealedSource result;

  bool matches(RgbaBuffer p, List<HealOp> o) =>
      identical(p, preview) &&
      (identical(o, ops) || const ListEquality<HealOp>().equals(o, ops));
}

/// One cache per photo. Invalidate it when the editor closes
/// (`ref.invalidate(healedSourceProvider(assetId))`) to free its buffers.
final healedSourceProvider = Provider.family<HealedSourceCache, String>((
  ref,
  assetId,
) {
  // Opened lazily: photos without heal ops never touch the store.
  return HealedSourceCache(
    (patch) async =>
        (await ref.read(patchStoreProvider.future)).load(assetId, patch),
  );
});

/// Full-resolution [source] with [ops] composited, for export and batch:
/// patches are stored at original resolution, so this is exact.
Future<RgbaBuffer> composeHealedFullRes(
  PatchStore store,
  String assetId,
  RgbaBuffer source,
  List<HealOp> ops,
) async {
  final patches = await loadPatchMap(store, assetId, ops);
  if (patches.isEmpty) return source;
  return runInBackground(
    () => composeHealed(source, ops, MapPatchLookup(patches)),
  );
}

/// True when [settings] has heal ops that draw something.
bool hasVisibleHeals(DevelopSettings settings) =>
    settings.heal.any((op) => !op.hidden && op.isRenderable);

/// [original] decoded (long edge ≤ [maxLongEdge] when given) with the
/// visible ops of [ops] drawn in: the source export, batch and thumbnail
/// renders develop. The store is only opened when there is something to
/// draw, so photos without retouching never touch it.
Future<RgbaBuffer> decodeHealedSource(
  Uint8List original, {
  required String assetId,
  required List<HealOp> ops,
  required PatchStoreGetter? patches,
  int? maxLongEdge,
}) async {
  final decoded = await decodePhoto(original, maxLongEdge: maxLongEdge);
  final RgbaBuffer src;
  try {
    src = await rgbaFromImage(decoded);
  } finally {
    decoded.dispose();
  }
  final visible = [
    for (final op in ops)
      if (!op.hidden && op.isRenderable) op,
  ];
  if (patches == null || visible.isEmpty) return src;
  return composeHealedFullRes(await patches(), assetId, src, visible);
}
