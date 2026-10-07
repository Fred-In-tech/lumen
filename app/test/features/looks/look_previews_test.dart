import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:lumen/engine/creative_lut_cache.dart';
import 'package:lumen/features/looks/look.dart';
import 'package:lumen/features/looks/look_previews.dart';
import 'package:lumen/features/projects/project_providers.dart';
import 'package:lumen_core/lumen_core.dart';

import '../../support/lut_fixtures.dart';
import '../../support/test_images.dart';

Preset _preset(String name, Map<ParamId, double> v, {String group = 'G'}) =>
    Preset(id: name, name: name, group: group, values: v);

double _meanLuma(List<int> jpeg) {
  final im = img.decodeJpg(Uint8List.fromList(jpeg))!;
  var sum = 0.0;
  for (final p in im) {
    sum += p.luminanceNormalized;
  }
  return sum / (im.width * im.height);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(CreativeLuts.reset);

  test('samples suit the look', () {
    expect(
      sampleFor(const StyleLook(AiStyle.moody)),
      SamplePhoto.portraitMoody,
    );
    expect(
      sampleFor(const StyleLook(AiStyle.goldenHour)),
      SamplePhoto.sunsetLandscape,
    );
    expect(
      sampleFor(const StyleLook(AiStyle.portraitSoft)),
      SamplePhoto.portraitPink,
    );
    expect(
      sampleFor(PresetLook(_preset('Bright & Airy', const {}))),
      SamplePhoto.weddingCouple,
    );
    expect(
      sampleFor(PresetLook(_preset('Dark Matte', const {}))),
      SamplePhoto.portraitMoody,
    );
    expect(
      sampleFor(PresetLook(_preset('Warm', const {}, group: 'Sunset'))),
      SamplePhoto.sunsetLandscape,
    );
    expect(
      sampleFor(PresetLook(_preset('Soft skin', const {}))),
      SamplePhoto.portraitPink,
    );
    final lut = Preset(
      id: 'l',
      name: 'X',
      values: const {},
      lut: refOf(tealOrangeLut(size: 3)),
      source: PresetSource.lut,
    );
    expect(sampleFor(PresetLook(lut)), SamplePhoto.sunsetLandscape);
    expect(SamplePhoto.portraitPink.asset, 'assets/samples/portrait_pink.jpg');
  });

  test('Home previews the newest active project cover, else the newest '
      'photo', () {
    CatalogEntry e(String id) => CatalogEntry(
      assetId: id,
      fileName: '$id.jpg',
      originalPath: 'o/$id.jpg',
      format: 'jpeg',
      width: 4,
      height: 4,
      bytes: 1,
      importedAt: DateTime.utc(2026),
    );
    final p = Project(
      id: 'p',
      name: 'Wedding',
      coverAssetId: 'b',
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );
    final wedding = summarize(
      p,
      [e('a'), e('b')],
      (accepted: const {}, faces: const {}),
    );
    final unsorted = summarize(
      null,
      [e('z')],
      (accepted: const {}, faces: const {}),
    );
    expect(homePreviewAssetId([unsorted, wedding], [e('z')]), 'b');
    expect(homePreviewAssetId([unsorted], [e('z')]), 'z');
    expect(homePreviewAssetId(const [], const []), isNull);
  });

  test('labels and kinds of every look', () {
    expect(const StyleLook(AiStyle.film).kind, LookKind.look);
    expect(const StyleLook(AiStyle.film).sourceLabel, 'Built-in');
    final lr = PresetLook(
      Preset(
        id: 'a',
        name: 'A',
        values: const {P.exposure: 1},
        source: PresetSource.lightroom,
      ),
    );
    expect(lr.kind, LookKind.preset);
    expect(lr.sourceLabel, 'Imported from Lightroom');
    expect(lr.editable, isTrue);
    expect(PresetLook(kBuiltinPresets.first).sourceLabel, 'Built-in');
    expect(PresetLook(kBuiltinPresets.first).editable, isFalse);
    expect(
      PresetLook(_preset('u', const {P.exposure: 1})).sourceLabel,
      'Saved in the editor',
    );
  });

  test('renders real samples, caches them, follows the settings', () async {
    final photo = await LookPreviewPhoto.fromProxy(
      'photo-1',
      TestScenes.portrait(640, 480),
    );
    expect(photo.pixels.width, kLookPreviewLongEdge);
    final service = LookPreviewService();
    final bright = PresetLook(_preset('Bright', const {P.exposure: 1.2}));
    final dark = PresetLook(_preset('Dark', const {P.exposure: -1.2}));
    final before = (await service.before(photo))!;
    final a = (await service.preview(bright, photo))!;
    final b = (await service.preview(dark, photo))!;
    expect(_meanLuma(a), greaterThan(_meanLuma(before) + 0.08));
    expect(_meanLuma(b), lessThan(_meanLuma(before) - 0.08));
    // Cached: the same future, one render each.
    final again = service.preview(bright, photo);
    expect(identical(again, service.preview(bright, photo)), isTrue);
    expect(service.renders, 2);
    expect(service.renderTime, greaterThan(Duration.zero));
    // Another value of the same preset is another preview.
    final brighter = PresetLook(_preset('Bright', const {P.exposure: 2}));
    expect(
      LookPreviewService.keyFor(brighter, photo),
      isNot(LookPreviewService.keyFor(bright, photo)),
    );
  });

  test('LUT looks and AI styles render on the photo', () async {
    final lut = twistLut();
    CreativeLuts.remember(lut);
    final photo = await LookPreviewPhoto.fromProxy(
      'photo-2',
      TestScenes.portrait(400, 300),
    );
    final service = LookPreviewService();
    final before = (await service.before(photo))!;
    final lutLook = PresetLook(
      Preset(
        id: 'lut',
        name: 'Twist',
        values: const {},
        lut: refOf(lut),
        source: PresetSource.lut,
      ),
    );
    final l = (await service.preview(lutLook, photo))!;
    expect((_meanLuma(l) - _meanLuma(before)).abs(), greaterThan(0.02));
    final bw = (await service.preview(const StyleLook(AiStyle.bw), photo))!;
    final im = img.decodeJpg(bw)!;
    final px = im.getPixel(im.width ~/ 2, im.height ~/ 2);
    expect((px.r - px.b).abs(), lessThan(8)); // black & white
  });
}
