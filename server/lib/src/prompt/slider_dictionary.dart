/// The slider dictionary section of the system prompt, generated from
/// [ParamRegistry] so the prompt names exactly the ids the schema accepts.
library;

import 'package:lumen_core/lumen_core.dart';

/// Lumen-calibrated meaning of the individually described sliders.
const Map<String, String> _semantics = {
  P.exposure:
      'Global brightness in stops. +1.0 = one stop brighter (doubles linear '
      'light), -1.0 halves it. Use it to put the subject at the right key; '
      'fix a dull top end with whites and a weak bottom end with blacks.',
  P.contrast:
      'S-curve around mid-gray. Positive deepens shadows and brightens '
      'highlights; negative flattens. Prefer moderate values (+5..+25).',
  P.highlights:
      'Recovers (negative) or boosts (positive) the brightest tones without '
      'moving the white point. Negative values rescue skies and bright skin.',
  P.shadows:
      'Lifts (positive) or deepens (negative) the darkest tones without '
      'moving the black point. Positive values open faces and interiors.',
  P.whites:
      'Moves the white point. Prefer it over exposure to fix a dull, grey '
      'top end; avoid clipping (watch clipPct in the stats).',
  P.blacks:
      'Moves the black point. Negative adds depth and removes haze; positive '
      'gives a faded, matte floor.',
  P.temp:
      'Relative white balance, blue (-) to yellow (+). The stats wb.a value '
      'estimates the cast; correct it only as much as the scene intent '
      'allows (never neutralize sunsets, candlelight or stage light).',
  P.tint:
      'Relative white balance, green (-) to magenta (+). Fluorescent and '
      'foliage casts are usually green; correct with small positive values.',
  P.vibrance:
      'Boosts low-saturation colors and protects skin. Prefer it over '
      'saturation for natural color.',
  P.saturation:
      'Uniform saturation of every color. Use sparingly; negative values are '
      'useful for muted looks.',
  P.texture:
      'Fine-detail contrast (skin pores, foliage, fabric). Negative smooths '
      'skin gently; keep within +-25.',
  P.clarity:
      'Mid-frequency local contrast. Positive adds punch and grit, negative '
      'softens and glows. Avoid strong positive values on portraits.',
  P.dehaze:
      'Removes (positive) or adds (negative) atmospheric haze using the dark '
      'channel; the stats haze score estimates the need. Keep within +-35.',
  P.gradeBlending: 'How much the three grading zones overlap (default 50).',
  P.gradeBalance:
      'Shifts the split between shadow and highlight grading: negative '
      'favors shadows, positive favors highlights.',
  P.sharpenAmount:
      'Capture sharpening strength. 20-40 is typical; more for landscapes, '
      'less for portraits and high-ISO images.',
  P.sharpenDetail: 'Sharpening halo suppression (default 25).',
  P.sharpenMasking:
      'Restricts sharpening to edges; raise it (40-70) for portraits and '
      'noisy images.',
  P.noiseLuminance:
      'Luminance noise reduction. Use the EXIF ISO: about 0 below ISO 400, '
      '10-25 at ISO 1600, 30-50 at ISO 6400+.',
  P.noiseColor: 'Chroma noise reduction; 10-25 is a safe default at high ISO.',
  P.vignetteAmount:
      'Post-crop vignette: negative darkens corners, positive brightens. '
      'Subtle values (-5..-20) draw the eye to the subject.',
  P.vignetteMidpoint: 'How far the vignette reaches inward (default 50).',
  P.vignetteRoundness: 'Vignette shape: -100 rectangular to +100 circular.',
  P.vignetteFeather: 'Vignette edge softness (default 50).',
  P.vignetteHighlights: 'Preserves bright highlights inside a dark vignette.',
  P.grainAmount: 'Film grain strength; 10-25 for a film look.',
  P.grainSize: 'Grain particle size (default 25).',
  P.grainRoughness: 'Grain irregularity (default 50).',
  P.splitShadow: 'Tone-curve region split between shadows and darks.',
  P.splitMidtone: 'Tone-curve region split between darks and lights.',
  P.splitHighlight: 'Tone-curve region split between lights and highlights.',
};

String _familySemantics(ParamSpec p) {
  final parts = p.id.split('.');
  switch (p.group) {
    case ParamGroup.hsl:
      final band = parts[1];
      return switch (parts[2]) {
        'hue' => 'Shifts $band hues toward the neighbouring band.',
        'sat' => 'Saturation of $band tones only.',
        _ => 'Brightness of $band tones only.',
      };
    case ParamGroup.bw:
      return 'Black & white mix: how bright ${parts[1]} tones render in '
          'monochrome (only matters with the B&W treatment).';
    case ParamGroup.curve:
      return 'Parametric tone curve region "${parts[2]}": lifts (+) or '
          'lowers (-) that tonal band.';
    case ParamGroup.grading:
      final zone = parts[1];
      return switch (parts[2]) {
        'hue' =>
          'Color grading hue for $zone, in degrees (0 red, 40 orange, '
              '60 yellow, 120 green, 200 teal, 215 blue, 300 magenta).',
        'sat' => 'Color grading strength for $zone (0 = off).',
        _ => 'Color grading brightness for $zone.',
      };
    case ParamGroup.light ||
        ParamGroup.color ||
        ParamGroup.presence ||
        ParamGroup.detail ||
        ParamGroup.effects:
      return p.label;
  }
}

String _fmt(double v) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toString();

/// One line per AI-editable param: `id [min..max, default d, unit]: meaning`.
String buildSliderDictionary() {
  final buffer = StringBuffer();
  ParamGroup? group;
  for (final p in ParamRegistry.all.where((p) => p.aiEditable)) {
    if (p.group != group) {
      group = p.group;
      buffer.writeln('\n[${group.name}]');
    }
    final unit = p.unit.isEmpty ? '' : ' ${p.unit}';
    final meaning = _semantics[p.id] ?? _familySemantics(p);
    buffer.writeln(
      '- ${p.id} [${_fmt(p.min)}..${_fmt(p.max)}$unit, default '
      '${_fmt(p.defaultValue)}]: $meaning',
    );
  }
  return buffer.toString();
}
