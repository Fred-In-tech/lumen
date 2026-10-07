import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/ai/ai_providers.dart';
import 'package:lumen/design/tokens.dart';
import 'package:lumen/design/type.dart';
import 'package:lumen/features/ai/ai_auto_run.dart';
import 'package:lumen/features/editor/editor_controller.dart';
import 'package:lumen/features/editor/editor_session.dart';
import 'package:lumen/widgets/ai_glyph.dart';

/// The 9 AI styles as tiles, each previewed on the open photo (the photo
/// itself shows until its preview renders); each runs the AI with that
/// style.
class StylesGrid extends ConsumerWidget {
  const StylesGrid({
    super.key,
    required this.session,
    this.columns = 2,
    this.horizontal = false,
  });

  final EditorSession session;
  final int columns;
  final bool horizontal;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      ValueListenableBuilder<bool>(
        valueListenable: session.ready,
        builder: (context, _, _) => _build(context, ref),
      );

  Widget _build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final st = ref.read(editorProvider(session.assetId)).value;
    final base = st?.doc.ai?.preAi ?? st?.settings ?? DevelopSettings.defaults;
    final previews = session.stylePreviews(
      ref.read(localAutoEditProvider),
      base,
    );
    final current = ref.watch(
      editorProvider(session.assetId).select((s) => s.value?.doc.ai?.style),
    );
    final busy = ref.watch(
      editorProvider(session.assetId).select((s) => s.value?.aiBusy ?? false),
    );
    Widget tile(AiStyle style) {
      final selected = current == style.id;
      return Semantics(
        button: true,
        selected: selected,
        label: '${style.label} style',
        child: GestureDetector(
          onTap: busy ? null : () => runAiAuto(ref, session, style: style),
          child: MouseRegion(
            cursor: busy
                ? SystemMouseCursors.forbidden
                : SystemMouseCursors.click,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AspectRatio(
                  aspectRatio: 1,
                  child: AnimatedContainer(
                    duration: Motion.fast,
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(Rad.tile + 2),
                      border: Border.all(
                        color: selected ? t.accent : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(Rad.tile),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          FutureBuilder<Map<AiStyle, Uint8List>>(
                            future: previews,
                            builder: (context, snap) {
                              final bytes = snap.data?[style];
                              if (bytes != null) {
                                return Image.memory(
                                  bytes,
                                  fit: BoxFit.cover,
                                  gaplessPlayback: true,
                                );
                              }
                              // The photo itself until its styled
                              // preview lands (never a made-up swatch).
                              final before = session.renderer.before;
                              return Stack(
                                fit: StackFit.expand,
                                children: [
                                  ColoredBox(color: t.surface2),
                                  if (before != null)
                                    Opacity(
                                      opacity: 0.55,
                                      child: RawImage(
                                        image: before,
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                ],
                              );
                            },
                          ),
                          const Positioned(
                            right: 4,
                            top: 4,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: Color(0x8C000000),
                                shape: BoxShape.circle,
                              ),
                              child: Padding(
                                padding: EdgeInsets.all(3),
                                child: AiGlyph(size: 11),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: Sp.s1_5),
                Text(
                  style.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: LumenType.label().copyWith(
                    color: selected ? t.textPrimary : t.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (horizontal) {
      return SizedBox(
        height: 112,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: AiStyle.values.length,
          separatorBuilder: (_, _) => const SizedBox(width: Sp.s2),
          itemBuilder: (_, i) =>
              SizedBox(width: 84, child: tile(AiStyle.values[i])),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, c) {
        const gap = Sp.s2;
        // A square preview, then the gap and one line of label.
        final side = (c.maxWidth - gap * (columns - 1)) / columns;
        return GridView(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: gap,
            crossAxisSpacing: gap,
            mainAxisExtent: side + Sp.s1_5 + 18,
          ),
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [for (final s in AiStyle.values) tile(s)],
        );
      },
    );
  }
}
