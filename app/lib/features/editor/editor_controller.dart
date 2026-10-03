import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/app/providers.dart';
import 'package:lumen/data/catalog_repository.dart';

enum CompareMode { off, split, sideBySide }

/// Immutable editor state for one photo.
class EditorState {
  const EditorState({
    required this.doc,
    this.compare = CompareMode.off,
    this.showingBefore = false,
    this.cropMode = false,
    this.aiBusy = false,
    this.aiStatus,
    this.lockedByUser = const {},
  });

  final EditDocument doc;
  final CompareMode compare;

  /// True while the user holds "\" or presses-and-holds the canvas.
  final bool showingBefore;
  final bool cropMode;
  final bool aiBusy;
  final String? aiStatus;

  /// Params the user changed by hand since the last AI edit (AI must not touch them).
  final Set<ParamId> lockedByUser;

  DevelopSettings get settings => doc.settings;
  HistoryStack get history => doc.history;
  bool get canUndo => history.canUndo;
  bool get canRedo => history.canRedo;

  EditorState copyWith({
    EditDocument? doc,
    CompareMode? compare,
    bool? showingBefore,
    bool? cropMode,
    bool? aiBusy,
    String? aiStatus,
    bool clearAiStatus = false,
    Set<ParamId>? lockedByUser,
  }) =>
      EditorState(
        doc: doc ?? this.doc,
        compare: compare ?? this.compare,
        showingBefore: showingBefore ?? this.showingBefore,
        cropMode: cropMode ?? this.cropMode,
        aiBusy: aiBusy ?? this.aiBusy,
        aiStatus: clearAiStatus ? null : (aiStatus ?? this.aiStatus),
        lockedByUser: lockedByUser ?? this.lockedByUser,
      );
}

/// Owns one photo's edit document: settings, history and persistence.
///
/// Slider gestures: call [beginGesture] on pointer-down, [preview] on every
/// move (no history), and [commitGesture] on pointer-up (one history entry).
class EditorController extends AsyncNotifier<EditorState> {
  EditorController(this.assetId);

  final String assetId;
  Timer? _saveTimer;
  CatalogRepository? _repo;

  /// Last document that still needs saving (readable during dispose, unlike `state`).
  EditDocument? _dirtyDoc;
  DevelopSettings? _gestureStart;
  String? _gestureLabel;

  static const saveDebounce = Duration(milliseconds: 500);

  @override
  Future<EditorState> build() async {
    _repo = ref.read(catalogRepositoryProvider);
    ref.onDispose(() {
      _saveTimer?.cancel();
      final doc = _dirtyDoc;
      if (doc != null) unawaited(_persist(doc));
    });
    final doc = await _repo!.loadEdit(assetId);
    return EditorState(doc: doc);
  }

  EditorState? get _s => state.value;

  void _set(EditorState next, {bool save = true}) {
    state = AsyncData(next);
    if (save) _scheduleSave();
  }

  void _scheduleSave() {
    _dirtyDoc = _s?.doc;
    _saveTimer?.cancel();
    _saveTimer = Timer(saveDebounce, () {
      final doc = _dirtyDoc;
      if (doc != null) unawaited(_persist(doc));
    });
  }

  Future<void> _persist(EditDocument doc) async {
    if (identical(doc, _dirtyDoc)) _dirtyDoc = null;
    final repo = _repo;
    if (repo == null) return;
    await repo.saveEdit(doc);
    final entry = await repo.get(assetId);
    if (entry == null) return;
    final ai = doc.ai;
    final hasEdits = doc.hasEdits;
    if (entry.hasEdits != hasEdits || entry.aiEngine != ai?.engine) {
      await repo.update(entry.copyWith(
        hasEdits: hasEdits,
        editedAt: DateTime.now().toUtc(),
        aiEngine: ai?.engine,
        aiStyle: ai?.style,
      ));
    }
  }

  /// Flushes pending saves immediately (app pause, navigation).
  Future<void> flush() async {
    _saveTimer?.cancel();
    final doc = _s?.doc;
    if (doc != null) await _persist(doc);
  }

  /// Applies [next] as one undoable step.
  void commit(DevelopSettings next, {required String label, HistoryKind kind = HistoryKind.slider, AiRecord? ai, bool clearAi = false}) {
    final s = _s;
    if (s == null || s.doc.readOnly) return;
    final entry = HistoryEntry.tryDiff(label: label, kind: kind, before: s.settings, after: next);
    if (entry == null && ai == null) return;
    final doc = s.doc.copyWith(
      settings: next,
      history: entry == null ? s.history : s.history.push(entry),
      ai: ai,
      clearAi: clearAi,
      updatedAt: DateTime.now().toUtc(),
    );
    final manual = kind == HistoryKind.slider || kind == HistoryKind.curve;
    _set(s.copyWith(
      doc: doc,
      lockedByUser: manual ? {...s.lockedByUser, ...s.settings.changedParams(next)} : s.lockedByUser,
    ));
  }

