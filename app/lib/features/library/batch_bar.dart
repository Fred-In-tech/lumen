import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/ai/ai_providers.dart';
import 'package:lumen/app/providers.dart';
import 'package:lumen/design/tokens.dart';
import 'package:lumen/design/type.dart';
import 'package:lumen/features/ai/auto_retouch.dart';
import 'package:lumen/features/batch/batch_auto_edit.dart';
import 'package:lumen/features/batch/remeasure_sync.dart';
import 'package:lumen/features/export/export_dialog.dart';
import 'package:lumen/features/library/library_actions.dart';
import 'package:lumen/features/masks/ai_mask_source.dart';
import 'package:lumen/features/portrait/retouch_build.dart';
import 'package:lumen/features/remove/remove_providers.dart';
import 'package:lumen/features/sync/settings_clipboard.dart';
import 'package:lumen/widgets/ai_glyph.dart';
import 'package:lumen/widgets/buttons.dart';
import 'package:lumen/widgets/toast.dart';

/// Floating batch bar for the library selection (DESIGN.md §3.2, §4.11).
class BatchBar extends ConsumerWidget {
  const BatchBar({super.key, required this.entries});
  final List<CatalogEntry> entries;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final selection = ref.watch(selectionProvider);
    final progress = ref.watch(batchProvider);
    final vision =
        ref.watch(gatewayStatusProvider).value?.visionAvailable ?? false;
    final ids = [
      for (final e in entries)
        if (selection.ids.contains(e.assetId)) e.assetId,
    ];
    final phone = MediaQuery.sizeOf(context).width < Layout.phoneBreakpoint;

    Widget sep() => Container(
      width: 1,
      height: 20,
      margin: const EdgeInsets.symmetric(horizontal: Sp.s1),
      color: t.line,
    );

