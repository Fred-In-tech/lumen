import 'dart:math' as math;

import '../analysis/image_stats.dart';
import '../analysis/proxy.dart';
import '../model/develop_settings.dart';
import '../model/exif_summary.dart';
import '../model/param_registry.dart';
import '../render/aux_maps.dart';
import '../render/reference_pipeline.dart';
import '../render/rgba_buffer.dart';
import 'ai_style.dart';
import 'auto_edit_provider.dart';
import 'auto_tone_constants.dart';
import 'auto_tone_solver.dart';
import 'reasons.dart';

typedef _C = AutoToneConstants;

/// Renders [source] with [settings] (8-bit sRGB in, 8-bit sRGB out).
typedef ProxyRenderer = RgbaBuffer Function(
  RgbaBuffer source,
  DevelopSettings settings,
);

/// The CPU reference renderer bound to [source]. Spatial aux maps are
/// computed once (lazily) from [auxSource] (default [source]) and reused for
/// every render of [source], so a 256-px solver proxy sees exactly the aux
/// data of the 512-px analysis image (as the GPU engine does).
ProxyRenderer referenceRendererFor(RgbaBuffer source, {RgbaBuffer? auxSource}) {
  AuxMaps? aux;
  return (src, settings) {
    if (!identical(src, source) || !needsAuxMaps(settings)) {
      return renderReference(src, settings);
    }
    aux ??= AuxMaps.compute(AuxMaps.proxy(auxSource ?? source));
    return renderReference(src, settings, aux: aux);
  };
}

/// Output of [LocalAutoTone.run].
class AutoToneResult {
  const AutoToneResult({
    required this.settings,
    required this.keyTarget,
    required this.wbStrength,
    required this.confidence,
    required this.renders,
  });

  final DevelopSettings settings;

  /// Median-luminance target the exposure was solved for.
  final double keyTarget;

  /// White-balance strength used (0..1).
  final double wbStrength;
  final double confidence;

  /// Proxy renders the solver needed.
  final int renders;

  /// Explained changes relative to [from].
  List<ParamChange> changesFrom(DevelopSettings from) =>
      Reasons.diff(from, settings, Reasons.auto);
}

/// Offline staged auto-tone (research 01 §6): WB → exposure → whites/blacks
/// → highlights/shadows → contrast → vibrance/saturation → dehaze →
/// whites/blacks + exposure refinement → WB re-check, every stage measured
/// on a rendered 256-px proxy.
abstract final class LocalAutoTone {
  /// Params the engine owns (reset before solving unless locked).
  static const Set<ParamId> managedParams = {
    P.exposure,
    P.contrast,
    P.highlights,
    P.shadows,
    P.whites,
    P.blacks,
    P.temp,
    P.tint,
    P.vibrance,
    P.saturation,
    P.dehaze,
  };

  /// Solves on a 256-px copy of [proxy] (the unedited analysis proxy).
  /// [renderer] renders that 256-px copy; it defaults to the CPU reference
  /// pipeline with aux maps from [proxy].
  static AutoToneResult run({
    required RgbaBuffer proxy,
    DevelopSettings base = DevelopSettings.defaults,
    AutoToneTargets targets = AutoToneTargets.neutral,
    ExifSummary? exif,
    SceneInfo? scene,
    Set<ParamId> locked = const {},
    ProxyRenderer? renderer,
  }) {
    final src = makeProxy(proxy, longEdge: kSolverLongEdge);
    final solver = AutoToneSolver(
      src: src,
      render: renderer ?? referenceRendererFor(src, auxSource: proxy),
      st0: ImageStats.compute(src),
      targets: targets,
      locked: locked,
      start: base.resetParams(managedParams.where((p) => !locked.contains(p))),
    );
    final out = solver.solve(
      key: _exposureTarget(solver.st0, targets),
      lowKey: sceneKey(solver.st0) < _C.lowKey || scene?.keyIntent == 'low_key',
      sunset: sunsetLike(exif, scene),
      night: (exif?.exposureSeconds ?? 0) >= 1 / 15 && (exif?.iso ?? 0) >= 1600,
    );
    return AutoToneResult(
      settings: out.settings,
      keyTarget: out.key,
      wbStrength: out.wbStrength,
      confidence: out.confidence,
      renders: out.renders,
    );
  }

  /// Scene-adaptive key (Reinhard 2002 auto-key, damped by
  /// [AutoToneConstants.keyAdaptivity]): a median-luminance target.
  static double sceneKey(ImageStats st) {
    double log2(double x) => math.log(x) / math.ln2;
    final lmin = math.max(st.yP1, 1e-4);
    final lmax = st.yP99;
    // Under half a stop of range there is no key to read: use middle gray.
    if (lmax <= lmin * math.sqrt2) return _C.keyBase;
    final lavg = st.lAvg.clamp(lmin, lmax);
    final f =
        (2 * log2(lavg) - log2(lmin) - log2(lmax)) / (log2(lmax) - log2(lmin));
    final key = _C.keyBase * math.pow(4, _C.keyAdaptivity * f);
    return key.clamp(_C.keyMin, _C.keyMax).toDouble();
  }

  /// The accepted median-luminance band, scaled by the style's key.
  static (double, double) exposureBand(AutoToneTargets targets) =>
      (_C.bandLowY * targets.keyScale, _C.bandHighY * targets.keyScale);

  static ExposureTarget _exposureTarget(ImageStats st, AutoToneTargets t) {
    final (lo, hi) = exposureBand(t);
    final key = (sceneKey(st) * t.keyScale)
        .clamp(_C.targetLowY * t.keyScale, _C.targetHighY * t.keyScale)
        .toDouble();
    return ExposureTarget(
      key: key,
      low: lo,
      high: hi,
      safeLow: _C.safetyLowY * t.keyScale,
      safeHigh: _C.safetyHighY * t.keyScale,
    );
  }

  /// True when EXIF time or scene hints suggest a deliberate warm cast.
  static bool sunsetLike(ExifSummary? exif, SceneInfo? scene) {
    const warmScenes = {
      'golden_hour',
      'blue_hour',
      'sunset',
      'sunrise',
      'night',
      'indoor_tungsten',
    };
    if (warmScenes.contains(scene?.timeOfDay)) return true;
    final t = exif?.capturedAt;
    if (t == null) return false;
    final h = t.hour + t.minute / 60;
    return (h >= 16.5 && h <= 21.5) || (h >= 5 && h <= 8.5);
  }
}
