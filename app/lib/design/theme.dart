import 'package:flutter/material.dart';

import 'tokens.dart';
import 'type.dart';

/// Builds the app theme. Material is only the scaffolding: ripples and
/// surface tint are disabled and every visual comes from [LumenTokens].
ThemeData buildLumenTheme({LumenTokens tokens = LumenTokens.light}) {
  final scheme = (tokens.isLight ? ColorScheme.light : ColorScheme.dark)(
    surface: tokens.surface1,
    primary: tokens.accent,
    onPrimary: tokens.textOnAccent,
    secondary: tokens.accent,
    error: tokens.danger,
    onSurface: tokens.textPrimary,
    surfaceTint: Colors.transparent,
  );
  final base = ThemeData(
    useMaterial3: true,
    brightness: tokens.brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: tokens.surface0,
    canvasColor: tokens.surface1,
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    hoverColor: tokens.hoverOverlay,
    focusColor: tokens.focusRing.withValues(alpha: 0.2),
    dividerColor: tokens.line,
    fontFamily: LumenType.sans,
    extensions: [tokens],
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(
      bodyColor: tokens.textPrimary,
      displayColor: tokens.textPrimary,
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: tokens.isLight ? tokens.textPrimary : tokens.surface3,
        borderRadius: BorderRadius.circular(Rad.sm),
      ),
      textStyle: LumenType.caption().copyWith(
        color: tokens.isLight ? tokens.surface1 : tokens.textPrimary,
      ),
      waitDuration: const Duration(milliseconds: 500),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: tokens.isLight ? tokens.surface1 : tokens.surface2,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Rad.lg),
      ),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: tokens.accent,
      selectionColor: tokens.accent.withValues(alpha: 0.3),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStatePropertyAll(tokens.lineStrong),
      thickness: const WidgetStatePropertyAll(6),
      radius: const Radius.circular(Rad.pill),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: tokens.raised,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Rad.md),
        side: BorderSide(color: tokens.line),
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: tokens.accent,
      linearTrackColor: tokens.surface3,
    ),
  );
}
