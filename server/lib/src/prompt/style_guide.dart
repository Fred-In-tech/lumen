/// Style paragraphs and the style-atom table for the system prompt.
library;

import 'package:lumen_core/lumen_core.dart';

/// One paragraph per Lumen style (MonetGPT style-instruction format).
const Map<GatewayStyle, String> kStyleParagraphs = {
  GatewayStyle.natural:
      'Natural: a faithful, technically clean edit. Correct white balance '
      'unless the cast is the point of the scene, place the subject at a '
      'natural brightness, recover clipped highlights, open blocked shadows '
      'and add only enough contrast and vibrance to look like a good camera '
      'JPEG. No grading, no vignette, no grain. Typical atoms: none.',
  GatewayStyle.vibrant:
      'Vibrant: clean exposure with rich but believable color. Raise '
      'vibrance before saturation, add a little contrast and clarity, let '
      'skies and foliage sing while keeping skin natural (orange/red hue '
      'shifts within +-5). Typical atoms: vibrant 0.6, punchy 0.3.',
  GatewayStyle.moody:
      'Moody: darker key, deeper shadows and restrained color. Lower '
      'exposure slightly, pull highlights, drop blacks, reduce vibrance, '
      'cool the shadows with grading (hue around 215) and add a gentle '
      'vignette. Keep the subject readable; never crush faces. Partially '
      'keep the ambient cast (wbStrength around 0.4). Typical atoms: moody '
      '0.8.',
  GatewayStyle.cinematic:
      'Cinematic: teal-and-orange separation with a filmic tone curve. Teal '
      'shadows (grade.shadows hue around 200), warm highlights (hue around '
      '40), slightly lifted blacks, moderate contrast, a touch less '
      'vibrance and a light vignette. Skin must stay natural. Typical atoms: '
      'cinematic_teal_orange 1.0.',
  GatewayStyle.film:
      'Film: a faded analogue print. Lifted blacks (blacks positive or the '
      'shadows curve region raised), softer contrast, slightly lower '
      'saturation, warm highlights, fine grain (15-25) and a faint vignette. '
      'Typical atoms: film_faded 1.0.',
  GatewayStyle.goldenHour:
      'Golden Hour: warm, glowing late-afternoon light. Keep or add warmth '
      '(temp positive, wbStrength around 0.2), warm highlight grading (hue '
      'around 40), boost orange and yellow saturation a little and protect '
      'highlights from clipping. Typical atoms: golden_hour 1.0.',
  GatewayStyle.cleanBright:
      'Clean & Bright: an airy, high-key look. Raise exposure, lift shadows, '
      'pull highlights so nothing clips, lower contrast slightly, neutral to '
      'slightly warm white balance and clean whites. Avoid a washed-out '
      'look: keep blacks near 0. Typical atoms: bright_airy 0.6.',
  GatewayStyle.bw:
      'B&W: a classic monochrome conversion. The app switches the treatment '
      'to black & white; you shape it with contrast, whites/blacks and the '
      'bw.* mix sliders (darken blue skies with bw.blue negative, brighten '
      'skin with bw.orange positive). Color sliders other than bw.* have no '
      'visible effect. Typical atoms: bw_classic 1.0.',
  GatewayStyle.portraitSoft:
      'Portrait Soft: flattering, gentle skin. Correct exposure on the face, '
      'soften with negative clarity (around -10) and texture (around -15), '
      'cap vibrance at 10, keep skin hues natural and add a soft matte '
      'floor. Typical atoms: soft_matte 0.4.',
};

/// The style atoms (research 01 §7.3), Δ at amount 1.0.
const Map<String, String> kAtomDescriptions = {
  'warm': 'temp +15, tint +3, hsl.orange.sat +5',
  'cool': 'temp -15, tint -2, hsl.blue.sat +5',
  'bright_airy':
      'exposure +0.4, contrast -10, highlights -20, shadows +25, whites +10, '
      'blacks +10, vibrance +5, hsl.orange.lum +5',
  'moody':
      'exposure -0.3, highlights -25, shadows -5, blacks -10, vibrance -15, '
      'saturation -5, temp -5, vignette.amount -15, grade.shadows hue 215 '
      'sat 10',
  'punchy': 'contrast +20, whites +8, blacks -8, clarity +8, vibrance +10',
  'soft_matte':
      'contrast -15, highlights -15, shadows +15, clarity -10, lifted black '
      'point',
  'cinematic_teal_orange':
      'contrast +10, blacks +6, grade.shadows hue 200 sat 15, '
      'grade.highlights hue 40 sat 12, hsl.blue.hue -10, hsl.orange.sat +5, '
      'vibrance -5, vignette.amount -10',
  'film_faded':
      'faded curve, contrast -10, saturation -10, grade.highlights hue 45 sat '
      '10, grain.amount 20, vignette.amount -8',
  'golden_hour':
      'temp +20, tint +5, grade.highlights hue 40 sat 15, hsl.orange.sat +10, '
      'hsl.yellow.sat +5, highlights -10',
  'sky_pop':
      'hsl.blue.sat +15, hsl.blue.lum -15, hsl.aqua.sat +8, highlights -15, '
      'dehaze +8',
  'vibrant': 'vibrance +25, saturation +5, clarity +5',
  'muted': 'vibrance -25, saturation -10',
  'bw_classic':
      'black & white treatment, contrast +15, bw.blue -20, '
      'bw.orange +10',
};

String buildStyleSection() {
  final buffer = StringBuffer();
  for (final style in GatewayStyle.values) {
    buffer.writeln('- ${kStyleParagraphs[style]}');
  }
  return buffer.toString();
}

String buildAtomSection() {
  final buffer = StringBuffer();
  for (final atom in kStyleAtomIds) {
    buffer.writeln('- $atom: ${kAtomDescriptions[atom]}');
  }
  return buffer.toString();
}
