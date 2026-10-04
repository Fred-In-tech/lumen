import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;
import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/features/editor/canvas_mapping.dart';
import 'package:lumen/features/editor/editor_controller.dart';
import 'package:lumen/features/masks/mask_kinds.dart';
import 'package:lumen/features/masks/mask_ui_state.dart';

/// Reads a provider (`WidgetRef.read` or `ProviderContainer.read`).
typedef ProviderReader = T Function<T>(ProviderListenable<T> provider);

/// Every edit to `settings.masks`. Discrete edits are one history entry
/// each; drags go through [begin] / [preview] / [end] (one entry per drag).
class MaskCommands {
  MaskCommands(this._read, this.assetId);

  factory MaskCommands.of(WidgetRef ref, String assetId) =>
      MaskCommands(ref.read, assetId);

  final ProviderReader _read;
  final String assetId;

  EditorController get _ctl => _read(editorProvider(assetId).notifier);
  MaskUiNotifier get _ui => _read(maskUiProvider(assetId).notifier);
  DevelopSettings? get _settings =>
      _read(editorProvider(assetId)).value?.settings;

  List<LocalMask> get masks => _settings?.masks ?? const [];
  bool get canAdd => masks.length < LocalMask.maxMasks;

  LocalMask? byId(String id) {
    for (final m in masks) {
      if (m.id == id) return m;
    }
    return null;
  }

  /// Adds a [kind] mask (manual kinds get a default shape in the visible
  /// frame, AI kinds the stored [ai] raster), selects it and shows its
  /// overlay. Null at the [LocalMask.maxMasks] limit.
  LocalMask? add(
    MaskKind kind, {
    Size sourceSize = const Size(1, 1),
    AiShape? ai,
  }) {
    final s = _settings;
    if (s == null || !canAdd || kind == MaskKind.unsupported) return null;
    final mask = LocalMask(
      id: newMaskId(masks),
      name: nextMaskName(masks, kind),
      kind: kind,
      shape: defaultMaskShape(kind, s.geometry, sourceSize, ai: ai),
    );
    _ctl.commit(
      s.copyWith(masks: [...s.masks, mask]),
      label: 'Add ${kind.menuLabel}',
    );
    _ui
      ..select(mask.id)
      ..setShowOverlay(true);
    return mask;
  }

  /// Replaces mask [id] by `edit(mask)` as one history entry.
  void update(
    String id,
    LocalMask Function(LocalMask m) edit, {
    required String label,
  }) {
    final s = _settings;
    if (s == null) return;
    final next = _replace(s, id, edit);
    if (next != null) _ctl.commit(next, label: label);
  }

  /// Starts a drag (handles, opacity, local sliders).
  void begin(String label) => _ctl.beginGesture(label);

  /// Live drag update: no history entry.
  void preview(String id, LocalMask Function(LocalMask m) edit) {
    final s = _settings;
    if (s == null) return;
    final next = _replace(s, id, edit);
    if (next != null) _ctl.preview(next);
  }

  /// Ends a drag as one history entry (none when nothing changed).
  void end(String label) => _ctl.commitGesture(label: label);

  void rename(String id, String name) {
    final m = byId(id);
    final clean = name.trim();
    if (m == null || clean.isEmpty || clean == m.name || !m.isSupported) {
      return;
    }
    update(id, (m) => m.copyWith(name: clean), label: 'Rename ${m.name}');
  }

  void setInvert(String id, bool invert) {
    final m = byId(id);
    if (m == null || !m.isSupported || m.invert == invert) return;
    update(
      id,
      (m) => m.copyWith(invert: invert),
      label: '${invert ? 'Invert' : 'Uninvert'} ${m.name}',
    );
  }

  /// Copies mask [id] right after itself and selects the copy.
  LocalMask? duplicate(String id) {
    final s = _settings;
    final m = byId(id);
    if (s == null || m == null || !canAdd || !m.isSupported) return null;
    final copy = LocalMask(
      id: newMaskId(s.masks),
      name: _uniqueName(s.masks, '${m.name} copy'),
      kind: m.kind,
      invert: m.invert,
      opacity: m.opacity,
      shape: m.shape,
      strokes: m.strokes,
      adjustments: m.adjustments,
    );
    final i = s.masks.indexWhere((x) => x.id == id);
    final next = [...s.masks]..insert(i + 1, copy);
    _ctl.commit(s.copyWith(masks: next), label: 'Duplicate ${m.name}');
    _ui.select(copy.id);
    return copy;
  }

