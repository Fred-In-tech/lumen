import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/design/tokens.dart';
import 'package:lumen/design/type.dart';
import 'package:lumen/features/editor/canvas_mapping.dart';
import 'package:lumen/features/editor/editor_controller.dart';
import 'package:lumen/features/masks/canvas/mask_painter.dart';
import 'package:lumen/features/portrait/portrait_state.dart';

/// Face boxes with group chips over the photo (Evoto's face-detection mode).
/// Tapping a face edits that person (Individual); tapping elsewhere returns to
/// the group they belong to.
class FaceBoxesOverlay extends ConsumerWidget {
  const FaceBoxesOverlay({
    super.key,
    required this.assetId,
    required this.mapping,
  });

  final String assetId;
  final CanvasMapping mapping;

  /// The face box corners in view coordinates (a quad under rotation).
  static List<Offset> quadOf(DetectedFace f, CanvasMapping m) {
    final b = f.box;
    return [
      m.toView(b.x, b.y),
      m.toView(b.x + b.width, b.y),
      m.toView(b.x + b.width, b.y + b.height),
      m.toView(b.x, b.y + b.height),
    ];
  }

  /// The face under [p], smallest first so nested faces stay selectable.
  static DetectedFace? hitTest(
    List<DetectedFace> faces,
    CanvasMapping m,
    Offset p,
  ) {
    final hits =
        [
          for (final f in faces)
            if ((Path()..addPolygon(quadOf(f, m), true)).contains(p)) f,
        ]..sort(
          (a, b) => (a.box.width * a.box.height).compareTo(
            b.box.width * b.box.height,
          ),
        );
    return hits.firstOrNull;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ui = ref.watch(portraitUiProvider(assetId));
    final faces = ref.watch(portraitFacesProvider(assetId))?.faces ?? const [];
    final portrait = ref.watch(
      editorProvider(assetId)
          .select((s) => s.value?.settings.portrait ?? PortraitSettings.empty),
    );
    if (!ui.showFaces || faces.isEmpty) return const SizedBox.expand();
    final t = context.tokens;
    final notifier = ref.read(portraitUiProvider(assetId).notifier);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: (d) {
        final hit = hitTest(faces, mapping, d.localPosition);
        if (hit == null) {
          notifier.clearSelection();
        } else {
          notifier.selectFace(hit);
        }
      },
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _FaceBoxPainter(
                quads: [for (final f in faces) quadOf(f, mapping)],
                selected: [for (final f in faces) f.id == ui.selectedFaceId],
                accent: t.accent,
              ),
            ),
          ),
          for (final f in faces)
            _chip(
              context,
              face: f,
              anchor: quadOf(f, mapping).reduce(
                (a, b) => Offset(
                  a.dx < b.dx ? a.dx : b.dx,
                  a.dy < b.dy ? a.dy : b.dy,
                ),
              ),
              selected: f.id == ui.selectedFaceId,
              individual: portrait.hasIndividual(f.personId ?? f.id),
            ),
        ],
      ),
    );
  }

  Widget _chip(
    BuildContext context, {
    required DetectedFace face,
    required Offset anchor,
    required bool selected,
    required bool individual,
  }) {
    final t = context.tokens;
    final label = face.group == FaceGroup.all ? 'Face' : face.group.label;
    return Positioned(
      left: anchor.dx,
      top: anchor.dy - 22,
      child: IgnorePointer(
        child: Container(
          height: 18,
          padding: const EdgeInsets.symmetric(horizontal: Sp.s1_5),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? t.accent : CanvasInk.pinFill,
            borderRadius: BorderRadius.circular(Rad.pill),
          ),
          child: Text(
            individual ? '$label · edited' : label,
            style: LumenType.micro().copyWith(
              color: selected ? t.textOnAccent : Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

class _FaceBoxPainter extends CustomPainter {
  _FaceBoxPainter({
    required this.quads,
    required this.selected,
    required this.accent,
  });

  final List<List<Offset>> quads;
  final List<bool> selected;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i < quads.length; i++) {
      final path = Path()..addPolygon(quads[i], true);
      canvas
        ..drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3
            ..color = CanvasInk.halo,
        )
        ..drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = selected[i] ? 2 : 1.25
            ..color = selected[i] ? accent : CanvasInk.line,
        );
    }
  }

  @override
  bool shouldRepaint(_FaceBoxPainter old) =>
      old.accent != accent ||
      old.quads.length != quads.length ||
      !_sameQuads(old.quads, quads) ||
      !_sameFlags(old.selected, selected);

  static bool _sameQuads(List<List<Offset>> a, List<List<Offset>> b) {
    for (var i = 0; i < a.length; i++) {
      for (var j = 0; j < 4; j++) {
        if (a[i][j] != b[i][j]) return false;
      }
    }
    return true;
  }

  static bool _sameFlags(List<bool> a, List<bool> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
