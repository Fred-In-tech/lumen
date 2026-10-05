import 'dart:math' as math;

import '../analysis/image_stats.dart';
import '../color/srgb.dart';
import '../model/develop_settings.dart';
import '../model/exif_summary.dart';
import '../model/face_analysis.dart';
import '../model/geometry.dart';
import '../model/param_registry.dart';
import '../render/rgba_buffer.dart';
import 'ai_style.dart';
import 'auto_edit_provider.dart';
import 'enhance_constants.dart';
import 'enhance_exposure.dart';
import 'enhance_pixels.dart';
import 'enhance_report.dart';
import 'enhance_scene.dart';
import 'enhance_tone.dart';
import 'enhance_wb.dart';
import 'frame_measure.dart';
import 'skin_bands.dart';
import 'skin_measure.dart';

typedef _C = EnhanceConstants;

/// Auto Enhance v2 (research 09 §2): white balance → exposure → highlights
/// and shadows → whites and blacks → contrast → skin re-check → colour →
/// guardrails. Every stage measures a render of the solver proxy.
class EnhanceSolver {
  EnhanceSolver({
    required this.src,
    required this.render,
    required this.targets,
    required this.locked,
    required DevelopSettings start,
    this.faces = const [],
    this.exif,
    this.hints,
  }) : _base = start,
       // Faces are located on the unwarped, uncropped frame.
       _s = start.copyWith(geometry: Geometry.none, liquify: const []);

  /// The solver proxy (8-bit sRGB today; measured as linear floats).
  final RgbaBuffer src;
  final RgbaBuffer Function(RgbaBuffer, DevelopSettings) render;
  final AutoToneTargets targets;
  final Set<ParamId> locked;
  final List<FaceBox> faces;
  final ExifSummary? exif;
  final SceneInfo? hints;

  final DevelopSettings _base;
  DevelopSettings _s;
  int _renders = 0;
  bool _whiteRepair = false;
  final Map<ParamId, String> _why = {};

  late final LinearPixels _lin0 = LinearPixels.fromRgba(src);
  late final List<SkinRegion> _regions = SkinRegions.locate(_lin0, faces);
  late final _mask = _regions.isEmpty
      ? null
      : SkinRegions.mask(_lin0.pixelCount, _regions);
  late final FrameMeasure _m0 = FrameMeasure.of(_lin0, skin: _mask);
  late final List<SkinTarget> _targets = [
    for (final r in _regions)
      SkinTarget.of(
        litY: SkinReading.of(_lin0, r).litY,
        sceneWhiteY: _m0.sceneWhiteY,
        clipFraction: _m0.clipFraction,
        shift: 9 * math.log(targets.keyScale) / math.ln2,
      ),
  ];

  late final List<FaceRead> _faces0 = _read(_lin0);
  late final EnhanceScene _scene = EnhanceScene.classify(
    frame: _m0,
    faces: _faces0,
    exif: exif,
    hints: hints,
  );
  final List<EnhanceNote> _notes = [];

  EnhanceOutcome solve() {
    final wb = _whiteBalance();
    final plan = _exposure();
    _recovery(plan);
    _levels();
    final rendered = _contrast();
    _dehaze(rendered);
    _colour();
    // J. Guardrails: confidence scaling, then the skin re-check on what is
    // actually applied (§2.11), then the clean-up and do-nothing rules.
    final disagree = _disagree(_scene, plan);
    final confidence = _confidence(plan, wb, disagree);
    _scale(confidence, disagree: disagree);
    _recheckSkin();
    final (finished, nothing) = _finish();
    if (nothing) _notes.insert(0, EnhanceNote.nothingToDo);
    final last = _read(_linear());
    return EnhanceOutcome(
      settings: finished,
      confidence: confidence,
      renders: _renders,
      reasons: Map.unmodifiable(_why),
      notes: List.unmodifiable(_notes),
      scene: _scene,
      faces: List.unmodifiable(last),
      wb: wb,
      exposure: plan,
    );
  }

