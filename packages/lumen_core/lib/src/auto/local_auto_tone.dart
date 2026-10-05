import '../analysis/proxy.dart';
import '../model/develop_settings.dart';
import '../model/exif_summary.dart';
import '../model/face_analysis.dart';
import '../model/param_registry.dart';
import '../render/aux_maps.dart';
import '../render/reference_pipeline.dart';
import '../render/rgba_buffer.dart';
import 'ai_style.dart';
import 'auto_edit_provider.dart';
import 'enhance_report.dart';
import 'enhance_solver.dart';
import 'reasons.dart';

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
  const AutoToneResult({required this.settings, required this.detail});

  final DevelopSettings settings;

  /// Everything the solver measured and decided.
  final EnhanceOutcome detail;

  double get confidence => detail.confidence;

  /// Proxy renders the solver needed.
  int get renders => detail.renders;

  /// The solver's reason for changing [param] from [from] to [to].
  String reasonFor(ParamId param, double from, double to) =>
      Reasons.auto(param, from, to, why: detail.reasons[param]);

  /// Explained changes relative to [from].
  List<ParamChange> changesFrom(DevelopSettings from) =>
      Reasons.diff(from, settings, reasonFor);
}

/// Offline Auto Enhance (research 09 §2): face-aware exposure, gated white
/// balance, clip-driven recovery, contrast and protected colour, every
/// stage measured on a rendered 256-px proxy. See [EnhanceSolver].
abstract final class LocalAutoTone {
  /// Params the engine owns (reset before solving unless locked).
  static const Set<ParamId> managedParams = enhanceManagedParams;

  /// Solves on a 256-px copy of [proxy] (the unedited analysis proxy).
  /// [faces] are the photo's face boxes (normalised; empty when unknown):
  /// they anchor exposure and white balance on skin. [renderer] renders the
  /// 256-px copy; it defaults to the CPU reference pipeline with aux maps
  /// from [proxy].
  static AutoToneResult run({
    required RgbaBuffer proxy,
    DevelopSettings base = DevelopSettings.defaults,
    AutoToneTargets targets = AutoToneTargets.neutral,
    ExifSummary? exif,
    SceneInfo? scene,
    List<FaceBox> faces = const [],
    Set<ParamId> locked = const {},
    ProxyRenderer? renderer,
  }) {
    final src = makeProxy(proxy, longEdge: kSolverLongEdge);
    final out = EnhanceSolver(
      src: src,
      render: renderer ?? referenceRendererFor(src, auxSource: proxy),
      targets: targets,
      locked: locked,
      start: base.resetParams(managedParams.where((p) => !locked.contains(p))),
      faces: faces,
      exif: exif,
      hints: scene,
    ).solve();
    // Geometry and liquify come back exactly as the photo has them.
    return AutoToneResult(settings: out.settings, detail: out);
  }
}
