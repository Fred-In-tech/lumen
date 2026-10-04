import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/design/tokens.dart';
import 'package:lumen/design/type.dart';
import 'package:lumen/features/cull/cull_providers.dart';

/// Short text for screen readers and tooltips.
String cullDescription(CatalogEntry e, CullSuggestion? pending) => [
  if (e.flag == PhotoFlag.pick) 'picked',
  if (e.flag == PhotoFlag.reject) 'rejected',
  if (e.rating > 0) '${e.rating} ${e.rating == 1 ? 'star' : 'stars'}',
  if (pending?.decision == CullDecision.pick) 'suggested pick',
  if (pending?.decision == CullDecision.reject) 'suggested reject',
  for (final r in pending?.reasons ?? const <CullReason>{}) r.label,
].join(', ');

/// Flag, rating and pending Smart Cull suggestion of one tile.
class CullBadges extends ConsumerWidget {
  const CullBadges({super.key, required this.entry});

  final CatalogEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final pending = ref.watch(
      cullRecordsProvider.select((v) => v.value?[entry.assetId]?.pending),
    );
    final e = entry;
    final reasons = pending?.reasons ?? const <CullReason>{};
    final chips = <Widget>[
      if (e.flag == PhotoFlag.pick)
        _Dot(icon: LucideIcons.flag, color: t.success, filled: true),
      if (e.flag == PhotoFlag.reject)
        _Dot(icon: LucideIcons.circleX, color: t.danger, filled: true),
      if (pending?.decision == CullDecision.pick && e.flag != PhotoFlag.pick)
        _Dot(icon: LucideIcons.thumbsUp, color: t.success),
      if (pending?.decision == CullDecision.reject &&
          e.flag != PhotoFlag.reject)
        _Dot(icon: LucideIcons.thumbsDown, color: t.warning),
      if (reasons.contains(CullReason.eyesClosed))
        _Dot(icon: LucideIcons.eyeOff, color: t.warning),
      if (reasons.contains(CullReason.blurryFace) ||
          reasons.contains(CullReason.blurry))
        _Dot(icon: LucideIcons.focus, color: t.warning),
      if (pending != null && pending.inCluster)
        _Count(count: pending.clusterSize, color: t.textPrimary),
    ];
    return Stack(
      fit: StackFit.expand,
      children: [
        if (chips.isNotEmpty)
          Positioned(
            right: 6,
            top: 6,
            child: Tooltip(
              message: cullDescription(e, pending),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final c in chips)
                    Padding(padding: const EdgeInsets.only(left: 3), child: c),
                ],
              ),
            ),
          ),
        if (e.rating > 0)
          Positioned(
            left: 6,
            bottom: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: const Color(0x8C000000),
                borderRadius: BorderRadius.circular(Rad.pill),
              ),
              child: Text(
                '★' * e.rating,
                style: LumenType.micro().copyWith(color: t.warning),
              ),
            ),
          ),
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.icon, required this.color, this.filled = false});

  final IconData icon;
  final Color color;
  final bool filled;

  @override
  Widget build(BuildContext context) => Container(
    width: 22,
    height: 22,
    decoration: BoxDecoration(
      color: filled ? color : const Color(0x8C000000),
      shape: BoxShape.circle,
    ),
    alignment: Alignment.center,
    child: Icon(
      icon,
      size: 12,
      color: filled ? context.tokens.textOnAccent : color,
    ),
  );
}

class _Count extends StatelessWidget {
  const _Count({required this.count, required this.color});

  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    height: 22,
    padding: const EdgeInsets.symmetric(horizontal: 6),
    decoration: BoxDecoration(
      color: const Color(0x8C000000),
      borderRadius: BorderRadius.circular(Rad.pill),
    ),
    alignment: Alignment.center,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(LucideIcons.layers, size: 11, color: color),
        const SizedBox(width: 3),
        Text('$count', style: LumenType.micro().copyWith(color: color)),
      ],
    ),
  );
}