  /// C. White balance, from the unedited frame.
  WbSolution _whiteBalance() {
    final wb = EnhanceWb.solve(
      candidates: WbCandidates.of(
        _lin0,
        skin: _mask,
        skinTones: [for (final f in _faces0) Cast(f.skin.a, f.skin.m)],
      ),
      faces: _faces0,
      warmIntent: _scene.warmIntent,
      alreadyEdited: _scene.alreadyEdited,
      styleStrength: targets.wbStrength,
    );
    _set(P.temp, wb.temp, _wbWhy(wb, P.temp));
    _set(P.tint, wb.tint, _wbWhy(wb, P.tint));
    if (wb.verdict == WbVerdict.skinLooksRight) {
      _notes.add(EnhanceNote.whiteBalanceKept);
    }
    return wb;
  }

  /// D. Exposure, measured after white balance.
  ExposurePlan _exposure() {
    final lin = _linear();
    final read = _read(lin);
    final plan = EnhanceExposure.plan(
      frame: FrameMeasure.of(lin, skin: _mask),
      faces: read,
      scene: _scene,
      keyScale: targets.keyScale,
    );
    final clipLimit = plan.faceDriven ? 6 * _C.clipGuard : _C.clipGuard;
    var ev = EnhanceExposure.guardClipping(lin, plan.ev, clipLimit);
    // 8-bit data: light that is blown as shot cannot be recovered, and a
    // big pull would only turn it grey.
    if (_m0.clipFraction > _C.clipGuard) ev = math.max(ev, _C.evMinBlown);
    _set(P.exposure, ev, _exposureWhy(plan, ev));
    if (read.isNotEmpty && plan.facesInBand) {
      _notes.add(EnhanceNote.skinInBand);
    }
    if (_scene.lowKey) _notes.add(EnhanceNote.lowKeyKept);
    if (_scene.highKey) _notes.add(EnhanceNote.highKeyKept);
    return plan;
  }

  /// E. Highlights and shadows.
  void _recovery(ExposurePlan plan) {
    final lin = _linear();
    final frame = FrameMeasure.of(lin, skin: _mask);
    final (hl, need) = EnhanceTone.highlights(
      frame,
      skinHot: _hot(_read(lin)),
      sourceClip: _m0.hiClip,
      scene: _scene,
    );
    _set(P.highlights, hl, switch (need) {
      HighlightNeed.skin => 'to keep detail in bright skin',
      HighlightNeed.whites => 'to keep detail in the brightest whites',
      HighlightNeed.general => null,
    });
    _set(
      P.shadows,
      EnhanceTone.shadows(
        frame,
        underStops: plan.underStops,
        scene: _scene,
        iso: exif?.iso,
      ),
      plan.underStops > 0.15 ? 'to bring up the darker faces' : null,
    );
  }

  /// F. Whites, then blacks in two measured steps.
  void _levels() {
    final hasWhite = _m0.maxP99_9 >= _C.whiteTarget;
    for (var pass = 0; pass < 2; pass++) {
      final lin = _linear();
      final frame = FrameMeasure.of(lin, skin: _mask);
      if (pass == 0) {
        _set(
          P.whites,
          EnhanceTone.whites(
            frame,
            highlights: _s.value(P.highlights),
            skinHot: _hot(_read(lin)),
            extraClip: frame.clipFraction - _m0.clipFraction,
            sourceHasWhite: hasWhite,
            kind: _scene.kind,
          ),
        );
        // Giving a blown light its white back is a repair, not a taste.
        _whiteRepair = hasWhite && _s.value(P.whites) > 0;
      }
      final step = EnhanceTone.blacks(
        frame,
        scene: _scene,
        targetShift: targets.blackTargetShift,
      );
      final lo = _scene.highKey
          ? _C.blacksMinAiry
          : _scene.isPeople
          ? _C.blacksMinPortrait
          : _C.blacksMin;
      final hi = _scene.isPeople ? _C.blacksMaxPortrait : _C.blacksMax;
      _set(P.blacks, (_s.value(P.blacks) + step).clamp(lo, hi).toDouble());
    }
  }

