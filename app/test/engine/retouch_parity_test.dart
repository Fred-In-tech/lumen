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
    lowMaps = computeRetouchMaps(p.image, p.analysis, targetIod: 64);
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
      final face = m.sourceNearest(
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

  test('red-eye: red pupils fixed, normal eyes untouched', () async {
    final red = renderSynthPortrait(384, 384, [
      const SynthFace(id: 'a', cx: 192, cy: 150, iod: 104, redEye: true),
    ]);
    final m = computeRetouchMaps(red.image, red.analysis);
    final u = RetouchUniforms.fromSettings(
      portraitOf({PortraitIds.redEye: 100}),
      red.analysis,
    );
    final cpu = applyRetouch(red.image, m, u);
    final gpu = await gpuRetouch(red.image, m, u);
    final d = diffStats(gpu, cpu);
    expect(d.max, lessThanOrEqualTo(1));
    expect(d.mean, lessThanOrEqualTo(1));
    if (_report) {
      debugPrint(
        'retouch parity red-eye: max ${d.max}/255, '
        'mean ${d.mean.toStringAsFixed(3)}/255',
      );
    }
    await check(
      'red-eye 100 (normal eyes)',
      portraitOf({PortraitIds.redEye: 100}),
    );
  });

  Future<int> strict(
    String name,
    RgbaBuffer image,
    RetouchMaps m,
    RetouchUniforms u,
  ) async {
    final cpu = applyRetouch(image, m, u);
    expect(identical(cpu, image), isFalse, reason: '$name: no effect');
    final gpu = await gpuRetouch(image, m, u);
    final d = diffStats(gpu, cpu);
    expect(d.max, lessThanOrEqualTo(1), reason: name);
    expect(d.mean, lessThanOrEqualTo(1), reason: name);
    if (_report) {
      debugPrint(
        'retouch parity $name: max ${d.max}/255, '
        'mean ${d.mean.toStringAsFixed(3)}/255',
      );
    }
    var changed = 0;
    for (var i = 0; i < cpu.data.length; i++) {
      if (cpu.data[i] != image.data[i]) changed++;
    }
    return changed;
  }

  test('glasses glare: clear and tinted lenses, 50 and 100', () async {
    for (final g in [SynthGlasses.clear, SynthGlasses.tinted]) {
      final gp = renderSynthPortrait(384, 384, [
        SynthFace(id: 'a', cx: 192, cy: 150, iod: 104, glasses: g),
      ]);
      final m = computeRetouchMaps(gp.image, gp.analysis);
      for (final v in [50.0, 100.0]) {
        final u = RetouchUniforms.fromSettings(
          portraitOf({PortraitIds.glare: v}),
          gp.analysis,
        );
        expect(
          await strict('glare ${g.name} $v', gp.image, m, u),
          greaterThan(0),
        );
      }
      // With other face edits on top (glare shares the heal atlas).
      final both = RetouchUniforms.fromSettings(
        portraitOf({
          PortraitIds.glare: 100,
          PortraitIds.skinSoftening: 60,
          PortraitIds.skinShine: 80,
        }),
        gp.analysis,
      );
      final cpu = applyRetouch(gp.image, m, both);
      final d = diffStats(await gpuRetouch(gp.image, m, both), cpu);
      expect(d.max, lessThanOrEqualTo(3), reason: 'glare ${g.name} + skin');
      expect(d.mean, lessThanOrEqualTo(1), reason: 'glare ${g.name} + skin');
    }
  });

  group('clothes (image scope)', () {
    late ClothesScene shirt;
    late RetouchMaps cm;
    setUpAll(() {
      shirt = renderClothesScene(w: 320, h: 240);
      cm = computeRetouchMaps(
        shirt.image,
        shirt.analysis,
        backdrop: shirt.input,
      );
    });

    test('the shirt maps are ready', () {
      expect(cm.backdrop.clothesState, ClothesState.ready);
      expect(cm.hasClothes, isTrue);
    });

    for (final e in {
      'wrinkles 100': {PortraitIds.clothesWrinkles: 100.0},
      'wrinkles 40': {PortraitIds.clothesWrinkles: 40.0},
      'lint 100': {PortraitIds.clothesLint: 100.0},
      'wrinkles 70 + lint 60': {
        PortraitIds.clothesWrinkles: 70.0,
        PortraitIds.clothesLint: 60.0,
      },
    }.entries) {
      test(e.key, () async {
        final u = RetouchUniforms.fromSettings(
          withImage(e.value),
          shirt.analysis,
        );
        expect(
          await strict('clothes ${e.key}', shirt.image, cm, u),
          greaterThan(0),
        );
        final tiled = await gpuRetouch(shirt.image, cm, u, tileSize: 100);
        expect(tiled.data, (await gpuRetouch(shirt.image, cm, u)).data);
      });
    }

    test('zero values are skipped bit-exactly', () async {
      final u = RetouchUniforms.fromSettings(
        PortraitSettings.empty,
        shirt.analysis,
      );
      expect(
        identical(await gpuRetouch(shirt.image, cm, u), shirt.image),
        isTrue,
      );
      expect(EngineImages.live, 0);
    });

    test('backdrop and clothes together in one atlas', () async {
      final b = renderBackdropScene(w: 320, h: 240);
      final people = b.people;
      final clothes = MaskRaster(
        people.width,
        people.height,
        Uint8List.fromList([
          for (var i = 0; i < people.data.length; i++)
            (i ~/ people.width) >= 0.64 * people.height ? people.data[i] : 0,
        ]),
      );
      final m = computeRetouchMaps(
        b.image,
        b.analysis,
        backdrop: BackdropInput(
          people: b.people,
          hair: b.hair,
          clothes: clothes,
          wantsClothes: true,
        ),
      );
      expect(m.backdrop.state, BackdropState.ready);
      expect(m.backdrop.clothesState, ClothesState.ready);
      final u = RetouchUniforms.fromSettings(
        withImage({
          PortraitIds.bgClean: 100,
          PortraitIds.bgUnify: 60,
          PortraitIds.clothesWrinkles: 100,
          PortraitIds.clothesLint: 100,
        }),
        b.analysis,
      );
      await strict('backdrop + clothes', b.image, m, u);
    });
  });

  group('backdrop (image scope)', () {
    late BackdropScene scene;
    late RetouchMaps bd;
    setUpAll(() {
      scene = renderBackdropScene(w: 320, h: 240);
      bd = computeRetouchMaps(
        scene.image,
        scene.analysis,
        backdrop: scene.input,
      );
    });

    Future<void> checkScene(String name, PortraitSettings s) async {
      final u = RetouchUniforms.fromSettings(s, scene.analysis);
      final cpu = applyRetouch(scene.image, bd, u);
      expect(identical(cpu, scene.image), isFalse, reason: '$name: no effect');
      final gpu = await gpuRetouch(scene.image, bd, u);
      final d = diffStats(gpu, cpu);
      expect(d.max, lessThanOrEqualTo(1), reason: name);
      expect(d.mean, lessThanOrEqualTo(1), reason: name);
      if (_report) {
        debugPrint(
          'retouch parity backdrop $name: max ${d.max}/255, '
          'mean ${d.mean.toStringAsFixed(3)}/255',
        );
      }
    }

    test('the scene backdrop is ready', () {
      expect(bd.backdrop.state, BackdropState.ready);
      expect(bd.hasFaces, isFalse);
    });

    for (final e in {
      'clean 100': {PortraitIds.bgClean: 100.0},
      'clean 40': {PortraitIds.bgClean: 40.0},
      'unify 100': {PortraitIds.bgUnify: 100.0},
      'luminance +100': {PortraitIds.bgUnifyLuminance: 100.0},
      'luminance -60': {PortraitIds.bgUnifyLuminance: -60.0},
      'strays 100': {PortraitIds.strayHairs: 100.0},
      'all': {
        PortraitIds.bgClean: 100.0,
        PortraitIds.bgUnify: 70.0,
        PortraitIds.bgUnifyLuminance: 30.0,
        PortraitIds.strayHairs: 100.0,
      },
    }.entries) {
      test(e.key, () => checkScene(e.key, withImage(e.value)));
    }

    test('defaults and textured backdrops are skipped bit-exactly', () async {
      final u = RetouchUniforms.fromSettings(
        PortraitSettings.empty,
        scene.analysis,
      );
      expect(
        identical(await gpuRetouch(scene.image, bd, u), scene.image),
        isTrue,
      );
      final t = renderBackdropScene(w: 320, h: 240, textured: true);
      final mt = computeRetouchMaps(t.image, t.analysis, backdrop: t.input);
      final ut = RetouchUniforms.fromSettings(
        withImage({PortraitIds.bgClean: 100, PortraitIds.strayHairs: 100}),
        t.analysis,
      );
      expect(identical(await gpuRetouch(t.image, mt, ut), t.image), isTrue);
      expect(EngineImages.live, 0);
    });

    test('faces and backdrop together, tiled = single pass', () async {
      final both = computeRetouchMaps(
        p.image,
        p.analysis,
        backdrop: BackdropInput(people: portraitPeopleRaster(p)),
      );
      expect(both.backdrop.state, BackdropState.ready);
      final s = withImage({
        PortraitIds.bgClean: 100,
        PortraitIds.bgUnify: 80,
      }, portraitOf({PortraitIds.skinSoftening: 60, PortraitIds.redEye: 100}));
      final u = RetouchUniforms.fromSettings(s, p.analysis);
      final cpu = applyRetouch(p.image, both, u);
      final gpu = await gpuRetouch(p.image, both, u);
      final d = diffStats(gpu, cpu);
      expect(d.max, lessThanOrEqualTo(1));
      expect(d.mean, lessThanOrEqualTo(1));
      final tiled = await gpuRetouch(p.image, both, u, tileSize: 100);
      expect(tiled.data, gpu.data);
      if (_report) {
        debugPrint(
          'retouch parity faces + backdrop: max ${d.max}/255, '
          'mean ${d.mean.toStringAsFixed(3)}/255',
        );
      }
    });
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

  test('per-face tiles: overlapping faces at different scales', () async {
    final two = renderSynthPortrait(384, 300, const [
      SynthFace(id: 'a', cx: 150, cy: 120, iod: 80),
      SynthFace(id: 'b', cx: 250, cy: 135, iod: 60),
    ]);
    // Face a is analysed on a 2× "original", face b on the decode.
    final big = renderSynthPortrait(768, 600, const [
      SynthFace(id: 'a', cx: 300, cy: 240, iod: 160),
      SynthFace(id: 'b', cx: 500, cy: 270, iod: 120),
    ]);
    final plans = planFaceTiles(two.analysis, 768, 600);
    final m = computeRetouchMaps(
      two.image,
      two.analysis,
      tiles: [FaceTileImage(plans[0], resampleTile(big.image, plans[0]))],
    );
    expect(m.faces.map((f) => f.iod.round()), [160, 60]);
    final u = RetouchUniforms.fromSettings(
      portraitOf({
        PortraitIds.skinSoftening: 80,
        PortraitIds.skinEven: 60,
        PortraitIds.acne: 100,
        PortraitIds.iris: 80,
        PortraitIds.skinTexture: -50,
      }),
      two.analysis,
    );
    final cpu = applyRetouch(two.image, m, u);
    final gpu = await gpuRetouch(two.image, m, u);
    final d = diffStats(gpu, cpu);
    var leaked = 0, changed = 0;
    final w = two.image.width, h = two.image.height;
    for (var i = 0; i < cpu.data.length; i += 4) {
      if (cpu.data[i] != two.image.data[i]) changed++;
      final x = (i ~/ 4) % w, y = (i ~/ 4) ~/ w;
      if (m.sourceNearest(
            RetouchChannel.faceId,
            (x + 0.5) / w,
            (y + 0.5) / h,
          ) !=
          0) {
        continue;
      }
      for (var c = 0; c < 3; c++) {
        if (gpu.data[i + c] != two.image.data[i + c]) leaked++;
      }
    }
    expect(changed, greaterThan(1000));
    expect(leaked, 0);
    expect(d.max, lessThanOrEqualTo(3));
    expect(d.mean, lessThanOrEqualTo(1));
    final tiled = await gpuRetouch(two.image, m, u, tileSize: 70);
    expect(tiled.data, gpu.data);
  });
}
