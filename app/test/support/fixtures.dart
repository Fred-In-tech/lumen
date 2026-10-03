import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Encoded test photos built in memory (no downloads).
abstract final class Fixtures {
  static img.Image gradient(int w, int h, {int seed = 0}) {
    final im = img.Image(width: w, height: h);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        im.setPixelRgb(x, y, (x * 255 ~/ w + seed) % 256, y * 255 ~/ h, (128 + seed) % 256);
      }
    }
    return im;
  }

  static Uint8List jpeg({int w = 64, int h = 48, int seed = 0}) =>
      Uint8List.fromList(img.encodeJpg(gradient(w, h, seed: seed), quality: 92));

  static Uint8List png({int w = 64, int h = 48, int seed = 0}) => Uint8List.fromList(img.encodePng(gradient(w, h, seed: seed)));
}
