import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lumen_core/lumen_core.dart';

/// Progress of the remove / heal / clone tool for one photo.
sealed class RemoveStatus {
  const RemoveStatus();
}

final class RemoveIdle extends RemoveStatus {
  const RemoveIdle();
}

/// A run is in progress. [method] is null while the photo loads and the
/// engine is being chosen, and always null for clone and heal.
final class RemoveRunning extends RemoveStatus {
  const RemoveRunning({required this.kind, this.method});

  final HealKind kind;
  final InpaintMethod? method;
}

/// The run failed; [message] is safe to show to the user.
final class RemoveFailed extends RemoveStatus {
  const RemoveFailed({required this.kind, required this.message});

  final HealKind kind;
  final String message;
}

/// The run committed [ops] as one history entry.
final class RemoveDone extends RemoveStatus {
  const RemoveDone({
    required this.kind,
    required this.ops,
    this.method,
    this.note,
  });

  final HealKind kind;
  final List<HealOp> ops;

  /// The engine that made the fill (after any fallback).
  final InpaintMethod? method;

  /// Something the user should know, e.g. the AI fill fell back.
  final String? note;

  /// An AI model generated the fill (show the AI label).
  bool get ai => ops.any((o) => o.ai);

  /// The hole touched a detected face (show the warning).
  bool get faceIntersect => ops.any((o) => o.faceIntersect);
}

class RemoveStatusNotifier extends Notifier<RemoveStatus> {
  RemoveStatusNotifier(this.assetId);

  final String assetId;

  @override
  RemoveStatus build() => const RemoveIdle();

  /// Written by `RemoveService`.
  void report(RemoveStatus status) => state = status;

  /// Clears a finished or failed status once the UI has shown it.
  void dismiss() {
    if (state is! RemoveRunning) state = const RemoveIdle();
  }
}

final removeStatusProvider =
    NotifierProvider.family<RemoveStatusNotifier, RemoveStatus, String>(
      RemoveStatusNotifier.new,
    );
