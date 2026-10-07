import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/app/providers.dart';
import 'package:lumen/design/tokens.dart';
import 'package:lumen/design/type.dart';
import 'package:lumen/features/home/help_dialogs.dart';
import 'package:lumen/features/projects/project_import.dart';
import 'package:lumen/features/projects/project_providers.dart';
import 'package:lumen/features/shell/shell_scope.dart';
import 'package:lumen/widgets/ai_glyph.dart';
import 'package:lumen/widgets/buttons.dart';
import 'package:lumen/widgets/toggle.dart';

/// "Welcome back", or "Welcome back, Sam" with a display name.
String greetingFor(String? displayName) =>
    displayName == null ? 'Welcome back' : 'Welcome back, $displayName';

/// Home's side column: greeting with a status line, this week's numbers,
/// auto-edit on import, and quick links.
class HomeSidebar extends ConsumerWidget {
  const HomeSidebar({super.key, this.showGreeting = true});

  /// False when the greeting already sits at the top of the page (narrow
  /// layouts, where this column goes below the main one).
  final bool showGreeting;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final name = ref.watch(settingsProvider).value?.displayName;
    final summaries = ref.watch(projectSummariesProvider);
    final active = summaries.where((s) => !s.progress.isComplete).length;
    final entries = ref.watch(libraryProvider).value ?? const <CatalogEntry>[];
    final status = entries.isEmpty
        ? 'Import your first shoot to begin.'
        : active == 0
        ? 'Every shoot is delivered.'
        : '$active ${active == 1 ? 'shoot is' : 'shoots are'} in progress.';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showGreeting) ...[
          Text(
            greetingFor(name),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: LumenType.display(touch: true)
                .copyWith(color: t.textPrimary),
          ),
          const SizedBox(height: Sp.s1),
        ],
        Text(status, style: LumenType.body().copyWith(color: t.textSecondary)),
        const SizedBox(height: Sp.s5),
        _ThisWeek(stats: weekStats(entries, DateTime.now().toUtc())),
        const SizedBox(height: Sp.s3),
        const _AutoEditCard(),
        const SizedBox(height: Sp.s3),
        const _QuickLinks(),
      ],
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child, this.padding = Sp.s4});
  final Widget child;
  final double padding;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        color: t.surface1,
        borderRadius: BorderRadius.circular(Rad.lg),
        boxShadow: Elevation.e1,
      ),
      child: child,
    );
  }
}

class _ThisWeek extends StatelessWidget {
  const _ThisWeek({required this.stats});
  final WeekStats stats;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    Widget stat(String label, int n) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$n',
            style: LumenType.display().copyWith(
              color: t.textPrimary,
              fontFeatures: LumenType.tabular,
            ),
          ),
          Text(
            label,
            style: LumenType.caption().copyWith(color: t.textTertiary),
          ),
        ],
      ),
    );
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'This week',
                style: LumenType.heading().copyWith(color: t.textPrimary),
              ),
              const Spacer(),
              Text(
                'Last 7 days',
                style: LumenType.caption().copyWith(color: t.textTertiary),
              ),
            ],
          ),
          const SizedBox(height: Sp.s3),
          Semantics(
            label:
                'This week: ${stats.imported} imported, ${stats.edited} '
                'edited, ${stats.exported} exported',
            excludeSemantics: true,
            child: Row(
              children: [
                stat('Imported', stats.imported),
                stat('Edited', stats.edited),
                stat('Exported', stats.exported),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The feature that saves the most time, with its switch.
class _AutoEditCard extends ConsumerWidget {
  const _AutoEditCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final on = ref.watch(settingsProvider).value?.autoEditOnImport ?? true;
    return _Panel(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: AiGlyph(size: 16),
          ),
          const SizedBox(width: Sp.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Auto-edit on import',
                  style: LumenType.heading().copyWith(color: t.textPrimary),
                ),
                const SizedBox(height: 2),
                Text(
                  on
                      ? 'New photos arrive with a first edit and retouch. '
                            'Every change stays a slider.'
                      : 'Off: new photos arrive untouched.',
                  style: LumenType.caption().copyWith(color: t.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: Sp.s2),
          LumenToggle(
            value: on,
            label: 'Auto-edit on import',
            onChanged: (v) => ref
                .read(settingsProvider.notifier)
                .change((s) => s.copyWith(autoEditOnImport: v)),
          ),
        ],
      ),
    );
  }
}

class _QuickLinks extends ConsumerWidget {
  const _QuickLinks();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final (shell, shellRef) = ShellScope.of(context, ref);
    final platform = ref.watch(platformInfoProvider);
    Widget link(IconData icon, String label, VoidCallback onTap) => Pressable(
      onTap: onTap,
      semanticLabel: label,
      scaleOnPress: false,
      radius: Rad.sm,
      builder: (context, states) => Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: Sp.s2),
        decoration: BoxDecoration(
          color: states.contains(WidgetState.hovered)
              ? t.surface2
              : Colors.transparent,
          borderRadius: BorderRadius.circular(Rad.sm),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: t.textSecondary),
            const SizedBox(width: Sp.s3),
            Expanded(
              child: Text(
                label,
                style: LumenType.body().copyWith(color: t.textPrimary),
              ),
            ),
            Icon(LucideIcons.chevronRight, size: 14, color: t.textTertiary),
          ],
        ),
      ),
    );
    return _Panel(
      padding: Sp.s2,
      child: Column(
        children: [
          link(
            LucideIcons.imagePlus,
            'Import a shoot',
            () => pickAndImport(shell, shellRef),
          ),
          link(
            LucideIcons.bookOpen,
            'Quick start guide',
            () => showQuickStartDialog(context),
          ),
          link(
            LucideIcons.refreshCw,
            'Check for updates',
            () => showUpdatesDialog(context),
          ),
          link(
            LucideIcons.messageSquare,
            'Send feedback',
            () => showFeedbackDialog(context, platform),
          ),
        ],
      ),
    );
  }
}
