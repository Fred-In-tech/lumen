/// The single source of truth for every scalar develop parameter.
///
/// UI sliders, uniform packing, presets, history patches, copy/paste and the
/// AI response schema are all generated from this registry, so they can never
/// disagree about ids or ranges.
library;

enum ParamGroup {
  light,
  color,
  presence,
  hsl,
  bw,
  curve,
  grading,
  detail,
  effects,
}

enum HslBand { red, orange, yellow, green, aqua, blue, purple, magenta }

enum HslChannel { hue, sat, lum }

enum GradeZone { shadows, midtones, highlights, global }

/// A parameter id is a stable dotted string such as `hsl.blue.sat`.
typedef ParamId = String;

class ParamSpec {
  const ParamSpec({
    required this.id,
    required this.label,
    required this.group,
    required this.min,
    required this.max,
    this.defaultValue = 0,
    this.step = 1,
    this.unit = '',
    required this.xmp,
    this.aiEditable = true,
    this.localAllowed = false,
    this.bipolar = true,
  });

  final ParamId id;
  final String label;
  final ParamGroup group;
  final double min;
  final double max;
  final double defaultValue;
  final double step;
  final String unit;

  /// Lightroom `crs:` XMP name, for preset import/export.
  final String xmp;
  final bool aiEditable;

  /// Allowed inside a local mask (Phase 2).
  final bool localAllowed;

  /// True when the slider is centered on zero (−x…+x).
  final bool bipolar;

  double clamp(double v) =>
      v.isNaN ? defaultValue : v.clamp(min, max).toDouble();

  bool isDefault(double v) => (v - defaultValue).abs() < 1e-9;
}

/// Convenience id constants.
abstract final class P {
  static const exposure = 'exposure';
  static const contrast = 'contrast';
  static const highlights = 'highlights';
  static const shadows = 'shadows';
  static const whites = 'whites';
  static const blacks = 'blacks';
  static const temp = 'temp';
  static const tint = 'tint';
  static const vibrance = 'vibrance';
  static const saturation = 'saturation';
  static const texture = 'texture';
  static const clarity = 'clarity';
  static const dehaze = 'dehaze';
  static const curveShadows = 'curve.p.shadows';
  static const curveDarks = 'curve.p.darks';
  static const curveLights = 'curve.p.lights';
  static const curveHighlights = 'curve.p.highlights';
  static const splitShadow = 'curve.split.shadow';
  static const splitMidtone = 'curve.split.midtone';
  static const splitHighlight = 'curve.split.highlight';
  static const gradeBlending = 'grade.blending';
  static const gradeBalance = 'grade.balance';
  static const sharpenAmount = 'sharpen.amount';
  static const sharpenRadius = 'sharpen.radius';
  static const sharpenDetail = 'sharpen.detail';
  static const sharpenMasking = 'sharpen.masking';
  static const noiseLuminance = 'noise.luminance';
  static const noiseColor = 'noise.color';
  static const vignetteAmount = 'vignette.amount';
  static const vignetteMidpoint = 'vignette.midpoint';
  static const vignetteRoundness = 'vignette.roundness';
  static const vignetteFeather = 'vignette.feather';
  static const vignetteHighlights = 'vignette.highlights';
  static const grainAmount = 'grain.amount';
  static const grainSize = 'grain.size';
  static const grainRoughness = 'grain.roughness';

  static ParamId hsl(HslBand band, HslChannel ch) =>
      'hsl.${band.name}.${ch.name}';
  static ParamId bw(HslBand band) => 'bw.${band.name}';
  static ParamId grade(GradeZone zone, String field) =>
      'grade.${zone.name}.$field';
}

String _cap(String s) => s[0].toUpperCase() + s.substring(1);

const _xmpBand = {
  HslBand.red: 'Red',
  HslBand.orange: 'Orange',
  HslBand.yellow: 'Yellow',
  HslBand.green: 'Green',
  HslBand.aqua: 'Aqua',
  HslBand.blue: 'Blue',
  HslBand.purple: 'Purple',
  HslBand.magenta: 'Magenta',
};

