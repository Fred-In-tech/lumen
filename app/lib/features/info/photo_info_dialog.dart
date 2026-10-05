import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/design/tokens.dart';
import 'package:lumen/design/type.dart';
import 'package:lumen/features/info/photo_info.dart';
import 'package:lumen/widgets/buttons.dart';

/// Shows the file, camera and exposure details of [entry].
Future<void> showPhotoInfo(BuildContext context, CatalogEntry entry) =>
    showDialog<void>(
      context: context,
      builder: (_) => _PhotoInfoDialog(entry: entry),
    );

class _PhotoInfoDialog extends StatelessWidget {
  const _PhotoInfoDialog({required this.entry});

  final CatalogEntry entry;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final sections = photoInfo(entry);
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 620),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Sp.s5, Sp.s4, Sp.s3, Sp.s2),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Photo info',
                      style: LumenType.title().copyWith(color: t.textPrimary),
                    ),
                  ),
                  LumenIconButton(
                    icon: LucideIcons.x,
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(Sp.s5, 0, Sp.s5, Sp.s5),
                children: [
                  for (final s in sections) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: Sp.s3, bottom: Sp.s1),
                      child: Text(
                        s.title,
                        style: LumenType.caption().copyWith(
                          color: t.textTertiary,
                        ),
                      ),
                    ),
                    for (final (label, value) in s.rows)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 124,
                              child: Text(
                                label,
                                style: LumenType.body().copyWith(
                                  color: t.textSecondary,
                                ),
                              ),
                            ),
                            Expanded(
                              child: SelectableText(
                                value,
                                style: LumenType.body().copyWith(
                                  color: t.textPrimary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                  if (sections.length == 1)
                    Padding(
                      padding: const EdgeInsets.only(top: Sp.s3),
                      child: Text(
                        'This file has no camera data.',
                        style: LumenType.body().copyWith(color: t.textTertiary),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
