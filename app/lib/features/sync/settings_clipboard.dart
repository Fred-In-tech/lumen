import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/app/providers.dart';
import 'package:lumen/design/tokens.dart';
import 'package:lumen/design/type.dart';
import 'package:lumen/features/editor/editor_controller.dart';
import 'package:lumen/features/remove/heal_transfer.dart';
import 'package:lumen/features/remove/remove_providers.dart';
import 'package:lumen/widgets/buttons.dart';
import 'package:lumen/widgets/toast.dart';

/// Copied develop settings + which groups to paste.
class SettingsClipboard {
  const SettingsClipboard({
    required this.settings,
    required this.groups,
    this.sourceAssetId,
  });
  final DevelopSettings settings;
  final Set<SettingsGroup> groups;

  /// The photo the settings came from: its heal patches are copied when
  /// "Heal & remove" is pasted onto another photo.
  final String? sourceAssetId;
}

/// "2 fixes were skipped: their patches are missing."
String skippedHealsMessage(int n) =>
    '$n ${n == 1 ? 'fix was' : 'fixes were'} skipped: '
    '${n == 1 ? 'its patch is' : 'their patches are'} missing.';

class ClipboardNotifier extends Notifier<SettingsClipboard?> {
  @override
  SettingsClipboard? build() => null;

  void set(SettingsClipboard? v) => state = v;
}

final settingsClipboardProvider =
    NotifierProvider<ClipboardNotifier, SettingsClipboard?>(
      ClipboardNotifier.new,
    );

/// Copies the open photo's settings after letting the user pick groups.
Future<void> copySettings(
  BuildContext context,
  WidgetRef ref,
  String assetId,
) async {
  final s = ref.read(editorProvider(assetId)).value?.settings;
  if (s == null) return;
  final groups = await showDialog<Set<SettingsGroup>>(
    context: context,
    builder: (_) =>
        const GroupPickerDialog(title: 'Copy settings', action: 'Copy'),
  );
  if (groups == null || groups.isEmpty) return;
  ref
      .read(settingsClipboardProvider.notifier)
      .set(
        SettingsClipboard(settings: s, groups: groups, sourceAssetId: assetId),
      );
  if (context.mounted) {
    showToast(context, 'Settings copied (${groups.length} groups).');
  }
}

/// Pastes the clipboard onto the open photo as one history entry. Heal ops
/// from another photo get their patches copied first (fresh ids).
Future<void> pasteSettingsInto(
  BuildContext context,
  WidgetRef ref,
  String assetId,
) async {
  final clip = ref.read(settingsClipboardProvider);
  if (clip == null) {
    showToast(context, 'Nothing copied yet. Use Copy first.');
    return;
  }
  final doc = ref.read(editorProvider(assetId)).value?.doc;
  if (doc == null) return;
  final prepared = await prepareHealPaste(
    source: clip.settings,
    groups: clip.groups,
    sourceAssetId: clip.sourceAssetId,
    targetAssetId: assetId,
    targetDoc: doc,
    store: () => ref.read(patchStoreProvider.future),
  );
  ref
      .read(editorProvider(assetId).notifier)
      .paste(prepared.settings, clip.groups);
  if (prepared.skipped > 0 && context.mounted) {
    showToast(context, skippedHealsMessage(prepared.skipped));
  }
}

/// Applies [source] (filtered to [groups]) to every asset in [assetIds] as one
/// history entry per photo. Returns the number of photos changed.
///
/// Heal ops from [sourceAssetId] get their patches copied into each target
/// under fresh ids; [onHealsSkipped] receives how many could not be (their
/// patch was missing), summed over all targets.
Future<int> syncSettingsToAssets(
  WidgetRef ref,
  DevelopSettings source,
  Set<SettingsGroup> groups,
  Iterable<String> assetIds, {
  String? sourceAssetId,
  ValueChanged<int>? onHealsSkipped,
}) async {
  final repo = ref.read(catalogRepositoryProvider);
  var n = 0, skipped = 0;
  for (final id in assetIds) {
    final doc = await repo.loadEdit(id);
    final prepared = await prepareHealPaste(
      source: source,
      groups: groups,
      sourceAssetId: sourceAssetId,
      targetAssetId: id,
      targetDoc: doc,
      store: () => ref.read(patchStoreProvider.future),
    );
    skipped += prepared.skipped;
    final next = pasteSettings(
      source: prepared.settings,
      target: doc.settings,
      groups: groups,
    );
    final entry = HistoryEntry.tryDiff(
      label: 'Paste settings',
      kind: HistoryKind.paste,
      before: doc.settings,
      after: next,
    );
    if (entry == null) continue;
    await repo.saveEdit(
      doc.copyWith(
        settings: next,
        history: doc.history.push(entry),
        updatedAt: DateTime.now().toUtc(),
      ),
    );
    final e = await repo.get(id);
    if (e != null) {
      await repo.update(
        e.copyWith(hasEdits: !next.isDefault, editedAt: DateTime.now().toUtc()),
      );
    }
    n++;
  }
  if (skipped > 0) onHealsSkipped?.call(skipped);
  return n;
}

/// Lets the user choose settings groups (copy dialog).
class GroupPickerDialog extends StatefulWidget {
  const GroupPickerDialog({
    super.key,
    required this.title,
    required this.action,
  });
  final String title;
  final String action;

  @override
  State<GroupPickerDialog> createState() => _GroupPickerDialogState();
}

class _GroupPickerDialogState extends State<GroupPickerDialog> {
  late final Set<SettingsGroup> _sel = {...SettingsGroup.defaultCopy};

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return AlertDialog(
      title: Text(
        widget.title,
        style: LumenType.title().copyWith(color: t.textPrimary),
      ),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final g in SettingsGroup.values)
              CheckboxListTile(
                dense: true,
                value: _sel.contains(g),
                activeColor: t.accent,
                checkColor: t.textOnAccent,
                title: Text(
                  g.label,
                  style: LumenType.body().copyWith(color: t.textPrimary),
                ),
                onChanged: (v) =>
                    setState(() => v == true ? _sel.add(g) : _sel.remove(g)),
              ),
          ],
        ),
      ),
      actions: [
        LumenButton(
          label: 'Cancel',
          kind: ButtonKind.ghost,
          onPressed: () => Navigator.pop(context),
        ),
        LumenButton(
          label: widget.action,
          kind: ButtonKind.primary,
          onPressed: () => Navigator.pop(context, _sel),
        ),
      ],
    );
  }
}