  /// Removes mask [id]; the selection moves to its neighbour.
  void delete(String id) {
    final s = _settings;
    final i = s?.masks.indexWhere((m) => m.id == id) ?? -1;
    if (s == null || i < 0) return;
    final name = s.masks[i].name;
    final next = [...s.masks]..removeAt(i);
    _ctl.commit(s.copyWith(masks: next), label: 'Delete $name');
    final ui = _read(maskUiProvider(assetId));
    if (ui.selectedId == id) {
      _ui.select(next.isEmpty ? null : next[math.min(i, next.length - 1)].id);
    }
    if (ui.hoverId == id) _ui.setHover(null);
  }

  void setAdjustment(String id, ParamId param, double value) {
    final m = byId(id);
    if (m == null || !m.isSupported) return;
    final spec = ParamRegistry.byId(param);
    update(
      id,
      (m) => m.withAdjustment(param, value),
      label: adjustmentLabel(m, param, spec.clamp(value)),
    );
  }

  void resetAdjustments(String id) {
    final m = byId(id);
    if (m == null || m.adjustments.isEmpty) return;
    update(
      id,
      (m) => m.copyWith(adjustments: const {}),
      label: 'Reset ${m.name}',
    );
  }

  /// Appends one finished brush stroke (one entry, one re-rasterization).
  void appendStroke(String id, BrushStroke stroke) {
    final m = byId(id);
    if (m == null || !m.isSupported || stroke.points.isEmpty) return;
    update(
      id,
      (m) => m.copyWith(strokes: [...m.strokes, stroke]),
      label: '${stroke.erase ? 'Erase' : 'Brush'} · ${m.name}',
    );
  }

  DevelopSettings? _replace(
    DevelopSettings s,
    String id,
    LocalMask Function(LocalMask m) edit,
  ) {
    final i = s.masks.indexWhere((m) => m.id == id);
    if (i < 0) return null;
    final next = [...s.masks];
    next[i] = edit(next[i]);
    return s.copyWith(masks: next);
  }
}

/// History label for a local slider ("Sky · Exposure +0.35").
String adjustmentLabel(LocalMask m, ParamId param, double v) {
  final spec = ParamRegistry.byId(param);
  final text = spec.unit == 'EV'
      ? '${v >= 0 ? '+' : ''}${v.toStringAsFixed(2)}'
      : '${v >= 0 ? '+' : ''}${v.round()}';
  return '${m.name} · ${spec.label} $text';
}

/// A fresh id that no mask in [masks] uses.
String newMaskId(List<LocalMask> masks) {
  final base =
      'mask-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';
  var id = base;
  for (var n = 2; masks.any((m) => m.id == id); n++) {
    id = '$base-$n';
  }
  return id;
}

/// "Linear 1", "Linear 2", … (the lowest free number for [kind]).
String nextMaskName(List<LocalMask> masks, MaskKind kind) {
  for (var n = 1; ; n++) {
    final name = '${kind.shortName} $n';
    if (!masks.any((m) => m.name == name)) return name;
  }
}

String _uniqueName(List<LocalMask> masks, String base) {
  var name = base;
  for (var n = 2; masks.any((m) => m.name == name); n++) {
    name = '$base $n';
  }
  return name;
}

/// The starting shape of a new mask, placed in the visible (cropped,
/// rotated) frame: a top-down linear gradient, a view-aligned ellipse in
/// the middle, nothing for a brush, the stored raster for AI kinds.
Map<String, Object?> defaultMaskShape(
  MaskKind kind,
  Geometry geometry,
  Size sourceSize, {
  AiShape? ai,
}) {
  final map = CanvasMapping.output(geometry, sourceSize);
  final w = map.view.width, h = map.view.height;
  switch (kind) {
    case MaskKind.linear:
      final (x0, y0) = map.toSource(Offset(w / 2, h * 0.1));
      final (x1, y1) = map.toSource(Offset(w / 2, h * 0.45));
      return LinearShape(x0: x0, y0: y0, x1: x1, y1: y1).toJson();
    case MaskKind.radial:
      final c = Offset(w / 2, h / 2);
      final (cx, cy) = map.toSource(c);
      // The view's x axis in source pixels gives the ellipse angle.
      final (ax, ay) = map.toSource(c + const Offset(1, 0));
      final src = map.source;
      final angle =
          math.atan2((ay - cy) * src.height, (ax - cx) * src.width) *
          180 /
          math.pi;
      final r = 0.22 * math.min(w, h);
      return RadialShape(
        cx: cx,
        cy: cy,
        rx: r * 1.25 / src.width,
        ry: r / src.height,
        angle: angle,
      ).toJson();
    case MaskKind.subject ||
        MaskKind.person ||
        MaskKind.background ||
        MaskKind.faceSkin ||
        MaskKind.hair ||
        MaskKind.clothes ||
        MaskKind.sky:
      return (ai ?? const AiShape()).toJson();
    case MaskKind.brush || MaskKind.unsupported:
      return const {};
  }
}
