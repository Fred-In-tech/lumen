import 'dart:typed_data';

import 'package:collection/collection.dart';

import '../analysis/image_stats.dart';
import '../model/develop_settings.dart';
import '../model/exif_summary.dart';
import '../model/param_registry.dart';
import '../render/rgba_buffer.dart';
import 'ai_style.dart';

/// Which engine produced (or should produce) an auto edit.
enum AutoEditEngine { local, vision, learned }

/// Whether a provider can serve requests right now.
class ProviderStatus {
  const ProviderStatus.available() : available = true, reason = null;
  const ProviderStatus.unavailable(String this.reason) : available = false;

  final bool available;
  final String? reason;
}

/// Pseudo param ids used in [ParamChange] for non-scalar changes.
abstract final class ChangeIds {
  /// `from`/`to` are 0 (color) / 1 (black & white).
  static const treatment = 'treatment';

  /// `from`/`to` are 0 (identity) / 1 (curve set).
  static const masterCurve = 'curve.master';
}

/// One explained change: [param] went [from] → [to] because of [reason].
class ParamChange {
  const ParamChange({
    required this.param,
    required this.from,
    required this.to,
    required this.reason,
  });

  factory ParamChange.fromJson(Map<String, Object?> json) => ParamChange(
    param: json['param']! as String,
    from: (json['from']! as num).toDouble(),
    to: (json['to']! as num).toDouble(),
    reason: json['reason'] as String? ?? '',
  );

  final ParamId param;
  final double from;
  final double to;
  final String reason;

  double get delta => to - from;

  Map<String, Object?> toJson() => {
    'param': param,
    'from': from,
    'to': to,
    'reason': reason,
  };

  @override
  bool operator ==(Object other) =>
      other is ParamChange &&
      other.param == param &&
      other.from == from &&
      other.to == to &&
      other.reason == reason;

  @override
  int get hashCode => Object.hash(param, from, to, reason);

  @override
  String toString() => 'ParamChange($param: $from → $to, "$reason")';
}

/// Scene understanding (from vision, or hints supplied by the caller).
class SceneInfo {
  const SceneInfo({
    this.subject,
    this.lighting,
    this.timeOfDay,
    this.keyIntent,
  });

  factory SceneInfo.fromJson(Map<String, Object?> json) => SceneInfo(
    subject: json['subject'] as String?,
    lighting: json['lighting'] as String?,
    timeOfDay: json['timeOfDay'] as String?,
    keyIntent: json['keyIntent'] as String?,
  );

  final String? subject;
  final String? lighting;

  /// e.g. `golden_hour`, `blue_hour`, `night`, `indoor_tungsten`, `day`.
  final String? timeOfDay;

  /// e.g. `normal`, `low_key`, `high_key`.
  final String? keyIntent;

  Map<String, Object?> toJson() => {
    if (subject != null) 'subject': subject,
    if (lighting != null) 'lighting': lighting,
    if (timeOfDay != null) 'timeOfDay': timeOfDay,
    if (keyIntent != null) 'keyIntent': keyIntent,
  };
}

/// Input of a style-driven auto edit.
class AutoEditInput {
  const AutoEditInput({
    required this.stats,
    this.exif,
    this.style = AiStyle.natural,
    this.current = DevelopSettings.defaults,
    this.locked = const {},
    this.previewJpeg,
    this.baseline,
    this.variants = 1,
    this.proxy,
    this.scene,
  });

  /// Stats of the unedited analysis proxy.
  final ImageStats stats;
  final ExifSummary? exif;
  final AiStyle style;

  /// The photo's settings right now.
  final DevelopSettings current;

  /// Params the user set by hand: providers never change them.
  final Set<ParamId> locked;

  /// 1024-px JPEG for the vision provider.
  final Uint8List? previewJpeg;

  /// Pre-AI state (for "less X" and the AI Amount slider).
  final DevelopSettings? baseline;
  final int variants;

  /// Unedited analysis proxy (512 px). The local provider renders it to
  /// solve; without it the local provider falls back to stats only.
  final RgbaBuffer? proxy;

  /// Optional scene hints (e.g. a previous vision answer).
  final SceneInfo? scene;
}

/// Input of an instruction ("warmer, lift shadows") edit.
class InstructInput extends AutoEditInput {
  const InstructInput({
    required this.instruction,
    required super.stats,
    super.exif,
    super.style,
    super.current,
    super.locked,
    super.previewJpeg,
    super.baseline,
    super.proxy,
    super.scene,
  });

  final String instruction;
}

/// Result of an auto edit or instruction.
class AutoEditOutcome {
  const AutoEditOutcome({
    required this.settings,
    required this.changes,
    required this.engineUsed,
    this.intent,
    this.scene,
    this.degraded = false,
    this.degradedReason,
    this.confidence = 1,
    this.suggestions = const [],
  });

  final DevelopSettings settings;

  /// Every change with its reason, in registry order.
  final List<ParamChange> changes;
  final String? intent;
  final SceneInfo? scene;
  final AutoEditEngine engineUsed;

  /// True when a fallback path produced this result.
  final bool degraded;
  final String? degradedReason;

  /// 0..1.
  final double confidence;

  /// Chips to show when an instruction was not understood.
  final List<String> suggestions;

  bool get hasChanges => changes.isNotEmpty;

  @override
  bool operator ==(Object other) =>
      other is AutoEditOutcome &&
      other.settings == settings &&
      const ListEquality<ParamChange>().equals(other.changes, changes) &&
      other.engineUsed == engineUsed &&
      other.degraded == degraded;

  @override
  int get hashCode => Object.hash(
    settings,
    const ListEquality<ParamChange>().hash(changes),
    engineUsed,
    degraded,
  );
}

/// An auto-edit engine (PLAN.md §1.8).
abstract interface class AutoEditProvider {
  AutoEditEngine get engine;

  Future<ProviderStatus> status();

  /// Style-driven full edit.
  Future<AutoEditOutcome> autoEdit(AutoEditInput input);

  /// Natural-language edit → deltas from `current`.
  Future<AutoEditOutcome> instruct(InstructInput input);
}