  /// G. Contrast. Returns the frame it was judged on.
  FrameMeasure _contrast() {
    final lin = _linear();
    final frame = FrameMeasure.of(lin, skin: _mask);
    final read = _read(lin);
    final faceContrast = read.fold(0.0, (s, f) => math.max(s, f.skin.contrast));
    final hardFaces = faceContrast > _C.faceContrastMax;
    var contrast = EnhanceTone.contrast(
      frame,
      scene: _scene,
      harsh: read.isEmpty ? EnhanceTone.harshFrame(frame, _scene) : hardFaces,
      sigmaShift: targets.sigmaShift,
    );
    // Face modelling guard: no added contrast on hard-lit faces.
    if (contrast > 0 && hardFaces) contrast = 0;
    _set(P.contrast, contrast, contrast < 0 ? 'to soften harsh light' : null);
    if (contrast == 0 && frame.sigmaLStar > EnhanceTone.sigmaTarget(_scene)) {
      _notes.add(EnhanceNote.softLightKept);
    }
    return frame;
  }

  /// H. Vibrance and saturation, skin checked first.
  void _colour() {
    final lin = _linear();
    final read = _read(lin);
    final skinSaturated = read.any(
      (f) =>
          f.region.weight > _C.groupFaceWeight &&
          f.skin.chroma > f.target.chromaMax,
    );
    final (vib, sat) = EnhanceTone.colour(
      ChromaReading.of(lin, skin: _mask),
      scene: _scene,
      skinSaturated: skinSaturated,
      chromaShift: targets.chromaShift,
      vibranceCap: targets.vibranceCap,
      skinProtect: targets.skinProtect,
    );
    _set(P.vibrance, vib, read.isEmpty ? null : 'with skin tones protected');
    _set(P.saturation, sat);
    if (skinSaturated) _notes.add(EnhanceNote.skinColourKept);
  }

  void _set(ParamId p, double v, [String? why]) {
    if (locked.contains(p)) return;
    _s = _s.withValue(p, v);
    if (why == null) {
      _why.remove(p);
    } else {
      _why[p] = why;
    }
  }

  LinearPixels _linear() {
    _renders++;
    return LinearPixels.fromRgba(render(src, _s));
  }

  List<FaceRead> _read(LinearPixels px) => [
    for (var i = 0; i < _regions.length; i++)
      FaceRead(_regions[i], SkinReading.of(px, _regions[i]), _targets[i]),
  ];

  static double _hot(List<FaceRead> read) => read.fold(
    0.0,
    (s, f) =>
        f.region.weight > _C.groupFaceWeight ? math.max(s, f.skin.hot) : s,
  );

  /// One correction step when the other sliders left a weighted face
  /// outside its band or too hot (the highlights budget is already spent).
  void _recheckSkin() {
    if (_regions.isEmpty || locked.contains(P.exposure)) return;
    final read = _read(_linear());
    var step = 0.0;
    var err = 0.0, w = 0.0;
    for (final f in read) {
      if (f.region.weight <= _C.groupFaceWeight) continue;
      err += f.region.weight * f.target.error(f.lStar);
      w += f.region.weight;
    }
    // ≈ 12 L* per stop around mid tones. A face that started inside its
    // band is only ever brought back to it, never further.
    if (w > 0) step = err / w / 12;
    final hot = _hot(read);
    if (hot > _C.skinHotMax) {
      final down =
          math.log(srgbToLinear(_C.skinHotMax) / srgbToLinear(hot)) / math.ln2;
      step = math.min(step, math.max(down, -_C.hotSkinEvBudget));
    }
    if (step.abs() < 0.03) return;
    _s = _s.withValue(P.exposure, _s.value(P.exposure) + step.clamp(-0.5, 0.5));
  }

  /// Haze removal for scenes without faces (research 01 §6.9).
  void _dehaze(FrameMeasure rendered) {
    final scene = _scene;
    if (scene.hasFaces) return;
    final st = ImageStats.compute(src);
    final target = EnhanceTone.sigmaTarget(scene) + targets.sigmaShift;
    if (rendered.sigmaLStar >= target ||
        st.lumaP.p0_5 < _C.dehazeMinBlackPoint ||
        st.clipFraction > 0.01) {
      return;
    }
    _set(
      P.dehaze,
      (250 * (st.haze - _C.hazeThreshold)).clamp(0, _C.dehazeMax).toDouble(),
    );
  }

