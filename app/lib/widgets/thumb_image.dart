import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/design/tokens.dart';
import 'package:lumen/features/library/library_tile.dart';

/// Catalog thumbnail that keeps the previous image while a new version loads.
class ThumbImage extends ConsumerStatefulWidget {
  const ThumbImage({super.key, required this.entry, this.fit = BoxFit.cover});

  final CatalogEntry entry;
  final BoxFit fit;

  @override
  ConsumerState<ThumbImage> createState() => _ThumbImageState();
}

class _ThumbImageState extends ConsumerState<ThumbImage> {
  Uint8List? _last;

  @override
  Widget build(BuildContext context) {
    final v = ref
        .watch(thumbProvider((widget.entry.assetId, widget.entry.thumbVersion)))
        .value;
    if (v != null) _last = v;
    final bytes = v ?? _last;
    if (bytes == null) return ColoredBox(color: context.tokens.surface2);
    return Image.memory(
      bytes,
      fit: widget.fit,
      gaplessPlayback: true,
      filterQuality: FilterQuality.medium,
    );
  }
}