  /// Sets one scalar param as its own history entry (keyboard nudges, field input).
  void setParam(ParamId id, double value) {
    final s = _s;
    if (s == null) return;
    final spec = ParamRegistry.byId(id);
    commit(s.settings.withValue(id, value), label: '${spec.label} ${_fmt(spec, spec.clamp(value))}');
  }

  void beginGesture(String label) {
    _gestureStart = _s?.settings;
    _gestureLabel = label;
  }

  /// Live update during a drag: updates settings without a history entry.
  void preview(DevelopSettings next) {
    final s = _s;
    if (s == null) return;
    _gestureStart ??= s.settings;
    _set(s.copyWith(doc: s.doc.copyWith(settings: next)), save: false);
  }

  void commitGesture({String? label, HistoryKind kind = HistoryKind.slider}) {
    final s = _s;
    final start = _gestureStart;
    _gestureStart = null;
    if (s == null || start == null) return;
    final end = s.settings;
    // Restore the start state, then commit start→end as one entry.
    state = AsyncData(s.copyWith(doc: s.doc.copyWith(settings: start)));
    commit(end, label: label ?? _gestureLabel ?? 'Edit', kind: kind);
    _gestureLabel = null;
  }

  void undo() {
    final s = _s;
    if (s == null || !s.canUndo) return;
    final r = s.history.undo(s.settings);
    _set(s.copyWith(doc: s.doc.copyWith(settings: r.settings, history: r.stack)));
  }

  void redo() {
    final s = _s;
    if (s == null || !s.canRedo) return;
    final r = s.history.redo(s.settings);
    _set(s.copyWith(doc: s.doc.copyWith(settings: r.settings, history: r.stack)));
  }

  void resetAll() {
    final s = _s;
    if (s == null) return;
    commit(DevelopSettings.defaults.copyWith(geometry: s.settings.geometry), label: 'Reset all', kind: HistoryKind.reset, clearAi: true);
  }

  void resetGroup(ParamGroup group, String label) {
    final s = _s;
    if (s == null) return;
    var next = s.settings.resetParams(ParamRegistry.inGroup(group).map((p) => p.id));
    if (group == ParamGroup.curve) next = next.copyWith(curves: CurveSet.identity);
    if (group == ParamGroup.bw) next = next.copyWith(treatment: Treatment.color);
    commit(next, label: 'Reset $label', kind: HistoryKind.reset);
  }

  void applyPreset(Preset preset, {double amount = 1}) {
    final s = _s;
    if (s == null) return;
    commit(preset.apply(s.settings, amount: amount), label: 'Preset · ${preset.name}', kind: HistoryKind.preset);
  }

  void paste(DevelopSettings source, Set<SettingsGroup> groups) {
    final s = _s;
    if (s == null) return;
    commit(pasteSettings(source: source, target: s.settings, groups: groups), label: 'Paste settings', kind: HistoryKind.paste);
  }

  void setCompare(CompareMode mode) => _s == null ? null : _set(_s!.copyWith(compare: mode), save: false);

  void setShowingBefore(bool v) => _s == null ? null : _set(_s!.copyWith(showingBefore: v), save: false);

  void setCropMode(bool v) => _s == null ? null : _set(_s!.copyWith(cropMode: v), save: false);

  void setAiBusy(bool busy, {String? status}) =>
      _s == null ? null : _set(_s!.copyWith(aiBusy: busy, aiStatus: status, clearAiStatus: status == null), save: false);

  /// Applies an AI result as one entry and records it for Explain + Amount.
  void applyAi(DevelopSettings next, AiRecord record, {required String label, HistoryKind kind = HistoryKind.ai}) {
    final s = _s;
    if (s == null) return;
    commit(next, label: label, kind: kind, ai: record);
    final after = _s;
    if (after != null) _set(after.copyWith(lockedByUser: const {}));
  }

  /// AI Amount (0–1.5): interpolates AI-changed params from the pre-AI state.
  void previewAiAmount(double amount) {
    final s = _s;
    final ai = s?.doc.ai;
    final post = ai?.postAi;
    if (s == null || ai == null || post == null) return;
    preview(interpolateSettings(ai.preAi, post, amount, base: s.settings));
  }

  static String _fmt(ParamSpec spec, double v) =>
      spec.unit == 'EV' ? '${v >= 0 ? '+' : ''}${v.toStringAsFixed(2)}' : '${v >= 0 && spec.bipolar ? '+' : ''}${v.round()}';
}

/// Interpolates every scalar that differs between [from] and [to] at [amount]
/// (extrapolating above 1), applied on top of [base]. Curves/treatment follow
/// [to] when amount ≥ 0.5.
DevelopSettings interpolateSettings(DevelopSettings from, DevelopSettings to, double amount, {required DevelopSettings base}) {
  final changed = from.changedParams(to);
  final next = base.withValues({
    for (final id in changed) id: from.value(id) + (to.value(id) - from.value(id)) * amount,
  });
  return amount >= 0.5
      ? next.copyWith(curves: to.curves, treatment: to.treatment)
      : next.copyWith(curves: from.curves, treatment: from.treatment);
}

final editorProvider = AsyncNotifierProvider.family<EditorController, EditorState, String>(EditorController.new);
