import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/app/app_info.dart';
import 'package:lumen/design/tokens.dart';
import 'package:lumen/design/type.dart';
import 'package:lumen/features/projects/project_dialogs.dart';
import 'package:lumen/platform/platform_info.dart';
import 'package:lumen/widgets/buttons.dart';
import 'package:lumen/widgets/toast.dart';

Future<void> _copy(BuildContext context, String text, String done) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) showToast(context, done, kind: ToastKind.success);
}

Widget _para(BuildContext context, String text) => Padding(
  padding: const EdgeInsets.only(bottom: Sp.s3),
  child: Text(
    text,
    style: LumenType.body().copyWith(color: context.tokens.textSecondary),
  ),
);

Widget _step(BuildContext context, int n, String title, String body) {
  final t = context.tokens;
  return Padding(
    padding: const EdgeInsets.only(bottom: Sp.s3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: t.accentTint,
            shape: BoxShape.circle,
          ),
          child: Text('$n', style: LumenType.label().copyWith(color: t.accent)),
        ),
        const SizedBox(width: Sp.s3),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: LumenType.bodyStrong().copyWith(color: t.textPrimary),
              ),
              const SizedBox(height: 2),
              Text(
                body,
                style: LumenType.body().copyWith(color: t.textSecondary),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

/// The first-use steps (same as INSTALL.md "First use").
Future<void> showQuickStartDialog(BuildContext context) => showDialog<void>(
  context: context,
  builder: (context) => ProjectDialogFrame(
    title: 'Quick start',
    maxWidth: 520,
    actions: [
      LumenButton(
        label: 'Copy guide link',
        icon: const Icon(LucideIcons.link),
        kind: ButtonKind.ghost,
        onPressed: () => _copy(context, kInstallGuideUrl, 'Guide link copied.'),
      ),
      LumenButton(
        label: 'Got it',
        kind: ButtonKind.primary,
        onPressed: () => Navigator.pop(context),
      ),
    ],
    children: [
      _step(
        context,
        1,
        'Import a shoot',
        'Click Import and pick photos (JPEG, PNG, HEIC or camera RAW). '
            'Give the shoot a project name; the date and first file are '
            'filled in for you.',
      ),
      _step(
        context,
        2,
        'Cull',
        'Smart Cull suggests picks and rejects. Review, then Accept. '
            'P picks, X rejects.',
      ),
      _step(
        context,
        3,
        'Edit and retouch',
        'Open a photo. Auto enhances light and colour, Auto Retouch cleans '
            'up skin, and Looks gives the shoot one style. Manual has every '
            'slider.',
      ),
      _step(
        context,
        4,
        'Export',
        'Export picks with a preset (Web, Full size JPEG, Print TIFF '
            '16-bit, Instagram). The project card shows what is left.',
      ),
    ],
  ),
);

/// The current version and how updates arrive.
Future<void> showUpdatesDialog(BuildContext context) => showDialog<void>(
  context: context,
  builder: (context) => ProjectDialogFrame(
    title: 'Updates',
    actions: [
      LumenButton(
        label: 'Copy install line',
        icon: const Icon(LucideIcons.terminal),
        kind: ButtonKind.ghost,
        onPressed: () => _copy(
          context,
          kInstallCommand,
          'Install line copied. Paste it into Terminal to update now.',
        ),
      ),
      LumenButton(
        label: 'Done',
        kind: ButtonKind.primary,
        onPressed: () => Navigator.pop(context),
      ),
    ],
    children: [
      _para(context, 'You’re on ${kBrand.name} $kAppVersion.'),
      _para(
        context,
        'Updates install by themselves. The updater checks when you log in '
        'and every 6 hours, and installs a new version while the app is '
        'closed. Your photos and edits are kept.',
      ),
      _para(
        context,
        'To update right away, quit the app and run the install line again '
        'in Terminal.',
      ),
    ],
  ),
);

/// Copies a feedback note with the version and platform for a message.
Future<void> showFeedbackDialog(BuildContext context, PlatformInfo platform) =>
    showDialog<void>(
      context: context,
      builder: (context) {
        final note =
            '${kBrand.name} $kAppVersion feedback\n'
            'Platform: ${platform.isMacOS
                ? 'macOS'
                : platform.isMobile
                ? 'mobile'
                : 'desktop'}\n\n'
            'What I was editing:\n\nWhat looked wrong or got in my way:\n\n'
            'What I expected:\n';
        return ProjectDialogFrame(
          title: 'Send feedback',
          actions: [
            LumenButton(
              label: 'Cancel',
              kind: ButtonKind.ghost,
              onPressed: () => Navigator.pop(context),
            ),
            LumenButton(
              label: 'Copy feedback note',
              icon: const Icon(LucideIcons.copy),
              kind: ButtonKind.primary,
              onPressed: () async {
                await _copy(
                  context,
                  note,
                  'Feedback note copied. Paste it into your message.',
                );
                if (context.mounted) Navigator.pop(context);
              },
            ),
          ],
          children: [
            _para(
              context,
              'Tell us what you edited, what looked wrong and which Mac you’re '
              'on. A screenshot helps a lot.',
            ),
            _para(
              context,
              'Copy a short note with your app version to start from, then '
              'paste it into your message to the team.',
            ),
          ],
        );
      },
    );
