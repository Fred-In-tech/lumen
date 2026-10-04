import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lumen_core/lumen_core.dart';

/// Brush tool settings (UI values; [radius] etc. convert to stroke units).
class BrushSettings {
  const BrushSettings({
    this.erase = false,
    this.size = 20,
    this.hardness = 50,
    this.flow = 100,
  });

  /// Erase removes coverage instead of painting it.
  final bool erase;

  /// 1–100; the radius is `size / 400` of the source long edge.
  final double size;

  /// 0–100: the solid fraction of the radius.
  final double hardness;

  /// 1–100: stroke strength.
  final double flow;

  static const double minSize = 1, maxSize = 100;

  /// Stroke radius as a fraction of the source long edge.
  double get radius => size / 400;

  BrushStroke stroke(List<(double, double)> points) => BrushStroke(
    points: List.unmodifiable(points),
    radius: radius,
    hardness: hardness / 100,
    flow: flow / 100,
    erase: erase,
  );

  BrushSettings copyWith({
    bool? erase,
    double? size,
    double? hardness,
    double? flow,
  }) => BrushSettings(
    erase: erase ?? this.erase,
    size: (size ?? this.size).clamp(minSize, maxSize).toDouble(),
    hardness: (hardness ?? this.hardness).clamp(0, 100).toDouble(),
    flow: (flow ?? this.flow).clamp(1, 100).toDouble(),
  );
}

/// Per-photo Masks UI state (not part of the edit document).
class MaskUiState {
  const MaskUiState({
    this.selectedId,
    this.showOverlay = false,
    this.hoverId,
    this.brush = const BrushSettings(),
  });

  /// The mask whose sliders and handles are shown (stale ids read as none).
  final String? selectedId;

  /// The coverage tint of the selected mask (`O`, the eye button).
  final bool showOverlay;

  /// A mask row under the pointer: its tint shows while hovering.
  final String? hoverId;

  final BrushSettings brush;

  /// The selected mask in [masks], or null.
  LocalMask? selectedIn(List<LocalMask> masks) => _find(masks, selectedId);

  /// Index of the mask whose tint to show, or null for none.
  int? tintIndexIn(List<LocalMask> masks) {
    final hover = _indexOf(masks, hoverId);
    if (hover != null) return hover;
    return showOverlay ? _indexOf(masks, selectedId) : null;
  }

  static LocalMask? _find(List<LocalMask> masks, String? id) {
    final i = _indexOf(masks, id);
    return i == null ? null : masks[i];
  }

  static int? _indexOf(List<LocalMask> masks, String? id) {
    if (id == null) return null;
    final i = masks.indexWhere((m) => m.id == id);
    return i < 0 ? null : i;
  }

  MaskUiState copyWith({
    String? selectedId,
    bool clearSelection = false,
    bool? showOverlay,
    String? hoverId,
    bool clearHover = false,
    BrushSettings? brush,
  }) => MaskUiState(
    selectedId: clearSelection ? null : (selectedId ?? this.selectedId),
    showOverlay: showOverlay ?? this.showOverlay,
    hoverId: clearHover ? null : (hoverId ?? this.hoverId),
    brush: brush ?? this.brush,
  );
}

class MaskUiNotifier extends Notifier<MaskUiState> {
  MaskUiNotifier(this.assetId);

  final String assetId;

  @override
  MaskUiState build() => const MaskUiState();

  void select(String? id) => state = id == null
      ? state.copyWith(clearSelection: true)
      : state.copyWith(selectedId: id);

  void setShowOverlay(bool v) => state = state.copyWith(showOverlay: v);

  void toggleOverlay() => setShowOverlay(!state.showOverlay);

  void setHover(String? id) => state = id == null
      ? state.copyWith(clearHover: true)
      : state.copyWith(hoverId: id);

  void setBrush(BrushSettings brush) => state = state.copyWith(brush: brush);
}

final maskUiProvider =
    NotifierProvider.family<MaskUiNotifier, MaskUiState, String>(
      MaskUiNotifier.new,
    );
