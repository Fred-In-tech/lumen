import 'package:flutter/material.dart';
import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/design/tokens.dart';
import 'package:lumen/design/type.dart';
import 'package:lumen/features/looks/look.dart';
import 'package:lumen/features/projects/project_dialogs.dart';
import 'package:lumen/widgets/buttons.dart';

/// What a look is and, for an imported one, what its import kept.
Future<void> showLookDetails(BuildContext context, Preset preset) =>
    showDialog<void>(
      context: context,
      builder: (context) => LookDetails(preset: preset),
    );

class LookDetails extends StatelessWidget {
  const LookDetails({super.key, required this.preset});
  final Preset preset;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final look = PresetLook(preset);
    final r = preset.importReport;
    Widget row(String label, String value) => Padding(
      padding: const EdgeInsets.only(top: Sp.s2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: LumenType.label().copyWith(color: t.textTertiary),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: LumenType.body().copyWith(color: t.textPrimary),
            ),
          ),
        ],
      ),
    );
    return ProjectDialogFrame(
      title: preset.name,
      maxWidth: 520,
      actions: [
        LumenButton(
          label: 'Close',
          kind: ButtonKind.primary,
          onPressed: () => Navigator.pop(context),
        ),
      ],
      children: [
        row('Type', look.kind.label),
        row('Source', look.sourceLabel),
        row('Group', preset.group),
        if (r != null && r.fileName.isNotEmpty) row('File', r.fileName),
        if (preset.lut case final l?)
          row('LUT', '${l.name} · ${l.amount.round()} %'),
        if (r != null && r.applied.isNotEmpty)
          row('Applied', r.applied.join(', ')),
        if (r != null && r.approximated.isNotEmpty)
          row('Approximated', r.approximated.join(', ')),
        if (r != null && r.skipped.isNotEmpty)
          row('Left out (no equivalent)', r.skipped.join(', ')),
        if (r == null) row('Changes', '${preset.adjustmentCount} settings'),
      ],
    );
  }
}
