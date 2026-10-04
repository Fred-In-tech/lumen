import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/design/tokens.dart';
import 'package:lumen/features/editor/canvas_ink.dart';
import 'package:lumen/features/editor/canvas_mapping.dart';
import 'package:lumen/features/editor/editor_controller.dart';
import 'package:lumen/features/portrait/portrait_state.dart';

/// Manual Tuning Pen for skin: paint where skin retouch should apply, erase
/// where it should not (beard, hair, jewellery). Existing strokes show
/// faintly; each stroke is one history entry.
class SkinPenCanvas extends ConsumerStatefulWidget {
  const SkinPenCanvas({
    super.key,
    required this.assetId,
    required this.mapping,
  });

  final String assetId;
  final CanvasMapping mapping;

  @override
  ConsumerState<SkinPenCanvas> createState() => _SkinPenCanvasState();
}

class _SkinPenCanvasState extends ConsumerState<SkinPenCanvas> {
  final List<Offset> _view = [];
  final List<(double, double)> _uv = [];
  Offset? _pointer;

  CanvasMapping get _map => widget.mapping;

  void _start(Offset p) => setState(() {
    _view
      ..clear()
      ..add(p);
    _uv
      ..clear()
      ..add(_map.toSource(p));
  });

  void _move(Offset p) {
    final ui = ref.read(portraitUiProvider(widget.assetId));
    final step = brushPointStep(
      brushRingRadius(ui.penRadius, _map.longEdgeInView),
    );
    setState(() {
      _pointer = p;
      if (_view.isNotEmpty && (p - _view.last).distance >= step) {
        _view.add(p);
        _uv.add(_map.toSource(p));
      }
    });
  }

  void _end() {
    if (_uv.isEmpty) return;
    final ui = ref.read(portraitUiProvider(widget.assetId));
    final s = ref.read(editorProvider(widget.assetId)).value?.settings;
    final stroke = BrushStroke(
      points: List.unmodifiable(_uv),
      radius: ui.penRadius,
      hardness: ui.penHardness,
      flow: ui.penFlow,
      erase: ui.penErase,
    );
    setState(() {
      _view.clear();
      _uv.clear();
    });
    if (s == null) return;
    ref
        .read(editorProvider(widget.assetId).notifier)
        .commit(
          s.copyWith(
            portrait: s.portrait.withSkinPen([...s.portrait.skinPen, stroke]),
          ),
          label: ui.penErase ? 'Skin pen erase' : 'Skin pen paint',
        );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final ui = ref.watch(portraitUiProvider(widget.assetId));
    final strokes = ref.watch(
      editorProvider(widget.assetId)
          .select((s) => s.value?.settings.portrait.skinPen ?? const []),
    );
    final le = _map.longEdgeInView;
    return Semantics(
      label: ui.penErase
          ? 'Photo. Paint to remove skin retouch here.'
          : 'Photo. Paint to add skin retouch here.',
      child: MouseRegion(
        cursor: SystemMouseCursors.precise,
        onHover: (e) => setState(() => _pointer = e.localPosition),
        onExit: (_) => setState(() => _pointer = null),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          dragStartBehavior: DragStartBehavior.down,
          onPanStart: (d) => _start(d.localPosition),
          onPanUpdate: (d) => _move(d.localPosition),
          onPanEnd: (_) => _end(),
          onPanCancel: _end,
          onTapUp: (d) {
            _start(d.localPosition);
            _end();
          },
          child: CustomPaint(
            size: _map.view,
            painter: _PenPainter(
              existing: [
                for (final st in strokes)
                  (
                    [for (final (u, v) in st.points) _map.toView(u, v)],
                    brushRingRadius(st.radius, le),
                    st.erase,
                  ),
              ],
              live: List.of(_view),
              liveErase: ui.penErase,
              radius: brushRingRadius(ui.penRadius, le),
              hardness: ui.penHardness,
              cursor: _pointer,
              paintInk: t.success.withValues(alpha: 0.28),
              eraseInk: t.danger.withValues(alpha: 0.28),
            ),
          ),
        ),
      ),
    );
  }
}

class _PenPainter extends CustomPainter {
  _PenPainter({
    required this.existing,
    required this.live,
    required this.liveErase,
    required this.radius,
    required this.hardness,
    required this.cursor,
    required this.paintInk,
    required this.eraseInk,
  });

  final List<(List<Offset>, double, bool)> existing;
  final List<Offset> live;
  final bool liveErase;
  final double radius;
  final double hardness;
  final Offset? cursor;
  final Color paintInk;
  final Color eraseInk;

  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..save()
      ..clipRect(Offset.zero & size);
    for (final (points, r, erase) in existing) {
      paintBrushStroke(canvas, points, r, erase ? eraseInk : paintInk);
    }
    paintBrushStroke(canvas, live, radius, liveErase ? eraseInk : paintInk);
    final c = cursor;
    if (c != null) paintBrushCursor(canvas, c, radius, hardness: hardness);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PenPainter old) => true;
}
