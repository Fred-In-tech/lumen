// Generated test photos for integration tests: drawn portraits and
// synthetic scenes. Never a real person or a user's photo.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:lumen_core/lumen_core.dart';

import '../../test/ai/ondevice/synthetic_portrait.dart';

Uint8List _encode(RgbaBuffer buf, {int quality = 92}) {
  final im = img.Image.fromBytes(
    width: buf.width,
    height: buf.height,
    bytes: buf.data.buffer,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  );
  return Uint8List.fromList(
    img.encodeJpg(im.convert(numChannels: 3), quality: quality),
  );
}

/// The drawn sample portrait with a few red acne spots on the cheeks.
Uint8List samplePortraitJpeg() {
  final (buf, face) = syntheticPortrait(width: 1200, height: 900, scale: 520);
  final rnd = math.Random(7);
  for (var k = 0; k < 9; k++) {
    final side = k.isEven ? -1 : 1;
    final cx = face.cx + side * (0.14 + rnd.nextDouble() * 0.1) * face.scale;
    final cy = face.cy + (0.05 + rnd.nextDouble() * 0.12) * face.scale;
    final r = 4 + rnd.nextDouble() * 4;
    for (var y = (cy - r).floor(); y <= (cy + r).ceil(); y++) {
      for (var x = (cx - r).floor(); x <= (cx + r).ceil(); x++) {
        final d = math.sqrt(math.pow(x - cx, 2) + math.pow(y - cy, 2)) / r;
        if (d > 1) continue;
        final a = (1 - d * d) * 0.55;
        final i = (y * buf.width + x) * 4;
        buf.data[i] = (buf.data[i] * (1 - a) + 205 * a).round();
        buf.data[i + 1] = (buf.data[i + 1] * (1 - a) + 70 * a).round();
        buf.data[i + 2] = (buf.data[i + 2] * (1 - a) + 70 * a).round();
      }
    }
  }
  return _encode(buf, quality: 95);
}

/// A synthetic scene ([SceneId]) as a JPEG.
Uint8List sceneJpeg(SceneId id, {int longEdge = 1200}) =>
    _encode(SyntheticScenes.build(id, longEdge: longEdge).image);

/// A drawn group portrait with [faces] people.
Uint8List groupPortraitJpeg(int faces, {int width = 1200, int height = 800}) {
  final step = width / (faces + 1);
  final scale = math.min(step * 0.9, height * 0.5);
  final (buf, _) = syntheticGroupPortrait(
    width: width,
    height: height,
    faces: [
      for (var i = 0; i < faces; i++) (step * (i + 1), height * 0.52, scale),
    ],
  );
  return _encode(buf);
}
