import 'package:flutter/material.dart';

import 'package:lumen/design/tokens.dart';
import 'package:lumen/design/type.dart';

/// Segmented control: surface2 track, selected segment surface3 (DESIGN.md §4.13).
class Segmented<T> extends StatelessWidget {
  const Segmented({super.key, required this.value, required this.options, required this.onChanged, this.height = 26});

  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;
  final double height;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      height: height,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(color: t.surface2, borderRadius: BorderRadius.circular(Rad.sm)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        for (final e in options.entries)
          Semantics(
            button: true,
            selected: e.key == value,
            label: e.value,
            child: GestureDetector(
              onTap: () => onChanged(e.key),
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: AnimatedContainer(
                  duration: Motion.fast,
                  padding: const EdgeInsets.symmetric(horizontal: Sp.s2),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: e.key == value ? t.surface3 : Colors.transparent,
                    borderRadius: BorderRadius.circular(Rad.sm - 2),
                  ),
                  child: Text(
                    e.value,
                    style: LumenType.label().copyWith(color: e.key == value ? t.textPrimary : t.textSecondary),
                  ),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}