List<ParamSpec> _build() {
  const g = ParamGroup.light;
  final list = <ParamSpec>[
    const ParamSpec(
      id: P.exposure,
      label: 'Exposure',
      group: g,
      min: -5,
      max: 5,
      step: 0.01,
      unit: 'EV',
      xmp: 'Exposure2012',
      localAllowed: true,
    ),
    const ParamSpec(
      id: P.contrast,
      label: 'Contrast',
      group: g,
      min: -100,
      max: 100,
      xmp: 'Contrast2012',
      localAllowed: true,
    ),
    const ParamSpec(
      id: P.highlights,
      label: 'Highlights',
      group: g,
      min: -100,
      max: 100,
      xmp: 'Highlights2012',
      localAllowed: true,
    ),
    const ParamSpec(
      id: P.shadows,
      label: 'Shadows',
      group: g,
      min: -100,
      max: 100,
      xmp: 'Shadows2012',
      localAllowed: true,
    ),
    const ParamSpec(
      id: P.whites,
      label: 'Whites',
      group: g,
      min: -100,
      max: 100,
      xmp: 'Whites2012',
      localAllowed: true,
    ),
    const ParamSpec(
      id: P.blacks,
      label: 'Blacks',
      group: g,
      min: -100,
      max: 100,
      xmp: 'Blacks2012',
      localAllowed: true,
    ),
    const ParamSpec(
      id: P.temp,
      label: 'Temp',
      group: ParamGroup.color,
      min: -100,
      max: 100,
      xmp: 'IncrementalTemperature',
      localAllowed: true,
    ),
    const ParamSpec(
      id: P.tint,
      label: 'Tint',
      group: ParamGroup.color,
      min: -100,
      max: 100,
      xmp: 'IncrementalTint',
      localAllowed: true,
    ),
    const ParamSpec(
      id: P.vibrance,
      label: 'Vibrance',
      group: ParamGroup.color,
      min: -100,
      max: 100,
      xmp: 'Vibrance',
    ),
    const ParamSpec(
      id: P.saturation,
      label: 'Saturation',
      group: ParamGroup.color,
      min: -100,
      max: 100,
      xmp: 'Saturation',
      localAllowed: true,
    ),
    const ParamSpec(
      id: P.texture,
      label: 'Texture',
      group: ParamGroup.presence,
      min: -100,
      max: 100,
      xmp: 'Texture',
      localAllowed: true,
    ),
    const ParamSpec(
      id: P.clarity,
      label: 'Clarity',
      group: ParamGroup.presence,
      min: -100,
      max: 100,
      xmp: 'Clarity2012',
      localAllowed: true,
    ),
    const ParamSpec(
      id: P.dehaze,
      label: 'Dehaze',
      group: ParamGroup.presence,
      min: -100,
      max: 100,
      xmp: 'Dehaze',
      localAllowed: true,
    ),
  ];
  const chXmp = {
    HslChannel.hue: 'Hue',
    HslChannel.sat: 'Saturation',
    HslChannel.lum: 'Luminance',
  };
  for (final band in HslBand.values) {
    for (final ch in HslChannel.values) {
      list.add(
        ParamSpec(
          id: P.hsl(band, ch),
          label:
              '${_cap(band.name)} ${ch == HslChannel.sat
                  ? 'Saturation'
                  : ch == HslChannel.lum
                  ? 'Luminance'
                  : 'Hue'}',
          group: ParamGroup.hsl,
          min: -100,
          max: 100,
          xmp: '${chXmp[ch]}Adjustment${_xmpBand[band]}',
        ),
      );
    }
  }
  for (final band in HslBand.values) {
    list.add(
      ParamSpec(
        id: P.bw(band),
        label: _cap(band.name),
        group: ParamGroup.bw,
        min: -100,
        max: 100,
        xmp: 'GrayMixer${_xmpBand[band]}',
      ),
    );
  }
  const c = ParamGroup.curve;
  list.addAll(const [
    ParamSpec(
      id: P.curveHighlights,
      label: 'Highlights',
      group: c,
      min: -100,
      max: 100,
      xmp: 'ParametricHighlights',
    ),
    ParamSpec(
      id: P.curveLights,
      label: 'Lights',
      group: c,
      min: -100,
      max: 100,
      xmp: 'ParametricLights',
    ),
    ParamSpec(
      id: P.curveDarks,
      label: 'Darks',
      group: c,
      min: -100,
      max: 100,
      xmp: 'ParametricDarks',
    ),
    ParamSpec(
      id: P.curveShadows,
      label: 'Shadows',
      group: c,
      min: -100,
      max: 100,
      xmp: 'ParametricShadows',
    ),
    ParamSpec(
      id: P.splitShadow,
      label: 'Shadow split',
      group: c,
      min: 10,
      max: 50,
      defaultValue: 25,
      xmp: 'ParametricShadowSplit',
      bipolar: false,
    ),
    ParamSpec(
      id: P.splitMidtone,
      label: 'Midtone split',
      group: c,
      min: 25,
      max: 75,
      defaultValue: 50,
      xmp: 'ParametricMidtoneSplit',
      bipolar: false,
    ),
    ParamSpec(
      id: P.splitHighlight,
      label: 'Highlight split',
      group: c,
      min: 50,
      max: 90,
      defaultValue: 75,
      xmp: 'ParametricHighlightSplit',
      bipolar: false,
    ),
  ]);
  const gradeXmp = {
    GradeZone.shadows: (
      'SplitToningShadowHue',
      'SplitToningShadowSaturation',
      'ColorGradeShadowLum',
    ),
    GradeZone.midtones: (
      'ColorGradeMidtoneHue',
      'ColorGradeMidtoneSat',
      'ColorGradeMidtoneLum',
    ),
    GradeZone.highlights: (
      'SplitToningHighlightHue',
      'SplitToningHighlightSaturation',
      'ColorGradeHighlightLum',
    ),
    GradeZone.global: (
      'ColorGradeGlobalHue',
      'ColorGradeGlobalSat',
      'ColorGradeGlobalLum',
    ),
  };
  for (final z in GradeZone.values) {
    final x = gradeXmp[z]!;
    list.addAll([
      ParamSpec(
        id: P.grade(z, 'hue'),
        label: '${_cap(z.name)} hue',
        group: ParamGroup.grading,
        min: 0,
        max: 359,
        xmp: x.$1,
        bipolar: false,
        unit: '°',
      ),
      ParamSpec(
        id: P.grade(z, 'sat'),
        label: '${_cap(z.name)} saturation',
        group: ParamGroup.grading,
        min: 0,
        max: 100,
        xmp: x.$2,
        bipolar: false,
      ),
      ParamSpec(
        id: P.grade(z, 'lum'),
        label: '${_cap(z.name)} luminance',
        group: ParamGroup.grading,
        min: -100,
        max: 100,
        xmp: x.$3,
      ),
    ]);
  }
  list.addAll(const [
    ParamSpec(
      id: P.gradeBlending,
      label: 'Blending',
      group: ParamGroup.grading,
      min: 0,
      max: 100,
      defaultValue: 50,
      xmp: 'ColorGradeBlending',
      bipolar: false,
    ),
    ParamSpec(
      id: P.gradeBalance,
      label: 'Balance',
      group: ParamGroup.grading,
      min: -100,
      max: 100,
      xmp: 'SplitToningBalance',
    ),
  ]);
  const d = ParamGroup.detail;
  list.addAll(const [
    ParamSpec(
      id: P.sharpenAmount,
      label: 'Sharpening',
      group: d,
      min: 0,
      max: 150,
      xmp: 'Sharpness',
      bipolar: false,
    ),
    ParamSpec(
      id: P.sharpenRadius,
      label: 'Radius',
      group: d,
      min: 0.5,
      max: 3,
      defaultValue: 1,
      step: 0.1,
      xmp: 'SharpenRadius',
      aiEditable: false,
      bipolar: false,
    ),
    ParamSpec(
      id: P.sharpenDetail,
      label: 'Detail',
      group: d,
      min: 0,
      max: 100,
      defaultValue: 25,
      xmp: 'SharpenDetail',
      bipolar: false,
    ),
    ParamSpec(
      id: P.sharpenMasking,
      label: 'Masking',
      group: d,
      min: 0,
      max: 100,
      xmp: 'SharpenEdgeMasking',
      bipolar: false,
    ),
    ParamSpec(
      id: P.noiseLuminance,
      label: 'Noise reduction',
      group: d,
      min: 0,
      max: 100,
      xmp: 'LuminanceSmoothing',
      bipolar: false,
    ),
    ParamSpec(
      id: P.noiseColor,
      label: 'Color noise',
      group: d,
      min: 0,
      max: 100,
      xmp: 'ColorNoiseReduction',
      bipolar: false,
    ),
  ]);
  const e = ParamGroup.effects;
  list.addAll(const [
    ParamSpec(
      id: P.vignetteAmount,
      label: 'Vignette',
      group: e,
      min: -100,
      max: 100,
      xmp: 'PostCropVignetteAmount',
    ),
    ParamSpec(
      id: P.vignetteMidpoint,
      label: 'Midpoint',
      group: e,
      min: 0,
      max: 100,
      defaultValue: 50,
      xmp: 'PostCropVignetteMidpoint',
      bipolar: false,
    ),
    ParamSpec(
      id: P.vignetteRoundness,
      label: 'Roundness',
      group: e,
      min: -100,
      max: 100,
      xmp: 'PostCropVignetteRoundness',
    ),
    ParamSpec(
      id: P.vignetteFeather,
      label: 'Feather',
      group: e,
      min: 0,
      max: 100,
      defaultValue: 50,
      xmp: 'PostCropVignetteFeather',
      bipolar: false,
    ),
    ParamSpec(
      id: P.vignetteHighlights,
      label: 'Highlights',
      group: e,
      min: 0,
      max: 100,
      xmp: 'PostCropVignetteHighlightContrast',
      bipolar: false,
    ),
    ParamSpec(
      id: P.grainAmount,
      label: 'Grain',
      group: e,
      min: 0,
      max: 100,
      xmp: 'GrainAmount',
      bipolar: false,
    ),
    ParamSpec(
      id: P.grainSize,
      label: 'Size',
      group: e,
      min: 0,
      max: 100,
      defaultValue: 25,
      xmp: 'GrainSize',
      bipolar: false,
    ),
    ParamSpec(
      id: P.grainRoughness,
      label: 'Roughness',
      group: e,
      min: 0,
      max: 100,
      defaultValue: 50,
      xmp: 'GrainFrequency',
      bipolar: false,
    ),
  ]);
  return List.unmodifiable(list);
}

abstract final class ParamRegistry {
  static final List<ParamSpec> all = _build();
  static final Map<ParamId, ParamSpec> _byId = {for (final p in all) p.id: p};

  static ParamSpec byId(ParamId id) {
    final p = _byId[id];
    if (p == null) throw ArgumentError.value(id, 'id', 'Unknown parameter');
    return p;
  }

  static ParamSpec? tryById(ParamId id) => _byId[id];

  static bool contains(ParamId id) => _byId.containsKey(id);

  static List<ParamSpec> inGroup(ParamGroup g) =>
      all.where((p) => p.group == g).toList(growable: false);

  static final List<ParamId> aiEditableIds = List.unmodifiable(
    all.where((p) => p.aiEditable).map((p) => p.id),
  );
}
