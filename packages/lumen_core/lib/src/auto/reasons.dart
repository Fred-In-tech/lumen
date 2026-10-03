import '../model/develop_settings.dart';
import '../model/param_registry.dart';
import '../model/treatment.dart';
import 'auto_edit_provider.dart';

/// Builds a reason string for a change of one param.
typedef ReasonFor = String Function(ParamId param, double from, double to);

/// Templated, human "why" strings for local-engine changes.
abstract final class Reasons {
  /// Signed delta with the param's unit: "+35", "−0.50 EV", "+7.5".
  static String formatDelta(ParamId param, double delta) {
    final sign = delta < 0 ? '−' : '+';
    final mag = delta.abs();
    if (param == P.exposure) return '$sign${mag.toStringAsFixed(2)} EV';
    final rounded = mag.roundToDouble();
    final text = (mag - rounded).abs() < 0.05
        ? rounded.toStringAsFixed(0)
        : mag.toStringAsFixed(1);
    return '$sign$text';
  }

  /// Lower-case display name of [param] ("shadows", "orange saturation").
  static String paramName(ParamId param) =>
      ParamRegistry.tryById(param)?.label.toLowerCase() ?? param;

  /// Reason for a change made by the auto-tone solver.
  static String auto(ParamId param, double from, double to) {
    final d = to - from;
    final t = _templates[param];
    final v = formatDelta(param, d);
    if (t == null) {
      return '${d >= 0 ? 'Raised' : 'Lowered'} ${paramName(param)} $v';
    }
    return (d >= 0 ? t.$1 : t.$2).replaceAll('{d}', v);
  }

  /// Reason for a change contributed by an AI style's look.
  static String style(
    String styleLabel,
    ParamId param,
    double from,
    double to,
  ) => '$styleLabel look: ${paramName(param)} ${formatDelta(param, to - from)}';

  /// Reason for a change requested by an instruction.
  static String instruction(
    String instruction,
    ParamId param,
    double from,
    double to,
  ) {
    final name = paramName(param);
    final cap = name.isEmpty ? name : name[0].toUpperCase() + name.substring(1);
    return '$cap ${formatDelta(param, to - from)} for “${instruction.trim()}”';
  }

  /// Every scalar, treatment and master-curve difference between [from] and
  /// [to], in registry order, each explained by [reason].
  static List<ParamChange> diff(
    DevelopSettings from,
    DevelopSettings to,
    ReasonFor reason, {
    String treatmentReason = 'Converted to black and white',
    String curveReason = 'Shaped the tone curve',
  }) {
    final changed = from.changedParams(to);
    final out = <ParamChange>[
      for (final spec in ParamRegistry.all)
        if (changed.contains(spec.id))
          ParamChange(
            param: spec.id,
            from: from.value(spec.id),
            to: to.value(spec.id),
            reason: reason(spec.id, from.value(spec.id), to.value(spec.id)),
          ),
    ];
    if (from.treatment != to.treatment) {
      out.add(
        ParamChange(
          param: ChangeIds.treatment,
          from: from.treatment == Treatment.bw ? 1 : 0,
          to: to.treatment == Treatment.bw ? 1 : 0,
          reason: to.treatment == Treatment.bw
              ? treatmentReason
              : 'Returned to color',
        ),
      );
    }
    if (from.curves.master != to.curves.master) {
      out.add(
        ParamChange(
          param: ChangeIds.masterCurve,
          from: from.curves.master.isIdentity ? 0 : 1,
          to: to.curves.master.isIdentity ? 0 : 1,
          reason: curveReason,
        ),
      );
    }
    return List.unmodifiable(out);
  }
}

/// (increase template, decrease template); `{d}` is the signed delta.
const Map<ParamId, (String, String)> _templates = {
  P.exposure: (
    'Raised exposure {d} to brighten the midtones',
    'Lowered exposure {d} to tame an overly bright image',
  ),
  P.temp: (
    'Warmed temp {d} to neutralize a cool cast',
    'Cooled temp {d} to neutralize a warm cast',
  ),
  P.tint: (
    'Shifted tint {d} toward magenta to remove a green cast',
    'Shifted tint {d} toward green to remove a magenta cast',
  ),
  P.whites: (
    'Raised whites {d} to set a clean white point',
    'Lowered whites {d} to keep highlights from clipping',
  ),
  P.blacks: (
    'Lifted blacks {d} to rescue crushed shadows',
    'Deepened blacks {d} to restore a true black point',
  ),
  P.highlights: (
    'Raised highlights {d} to add sparkle',
    'Pulled highlights {d} to recover bright detail',
  ),
  P.shadows: (
    'Lifted shadows {d} to open up dark areas',
    'Deepened shadows {d} to keep the mood',
  ),
  P.contrast: (
    'Added contrast {d} for more depth',
    'Reduced contrast {d} to soften harsh tones',
  ),
  P.vibrance: (
    'Boosted vibrance {d} to enrich muted colors',
    'Reduced vibrance {d} to calm strong colors',
  ),
  P.saturation: (
    'Raised saturation {d} for richer color',
    'Lowered saturation {d} to tone down color',
  ),
  P.dehaze: (
    'Added dehaze {d} to cut through haze',
    'Reduced dehaze {d} for a softer atmosphere',
  ),
};
