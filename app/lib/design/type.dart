import 'package:flutter/material.dart';

/// Type scale (DESIGN.md §2.5). Geist for UI, Instrument Serif for editorial
/// moments only. When the bundled font files are absent, Flutter falls back
/// to the platform UI font, so layout and tests stay stable.
abstract final class LumenType {
  static const String sans = 'Geist';
  static const String mono = 'GeistMono';
  static const String serif = 'InstrumentSerif';
  static const List<String> _sansFallback = [
    'SF Pro Text',
    'Segoe UI',
    'Roboto',
    'Helvetica Neue',
  ];
  static const List<String> _serifFallback = [
    'New York',
    'Georgia',
    'Times New Roman',
    'serif',
  ];
  static const tabular = [FontFeature.tabularFigures()];

  static TextStyle _sans(
    double size,
    double height,
    FontWeight w, {
    double tracking = 0,
  }) => TextStyle(
    fontFamily: sans,
    fontFamilyFallback: _sansFallback,
    fontSize: size,
    height: height / size,
    fontWeight: w,
    letterSpacing: size * tracking,
  );

  static TextStyle _serif(
    double size,
    double height, {
    double tracking = 0,
    bool italic = false,
  }) => TextStyle(
    fontFamily: serif,
    fontFamilyFallback: _serifFallback,
    fontSize: size,
    height: height / size,
    fontWeight: FontWeight.w400,
    fontStyle: italic ? FontStyle.italic : FontStyle.normal,
    letterSpacing: size * tracking,
  );

  static TextStyle displayXL({bool touch = false}) =>
      touch ? _serif(40, 44, tracking: -0.01) : _serif(56, 60, tracking: -0.01);
  static TextStyle display({bool touch = false}) => touch
      ? _serif(30, 34, tracking: -0.005)
      : _serif(36, 40, tracking: -0.005);
  static TextStyle titleSerif({bool touch = false}) =>
      touch ? _serif(22, 26) : _serif(24, 28);
  static TextStyle title({bool touch = false}) => touch
      ? _sans(17, 22, FontWeight.w600, tracking: -0.005)
      : _sans(16, 22, FontWeight.w600, tracking: -0.005);
  static TextStyle heading({bool touch = false}) =>
      touch ? _sans(15, 20, FontWeight.w600) : _sans(13, 18, FontWeight.w600);
  static TextStyle body({bool touch = false}) =>
      touch ? _sans(15, 21, FontWeight.w400) : _sans(13, 18, FontWeight.w400);
  static TextStyle bodyStrong({bool touch = false}) =>
      touch ? _sans(15, 21, FontWeight.w500) : _sans(13, 18, FontWeight.w500);
  static TextStyle label({bool touch = false}) => touch
      ? _sans(13, 18, FontWeight.w500, tracking: 0.005)
      : _sans(12, 16, FontWeight.w500, tracking: 0.005);
  static TextStyle button({bool touch = false}) =>
      touch ? _sans(15, 20, FontWeight.w600) : _sans(13, 16, FontWeight.w600);
  static TextStyle value({bool touch = false}) =>
      (touch ? _sans(14, 18, FontWeight.w500) : _sans(12, 16, FontWeight.w500))
          .copyWith(fontFeatures: tabular);
  static TextStyle caption({bool touch = false}) => touch
      ? _sans(11, 13, FontWeight.w500, tracking: 0.02)
      : _sans(11, 14, FontWeight.w500, tracking: 0.02);
  static TextStyle micro() => _sans(10, 12, FontWeight.w600, tracking: 0.08);
  static TextStyle monoStyle({bool touch = false}) => TextStyle(
    fontFamily: mono,
    fontFamilyFallback: const ['SF Mono', 'Menlo', 'Consolas', 'monospace'],
    fontSize: touch ? 12 : 11,
    height: touch ? 16 / 12 : 14 / 11,
  );
}

/// Formats a signed slider value with a true minus sign and explicit plus.
String formatSigned(double v, {int decimals = 0}) {
  final s = v.abs().toStringAsFixed(decimals);
  if (double.parse(s) == 0) return s;
  return v > 0 ? '+$s' : '\u2212$s';
}
