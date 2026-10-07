import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:lumen/app/providers.dart';
import 'package:lumen/design/tokens.dart';
import 'package:lumen/design/type.dart';
import 'package:lumen/widgets/buttons.dart';

/// One breadcrumb step; [onTap] null for the current page.
typedef Crumb = ({String label, VoidCallback? onTap});

/// Page title row: breadcrumb (Home › Projects › Name), a serif title with
/// a quiet subtitle, and the page actions on the right (below on phones).
class PageHeader extends ConsumerWidget {
  const PageHeader({
    super.key,
    required this.title,
    this.breadcrumb = const [],
    this.subtitle,
    this.actions = const [],
    this.trailingTitle,
  });

  final String title;
  final List<Crumb> breadcrumb;
  final String? subtitle;
  final List<Widget> actions;

  /// Sits right after the title (e.g. a project's "…" menu).
  final Widget? trailingTitle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final phone = MediaQuery.sizeOf(context).width < Layout.phoneBreakpoint;
    // macOS draws the window buttons over the top-left corner; the rail
    // leaves room on wider windows, the phone layout needs it here.
    final mac = ref.watch(platformInfoProvider).isMacOS;
    final h = phone ? Sp.s4 : Sp.s8;
    final titleRow = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Flexible(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style:
                (phone
                        ? LumenType.titleSerif(touch: true)
                        : LumenType.display())
                    .copyWith(color: t.textPrimary),
          ),
        ),
        if (trailingTitle != null) ...[
          const SizedBox(width: Sp.s1),
          trailingTitle!,
        ],
      ],
    );
    final heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (breadcrumb.isNotEmpty) ...[
          _Breadcrumb(crumbs: breadcrumb),
          const SizedBox(height: Sp.s1_5),
        ],
        titleRow,
        if (subtitle != null) ...[
          const SizedBox(height: Sp.s1),
          Text(
            subtitle!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: LumenType.body().copyWith(color: t.textTertiary),
          ),
        ],
      ],
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(
        h,
        phone ? (mac ? Sp.s8 : Sp.s4) : Sp.s6,
        h,
        Sp.s4,
      ),
      child: phone || actions.isEmpty
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                heading,
                if (actions.isNotEmpty) ...[
                  const SizedBox(height: Sp.s3),
                  Wrap(spacing: Sp.s2, runSpacing: Sp.s2, children: actions),
                ],
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(child: heading),
                const SizedBox(width: Sp.s4),
                Wrap(spacing: Sp.s2, runSpacing: Sp.s2, children: actions),
              ],
            ),
    );
  }
}

class _Breadcrumb extends StatelessWidget {
  const _Breadcrumb({required this.crumbs});

  final List<Crumb> crumbs;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Semantics(
      container: true,
      label: 'Breadcrumb',
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (var i = 0; i < crumbs.length; i++) ...[
            if (i > 0)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Sp.s1),
                child: Icon(
                  LucideIcons.chevronRight,
                  size: 12,
                  color: t.textTertiary,
                ),
              ),
            if (crumbs[i].onTap == null)
              Text(
                crumbs[i].label,
                style: LumenType.label().copyWith(color: t.textSecondary),
              )
            else
              Pressable(
                onTap: crumbs[i].onTap,
                semanticLabel: crumbs[i].label,
                scaleOnPress: false,
                radius: Rad.xs,
                builder: (context, states) => Text(
                  crumbs[i].label,
                  style: LumenType.label().copyWith(
                    color: states.contains(WidgetState.hovered)
                        ? t.accent
                        : t.textTertiary,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
