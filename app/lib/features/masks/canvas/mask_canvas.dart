import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/design/tokens.dart';
import 'package:lumen/features/editor/canvas_ink.dart';
import 'package:lumen/features/editor/canvas_mapping.dart';
import 'package:lumen/features/editor/editor_controller.dart';
import 'package:lumen/features/editor/renderer/photo_renderer.dart';
import 'package:lumen/features/masks/canvas/mask_handles.dart';
import 'package:lumen/features/masks/canvas/mask_painter.dart';
import 'package:lumen/features/masks/canvas/mask_tint_layer.dart';
import 'package:lumen/features/masks/mask_commands.dart';
import 'package:lumen/features/masks/mask_ui_state.dart';

/// On-canvas mask tools for the Masks module:
/// * Linear: drag either end line or the centre pin (three guide lines).
/// * Radial: drag the centre, the four axis handles, the rotate knob above
///   the ellipse and the feather knob on the inner ellipse.
/// * Brush: paint or erase. The stroke is drawn as a live vector path and
///   appended as one `BrushStroke` on release (one re-rasterization).
/// * Pins of the other masks select them; the selected mask's tint shows
///   when the overlay is on or a mask row is hovered.
///
/// Hit targets are ≥ 24 px with a mouse and 44 px on touch.
class MaskCanvas extends ConsumerStatefulWidget {
  const MaskCanvas({
    super.key,
    required this.assetId,
    required this.mapping,
    this.overlayRenderer,
    this.touch = false,
    this.showTint = true,
  });

  final String assetId;
  final CanvasMapping mapping;

  /// Renders the coverage tint; null (fakes, tests) shows none.
  final MaskOverlayRenderer? overlayRenderer;
  final bool touch;

  /// False while the "before" photo is shown.
  final bool showTint;

  @override
  ConsumerState<MaskCanvas> createState() => _MaskCanvasState();
}

class _Drag {
  const _Drag(this.role, this.maskId, this.kind, this.startShape, this.startUv);
  final HandleRole role;
  final String maskId;
  final MaskKind kind;
  final Map<String, Object?> startShape;
  final (double, double) startUv;
}

class _MaskCanvasState extends ConsumerState<MaskCanvas> {
  _Drag? _drag;
  String? _strokeMask;
  final List<Offset> _strokeView = [];
  final List<(double, double)> _strokeUv = [];
  Offset? _pointer;
  HandleRole? _hover;

  double get _hitRadius => widget.touch ? 22 : 12;
  CanvasMapping get _map => widget.mapping;
  MaskCommands get _cmds => MaskCommands.of(ref, widget.assetId);
  MaskUiState get _ui => ref.read(maskUiProvider(widget.assetId));

  List<LocalMask> get _masks =>
      ref.read(editorProvider(widget.assetId)).value?.settings.masks ??
      const [];

  MaskScene _scene() => MaskScene.build(
    _masks,
    _ui.selectedIn(_masks),
    _map,
    touch: widget.touch,
  );

  LocalMask? get _brushMask {
    final m = _ui.selectedIn(_masks);
    return m != null && m.kind == MaskKind.brush && m.isSupported ? m : null;
  }

  double get _brushRadius =>
      brushRingRadius(_ui.brush.radius, _map.longEdgeInView);

  void _onPanStart(DragStartDetails d) {
    final p = d.localPosition;
    final hit = _scene().hit(p, _hitRadius);
    final selected = _ui.selectedIn(_masks);
    if (hit != null && hit.role == HandleRole.pin) {
      ref.read(maskUiProvider(widget.assetId).notifier).select(hit.maskId);
      return;
    }
    if (hit != null && selected != null) {
      _cmds.begin('${hit.role.verb} ${selected.name}');
      setState(() {
        _drag = _Drag(
          hit.role,
          selected.id,
          selected.kind,
          selected.shape,
          _map.toSource(p),
        );
      });
      return;
    }
    final brush = _brushMask;
    if (brush == null) return;
    setState(() {
      _strokeMask = brush.id;
      _strokeView
        ..clear()
        ..add(p);
      _strokeUv
        ..clear()
        ..add(_map.toSource(p));
      _pointer = p;
    });
  }

