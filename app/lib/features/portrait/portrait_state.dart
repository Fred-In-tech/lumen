import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lumen/ai/ondevice/ondevice_providers.dart';
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

/// The part of a portrait the panel is showing: a few groups at a time
/// instead of every retouch group in one long list.
enum PortraitCategory {
  skin('Skin'),
  face('Face'),
  shape('Shape'),
  scene('Scene');

  const PortraitCategory(this.label);

  final String label;
}

/// What a pointer on the Portrait canvas does.
enum PortraitCanvasTool { faces, spots, liquify, pen }

/// Per-photo Portrait UI state (not part of the edit document).
class PortraitUiState {
  const PortraitUiState({
    this.target = const PortraitTarget.group(FaceGroup.all),
    this.selectedFaceId,
    this.showFaces = true,
    this.category = PortraitCategory.skin,
    this.tool = PortraitCanvasTool.faces,
    this.liquifyTool = LiquifyTool.push,
    this.liquifyRadius = 0.06,
    this.liquifyStrength = 0.5,
    this.penErase = false,
    this.penRadius = 0.025,
    this.penHardness = 0.5,
    this.penFlow = 1,
  });

  final PortraitTarget target;
  final String? selectedFaceId;
  final bool showFaces;
  final PortraitCategory category;

  final PortraitCanvasTool tool;

  /// The canvas shows detected spots to keep or remove (instead of faces).
  bool get spotEdit => tool == PortraitCanvasTool.spots;

  /// Liquify brush: tool, radius (fraction of the long edge), strength 0..1.
  final LiquifyTool liquifyTool;
  final double liquifyRadius;
  final double liquifyStrength;

  /// Skin pen brush (Manual Tuning Pen).
  final bool penErase;
  final double penRadius;
  final double penHardness;
  final double penFlow;

  PortraitUiState copyWith({
    PortraitTarget? target,
    String? selectedFaceId,
    bool clearSelection = false,
    bool? showFaces,
    PortraitCategory? category,
    PortraitCanvasTool? tool,
    LiquifyTool? liquifyTool,
    double? liquifyRadius,
    double? liquifyStrength,
    bool? penErase,
    double? penRadius,
    double? penHardness,
    double? penFlow,
  }) => PortraitUiState(
    target: target ?? this.target,
    selectedFaceId: clearSelection
        ? null
        : (selectedFaceId ?? this.selectedFaceId),
    showFaces: showFaces ?? this.showFaces,
    category: category ?? this.category,
    tool: tool ?? this.tool,
    liquifyTool: liquifyTool ?? this.liquifyTool,
    liquifyRadius: liquifyRadius ?? this.liquifyRadius,
    liquifyStrength: liquifyStrength ?? this.liquifyStrength,
    penErase: penErase ?? this.penErase,
    penRadius: penRadius ?? this.penRadius,
    penHardness: penHardness ?? this.penHardness,
    penFlow: penFlow ?? this.penFlow,
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

  void setCategory(PortraitCategory c) => state = state.copyWith(category: c);

  void setSpotEdit(bool v) =>
      setTool(v ? PortraitCanvasTool.spots : PortraitCanvasTool.faces);

  void setTool(PortraitCanvasTool t) => state = state.copyWith(tool: t);

  /// Turns [t] on, or back to face selection when it is already active.
  void toggleTool(PortraitCanvasTool t) =>
      setTool(state.tool == t ? PortraitCanvasTool.faces : t);

  void setLiquify({LiquifyTool? tool, double? radius, double? strength}) =>
      state = state.copyWith(
        liquifyTool: tool,
        liquifyRadius: radius,
        liquifyStrength: strength,
      );

  void setPen({bool? erase, double? radius, double? hardness, double? flow}) =>
      state = state.copyWith(
        penErase: erase,
        penRadius: radius,
        penHardness: hardness,
        penFlow: flow,
      );
}

final portraitUiProvider =
    NotifierProvider.family<PortraitUiNotifier, PortraitUiState, String>(
      PortraitUiNotifier.new,
    );

/// Face detection state for the open photo: the local cache when current,
/// else a fresh on-device analysis (runs the first time it is watched).
final portraitFacesStatusProvider =
    Provider.family<AsyncValue<FaceAnalysis?>, String>(
      (ref, assetId) =>
          ref.watch(faceAnalysisProvider(assetId)).whenData((e) => e.analysis),
    );

/// Faces found in the open photo; null while detecting or when unavailable.
final portraitFacesProvider = Provider.family<FaceAnalysis?, String>(
  (ref, assetId) => ref.watch(portraitFacesStatusProvider(assetId)).value,
);

/// Tags [face] with [group] in the local face cache and re-selects it, so the
/// person's sliders resolve through the new group.
Future<void> tagFace(
  WidgetRef ref,
  String assetId,
  DetectedFace face,
  FaceGroup group,
) async {
  final service = await ref.read(faceAnalysisServiceProvider.future);
  await service.tag(assetId, face.id, group, personId: face.personId);
  ref.invalidate(faceAnalysisProvider(assetId));
  ref
      .read(portraitUiProvider(assetId).notifier)
      .selectFace(face.copyWith(group: group, tagSource: TagSource.manual));
}

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
