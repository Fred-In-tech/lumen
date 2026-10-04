import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:lumen/features/editor/canvas_ink.dart';
import 'package:lumen/features/editor/canvas_mapping.dart';
import 'package:lumen/features/remove/remove_service.dart';
import 'package:lumen/features/remove/remove_status.dart';
import 'package:lumen/features/remove/remove_ui_state.dart';
import 'package:lumen/widgets/toast.dart';

/// Brush ink for removal strokes: translucent white, like Lightroom.
const kRemoveStrokeInk = Color(0x8CFFFFFF);

/// The Remove module's canvas tool: paint a stroke, release, and the
/// stroke is removed (healed / cloned). Alt/Option-click sets the heal or
/// clone source on desktop; on touch, "Set source" in the panel makes the
/// next tap set it (and clone asks for one before its first stroke).
class RemoveCanvas extends ConsumerStatefulWidget {
  const RemoveCanvas({
    super.key,
    required this.assetId,
    required this.mapping,
    this.touch = false,
  });

  final String assetId;
  final CanvasMapping mapping;
  final bool touch;

  @override
  ConsumerState<RemoveCanvas> createState() => _RemoveCanvasState();
}

class _RemoveCanvasState extends ConsumerState<RemoveCanvas> {
  final List<Offset> _strokeView = [];
  final List<(double, double)> _strokeUv = [];
  Offset? _pointer;
  bool _painting = false;

  CanvasMapping get _map => widget.mapping;
  RemoveUiState get _ui => ref.read(removeUiProvider(widget.assetId));
  RemoveUiNotifier get _uiCtl =>
      ref.read(removeUiProvider(widget.assetId).notifier);
  bool get _running =>
      ref.read(removeStatusProvider(widget.assetId)) is RemoveRunning;

  bool get _altHeld => !widget.touch && HardwareKeyboard.instance.isAltPressed;

  /// Sets the source when picking (touch two-step, "Set source") or with
  /// Alt held. True when [p] was consumed that way.
  bool _maybeSetSource(Offset p) {
    final ui = _ui;
    if (!ui.tool.usesSource) return false;
    if (ui.pickingSource || _altHeld || (widget.touch && ui.needsSource)) {
      _uiCtl.setSource(_map.toSource(p));
      return true;
    }
    return false;
  }

  void _hintSource() => showToast(
    context,
    widget.touch
        ? 'Tap the photo to choose what to copy, then paint.'
        : 'Alt-click (Option-click) to choose what to copy, then paint.',
  );

  void _onPanStart(DragStartDetails d) {
    if (_running || _maybeSetSource(d.localPosition)) return;
    if (_ui.needsSource) {
      _hintSource();
      return;
    }
    final p = d.localPosition;
    setState(() {
      _painting = true;
      _pointer = p;
      _strokeView
        ..clear()
        ..add(p);
      _strokeUv
        ..clear()
        ..add(_map.toSource(p));
    });
  }

  void _onPanUpdate(DragUpdateDetails d) {
    if (!_painting) return;
    final p = d.localPosition;
    final step = brushPointStep(
      brushRingRadius(_ui.radius, _map.longEdgeInView),
    );
    setState(() {
      _pointer = p;
      if ((p - _strokeView.last).distance >= step) {
        _strokeView.add(p);
        _strokeUv.add(_map.toSource(p));
      }
    });
  }

  void _onPanEnd() {
    if (!_painting) return;
    final uv = List.of(_strokeUv);
    setState(() {
      _painting = false;
      _strokeView.clear();
      _strokeUv.clear();
      if (widget.touch) _pointer = null;
    });
    unawaited(_apply(uv));
  }

  void _onTapUp(TapUpDetails d) {
    if (_running || _maybeSetSource(d.localPosition)) return;
    if (_ui.needsSource) {
      _hintSource();
      return;
    }
    unawaited(_apply([_map.toSource(d.localPosition)])); // a single dab
  }