  void _onPanUpdate(DragUpdateDetails d) {
    final p = d.localPosition;
    final drag = _drag;
    if (drag != null) {
      final cur = _map.toSource(p);
      _cmds.preview(
        drag.maskId,
        (m) => m.copyWith(
          shape: dragShape(
            drag.role,
            drag.kind,
            drag.startShape,
            drag.startUv,
            cur,
            _map.source,
          ),
        ),
      );
      return;
    }
    if (_strokeMask == null) return;
    final step = brushPointStep(_brushRadius);
    setState(() {
      _pointer = p;
      if ((p - _strokeView.last).distance >= step) {
        _strokeView.add(p);
        _strokeUv.add(_map.toSource(p));
      }
    });
  }

  void _onPanEnd() {
    final drag = _drag;
    if (drag != null) {
      final m = _cmds.byId(drag.maskId);
      _cmds.end('${drag.role.verb} ${m?.name ?? 'mask'}');
      setState(() => _drag = null);
      return;
    }
    final id = _strokeMask;
    if (id == null) return;
    _cmds.appendStroke(id, _ui.brush.stroke(_strokeUv));
    setState(() {
      _strokeMask = null;
      _strokeView.clear();
      _strokeUv.clear();
      if (widget.touch) _pointer = null;
    });
  }

  void _onTapUp(TapUpDetails d) {
    final p = d.localPosition;
    final hit = _scene().hit(p, _hitRadius);
    if (hit != null && hit.role == HandleRole.pin) {
      ref.read(maskUiProvider(widget.assetId).notifier).select(hit.maskId);
      return;
    }
    if (hit != null) return;
    final brush = _brushMask;
    if (brush != null) {
      // A tap is a single dab.
      _cmds.appendStroke(brush.id, _ui.brush.stroke([_map.toSource(p)]));
    }
  }

  void _onHover(PointerHoverEvent e) {
    final hit = _scene().hit(e.localPosition, _hitRadius);
    setState(() {
      _pointer = e.localPosition;
      _hover = hit?.role;
    });
  }

  MouseCursor _cursor(bool brushMode) {
    if (_drag != null) return SystemMouseCursors.grabbing;
    if (_hover == HandleRole.pin) return SystemMouseCursors.click;
    if (_hover != null) return SystemMouseCursors.grab;
    return brushMode ? SystemMouseCursors.precise : MouseCursor.defer;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final settings = ref.watch(
      editorProvider(widget.assetId).select((s) => s.value?.settings),
    );
    final ui = ref.watch(maskUiProvider(widget.assetId));
    if (settings == null) return const SizedBox.shrink();
    final masks = settings.masks;
    final selected = ui.selectedIn(masks);
    final scene = MaskScene.build(masks, selected, _map, touch: widget.touch);
    final brushMode =
        selected != null &&
        selected.kind == MaskKind.brush &&
        selected.isSupported;
    final tintIndex = ui.tintIndexIn(masks);
    final renderer = widget.overlayRenderer;
    final ring = brushRingRadius(ui.brush.radius, _map.longEdgeInView);
    return Stack(
      fit: StackFit.expand,
      children: [
        if (renderer != null && tintIndex != null && widget.showTint)
          MaskTintLayer(
            renderer: renderer,
            settings: settings,
            index: tintIndex,
          ),
        Semantics(
          label: selected == null
              ? 'Photo. Select a mask to edit it here.'
              : brushMode
              ? 'Photo. Paint to ${ui.brush.erase ? 'erase from' : 'add to'} ${selected.name}.'
              : 'Photo. Drag the handles to shape ${selected.name}.',
          child: MouseRegion(
            cursor: _cursor(brushMode),
            onHover: _onHover,
            onExit: (_) => setState(() {
              _pointer = null;
              _hover = null;
            }),
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
                painter: MaskToolPainter(
                  scene: scene,
                  accent: t.accent,
                  touch: widget.touch,
                  hot: _drag?.role ?? _hover,
                  stroke: List.of(_strokeView),
                  strokeRadius: brushMode ? ring : 0,
                  erase: ui.brush.erase,
                  cursor: brushMode ? _pointer : null,
                  cursorHardness: ui.brush.hardness / 100,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
