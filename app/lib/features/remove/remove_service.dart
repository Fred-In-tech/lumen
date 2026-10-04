import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/data/catalog_repository.dart';
import 'package:lumen/data/patch_store.dart';
import 'package:lumen/features/editor/editor_controller.dart';
import 'package:lumen/features/portrait/portrait_state.dart';
import 'package:lumen/features/remove/remove_jobs.dart';
import 'package:lumen/features/remove/remove_providers.dart';
import 'package:lumen/features/remove/remove_status.dart';
import 'package:lumen/import/photo_decoder.dart';
import 'package:lumen/platform/cancellable_task.dart';

final _log = Logger('RemoveService');

/// A failure whose message is written for the user.
class RemoveException implements Exception {
  const RemoveException(this.message);
  final String message;

  @override
  String toString() => 'RemoveException: $message';
}

/// Object removal, healing brush and clone stamp for catalog photos.
///
/// Each call loads the full-resolution original, draws the photo's existing
/// heal ops onto it, fills the new hole in a killable background isolate,
/// stores the patch PNGs and commits the new ops as ONE history entry.
/// Progress is published on [removeStatusProvider]. One run per photo.
class RemoveService {
  RemoveService(this._ref);

  final Ref _ref;
  final Map<String, _Run> _runs = {};

  /// The history label of each tool.
  static String labelFor(HealKind kind) => switch (kind) {
    HealKind.remove => 'Remove',
    HealKind.heal => 'Heal',
    HealKind.clone => 'Clone',
  };

  bool isRunning(String assetId) => _runs.containsKey(assetId);

  /// Removes what [strokes] cover. [method] forces an engine; by default
  /// the picker chooses (the model only when [removeModelProvider] has one).
  /// Returns the committed ops (empty when cancelled, failed or nothing
  /// was covered).
  Future<List<HealOp>> remove(
    String assetId,
    List<BrushStroke> strokes, {
    InpaintMethod? method,
  }) =>
      _start(assetId, HealKind.remove, (run) => _remove(run, strokes, method));

  /// Clone stamp: covers [strokes] with the photo at [offset] (normalized
  /// uv, e.g. (0.1, 0) samples 10 % of the width to the right).
  Future<List<HealOp>> cloneAt(
    String assetId,
    List<BrushStroke> strokes,
    (double, double) offset,
  ) => _start(
    assetId,
    HealKind.clone,
    (run) => _brush(run, HealKind.clone, strokes, offset),
  );

  /// Healing brush: texture from [offset] (normalized uv; null picks the
  /// best nearby area), colour and light from around the strokes.
  Future<List<HealOp>> healAt(
    String assetId,
    List<BrushStroke> strokes, {
    (double, double)? offset,
  }) => _start(
    assetId,
    HealKind.heal,
    (run) => _brush(run, HealKind.heal, strokes, offset),
  );

  /// Stops the photo's run (kills its isolate) unless it is already
  /// committing. The status returns to idle; nothing is committed.
  void cancel(String assetId) {
    final run = _runs[assetId];
    if (run == null || run.committing) return;
    run.cancel();
    _report(assetId, const RemoveIdle());
  }

  /// Deletes patch PNGs that neither the settings nor the undo/redo history
  /// (nor snapshots) reference. Call it when the editor closes; runs after
  /// every commit too. Returns the deleted refs.
  Future<Set<String>> collectGarbage(String assetId) async {
    await _ref.read(editorProvider(assetId).future);
    final ctl = _ref.read(editorProvider(assetId).notifier);
    await ctl.flush();
    final doc = _ref.read(editorProvider(assetId)).value?.doc;
    if (doc == null) return const {};
    final store = await _ref.read(patchStoreProvider.future);
    return collectPatchGarbage(
      store,
      doc,
      protect: {...?_runs[assetId]?.savedRefs},
    );
  }

