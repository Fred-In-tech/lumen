import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lumen_core/lumen_core.dart';

/// What the Portrait sliders currently edit: a face group, or one person.
class PortraitTarget {
  const PortraitTarget.group(this.group) : personId = null;
  const PortraitTarget.person(String this.personId, this.group);

  /// For a person: the group their face belongs to (used for inherited values).
  final FaceGroup group;
  final String? personId;

  bool get isPerson => personId != null;

  String get label => isPerson ? 'Individual' : group.label;

  @override
  bool operator ==(Object other) =>
      other is PortraitTarget &&
      other.group == group &&
      other.personId == personId;

  @override
  int get hashCode => Object.hash(group, personId);
}

/// Per-photo Portrait UI state (not part of the edit document).
class PortraitUiState {
  const PortraitUiState({
    this.target = const PortraitTarget.group(FaceGroup.all),
    this.selectedFaceId,
    this.showFaces = true,
  });

  final PortraitTarget target;
  final String? selectedFaceId;
  final bool showFaces;

  PortraitUiState copyWith({
    PortraitTarget? target,
    String? selectedFaceId,
    bool clearSelection = false,
    bool? showFaces,
  }) => PortraitUiState(
    target: target ?? this.target,
    selectedFaceId: clearSelection
        ? null
        : (selectedFaceId ?? this.selectedFaceId),
    showFaces: showFaces ?? this.showFaces,
  );
}

class PortraitUiNotifier extends Notifier<PortraitUiState> {
  PortraitUiNotifier(this.assetId);

  final String assetId;

  @override
  PortraitUiState build() => const PortraitUiState();

  void selectGroup(FaceGroup group) => state = state.copyWith(
    target: PortraitTarget.group(group),
    clearSelection: true,
  );

  /// Selects [face] on the canvas and edits that person individually.
  void selectFace(DetectedFace face) => state = state.copyWith(
    selectedFaceId: face.id,
    target: PortraitTarget.person(face.personId ?? face.id, face.group),
  );

  void clearSelection() => state = state.copyWith(
    clearSelection: true,
    target: PortraitTarget.group(state.target.group),
  );

  void setShowFaces(bool v) => state = state.copyWith(showFaces: v);
}

final portraitUiProvider =
    NotifierProvider.family<PortraitUiNotifier, PortraitUiState, String>(
      PortraitUiNotifier.new,
    );

/// Faces found in the open photo, from the on-device analyzer's local cache.
/// Null while analysis has not run (or no analyzer is available).
final portraitFacesProvider = Provider.family<FaceAnalysis?, String>(
  (ref, assetId) => null,
);

/// Reads [id] for [target] from [p] (inherited values included).
double portraitValue(PortraitSettings p, String id, PortraitTarget target) {
  if (PortraitRegistry.byId(id).scope == PortraitScope.image) {
    return p.imageValue(id);
  }
  return p.valueFor(id, group: target.group, personId: target.personId);
}

/// Writes [v] for [id] at [target].
PortraitSettings withPortraitValue(
  PortraitSettings p,
  String id,
  PortraitTarget target,
  double v,
) {
  if (PortraitRegistry.byId(id).scope == PortraitScope.image) {
    return p.withImageValue(id, v);
  }
  final person = target.personId;
  return person != null
      ? p.withIndividualValue(person, id, v)
      : p.withGroupValue(target.group, id, v);
}
