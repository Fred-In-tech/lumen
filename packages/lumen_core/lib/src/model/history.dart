import 'package:collection/collection.dart';

import '../inpaint/heal_op.dart';
import '../model/develop_settings.dart';
import 'geometry.dart';
import 'mask.dart';
import 'param_registry.dart';
import 'portrait.dart';
import 'tone_curve.dart';
import 'treatment.dart';

enum HistoryKind {
  slider,
  ai,
  preset,
  paste,
  curve,
  geometry,
  reset,
  instruction,
  import,
}

/// One reversible change: [path] goes from [from] to [to] (JSON values).
///
/// Paths: `values.<paramId>`, `curves.<channel>`, `treatment`, `geometry`,
/// `masks`, `portrait`, `heal`.
class HistoryOp {
  const HistoryOp(this.path, this.from, this.to);

  factory HistoryOp.fromJson(Map<String, Object?> json) =>
      HistoryOp(json['path'] as String? ?? '', json['from'], json['to']);

  final String path;
  final Object? from;
  final Object? to;

  Map<String, Object?> toJson() => {'path': path, 'from': from, 'to': to};
}

DevelopSettings _apply(DevelopSettings s, String path, Object? v) {
  if (path.startsWith('values.')) {
    final id = path.substring(7);
    final spec = ParamRegistry.tryById(id);
    if (spec == null) return s;
    return s.withValue(id, v is num ? v.toDouble() : spec.defaultValue);
  }
  if (path.startsWith('curves.')) {
    final ch = CurveChannel.values.where((c) => c.name == path.substring(7));
    if (ch.isEmpty) return s;
    return s.copyWith(
      curves: s.curves.withChannel(
        ch.first,
        v == null ? ToneCurve.identity : ToneCurve.fromJson(v),
      ),
    );
  }
  return switch (path) {
    'treatment' => s.copyWith(treatment: Treatment.fromJson(v)),
    'geometry' => s.copyWith(geometry: Geometry.fromJson(v)),
    'masks' => s.copyWith(
      masks: v is List
          ? v
                .whereType<Map<Object?, Object?>>()
                .map((m) => LocalMask.fromJson(m.cast()))
                .toList()
          : [],
    ),
    'portrait' => s.copyWith(portrait: PortraitSettings.fromJson(v)),
    'heal' => s.copyWith(heal: parseHealOps(v)),
    _ => s,
  };
}

List<HistoryOp> _diffOps(DevelopSettings a, DevelopSettings b) {
  final ops = <HistoryOp>[];
  final ids = a.changedParams(b).toList()..sort();
  for (final id in ids) {
    ops.add(HistoryOp('values.$id', a.value(id), b.value(id)));
  }
  for (final c in CurveChannel.values) {
    final ca = a.curves.channel(c), cb = b.curves.channel(c);
    if (ca != cb) {
      ops.add(
        HistoryOp(
          'curves.${c.name}',
          ca.isIdentity ? null : ca.toJson(),
          cb.isIdentity ? null : cb.toJson(),
        ),
      );
    }
  }
  if (a.treatment != b.treatment) {
    ops.add(HistoryOp('treatment', a.treatment.name, b.treatment.name));
  }
  if (a.geometry != b.geometry) {
    ops.add(HistoryOp('geometry', a.geometry.toJson(), b.geometry.toJson()));
  }
  if (a.masks.length != b.masks.length || !_listEq(a.masks, b.masks)) {
    ops.add(HistoryOp('masks', a.toJson()['masks'], b.toJson()['masks']));
  }
  if (a.portrait != b.portrait) {
    ops.add(HistoryOp('portrait', a.portrait.toJson(), b.portrait.toJson()));
  }
  if (!const ListEquality<HealOp>().equals(a.heal, b.heal)) {
    ops.add(
      HistoryOp(
        'heal',
        [for (final h in a.heal) h.toJson()],
        [for (final h in b.heal) h.toJson()],
      ),
    );
  }
  return ops;
}

