import 'package:flutter/material.dart';

import 'package:lumen/design/tokens.dart';
import 'package:lumen/design/type.dart';

enum ButtonKind { primary, secondary, ghost, ai, danger }

/// Pressable surface with designed hover/pressed/focus states and no ripple.
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.onTap,
    required this.builder,
    this.semanticLabel,
    this.tooltip,
    this.radius = Rad.sm,
    this.scaleOnPress = true,
  });

  final VoidCallback? onTap;
  final Widget Function(BuildContext context, Set<WidgetState> states) builder;
  final String? semanticLabel;
  final String? tooltip;
  final double radius;
  final bool scaleOnPress;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _hover = false;
  bool _pressed = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    final states = <WidgetState>{
      if (_hover && enabled) WidgetState.hovered,
      if (_pressed && enabled) WidgetState.pressed,
      if (_focused) WidgetState.focused,
      if (!enabled) WidgetState.disabled,
    };
    Widget child = FocusableActionDetector(
      enabled: enabled,
      mouseCursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.forbidden,
      onShowHoverHighlight: (v) => setState(() => _hover = v),
      onShowFocusHighlight: (v) => setState(() => _focused = v),
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) {
          widget.onTap?.call();
          return null;
        }),
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
        onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
        onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: widget.scaleOnPress && _pressed ? 0.97 : 1,
          duration: Motion.micro,
          child: DecoratedBox(
            position: DecorationPosition.foreground,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(widget.radius + 2),
              border: _focused ? Border.all(color: context.tokens.focusRing, width: 2) : null,
            ),
            child: Opacity(opacity: enabled ? 1 : 0.38, child: widget.builder(context, states)),
          ),
        ),
      ),
    );
    if (widget.semanticLabel != null) {
      child = Semantics(button: true, enabled: enabled, label: widget.semanticLabel, child: child);
    }
    if (widget.tooltip != null) child = Tooltip(message: widget.tooltip!, child: child);
    return child;
  }
}

/// Text (+ optional icon) button in one of the design kinds.
class LumenButton extends StatelessWidget {
  const LumenButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.kind = ButtonKind.secondary,
    this.icon,
    this.height = 32,
    this.expand = false,
    this.tooltip,
  });

  final String label;
  final VoidCallback? onPressed;
  final ButtonKind kind;
  final Widget? icon;
  final double height;
  final bool expand;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Pressable(
      onTap: onPressed,
      tooltip: tooltip,
      semanticLabel: label,
      builder: (context, states) {
        final hovered = states.contains(WidgetState.hovered);
        final pressed = states.contains(WidgetState.pressed);
        final (Color? fill, Gradient? gradient, Color fg, Color? border) = switch (kind) {
          ButtonKind.primary => (pressed ? t.accentPressed : (hovered ? t.accentHover : t.accent), null, t.textOnAccent, null),
          ButtonKind.ai => (null, LumenTokens.aiGradient, t.textOnAccent, null),
          ButtonKind.secondary => (hovered ? t.surface3 : t.surface2, null, t.textPrimary, t.lineStrong),
          ButtonKind.ghost => (hovered ? t.hoverOverlay : Colors.transparent, null, t.textSecondary, null),
          ButtonKind.danger => (hovered ? t.surface3 : t.surface2, null, t.danger, t.lineStrong),
        };
        final content = Row(
          mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              IconTheme.merge(data: IconThemeData(color: fg, size: 16), child: icon!),
              const SizedBox(width: Sp.s1_5),
            ],
            Flexible(
              child: Text(label, overflow: TextOverflow.ellipsis, style: LumenType.button().copyWith(color: fg)),
            ),
          ],
        );
        return Container(
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: Sp.s3),
          decoration: BoxDecoration(
            color: fill,
            gradient: gradient,
            borderRadius: BorderRadius.circular(Rad.sm),
            border: border == null ? null : Border.all(color: border),
          ),
          foregroundDecoration: kind == ButtonKind.ai && hovered
              ? BoxDecoration(color: t.hoverOverlay, borderRadius: BorderRadius.circular(Rad.sm))
              : null,
          child: content,
        );
      },
    );
  }
}

/// Square icon button (28–44px) with tooltip.
class LumenIconButton extends StatelessWidget {
  const LumenIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    required this.tooltip,
    this.size = 28,
    this.iconSize = 16,
    this.selected = false,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String tooltip;
  final double size;
  final double iconSize;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Pressable(
      onTap: onPressed,
      tooltip: tooltip,
      semanticLabel: tooltip,
      builder: (context, states) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: selected
              ? t.accentTint
              : states.contains(WidgetState.hovered)
                  ? t.hoverOverlay
                  : Colors.transparent,
          borderRadius: BorderRadius.circular(Rad.sm),
        ),
        child: Icon(icon, size: iconSize, color: selected ? t.accent : t.textSecondary),
      ),
    );
  }
}

/// Rounded status pill (AI status, offline badge, counts).
class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.label, this.leading, this.elevated = false});

  final String label;
  final Widget? leading;
  final bool elevated;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: Sp.s3),
      decoration: BoxDecoration(
        color: elevated ? t.surface3 : t.surface2,
        borderRadius: BorderRadius.circular(Rad.pill),
        boxShadow: elevated ? Elevation.e2 : null,
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (leading != null) ...[leading!, const SizedBox(width: Sp.s1_5)],
        Text(label, style: LumenType.caption().copyWith(color: t.textSecondary)),
      ]),
    );
  }
}
