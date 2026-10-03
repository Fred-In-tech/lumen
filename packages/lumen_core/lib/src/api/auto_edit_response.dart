/// What the vision model returns, parsed tolerantly.
///
/// Parsing never throws: unknown or non-editable params, non-numeric or
/// non-finite values and unknown atoms are dropped, unknown enum values fall
/// back to a neutral value. Ranges are clamped by [AutoEditResponse.clampedAbsolute]
/// (initial edits) or [AutoEditResponse.clampedDeltas] (instructions), on the
/// gateway and again in the app (never trust the network).
library;

import '../model/param_registry.dart';
import 'response_schema.dart';

const int _kMaxText = 400;
const int _kMaxReason = 120;
const double _kMaxAtomAmount = 2;

String _text(Object? v, {int max = _kMaxText}) {
  if (v is! String) return '';
  final t = v.trim();
  return t.length <= max ? t : t.substring(0, max);
}

double? _finite(Object? v) {
  if (v is! num) return null;
  final d = v.toDouble();
  return d.isFinite ? d : null;
}

String _oneOf(Object? v, List<String> allowed, String fallback) =>
    v is String && allowed.contains(v) ? v : fallback;

List<Map<Object?, Object?>> _maps(Object? v) =>
    v is List ? v.whereType<Map<Object?, Object?>>().toList() : const [];

class AiScene {
  const AiScene({
    this.subject = '',
    this.lighting = '',
    this.timeOfDay = 'unknown',
    this.keyIntent = 'normal',
  });

  factory AiScene.fromJson(Object? json) {
    if (json is! Map) return const AiScene();
    return AiScene(
      subject: _text(json['subject']),
      lighting: _text(json['lighting']),
      timeOfDay: _oneOf(json['timeOfDay'], kTimeOfDayValues, 'unknown'),
      keyIntent: _oneOf(json['keyIntent'], kKeyIntentValues, 'normal'),
    );
  }

  final String subject;
  final String lighting;
  final String timeOfDay;
  final String keyIntent;

  Map<String, Object?> toJson() => {
    'subject': subject,
    'lighting': lighting,
    'timeOfDay': timeOfDay,
    'keyIntent': keyIntent,
  };
}

class AiIssue {
  const AiIssue({required this.issue, this.severity = 'low'});

  final String issue;
  final String severity;

  static AiIssue? tryParse(Map<Object?, Object?> json) {
    final issue = _text(json['issue']);
    if (issue.isEmpty) return null;
    return AiIssue(
      issue: issue,
      severity: _oneOf(json['severity'], kSeverityValues, 'low'),
    );
  }

  Map<String, Object?> toJson() => {'issue': issue, 'severity': severity};
}

class AiTargets {
  const AiTargets({
    this.midLStar = 50,
    this.wbStrength = 1,
    this.contrastLevel = 'medium',
    this.colorLevel = 'natural',
  });

  factory AiTargets.fromJson(Object? json) {
    if (json is! Map) return const AiTargets();
    return AiTargets(
      midLStar: (_finite(json['midLStar']) ?? 50).clamp(0, 100).toDouble(),
      wbStrength: (_finite(json['wbStrength']) ?? 1).clamp(0, 1).toDouble(),
      contrastLevel: _oneOf(
        json['contrastLevel'],
        kContrastLevelValues,
        'medium',
      ),
      colorLevel: _oneOf(json['colorLevel'], kColorLevelValues, 'natural'),
    );
  }

  /// Desired median L* (0..100).
  final double midLStar;

  /// 0 keeps the color cast, 1 fully neutralizes it.
  final double wbStrength;
  final String contrastLevel;
  final String colorLevel;

  Map<String, Object?> toJson() => {
    'midLStar': midLStar,
    'wbStrength': wbStrength,
    'contrastLevel': contrastLevel,
    'colorLevel': colorLevel,
  };
}

class AiAtomAmount {
  const AiAtomAmount({required this.atom, required this.amount});

  /// One of [kStyleAtomIds].
  final String atom;

  /// 0..2.
  final double amount;

  static AiAtomAmount? tryParse(Map<Object?, Object?> json) {
    final atom = json['atom'];
    final amount = _finite(json['amount']);
    if (atom is! String || !kStyleAtomIds.contains(atom) || amount == null) {
      return null;
    }
    return AiAtomAmount(
      atom: atom,
      amount: amount.clamp(0, _kMaxAtomAmount).toDouble(),
    );
  }

  Map<String, Object?> toJson() => {'atom': atom, 'amount': amount};
}

class AiAdjustment {
  const AiAdjustment({
    required this.param,
    required this.value,
    this.reason = '',
  });

  final ParamId param;

  /// Absolute value (initial edit) or delta from `current` (instruct).
  final double value;

  /// User-facing, ≤ 12 words by prompt contract.
  final String reason;

  /// Null when the param is unknown, not AI-editable or the value is not a
  /// finite number.
  static AiAdjustment? tryParse(Map<Object?, Object?> json) {
    final id = json['param'];
    final value = _finite(json['value']);
    if (id is! String || value == null) return null;
    final spec = ParamRegistry.tryById(id);
    if (spec == null || !spec.aiEditable) return null;
    return AiAdjustment(
      param: id,
      value: value,
      reason: _text(json['reason'], max: _kMaxReason),
    );
  }

  AiAdjustment withValue(double v) =>
      AiAdjustment(param: param, value: v, reason: reason);

  Map<String, Object?> toJson() => {
    'param': param,
    'value': value,
    'reason': reason,
  };
}

class AiVariant {
  const AiVariant({
    this.label = '',
    this.confidence = 0.5,
    this.targets = const AiTargets(),
    this.presetAtoms = const [],
    this.adjustments = const [],
  });