  /// Runs the tool on one stroke through [uv]; the stroke stays drawn
  /// until the service finishes.
  Future<void> _apply(List<(double, double)> uv) async {
    if (uv.isEmpty) return;
    final ui = _ui;
    final strokes = [ui.stroke(uv)];
    final source = ui.source;
    final offset = source == null
        ? null
        : (source.$1 - uv.first.$1, source.$2 - uv.first.$2);
    final service = ref.read(removeServiceProvider);
    final uiCtl = _uiCtl..setPending(strokes);
    try {
      switch (ui.tool) {
        case RemoveTool.remove:
          await service.remove(widget.assetId, strokes);
        case RemoveTool.heal:
          await service.healAt(widget.assetId, strokes, offset: offset);
        case RemoveTool.clone:
          if (offset != null) {
            await service.cloneAt(widget.assetId, strokes, offset);
          }
      }
    } on StateError {
      // A run is already going (the UI blocks input meanwhile).
    } finally {
      uiCtl.setPending(const []);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ui = ref.watch(removeUiProvider(widget.assetId));
    final running =
        ref.watch(removeStatusProvider(widget.assetId)) is RemoveRunning;
    final ring = brushRingRadius(ui.radius, _map.longEdgeInView);
    final le = _map.longEdgeInView;
    Offset? crosshair;
    final src = ui.source;
    if (src != null && ui.tool.usesSource) {
      if (_painting && _strokeUv.isNotEmpty && _pointer != null) {
        final start = _strokeUv.first, now = _map.toSource(_pointer!);
        crosshair = _map.toView(
          src.$1 + now.$1 - start.$1,
          src.$2 + now.$2 - start.$2,
        );
      } else {
        crosshair = _map.toView(src.$1, src.$2);
      }
    }
    final semantics = switch (ui.tool) {
      _ when running => 'Photo. Working on your last stroke.',
      RemoveTool.remove => 'Photo. Paint over what you want to remove.',
      RemoveTool.heal => 'Photo. Paint over a blemish to heal it.',
      RemoveTool.clone when ui.needsSource =>
        'Photo. Choose the area to copy first.',
      RemoveTool.clone => 'Photo. Paint to copy the source area here.',
    };
    return Semantics(
      label: semantics,
      child: MouseRegion(
        cursor: running ? SystemMouseCursors.wait : SystemMouseCursors.precise,
        onHover: (e) => setState(() => _pointer = e.localPosition),
        onExit: (_) => setState(() => _pointer = null),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          dragStartBehavior: DragStartBehavior.down,
          onTapUp: _onTapUp,
          onPanStart: _onPanStart,
          onPanUpdate: _onPanUpdate,
          onPanEnd: (_) => _onPanEnd(),
          onPanCancel: _onPanEnd,
          child: CustomPaint(
            size: _map.view,
            painter: RemoveToolPainter(
              stroke: List.of(_strokeView),
              pending: [
                for (final s in ui.pending)
                  (
                    [for (final (u, v) in s.points) _map.toView(u, v)],
                    brushRingRadius(s.radius, le),
                  ),
              ],
              radius: ring,
              cursor: running ? null : _pointer,
              crosshair: crosshair,
            ),
          ),
        ),
      ),
    );
  }
}

/// Paints the live stroke, strokes still being processed, the brush ring
/// and the heal/clone source crosshair.
class RemoveToolPainter extends CustomPainter {
  RemoveToolPainter({
    this.stroke = const [],
    this.pending = const [],
    required this.radius,
    this.cursor,
    this.crosshair,
  });

  final List<Offset> stroke;
  final List<(List<Offset>, double)> pending;
  final double radius;
  final Offset? cursor;
  final Offset? crosshair;

  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..save()
      ..clipRect(Offset.zero & size);
    for (final (points, r) in pending) {
      paintBrushStroke(canvas, points, r, kRemoveStrokeInk);
    }
    paintBrushStroke(canvas, stroke, radius, kRemoveStrokeInk);
    final c = crosshair;
    if (c != null) paintCrosshair(canvas, c);
    final p = cursor;
    if (p != null) paintBrushCursor(canvas, p, radius);
    canvas.restore();
  }

  @override
  bool shouldRepaint(RemoveToolPainter old) => true;
}
