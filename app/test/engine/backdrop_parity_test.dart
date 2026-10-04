import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/engine/gpu_pass.dart';
import 'package:lumen_core/lumen_core.dart';

import '../support/test_images.dart';
import 'backdrop_harness.dart';

/// GPU `backdrop.frag` vs CPU `applyBackdrop` (§6.3: max ≤ 3/255, mean ≤
/// 1/255). `--dart-define=LUMEN_PARITY_REPORT=true` logs the stats.
const _report = bool.fromEnvironment('LUMEN_PARITY_REPORT');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SwapScene s;
  late BackdropBase base;
  late RgbaBuffer photo;

  setUpAll(() {
    s = SwapScene.make();
    base = BackdropBase.build(s.image, people: s.people);
    photo = testBackdropImage(300, 160);
  });

  Future<void> check(
    String name,
    BackdropChange b, {
    BackdropBase? using,
    RgbaBuffer? src,
  }) async {
    final input = src ?? s.image;
    final a = BackdropAssets.build(using ?? base, b, image: photo);
    final cpu = applyBackdrop(input, a, b);
    final gpu = await gpuBackdrop(input, a, b);
    final d = diffStats(gpu, cpu);
    // Deep inside the subject (no match) the GPU keeps the source exactly.
    var changed = 0, inner = 0, leaked = 0;
    final scale = input.width / s.image.width;
    for (var y = 0; y < input.height; y++) {
      for (var x = 0; x < input.width; x++) {
        final o = (y * input.width + x) * 4;
        var same = true;
        for (var c = 0; c < 3; c++) {
          same = same && cpu.data[o + c] == input.data[o + c];
        }
        if (!same) changed++;
        final dx = (x + 0.5) / scale - s.cx, dy = (y + 0.5) / scale - s.cy;
        if (b.match > 0 || dx * dx + dy * dy > (s.r - 12) * (s.r - 12)) {
          continue;
        }
        inner++;
        for (var c = 0; c < 3; c++) {
          if (gpu.data[o + c] != input.data[o + c]) leaked++;
        }
      }
    }
    expect(leaked, 0, reason: '$name: subject interior changed');
    expect(changed, greaterThan(0), reason: '$name had no effect');
    expect(d.max, lessThanOrEqualTo(3), reason: name);
    expect(d.mean, lessThanOrEqualTo(1), reason: name);
    if (_report) {
      debugPrint(
        'backdrop parity $name: max ${d.max}/255, '
        'mean ${d.mean.toStringAsFixed(3)}/255, changed $changed px, '
        'interior $inner px exact',
      );
    }
  }

  const blue = 0xFF2050C0, sand = 0xFFE8D8B0;
  final cases = <String, BackdropChange>{
    'blur 50': const BackdropChange(mode: BackdropMode.blur),
    'blur 100, spill 0': const BackdropChange(
      mode: BackdropMode.blur,
      blur: 100,
      spill: 0,
    ),
    'colour, spill 0': const BackdropChange(
      mode: BackdropMode.color,
      color: blue,
      spill: 0,
    ),
    'colour, spill 100': const BackdropChange(
      mode: BackdropMode.color,
      color: blue,
      spill: 100,
    ),
    'colour, match 100': const BackdropChange(
      mode: BackdropMode.color,
      color: sand,
      match: 100,
    ),
    'gradient 0°': const BackdropChange(
      mode: BackdropMode.gradient,
      color: blue,
      color2: sand,
      angle: 0,
    ),
    'gradient 135°': const BackdropChange(
      mode: BackdropMode.gradient,
      color: blue,
      color2: sand,
      angle: 135,
    ),
    'image fill': const BackdropChange(
      mode: BackdropMode.image,
      imageRef: 'retouch/bg.png',
    ),
    'image fit (letterbox)': const BackdropChange(
      mode: BackdropMode.image,
      imageRef: 'retouch/bg.png',
      fit: BackdropFit.fit,
      color: sand,
    ),
    'image stretch, match 60': const BackdropChange(
      mode: BackdropMode.image,
      imageRef: 'retouch/bg.png',
      fit: BackdropFit.stretch,
      match: 60,
    ),
    'shift +80, feather 100': const BackdropChange(
      mode: BackdropMode.color,
      color: blue,
      edgeShift: 80,
      feather: 100,
    ),
    'shift -80, feather 0': const BackdropChange(
      mode: BackdropMode.color,
      color: blue,
      edgeShift: -80,
      feather: 0,
    ),
  };

  group('each mode', () {
    for (final e in cases.entries) {
      test(e.key, () => check(e.key, e.value));
    }
  });

  test('assets coarser than the image (export: preview-built matte)', () async {
    final low = AuxMaps.proxy(s.image, longEdge: 150);
    final coarse = BackdropBase.build(low, people: s.people);
    for (final e in cases.entries.take(4)) {
      await check('${e.key} (coarse assets)', e.value, using: coarse);
    }
  });

  test('off and image-without-ref are identity (no pass)', () async {
    for (final b in const [
      BackdropChange.none,
      BackdropChange(mode: BackdropMode.image),
    ]) {
      final a = BackdropAssets.build(base, b);
      expect(identical(applyBackdrop(s.image, a, b), s.image), isTrue);
      expect(identical(await gpuBackdrop(s.image, a, b), s.image), isTrue);
    }
  });

  test('tiles compose bit-exactly into the single pass', () async {
    const b = BackdropChange(mode: BackdropMode.blur, blur: 80, spill: 70);
    final a = BackdropAssets.build(base, b);
    final whole = await gpuBackdrop(s.image, a, b);
    final tiled = await gpuBackdrop(s.image, a, b, tileSize: 64);
    expect(diffStats(tiled, whole).max, 0);
  });

  test('no image leaks', () async {
    final before = EngineImages.live;
    const b = BackdropChange(mode: BackdropMode.color, color: blue);
    await gpuBackdrop(s.image, BackdropAssets.build(base, b), b, tileSize: 64);
    expect(EngineImages.live, before);
  });
}
