import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Encoded test photos built in memory (no downloads).
abstract final class Fixtures {
  static img.Image gradient(int w, int h, {int seed = 0}) {
    final im = img.Image(width: w, height: h);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        im.setPixelRgb(
          x,
          y,
          (x * 255 ~/ w + seed) % 256,
          y * 255 ~/ h,
          (128 + seed) % 256,
        );
      }
    }
    return im;
  }

  static Uint8List jpeg({int w = 64, int h = 48, int seed = 0}) =>
      Uint8List.fromList(
        img.encodeJpg(gradient(w, h, seed: seed), quality: 92),
      );

  static Uint8List png({int w = 64, int h = 48, int seed = 0}) =>
      Uint8List.fromList(img.encodePng(gradient(w, h, seed: seed)));

  /// The first bytes of a Canon CR3 (ISO BMFF, brand `crx `). Only the
  /// signature is real: RAW decoding is the platform's job (faked in tests).
  static Uint8List cr3({int seed = 0}) => Uint8List.fromList([
    0, 0, 0, 0x18, ...'ftypcrx '.codeUnits, 0, 0, 0, 1, //
    ...'crx isom'.codeUnits, seed,
  ]);

  /// The first bytes of a Canon CR2 (TIFF header, then `CR` 2.0).
  static Uint8List cr2({int seed = 0}) => Uint8List.fromList([
    ...tiffHeader(), ...'CR'.codeUnits, 2, 0, seed, //
  ]);

  /// A bare TIFF header (also how DNG, NEF and ARW start).
  static Uint8List tiffHeader({bool bigEndian = false}) => Uint8List.fromList(
    bigEndian
        ? [0x4D, 0x4D, 0x00, 0x2A, 0, 0, 0, 0x10]
        : [0x49, 0x49, 0x2A, 0x00, 0x10, 0, 0, 0],
  );
}