  Future<List<HealOp>> _start(
    String assetId,
    HealKind kind,
    Future<_Outcome?> Function(_Run run) body,
  ) async {
    if (_runs.containsKey(assetId)) {
      throw StateError('A ${kind.name} is already running for $assetId');
    }
    final run = _Run(assetId, kind);
    _runs[assetId] = run;
    _report(assetId, RemoveRunning(kind: kind));
    try {
      final outcome = await body(run);
      if (run.cancelled) return const [];
      if (outcome == null) {
        _report(assetId, const RemoveIdle());
        return const [];
      }
      _report(
        assetId,
        RemoveDone(kind: kind, ops: outcome.ops, method: outcome.method),
      );
      return outcome.ops;
    } on InpaintCancelled {
      return const [];
    } on Object catch (e, st) {
      // The status must leave "running" whatever went wrong; errors from
      // the isolate arrive as RemoteError, which is an Error subtype.
      if (run.cancelled) return const [];
      _log.warning('${kind.name} failed for $assetId', e, st);
      _report(assetId, RemoveFailed(kind: kind, message: _messageFor(kind, e)));
      return const [];
    } finally {
      _runs.remove(assetId);
    }
  }

  Future<_Outcome?> _remove(
    _Run run,
    List<BrushStroke> strokes,
    InpaintMethod? forced,
  ) async {
    final model = _ref.read(removeModelProvider);
    if (forced == InpaintMethod.model && model == null) {
      throw const RemoveException(
        'AI removal is not available on this device yet.',
      );
    }
    final ctx = await _prepare(run, strokes);
    final plan = await run.track(
      startPlan(
        _runner,
        PlanInput(
          strokes: strokes,
          width: ctx.width,
          height: ctx.height,
          faces: _faces(run.assetId),
          modelAvailable: model != null,
          forced: forced,
        ),
      ),
    );
    final method = plan.method;
    if (method == null) return null;
    _report(run.assetId, RemoveRunning(kind: HealKind.remove, method: method));
    final InpaintResult result;
    if (method == InpaintMethod.model && model != null) {
      // MI-GAN seam: the model lives on its own interpreter isolate, so
      // the pipeline runs here and cancels cooperatively.
      final base = ctx.input.healedBase();
      result = await InpaintPipeline.remove(
        base,
        rasterizeHoleMask(strokes, ctx.width, ctx.height),
        model: model,
        method: method,
        shouldCancel: () => run.cancelled,
      );
    } else {
      result = await run.track(
        startClassicalRemoval(
          _runner,
          ctx.input,
          method,
          const InpaintConfig(),
        ),
      );
    }
    return _commit(
      run,
      ctx,
      patches: result.patches,
      engine: result.engineId,
      ai: result.ai,
      faceIntersect: plan.faceIntersect,
      method: method,
    );
  }

  Future<_Outcome?> _brush(
    _Run run,
    HealKind kind,
    List<BrushStroke> strokes,
    (double, double)? offset,
  ) async {
    final ctx = await _prepare(run, strokes);
    final px = offset == null
        ? null
        : ((offset.$1 * ctx.width).round(), (offset.$2 * ctx.height).round());
    final patch = await run.track(startBrush(_runner, ctx.input, kind, px));
    if (patch == null) return null;
    return _commit(
      run,
      ctx,
      patches: [patch],
      engine: kind == HealKind.clone ? 'clone@1' : 'heal@1',
      ai: false,
      faceIntersect: false,
      cloneOffset: offset,
    );
  }

  /// Editor document, store, full-res source and the existing patches.
  Future<_Context> _prepare(_Run run, List<BrushStroke> strokes) async {
    final editor = await _ref.read(editorProvider(run.assetId).future);
    if (editor.doc.readOnly) {
      throw const RemoveException(
        'This photo was edited in a newer version and is read-only here.',
      );
    }
    final store = await _ref.read(patchStoreProvider.future);
    final source = await _ref.read(removeSourceLoaderProvider)(run.assetId);
    run.throwIfCancelled();
    final existing = [
      for (final op in editor.settings.heal)
        if (!op.hidden && op.isRenderable) op,
    ];
    final patches = await loadPatchMap(store, run.assetId, existing);
    run.throwIfCancelled();
    return _Context(
      store: store,
      input: HealInput(
        source: source,
        existing: existing,
        patches: patches,
        strokes: strokes,
      ),
    );
  }

