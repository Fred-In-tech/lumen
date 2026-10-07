import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:lumen/design/tokens.dart';
import 'package:lumen/design/type.dart';
import 'package:lumen/widgets/ai_glyph.dart';
import 'package:lumen/widgets/buttons.dart';

/// One hero slide: a real feature, one sentence about it, and a button
/// that does it.
class HeroSlide {
  const HeroSlide({
    required this.eyebrow,
    required this.headline,
    required this.body,
    required this.action,
    required this.onAction,
    required this.visual,
    this.ai = false,
  });

  final String eyebrow;
  final String headline;
  final String body;
  final String action;
  final VoidCallback onAction;
  final CustomPainter Function(LumenTokens t) visual;

  /// A model makes the decisions in this feature (AI glyph on the eyebrow).
  final bool ai;
}

/// The Home banner: one slide at a time with dots and arrows. It never
/// advances by itself, so nothing moves while you read it.
class HeroCarousel extends StatefulWidget {
  const HeroCarousel({super.key, required this.slides});

  final List<HeroSlide> slides;

  @override
  State<HeroCarousel> createState() => _HeroCarouselState();
}

class _HeroCarouselState extends State<HeroCarousel> {
  int _i = 0;

  void _go(int i) =>
      setState(() => _i = (i + widget.slides.length) % widget.slides.length);

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final slide = widget.slides[_i];
    return LayoutBuilder(
      builder: (context, c) {
        final narrow = c.maxWidth < 560;
        final text = _SlideText(slide: slide, narrow: narrow);
        final visual = AspectRatio(
          aspectRatio: 4 / 3,
          child: CustomPaint(painter: slide.visual(t)),
        );
        return Container(
          decoration: BoxDecoration(
            color: t.surface1,
            borderRadius: BorderRadius.circular(Rad.sheet),
            boxShadow: Elevation.e1,
          ),
          padding: EdgeInsets.fromLTRB(
            narrow ? Sp.s5 : Sp.s8,
            narrow ? Sp.s5 : Sp.s8,
            narrow ? Sp.s5 : Sp.s6,
            narrow ? Sp.s4 : Sp.s5,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AnimatedSwitcher(
                duration: Motion.of(context, Motion.base),
                layoutBuilder: (current, previous) => Stack(
                  alignment: Alignment.topLeft,
                  children: [...previous, ?current],
                ),
                child: narrow
                    ? KeyedSubtree(key: ValueKey(_i), child: text)
                    : Row(
                        key: ValueKey(_i),
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(flex: 6, child: text),
                          const SizedBox(width: Sp.s8),
                          Expanded(
                            flex: 4,
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxHeight: 210),
                              child: visual,
                            ),
                          ),
                        ],
                      ),
              ),
              const SizedBox(height: Sp.s4),
              Row(
                children: [
                  for (var k = 0; k < widget.slides.length; k++)
                    _Dot(
                      active: k == _i,
                      label: 'Slide ${k + 1}: ${widget.slides[k].eyebrow}',
                      onTap: () => _go(k),
                    ),
                  const Spacer(),
                  LumenIconButton(
                    icon: LucideIcons.chevronLeft,
                    tooltip: 'Previous',
                    onPressed: () => _go(_i - 1),
                  ),
                  const SizedBox(width: Sp.s1),
                  LumenIconButton(
                    icon: LucideIcons.chevronRight,
                    tooltip: 'Next',
                    onPressed: () => _go(_i + 1),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SlideText extends StatelessWidget {
  const _SlideText({required this.slide, required this.narrow});

  final HeroSlide slide;
  final bool narrow;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (slide.ai) ...[
              const AiGlyph(size: 13),
              const SizedBox(width: Sp.s1_5),
            ],
            Text(
              slide.eyebrow.toUpperCase(),
              style: LumenType.micro().copyWith(color: t.textTertiary),
            ),
          ],
        ),
        const SizedBox(height: Sp.s3),
        Text(
          slide.headline,
          style: (narrow ? LumenType.display(touch: true) : LumenType.display())
              .copyWith(color: t.textPrimary),
        ),
        const SizedBox(height: Sp.s3),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Text(
            slide.body,
            style: LumenType.body(touch: true).copyWith(color: t.textSecondary),
          ),
        ),
        const SizedBox(height: Sp.s5),
        LumenButton(
          label: slide.action,
          kind: ButtonKind.primary,
          height: 38,
          icon: const Icon(LucideIcons.arrowRight),
          onPressed: slide.onAction,
        ),
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.active, required this.label, required this.onTap});

  final bool active;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Pressable(
      onTap: onTap,
      semanticLabel: label,
      radius: Rad.pill,
      builder: (context, _) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 8),
        child: AnimatedContainer(
          duration: Motion.fast,
          width: active ? 22 : 7,
          height: 7,
          decoration: BoxDecoration(
            color: active ? t.accent : t.lineStrong,
            borderRadius: BorderRadius.circular(Rad.pill),
          ),
        ),
      ),
    );
  }
}
