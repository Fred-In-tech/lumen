import '../cull/smart_cull.dart' show PhotoFlag;
import '../model/catalog_entry.dart';

/// The five steps of a shoot, in workflow order.
enum ProjectStep {
  import('Import'),
  cull('Cull'),
  edit('Edit'),
  retouch('Retouch'),
  export('Export');

  const ProjectStep(this.label);
  final String label;
}

/// Where one step stands. [optional]: nothing to do for it (no portraits
/// found), so it never blocks the next step.
enum StepState { notStarted, partial, done, optional }

/// One step: [done] of [total] photos, and a sentence for the UI.
class StepProgress {
  const StepProgress({
    required this.step,
    required this.state,
    required this.done,
    required this.total,
    required this.summary,
  });

  final ProjectStep step;
  final StepState state;
  final int done;
  final int total;

  /// e.g. "38 of 120 edited".
  final String summary;

  bool get isComplete => state == StepState.done || state == StepState.optional;
}

/// What to do next: the first unfinished step, with the photos it applies
/// to. [step] is null when every step is complete.
class NextStep {
  const NextStep({
    required this.step,
    required this.label,
    this.assetIds = const [],
  });

  final ProjectStep? step;

  /// e.g. "Cull 120 photos", "Edit 82 picks", "Export 40 photos".
  final String label;

  /// Photos the action applies to (unculled, unedited, unexported, …).
  final List<String> assetIds;
}

/// Derived progress of a project (never stored).
class ProjectProgress {
  const ProjectProgress({required this.steps, required this.next});

  final List<StepProgress> steps;
  final NextStep next;

  StepProgress of(ProjectStep step) => steps[step.index];

  /// Steps that are done (optional steps count as done).
  int get completedSteps => steps.where((s) => s.isComplete).length;

  bool get isComplete => next.step == null;
}

String _photos(int n) => n == 1 ? 'photo' : 'photos';
String _picks(int n) => n == 1 ? 'pick' : 'picks';
String _portraits(int n) => n == 1 ? 'portrait' : 'portraits';

StepState _state(int done, int total) => total == 0 || done == 0
    ? StepState.notStarted
    : done >= total
    ? StepState.done
    : StepState.partial;

/// Project progress from its [photos].
///
/// Rules (docs/DESIGN.md "Home and projects"):
/// - **Import**: done once the project has a photo.
/// - **Cull**: a photo is culled when it has a pick/reject flag or its Smart
///   Cull suggestion was accepted ([cullAccepted]). Done when all are.
/// - **Edit**: photos with edits, among the picks when there are picks,
///   else among every photo that is not rejected.
/// - **Retouch**: among the Edit photos, those known to show faces
///   ([faceCounts] > 0, or already retouched) that carry face retouch.
///   Optional when no faces are known.
/// - **Export**: photos exported since their last edit, among the picks,
///   else the edited photos, else every photo that is not rejected.
///
/// The next step is the first step that is not complete.
ProjectProgress computeProjectProgress(
  List<CatalogEntry> photos, {
  Set<String> cullAccepted = const {},
  Map<String, int> faceCounts = const {},
}) {
  final live = [
    for (final e in photos)
      if (e.flag != PhotoFlag.reject) e,
  ];
  final picks = [
    for (final e in live)
      if (e.flag == PhotoFlag.pick) e,
  ];
  final byPicks = picks.isNotEmpty;
  final editScope = byPicks ? picks : live;
  final edited = [
    for (final e in live)
      if (e.hasEdits) e,
  ];
  final exportScope = byPicks
      ? picks
      : edited.isNotEmpty
      ? edited
      : live;

  bool culled(CatalogEntry e) =>
      e.flag != PhotoFlag.none || cullAccepted.contains(e.assetId);
  final unculled = [
    for (final e in photos)
      if (!culled(e)) e.assetId,
  ];
  final unedited = [
    for (final e in editScope)
      if (!e.hasEdits) e.assetId,
  ];
  final portraits = [
    for (final e in editScope)
      if ((faceCounts[e.assetId] ?? 0) > 0 || e.retouched) e,
  ];
  final unretouched = [
    for (final e in portraits)
      if (!e.retouched) e.assetId,
  ];
  final unexported = [
    for (final e in exportScope)
      if (!e.exportIsCurrent) e.assetId,
  ];

  final n = photos.length;
  final editNoun = byPicks
      ? _picks(editScope.length)
      : _photos(editScope.length);
  final exportNoun = byPicks
      ? _picks(exportScope.length)
      : _photos(exportScope.length);
  final steps = [
    StepProgress(
      step: ProjectStep.import,
      state: n == 0 ? StepState.notStarted : StepState.done,
      done: n,
      total: n,
      summary: n == 0 ? 'No photos yet' : '$n ${_photos(n)}',
    ),
    StepProgress(
      step: ProjectStep.cull,
      state: _state(n - unculled.length, n),
      done: n - unculled.length,
      total: n,
      summary: '${n - unculled.length} of $n culled',
    ),
    StepProgress(
      step: ProjectStep.edit,
      state: _state(editScope.length - unedited.length, editScope.length),
      done: editScope.length - unedited.length,
      total: editScope.length,
      summary:
          '${editScope.length - unedited.length} of ${editScope.length} '
          '${byPicks ? '$editNoun ' : ''}edited',
    ),
    StepProgress(
      step: ProjectStep.retouch,
      state: portraits.isEmpty
          ? StepState.optional
          : _state(portraits.length - unretouched.length, portraits.length),
      done: portraits.length - unretouched.length,
      total: portraits.length,
      summary: portraits.isEmpty
          ? 'No faces found yet'
          : '${portraits.length - unretouched.length} of ${portraits.length} '
                '${_portraits(portraits.length)} retouched',
    ),
    StepProgress(
      step: ProjectStep.export,
      state: _state(exportScope.length - unexported.length, exportScope.length),
      done: exportScope.length - unexported.length,
      total: exportScope.length,
      summary:
          '${exportScope.length - unexported.length} of ${exportScope.length} '
          '${byPicks ? '$exportNoun ' : ''}exported',
    ),
  ];

  final pending = steps.where((s) => !s.isComplete);
  final first = pending.isEmpty ? null : pending.first.step;
  final next = switch (first) {
    null => const NextStep(step: null, label: 'All delivered'),
    ProjectStep.import => const NextStep(
      step: ProjectStep.import,
      label: 'Add photos',
    ),
    ProjectStep.cull => NextStep(
      step: ProjectStep.cull,
      label: 'Cull ${unculled.length} ${_photos(unculled.length)}',
      assetIds: List.unmodifiable(unculled),
    ),
    ProjectStep.edit => NextStep(
      step: ProjectStep.edit,
      label:
          'Edit ${unedited.length} '
          '${byPicks ? _picks(unedited.length) : _photos(unedited.length)}',
      assetIds: List.unmodifiable(unedited),
    ),
    ProjectStep.retouch => NextStep(
      step: ProjectStep.retouch,
      label: 'Retouch ${unretouched.length} ${_portraits(unretouched.length)}',
      assetIds: List.unmodifiable(unretouched),
    ),
    ProjectStep.export => NextStep(
      step: ProjectStep.export,
      label:
          'Export ${unexported.length} '
          '${byPicks ? _picks(unexported.length) : _photos(unexported.length)}',
      assetIds: List.unmodifiable(unexported),
    ),
  };
  return ProjectProgress(steps: List.unmodifiable(steps), next: next);
}
