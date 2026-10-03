import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/features/crop/crop_panel.dart';
import 'package:lumen/features/editor/editor_controller.dart';

/// Crop frame drawn over the uncropped image (DESIGN.md §3.6).
///
/// The canvas shows the oriented, straightened image without the crop while
/// crop mode is on; this overlay edits `geometry.crop` in that space.
class CropOverlay extends ConsumerStatefulWidget {
  const CropOverlay({super.key, required this.assetId, required this.imageAspect});

  final String assetId;
  final double imageAspect;

  @override
  ConsumerState<CropOverlay> createState() => _CropOverlayState();
}

enum _Handle { move, tl, tr, bl, br }

class _CropOverlayState extends ConsumerState<CropOverlay> {
  _Handle? _handle;
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    final g = ref.watch(editorProvider(widget.assetId).select((s) => s.value?.settings.geometry ?? Geometry.none));
    final ctl = ref.read(editorProvider(widget.assetId).notifier);
    final ratio = kAspectPresets[g.aspect];
    return LayoutBuilder(builder: (context, c) {
      final size = Size(c.maxWidth, c.maxHeight);
      final r = g.crop;
      final rect = Rect.fromLTRB(r.left * size.width, r.top * size.height, r.right * size.width, r.bottom * size.height);

      _Handle hit(Offset p) {
        const k = 24.0;
        if ((p - rect.topLeft).distance < k) return _Handle.tl;
        if ((p - rect.topRight).distance < k) return _Handle.tr;
        if ((p - rect.bottomLeft).distance < k) return _Handle.bl;
        if ((p - rect.bottomRight).distance < k) return _Handle.br;
        return _Handle.move;
      }

      void update(Offset delta) {
        final s = ref.read(editorProvider(widget.assetId)).value?.settings;
        if (s == null || _handle == null) return;
        final dx = delta.dx / size.width, dy = delta.dy / size.height;
        var l = s.geometry.crop.left, t = s.geometry.crop.top, rr = s.geometry.crop.right, b = s.geometry.crop.bottom;
        switch (_handle!) {
          case _Handle.move:
            final w = rr - l, h = b - t;
            l = (l + dx).clamp(0.0, 1 - w);
            t = (t + dy).clamp(0.0, 1 - h);
            rr = l + w;
            b = t + h;
          case _Handle.tl:
            l += dx;
            t += dy;
          case _Handle.tr:
            rr += dx;
            t += dy;
          case _Handle.bl:
            l += dx;
            b += dy;
          case _Handle.br:
            rr += dx;
            b += dy;
        }
        var next = CropRect.normalized(l, t, rr, b);
        if (ratio != null && _handle != _Handle.move) {
          final imgAspect = size.width / size.height;
          final wantH = next.width * imgAspect / ratio;
          final top = (_handle == _Handle.tl || _handle == _Handle.tr) ? next.bottom - wantH : next.top;
          next = CropRect.normalized(next.left, top, next.right, top + wantH);
        }
        ctl.preview(s.copyWith(geometry: s.geometry.copyWith(crop: next, aspect: g.aspect == 'original' ? 'free' : g.aspect)));
      }

      return GestureDetector(
        onPanStart: (d) {
          ctl.beginGesture('Crop');
          setState(() {
            _handle = hit(d.localPosition);
            _dragging = true;
          });
        },
        onPanUpdate: (d) => update(d.delta),
        onPanEnd: (_) {
          setState(() => _dragging = false);
          ctl.commitGesture(label: 'Crop', kind: HistoryKind.geometry);
        },
        child: CustomPaint(size: size, painter: _CropPainter(rect, grid: _dragging)),
      );
    });
  }
}

class _CropPainter extends CustomPainter {
  _CropPainter(this.rect, {required this.grid});
  final Rect rect;
  final bool grid;

  @override
  void paint(Canvas canvas, Size size) {
    final outside = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRect(rect);
    canvas.drawPath(outside, Paint()..color = const Color(0x99000000));
    canvas.drawRect(rect, Paint()
      ..color = const Color(0xCCFFFFFF)
      ..style = PaintingStyle.stroke);
    if (grid) {
      final p = Paint()..color = const Color(0x59FFFFFF);
      for (var i = 1; i < 3; i++) {
        canvas.drawLine(Offset(rect.left + rect.width * i / 3, rect.top), Offset(rect.left + rect.width * i / 3, rect.bottom), p);
        canvas.drawLine(Offset(rect.left, rect.top + rect.height * i / 3), Offset(rect.right, rect.top + rect.height * i / 3), p);
      }
    }
    final h = Paint()
      ..color = Colors.white
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;
    const l = 18.0;
    for (final c in [rect.topLeft, rect.topRight, rect.bottomLeft, rect.bottomRight]) {
      final sx = c.dx == rect.left ? 1 : -1, sy = c.dy == rect.top ? 1 : -1;
      canvas.drawLine(c, c + Offset(l * sx, 0), h);
      canvas.drawLine(c, c + Offset(0, l * sy), h);
    }
  }

  @override
  bool shouldRepaint(_CropPainter o) => o.rect != rect || o.grid != grid;
}
