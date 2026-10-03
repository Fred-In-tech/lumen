import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:lumen/design/tokens.dart';
import 'package:lumen/design/type.dart';
import 'package:lumen/features/editor/editor_controller.dart';

/// Shows the rendered photo with zoom/pan, hold-to-compare and split wipe.
///
/// [after] is the live rendered frame; [before] the unedited preview.
class PhotoCanvas extends StatefulWidget {
  const PhotoCanvas({
    super.key,
    required this.after,
    required this.before,
    required this.compare,
    required this.showingBefore,
    required this.onHoldBefore,
    this.padding = Sp.s6,
    this.overlay,
  });

  final ValueListenable<ui.Image?> after;
  final ui.Image? before;
  final CompareMode compare;
  final bool showingBefore;
  final ValueChanged<bool> onHoldBefore;
  final double padding;

  /// Drawn on top of the photo in photo coordinates (e.g. the crop frame).
  final Widget? overlay;

  @override
  State<PhotoCanvas> createState() => _PhotoCanvasState();
}

class _PhotoCanvasState extends State<PhotoCanvas> {
  final TransformationController _zoom = TransformationController();
  double _split = 0.5;

  @override
  void dispose() {
    _zoom.dispose();
    super.dispose();
  }

  // RawImage disposes the image it is given, so it always gets its own clone.
  Widget _image(ui.Image img) => RawImage(
    image: img.clone(),
    fit: BoxFit.contain,
    filterQuality: FilterQuality.medium,
  );

  Widget _chip(String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: Sp.s2, vertical: 3),
    decoration: BoxDecoration(
      color: const Color(0x99000000),
      borderRadius: BorderRadius.circular(Rad.pill),
    ),
    child: Text(text, style: LumenType.micro().copyWith(color: Colors.white)),
  );

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.all(widget.padding),
      child: ValueListenableBuilder<ui.Image?>(
        valueListenable: widget.after,
        builder: (context, after, _) {
          final shown = after ?? widget.before;
          if (shown == null) return const Center(child: SizedBox.shrink());
          final aspect = shown.width / shown.height;
          final before = widget.before;
          Widget content;
          if (widget.compare == CompareMode.sideBySide &&
              before != null &&
              after != null) {
            content = Row(
              children: [
                Expanded(
                  child: Stack(
                    children: [
                      Center(child: _image(before)),
                      Positioned(top: 8, left: 8, child: _chip('BEFORE')),
                    ],
                  ),
                ),
                const SizedBox(width: 2),
                Expanded(
                  child: Stack(
                    children: [
                      Center(child: _image(after)),
                      Positioned(top: 8, right: 8, child: _chip('AFTER')),
                    ],
                  ),
                ),
              ],
            );
            return content;
          }
          final showBefore = widget.showingBefore && before != null;
          content = Center(
            child: AspectRatio(
              aspectRatio: aspect,
              child: LayoutBuilder(
                builder: (context, c) {
                  final layers = <Widget>[
                    Positioned.fill(child: _image(showBefore ? before : shown)),
                  ];
                  if (widget.compare == CompareMode.split &&
                      before != null &&
                      !showBefore) {
                    layers.add(
                      Positioned.fill(
                        child: ClipRect(
                          clipper: _LeftClipper(_split),
                          child: _image(before),
                        ),
                      ),
                    );
                    layers.add(
                      Positioned(
                        left: c.maxWidth * _split - 16,
                        top: 0,
                        bottom: 0,
                        child: GestureDetector(
                          onHorizontalDragUpdate: (d) => setState(
                            () => _split = (_split + d.delta.dx / c.maxWidth)
                                .clamp(0.0, 1.0),
                          ),
                          child: MouseRegion(
                            cursor: SystemMouseCursors.resizeLeftRight,
                            child: SizedBox(
                              width: 32,
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  Container(width: 1, color: Colors.white),
                                  Container(
                                    width: 28,
                                    height: 28,
                                    decoration: BoxDecoration(
                                      color: context.tokens.surface3,
                                      shape: BoxShape.circle,
                                      boxShadow: Elevation.e2,
                                    ),
                                    child: Icon(
                                      LucideIcons.chevronsLeftRight,
                                      size: 16,
                                      color: context.tokens.textPrimary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                    layers.add(
                      Positioned(top: 8, left: 8, child: _chip('BEFORE')),
                    );
                    layers.add(
                      Positioned(top: 8, right: 8, child: _chip('AFTER')),
                    );
                  }
                  if (showBefore) {
                    layers.add(
                      Positioned(
                        top: 8,
                        left: 0,
                        right: 0,
                        child: Center(child: _chip('BEFORE')),
                      ),
                    );
                  }
                  if (widget.overlay != null) {
                    layers.add(Positioned.fill(child: widget.overlay!));
                  }
                  return Stack(children: layers);
                },
              ),
            ),
          );
          return GestureDetector(
            onLongPressStart: (_) => widget.onHoldBefore(true),
            onLongPressEnd: (_) => widget.onHoldBefore(false),
            child: InteractiveViewer(
              transformationController: _zoom,
              minScale: 1,
              maxScale: 8,
              panEnabled: widget.overlay == null,
              scaleEnabled: widget.overlay == null,
              child: content,
            ),
          );
        },
      ),
    );
  }
}

class _LeftClipper extends CustomClipper<Rect> {
  _LeftClipper(this.frac);
  final double frac;

  @override
  Rect getClip(Size size) =>
      Rect.fromLTWH(0, 0, size.width * frac, size.height);

  @override
  bool shouldReclip(_LeftClipper old) => old.frac != frac;
}