    final Widget content;
    if (progress != null) {
      content = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const AiGlyph(size: 16),
          const SizedBox(width: Sp.s2),
          Text(
            '${progress.label} ${progress.done + 1 > progress.total ? progress.total : progress.done + 1} of ${progress.total}',
            style: LumenType.bodyStrong().copyWith(color: t.textPrimary),
          ),
          const SizedBox(width: Sp.s3),
          SizedBox(
            width: 120,
            child: LinearProgressIndicator(
              value: progress.done / progress.total,
              minHeight: 3,
            ),
          ),
          const SizedBox(width: Sp.s3),
          LumenButton(
            label: 'Stop',
            kind: ButtonKind.ghost,
            onPressed: () => ref.read(batchProvider.notifier).cancel(),
          ),
        ],
      );
    } else {
      content = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Sp.s2),
            child: Text(
              '${ids.length} selected',
              style: LumenType.value().copyWith(color: t.textPrimary),
            ),
          ),
          sep(),
          LumenButton(
            label: phone ? 'Auto' : 'Auto-edit all',
            icon: const AiGlyph(size: 14, neutral: true),
            kind: vision ? ButtonKind.ai : ButtonKind.secondary,
            onPressed: () async {
              final noted = <String>{};
              final (ok, failed) = await batchAutoEdit(
                ref,
                ids,
                onNote: (id, _) => noted.add(id),
              );
              if (context.mounted) {
                final base = failed == 0
                    ? '$ok photos auto-edited. Every change is a slider.'
                    : '$ok edited, $failed failed.';
                showToast(
                  context,
                  noted.isEmpty
                      ? base
                      : '$base Faces on ${noted.length} '
                            '${noted.length == 1 ? 'photo' : 'photos'} were '
                            'not retouched (face analysis unavailable).',
                  kind: vision ? ToastKind.ai : ToastKind.success,
                );
              }
            },
          ),
          const SizedBox(width: Sp.s1),
          _PresetMenu(ids: ids),
          if (!phone)
            LumenButton(
              label: 'Sync',
              kind: ButtonKind.ghost,
              tooltip:
                  'Paste copied settings onto the selection (portrait '
                  'retouch is re-measured per photo; see Settings)',
              onPressed: () async {
                final clip = ref.read(settingsClipboardProvider);
                if (clip == null) {
                  showToast(
                    context,
                    'Copy settings in the editor first, then sync them here.',
                  );
                  return;
                }
                var skipped = 0;
                final n = await syncSettingsToAssets(
                  ref,
                  clip.settings,
                  clip.groups,
                  ids,
                  sourceAssetId: clip.sourceAssetId,
                  onHealsSkipped: (k) => skipped = k,
                );
                final source = clip.sourceAssetId;
                final remeasure =
                    ref.read(settingsProvider).value?.remeasureRetouchOnSync ??
                    true;
                if (remeasure &&
                    source != null &&
                    clip.groups.contains(SettingsGroup.portrait) &&
                    clip.settings.portrait.hasFaceEdits) {
                  await remeasureSyncedRetouch(
                    repo: ref.read(catalogRepositoryProvider),
                    planner: ref.read(autoRetouchPlannerProvider),
                    sourceAssetId: source,
                    sourceSettings: clip.settings,
                    targets: ids,
                  );
                }
                for (final id in ids) {
                  final doc = await ref
                      .read(catalogRepositoryProvider)
                      .loadEdit(id);
                  await refreshThumbnail(
                    ref.read(catalogRepositoryProvider),
                    id,
                    doc.settings,
                    patches: () => ref.read(patchStoreProvider.future),
                    maskLoader: ref.read(aiMaskRasterLoaderProvider),
                    retouch: ref.read(storedRetouchLoaderProvider).load,
                  );
                }
                if (context.mounted) {
                  showToast(
                    context,
                    skipped == 0
                        ? 'Settings synced to $n photos.'
                        : 'Settings synced to $n photos. '
                              '${skippedHealsMessage(skipped)}',
                    kind: ToastKind.success,
                  );
                }
              },
            ),
          LumenButton(
            label: 'Export',
            kind: ButtonKind.ghost,
            onPressed: () => showExportDialog(context, ref, ids),
          ),
          LumenIconButton(
            icon: LucideIcons.trash2,
            tooltip: 'Remove from library',
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (_) => AlertDialog(
                  title: Text(
                    'Remove ${ids.length} photos?',
                    style: LumenType.title().copyWith(color: t.textPrimary),
                  ),
                  content: Text(
                    'They’ll be removed from the library with their edits. Your original files elsewhere are untouched.',
                    style: LumenType.body().copyWith(color: t.textSecondary),
                  ),
                  actions: [
                    LumenButton(
                      label: 'Cancel',
                      kind: ButtonKind.ghost,
                      onPressed: () => Navigator.pop(context, false),
                    ),
                    LumenButton(
                      label: 'Remove',
                      kind: ButtonKind.danger,
                      onPressed: () => Navigator.pop(context, true),
                    ),
                  ],
                ),
              );
              if (ok == true && context.mounted) {
                await deleteSelected(context, ref);
              }
            },
          ),
          sep(),
          LumenIconButton(
            icon: LucideIcons.x,
            tooltip: 'Clear selection  Esc',
            onPressed: ref.read(selectionProvider.notifier).clear,
          ),
        ],
      );
    }
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: Sp.s2),
      decoration: BoxDecoration(
        color: t.surface3,
        borderRadius: BorderRadius.circular(Rad.xl),
        boxShadow: Elevation.e2,
        border: Border.all(color: const Color(0x66000000)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: content,
      ),
    );
  }
}

class _PresetMenu extends ConsumerWidget {
  const _PresetMenu({required this.ids});
  final List<String> ids;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final user = ref.watch(userPresetsProvider).value ?? const <Preset>[];
    return PopupMenuButton<Preset>(
      tooltip: 'Apply preset',
      color: t.surface3,
      onSelected: (p) async {
        final n = await applyPresetToAssets(ref, p, ids);
        if (context.mounted) {
          showToast(
            context,
            '“${p.name}” applied to $n photos.',
            kind: ToastKind.success,
          );
        }
      },
      itemBuilder: (_) => [
        for (final p in [...user, ...kBuiltinPresets])
          PopupMenuItem(
            value: p,
            child: Text(
              p.name,
              style: LumenType.body().copyWith(color: t.textPrimary),
            ),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Sp.s3, vertical: Sp.s2),
        child: Text(
          'Apply preset',
          style: LumenType.button().copyWith(color: t.textSecondary),
        ),
      ),
    );
  }
}
