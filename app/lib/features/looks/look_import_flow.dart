import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/design/tokens.dart';
import 'package:lumen/design/type.dart';
import 'package:lumen/features/looks/look_import_service.dart';
import 'package:lumen/features/projects/project_dialogs.dart';
import 'package:lumen/widgets/buttons.dart';
import 'package:lumen/widgets/toast.dart';

/// The last import of this session (the Looks page shows it again).
class LastLookImport extends Notifier<LookImportOutcome?> {
  @override
  LookImportOutcome? build() => null;

  void set(LookImportOutcome outcome) => state = outcome;
}

final lastLookImportProvider =
    NotifierProvider<LastLookImport, LookImportOutcome?>(LastLookImport.new);

/// "Import presets & LUTs": picker (multi-select), import, summary.
Future<void> pickAndImportLooks(BuildContext context, WidgetRef ref) async {
  final files = await ref.read(lookImportSourceProvider).pick();
  if (files.isEmpty || !context.mounted) return;
  await importLooksWithSummary(context, ref, files);
}

/// Files dropped on a looks area: imports the preset and LUT files among
/// them. Returns false when there were none (the drop is for someone else).
Future<bool> importDroppedLooks(
  BuildContext context,
  WidgetRef ref,
  List<XFile> items,
) async {
  if (!items.any((f) => isLookFile(f.name))) return false;
  final files = await readLookXFiles(items);
  if (files.isEmpty || !context.mounted) return false;
  await importLooksWithSummary(context, ref, files);
  return true;
}

Future<void> importLooksWithSummary(
  BuildContext context,
  WidgetRef ref,
  List<LookImportFile> files,
) async {
  showToast(
    context,
    'Reading ${files.length} ${files.length == 1 ? 'file' : 'files'}…',
  );
  final outcome = await importLooksInto(ref, files);
  ref.read(lastLookImportProvider.notifier).set(outcome);
  if (!context.mounted) return;
  await showLookImportSummary(context, outcome);
}

/// The import summary: what arrived, what had no equivalent, what was
/// converted approximately, and the files that could not be read.
Future<void> showLookImportSummary(
  BuildContext context,
  LookImportOutcome outcome,
) => showDialog<void>(
  context: context,
  builder: (context) => LookImportSummary(outcome: outcome),
);

class LookImportSummary extends StatelessWidget {
  const LookImportSummary({super.key, required this.outcome});

  final LookImportOutcome outcome;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final saved = outcome.saved;
    final skipped = [for (final p in saved) ?skippedLine(p)];
    final approx = [
      for (final p in saved)
        if (p.importReport?.approximated case final a? when a.isNotEmpty)
          '“${p.name}”: ${a.join(', ')}',
    ];
    Widget section(String title, IconData icon, List<String> lines) {
      const cap = 8;
      final shown = lines.take(cap).toList();
      return Padding(
        padding: const EdgeInsets.only(top: Sp.s4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 14, color: t.textSecondary),
                const SizedBox(width: Sp.s2),
                Text(
                  title,
                  style: LumenType.label().copyWith(color: t.textPrimary),
                ),
              ],
            ),
            const SizedBox(height: Sp.s1),
            for (final l in shown)
              Padding(
                padding: const EdgeInsets.only(left: 22, top: 2),
                child: Text(
                  l,
                  style: LumenType.body().copyWith(color: t.textSecondary),
                ),
              ),
            if (lines.length > cap)
              Padding(
                padding: const EdgeInsets.only(left: 22, top: 2),
                child: Text(
                  'and ${lines.length - cap} more',
                  style: LumenType.caption().copyWith(color: t.textTertiary),
                ),
              ),
          ],
        ),
      );
    }

    return ProjectDialogFrame(
      title: outcome.headline,
      maxWidth: 520,
      actions: [
        LumenButton(
          label: 'Done',
          kind: ButtonKind.primary,
          onPressed: () => Navigator.pop(context),
        ),
      ],
      children: [
        Text(
          saved.isEmpty
              ? 'Nothing new was added.'
              : 'Ready under Looks & presets, each with a sample of what '
                    'it does. Only the settings a preset contains are applied.',
          style: LumenType.body().copyWith(color: t.textSecondary),
        ),
        if (skipped.isNotEmpty)
          section(
            'No equivalent here (left out)',
            LucideIcons.circleSlash,
            skipped,
          ),
        if (approx.isNotEmpty)
          section(
            'Converted approximately',
            LucideIcons.equalApproximately,
            approx,
          ),
        if (outcome.result.failures.isNotEmpty)
          section('Not imported', LucideIcons.fileX, [
            for (final f in outcome.result.failures)
              '${f.fileName}: ${f.reason}',
          ]),
      ],
    );
  }
}
