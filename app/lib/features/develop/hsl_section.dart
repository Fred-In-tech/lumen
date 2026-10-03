import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/design/tokens.dart';
import 'package:lumen/design/type.dart';
import 'package:lumen/features/develop/param_slider.dart';
import 'package:lumen/features/editor/editor_controller.dart';

/// 8 color dots + Hue/Sat/Lum sliders for the selected band (DESIGN.md §4.5).
class HslSection extends ConsumerStatefulWidget {
  const HslSection({super.key, required this.assetId, this.touch = false});

  final String assetId;
  final bool touch;

  @override
  ConsumerState<HslSection> createState() => _HslSectionState();
}

class _HslSectionState extends ConsumerState<HslSection> {
  HslBand _band = HslBand.orange;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final s = ref.watch(editorProvider(widget.assetId).select((v) => v.value?.settings));
    final dot = widget.touch ? 28.0 : 20.0;
    String cap(String x) => x[0].toUpperCase() + x.substring(1);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        for (final band in HslBand.values)
          Semantics(
            button: true,
            selected: band == _band,
            label: '${cap(band.name)} band',
            child: GestureDetector(
              onTap: () => setState(() => _band = band),
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: SizedBox(
                  width: dot + 8,
                  height: dot + 12,
                  child: Stack(alignment: Alignment.topCenter, children: [
                    AnimatedContainer(
                      duration: Motion.fast,
                      width: dot + 6,
                      height: dot + 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: band == _band ? t.textPrimary : Colors.transparent, width: 2),
                      ),
                      alignment: Alignment.center,
                      child: Container(
                        width: dot,
                        height: dot,
                        decoration: BoxDecoration(color: kHslBandColors[band.index], shape: BoxShape.circle),
                      ),
                    ),
                    if (s != null &&
                        HslChannel.values.any((c) => s.value(P.hsl(band, c)) != 0))
                      Positioned(
                        bottom: 0,
                        child: Container(width: 4, height: 4, decoration: BoxDecoration(color: t.accent, shape: BoxShape.circle)),
                      ),
                  ]),
                ),
              ),
            ),
          ),
      ]),
      Padding(
        padding: const EdgeInsets.only(top: Sp.s1, bottom: Sp.s1),
        child: Text(cap(_band.name), textAlign: TextAlign.center, style: LumenType.caption().copyWith(color: t.textSecondary)),
      ),
      for (final ch in HslChannel.values)
        ParamSlider(
          assetId: widget.assetId,
          param: P.hsl(_band, ch),
          label: switch (ch) {
            HslChannel.hue => 'Hue',
            HslChannel.sat => 'Saturation',
            HslChannel.lum => 'Luminance',
          },
          touch: widget.touch,
        ),
    ]);
  }
}