  factory AiVariant.fromJson(Map<Object?, Object?> json) {
    // A later duplicate of the same param wins.
    final byParam = <ParamId, AiAdjustment>{};
    for (final m in _maps(json['adjustments'])) {
      final a = AiAdjustment.tryParse(m);
      if (a != null) byParam[a.param] = a;
    }
    return AiVariant(
      label: _text(json['label'], max: 60),
      confidence: (_finite(json['confidence']) ?? 0.5).clamp(0, 1).toDouble(),
      targets: AiTargets.fromJson(json['targets']),
      presetAtoms: List.unmodifiable(
        _maps(json['presetAtoms']).map(AiAtomAmount.tryParse).nonNulls,
      ),
      adjustments: List.unmodifiable(byParam.values),
    );
  }

  final String label;
  final double confidence;
  final AiTargets targets;
  final List<AiAtomAmount> presetAtoms;
  final List<AiAdjustment> adjustments;

  Map<ParamId, double> get valuesByParam =>
      Map.unmodifiable({for (final a in adjustments) a.param: a.value});

  AiVariant withAdjustments(Iterable<AiAdjustment> next) => AiVariant(
    label: label,
    confidence: confidence,
    targets: targets,
    presetAtoms: presetAtoms,
    adjustments: List.unmodifiable(next),
  );

  Map<String, Object?> toJson() => {
    'label': label,
    'confidence': confidence,
    'targets': targets.toJson(),
    'presetAtoms': [for (final a in presetAtoms) a.toJson()],
    'adjustments': [for (final a in adjustments) a.toJson()],
  };
}

class AutoEditResponse {
  const AutoEditResponse({
    this.scene = const AiScene(),
    this.issues = const [],
    this.intent = '',
    this.variants = const [],
    this.done = false,
  });

  factory AutoEditResponse.fromJson(Object? json) {
    if (json is! Map) return const AutoEditResponse();
    return AutoEditResponse(
      scene: AiScene.fromJson(json['scene']),
      issues: List.unmodifiable(
        _maps(json['issues']).map(AiIssue.tryParse).nonNulls,
      ),
      intent: _text(json['intent']),
      variants: List.unmodifiable(
        _maps(json['variants']).map(AiVariant.fromJson),
      ),
      done: json['done'] == true,
    );
  }

  final AiScene scene;
  final List<AiIssue> issues;
  final String intent;
  final List<AiVariant> variants;

  /// Refine/verify rounds: true means no change is needed.
  final bool done;

  AutoEditResponse _mapAdjustments(AiAdjustment? Function(AiAdjustment a) f) =>
      AutoEditResponse(
        scene: scene,
        issues: issues,
        intent: intent,
        done: done,
        variants: List.unmodifiable(
          variants.map((v) => v.withAdjustments(v.adjustments.map(f).nonNulls)),
        ),
      );

  /// Clamps absolute values to the registry ranges.
  AutoEditResponse clampedAbsolute() => _mapAdjustments(
    (a) => a.withValue(ParamRegistry.byId(a.param).clamp(a.value)),
  );

  /// Clamps deltas so that `current + delta` stays within range. Params
  /// missing from [current] are at their default.
  AutoEditResponse clampedDeltas(Map<ParamId, double> current) =>
      _mapAdjustments((a) {
        final spec = ParamRegistry.byId(a.param);
        final base = current[a.param] ?? spec.defaultValue;
        return a.withValue(spec.clamp(base + a.value) - base);
      });

  /// Removes adjustments to [params] (e.g. user-locked sliders).
  AutoEditResponse withoutParams(Set<ParamId> params) =>
      _mapAdjustments((a) => params.contains(a.param) ? null : a);

  /// Applies [AiDamping] to every adjustment. Absolute values are damped
  /// toward the default; with [deltas] the delta is scaled toward zero.
  AutoEditResponse damped({
    Map<ParamId, double>? factors,
    bool deltas = false,
  }) => _mapAdjustments((a) {
    if (deltas) {
      final f = factors?[a.param] ?? AiDamping.factorFor(a.param);
      return a.withValue(a.value * f);
    }
    return a.withValue(AiDamping.damp(a.param, a.value, factors: factors));
  });

  Map<String, Object?> toJson() => {
    'scene': scene.toJson(),
    'issues': [for (final i in issues) i.toJson()],
    'intent': intent,
    'variants': [for (final v in variants) v.toJson()],
    'done': done,
  };
}

/// Per-param damping (MonetGPT-style overshoot control). Local-contrast and
/// color params start at 0.85; everything else is undamped.
abstract final class AiDamping {
  static const double localContrastAndColor = 0.85;

  static final Map<ParamId, double> defaultFactors = Map.unmodifiable({
    for (final p in ParamRegistry.all)
      if (_isDamped(p)) p.id: localContrastAndColor,
  });

  static bool _isDamped(ParamSpec p) =>
      p.id == P.texture ||
      p.id == P.clarity ||
      p.id == P.dehaze ||
      p.id == P.vibrance ||
      p.id == P.saturation ||
      p.group == ParamGroup.hsl ||
      (p.group == ParamGroup.grading && p.id.endsWith('.sat'));

  static double factorFor(ParamId id) => defaultFactors[id] ?? 1.0;

  /// `from + (value − from) × factor`, clamped. [from] defaults to the
  /// param's default value.
  static double damp(
    ParamId id,
    double value, {
    double? from,
    Map<ParamId, double>? factors,
  }) {
    final spec = ParamRegistry.byId(id);
    final origin = from ?? spec.defaultValue;
    final f = factors?[id] ?? factorFor(id);
    return spec.clamp(origin + (value - origin) * f);
  }
}
