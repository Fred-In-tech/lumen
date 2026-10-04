import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/features/editor/canvas_ink.dart';
import 'package:lumen/features/editor/canvas_mapping.dart';
import 'package:lumen/features/editor/editor_controller.dart';
import 'package:lumen/features/portrait/portrait_state.dart';

String liquifyLabel(LiquifyTool t) => switch (t) {
  LiquifyTool.push => 'Push',
  LiquifyTool.reconstruct => 'Reconstruct',
  LiquifyTool.pucker => 'Pucker',
  LiquifyTool.bloat => 'Bloat',
};

/// Liquify brush on the photo: the stroke previews live (the renderer grows
/// the warp incrementally) and becomes one history entry on release.
class LiquifyCanvas extends ConsumerStatefulWidget {
  const LiquifyCanvas({
    super.key,
    required this.assetId,
    required this.mapping,
  });

  final String assetId;
  final CanvasMapping mapping;

  @override
  ConsumerState<LiquifyCanvas> createState() => _LiquifyCanvasState();
}

class _LiquifyCanvasState extends ConsumerState<LiquifyCanvas> {
  LiquifyStroke? _live;
  List<LiquifyStroke> _done = const [];
  Offset? _pointer;
  Offset? _last;

  EditorController get _ctl =>
      ref.read(editorProvider(widget.assetId).notifier);

  void _start(Offset p) {
    final s = ref.read(editorProvider(widget.assetId)).value?.settings;
    if (s == null) return;
    final ui = ref.read(portraitUiProvider(widget.assetId));
    _done = s.liquify;
    _last = p;
    _live = LiquifyStroke(
      tool: ui.liquifyTool,
      points: [widget.mapping.toSource(p)],
      radius: ui.liquifyRadius,
      strength: ui.liquifyStrength,
    );
    _ctl.beginGesture('Liquify');
    _preview();
  }

  void _move(Offset p) {
    final live = _live;
    final last = _last;
    if (live == null || last == null) return;
    setState(() => _pointer = p);
    final ring = brushRingRadius(live.radius, widget.mapping.longEdgeInView);
    if ((p - last).distance < brushPointStep(ring) * 0.5) return;
    _last = p;
    _live = live.withPoint(widget.mapping.toSource(p));
    _preview();
  }

  void _preview() {
    final s = ref.read(editorProvider(widget.assetId)).value?.settings;
    final live = _live;
    if (s == null || live == null) return;
    _ctl.preview(s.copyWith(liquify: [..._done, live]));
  }

  void _end() {
    final live = _live;
    if (live == null) return;
    _live = null;
    _ctl.commitGesture(
      label: 'Liquify ${liquifyLabel(live.tool).toLowerCase()}',
      kind: HistoryKind.liquify,
    );
  }

  @override
  Widget build(BuildContext context) {
    final ui = ref.watch(portraitUiProvider(widget.assetId));
    final ring = brushRingRadius(
      ui.liquifyRadius,
      widget.mapping.longEdgeInView,
    );
    return Semantics(
      label: 'Photo. Drag to ${liquifyLabel(ui.liquifyTool).toLowerCase()}.',
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
          child: CustomPaint(
            size: widget.mapping.view,
            painter: _CursorPainter(cursor: _pointer, radius: ring),
          ),
        ),
      ),
    );
  }
}

class _CursorPainter extends CustomPainter {
  _CursorPainter({required this.cursor, required this.radius});

  final Offset? cursor;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final c = cursor;
    if (c != null) paintBrushCursor(canvas, c, radius, hardness: 0.5);
  }

  @override
  bool shouldRepaint(_CursorPainter old) =>
      old.cursor != cursor || old.radius != radius;
}
