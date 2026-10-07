import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/app/providers.dart';
import 'package:lumen/design/tokens.dart';
import 'package:lumen/design/type.dart';
import 'package:lumen/features/home/looks.dart';
import 'package:lumen/features/looks/look_import_flow.dart';
import 'package:lumen/features/looks/looks_drop_zone.dart';
import 'package:lumen/features/shell/page_header.dart';
import 'package:lumen/features/shell/shell_location.dart';
import 'package:lumen/widgets/buttons.dart';
import 'package:lumen/widgets/dashed_card.dart';

/// Every look, and where the user manages theirs: imported presets and
/// LUTs grouped as they came (zip folders become groups), presets saved in
/// the editor, the AI styles and the built-in presets. Each card renders
/// its look on a real photo; imported ones can be renamed, deleted and
/// inspected (their import report).
class LooksPage extends ConsumerWidget {
  const LooksPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final presets = ref.watch(userPresetsProvider).value ?? const <Preset>[];
    final last = ref.watch(lastLookImportProvider);
    final mine = [
      for (final p in presets)
        if (!p.builtIn) p,
    ];
    final groups = <String, List<Preset>>{};
    for (final p in mine) {
      final g = p.source == PresetSource.user ? 'Saved in the editor' : p.group;
      groups.putIfAbsent(g, () => []).add(p);
    }
    final phone = MediaQuery.sizeOf(context).width < Layout.phoneBreakpoint;
    final pad = phone ? Sp.s4 : Sp.s8;
    SliverGridDelegate grid() => const SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent: 200,
      mainAxisExtent: 252,
      mainAxisSpacing: Sp.s4,
      crossAxisSpacing: Sp.s4,
    );
    Widget section(String title, String caption, {bool small = false}) =>
        SliverPadding(
          padding: EdgeInsets.fromLTRB(pad, small ? Sp.s4 : Sp.s6, pad, Sp.s3),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: (small ? LumenType.heading() : LumenType.titleSerif())
                      .copyWith(color: t.textPrimary),
                ),
                const SizedBox(height: 2),
                Text(
                  caption,
                  style: LumenType.body().copyWith(color: t.textTertiary),
                ),
              ],
            ),
          ),
        );
    Widget cards(List<Widget> children) => SliverPadding(
      padding: EdgeInsets.symmetric(horizontal: pad),
      sliver: SliverGrid(
        gridDelegate: grid(),
        delegate: SliverChildListDelegate(children),
      ),
    );
    String count(List<Preset> ps) {
      final luts = ps.where((p) => p.isLutOnly).length;
      final others = ps.length - luts;
      return [
        if (others > 0) '$others ${others == 1 ? 'preset' : 'presets'}',
        if (luts > 0) '$luts ${luts == 1 ? 'LUT' : 'LUTs'}',
      ].join(' · ');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          title: 'Looks & presets',
          breadcrumb: [
            (
              label: 'Home',
              onTap: () => ref
                  .read(shellLocationProvider.notifier)
                  .go(const HomeLocation()),
            ),
            (label: 'Looks & presets', onTap: null),
          ],
          subtitle: 'Give a whole shoot one look',
          actions: [
            if (last != null)
              LumenButton(
                label: 'Last import',
                kind: ButtonKind.ghost,
                icon: const Icon(LucideIcons.info),
                onPressed: () => showLookImportSummary(context, last),
              ),
            LumenButton(
              label: 'Import presets & LUTs',
              kind: ButtonKind.primary,
              icon: const Icon(LucideIcons.fileUp),
              onPressed: () => pickAndImportLooks(context, ref),
            ),
          ],
        ),
        Expanded(
          child: LooksDropZone(
            builder: (context, dragging) => CustomScrollView(
              slivers: [
                section(
                  'Your looks',
                  'Presets from Lightroom, .cube LUTs and presets saved in '
                      'the editor. Drop files here to add more.',
                ),
                cards([
                  DashedCard(
                    icon: LucideIcons.fileUp,
                    label: 'Import presets & LUTs',
                    caption: '.xmp · .lrtemplate · .zip · .cube',
                    highlight: dragging,
                    onTap: () => pickAndImportLooks(context, ref),
                  ),
                  if (groups.length <= 1)
                    for (final p in mine) LookCard(look: PresetLook(p)),
                ]),
                if (groups.length > 1)
                  for (final g in groups.entries) ...[
                    section(g.key, count(g.value), small: true),
                    cards([
                      for (final p in g.value) LookCard(look: PresetLook(p)),
                    ]),
                  ],
                section(
                  'AI styles',
                  'A model edits each photo for its own light, in this style.',
                ),
                cards([
                  for (final s in AiStyle.values) LookCard(look: StyleLook(s)),
                ]),
                section(
                  'Built-in presets',
                  'Starting points that ship with the app.',
                ),
                cards([
                  for (final p in kBuiltinPresets)
                    LookCard(look: PresetLook(p)),
                ]),
                const SliverToBoxAdapter(child: SizedBox(height: Sp.s10)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