  /// Faces and histogram ask for clearly different exposures and the
  /// frame is not simply backlit (§2.11).
  static bool _disagree(EnhanceScene scene, ExposurePlan plan) =>
      plan.faceWeight > 0 &&
      !scene.backlit &&
      (plan.faceEv - plan.globalEv).abs() > _C.disagreeEv;

  double _confidence(ExposurePlan plan, WbSolution wb, bool disagree) {
    var exposure = _C.confHistogram;
    if (_faces0.isNotEmpty && plan.faceWeight > 0) {
      var known = 0.0;
      for (final f in _faces0) {
        known += f.region.weight * (f.target.confidence > 0 ? 1 : 0);
      }
      exposure = _C.confHistogram + (_C.confFaces - _C.confHistogram) * known;
      if (disagree) exposure *= _C.confDisagree;
    }
    var c = math.min(exposure, 0.5 + 0.5 * wb.confidence);
    if (_scene.alreadyEdited) c *= _C.alreadyEditedScale;
    return c.clamp(0.0, 1.0);
  }

  /// Scales every delta by [confidence] (§2.11). White balance carries its
  /// own confidence; exposure is already damped and keeps a floor, higher
  /// when a face is more than a stop outside its band.
  void _scale(double confidence, {required bool disagree}) {
    final edited = _scene.alreadyEdited;
    final wrongFace = _faces0.any(
      (f) =>
          f.region.weight > _C.groupFaceWeight &&
          f.target.error(f.lStar).abs() > 12,
    );
    for (final p in enhanceManagedParams) {
      if (locked.contains(p) || p == P.temp || p == P.tint) continue;
      if (p == P.whites && _whiteRepair) continue;
      var k = confidence;
      if (p == P.exposure) {
        k = disagree ? _C.confDisagree : 1;
        if (wrongFace) k = math.max(k, _C.confFloorWrongFace);
        if (edited) k *= _C.alreadyEditedScale;
      }
      _s = _s.withValue(p, _s.value(p) * k);
    }
  }

  /// Per-click clean-up and the do-nothing rule. Returns the settings (on
  /// the caller's geometry) and whether nothing was changed.
  (DevelopSettings, bool) _finish() {
    final from = _base.resetParams(
      enhanceManagedParams.where((p) => !locked.contains(p)),
    );
    final values = <ParamId, double>{};
    for (final p in enhanceManagedParams) {
      if (locked.contains(p)) continue;
      final v = _s.value(p);
      final zero = p == P.exposure ? _C.zeroEv : _C.zeroOther;
      values[p] = v.abs() < zero ? 0 : v;
    }
    double a(ParamId p) => (values[p] ?? 0).abs();
    final nothing =
        a(P.exposure) < _C.nothingEv &&
        a(P.temp) == 0 &&
        a(P.tint) == 0 &&
        a(P.highlights) < _C.nothingRecovery &&
        a(P.shadows) < _C.nothingRecovery &&
        a(P.whites) < _C.nothingLevels &&
        a(P.blacks) < _C.nothingLevels &&
        a(P.contrast) < _C.nothingContrast &&
        a(P.vibrance) < _C.nothingVibrance &&
        a(P.dehaze) < _C.nothingLevels;
    return (nothing ? from : from.withValues(values), nothing);
  }

  String? _wbWhy(WbSolution wb, ParamId p) {
    if (p == P.tint) {
      return wb.tint == 0
          ? null
          : wb.tint > 0
          ? 'to remove a green cast'
          : 'to remove a magenta cast';
    }
    if (wb.temp == 0) return null;
    if (wb.verdict == WbVerdict.keptWarmth) {
      return 'to ease the warm cast and keep its mood';
    }
    return wb.temp < 0 ? 'to neutralize a warm cast' : 'to remove a cool cast';
  }

  String? _exposureWhy(ExposurePlan plan, double ev) {
    if (ev == 0) return null;
    if (plan.faceDriven && plan.faceEv != 0) {
      return ev > 0
          ? 'to bring faces up to a natural level'
          : 'to bring bright skin back into range';
    }
    return null;
  }
}

/// Params Auto Enhance owns: it always solves them from their defaults and
/// replaces them (never Auto on top of Auto).
const Set<ParamId> enhanceManagedParams = {
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
