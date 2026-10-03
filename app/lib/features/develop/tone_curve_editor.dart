import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/design/tokens.dart';
import 'package:lumen/design/type.dart';
import 'package:lumen/features/editor/editor_controller.dart';

/// Point-curve editor with RGB/R/G/B channels (DESIGN.md §4.6).
class ToneCurveEditor extends ConsumerStatefulWidget {
  const ToneCurveEditor({super.key, required this.assetId});
  final String assetId;

  @override
  ConsumerState<ToneCurveEditor> createState() => _ToneCurveEditorState();
}

class _ToneCurveEditorState extends ConsumerState<ToneCurveEditor> {
  CurveChannel _channel = CurveChannel.master;
  int? _dragIndex;
  CurvePoint? _readout;

  static const _channelColors = {
    CurveChannel.master: Color(0xFFEDEDED),
    CurveChannel.red: Color(0xFFFF5A5A),
    CurveChannel.green: Color(0xFF5AD17A),
    CurveChannel.blue: Color(0xFF5A8CFF),
  };

  EditorController get _ctl => ref.read(editorProvider(widget.assetId).notifier);
  DevelopSettings? get _settings => ref.read(editorProvider(widget.assetId)).value?.settings;

  CurvePoint _toCurve(Offset p, double size) =>
      CurvePoint((p.dx / size * 255).clamp(0, 255).toDouble(), ((1 - p.dy / size) * 255).clamp(0, 255).toDouble());

  void _update(ToneCurve curve) {
    final s = _settings;
    if (s != null) _ctl.preview(s.copyWith(curves: s.curves.withChannel(_channel, curve)));
  }

  void _onPanStart(Offset local, double size) {
    final s = _settings;
    if (s == null) return;
    _ctl.beginGesture('Tone curve');
    final curve = s.curves.channel(_channel);
    final p = _toCurve(local, size);
    var idx = -1;
    for (var i = 0; i < curve.points.length; i++) {
      final c = curve.points[i];
      if ((c.x - p.x).abs() < 12 && (c.y - p.y).abs() < 20) idx = i;
    }
    if (idx < 0 && curve.points.length < ToneCurve.kMaxPoints) {
      final pts = [...curve.points, CurvePoint(p.x, curve.evaluate(p.x))]..sort((a, b) => a.x.compareTo(b.x));
      idx = pts.indexWhere((q) => q.x == p.x);
      _update(ToneCurve(List.unmodifiable(pts)));
    }
    setState(() => _dragIndex = idx < 0 ? null : idx);
  }

  void _onPanUpdate(Offset local, double size) {
    final s = _settings;
    final i = _dragIndex;
    if (s == null || i == null) return;
    final curve = s.curves.channel(_channel);
    if (i >= curve.points.length) return;
    final p = _toCurve(local, size);
    final pts = [...curve.points];
    final isEnd = i == 0 || i == pts.length - 1;
    final lo = i == 0 ? 0.0 : pts[i - 1].x + 1;
    final hi = i == pts.length - 1 ? 255.0 : pts[i + 1].x - 1;
    pts[i] = CurvePoint(isEnd ? pts[i].x : p.x.clamp(lo, hi).toDouble(), p.y);
    setState(() => _readout = pts[i]);
    _update(ToneCurve(List.unmodifiable(pts)));
  }

  void _onPanEnd() {
    setState(() {
      _dragIndex = null;
      _readout = null;
    });
    _ctl.commitGesture(label: 'Tone curve', kind: HistoryKind.curve);
  }

