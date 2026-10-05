import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/app/providers.dart';
import 'package:lumen/design/tokens.dart';
import 'package:lumen/design/type.dart';
import 'package:lumen/widgets/thumb_image.dart';

/// Horizontal strip of the photos opened from the library (DESIGN.md §4.9).
class Filmstrip extends ConsumerWidget {
  const Filmstrip({
    super.key,
    required this.assetIds,
    required this.current,
    required this.onOpen,
  });

  final List<String> assetIds;
  final String current;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final entries = {
      for (final e
          in ref.watch(libraryProvider).value ?? const <CatalogEntry>[])
        e.assetId: e,
    };
    final ids = [
      for (final id in assetIds)
        if (entries.containsKey(id)) id,
    ];
    return SizedBox(
      height: Layout.filmstrip,
      child: Row(
        children: [
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(
                horizontal: Sp.s3,
                vertical: Sp.s2,
              ),
              itemCount: ids.length,
              separatorBuilder: (_, _) => const SizedBox(width: Sp.s1),
              itemBuilder: (context, i) {
                final e = entries[ids[i]]!;
                final isCurrent = e.assetId == current;
                final aspect = e.height == 0
                    ? 1.0
                    : (e.width / e.height).clamp(0.75, 1.5);
                return Semantics(
                  button: true,
                  selected: isCurrent,
                  label: e.fileName,
                  child: GestureDetector(
                    onTap: () => onOpen(e.assetId),
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: AnimatedOpacity(
                        duration: Motion.fast,
                        opacity: isCurrent ? 1 : 0.72,
                        child: Container(
                          width: 64 * aspect,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(Rad.sm + 2),
                            border: Border.all(
                              color: isCurrent ? t.accent : Colors.transparent,
                              width: 2,
                            ),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(Rad.sm),
                            child: ThumbImage(entry: e),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: Sp.s4),
            child: Text(
              '${ids.indexOf(current) + 1} of ${ids.length}',
              style: LumenType.value().copyWith(color: t.textTertiary),
            ),
          ),
        ],
      ),
    );
  }
}
