import 'param_registry.dart';
import 'portrait.dart';
import 'portrait_presets.dart';
import 'preset.dart';
import 'tone_curve.dart';
import 'treatment.dart';

ParamId _h(HslBand b, HslChannel c) => P.hsl(b, c);

/// The built-in looks: 12 colour looks (values derived from the style atoms
/// in research 01 §7.3) and 6 portrait retouch presets ([kPortraitPresets]).
final List<Preset> kBuiltinPresets = List.unmodifiable([
  Preset(
    id: 'builtin.natural_lift',
    name: 'Natural Lift',
    group: 'Essentials',
    builtIn: true,
    values: {
      P.exposure: 0.15,
      P.shadows: 20,
      P.highlights: -15,
      P.vibrance: 10,
      P.clarity: 5,
    },
  ),
  Preset(
    id: 'builtin.bright_airy',
    name: 'Bright & Airy',
    group: 'Essentials',
    builtIn: true,
    values: {
      P.exposure: 0.4,
      P.contrast: -10,
      P.highlights: -20,
      P.shadows: 25,
      P.whites: 10,
      P.blacks: 10,
      P.vibrance: 5,
      _h(HslBand.orange, HslChannel.lum): 5,
    },
  ),
  Preset(
    id: 'builtin.moody',
    name: 'Moody',
    group: 'Creative',
    builtIn: true,
    values: {
      P.exposure: -0.3,
      P.highlights: -25,
      P.shadows: -5,
      P.blacks: -10,
      P.vibrance: -15,
      P.saturation: -5,
      P.temp: -5,
      P.vignetteAmount: -15,
      P.grade(GradeZone.shadows, 'hue'): 215,
      P.grade(GradeZone.shadows, 'sat'): 10,
    },
  ),
  Preset(
    id: 'builtin.punchy',
    name: 'Punchy',
    group: 'Essentials',
    builtIn: true,
    values: {
      P.contrast: 20,
      P.whites: 8,
      P.blacks: -8,
      P.clarity: 8,
      P.vibrance: 10,
    },
  ),
  Preset(
    id: 'builtin.soft_matte',
    name: 'Soft Matte',
    group: 'Creative',
    builtIn: true,
    values: {P.contrast: -15, P.highlights: -15, P.shadows: 15, P.clarity: -10},
    curves: const CurveSet(
      master: ToneCurve([CurvePoint(0, 18), CurvePoint(255, 255)]),
    ),
  ),
  Preset(
    id: 'builtin.cinematic',
    name: 'Cinematic Teal-Orange',
    group: 'Creative',
    builtIn: true,
    values: {
      P.contrast: 10,
      P.blacks: 6,
      P.grade(GradeZone.shadows, 'hue'): 200,
      P.grade(GradeZone.shadows, 'sat'): 15,
      P.grade(GradeZone.highlights, 'hue'): 40,
      P.grade(GradeZone.highlights, 'sat'): 12,
      _h(HslBand.blue, HslChannel.hue): -10,
      _h(HslBand.orange, HslChannel.sat): 5,
      P.vibrance: -5,
      P.vignetteAmount: -10,
    },
  ),
  Preset(
    id: 'builtin.faded_film',
    name: 'Faded Film',
    group: 'Film',
    builtIn: true,
    values: {
      P.contrast: -10,
      P.saturation: -10,
      P.grade(GradeZone.highlights, 'hue'): 45,
      P.grade(GradeZone.highlights, 'sat'): 10,
      P.grainAmount: 20,
      P.vignetteAmount: -8,
    },
    curves: const CurveSet(
      master: ToneCurve([
        CurvePoint(0, 20),
        CurvePoint(64, 60),
        CurvePoint(192, 200),
        CurvePoint(255, 245),
      ]),
    ),
  ),
  Preset(
    id: 'builtin.golden_hour',
    name: 'Golden Hour',
    group: 'Creative',
    builtIn: true,
    values: {
      P.temp: 20,
      P.tint: 5,
      P.grade(GradeZone.highlights, 'hue'): 40,
      P.grade(GradeZone.highlights, 'sat'): 15,
      _h(HslBand.orange, HslChannel.sat): 10,
      _h(HslBand.yellow, HslChannel.sat): 5,
      P.highlights: -10,
    },
  ),
  Preset(
    id: 'builtin.crisp_landscape',
    name: 'Crisp Landscape',
    group: 'Essentials',
    builtIn: true,
    values: {
      P.contrast: 12,
      P.highlights: -30,
      P.shadows: 20,
      P.clarity: 15,
      P.dehaze: 10,
      P.vibrance: 15,
      _h(HslBand.blue, HslChannel.sat): 12,
      _h(HslBand.blue, HslChannel.lum): -10,
      _h(HslBand.green, HslChannel.sat): 5,
      P.sharpenAmount: 40,
    },
  ),
  Preset(
    id: 'builtin.clean_product',
    name: 'Clean Product',
    group: 'Commerce',
    builtIn: true,
    values: {
      P.exposure: 0.3,
      P.whites: 25,
      P.blacks: -5,
      P.contrast: 8,
      P.clarity: 5,
      P.vibrance: 5,
      P.sharpenAmount: 50,
    },
  ),
  Preset(
    id: 'builtin.classic_bw',
    name: 'Classic B&W',
    group: 'Black & white',
    builtIn: true,
    values: {P.contrast: 15, P.bw(HslBand.blue): -20, P.bw(HslBand.orange): 10},
    treatment: Treatment.bw,
  ),
  Preset(
    id: 'builtin.high_contrast_bw',
    name: 'High-Contrast B&W',
    group: 'Black & white',
    builtIn: true,
    values: {
      P.contrast: 40,
      P.whites: 20,
      P.blacks: -25,
      P.clarity: 20,
      P.bw(HslBand.blue): -35,
      P.grainAmount: 12,
    },
    treatment: Treatment.bw,
  ),
  ...kPortraitPresets,
]);

