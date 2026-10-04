import 'package:lumen_core/lumen_core.dart';
import 'package:test/test.dart';

import '../warp/support/warp_faces.dart';

/// Left half dark, right half bright, 200×150.
RgbaBuffer _edge() {
  final b = RgbaBuffer(200, 150);
  for (var y = 0; y < 150; y++) {
    for (var x = 0; x < 200; x++) {
      final v = x < 100 ? 40 : 200;
      b.setPixel(x, y, v, v, v);
    }
  }
  return b;
}

int _firstBright(RgbaBuffer b, int y) {
  for (var x = 0; x < b.width; x++) {
    if (b.r(x, y) > 120) return x;
  }
  return b.width;
}

void main() {
  final edge = _edge();

  test('an identity warp is bit-exact', () {
    final plain = renderReference(edge, DevelopSettings.defaults);
    final warped = renderReference(
      edge,
      DevelopSettings.defaults,
      warp: WarpField.identity(),
    );
    expect(warped.data, plain.data);
  });

  test('liquify push moves the edge along the stroke, only near it', () {
    final s = DevelopSettings.defaults.copyWith(
      liquify: const [
        LiquifyStroke(
          tool: LiquifyTool.push,
          points: [(0.45, 0.5), (0.6, 0.5)],
          radius: 0.15,
          strength: 1,
        ),
      ],
    );
    final out = renderReference(edge, s);
    // The dark side is pushed right at the stroke row; far rows unchanged.
    expect(_firstBright(out, 75), greaterThan(_firstBright(edge, 75) + 10));
    expect(_firstBright(out, 3), _firstBright(edge, 3));
  });

  test('face reshape changes pixels inside the feather only, exactly', () {
    final img = RgbaBuffer(400, 300);
    for (var y = 0; y < 300; y++) {
      for (var x = 0; x < 400; x++) {
        img.setPixel(x, y, (x * 7) % 256, (y * 5) % 256, ((x + y) * 3) % 256);
      }
    }
    final faces = synthAnalysis(400, 300, [face('a', 200, 130, 60)]);
    final s = DevelopSettings.defaults.copyWith(
      portrait: shapes({PortraitIds.faceWidth: 100, PortraitIds.eyeSize: 80}),
    );
    final plain = renderReference(img, DevelopSettings.defaults);
    final out = renderReference(img, s, faces: faces);
    var changedInside = 0;
    for (final (x, y) in [(5, 5), (395, 295), (10, 150), (390, 10)]) {
      for (var c = 0; c < 3; c++) {
        expect(
          out.data[img.offset(x, y) + c],
          plain.data[img.offset(x, y) + c],
        );
      }
    }
    for (var y = 100; y < 220; y++) {
      for (var x = 120; x < 280; x++) {
        if (out.r(x, y) != plain.r(x, y)) changedInside++;
      }
    }
    expect(changedInside, greaterThan(500));
    // Without the analysis, shape sliders cannot warp anything.
    expect(renderReference(img, s).data, plain.data);
  });

  test('masks are sampled at the warped uv', () {
    final flat = RgbaBuffer.filled(200, 200, 100, 100, 100);
    const mask = LocalMask(
      id: 'r',
      name: 'r',
      kind: MaskKind.radial,
      shape: {'cx': 0.5, 'cy': 0.5, 'rx': 0.1, 'ry': 0.1, 'feather': 0.0},
      adjustments: {P.exposure: 1},
    );
    int bright(RgbaBuffer b) {
      var n = 0;
      for (var i = 0; i < b.data.length; i += 4) {
        if (b.data[i] > 130) n++;
      }
      return n;
    }

    final base = DevelopSettings.defaults.copyWith(masks: const [mask]);
    final bloated = base.copyWith(
      liquify: const [
        LiquifyStroke(
          tool: LiquifyTool.bloat,
          points: [(0.5, 0.5), (0.5, 0.5), (0.5, 0.5)],
          radius: 0.25,
          strength: 1,
        ),
      ],
    );
    expect(
      bright(renderReference(flat, bloated)),
      greaterThan(bright(renderReference(flat, base)) * 1.08),
    );
  });
}
