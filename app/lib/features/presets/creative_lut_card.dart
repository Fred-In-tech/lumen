import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/design/tokens.dart';
import 'package:lumen/design/type.dart';
import 'package:lumen/features/looks/look_import_service.dart';
import 'package:lumen/features/editor/editor_controller.dart';
import 'package:lumen/widgets/lumen_slider.dart';

/// The creative LUT of the open photo: name, amount 0–100 %, remove; a
/// clear note when the LUT file is missing (the photo then renders
/// without it).
class CreativeLutCard extends ConsumerWidget {
  const CreativeLutCard({super.key, required this.assetId, required this.lut});

  final String assetId;
  final LutRef lut;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final ctl = ref.read(editorProvider(assetId).notifier);
    final available = ref.watch(lutAvailableProvider(lut.hash)).value ?? true;
    DevelopSettings? current() =>
        ref.read(editorProvider(assetId)).value?.settings;
    return Container(
      padding: const EdgeInsets.fromLTRB(Sp.s3, Sp.s2, Sp.s1, Sp.s2),
      decoration: BoxDecoration(
        color: t.surface0,
        borderRadius: BorderRadius.circular(Rad.md),
        border: Border.all(color: available ? t.line : t.warning),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(LucideIcons.swatchBook, size: 14, color: t.textSecondary),
              const SizedBox(width: Sp.s2),
              Expanded(
                child: Text(
                  'LUT: ${lut.name}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: LumenType.bodyStrong().copyWith(color: t.textPrimary),
                ),
              ),
              IconButton(
                tooltip: 'Remove LUT',
                iconSize: 14,
                visualDensity: VisualDensity.compact,
                icon: Icon(LucideIcons.x, color: t.textTertiary),
                onPressed: () {
                  final s = current();
                  if (s != null) {
                    ctl.commit(
                      s.withLut(null),
                      label: 'Remove LUT',
                      kind: HistoryKind.preset,
                    );
                  }
                },
              ),
            ],
          ),
          if (!available)
            Padding(
              padding: const EdgeInsets.only(right: Sp.s2, bottom: Sp.s1),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(LucideIcons.triangleAlert, size: 13, color: t.warning),
                  const SizedBox(width: Sp.s2),
                  Expanded(
                    child: Text(
                      'This LUT is not in your library on this computer, so '
                      'the photo shows without it. Import the .cube file to '
                      'bring it back.',
                      style: LumenType.caption().copyWith(
                        color: t.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(right: Sp.s2),
            child: LumenSlider(
              label: 'Amount',
              value: lut.amount,
              min: 0,
              max: 100,
              defaultValue: 100,
              bipolar: false,
              onChangeStart: () => ctl.beginGesture('LUT amount'),
              onChanged: (v) {
                final s = current();
                final l = s?.lut;
                if (s != null && l != null) {
                  ctl.preview(s.withLut(l.copyWith(amount: v)));
                }
              },
              onChangeEnd: () => ctl.commitGesture(kind: HistoryKind.preset),
              onCommit: (v) {
                final s = current();
                final l = s?.lut;
                if (s != null && l != null) {
                  ctl.commit(
                    s.withLut(l.copyWith(amount: v)),
                    label: 'LUT amount ${v.round()}',
                    kind: HistoryKind.preset,
                  );
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}