  /// Saves the patches, then commits their ops as one history entry.
  Future<_Outcome?> _commit(
    _Run run,
    _Context ctx, {
    required List<InpaintPatch> patches,
    required String engine,
    required bool ai,
    required bool faceIntersect,
    InpaintMethod? method,
    (double, double)? cloneOffset,
  }) async {
    run.throwIfCancelled();
    if (patches.isEmpty) return null;
    final assetId = run.assetId;
    final before = _ref.read(editorProvider(assetId)).value;
    final ids = _newIds(before?.doc, patches.length);
    final now = DateTime.now().toUtc();
    final ops = [
      for (var i = 0; i < patches.length; i++)
        HealOp.forPatch(
          id: ids[i],
          kind: run.kind,
          bbox: patches[i].bbox,
          srcWidth: ctx.width,
          srcHeight: ctx.height,
          engine: engine,
          ai: ai,
          strokes: ctx.input.strokes,
          cloneOffset: cloneOffset,
          faceIntersect: faceIntersect,
          createdAt: now,
        ),
    ];
    run.savedRefs.addAll(ops.map((o) => o.patch));
    try {
      await Future.wait([
        for (var i = 0; i < ops.length; i++)
          ctx.store.save(assetId, ops[i].patch, patches[i].rgba),
      ]);
      run.throwIfCancelled();
    } on Object {
      await _discard(ctx.store, assetId, ops);
      rethrow;
    }
    final state = _ref.read(editorProvider(assetId)).value;
    if (state == null || state.doc.readOnly) {
      await _discard(ctx.store, assetId, ops);
      throw const RemoveException('The photo was closed before the edit.');
    }
    run.committing = true;
    final ctl = _ref.read(editorProvider(assetId).notifier);
    ctl.commit(
      state.settings.copyWith(heal: [...state.settings.heal, ...ops]),
      label: labelFor(run.kind),
      kind: ai ? HistoryKind.ai : HistoryKind.slider,
    );
    try {
      await collectGarbage(assetId);
    } on Exception catch (e, st) {
      _log.warning('patch cleanup failed for $assetId', e, st);
    }
    return _Outcome(List.unmodifiable(ops), method);
  }

  Future<void> _discard(
    PatchStore store,
    String assetId,
    List<HealOp> ops,
  ) async {
    for (final op in ops) {
      try {
        await store.delete(assetId, op.patch);
      } on Exception catch (e) {
        _log.fine('could not delete ${op.patch}: $e');
      }
    }
  }

  /// Fresh op ids that no op in [doc] (settings, history, snapshots) uses,
  /// so a new PNG never overwrites one an undo could bring back.
  List<String> _newIds(EditDocument? doc, int count) {
    final taken = doc == null ? const <String>{} : referencedPatchRefs(doc);
    final stamp = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final ids = <String>[];
    for (var n = 0; ids.length < count; n++) {
      final id = 'h${stamp}_$n';
      if (!taken.contains('$kRetouchDir/$id.png')) ids.add(id);
    }
    return ids;
  }

  List<FaceBox> _faces(String assetId) => [
    ...?_ref.read(portraitFacesProvider(assetId))?.faces.map((f) => f.box),
  ];

  CancellableRunner get _runner => _ref.read(cancellableRunnerProvider);

  void _report(String assetId, RemoveStatus status) =>
      _ref.read(removeStatusProvider(assetId).notifier).report(status);

  static String _messageFor(HealKind kind, Object e) => switch (e) {
    RemoveException(:final message) => message,
    CatalogException(:final message) => message,
    DecodeException(:final message) => message,
    _ => switch (kind) {
      HealKind.remove => "Couldn't remove that area. Try a smaller stroke.",
      HealKind.heal => "Couldn't heal that area.",
      HealKind.clone => "Couldn't clone that area.",
    },
  };
}

final removeServiceProvider = Provider<RemoveService>(RemoveService.new);

class _Run {
  _Run(this.assetId, this.kind);

  final String assetId;
  final HealKind kind;
  final Set<String> savedRefs = {};
  CancellableTask<Object?>? _task;
  bool cancelled = false;
  bool committing = false;

  /// Awaits [task], killing it if the run is cancelled meanwhile.
  Future<T> track<T>(CancellableTask<T> task) {
    _task = task;
    if (cancelled) task.cancel();
    return task.result;
  }

  void cancel() {
    cancelled = true;
    _task?.cancel();
  }

  void throwIfCancelled() {
    if (cancelled) throw const InpaintCancelled();
  }
}

class _Context {
  const _Context({required this.store, required this.input});

  final PatchStore store;
  final HealInput input;

  int get width => input.source.width;
  int get height => input.source.height;
}

class _Outcome {
  const _Outcome(this.ops, this.method);
  final List<HealOp> ops;
  final InpaintMethod? method;
}
