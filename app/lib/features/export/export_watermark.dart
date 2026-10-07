import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:lumen_core/lumen_core.dart';

/// Renders [text] in white, [heightPx] tall (cap to descender), at most
/// [maxWidth] pixels wide, and returns its coverage for `blendWatermark`.
Future<WatermarkMask> rasterizeWatermark(
  String text,
  double heightPx,
  int maxWidth,
) async {
  final builder =
      ui.ParagraphBuilder(
          ui.ParagraphStyle(fontSize: heightPx, maxLines: 1, ellipsis: '…'),
        )
        ..pushStyle(
          ui.TextStyle(
            color: const ui.Color(0xFFFFFFFF),
            fontSize: heightPx,
            fontWeight: ui.FontWeight.w500,
          ),
        )
        ..addText(text);
  final paragraph = builder.build()
    ..layout(ui.ParagraphConstraints(width: maxWidth.toDouble()));
  final w = math.max(1, math.min(maxWidth, paragraph.maxIntrinsicWidth.ceil()));
  final h = math.max(1, paragraph.height.ceil());
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawParagraph(paragraph, ui.Offset.zero);
  final picture = recorder.endRecording();
  final image = await picture.toImage(w, h);
  picture.dispose();
  paragraph.dispose();
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null) throw StateError('watermark readback failed');
    final rgba = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    final cov = Uint8List(w * h);
    for (var i = 0; i < cov.length; i++) {
      cov[i] = rgba[i * 4 + 3];
    }
    return WatermarkMask(w, h, cov);
  } finally {
    image.dispose();
  }
}
