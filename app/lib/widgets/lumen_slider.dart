import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:lumen/design/tokens.dart';
import 'package:lumen/design/type.dart';

/// The develop slider (DESIGN.md §4.1): label row + track row.
///
/// Gesture contract: [onChangeStart] → many [onChanged] → [onChangeEnd].
/// Discrete changes (keyboard, typed value, track click) call [onCommit].
class LumenSlider extends StatefulWidget {
  const LumenSlider({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    this.defaultValue = 0,
    this.bipolar = true,
    this.step = 1,
    this.decimals = 0,
    this.trackGradient,
    this.aiReason,
    this.touch = false,
    this.onChangeStart,
    this.onChanged,
    this.onChangeEnd,
    required this.onCommit,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final double defaultValue;
  final bool bipolar;
  final double step;
  final int decimals;

  /// Colored track (temp, tint, HSL); replaces the accent fill.
  final Gradient? trackGradient;

  /// Non-null when the value was set by AI and not touched since (shows the dot).
  final String? aiReason;
  final bool touch;
  final VoidCallback? onChangeStart;
  final ValueChanged<double>? onChanged;
  final VoidCallback? onChangeEnd;
  final ValueChanged<double> onCommit;

  @override
  State<LumenSlider> createState() => _LumenSliderState();
}

class _LumenSliderState extends State<LumenSlider> {
  final FocusNode _focus = FocusNode();
  bool _hover = false;
  bool _dragging = false;
  bool _editing = false;
  double _dragStartValue = 0;
  double _dragDx = 0;
  late final TextEditingController _field = TextEditingController();

  double get _range => widget.max - widget.min;

  String _format(double v) => widget.bipolar ? formatSigned(v, decimals: widget.decimals) : v.toStringAsFixed(widget.decimals);

  double _clamp(double v) => v.clamp(widget.min, widget.max).toDouble();

  double _snap(double v) {
    final s = widget.step;
    return _clamp((v / s).roundToDouble() * s);
  }

  @override
  void dispose() {
    _focus.dispose();
    _field.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    final keys = HardwareKeyboard.instance;
    final mult = keys.isShiftPressed ? 10.0 : (keys.isAltPressed ? 0.1 : 1.0);
    double? next;
    if (e.logicalKey == LogicalKeyboardKey.arrowRight || e.logicalKey == LogicalKeyboardKey.arrowUp) {
      next = widget.value + widget.step * mult;
    } else if (e.logicalKey == LogicalKeyboardKey.arrowLeft || e.logicalKey == LogicalKeyboardKey.arrowDown) {
      next = widget.value - widget.step * mult;
    } else if (e.logicalKey == LogicalKeyboardKey.home) {
      next = widget.min;
    } else if (e.logicalKey == LogicalKeyboardKey.end) {
      next = widget.max;
    } else if (e.logicalKey == LogicalKeyboardKey.backspace || e.logicalKey == LogicalKeyboardKey.delete) {
      next = widget.defaultValue;
    }
    if (next == null) return KeyEventResult.ignored;
    widget.onCommit(_clamp(next));
    return KeyEventResult.handled;
  }

  void _startEdit() {
    setState(() => _editing = true);
    _field.text = widget.value.toStringAsFixed(widget.decimals);
    _field.selection = TextSelection(baseOffset: 0, extentOffset: _field.text.length);
  }

  void _finishEdit({required bool commit}) {
    if (commit) {
      final raw = _field.text.trim().replaceAll('−', '-').replaceAll('+', '');
      double? v;
      final frac = RegExp(r'^(-?\d+)/(\d+)$').firstMatch(raw);
      if (frac != null) {
        final d = double.parse(frac.group(2)!);
        if (d != 0) v = double.parse(frac.group(1)!) / d;
      } else {
        v = double.tryParse(raw);
      }
      if (v != null) widget.onCommit(_clamp(v));
    }
    setState(() => _editing = false);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final modified = (widget.value - widget.defaultValue).abs() > 1e-9;
    final labelStyle = LumenType.label(touch: widget.touch).copyWith(color: modified ? t.textPrimary : t.textSecondary);
    final trackHeight = widget.touch ? 32.0 : 20.0;
    return Semantics(
      slider: true,
      label: widget.label,
      value: _format(widget.value),
      increasedValue: _format(_clamp(widget.value + widget.step)),
      decreasedValue: _format(_clamp(widget.value - widget.step)),
      hint: widget.aiReason == null ? null : 'Set by AI: ${widget.aiReason}',
      onIncrease: () => widget.onCommit(_clamp(widget.value + widget.step)),
      onDecrease: () => widget.onCommit(_clamp(widget.value - widget.step)),
      child: Focus(
        focusNode: _focus,
        onKeyEvent: _onKey,
        child: MouseRegion(
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: Sp.s0_5),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              SizedBox(
                height: widget.touch ? 22 : 18,
                child: Row(children: [
                  if (widget.aiReason != null) ...[
                    Tooltip(
                      message: widget.aiReason!,
                      child: Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(gradient: LumenTokens.aiGradient, shape: BoxShape.circle),
                      ),
                    ),
                    const SizedBox(width: Sp.s1_5),
                  ],
                  Expanded(
                    child: GestureDetector(
                      onDoubleTap: () => widget.onCommit(widget.defaultValue),
                      child: Text(widget.label, style: labelStyle, overflow: TextOverflow.ellipsis),
                    ),
                  ),
                  _valueField(t),
                ]),
              ),
              SizedBox(
                height: trackHeight,
                child: LayoutBuilder(builder: (context, c) => _track(t, c.maxWidth, trackHeight)),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _valueField(LumenTokens t) {
    final w = widget.touch ? 64.0 : 52.0;
    if (_editing) {
      return SizedBox(
        width: w,
        height: widget.touch ? 26 : 18,
        child: TextField(
          controller: _field,
          autofocus: true,
          textAlign: TextAlign.right,
          style: LumenType.value(touch: widget.touch).copyWith(color: t.textPrimary),
          keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            filled: true,
            fillColor: t.surface2,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(Rad.xs), borderSide: BorderSide(color: t.accent)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(Rad.xs), borderSide: BorderSide(color: t.accent)),
          ),
          onSubmitted: (_) => _finishEdit(commit: true),
          onTapOutside: (_) => _finishEdit(commit: true),
        ),
      );
    }
    return GestureDetector(
      onTap: _startEdit,
      child: MouseRegion(
        cursor: SystemMouseCursors.text,
        child: Container(
          width: w,
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: _hover ? t.surface2 : Colors.transparent,
            borderRadius: BorderRadius.circular(Rad.xs),
          ),
          child: Text(
            _format(widget.value),
            style: LumenType.value(touch: widget.touch).copyWith(color: _dragging ? t.textPrimary : t.textSecondary),
          ),
        ),
      ),
    );
  }

  Widget _track(LumenTokens t, double width, double height) {
    final frac = _range == 0 ? 0.0 : ((widget.value - widget.min) / _range).clamp(0.0, 1.0);
    final zeroFrac = widget.bipolar ? ((0 - widget.min) / _range).clamp(0.0, 1.0) : 0.0;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onDoubleTap: () => widget.onCommit(widget.defaultValue),
      onTapUp: widget.touch
          ? null
          : (d) {
              _focus.requestFocus();
              widget.onCommit(_snap(widget.min + (d.localPosition.dx / width).clamp(0.0, 1.0) * _range));
            },
      onHorizontalDragStart: (d) {
        _focus.requestFocus();
        setState(() => _dragging = true);
        _dragStartValue = widget.value;
        _dragDx = 0;
        widget.onChangeStart?.call();
      },
      onHorizontalDragUpdate: (d) {
        final fine = HardwareKeyboard.instance.isAltPressed ? 0.1 : 1.0;
        _dragDx += d.delta.dx * fine;
        widget.onChanged?.call(_snap(_dragStartValue + _dragDx / width * _range));
      },
      onHorizontalDragEnd: (_) {
        setState(() => _dragging = false);
        widget.onChangeEnd?.call();
      },
      onHorizontalDragCancel: () {
        setState(() => _dragging = false);
        widget.onChangeEnd?.call();
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeLeftRight,
        child: CustomPaint(
          size: Size(width, height),
          painter: _TrackPainter(
            frac: frac,
            zeroFrac: zeroFrac,
            bipolar: widget.bipolar,
            gradient: widget.trackGradient,
            line: t.lineStrong,
            fill: t.accent,
            thumb: t.textPrimary,
            tick: t.textTertiary,
            thumbRadius: (widget.touch ? (_dragging ? 12.0 : 10.0) : (_dragging ? 8.0 : (_hover ? 7.0 : 6.0))),
            trackWidth: widget.touch ? 3 : 2,
            focused: _focus.hasFocus,
            focusColor: t.focusRing,
          ),
        ),
      ),
    );
  }
}

class _TrackPainter extends CustomPainter {
  _TrackPainter({
    required this.frac,
    required this.zeroFrac,
    required this.bipolar,
    required this.gradient,
    required this.line,
    required this.fill,
    required this.thumb,
    required this.tick,
    required this.thumbRadius,
    required this.trackWidth,
    required this.focused,
    required this.focusColor,
  });

