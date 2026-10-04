import 'dart:typed_data';

import 'package:lumen_core/lumen_core.dart';
import 'package:test/test.dart';

import 'synthetic_images.dart';

/// A 3 px diagonal scratch across the whole image.
Uint8List scratch(int w, int h) {
  final m = Uint8List(w * h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final d = (x - 0.8 * y - 10).abs();
      if (d < 1.6) m[y * w + x] = 255;
    }
  }
  return m;
}

void main() {
  group('teleaInpaint', () {
    test('thin scratch on texture: low error, far better than a mean fill', () {
      final gt = grainTexture(128, 128, grain: 2);
      final hole = scratch(128, 128);
      final src = withObject(gt, hole, 255);
      final out = teleaInpaint(src, hole);
      final err = holeMae(out, gt, hole);
      expect(err, lessThan(4));
      expect(err, lessThan(0.2 * holeMae(meanFill(src, hole), gt, hole)));
    });

    test('reproduces a linear ramp across a thin gap', () {
      final gt = gradientImage(64, 64);
      final hole = rectHole(64, 64, 30, 0, 3, 64);
      final out = teleaInpaint(withObject(gt, hole), hole);
      expect(holeMae(out, gt, hole), lessThan(1));
    });

    test('keeps known pixels and is deterministic', () {
      final gt = grainTexture(64, 64);
      final hole = discHole(64, 64, 20, 30, 5);
      final src = withObject(gt, hole, 0);
      final a = teleaInpaint(src, hole);
      final b = teleaInpaint(src, hole);
      expect(a.data, b.data);
      for (var i = 0; i < hole.length; i++) {
        if (hole[i] == 0) expect(a.data[i * 3 + 1], src.data[i * 3 + 1]);
      }
    });

    test('handles a hole on the image border', () {
      final gt = gradientImage(32, 32);
      final hole = rectHole(32, 32, 0, 0, 4, 32);
      final out = teleaInpaint(withObject(gt, hole), hole);
      expect(holeMae(out, gt, hole), lessThan(6));
    });
  });
}
