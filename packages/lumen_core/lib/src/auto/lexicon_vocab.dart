import '../model/param_registry.dart';
import 'atoms.dart';

/// A slider the lexicon can address by name.
class SliderWord {
  const SliderWord(
    this.param,
    this.unit, {
    this.moreSign = 1,
    this.lessMeansDown = false,
  });

  final ParamId param;

  /// Δ at intensity 1.0 for "more X".
  final double unit;

  /// −1 when "more X" lowers the slider (vignette darkens with negatives).
  final int moreSign;

  /// "Less haze" / "less noise" mean a plain decrease of X, not "undo".
  final bool lessMeansDown;
}

const _haze = SliderWord(P.dehaze, 15, moreSign: -1, lessMeansDown: true);
const _noise = SliderWord(
  P.noiseLuminance,
  20,
  moreSign: -1,
  lessMeansDown: true,
);

/// Slider keywords (single tokens).
const Map<String, SliderWord> kSliderWords = {
  'exposure': SliderWord(P.exposure, 0.3),
  'brightness': SliderWord(P.exposure, 0.3),
  'ev': SliderWord(P.exposure, 0.3),
  'contrast': SliderWord(P.contrast, 15),
  'highlights': SliderWord(P.highlights, 20),
  'highlight': SliderWord(P.highlights, 20),
  'shadows': SliderWord(P.shadows, 20),
  'shadow': SliderWord(P.shadows, 20),
  'whites': SliderWord(P.whites, 10),
  'blacks': SliderWord(P.blacks, 10),
  'temperature': SliderWord(P.temp, 15),
  'temp': SliderWord(P.temp, 15),
  'tint': SliderWord(P.tint, 10),
  'vibrance': SliderWord(P.vibrance, 15),
  'saturation': SliderWord(P.saturation, 10),
  'saturated': SliderWord(P.saturation, 10),
  'clarity': SliderWord(P.clarity, 15),
  'texture': SliderWord(P.texture, 15),
  'detail': SliderWord(P.texture, 15),
  'details': SliderWord(P.texture, 15),
  'dehaze': SliderWord(P.dehaze, 15),
  'haze': _haze,
  'hazy': _haze,
  'hazier': _haze,
  'vignette': SliderWord(P.vignetteAmount, 15, moreSign: -1),
  'vignetting': SliderWord(P.vignetteAmount, 15, moreSign: -1),
  'grain': SliderWord(P.grainAmount, 20),
  'grainy': SliderWord(P.grainAmount, 20),
  'sharpness': SliderWord(P.sharpenAmount, 25),
  'sharpen': SliderWord(P.sharpenAmount, 25),
  'sharper': SliderWord(P.sharpenAmount, 25),
  'sharpening': SliderWord(P.sharpenAmount, 25),
  'noise': _noise,
  'denoise': SliderWord(P.noiseLuminance, 20),
};

/// Words that push a named slider up / down.
const Set<String> kUpWords = {
  'more',
  'increase',
  'raise',
  'lift',
  'boost',
  'brighten',
  'brighter',
  'open',
  'add',
  'higher',
  'up',
  'bump',
  'stronger',
  'strengthen',
  'enhance',
  'extra',
  'plus',
  'lighten',
  'lighter',
};
const Set<String> kDownWords = {
  'decrease',
  'reduce',
  'lower',
  'drop',
  'down',
  'darken',
  'darker',
  'deepen',
  'deeper',
  'crush',
  'recover',
  'tame',
  'pull',
  'cut',
  'soften',
  'softer',
  'weaker',
  'weaken',
  'minus',
  'kill',
  'dim',
  'remove',
};

/// Words that request "less X" relative to the baseline.
const Set<String> kLessWords = {'less', 'fewer'};

/// Bare brightness words (no slider named) → exposure.
const Map<String, int> kBrightnessWords = {
  'brighter': 1,
  'brighten': 1,
  'lighter': 1,
  'lighten': 1,
  'darker': -1,
  'darken': -1,
  'dimmer': -1,
  'dim': -1,
};

