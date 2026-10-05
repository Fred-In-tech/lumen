import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/design/tokens.dart';
import 'package:lumen/design/type.dart';
import 'package:lumen/features/info/photo_info.dart';
import 'package:lumen/import/float_sources.dart';
import 'package:lumen/widgets/buttons.dart';

/// Shows the file, camera and exposure details of [entry].
Future<void> showPhotoInfo(BuildContext context, CatalogEntry entry) =>
    showDialog<void>(
      context: context,
      builder: (_) => _PhotoInfoDialog(entry: entry),
    );

class _PhotoInfoDialog extends StatefulWidget {
  const _PhotoInfoDialog({required this.entry});

  final CatalogEntry entry;

  @override
  State<_PhotoInfoDialog> createState() => _PhotoInfoDialogState();
}

class _PhotoInfoDialogState extends State<_PhotoInfoDialog> {
  /// Whether this photo is edited on the float path (false until known,
  /// and without a provider scope).
  Future<bool>? _floatEditing;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _floatEditing ??= _lookUp();
  }

  Future<bool> _lookUp() async {
    final ProviderContainer container;
    try {
      container = ProviderScope.containerOf(context, listen: false);
      // ignore: avoid_catching_errors, the documented way to probe a scope
    } on StateError {
      return false; // No provider scope (plain widget tests).
    }
    try {
      return await container.read(
        floatEditingProvider(widget.entry.assetId).future,
      );
    } on Exception {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<bool>(
    future: _floatEditing,
    builder: (context, float) => _content(
      context,
      photoInfo(widget.entry, floatEditing: float.data ?? false),
    ),
  );

  Widget _content(BuildContext context, List<InfoSection> sections) {
    final t = context.tokens;
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
