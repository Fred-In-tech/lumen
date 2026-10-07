import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/app/providers.dart';
import 'package:lumen/design/tokens.dart';
import 'package:lumen/design/type.dart';
import 'package:lumen/features/batch/batch_auto_edit.dart';
import 'package:lumen/features/home/home_screen.dart';
import 'package:lumen/features/home/looks_page.dart';
import 'package:lumen/features/library/all_photos_page.dart';
import 'package:lumen/features/library/library_actions.dart';
import 'package:lumen/features/projects/project_import.dart';
import 'package:lumen/features/projects/project_page.dart';
import 'package:lumen/features/projects/projects_page.dart';
import 'package:lumen/features/settings/settings_dialog.dart';
import 'package:lumen/features/shell/shell_location.dart';
import 'package:lumen/features/shell/shell_scope.dart';
import 'package:lumen/widgets/buttons.dart';

/// The app frame: a left rail (desktop, tablet) or a bottom tab bar
/// (phone) around Home, Projects, a project, All photos and Looks.
class AppShell extends ConsumerWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final location = ref.watch(shellLocationProvider);
    final platform = ref.watch(platformInfoProvider);
    final phone = MediaQuery.sizeOf(context).width < Layout.phoneBreakpoint;
    final page = switch (location) {
      HomeLocation() => const HomeScreen(),
      ProjectsLocation() => const ProjectsPage(),
      AllPhotosLocation() => const AllPhotosPage(),
      LooksLocation() => const LooksPage(),
      ProjectLocation(:final projectId) => ProjectPage(
        key: ValueKey(projectId),
        projectId: projectId,
      ),
    };
    final content = Stack(
      children: [
        Positioned.fill(
          child: AnimatedSwitcher(
            duration: Motion.of(context, Motion.fast),
            child: KeyedSubtree(key: ValueKey(location), child: page),
          ),
        ),
        const Positioned(top: 0, left: 0, right: 0, child: _WorkProgress()),
      ],
    );
    return ShellScope(
      shellContext: context,
      shellRef: ref,
      child: PopScope(
        canPop: location is HomeLocation,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) ref.read(shellLocationProvider.notifier).back();
        },
        child: CallbackShortcuts(
          bindings: {
            SingleActivator(
              LogicalKeyboardKey.keyI,
              meta: platform.isApple,
              control: !platform.isApple,
              shift: true,
            ): () =>
                pickAndImport(context, ref),
          },
          child: Scaffold(
            backgroundColor: t.surface0,
            body: SafeArea(
              bottom: false,
              child: phone
                  ? content
                  : Row(
                      children: [
                        _NavRail(current: location.section),
                        Expanded(child: content),
                      ],
                    ),
            ),
            bottomNavigationBar: phone
                ? _BottomTabs(current: location.section)
                : null,
          ),
        ),
      ),
    );
  }
}

/// A thin bar over the page while an import or a batch edit runs.
class _WorkProgress extends ConsumerWidget {
  const _WorkProgress();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final import = ref.watch(importProgressProvider);
    final batch = ref.watch(batchProvider);
    final double? value;
    if (import != null) {
      value = import.total == 0 ? null : import.done / import.total;
    } else if (batch != null) {
      value = batch.total == 0 ? null : batch.done / batch.total;
    } else {
      return const SizedBox.shrink();
    }
    return LinearProgressIndicator(value: value, minHeight: 2);
  }
}

typedef _NavItem = ({ShellSection section, IconData icon, String label});

const List<_NavItem> _railItems = [
  (section: ShellSection.home, icon: LucideIcons.house, label: 'Home'),
  (
    section: ShellSection.projects,
    icon: LucideIcons.folderOpen,
    label: 'Projects',
  ),
  (
    section: ShellSection.allPhotos,
    icon: LucideIcons.images,
    label: 'All photos',
  ),
  (section: ShellSection.looks, icon: LucideIcons.palette, label: 'Looks'),
];