bool _listEq(List<LocalMask> a, List<LocalMask> b) {
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

class HistoryEntry {
  const HistoryEntry({
    required this.id,
    required this.label,
    required this.kind,
    required this.at,
    required this.ops,
    this.coalesceKey,
  });

  /// Builds an entry from the difference between two settings (may have no ops).
  factory HistoryEntry.diff({
    required String label,
    required HistoryKind kind,
    required DevelopSettings before,
    required DevelopSettings after,
    String? coalesceKey,
    DateTime? at,
  }) {
    final when = at ?? DateTime.now().toUtc();
    return HistoryEntry(
      id: 'h${when.microsecondsSinceEpoch}',
      label: label,
      kind: kind,
      at: when,
      ops: List.unmodifiable(_diffOps(before, after)),
      coalesceKey: coalesceKey,
    );
  }

  factory HistoryEntry.fromJson(Map<String, Object?> json) => HistoryEntry(
    id: json['id'] as String? ?? '',
    label: json['label'] as String? ?? '',
    kind: HistoryKind.values.firstWhere(
      (k) => k.name == json['kind'],
      orElse: () => HistoryKind.slider,
    ),
    at:
        DateTime.tryParse(json['at'] as String? ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    ops: List.unmodifiable(
      ((json['ops'] as List?) ?? const [])
          .whereType<Map<Object?, Object?>>()
          .map((m) => HistoryOp.fromJson(m.cast())),
    ),
  );

  /// Returns null when [before] and [after] are equal.
  static HistoryEntry? tryDiff({
    required String label,
    required HistoryKind kind,
    required DevelopSettings before,
    required DevelopSettings after,
    String? coalesceKey,
  }) {
    final e = HistoryEntry.diff(
      label: label,
      kind: kind,
      before: before,
      after: after,
      coalesceKey: coalesceKey,
    );
    return e.ops.isEmpty ? null : e;
  }

  final String id;
  final String label;
  final HistoryKind kind;
  final DateTime at;
  final List<HistoryOp> ops;

  /// Consecutive entries with the same non-null key are merged (not persisted).
  final String? coalesceKey;

  DevelopSettings applyForward(DevelopSettings s) =>
      ops.fold(s, (acc, op) => _apply(acc, op.path, op.to));

  DevelopSettings applyBackward(DevelopSettings s) =>
      ops.reversed.fold(s, (acc, op) => _apply(acc, op.path, op.from));

  /// Merges [next] (which happened after this) into one entry keeping this entry's `from` values.
  HistoryEntry mergedWith(HistoryEntry next) {
    final byPath = <String, HistoryOp>{for (final op in ops) op.path: op};
    for (final op in next.ops) {
      final prev = byPath[op.path];
      byPath[op.path] = HistoryOp(
        op.path,
        prev != null ? prev.from : op.from,
        op.to,
      );
    }
    return HistoryEntry(
      id: id,
      label: next.label,
      kind: kind,
      at: next.at,
      ops: List.unmodifiable(byPath.values),
      coalesceKey: coalesceKey,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'label': label,
    'kind': kind.name,
    'at': at.toIso8601String(),
    'ops': [for (final op in ops) op.toJson()],
  };
}

/// The result of an undo or redo.
typedef HistoryStep = ({HistoryStack stack, DevelopSettings settings});

/// Immutable undo/redo stack. [cursor] = number of applied entries.
class HistoryStack {
  const HistoryStack(this.entries, this.cursor);

  factory HistoryStack.fromJson(Object? json) {
    if (json is! Map) return empty;
    final entries = ((json['entries'] as List?) ?? const [])
        .whereType<Map<Object?, Object?>>()
        .map((m) => HistoryEntry.fromJson(m.cast()))
        .toList(growable: false);
    final cursor = ((json['cursor'] as num?) ?? entries.length).toInt().clamp(
      0,
      entries.length,
    );
    return HistoryStack(List.unmodifiable(entries), cursor);
  }

  static const empty = HistoryStack([], 0);
  static const int maxEntries = 200;

  final List<HistoryEntry> entries;
  final int cursor;

  bool get canUndo => cursor > 0;
  bool get canRedo => cursor < entries.length;
  HistoryEntry? get current => cursor > 0 ? entries[cursor - 1] : null;

  /// Appends [entry], truncating any redo tail. With [coalesce], merges into the
  /// previous entry when both share the same non-null coalesce key.
  HistoryStack push(HistoryEntry entry, {bool coalesce = false}) {
    final kept = entries.sublist(0, cursor);
    final last = kept.isEmpty ? null : kept.last;
    if (coalesce &&
        last != null &&
        entry.coalesceKey != null &&
        last.coalesceKey == entry.coalesceKey) {
      kept[kept.length - 1] = last.mergedWith(entry);
      return HistoryStack(List.unmodifiable(kept), kept.length);
    }
    kept.add(entry);
    final overflow = kept.length - maxEntries;
    final trimmed = overflow > 0 ? kept.sublist(overflow) : kept;
    return HistoryStack(List.unmodifiable(trimmed), trimmed.length);
  }

  HistoryStep undo(DevelopSettings current) {
    if (!canUndo) return (stack: this, settings: current);
    return (
      stack: HistoryStack(entries, cursor - 1),
      settings: entries[cursor - 1].applyBackward(current),
    );
  }

  HistoryStep redo(DevelopSettings current) {
    if (!canRedo) return (stack: this, settings: current);
    return (
      stack: HistoryStack(entries, cursor + 1),
      settings: entries[cursor].applyForward(current),
    );
  }

  Map<String, Object?> toJson() => {
    'cursor': cursor,
    'entries': [for (final e in entries) e.toJson()],
  };
}
