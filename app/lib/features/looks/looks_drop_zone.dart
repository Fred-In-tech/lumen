import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/app/providers.dart';
import 'package:lumen/features/looks/look_import_flow.dart';
import 'package:lumen/features/shell/drop_claim.dart';

/// Accepts presets and LUTs dropped on a looks section: `.xmp`,
/// `.lrtemplate`, `.zip`, `.cube` (folders too). [builder] gets whether
/// files are over it, to light up the import card. Drops without look
/// files are left to the page underneath (photos still import there).
class LooksDropZone extends ConsumerStatefulWidget {
  const LooksDropZone({super.key, required this.builder});

  final Widget Function(BuildContext context, bool dragging) builder;

  @override
  ConsumerState<LooksDropZone> createState() => _LooksDropZoneState();
}

class _LooksDropZoneState extends ConsumerState<LooksDropZone> {
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    final child = widget.builder(context, _dragging);
    if (!ref.watch(platformInfoProvider).supportsDragAndDrop) return child;
    return DropTarget(
      onDragEntered: (_) => setState(() => _dragging = true),
      onDragExited: (_) => setState(() => _dragging = false),
      onDragDone: (details) async {
        setState(() => _dragging = false);
        if (details.files.any((f) => isLookFile(f.name))) DropClaim.claim();
        await importDroppedLooks(context, ref, details.files);
      },
      child: child,
    );
  }
}
