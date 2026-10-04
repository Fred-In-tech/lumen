import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/ai/ondevice/ai_raster_store.dart';
import 'package:lumen/ai/ondevice/fake_inference_backend.dart';
import 'package:lumen/ai/ondevice/inference_backend.dart';
import 'package:lumen/ai/ondevice/mask_segmenter.dart';
import 'package:lumen/ai/ondevice/model_store.dart';
import 'package:lumen/ai/ondevice/ondevice_ai_mask_source.dart';
import 'package:lumen_core/lumen_core.dart';

import 'face_fakes.dart';

const _spec = ModelManifest.selfieMulticlass;
const _w = 400, _h = 300;
const _asset = '0123456789abcdef0123456789abcdef';
const _face = FaceBox(0.6, 0.4, 0.1, 0.13);

/// Whole image: background left of the tensor centre, clothes right.
/// Face crops: face skin everywhere. One-hot probabilities.
FakeModel _selfieModel(List<int> runs) => FakeModel.fromSpec(_spec, (inputs) {
  final whole = runs.isEmpty;
  runs.add(1);
  final out = Float32List(256 * 256 * 6);
  for (var y = 0; y < 256; y++) {
    for (var x = 0; x < 256; x++) {
      final c = !whole
          ? SelfieClass.faceSkin
          : x < 128
          ? SelfieClass.background
          : SelfieClass.clothes;
      out[(y * 256 + x) * 6 + c] = 1;
    }
  }
  return {'Identity': out};
});

int _at(MaskRaster r, double u, double v) =>
    r.data[(v * r.height).floor() * r.width + (u * r.width).floor()];

void main() {
  late List<int> runs;
  late MemoryAiRasterStore store;
  late FakeInferenceBackend backend;

  setUp(() {
    runs = [];
    store = MemoryAiRasterStore();
    backend = FakeInferenceBackend({_spec.fileName: _selfieModel(runs)});
  });

  Future<MaskSegmenter> segmenter() async => MaskSegmenter(
    session: await loadVerifiedSession(
      backend,
      _spec,
      ModelFileSource('/m/${_spec.fileName}'),
    ),
    spec: _spec,
    runner: inlineRunner,
  );

  OnDeviceAiMaskSource source({
    Future<MaskSegmenter> Function()? seg,
    List<FaceBox> faces = const [_face],
  }) => OnDeviceAiMaskSource(
    spec: _spec,
    segmenter: seg ?? segmenter,
    store: () async => store,
    pixels: (_) async => RgbaBuffer.filled(_w, _h, 120, 120, 120),
    faces: (_) async => faces,
  );

  test('planes in → expected coverage rasters, one model pass', () async {
    final s = source();

    final shape = await s.segment(_asset, MaskKind.subject);

    expect(shape.maskRef, 'people.selfie_multiclass_256-1');
    expect(shape.model, 'selfie_multiclass_256');
    expect(shape.modelVersion, '1');
    expect(runs, hasLength(2), reason: 'whole image + one face crop');
    final people = (await s.load(_asset, shape.maskRef))!;
    expect((people.width, people.height), (_w, _h));
    expect(_at(people, 0.9, 0.8), greaterThan(250));
    expect(_at(people, 0.1, 0.5), lessThan(5));
    final bg = (await s.load(_asset, s.maskRefFor(AiRaster.background)))!;
    for (var i = 0; i < bg.data.length; i += 97) {
      expect(bg.data[i] + people.data[i], inInclusiveRange(254, 256));
    }
    final skin = (await s.load(_asset, s.maskRefFor(AiRaster.faceSkin)))!;
    expect(_at(skin, _face.centerX, _face.centerY), greaterThan(250));
    expect(_at(skin, 0.1, 0.1), lessThan(5));
    final clothes = (await s.load(_asset, s.maskRefFor(AiRaster.clothes)))!;
    expect(_at(clothes, 0.9, 0.9), greaterThan(250));
    // Every raster was written; Background reuses the same pass.
    expect(store.files, hasLength(AiRaster.values.length));
    final bgShape = await s.segment(_asset, MaskKind.background);
    expect(bgShape.maskRef, 'background.selfie_multiclass_256-1');
    expect(runs, hasLength(2));
  });

  test('sky has no on-device model', () async {
    final s = source();
    expect(s.supports(MaskKind.sky), isFalse);
    expect(s.supports(MaskKind.faceSkin), isTrue);
    expect(s.supports(MaskKind.linear), isFalse);
    await expectLater(
      s.segment(_asset, MaskKind.sky),
      throwsA(isA<AiMaskUnsupported>()),
    );
    expect(runs, isEmpty);
  });

  test(
    'a cleared cache is regenerated; other model versions are not',
    () async {
      await source().segment(_asset, MaskKind.person);
      store.files.clear();
      final fresh = source();
      final ref = fresh.maskRefFor(AiRaster.people);
      expect(await fresh.load(_asset, ref), isNotNull);
      expect(runs, hasLength(4));
      expect(
        await fresh.load(_asset, 'people.selfie_multiclass_256-0'),
        isNull,
      );
      expect(await fresh.load(_asset, 'garbage'), isNull);
      expect(runs, hasLength(4));
    },
  );

  test('no faces → whole-image pass only', () async {
    final s = source(faces: const []);
    await s.segment(_asset, MaskKind.subject);
    expect(runs, hasLength(1));
  });

  test('model failures surface as typed errors and a failed status', () async {
    final s = source(
      seg: () async => throw const ModelDownloadFailed('offline'),
    );
    final statuses = <AiMaskStatus>[];
    final sub = s.status.listen(statuses.add);
    await expectLater(
      s.segment(_asset, MaskKind.subject),
      throwsA(isA<ModelDownloadFailed>()),
    );
    await pumpEventQueue();
    expect(statuses.map((e) => e.phase), [
      AiMaskPhase.loadingModel,
      AiMaskPhase.failed,
    ]);
    expect(statuses.last.message, contains('offline'));
    expect(store.files, isEmpty);
    await sub.cancel();
  });

  test('a segmentation output without class channels is refused', () async {
    final bad = FakeInferenceBackend({
      'bad': FakeModel(
        inputs: const [
          (name: 'input_29', shape: [1, 256, 256, 3]),
        ],
        outputs: const [
          (name: 'Identity', shape: [1, 256, 256, 2]),
        ],
        onRun: (_) => const {},
      ),
    });
    final session = await bad.load(const ModelFileSource('bad'));
    expect(
      () => MaskSegmenter(session: session, spec: _spec),
      throwsA(isA<ModelContractMismatch>()),
    );
  });
}
