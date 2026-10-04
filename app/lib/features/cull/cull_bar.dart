import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/app/providers.dart';
import 'package:lumen/design/tokens.dart';
import 'package:lumen/design/type.dart';
import 'package:lumen/features/cull/cull_actions.dart';
import 'package:lumen/features/cull/cull_providers.dart';
import 'package:lumen/features/cull/library_filter.dart';
import 'package:lumen/widgets/buttons.dart';
import 'package:lumen/widgets/toast.dart';

/// Library culling strip: filter chips with counts, the pending-suggestion
/// review (Accept / Dismiss) and the Smart Cull button with progress.
class CullBar extends ConsumerWidget {
  const CullBar({super.key, required this.entries});

  /// All library entries (unfiltered, library order).
  final List<CatalogEntry> entries;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final records = ref.watch(cullRecordsProvider).value ?? const {};
    final filter = ref.watch(libraryFilterProvider);
    final run = ref.watch(smartCullProvider);
    final counts = libraryFilterCounts(entries, records);
    final pending = pendingSuggestions(records, [
      for (final e in entries) e.assetId,
    ]);
    final picks = pending.values
        .where((s) => s.decision == CullDecision.pick)
        .length;
    final rejects = pending.values
        .where((s) => s.decision == CullDecision.reject)
        .length;
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: Sp.s3),
      decoration: BoxDecoration(
        color: t.surface1,
        border: Border(bottom: BorderSide(color: t.line)),
      ),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final f in LibraryFilter.values)
                    Padding(
                      padding: const EdgeInsets.only(right: Sp.s1),
                      child: _FilterChip(
                        label: f.label,
                        count: counts[f] ?? 0,
                        selected: filter == f,
                        onTap: () =>
                            ref.read(libraryFilterProvider.notifier).set(f),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (run == null && pending.isNotEmpty) ...[
            Text(
              '$picks ${picks == 1 ? 'pick' : 'picks'} · $rejects '
              '${rejects == 1 ? 'reject' : 'rejects'} suggested',
              style: LumenType.caption().copyWith(color: t.textSecondary),
            ),
            const SizedBox(width: Sp.s2),
            LumenButton(
              label: 'Accept',
              kind: ButtonKind.primary,
              height: 28,
              onPressed: () => unawaited(_accept(context, ref)),
            ),
            const SizedBox(width: Sp.s1),
            LumenButton(
              label: 'Dismiss',
              kind: ButtonKind.ghost,
              height: 28,
              onPressed: () => unawaited(dismissSuggestions(ref.read)),
            ),
            const SizedBox(width: Sp.s2),
          ],
          if (run != null) ...[
            SizedBox(
              width: 120,
              child: LinearProgressIndicator(
                value: run.total == 0 ? null : run.done / run.total,
                minHeight: 3,
              ),
            ),
            const SizedBox(width: Sp.s2),
            Text(
              'Culling ${run.done}/${run.total}',
              style: LumenType.caption().copyWith(color: t.textSecondary),
            ),
            LumenIconButton(
              icon: LucideIcons.x,
              tooltip: 'Stop Smart Cull',
              onPressed: () => ref.read(smartCullProvider.notifier).cancel(),
            ),
          ] else
            LumenButton(
              label: 'Smart Cull',
              icon: const Icon(LucideIcons.sparkles),
              kind: ButtonKind.ai,
              height: 28,
              tooltip: 'Find the best of similar shots, closed eyes and blur',
              onPressed: entries.isEmpty
                  ? null
                  : () => unawaited(runSmartCull(context, ref, entries)),
            ),
        ],
      ),
    );
  }

  Future<void> _accept(BuildContext context, WidgetRef ref) async {
    final n = await acceptSuggestions(ref.read);
    if (context.mounted) {
      showToast(context, '$n ${n == 1 ? 'flag' : 'flags'} applied.');
    }
  }
}

/// Runs Smart Cull on the selection (or every photo) and reports.
Future<void> runSmartCull(
  BuildContext context,
  WidgetRef ref,
  List<CatalogEntry> entries,
) async {
  final selected = ref.read(selectionProvider).ids;
  final ids = [
    for (final e in entries)
      if (selected.isEmpty || selected.contains(e.assetId)) e.assetId,
  ];
  final outcome = await ref.read(smartCullProvider.notifier).run(ids);
  if (outcome == null || !context.mounted) return;
  final s = outcome.result.suggestions.values;
  final picks = s.where((x) => x.decision == CullDecision.pick).length;
  final rejects = s.where((x) => x.decision == CullDecision.reject).length;
  final parts = [
    '$picks ${picks == 1 ? 'pick' : 'picks'} and $rejects '
        '${rejects == 1 ? 'reject' : 'rejects'} suggested',
    if (outcome.failed.isNotEmpty)
      '${outcome.failed.length} couldn’t be measured',
    if (outcome.cancelled) 'stopped early',
  ];
  showToast(
    context,
    'Smart Cull: ${parts.join(' · ')}. Review, then Accept.',
    kind: ToastKind.ai,
  );
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Semantics(
      button: true,
      selected: selected,
      label: '$label, $count',
      child: GestureDetector(
        onTap: onTap,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: AnimatedContainer(
            duration: Motion.fast,
            height: 26,
            padding: const EdgeInsets.symmetric(horizontal: Sp.s2),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? t.accentTint : t.surface2,
              borderRadius: BorderRadius.circular(Rad.pill),
              border: Border.all(color: selected ? t.accent : t.line),
            ),
            child: Text(
              '$label  $count',
              style: LumenType.label().copyWith(
                color: selected ? t.accent : t.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
