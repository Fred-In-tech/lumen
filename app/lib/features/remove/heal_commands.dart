import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/features/editor/editor_controller.dart';
import 'package:lumen/features/masks/mask_commands.dart' show ProviderReader;
import 'package:lumen/features/remove/remove_service.dart';
import 'package:lumen/features/remove/remove_ui_state.dart';

/// Edits to the heal list from the Remove panel: hide/show and delete are
/// one history entry each (the patch PNGs stay for undo).
class HealCommands {
  HealCommands(this._read, this.assetId);

  final ProviderReader _read;
  final String assetId;

  EditorController get _ctl => _read(editorProvider(assetId).notifier);

  List<HealOp> get ops =>
      _read(editorProvider(assetId)).value?.settings.heal ?? const [];

  /// "Remove 2": the op's kind and its place among ops of that kind.
  static String nameOf(List<HealOp> ops, HealOp op) {
    var n = 0;
    for (final o in ops) {
      if (o.kind == op.kind) n++;
      if (o.id == op.id) break;
    }
    return '${RemoveService.labelFor(op.kind)} $n';
  }

  /// "Remove 2 · Patch fill".
  static String describe(List<HealOp> ops, HealOp op) =>
      '${nameOf(ops, op)} · ${engineLabel(op.engine)}';

  void toggleHidden(String id) {
    final s = _read(editorProvider(assetId)).value?.settings;
    if (s == null) return;
    final op = s.heal.where((o) => o.id == id).firstOrNull;
    if (op == null) return;
    _ctl.commit(
      s.copyWith(
        heal: [
          for (final o in s.heal)
            o.id == id ? o.copyWith(hidden: !o.hidden) : o,
        ],
      ),
      label: '${op.hidden ? 'Show' : 'Hide'} ${nameOf(s.heal, op)}',
    );
  }

  /// Deletes the op; returns its name for the toast (null when gone).
  String? delete(String id) {
    final s = _read(editorProvider(assetId)).value?.settings;
    if (s == null) return null;
    final op = s.heal.where((o) => o.id == id).firstOrNull;
    if (op == null) return null;
    final name = nameOf(s.heal, op);
    _ctl.commit(
      s.copyWith(
        heal: [
          for (final o in s.heal)
            if (o.id != id) o,
        ],
      ),
      label: 'Delete $name',
    );
    return name;
  }
}
