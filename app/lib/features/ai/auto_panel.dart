import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:lumen/design/tokens.dart';
import 'package:lumen/design/type.dart';
import 'package:lumen/features/ai/ai_panel.dart';
import 'package:lumen/features/ai/styles_grid.dart';
import 'package:lumen/features/editor/editor_controller.dart';
import 'package:lumen/features/editor/editor_session.dart';
import 'package:lumen/features/portrait/portrait_header.dart';
import 'package:lumen/features/portrait/portrait_state.dart';
import 'package:lumen/widgets/buttons.dart';
import 'package:lumen/widgets/toast.dart';

/// The three AI steps of Auto mode, in the order people use them: fix the
/// photo, retouch the faces, pick a look. Everything else lives in Manual.
class AutoSteps extends ConsumerWidget {
  const AutoSteps({
    super.key,
    required this.session,
    required this.onFineTuneFaces,
    this.touch = false,
  });

  final EditorSession session;

  /// Opens the manual Portrait tools.
  final VoidCallback onFineTuneFaces;
  final bool touch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = session.assetId;
    final faces = ref.watch(portraitFacesStatusProvider(id));
    final count = faces.value?.faces.length;
    final faceLine = switch (count) {
      null when faces.hasError => 'Face detection isn’t available here.',
      null => 'Looking for faces…',
      0 => 'No faces in this photo.',
      1 => '1 face found. Skin, eyes and teeth, kept natural.',
      _ => '$count faces found. Skin, eyes and teeth, kept natural.',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AutoCard(
          step: 1,
          title: 'Enhance',
          caption: 'Light, colour and tone in one click.',
          child: AiPanel(session: session, touch: touch),
        ),
        const SizedBox(height: Sp.s3),
        AutoCard(
          step: 2,
          title: 'Retouch',
          caption: faceLine,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AutoRetouchButton(assetId: id, height: touch ? 48 : 40),
              const SizedBox(height: Sp.s1_5),
              LumenButton(
                label: 'Fine-tune faces',
                icon: const Icon(LucideIcons.slidersHorizontal, size: 14),
                kind: ButtonKind.ghost,
                height: touch ? 44 : 30,
                expand: true,
                tooltip: 'Open the manual Portrait tools',
                onPressed: onFineTuneFaces,
              ),
            ],
          ),
        ),
        const SizedBox(height: Sp.s3),
        AutoCard(
          step: 3,
          title: 'Looks',
          caption: 'The AI’s edit for this photo in each style.',
          child: StylesGrid(session: session, columns: 3, horizontal: touch),
        ),
      ],
    );
  }
}

/// One numbered step card of Auto mode.
class AutoCard extends StatelessWidget {
  const AutoCard({
    super.key,
    required this.step,
    required this.title,
    required this.caption,
    required this.child,
  });

  final int step;
  final String title;
  final String caption;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.all(Sp.s3),
      decoration: BoxDecoration(
        color: t.surface0,
        borderRadius: BorderRadius.circular(Rad.lg),
        border: Border.all(color: t.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 20,
                height: 20,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: t.raised,
                  shape: BoxShape.circle,
                  border: Border.all(color: t.line),
                ),
                child: Text(
                  '$step',
                  style: LumenType.caption().copyWith(color: t.textSecondary),
                ),
              ),
              const SizedBox(width: Sp.s2),
              Text(
                title,
                style: LumenType.title().copyWith(color: t.textPrimary),
              ),
            ],
          ),
          const SizedBox(height: Sp.s1),
          Text(
            caption,
            style: LumenType.body().copyWith(color: t.textSecondary),
          ),
          const SizedBox(height: Sp.s3),
          child,
        ],
      ),
    );
  }
}

/// Right-hand panel of Auto mode (desktop/tablet): the steps, then the way
/// out to Manual.
class AutoPanel extends ConsumerWidget {
  const AutoPanel({
    super.key,
    required this.session,
    required this.width,
    required this.onManual,
    required this.onFineTuneFaces,
  });

  final EditorSession session;
  final double width;
  final VoidCallback onManual;
  final VoidCallback onFineTuneFaces;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final id = session.assetId;
    return SizedBox(
      width: width,
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(Sp.s3),
              children: [
                AutoSteps(session: session, onFineTuneFaces: onFineTuneFaces),
              ],
            ),
          ),
          Container(
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: Sp.s3),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: t.line)),
            ),
            child: Row(
              children: [
                LumenButton(
                  label: 'Reset all',
                  kind: ButtonKind.ghost,
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
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: LumenButton(
                      label: 'Fine-tune manually',
                      icon: const Icon(LucideIcons.arrowRight, size: 14),
                      onPressed: onManual,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
