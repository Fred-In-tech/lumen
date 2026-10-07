import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:lumen/design/tokens.dart';
import 'package:lumen/design/type.dart';
import 'package:lumen/features/looks/look.dart';
import 'package:lumen/features/looks/look_previews.dart';

/// A look rendered on a real photo. Press and hold to see the photo
/// without it; hovering says so. While the render runs the unedited photo
/// shows, softened (no spinner: nothing animates while waiting).
///
/// [photo]: the photo in context; null uses the bundled sample that suits
/// the look. [waiting]: the photo in context is still loading (show
/// nothing rather than flash a sample first).
class LookSample extends ConsumerStatefulWidget {
  const LookSample({
    super.key,
    required this.look,
    this.photo,
    this.waiting = false,
    this.compare = true,
  });

  final Look look;
  final LookPreviewPhoto? photo;
  final bool waiting;

  /// Offer hold-to-compare (off on the tiny editor tiles).
  final bool compare;

  @override
  ConsumerState<LookSample> createState() => _LookSampleState();
}

class _LookSampleState extends ConsumerState<LookSample> {
  Future<(Uint8List?, Uint8List?)>? _images;
  String? _key;
  bool _holding = false;
  bool _hover = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _refresh();
  }

  @override
  void didUpdateWidget(LookSample old) {
    super.didUpdateWidget(old);
    _refresh();
  }

  void _refresh() {
    if (widget.waiting) {
      _images = null;
      _key = null;
      return;
    }
    final photo = widget.photo;
    final key =
        '${widget.look.id}|${photo?.id ?? 'sample'}|'
        '${LookPreviewService.settingsFor(widget.look)?.hashCode}';
    if (key == _key) return;
    _key = key;
    final service = ref.read(lookPreviewServiceProvider);
    final look = widget.look;
    _images = () async {
      final p = photo ?? await loadSamplePhoto(sampleFor(look));
      final before = service.before(p);
      final after = service.preview(look, p);
      return (await before, await after);
    }();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Listener(
        onPointerDown: widget.compare
            ? (_) => setState(() => _holding = true)
            : null,
        onPointerUp: (_) => setState(() => _holding = false),
        onPointerCancel: (_) => setState(() => _holding = false),
        child: FutureBuilder<(Uint8List?, Uint8List?)>(
          future: _images,
          builder: (context, snap) {
            final (before, after) = snap.data ?? (null, null);
            final shown = _holding ? before : (after ?? before);
            return Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(color: t.surface2),
                if (shown != null)
                  AnimatedOpacity(
                    duration: Motion.fast,
                    opacity: after == null && !_holding ? 0.55 : 1,
                    child: Image.memory(
                      shown,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                      semanticLabel: _holding
                          ? 'The photo without ${widget.look.name}'
                          : '${widget.look.name} on a sample photo',
                    ),
                  ),
                if (widget.compare && (_hover || _holding) && after != null)
                  Positioned(
                    left: Sp.s2,
                    bottom: Sp.s2,
                    child: _Hint(
                      label: _holding ? 'Before' : 'Hold to compare',
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    height: 20,
    padding: const EdgeInsets.symmetric(horizontal: Sp.s2),
    decoration: BoxDecoration(
      color: const Color(0xB3161616),
      borderRadius: BorderRadius.circular(Rad.pill),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          LucideIcons.splitSquareHorizontal,
          size: 10,
          color: Colors.white,
        ),
        const SizedBox(width: 4),
        Text(label, style: LumenType.caption().copyWith(color: Colors.white)),
      ],
    ),
  );
}
