import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/design/tokens.dart';
import 'package:lumen/design/type.dart';
import 'package:lumen/features/ai/ai_panel.dart';
import 'package:lumen/features/develop/histogram_view.dart';
import 'package:lumen/features/develop/sections.dart';
import 'package:lumen/features/editor/editor_controller.dart';
import 'package:lumen/features/editor/editor_session.dart';
import 'package:lumen/features/sync/settings_clipboard.dart';
import 'package:lumen/widgets/buttons.dart';
import 'package:lumen/widgets/toast.dart';

/// Right-hand develop panel (desktop/tablet): histogram, AI, groups, footer.
class DevelopPanel extends ConsumerWidget {
  const DevelopPanel({super.key, required this.session, required this.width});

  final EditorSession session;
  final double width;

  String _exifLine(ExifSummary? e) {
    if (e == null || e.isEmpty) return '';
    return [
      if (e.aperture != null)
        'f/${e.aperture!.toStringAsFixed(e.aperture! < 10 ? 1 : 0)}',
      if (e.shutter != null) '${e.shutter} s',
      if (e.iso != null) 'ISO ${e.iso}',
      if (e.focalMm != null) '${e.focalMm!.round()} mm',
    ].join(' · ');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final id = session.assetId;
    return Container(
      width: width,
      decoration: BoxDecoration(
        color: t.surface1,
        border: Border(left: BorderSide(color: t.line)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Sp.s4, Sp.s3, Sp.s4, Sp.s2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ValueListenableBuilder<Histogram?>(
                  valueListenable: session.histogram,
                  builder: (_, h, _) => HistogramView(histogram: h),
                ),
                const SizedBox(height: Sp.s1_5),
                Text(
                  _exifLine(session.entry?.exif),
                  style: LumenType.monoStyle().copyWith(color: t.textTertiary),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Sp.s4,
                    Sp.s1,
                    Sp.s4,
                    Sp.s4,
                  ),
                  child: AiPanel(session: session),
                ),
                DevelopSections(assetId: id),
                const SizedBox(height: Sp.s6),
              ],
            ),
          ),
          Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: Sp.s3),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: t.line)),
            ),
            child: Row(
              children: [
                LumenButton(
                  label: 'Copy',
                  kind: ButtonKind.ghost,
                  onPressed: () => copySettings(context, ref, id),
                ),
                LumenButton(
                  label: 'Paste',
                  kind: ButtonKind.ghost,
                  onPressed: () => pasteSettingsInto(context, ref, id),
                ),
                const Spacer(),
                LumenButton(
                  label: 'Reset all',
                  onPressed: () {
                    ref.read(editorProvider(id).notifier).resetAll();
                    showToast(
                      context,
                      'Reset all edits.',
                      actionLabel: 'Undo',
                      onAction: () =>
                          ref.read(editorProvider(id).notifier).undo(),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
