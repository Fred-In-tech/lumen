import 'dart:math' as math;

import 'package:lumen/engine/aux_cache.dart';
import 'package:lumen/engine/gpu_pass.dart';
import 'package:lumen/engine/render_graph.dart';
import 'package:lumen/engine/shader_library.dart';
import 'package:lumen_core/lumen_core.dart';

import '../support/test_images.dart';

/// Renders [src] with [s] on the GPU through a [RenderGraph], using CPU aux
/// maps [aux] (computed from [src] when omitted) so GPU and CPU see the same
/// analysis data. Disposes everything it creates.
Future<RgbaBuffer> gpuRender(
  RgbaBuffer src,
  DevelopSettings s, {
  AuxMaps? aux,
  double scale = 1,
  bool showClipping = false,
  String assetId = 'test',
  Map<String, MaskRaster> maskRasters = const {},
}) async {
  final shaders = await ShaderLibrary.load();
  final maps = aux ?? AuxMaps.compute(AuxMaps.proxy(src));
  final textures = await AuxTextures.fromMaps(maps);
  final image = await imageFromBuffer(src);
  final graph = RenderGraph(
    shaders: shaders,
    source: image,
    aux: textures,
    assetId: assetId,
  )..maskRasters = maskRasters;
  try {
    final out = await graph.render(s, scale: scale, showClipping: showClipping);
    final buf = await bufferFromImage(out);
    EngineImages.dispose(out);
    return buf;
  } finally {
    graph.dispose();
    textures.dispose();
    EngineImages.dispose(image);
  }
}

/// Seeded random settings for one pipeline stage.
typedef StageGen = DevelopSettings Function(math.Random r);

double _u(math.Random r, double lo, double hi) =>
    lo + (hi - lo) * r.nextDouble();

final Map<String, StageGen> pointStages = {
  'wb+exposure': (r) => DevelopSettings.defaults.withValues({
    P.temp: _u(r, -100, 100),
    P.tint: _u(r, -100, 100),
    P.exposure: _u(r, -2, 2),
  }),
  'tone lut': (r) => DevelopSettings.defaults.withValues({
    P.contrast: _u(r, -100, 100),
    P.whites: _u(r, -100, 100),
    P.blacks: _u(r, -100, 100),
    P.curveShadows: _u(r, -100, 100),
    P.curveLights: _u(r, -100, 100),
  }),
  'rgb curves': (r) => DevelopSettings.defaults.copyWith(
    curves: CurveSet(
      master: ToneCurve([
        const CurvePoint(0, 0),
        CurvePoint(128, _u(r, 90, 170)),
        const CurvePoint(255, 255),
      ]),
      red: ToneCurve([
        CurvePoint(0, _u(r, 0, 40)),
        CurvePoint(255, _u(r, 210, 255)),
      ]),
      blue: ToneCurve([
        const CurvePoint(0, 0),
        CurvePoint(100, _u(r, 60, 140)),
        const CurvePoint(255, 255),
      ]),
    ),
  ),
  'hsl': (r) => DevelopSettings.defaults.withValues({
    for (final b in HslBand.values)
      for (final c in HslChannel.values) P.hsl(b, c): _u(r, -100, 100),
  }),
  'vibrance+saturation': (r) => DevelopSettings.defaults.withValues({
    P.vibrance: _u(r, -100, 100),
    P.saturation: _u(r, -100, 100),
  }),
  'grading': (r) => DevelopSettings.defaults.withValues({
    for (final z in GradeZone.values) ...{
      P.grade(z, 'hue'): _u(r, 0, 359),
      P.grade(z, 'sat'): _u(r, 0, 100),
      P.grade(z, 'lum'): _u(r, -100, 100),
    },
    P.gradeBlending: _u(r, 0, 100),
    P.gradeBalance: _u(r, -100, 100),
  }),
  'b&w': (r) => DevelopSettings.defaults
      .withValues({for (final b in HslBand.values) P.bw(b): _u(r, -100, 100)})
      .copyWith(treatment: Treatment.bw),
  'vignette': (r) => DevelopSettings.defaults.withValues({
    P.vignetteAmount: _u(r, -100, 100),
    P.vignetteMidpoint: _u(r, 0, 100),
    P.vignetteRoundness: _u(r, -100, 100),
    P.vignetteFeather: _u(r, 0, 100),
    P.vignetteHighlights: _u(r, 0, 100),
  }),
};

final Map<String, StageGen> spatialStages = {
  'dehaze': (r) =>
      DevelopSettings.defaults.withValue(P.dehaze, _u(r, -100, 100)),
  'shadows+highlights': (r) => DevelopSettings.defaults.withValues({
    P.shadows: _u(r, -100, 100),
    P.highlights: _u(r, -100, 100),
  }),
  'clarity': (r) =>
      DevelopSettings.defaults.withValue(P.clarity, _u(r, -100, 100)),
  'texture': (r) =>
      DevelopSettings.defaults.withValue(P.texture, _u(r, -100, 100)),
};

/// All point ops at once (the §6.3 "12 seeded random settings").
DevelopSettings randomPointSettings(math.Random r) {
  var s = DevelopSettings.defaults;
  for (final g in pointStages.values) {
    final part = g(r);
    s = s.withValues(part.nonDefaultValues);
    if (part.treatment == Treatment.bw && r.nextBool()) {
      s = s.copyWith(treatment: Treatment.bw);
    }
    if (!part.curves.isIdentity) s = s.copyWith(curves: part.curves);
  }
  return s;
}