ShellLocation _locationOf(ShellSection s) => switch (s) {
  ShellSection.home => const HomeLocation(),
  ShellSection.projects => const ProjectsLocation(),
  ShellSection.allPhotos => const AllPhotosLocation(),
  ShellSection.looks => const LooksLocation(),
};

class _NavRail extends ConsumerWidget {
  const _NavRail({required this.current});

  final ShellSection current;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final mac = ref.watch(platformInfoProvider).isMacOS;
    final nav = ref.read(shellLocationProvider.notifier);
    return Container(
      width: 84,
      decoration: BoxDecoration(
        color: t.surface1,
        border: Border(right: BorderSide(color: t.line)),
      ),
      // macOS draws the window buttons over the top-left corner.
      padding: EdgeInsets.only(top: mac ? 40 : Sp.s4, bottom: Sp.s3),
      child: Column(
        children: [
          Text(
            kBrand.name,
            style: LumenType.titleSerif().copyWith(
              color: t.textPrimary,
              fontSize: 20,
            ),
          ),
          const SizedBox(height: Sp.s5),
          for (final item in _railItems)
            _RailTile(
              icon: item.icon,
              label: item.label,
              selected: item.section == current,
              onTap: () => nav.go(_locationOf(item.section)),
            ),
          const Spacer(),
          _RailTile(
            icon: LucideIcons.settings,
            label: 'Settings',
            selected: false,
            onTap: () => showSettingsDialog(context),
          ),
        ],
      ),
    );
  }
}

class _RailTile extends StatelessWidget {
  const _RailTile({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Sp.s2, vertical: 2),
      child: Semantics(
        selected: selected,
        child: Pressable(
          onTap: onTap,
          semanticLabel: label,
          radius: Rad.md,
          builder: (context, states) {
            final hover = states.contains(WidgetState.hovered);
            final fg = selected ? t.accent : t.textSecondary;
            return AnimatedContainer(
              duration: Motion.fast,
              height: 58,
              decoration: BoxDecoration(
                color: selected
                    ? t.accentTint
                    : hover
                    ? t.surface2
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(Rad.md),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 20, color: fg),
                  const SizedBox(height: Sp.s1),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.fade,
                    softWrap: false,
                    style: LumenType.caption().copyWith(
                      color: selected ? t.accent : t.textSecondary,
                      fontWeight: selected ? FontWeight.w600 : null,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Phone navigation: Home, Projects, Import, Settings.
class _BottomTabs extends ConsumerWidget {
  const _BottomTabs({required this.current});

  final ShellSection current;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final nav = ref.read(shellLocationProvider.notifier);
    final bottom = MediaQuery.paddingOf(context).bottom;
    Widget tab(
      IconData icon,
      String label,
      bool selected,
      VoidCallback onTap,
    ) => Expanded(
      child: Semantics(
        selected: selected,
        child: Pressable(
          onTap: onTap,
          semanticLabel: label,
          scaleOnPress: false,
          builder: (context, _) => Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 22,
                color: selected ? t.accent : t.textSecondary,
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: LumenType.caption(touch: true)
                    .copyWith(color: selected ? t.accent : t.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
    return Container(
      height: Layout.phoneTabs + bottom,
      padding: EdgeInsets.only(bottom: bottom),
      decoration: BoxDecoration(
        color: t.surface1,
        border: Border(top: BorderSide(color: t.line)),
      ),
      child: Row(
        children: [
          tab(
            LucideIcons.house,
            'Home',
            current == ShellSection.home,
            () => nav.go(const HomeLocation()),
          ),
          tab(
            LucideIcons.folderOpen,
            'Projects',
            current == ShellSection.projects ||
                current == ShellSection.allPhotos,
            () => nav.go(const ProjectsLocation()),
          ),
          tab(
            LucideIcons.circlePlus,
            'Import',
            false,
            () => pickAndImport(context, ref),
          ),
          tab(
            LucideIcons.settings,
            'Settings',
            false,
            () => showSettingsDialog(context),
          ),
        ],
      ),
    );
  }
}
