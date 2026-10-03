import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/app/providers.dart';
import 'package:lumen/design/tokens.dart';
import 'package:lumen/design/type.dart';
import 'package:lumen/features/editor/editor_controller.dart';
import 'package:lumen/widgets/buttons.dart';
import 'package:lumen/widgets/toast.dart';

/// Copied develop settings + which groups to paste.
class SettingsClipboard {
  const SettingsClipboard({required this.settings, required this.groups});
  final DevelopSettings settings;
  final Set<SettingsGroup> groups;
}

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
      .set(SettingsClipboard(settings: s, groups: groups));
  if (context.mounted) {
    showToast(context, 'Settings copied (${groups.length} groups).');
  }
}

void pasteSettingsInto(BuildContext context, WidgetRef ref, String assetId) {
  final clip = ref.read(settingsClipboardProvider);
  if (clip == null) {
    showToast(context, 'Nothing copied yet. Use Copy first.');
    return;
  }
  ref.read(editorProvider(assetId).notifier).paste(clip.settings, clip.groups);
}

/// Applies [source] (filtered to [groups]) to every asset in [assetIds] as one
/// history entry per photo. Returns the number of photos changed.
Future<int> syncSettingsToAssets(
  WidgetRef ref,
  DevelopSettings source,
  Set<SettingsGroup> groups,
  Iterable<String> assetIds,
) async {
  final repo = ref.read(catalogRepositoryProvider);
  var n = 0;
  for (final id in assetIds) {
    final doc = await repo.loadEdit(id);
    final next = pasteSettings(
      source: source,
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
