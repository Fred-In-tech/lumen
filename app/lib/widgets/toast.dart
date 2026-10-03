import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:lumen/design/tokens.dart';
import 'package:lumen/design/type.dart';
import 'package:lumen/widgets/ai_glyph.dart';

enum ToastKind { info, success, error, ai }

/// Shows a floating toast (e2 surface) with an optional action.
void showToast(
  BuildContext context,
  String message, {
  ToastKind kind = ToastKind.info,
  String? actionLabel,
  VoidCallback? onAction,
  Duration duration = const Duration(seconds: 4),
}) {
  final t = context.tokens;
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  final leading = switch (kind) {
    ToastKind.ai => const AiGlyph(size: 14),
    ToastKind.success => Icon(LucideIcons.circleCheck, size: 14, color: t.success),
    ToastKind.error => Icon(LucideIcons.triangleAlert, size: 14, color: t.danger),
    ToastKind.info => null,
  };
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: t.surface3,
      elevation: 0,
      duration: duration,
      width: 420,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Rad.md)),
      content: Row(children: [
        if (leading != null) ...[leading, const SizedBox(width: Sp.s2)],
        Expanded(child: Text(message, style: LumenType.body().copyWith(color: t.textPrimary))),
      ]),
      action: actionLabel == null
          ? null
          : SnackBarAction(label: actionLabel, textColor: t.accent, onPressed: onAction ?? () {}),
    ));
}
