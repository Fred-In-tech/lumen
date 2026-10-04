import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/engine/gpu_pass.dart';
import 'package:lumen_core/lumen_core.dart';

import '../support/test_images.dart';
import 'retouch_harness.dart';

/// GPU `retouch.frag` vs CPU `applyRetouch` (§6.3: max ≤ 3/255, mean ≤
/// 1/255). `--dart-define=LUMEN_PARITY_REPORT=true` logs the stats.
const _report = bool.fromEnvironment('LUMEN_PARITY_REPORT');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SynthPortrait p;
  late RetouchMaps maps;
  late RetouchMaps lowMaps; // maps coarser than the image (interpolated)

  setUpAll(() {
    final one = onePortrait();
    p = one.p;
    maps = one.maps;
    lowMaps = computeRetouchMaps(p.image, p.analysis, longEdge: 256);
  });

  Future<({int max, double mean, int changed})> check(
    String name,
    PortraitSettings s, {
    RetouchMaps? using,
  }) async {
    final m = using ?? maps;
    final u = RetouchUniforms.fromSettings(s, p.analysis);
    final cpu = applyRetouch(p.image, m, u);
    final gpu = await gpuRetouch(p.image, m, u);
    final d = diffStats(gpu, cpu);
    // Outside every face (face id 0) the GPU must keep the source bit-exact.
    final w = p.image.width, h = p.image.height;
    var changed = 0, leaked = 0;
    for (var i = 0; i < cpu.data.length; i += 4) {
      var same = true;
      for (var c = 0; c < 3; c++) {
        same = same && cpu.data[i + c] == p.image.data[i + c];
      }
      if (!same) changed++;
      final x = (i ~/ 4) % w, y = (i ~/ 4) ~/ w;
      final face = m.nearest(
        RetouchChannel.faceId,
        (x + 0.5) / w,
        (y + 0.5) / h,
      );
      if (face != 0) continue;
      for (var c = 0; c < 3; c++) {
        if (gpu.data[i + c] != p.image.data[i + c]) leaked++;
      }
    }
    expect(leaked, 0, reason: '$name: pixels outside faces changed');
    expect(d.max, lessThanOrEqualTo(3), reason: name);
    expect(d.mean, lessThanOrEqualTo(1), reason: name);
    if (_report) {
      debugPrint(
        'retouch parity $name: max ${d.max}/255, '
        'mean ${d.mean.toStringAsFixed(3)}/255, changed $changed px',
      );
    }
    return (max: d.max, mean: d.mean, changed: changed);
  }

  const effects = {
    'smooth 60': {PortraitIds.skinSoftening: 60.0},
    'smooth 100': {PortraitIds.skinSoftening: 100.0},
    'texture -80': {PortraitIds.skinTexture: -80.0},
    'texture +80': {PortraitIds.skinTexture: 80.0},
    'even 80': {PortraitIds.skinEven: 80.0},
    'dark circles 80': {PortraitIds.darkCircles: 80.0},
    'bags 80': {PortraitIds.eyeBags: 80.0},
    'shine 80': {PortraitIds.skinShine: 80.0},
    'eye whites 80': {PortraitIds.eyeWhites: 80.0},
    'iris 80': {PortraitIds.iris: 80.0},
    'red vein 80': {PortraitIds.redVein: 80.0},
    'teeth bright 80': {PortraitIds.teethBrightness: 80.0},
    'teeth desat 80': {PortraitIds.teethDesaturate: 80.0},
    'acne 100': {PortraitIds.acne: 100.0},
    'freckle 100': {PortraitIds.freckle: 100.0},
    'mole 100': {PortraitIds.mole: 100.0},
    'wrinkle forehead 100': {PortraitIds.wrinkleForehead: 100.0},
    'wrinkle frown 100': {PortraitIds.wrinkleFrown: 100.0},
    'wrinkle crow’s feet 100': {PortraitIds.wrinkleCrowsFeet: 100.0},
    'wrinkle smile 100': {PortraitIds.wrinkleSmile: 100.0},
    'wrinkle marionette 70': {PortraitIds.wrinkleMarionette: 70.0},
    'lips 100': {PortraitIds.lips: 100.0},
    'blush 100': {PortraitIds.blush: 100.0},
  };

  group('each effect alone', () {
    for (final e in effects.entries) {
      test(e.key, () async {
        final r = await check(e.key, portraitOf(e.value));
        expect(r.changed, greaterThan(0), reason: '${e.key} had no effect');
      });
    }
  });

  test('a user-forced spot removal heals with every slider at 0', () async {
    final acne = maps.blemishes.firstWhere((b) => b.kind == BlemishKind.acne);
    final forced = computeRetouchMaps(
      p.image,
      p.analysis,
      overrides: BlemishOverrides(removeAt: [acne.anchor]),
    );
    expect(forced.hasForcedSpots, isTrue);
    final r = await check(
      'forced removal only',
      PortraitSettings.empty,
      using: forced,
    );
    expect(r.changed, greaterThan(0));
  });

  test('blemish slider levels', () async {
    var last = -1;
    for (final v in [10.0, 35.0, 60.0, 90.0]) {
      final r = await check('acne $v', portraitOf({PortraitIds.acne: v}));
      expect(r.changed, greaterThanOrEqualTo(last));
      last = r.changed;
    }
  });

  test('all effects at once, maps coarser than the image', () async {
    final all = <String, double>{
      for (final v in effects.values) ...v,
      PortraitIds.lidProtect: 100,
    }..remove(PortraitIds.skinTexture);
    await check('all (maps 384)', portraitOf(all));
    await check('all (maps 256)', portraitOf(all), using: lowMaps);
  });

  test('wrinkle zones blend with different sliders', () async {
    await check(
      'forehead 100 + frown 20 + smile 40 + marionette 90',
      portraitOf({
        PortraitIds.wrinkleForehead: 100,
        PortraitIds.wrinkleFrown: 20,
        PortraitIds.wrinkleSmile: 40,
        PortraitIds.wrinkleMarionette: 90,
        PortraitIds.skinSoftening: 50,
      }),
    );
  });

  test('clipped shine core: no fill at 40, fill at 70 and 100', () async {
    final core = onePortrait(clippedShine: true);
    for (final v in [40.0, 70.0, 100.0]) {
      final u = RetouchUniforms.fromSettings(
        portraitOf({PortraitIds.skinShine: v}),
        core.p.analysis,
      );
      final cpu = applyRetouch(core.p.image, core.maps, u);
      final gpu = await gpuRetouch(core.p.image, core.maps, u);
      final d = diffStats(gpu, cpu);
      expect(d.max, lessThanOrEqualTo(3), reason: 'shine $v');
      expect(d.mean, lessThanOrEqualTo(1), reason: 'shine $v');
      if (_report) {
        debugPrint(
          'retouch parity clipped shine $v: max ${d.max}/255, '
          'mean ${d.mean.toStringAsFixed(3)}/255',
        );
      }
    }
  });

  test('group and individual rows pick per-face values', () async {
    final two = renderSynthPortrait(512, 320, const [
      SynthFace(id: 'f', cx: 140, cy: 120, iod: 80, group: FaceGroup.female),
      SynthFace(id: 'm', cx: 380, cy: 120, iod: 80, personId: 'bob'),
    ]);
    final m = computeRetouchMaps(two.image, two.analysis);
    final s = portraitOf({PortraitIds.skinSoftening: 30})
        .withGroupValue(FaceGroup.female, PortraitIds.skinSoftening, 90)
        .withGroupValue(FaceGroup.female, PortraitIds.lips, 80)
        .withIndividualValue('bob', PortraitIds.skinShine, 100)
        .withIndividualValue('bob', PortraitIds.blush, 60)
        .withIndividualValue('bob', PortraitIds.wrinkleSmile, 100);
    final u = RetouchUniforms.fromSettings(s, two.analysis);
    expect(u.row(0), isNot(u.row(1)));
    final cpu = applyRetouch(two.image, m, u);
    final gpu = await gpuRetouch(two.image, m, u);
    final d = diffStats(gpu, cpu);
    expect(d.max, lessThanOrEqualTo(3));
    expect(d.mean, lessThanOrEqualTo(1));
    if (_report) {
      debugPrint(
        'retouch parity 2 faces (group+individual): max ${d.max}/255, '
        'mean ${d.mean.toStringAsFixed(3)}/255',
      );
    }
  });

  test(
    'identity is skipped and bit-exact (lid protection alone is inert)',
    () async {
      for (final s in [
        PortraitSettings.empty,
        portraitOf({PortraitIds.lidProtect: 100}),
      ]) {
        final u = RetouchUniforms.fromSettings(s, p.analysis);
        expect(u.key, 'retouch:identity');
        final gpu = await gpuRetouch(p.image, maps, u);
        expect(identical(gpu, p.image), isTrue);
      }
      expect(EngineImages.live, 0);
    },
  );

  test('tiled pass equals the single pass bit-exactly', () async {
    final u = RetouchUniforms.fromSettings(
      portraitOf({PortraitIds.skinSoftening: 70, PortraitIds.acne: 80}),
      p.analysis,
    );
    final single = await gpuRetouch(p.image, maps, u);
    final tiled = await gpuRetouch(p.image, maps, u, tileSize: 100);
    expect(tiled.data, single.data);
    expect(EngineImages.live, 0);
  });
}
