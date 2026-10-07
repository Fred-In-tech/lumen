import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/app/providers.dart';
import 'package:lumen/design/tokens.dart';
import 'package:lumen/design/type.dart';
import 'package:lumen/features/home/looks.dart';
import 'package:lumen/features/shell/page_header.dart';
import 'package:lumen/features/shell/shell_location.dart';
import 'package:lumen/widgets/dashed_card.dart';

/// Every look: AI styles, the user's presets and the built-in presets,
/// each usable on a whole project.
class LooksPage extends ConsumerWidget {
  const LooksPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final presets = ref.watch(userPresetsProvider).value ?? const <Preset>[];
    final user = [
      for (final p in presets)
        if (!p.builtIn) p,
    ];
    final phone = MediaQuery.sizeOf(context).width < Layout.phoneBreakpoint;
    final pad = phone ? Sp.s4 : Sp.s8;
    SliverGridDelegate grid() => const SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent: 200,
      mainAxisExtent: 236,
      mainAxisSpacing: Sp.s4,
      crossAxisSpacing: Sp.s4,
    );
    Widget section(String title, String caption) => SliverPadding(
      padding: EdgeInsets.fromLTRB(pad, Sp.s6, pad, Sp.s3),
      sliver: SliverToBoxAdapter(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: LumenType.titleSerif().copyWith(color: t.textPrimary),
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
        ),
        Expanded(
          child: CustomScrollView(
            slivers: [
              section(
                'AI styles',
                'A model edits each photo for its own light, in this style.',
              ),
              cards([
                for (final s in AiStyle.values) LookCard(look: StyleLook(s)),
              ]),
              section(
                'Your presets',
                'The same sliders on every photo. Save one from the editor.',
              ),
              cards([
                DashedCard(
                  icon: LucideIcons.slidersHorizontal,
                  label: 'Create a preset',
                  caption: 'From a photo you edited',
                  onTap: () => createPresetFlow(context, ref),
                ),
                for (final p in user) LookCard(look: PresetLook(p)),
              ]),
              section(
                'Built-in presets',
                'Starting points that ship with the app.',
              ),
              cards([
                for (final p in kBuiltinPresets) LookCard(look: PresetLook(p)),
              ]),
              const SliverToBoxAdapter(child: SizedBox(height: Sp.s10)),
            ],
          ),
        ),
      ],
    );
  }
}
