import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:lumen_core/lumen_core.dart';

/// The Remove module's three tools.
enum RemoveTool {
  remove('Remove', LucideIcons.eraser, HealKind.remove),
  heal('Heal', LucideIcons.bandage, HealKind.heal),
  clone('Clone', LucideIcons.stamp, HealKind.clone);

  const RemoveTool(this.label, this.icon, this.kind);

  final String label;
  final IconData icon;
  final HealKind kind;

  /// Heal and clone can take a source point.
  bool get usesSource => this != RemoveTool.remove;
}

/// Icon of an op of [kind] (rows, chips).
IconData healKindIcon(HealKind kind) => switch (kind) {
  HealKind.remove => LucideIcons.eraser,
  HealKind.heal => LucideIcons.bandage,
  HealKind.clone => LucideIcons.stamp,
};

/// The method chip shown while a removal runs.
String methodLabel(InpaintMethod method) => switch (method) {
  InpaintMethod.pushPull => 'Spot heal',
  InpaintMethod.telea => 'Wire',
  InpaintMethod.patchMatch => 'Patch fill',
  InpaintMethod.model => 'AI fill',
};

/// A readable name for an op's engine id (`patchmatch@1` → Patch fill).
String engineLabel(String engine) {
  final name = engine.split('@').first;
  return switch (name) {
    'pushpull' => 'Spot heal',
    'telea' => 'Wire',
    'patchmatch' => 'Patch fill',
    'migan' => 'AI fill',
    'clone' => 'Clone',
    'heal' => 'Heal',
    _ => name.isEmpty ? 'Fill' : name,
  };
}

class RemoveUiState {
  const RemoveUiState({
    this.tool = RemoveTool.remove,
    this.size = defaultSize,
    this.source,
    this.pickingSource = false,
    this.pending = const [],
  });

  static const double defaultSize = 12, minSize = 1, maxSize = 100;

  final RemoveTool tool;

  /// 1–100; the radius is `size / 400` of the source long edge (as masks).
  final double size;

  /// Heal / clone source in source uv; null = not set (heal picks one).
  final (double, double)? source;

  /// The next tap on the photo sets [source] instead of painting.
  final bool pickingSource;

  /// The stroke being processed: drawn on the canvas until the result lands.
  final List<BrushStroke> pending;

  /// Stroke radius as a fraction of the source long edge.
  double get radius => size / 400;

  /// Clone needs a source before it can paint.
  bool get needsSource => tool == RemoveTool.clone && source == null;

  /// A hard round stroke (what you paint is exactly what is filled).
  BrushStroke stroke(List<(double, double)> points) => BrushStroke(
    points: List.unmodifiable(points),
    radius: radius,
    hardness: 1,
  );

  RemoveUiState copyWith({
    RemoveTool? tool,
    double? size,
    (double, double)? source,
    bool clearSource = false,
    bool? pickingSource,
    List<BrushStroke>? pending,
  }) => RemoveUiState(
    tool: tool ?? this.tool,
    size: (size ?? this.size).clamp(minSize, maxSize).toDouble(),
    source: clearSource ? null : (source ?? this.source),
    pickingSource: pickingSource ?? this.pickingSource,
    pending: pending ?? this.pending,
  );
}

class RemoveUiNotifier extends Notifier<RemoveUiState> {
  RemoveUiNotifier(this.assetId);

  final String assetId;

  @override
  RemoveUiState build() => const RemoveUiState();

  void setTool(RemoveTool tool) =>
      state = state.copyWith(tool: tool, pickingSource: false);

  void setSize(double size) => state = state.copyWith(size: size);

  /// `[` / `]`: about 15 % per step, at least 1.
  void nudgeSize(int direction) {
    final step = (state.size * 0.15).clamp(1.0, 10.0);
    setSize(state.size + direction * step);
  }

  void setSource((double, double) uv) =>
      state = state.copyWith(source: uv, pickingSource: false);

  void clearSource() => state = state.copyWith(clearSource: true);

  void startPickingSource() => state = state.copyWith(pickingSource: true);

  void setPending(List<BrushStroke> strokes) =>
      state = state.copyWith(pending: strokes);
}

final removeUiProvider =
    NotifierProvider.family<RemoveUiNotifier, RemoveUiState, String>(
      RemoveUiNotifier.new,
    );