typedef _G = FaceGroup;
typedef _I = PortraitIds;

/// Group values → portrait settings (a preset never carries spots or
/// individuals).
PortraitSettings _portrait(Map<FaceGroup, Map<String, double>> groups) {
  var p = PortraitSettings.empty;
  for (final g in groups.entries) {
    for (final e in g.value.entries) {
      p = p.withGroupValue(g.key, e.key, e.value);
    }
  }
  return p;
}

/// Evoto-style portrait presets: retouch values per face group (children
/// keep their skin, seniors their character, men their texture) with a
/// light colour touch. Each stays below the "plastic" zone.
final List<Preset> kPortraitPresets = List.unmodifiable([
  Preset(
    id: 'builtin.portrait.natural',
    name: 'Natural Retouch',
    group: 'Portrait',
    builtIn: true,
    values: {P.vibrance: 5},
    portrait: _portrait({
      _G.all: PortraitPresets.natural,
      ...PortraitPresets.groupOverrides,
    }),
  ),
  Preset(
    id: 'builtin.portrait.soft_skin',
    name: 'Soft Skin',
    group: 'Portrait',
    builtIn: true,
    values: {P.clarity: -8, P.highlights: -10, P.vibrance: 5},
    portrait: _portrait({
      _G.all: {
        _I.skinSoftening: 55,
        _I.skinEven: 40,
        _I.skinShine: 35,
        _I.acne: 85,
        _I.darkCircles: 45,
        _I.eyeBags: 35,
        _I.wrinkleForehead: 35,
        _I.wrinkleCrowsFeet: 30,
        _I.eyeWhites: 30,
        _I.iris: 25,
      },
      _G.child: {_I.skinSoftening: 20, _I.acne: 40, _I.eyeBags: 0},
      _G.senior: {_I.skinSoftening: 40, _I.wrinkleCrowsFeet: 20},
    }),
  ),
  Preset(
    id: 'builtin.portrait.clean_headshot',
    name: 'Clean Headshot',
    group: 'Portrait',
    builtIn: true,
    values: {P.whites: 5, P.clarity: 5, P.vibrance: 5},
    portrait: _portrait({
      _G.all: {
        _I.skinSoftening: 35,
        _I.skinEven: 30,
        _I.skinShine: 50,
        _I.acne: 85,
        _I.wrinkleForehead: 25,
        _I.wrinkleFrown: 25,
        _I.darkCircles: 50,
        _I.eyeBags: 40,
        _I.eyeWhites: 40,
        _I.iris: 35,
        _I.redVein: 50,
        _I.teethBrightness: 30,
        _I.teethDesaturate: 35,
      },
      _G.child: {_I.skinSoftening: 15, _I.eyeBags: 0},
      _G.senior: {_I.skinSoftening: 30, _I.wrinkleForehead: 15},
    }),
  ),
  Preset(
    id: 'builtin.portrait.groom',
    name: 'Groom / Men’s Natural',
    group: 'Portrait',
    builtIn: true,
    values: {P.clarity: 8, P.contrast: 5},
    portrait: _portrait({
      _G.all: {
        _I.skinSoftening: 20,
        _I.skinEven: 20,
        _I.skinShine: 45,
        _I.acne: 70,
        _I.wrinkleForehead: 15,
        _I.darkCircles: 35,
        _I.eyeBags: 30,
        _I.eyeWhites: 30,
        _I.iris: 25,
        _I.teethBrightness: 20,
        _I.teethDesaturate: 25,
      },
      _G.male: {_I.skinSoftening: 15, _I.wrinkleForehead: 10},
      _G.senior: {_I.skinSoftening: 15, _I.eyeBags: 20},
    }),
  ),
  Preset(
    id: 'builtin.portrait.kids_gentle',
    name: 'Kids Gentle',
    group: 'Portrait',
    builtIn: true,
    values: {P.exposure: 0.1, P.vibrance: 8, P.temp: 4},
    portrait: _portrait({
      _G.all: {
        _I.skinSoftening: 10,
        _I.acne: 30,
        _I.darkCircles: 20,
        _I.eyeWhites: 20,
        _I.iris: 20,
      },
      _G.child: {_I.skinSoftening: 8, _I.darkCircles: 15},
    }),
  ),
  Preset(
    id: 'builtin.portrait.glam',
    name: 'Glam',
    group: 'Portrait',
    builtIn: true,
    values: {P.contrast: 10, P.vibrance: 10, P.clarity: -5},
    portrait: _portrait({
      _G.all: {
        _I.skinSoftening: 50,
        _I.skinEven: 45,
        _I.skinShine: 40,
        _I.acne: 90,
        _I.wrinkleForehead: 30,
        _I.wrinkleCrowsFeet: 30,
        _I.darkCircles: 55,
        _I.eyeBags: 45,
        _I.eyeWhites: 40,
        _I.iris: 40,
        _I.teethBrightness: 35,
        _I.teethDesaturate: 40,
        _I.lips: 40,
        _I.blush: 30,
      },
      _G.male: {_I.lips: 0, _I.blush: 0, _I.skinSoftening: 30},
      _G.child: {_I.lips: 0, _I.blush: 0, _I.skinSoftening: 15},
      _G.senior: {_I.skinSoftening: 35, _I.wrinkleCrowsFeet: 15},
    }),
  ),
]);
