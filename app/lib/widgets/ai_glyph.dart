import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:lumen/design/tokens.dart';

/// The sparkles glyph filled with the AI gradient: the only place sparkles appear.
class AiGlyph extends StatelessWidget {
  const AiGlyph({super.key, this.size = 16, this.neutral = false});

  final double size;

  /// Neutral rendering for the offline statistical auto (not a model decision).
  final bool neutral;

  @override
  Widget build(BuildContext context) {
    final icon = Icon(
      LucideIcons.sparkles,
      size: size,
      color: neutral
          ? (IconTheme.of(context).color ?? context.tokens.textPrimary)
          : Colors.white,
    );
    if (neutral) return icon;
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (rect) => LumenTokens.aiGradient.createShader(rect),
      child: icon,
    );
  }
}
