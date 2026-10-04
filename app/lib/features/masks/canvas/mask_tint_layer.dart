import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:logging/logging.dart';
import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/design/tokens.dart';
import 'package:lumen/features/editor/renderer/photo_renderer.dart';
import 'package:lumen/features/masks/canvas/mask_painter.dart';

final _log = Logger('MaskTintLayer');

/// The coverage tint of mask [index] ("Show overlay"), rendered by the
/// engine in the frame's geometry and stretched over the overlay. Renders
/// coalesce (latest wins, one in flight) and re-run only when that mask's
/// coverage or the geometry changes, not for adjustment edits.
class MaskTintLayer extends StatefulWidget {
  const MaskTintLayer({
    super.key,
    required this.renderer,
    required this.settings,
    required this.index,
  });

  final MaskOverlayRenderer renderer;
  final DevelopSettings settings;
  final int index;

  @override
  State<MaskTintLayer> createState() => _MaskTintLayerState();
}

class _MaskTintLayerState extends State<MaskTintLayer> {
  ui.Image? _image;
  Object? _shownKey;
  bool _busy = false;
  bool _dirty = false;
  bool _disposed = false;

  Object? get _key {
    final masks = widget.settings.masks;
    if (widget.index < 0 || widget.index >= masks.length) return null;
    return Object.hash(
      widget.index,
      widget.settings.geometry,
      masks[widget.index].coverageKey,
    );
  }

  @override
  void initState() {
    super.initState();
    unawaited(_request());
  }

  @override
  void didUpdateWidget(MaskTintLayer old) {
    super.didUpdateWidget(old);
    if (_key != _shownKey) unawaited(_request());
  }

  Future<void> _request() async {
    if (_busy) {
      _dirty = true;
      return;
    }
    final key = _key;
    if (key == null) return;
    _busy = true;
    ui.Image? img;
    try {
      img = await widget.renderer.renderMaskOverlay(
        widget.settings,
        widget.index,
        tint: CanvasInk.maskTint,
      );
    } on StateError catch (e) {
      // The session closed mid-render: nothing to show.
      _log.fine('overlay skipped: $e');
    } on Exception catch (e) {
      _log.warning('overlay failed: $e');
    } finally {
      _busy = false;
    }
    if (_disposed) {
      img?.dispose();
      return;
    }
    final old = _image;
    setState(() {
      _image = img;
      _shownKey = key;
    });
    // Frames already recorded keep the old image alive in the engine.
    old?.dispose();
    if (_dirty || _key != key) {
      _dirty = false;
      unawaited(_request());
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _image?.dispose();
    _image = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final img = _image;
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: img == null ? 0 : 1,
        duration: Motion.of(context, Motion.fast),
        child: img == null
            ? const SizedBox.expand()
            : CustomPaint(size: Size.infinite, painter: _ImagePainter(img)),
      ),
    );
  }
}

class _ImagePainter extends CustomPainter {
  _ImagePainter(this.image);
  final ui.Image image;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Offset.zero & size,
      Paint()..filterQuality = FilterQuality.low,
    );
  }

  @override
  bool shouldRepaint(_ImagePainter old) => !identical(old.image, image);
}
