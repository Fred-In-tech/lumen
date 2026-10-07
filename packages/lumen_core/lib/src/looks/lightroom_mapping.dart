/// Lightroom / Camera Raw preset settings (`crs:` keys) → Lumen settings.
///
/// Most Lightroom sliders have a Lumen slider with the same range and the
/// same intent (`ParamSpec.xmp` names them), so those values are copied as
/// they are. The rest is converted or reported; the full table is in
/// docs/DESIGN.md ("Looks & presets").
library;

import '../model/param_registry.dart';
import '../model/tone_curve.dart';
import '../model/treatment.dart';
import 'kelvin.dart';
import 'lightroom_keys.dart';

/// A structured value of a preset (a mask, a profile look): never applied,
/// only reported. [name] is its `Name`, when it has one.
class CrsStruct {
  const CrsStruct([this.name]);
  final String? name;
}

/// The settings of one Lightroom preset, as read from its file.
class LightroomPresetData {
  const LightroomPresetData({required this.settings, this.name, this.group});

  /// `crs:` key (without prefix) → `String`, `num`, `bool`, `List` (curve
  /// points: `"x, y"` strings or flat numbers) or [CrsStruct].
  final Map<String, Object?> settings;

  /// The preset's own name (`crs:Name`, lrtemplate `title`), if any.
  final String? name;

  /// The preset's own group (`crs:Group`), if any.
  final String? group;
}

/// What a preset becomes in Lumen.
class LightroomConversion {
  const LightroomConversion({
    required this.values,
    required this.curves,
    required this.curveChannels,
    required this.treatment,
    required this.applied,
    required this.approximated,
    required this.skipped,
  });

  final Map<ParamId, double> values;
  final CurveSet? curves;
  final Set<CurveChannel>? curveChannels;
  final Treatment? treatment;

  /// Plain-language labels, each once, in a stable order.
  final List<String> applied;
  final List<String> approximated;
  final List<String> skipped;

  bool get isEmpty => values.isEmpty && curves == null && treatment == null;
}

/// Registry params by their Lightroom name.
final Map<String, ParamSpec> _byXmp = {
  for (final p in ParamRegistry.all) p.xmp: p,
};

/// Label of an applied Lumen param in the import summary.
String _labelFor(ParamSpec p) => switch (p.group) {
  ParamGroup.hsl => 'Color mixer (HSL)',
  ParamGroup.bw => 'B&W mix',
  ParamGroup.curve => 'Tone curve',
  ParamGroup.grading => 'Color grading',
  ParamGroup.detail =>
    p.id == P.noiseLuminance || p.id == P.noiseColor
        ? 'Noise reduction'
        : 'Sharpening',
  ParamGroup.effects => p.id.startsWith('grain') ? 'Grain' : 'Vignette',
  ParamGroup.color =>
    p.id == P.temp || p.id == P.tint ? 'White balance' : p.label,
  _ => p.label,
};

double? _num(Object? v) => switch (v) {
  final num n => n.isFinite ? n.toDouble() : null,
  final String s => double.tryParse(s.trim().replaceFirst(RegExp(r'^\+'), '')),
  _ => null,
};

bool? _bool(Object? v) => switch (v) {
  final bool b => b,
  final String s when s.toLowerCase() == 'true' => true,
  final String s when s.toLowerCase() == 'false' => false,
  _ => null,
};

/// Curve points from `["0, 0", "255, 255"]` (XMP) or `[0, 0, 255, 255]`
/// (lrtemplate); null when the value is not a curve.
List<CurvePoint>? _points(Object? v) {
  if (v is! List || v.isEmpty) return null;
  final nums = <double>[];
  for (final e in v) {
    if (e is num) {
      nums.add(e.toDouble());
    } else if (e is String) {
      for (final part in e.split(',')) {
        final n = double.tryParse(part.trim());
        if (n == null) return null;
        nums.add(n);
      }
    } else {
      return null;
    }
  }
  if (nums.length < 4 || nums.length.isOdd) return null;
  return [
    for (var i = 0; i < nums.length; i += 2) CurvePoint(nums[i], nums[i + 1]),
  ];
}

