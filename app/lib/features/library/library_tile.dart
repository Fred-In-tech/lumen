import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/app/providers.dart';
import 'package:lumen/design/tokens.dart';
import 'package:lumen/design/type.dart';
import 'package:lumen/widgets/ai_glyph.dart';

/// Thumbnail bytes for (assetId, thumbVersion); refetched when the version bumps.
final thumbProvider = FutureProvider.autoDispose
    .family<Uint8List?, (String, int)>(
      (ref, key) => ref.watch(catalogRepositoryProvider).readThumb(key.$1),
    );

/// Asset ids currently being auto-edited (shimmer + "Editing…" pill).
class BusyAssetsNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};

  void add(Iterable<String> ids) =>
      state = Set.unmodifiable({...state, ...ids});
  void remove(String id) => state = Set.unmodifiable({...state}..remove(id));
}

final busyAssetsProvider = NotifierProvider<BusyAssetsNotifier, Set<String>>(
  BusyAssetsNotifier.new,
);

class LibraryTile extends ConsumerStatefulWidget {
  const LibraryTile({
    super.key,
    required this.entry,
    required this.selected,
    required this.selectionMode,
    required this.onOpen,
    required this.onToggle,
    required this.onRange,
  });

  final CatalogEntry entry;
  final bool selected;
  final bool selectionMode;
  final VoidCallback onOpen;
  final VoidCallback onToggle;
  final VoidCallback onRange;

  @override
  ConsumerState<LibraryTile> createState() => _LibraryTileState();
}

class _LibraryTileState extends ConsumerState<LibraryTile> {
  bool _hover = false;

  /// Last shown thumbnail, kept while a newer version loads (no blank flash).
  Uint8List? _lastThumb;

  void _handleTap() {
    final keys = HardwareKeyboard.instance;
    if (keys.isShiftPressed) return widget.onRange();
    if (keys.isMetaPressed || keys.isControlPressed || widget.selectionMode) {
      return widget.onToggle();
    }
    widget.onOpen();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final e = widget.entry;
    final thumb = ref.watch(thumbProvider((e.assetId, e.thumbVersion)));
    final busy = ref.watch(busyAssetsProvider).contains(e.assetId);
    return Semantics(
      button: true,
      selected: widget.selected,
      label: '${e.fileName}${e.hasEdits ? ', edited' : ''}',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: _handleTap,
          onLongPress: widget.onToggle,
          child: AnimatedScale(
            scale: widget.selected ? 0.96 : 1,
            duration: Motion.fast,
            curve: Motion.standard,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(Rad.tile),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(color: t.surface2),
                  Builder(
                    builder: (context) {
                      final bytes = thumb.value ?? _lastThumb;
                      if (thumb.value != null) _lastThumb = thumb.value;
                      if (bytes != null) {
                        return Image.memory(
                          bytes,
                          fit: BoxFit.cover,
                          gaplessPlayback: true,
                          filterQuality: FilterQuality.medium,
                        );
                      }
                      if (thumb.hasError) {
                        return Center(
                          child: Icon(
                            LucideIcons.triangleAlert,
                            color: t.danger,
                          ),
                        );
                      }
                      return thumb.isLoading
                          ? const SizedBox.shrink()
                          : Center(
                              child: Icon(
                                LucideIcons.image,
                                color: t.textDisabled,
                              ),
                            );
                    },
                  ),
                  if (busy) const _Shimmer(),
                  if (busy)
                    const Positioned(left: 8, top: 8, child: _EditingPill()),
                  if (!busy && (e.hasEdits || e.aiEngine != null))
                    Positioned(right: 6, bottom: 6, child: _Badge(entry: e)),
                  if (widget.selected)
                    DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(color: t.accent, width: 2),
                        borderRadius: BorderRadius.circular(Rad.tile),
                      ),
                    ),
                  if (widget.selected || _hover || widget.selectionMode)
                    Positioned(
                      left: 6,
                      top: 6,
                      child: _Check(
                        selected: widget.selected,
                        onTap: widget.onToggle,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.entry});
  final CatalogEntry entry;

  @override
  Widget build(BuildContext context) {
    final ai = entry.aiEngine != null;
    return Container(
      width: 22,
      height: 22,
      decoration: const BoxDecoration(
        color: Color(0x8C000000),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: ai
          ? AiGlyph(size: 12, neutral: entry.aiEngine == 'local')
          : Icon(
              LucideIcons.slidersHorizontal,
              size: 12,
              color: context.tokens.textPrimary,
            ),
    );
  }
}

class _Check extends StatelessWidget {
  const _Check({required this.selected, required this.onTap});
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: Motion.fast,
        width: 20,
        height: 20,
        decoration: BoxDecoration(
          color: selected ? t.accent : const Color(0x8C000000),
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? t.accent : Colors.white70,
            width: 1.5,
          ),
        ),
        child: selected
            ? Icon(LucideIcons.check, size: 12, color: t.textOnAccent)
            : null,
      ),
    );
  }
}

class _EditingPill extends StatelessWidget {
  const _EditingPill();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Sp.s2, vertical: Sp.s0_5),
      decoration: BoxDecoration(
        color: t.surface3,
        borderRadius: BorderRadius.circular(Rad.pill),
        boxShadow: Elevation.e2,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const AiGlyph(size: 11),
          const SizedBox(width: 4),
          Text(
            'Editing…',
            style: LumenType.caption().copyWith(color: t.textPrimary),
          ),
        ],
      ),
    );
  }
}

class _Shimmer extends StatefulWidget {
  const _Shimmer();

  @override
  State<_Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<_Shimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      return const SizedBox.shrink();
    }
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => Opacity(
        opacity: 0.15,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment(-2 + 4 * _c.value, -1),
              end: Alignment(-1 + 4 * _c.value, 1),
              colors: LumenTokens.aiGradient.colors,
            ),
          ),
        ),
      ),
    );
  }
}
