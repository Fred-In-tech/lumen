/// Which portrait values the user set by hand: auto retouch never
/// overwrites them (the portrait counterpart of the editor's
/// `lockedByUser`). Derived from the persisted history, so it holds across
/// sessions and for photos edited outside the editor.
library;

import '../model/history.dart';
import '../model/portrait.dart';
import '../model/portrait_presets.dart';

/// `group/id` keys ([PortraitPresets.lockKey]) of group values whose last
/// change, up to the history cursor, was a manual edit (slider or curve
/// entries). A later preset, paste, AI or reset entry that changes the
/// value hands it back to auto retouch.
Set<String> manualPortraitLocks(HistoryStack history) {
  final locks = <String>{};
  for (final entry in history.entries.take(history.cursor)) {
    final manual =
        entry.kind == HistoryKind.slider || entry.kind == HistoryKind.curve;
    for (final op in entry.ops) {
      if (op.path != 'portrait') continue;
      final from = PortraitSettings.fromJson(op.from);
      final to = PortraitSettings.fromJson(op.to);
      for (final g in FaceGroup.values) {
        final a = from.groups[g] ?? const <String, double>{};
        final b = to.groups[g] ?? const <String, double>{};
        for (final id in {...a.keys, ...b.keys}) {
          if (a[id] == b[id]) continue;
          final key = PortraitPresets.lockKey(g, id);
          manual ? locks.add(key) : locks.remove(key);
        }
      }
    }
  }
  return locks;
}
