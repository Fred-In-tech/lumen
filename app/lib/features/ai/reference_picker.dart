import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/app/providers.dart';
import 'package:lumen/design/tokens.dart';
import 'package:lumen/design/type.dart';
import 'package:lumen/features/ai/color_match_service.dart';
import 'package:lumen/widgets/buttons.dart';
import 'package:lumen/widgets/thumb_image.dart';

/// Lets the user pick the photo whose look to match: "Match to last edited
/// photo" first, then the library as thumbnails. [exclude] (the photo being
/// matched) is left out. Null when dismissed.
Future<CatalogEntry?> pickReferencePhoto(
  BuildContext context, {
  Set<String> exclude = const {},
}) => showDialog<CatalogEntry>(
  context: context,
  builder: (_) => _ReferencePicker(exclude: exclude),
);

class _ReferencePicker extends ConsumerWidget {
  const _ReferencePicker({required this.exclude});

  final Set<String> exclude;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final all = ref.watch(libraryProvider).value ?? const <CatalogEntry>[];
    final entries = [
      for (final e in all)
        if (!exclude.contains(e.assetId)) e,
    ];
    final last = lastEditedExcept(entries, null);
    final narrow = MediaQuery.sizeOf(context).width < 520;
    return Dialog(
      backgroundColor: t.surface2,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 620),
        child: Padding(
          padding: const EdgeInsets.all(Sp.s5),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Match look',
                style: LumenType.title().copyWith(color: t.textPrimary),
              ),
              const SizedBox(height: Sp.s1),
              Text(
                'Pick a photo whose colour and tone to match. Every change '
                'lands on the sliders; skin keeps its colour.',
                style: LumenType.body().copyWith(color: t.textSecondary),
              ),
              const SizedBox(height: Sp.s3),
              if (last != null) ...[
                LumenButton(
                  label: 'Match to last edited photo (${last.fileName})',
                  icon: const Icon(LucideIcons.pipette, size: 14),
                  expand: true,
                  onPressed: () => Navigator.pop(context, last),
                ),
                const SizedBox(height: Sp.s3),
              ],
              if (entries.isEmpty)
                Text(
                  'Import another photo to use as a reference.',
                  style: LumenType.body().copyWith(color: t.textTertiary),
                )
              else
                Flexible(
                  child: GridView.builder(
                    shrinkWrap: true,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: narrow ? 3 : 4,
                      mainAxisSpacing: Sp.s1_5,
                      crossAxisSpacing: Sp.s1_5,
                    ),
                    itemCount: entries.length,
                    itemBuilder: (context, i) {
                      final e = entries[i];
                      return Semantics(
                        button: true,
                        label: 'Match ${e.fileName}',
                        child: Tooltip(
                          message: e.fileName,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(Rad.tile),
                            onTap: () => Navigator.pop(context, e),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(Rad.tile),
                              child: ThumbImage(entry: e),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              const SizedBox(height: Sp.s3),
              Align(
                alignment: Alignment.centerRight,
                child: LumenButton(
                  label: 'Cancel',
                  kind: ButtonKind.ghost,
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