/// Atom keywords, checked in this order.
const List<(StyleAtom, Set<String>)> kAtomWords = [
  (StyleAtom.skyPop, {'sky', 'skies'}),
  (StyleAtom.goldenHour, {'golden', 'sunset', 'sunsets'}),
  (
    StyleAtom.bwClassic,
    {'bwtoken', 'monochrome', 'mono', 'grayscale', 'greyscale', 'bw'},
  ),
  (StyleAtom.warm, {'warmer', 'warm', 'warmth', 'cozier', 'cozy', 'cosy'}),
  (StyleAtom.cool, {'cooler', 'cool', 'colder', 'cold', 'icy', 'chilly'}),
  (StyleAtom.brightAiry, {'airy', 'airytoken', 'ethereal'}),
  (StyleAtom.moody, {'moodier', 'moody', 'dramatic', 'drama', 'mood'}),
  (
    StyleAtom.cinematicTealOrange,
    {'cinematic', 'movie', 'filmic', 'tealorange', 'blockbuster'},
  ),
  (
    StyleAtom.filmFaded,
    {'film', 'vintage', 'retro', 'faded', 'analog', 'analogue', 'nostalgic'},
  ),
  (StyleAtom.punchy, {'punchy', 'punchier', 'pop', 'crisp', 'crisper'}),
  (StyleAtom.softMatte, {'softer', 'soft', 'flatter', 'flat', 'matte'}),
  (StyleAtom.vibrant, {'vivid', 'vibrant', 'colorful', 'colourful'}),
  (StyleAtom.muted, {'muted', 'desaturated', 'desaturate', 'subtle'}),
];

/// Atoms that make another matched atom redundant in the same clause.
const Map<StyleAtom, StyleAtom> kAtomSubsumes = {
  StyleAtom.skyPop: StyleAtom.punchy,
  StyleAtom.goldenHour: StyleAtom.warm,
};

/// Intensity phrases (research 01 §7.2), longest match wins.
const List<(List<String>, double)> kIntensityPhrases = [
  (['just', 'a', 'touch'], 0.25),
  (['a', 'tiny', 'bit'], 0.25),
  (['tiny', 'bit'], 0.25),
  (['a', 'touch'], 0.25),
  (['a', 'hint'], 0.25),
  (['a', 'tad'], 0.25),
  (['a', 'little', 'bit'], 0.5),
  (['a', 'bit'], 0.5),
  (['a', 'little'], 0.5),
  (['a', 'lot'], 1.75),
  (['touch'], 0.25),
  (['hint'], 0.25),
  (['tad'], 0.25),
  (['smidge'], 0.25),
  (['barely'], 0.25),
  (['slightly'], 0.5),
  (['bit'], 0.5),
  (['little'], 0.5),
  (['somewhat'], 0.5),
  (['mildly'], 0.5),
  (['gently'], 0.5),
  (['subtly'], 0.5),
  (['noticeably'], 1.0),
  (['much'], 1.75),
  (['lot'], 1.75),
  (['lots'], 1.75),
  (['really'], 1.75),
  (['very'], 1.75),
  (['strongly'], 1.75),
  (['heavily'], 1.75),
  (['significantly'], 1.75),
  (['way'], 2.5),
  (['extremely'], 2.5),
  (['dramatically'], 2.5),
  (['super'], 2.5),
  (['massively'], 2.5),
  (['hugely'], 2.5),
];

/// Multi-word phrases rewritten to one token before splitting on "and".
const List<(String, String)> kProtectedPhrases = [
  ('black and white', ' bwtoken '),
  ('black & white', ' bwtoken '),
  ('black-and-white', ' bwtoken '),
  ('b&w', ' bwtoken '),
  ('b/w', ' bwtoken '),
  ('light and bright', ' airytoken '),
  ('bright and airy', ' airytoken '),
  ('light and airy', ' airytoken '),
  ('teal and orange', ' tealorange '),
  ('teal & orange', ' tealorange '),
  ('less colorful', ' muted '),
  ('less colourful', ' muted '),
  ('less color', ' muted '),
  ('less colour', ' muted '),
  ('not so', ' less '),
  ('not as', ' less '),
];

/// Clause separators (tokens).
const Set<String> kClauseBreaks = {'and', 'but', 'then', 'also', ',', ';', '.'};

/// Chips offered when nothing is understood.
const List<String> kDefaultSuggestions = [
  'warmer',
  'brighter',
  'more contrast',
  'moodier',
  'lift the shadows',
];

/// Every keyword the lexicon knows (for did-you-mean suggestions).
final List<String> kKnownWords = List.unmodifiable(<String>{
  for (final (_, words) in kAtomWords)
    ...words.where((w) => !w.endsWith('token') && w != 'tealorange'),
  ...kSliderWords.keys,
  ...kBrightnessWords.keys,
});
