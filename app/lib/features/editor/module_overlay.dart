import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:lumen/features/editor/canvas_mapping.dart';
import 'package:lumen/features/editor/editor_controller.dart';
import 'package:lumen/features/editor/editor_module.dart';
import 'package:lumen/features/editor/editor_session.dart';
import 'package:lumen/features/editor/renderer/photo_renderer.dart';
import 'package:lumen/features/masks/canvas/mask_canvas.dart';
import 'package:lumen/features/portrait/face_boxes_overlay.dart';

/// Canvas tools of the active [EditorModule], drawn over the photo in
/// [PhotoCanvas.overlay] (outside crop mode).
///
/// The overlay is laid out exactly over the displayed frame. It builds one
/// [CanvasMapping] (source uv ↔ view, through crop/rotation/flips) per
/// layout and hands it to the module's tool, so every tool maps points the
/// way the renderer does. To add a module's tools: return `true` for it in
/// [hasTools] and add a case in [build]. While an overlay is shown it owns
/// pointer input on the canvas (no zoom/pan, no hold-to-compare).
class ModuleOverlay extends ConsumerWidget {
  const ModuleOverlay({super.key, required this.session, this.touch = false});

  final EditorSession session;
  final bool touch;

  /// Modules that draw on the canvas.
  static bool hasTools(EditorModule module) => switch (module) {
    EditorModule.masks || EditorModule.portrait => true,
    EditorModule.adjust => false,
  };

  /// The overlay for [module], or null when it has no canvas tools (the
  /// canvas then keeps zoom/pan and hold-to-compare).
  static Widget? forModule(
    EditorModule module, {
    required EditorSession session,
    bool touch = false,
  }) => hasTools(module)
      ? ModuleOverlay(
          key: ValueKey('module-overlay-${module.name}'),
          session: session,
          touch: touch,
        )
      : null;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = session.assetId;
    final module = ref.watch(editorModuleProvider(id));
    final geometry = ref.watch(
      editorProvider(id).select((s) => s.value?.settings.geometry),
    );
    final showingBefore = ref.watch(
      editorProvider(id).select((s) => s.value?.showingBefore ?? false),
    );
    if (geometry == null || !hasTools(module)) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, c) {
        final mapping = CanvasMapping(
          geometry: geometry,
          source: sourceSizeOf(session),
          view: c.biggest,
        );
        return switch (module) {
          EditorModule.masks => MaskCanvas(
            assetId: id,
            mapping: mapping,
            overlayRenderer: switch (session.renderer) {
              final MaskOverlayRenderer r => r,
              _ => null,
            },
            touch: touch,
            showTint: !showingBefore,
          ),
          EditorModule.portrait => FaceBoxesOverlay(
            assetId: id,
            mapping: mapping,
          ),
          EditorModule.adjust => const SizedBox.shrink(),
        };
      },
    );
  }
}

/// Pixel size of the source the renderer develops (its aspect ratio maps
/// uv to pixels): the decoded preview, else the catalog entry, else square.
Size sourceSizeOf(EditorSession session) {
  final img = session.renderer.before;
  if (img != null) return Size(img.width.toDouble(), img.height.toDouble());
  final e = session.entry;
  if (e != null && e.width > 0 && e.height > 0) {
    return Size(e.width.toDouble(), e.height.toDouble());
  }
  return const Size(1, 1);
}
