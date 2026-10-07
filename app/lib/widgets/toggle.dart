import 'package:flutter/material.dart';

import 'package:lumen/design/tokens.dart';
import 'package:lumen/widgets/buttons.dart';

/// On/off switch in the Studio look (DESIGN.md §1.3: no default Switch).
class LumenToggle extends StatelessWidget {
  const LumenToggle({
    super.key,
    required this.value,
    required this.onChanged,
    required this.label,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;

  /// Read by screen readers.
  final String label;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Semantics(
      toggled: value,
      label: label,
      child: Pressable(
        onTap: onChanged == null ? null : () => onChanged!(!value),
        radius: Rad.pill,
        scaleOnPress: false,
        builder: (context, _) => AnimatedContainer(
          duration: Motion.fast,
          width: 34,
          height: 20,
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: value ? t.accent : t.surface3,
            borderRadius: BorderRadius.circular(Rad.pill),
          ),
          child: AnimatedAlign(
            duration: Motion.fast,
            curve: Motion.standard,
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: t.surface1,
                shape: BoxShape.circle,
                boxShadow: Elevation.e1,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
