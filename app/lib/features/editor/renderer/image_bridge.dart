import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:lumen_core/lumen_core.dart';

/// RGBA bytes → GPU image. The caller owns the result.
Future<ui.Image> imageFromRgba(RgbaBuffer buf) {
  final c = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    buf.data,
    buf.width,
    buf.height,
    ui.PixelFormat.rgba8888,
    c.complete,
  );
  return c.future;
}

/// GPU image → RGBA bytes (straight alpha).
Future<RgbaBuffer> rgbaFromImage(ui.Image img) async {
  final data = await img.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
  if (data == null) throw StateError('Image readback failed');
  return RgbaBuffer(
    img.width,
    img.height,
    Uint8List.view(data.buffer, data.offsetInBytes, data.lengthInBytes),
  );
}

/// Draws [img] scaled so its long edge is [longEdge] (never upscales).
Future<ui.Image> resizeImage(ui.Image img, int longEdge) async {
  final scale = longEdge / (img.width > img.height ? img.width : img.height);
  if (scale >= 1) return img.clone();
  final w = (img.width * scale).round().clamp(1, longEdge),
      h = (img.height * scale).round().clamp(1, longEdge);
  final rec = ui.PictureRecorder();
  ui.Canvas(rec).drawImageRect(
    img,
    ui.Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
    ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
    ui.Paint()..filterQuality = ui.FilterQuality.medium,
  );
  final pic = rec.endRecording();
  final out = await pic.toImage(w, h);
  pic.dispose();
  return out;
}