  void _removeNear(Offset local, double size) {
    final s = _settings;
    if (s == null) return;
    final curve = s.curves.channel(_channel);
    final p = _toCurve(local, size);
    for (var i = 1; i < curve.points.length - 1; i++) {
      final c = curve.points[i];
      if ((c.x - p.x).abs() < 12 && (c.y - p.y).abs() < 20) {
        final pts = [...curve.points]..removeAt(i);
        _ctl.commit(s.copyWith(curves: s.curves.withChannel(_channel, ToneCurve(List.unmodifiable(pts)))),
            label: 'Remove curve point', kind: HistoryKind.curve);
        return;
      }
    }
    _ctl.commit(s.copyWith(curves: s.curves.withChannel(_channel, ToneCurve.identity)),
        label: 'Reset curve', kind: HistoryKind.curve);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final curves = ref.watch(editorProvider(widget.assetId).select((v) => v.value?.settings.curves ?? CurveSet.identity));
    final curve = curves.channel(_channel);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        for (final c in CurveChannel.values)
          Padding(
            padding: const EdgeInsets.only(right: Sp.s1),
            child: GestureDetector(
              onTap: () => setState(() => _channel = c),
              child: AnimatedContainer(
                duration: Motion.fast,
                height: 24,
                padding: const EdgeInsets.symmetric(horizontal: Sp.s2),
                decoration: BoxDecoration(
                  color: c == _channel ? t.surface3 : t.surface2,
                  borderRadius: BorderRadius.circular(Rad.pill),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(width: 7, height: 7, decoration: BoxDecoration(color: _channelColors[c], shape: BoxShape.circle)),
                  const SizedBox(width: 4),
                  Text(c == CurveChannel.master ? 'RGB' : c.name[0].toUpperCase(),
                      style: LumenType.caption().copyWith(color: c == _channel ? t.textPrimary : t.textSecondary)),
                ]),
              ),
            ),
          ),
        const Spacer(),
        if (_readout != null)
          Text('In ${_readout!.x.round()} · Out ${_readout!.y.round()}', style: LumenType.value().copyWith(color: t.textSecondary)),
      ]),
      const SizedBox(height: Sp.s2),
      AspectRatio(
        aspectRatio: 1,
        child: LayoutBuilder(builder: (context, c) {
          final size = c.maxWidth;
          return GestureDetector(
            onPanStart: (d) => _onPanStart(d.localPosition, size),
            onPanUpdate: (d) => _onPanUpdate(d.localPosition, size),
            onPanEnd: (_) => _onPanEnd(),
            onDoubleTapDown: (d) => _removeNear(d.localPosition, size),
            onDoubleTap: () {},
            child: CustomPaint(
              size: Size.square(size),
              painter: _CurvePainter(curve: curve, color: _channelColors[_channel]!, grid: t.line, base: t.lineStrong, bg: t.surface0, active: _dragIndex, accent: t.accent),
            ),
          );
        }),
      ),
      Padding(
        padding: const EdgeInsets.only(top: Sp.s1),
        child: Text('Drag to add or move points · double-click a point to remove',
            style: LumenType.caption().copyWith(color: t.textTertiary)),
      ),
    ]);
  }
}

class _CurvePainter extends CustomPainter {
  _CurvePainter({
    required this.curve,
    required this.color,
    required this.grid,
    required this.base,
    required this.bg,
    required this.active,
    required this.accent,
  });

  final ToneCurve curve;
  final Color color;
  final Color grid;
  final Color base;
  final Color bg;
  final int? active;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    canvas.drawRect(Offset.zero & size, Paint()..color = bg);
    final g = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var i = 1; i < 4; i++) {
      canvas.drawLine(Offset(s * i / 4, 0), Offset(s * i / 4, s), g);
      canvas.drawLine(Offset(0, s * i / 4), Offset(s, s * i / 4), g);
    }
    canvas.drawLine(Offset(0, s), Offset(s, 0), Paint()
      ..color = base
      ..strokeWidth = 1);
    final path = Path();
    for (var x = 0; x <= 255; x++) {
      final y = curve.evaluate(x.toDouble());
      final o = Offset(x / 255 * s, (1 - y / 255) * s);
      x == 0 ? path.moveTo(o.dx, o.dy) : path.lineTo(o.dx, o.dy);
    }
    canvas.drawPath(path, Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5);
    for (var i = 0; i < curve.points.length; i++) {
      final p = curve.points[i];
      final o = Offset(p.x / 255 * s, (1 - p.y / 255) * s);
      canvas.drawCircle(o, 5, Paint()..color = i == active ? accent : bg);
      canvas.drawCircle(o, 5, Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5);
    }
  }

  @override
  bool shouldRepaint(_CurvePainter o) => o.curve != curve || o.color != color || o.active != active;
}
