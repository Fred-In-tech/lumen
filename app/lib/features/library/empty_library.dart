import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:lumen/app/providers.dart';
import 'package:lumen/design/tokens.dart';
import 'package:lumen/design/type.dart';
import 'package:lumen/widgets/buttons.dart';

/// First-run library: editorial headline + a real drop zone (DESIGN.md §3.1).
class EmptyLibrary extends ConsumerWidget {
  const EmptyLibrary({
    super.key,
    required this.dragging,
    required this.onChoose,
  });

  final bool dragging;
  final VoidCallback onChoose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final width = MediaQuery.sizeOf(context).width;
    final phone = width < Layout.phoneBreakpoint;
    final platform = ref.watch(platformInfoProvider);
    final settings = ref.watch(settingsProvider).value;
    final headline = LumenType.displayXL(touch: phone)
        .copyWith(color: t.textPrimary);
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        phone ? Sp.s6 : Sp.s20,
        phone ? Sp.s8 : Sp.s14,
        phone ? Sp.s6 : Sp.s20,
        Sp.s10,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 880),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text.rich(
              TextSpan(
                children: [
                  const TextSpan(text: 'Your photos,\n'),
                  TextSpan(
                    text: 'developed.',
                    style: headline.copyWith(fontStyle: FontStyle.italic),
                  ),
                ],
              ),
              style: headline,
            ),
            const SizedBox(height: Sp.s4),
            Text(
              'AI makes the first edit. Every change stays a slider.',
              style: LumenType.body(touch: true)
                  .copyWith(color: t.textSecondary),
            ),
            const SizedBox(height: Sp.s8),
            AnimatedContainer(
              duration: Motion.of(context, Motion.fast),
              height: phone ? 200 : 260,
              width: double.infinity,
              decoration: BoxDecoration(
                color: dragging ? t.accentTint : t.surface1,
                borderRadius: BorderRadius.circular(Rad.md),
                border: Border.all(
                  color: dragging ? t.accent : t.lineStrong,
                  width: dragging ? 2 : 1.5,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    LucideIcons.imagePlus,
                    size: 28,
                    color: dragging ? t.accent : t.textSecondary,
                  ),
                  const SizedBox(height: Sp.s3),
                  Text(
                    dragging
                        ? 'Drop to import'
                        : platform.supportsDragAndDrop
                        ? 'Drop photos here'
                        : 'Add photos to start',
                    style: LumenType.title(touch: phone)
                        .copyWith(color: t.textPrimary),
                  ),
                  const SizedBox(height: Sp.s1),
                  Text(
                    platform.isApple
                        ? 'JPEG · PNG · WebP · HEIC · Camera RAW'
                        : 'JPEG · PNG · WebP · HEIC',
                    style: LumenType.caption().copyWith(color: t.textTertiary),
                  ),
                  const SizedBox(height: Sp.s5),
                  LumenButton(
                    label: platform.isMobile
                        ? 'Choose from Photos'
                        : 'Choose photos',
                    kind: ButtonKind.primary,
                    height: phone ? 44 : 36,
                    onPressed: onChoose,
                  ),
                ],
              ),
            ),
            const SizedBox(height: Sp.s4),
            _AutoEditToggle(
              value: settings?.autoEditOnImport ?? true,
              onChanged: (v) => ref
                  .read(settingsProvider.notifier)
                  .change((s) => s.copyWith(autoEditOnImport: v)),
            ),
          ],
        ),
      ),
    );
  }
}

class _AutoEditToggle extends StatelessWidget {
  const _AutoEditToggle({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Pressable(
      onTap: () => onChanged(!value),
      semanticLabel: 'Auto-edit photos when I import them',
      scaleOnPress: false,
      builder: (context, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: Motion.fast,
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: value ? t.accent : Colors.transparent,
              borderRadius: BorderRadius.circular(Rad.xs),
              border: Border.all(
                color: value ? t.accent : t.lineStrong,
                width: 1.5,
              ),
            ),
            child: value
                ? Icon(LucideIcons.check, size: 13, color: t.textOnAccent)
                : null,
          ),
          const SizedBox(width: Sp.s2),
          Flexible(
            child: Text(
              'Auto-edit photos when I import them',
              style: LumenType.body().copyWith(color: t.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}
