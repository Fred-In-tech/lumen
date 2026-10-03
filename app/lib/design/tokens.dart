import 'package:flutter/material.dart';

/// Design tokens for the "Darkroom editorial" direction (docs/DESIGN.md §2).
///
/// Widgets read tokens via `context.tokens`; they never hard-code colors,
/// radii, spacing or durations.
@immutable
class LumenTokens extends ThemeExtension<LumenTokens> {
  const LumenTokens({
    required this.surface0,
    required this.surface1,
    required this.surface2,
    required this.surface3,
    required this.line,
    required this.lineStrong,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.textDisabled,
    required this.textOnAccent,
    required this.accent,
    required this.accentHover,
    required this.accentPressed,
    required this.focusRing,
    required this.danger,
    required this.success,
    required this.warning,
  });

  static const dark = LumenTokens(
    surface0: Color(0xFF111111),
    surface1: Color(0xFF181818),
    surface2: Color(0xFF212121),
    surface3: Color(0xFF2A2A2A),
    line: Color(0xFF2E2E2E),
    lineStrong: Color(0xFF3D3D3D),
    textPrimary: Color(0xFFEDEDED),
    textSecondary: Color(0xFFA3A3A3),
    textTertiary: Color(0xFF8A8A8A),
    textDisabled: Color(0xFF595959),
    textOnAccent: Color(0xFF1A1206),
    accent: Color(0xFFFEA92F),
    accentHover: Color(0xFFFFBE5C),
    accentPressed: Color(0xFFE78C08),
    focusRing: Color(0xFF81B4F6),
    danger: Color(0xFFF75E51),
    success: Color(0xFF52CD86),
    warning: Color(0xFFE7B643),
  );

  final Color surface0;
  final Color surface1;
  final Color surface2;
  final Color surface3;
  final Color line;
  final Color lineStrong;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color textDisabled;
  final Color textOnAccent;
  final Color accent;
  final Color accentHover;
  final Color accentPressed;
  final Color focusRing;
  final Color danger;
  final Color success;
  final Color warning;

  Color get accentTint => accent.withValues(alpha: 0.14);
  Color get hoverOverlay => const Color(0x0DFFFFFF);
  Color get pressedOverlay => const Color(0x17FFFFFF);
  Color get scrim => const Color(0x8C000000);

  /// The AI signature. Only for decisions a model made (DESIGN.md §7).
  static const aiGradient = LinearGradient(
    begin: Alignment(-1, -1),
    end: Alignment(1, 1),
    colors: [Color(0xFFFCB442), Color(0xFFFF894B), Color(0xFFF45693)],
    stops: [0, 0.5, 1],
  );

  static const aiGlow = Color(0x59FF894B);

  @override
  LumenTokens copyWith({Color? surface0, Color? accent}) => LumenTokens(
    surface0: surface0 ?? this.surface0,
    surface1: surface1,
    surface2: surface2,
    surface3: surface3,
    line: line,
    lineStrong: lineStrong,
    textPrimary: textPrimary,
    textSecondary: textSecondary,
    textTertiary: textTertiary,
    textDisabled: textDisabled,
    textOnAccent: textOnAccent,
    accent: accent ?? this.accent,
    accentHover: accentHover,
    accentPressed: accentPressed,
    focusRing: focusRing,
    danger: danger,
    success: success,
    warning: warning,
  );

  @override
  LumenTokens lerp(LumenTokens? other, double t) =>
      t < 0.5 ? this : (other ?? this);
}

/// Spacing scale (4-pt base with half steps).
abstract final class Sp {
  static const double s0_5 = 2;
  static const double s1 = 4;
  static const double s1_5 = 6;
  static const double s2 = 8;
  static const double s3 = 12;
  static const double s4 = 16;
  static const double s5 = 20;
  static const double s6 = 24;
  static const double s8 = 32;
  static const double s10 = 40;
  static const double s14 = 56;
  static const double s20 = 80;
}

/// Radius ladder: deliberately non-uniform (DESIGN.md §2.8).
abstract final class Rad {
  static const double none = 0;
  static const double xs = 3;
  static const double tile = 4;
  static const double sm = 6;
  static const double md = 10;
  static const double lg = 14;
  static const double xl = 16;
  static const double sheet = 20;
  static const double pill = 999;
}

/// Layout constants (DESIGN.md §2.7).
abstract final class Layout {
  static const double topBar = 48;
  static const double rail = 56;
  static const double flyout = 280;
  static const double developPanel = 320;
  static const double developPanelWide = 352;
  static const double filmstrip = 88;
  static const double phoneTabs = 64;
  static const double promptBarHeight = 48;
  static const double phoneBreakpoint = 600;
  static const double desktopBreakpoint = 1024;
  static const double wideBreakpoint = 1440;
}

/// Motion tokens (DESIGN.md §2.10).
abstract final class Motion {
  static const micro = Duration(milliseconds: 90);
  static const fast = Duration(milliseconds: 150);
  static const base = Duration(milliseconds: 220);
  static const panel = Duration(milliseconds: 300);
  static const slow = Duration(milliseconds: 450);
  static const develop = Duration(milliseconds: 600);
  static const developStagger = Duration(milliseconds: 35);
  static const standard = Cubic(0.2, 0, 0, 1);
  static const expoOut = Cubic(0.16, 1, 0.3, 1);

  /// Respects the platform reduced-motion flag.
  static Duration of(BuildContext context, Duration d) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false ? Duration.zero : d;
}

/// Elevation recipes (DESIGN.md §2.9).
abstract final class Elevation {
  static const List<BoxShadow> e2 = [
    BoxShadow(color: Color(0x66000000), offset: Offset(0, 1), blurRadius: 2),
    BoxShadow(color: Color(0x73000000), offset: Offset(0, 12), blurRadius: 32),
  ];
  static const List<BoxShadow> e3 = [
    BoxShadow(color: Color(0x99000000), offset: Offset(0, 24), blurRadius: 64),
  ];
}

/// HSL band swatches (DESIGN.md §2.3), in HslBand order.
const List<Color> kHslBandColors = [
  Color(0xFFE5484D),
  Color(0xFFF2994A),
  Color(0xFFF2D74A),
  Color(0xFF5BBF5B),
  Color(0xFF3CC7C2),
  Color(0xFF3D7BD9),
  Color(0xFF8E5BD9),
  Color(0xFFD94FAE),
];

extension LumenTokensX on BuildContext {
  LumenTokens get tokens =>
      Theme.of(this).extension<LumenTokens>() ?? LumenTokens.dark;
}