/// Converts the `crs:` settings of one preset. Only settings present in
/// [crs] are set (a Lightroom preset changes only what it contains).
LightroomConversion convertLightroomSettings(Map<String, Object?> crs) {
  final values = <ParamId, double>{};
  final applied = <String>{};
  final approx = <String>{};
  final skipped = <String>{};
  final unknown = <String>[];
  void set(ParamSpec p, double v, {String? approximated}) {
    values[p.id] = p.clamp(v);
    if (approximated == null) {
      applied.add(_labelFor(p));
    } else {
      approx.add(approximated);
    }
  }

  // 1. Same slider, same range: copied as is.
  final hasColorGrade = crs.keys.any((k) => k.startsWith('ColorGrade'));
  for (final e in crs.entries) {
    final spec = _byXmp[e.key];
    if (spec == null || spec.id == P.temp || spec.id == P.tint) continue;
    final v = _num(e.value);
    if (v == null) continue;
    final legacySplit = !hasColorGrade && e.key.startsWith('SplitToning');
    set(spec, v);
    if (legacySplit) {
      applied
        ..remove('Color grading')
        ..add('Split toning (as color grading)');
    }
  }

  // 2. White balance.
  _whiteBalance(crs, values, applied, approx, skipped);

  // 3. Black & white.
  final gray = _bool(crs['ConvertToGrayscale']);
  final treatment = gray == null
      ? null
      : (gray ? Treatment.bw : Treatment.color);
  if (gray == true) applied.add('Black & white');

  // 4. Point curves.
  final (curves, channels, curveNote) = _curves(crs);
  if (curves != null) {
    applied.add('Tone curve');
    if (curveNote != null) approx.add(curveNote);
  }

  // 5. Process 2010 presets (older .lrtemplate files).
  _legacy(crs, values, approx, skipped);

  // 6. Vignette style: Lumen's vignette is one style.
  final style = _num(crs['PostCropVignetteStyle']);
  if (style != null &&
      style != 1 &&
      crs.containsKey('PostCropVignetteAmount')) {
    approx.add('Vignette style (drawn as highlight priority)');
  }

  // 7. Everything else is reported.
  for (final e in crs.entries) {
    if (_byXmp.containsKey(e.key)) continue;
    final label = lightroomSkippedLabel(e.key);
    if (label == null) {
      unknown.add(e.key);
    } else if (label.isNotEmpty) {
      skipped.add(
        e.key == 'Look' && e.value is CrsStruct
            ? _profileLabel(e.value as CrsStruct)
            : label,
      );
    }
  }
  if (unknown.isNotEmpty) {
    final shown = unknown.take(3).join(', ');
    skipped.add(
      unknown.length > 3
          ? 'Other settings ($shown and ${unknown.length - 3} more)'
          : 'Other settings ($shown)',
    );
  }
  // A camera profile is one thing to the user, named once.
  if (skipped.any((s) => s.startsWith('Camera profile ('))) {
    skipped.remove('Camera profile');
  }
  return LightroomConversion(
    values: Map.unmodifiable(values),
    curves: curves,
    curveChannels: channels,
    treatment: treatment,
    applied: List.unmodifiable(applied),
    approximated: List.unmodifiable(approx),
    skipped: List.unmodifiable(skipped),
  );
}

String _profileLabel(CrsStruct look) {
  final n = look.name;
  return n == null || n.isEmpty ? 'Camera profile' : 'Camera profile ("$n")';
}

/// Temperature / Tint. Incremental values (JPEG, TIFF, HEIC presets) are
/// relative already and equal Lumen's Temp / Tint. Absolute ones (RAW
/// presets: Kelvin and −150…150) are read against a daylight "as shot"
/// ([kLightroomReferenceKelvin]) and marked approximated. "As Shot" means
/// no change; "Auto" has no equivalent.
void _whiteBalance(
  Map<String, Object?> crs,
  Map<ParamId, double> values,
  Set<String> applied,
  Set<String> approx,
  Set<String> skipped,
) {
  final mode = crs['WhiteBalance']?.toString().toLowerCase();
  final incT = _num(crs['IncrementalTemperature']);
  final incG = _num(crs['IncrementalTint']);
  if (incT != null || incG != null) {
    if (incT != null) values[P.temp] = incT.clamp(-100, 100).toDouble();
    if (incG != null) values[P.tint] = incG.clamp(-100, 100).toDouble();
    applied.add('White balance');
    return;
  }
  if (mode == 'as shot') return;
  if (mode == 'auto') {
    skipped.add('Auto white balance');
    return;
  }
  final k = _num(crs['Temperature']);
  final tint = _num(crs['Tint']);
  if (k == null && tint == null) return;
  if (k != null) values[P.temp] = kelvinToRelativeTemp(k);
  if (tint != null) values[P.tint] = absoluteTintToRelative(tint);
  approx.add('White balance (Kelvin read as a shift from daylight)');
}

(CurveSet?, Set<CurveChannel>?, String?) _curves(Map<String, Object?> crs) {
  final pv2012 = _points(crs['ToneCurvePV2012']);
  final legacy = pv2012 == null ? _points(crs['ToneCurve']) : null;
  final channels = <CurveChannel, List<CurvePoint>>{
    CurveChannel.master: ?(pv2012 ?? legacy),
    CurveChannel.red: ?_points(crs['ToneCurvePV2012Red']),
    CurveChannel.green: ?_points(crs['ToneCurvePV2012Green']),
    CurveChannel.blue: ?_points(crs['ToneCurvePV2012Blue']),
  };
  if (channels.isEmpty) return (null, null, null);
  var set = CurveSet.identity;
  var capped = false;
  channels.forEach((ch, pts) {
    capped |= pts.length > ToneCurve.kMaxPoints;
    set = set.withChannel(ch, ToneCurve.normalized(pts));
  });
  final note = legacy != null
      ? 'Tone curve (process 2010)'
      : capped
      ? 'Tone curve (more than ${ToneCurve.kMaxPoints} points)'
      : null;
  return (set, channels.keys.toSet(), note);
}

/// Process 2010 basics, only where the preset has no 2012 value.
void _legacy(
  Map<String, Object?> crs,
  Map<ParamId, double> values,
  Set<String> approx,
  Set<String> skipped,
) {
  void put(String key, String modern, ParamId id, double Function(double) f) {
    final v = _num(crs[key]);
    if (v == null || crs.containsKey(modern)) return;
    values[id] = ParamRegistry.byId(id).clamp(f(v));
    approx.add('Process 2010 basics');
  }

  put('Exposure', 'Exposure2012', P.exposure, (v) => v);
  // Process 2010 Contrast defaults to +25.
  put('Contrast', 'Contrast2012', P.contrast, (v) => v - 25);
  put('Clarity', 'Clarity2012', P.clarity, (v) => v);
  put('FillLight', 'Shadows2012', P.shadows, (v) => v);
  put('HighlightRecovery', 'Highlights2012', P.highlights, (v) => -v);
  // Process 2010 "Shadows" is the black clip, default 5.
  put('Shadows', 'Blacks2012', P.blacks, (v) => -(v - 5) * 2);
}