  final double frac;
  final double zeroFrac;
  final bool bipolar;
  final Gradient? gradient;
  final Color line;
  final Color fill;
  final Color thumb;
  final Color tick;
  final double thumbRadius;
  final double trackWidth;
  final bool focused;
  final Color focusColor;

  @override
  void paint(Canvas canvas, Size size) {
    final pad = thumbRadius;
    final usable = size.width - 2 * pad;
    final cy = size.height / 2;
    final x = pad + usable * frac;
    final track = RRect.fromLTRBR(pad, cy - trackWidth / 2, size.width - pad, cy + trackWidth / 2, const Radius.circular(2));
    final trackPaint = Paint()..color = line;
    if (gradient != null) {
      trackPaint
        ..shader = gradient!.createShader(track.outerRect)
        ..color = const Color(0xB3FFFFFF);
    }
    canvas.drawRRect(track, trackPaint);
    if (gradient == null) {
      final from = pad + usable * zeroFrac;
      final rect = Rect.fromLTRB(from < x ? from : x, cy - trackWidth / 2, from < x ? x : from, cy + trackWidth / 2);
      canvas.drawRect(rect, Paint()..color = fill);
    }
    if (bipolar) {
      final zx = pad + usable * zeroFrac;
      canvas.drawLine(Offset(zx, cy - 4), Offset(zx, cy + 4), Paint()
        ..color = tick
        ..strokeWidth = 1);
    }
    if (focused) {
      canvas.drawCircle(Offset(x, cy), thumbRadius + 3, Paint()
        ..color = focusColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2);
    }
    canvas.drawCircle(Offset(x, cy), thumbRadius, Paint()..color = thumb);
    canvas.drawCircle(Offset(x, cy), thumbRadius, Paint()
      ..color = const Color(0x66000000)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1);
  }

  @override
  bool shouldRepaint(_TrackPainter o) =>
      o.frac != frac || o.thumbRadius != thumbRadius || o.focused != focused || o.gradient != gradient || o.fill != fill;
}
