// Auto Enhance receives the photo's face boxes (and only the boxes), and
// works from the whole frame when they cannot be had.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/ai/auto_edit_service.dart';
import 'package:lumen/ai/ondevice/face_cache.dart';
import 'package:lumen/ai/ondevice/ondevice_providers.dart';
import 'package:lumen/features/ai/auto_faces.dart';
import 'package:lumen_core/lumen_core.dart';

class _Recording implements AutoEditProvider {
  final inputs = <AutoEditInput>[];

  @override
  AutoEditEngine get engine => AutoEditEngine.local;

  @override
  Future<ProviderStatus> status() async => const ProviderStatus.available();

  @override
  Future<AutoEditOutcome> autoEdit(AutoEditInput input) async {
    inputs.add(input);
    return AutoEditOutcome(
      settings: input.current,
      changes: const [],
      engineUsed: AutoEditEngine.local,
    );
  }

  @override
  Future<AutoEditOutcome> instruct(InstructInput input) => autoEdit(input);
}

/// A brown-skinned face, 1.5 stops under, in a white shirt on a grey wall.
RgbaBuffer _underexposedPortrait() {
  final p = RgbaBuffer(240, 160);
  const k = 0.35; // 2^-1.5
  int enc(double lin) => (linearToSrgb(lin * k) * 255).round();
  for (var y = 0; y < p.height; y++) {
    for (var x = 0; x < p.width; x++) {
      final du = (x - 120) / 22, dv = (y - 64) / 24;
      final ds = (x - 120) / 60, dt = (y - 140) / 36;
      if (du * du + dv * dv <= 1) {
        p.setPixel(x, y, enc(0.25), enc(0.14), enc(0.085));
      } else if (ds * ds + dt * dt <= 1) {
        p.setPixel(x, y, enc(0.85), enc(0.85), enc(0.85));
      } else {
        final g = enc(0.3 + 0.1 * y / p.height);
        p.setPixel(x, y, g, g, g);
      }
    }
  }
  return p;
}

const _box = FaceBox(98 / 240, 40 / 160, 44 / 240, 48 / 160);

void main() {
  final proxy = _underexposedPortrait();

  AiPhotoContext ctx({Future<List<FaceBox>> Function()? faces}) =>
      AiPhotoContext(
        proxy: proxy,
        current: DevelopSettings.defaults,
        faces: faces,
      );

  test('the face boxes reach the local engine', () async {
    final engine = _Recording();
    final service = AutoEditService(local: engine, isolateLocal: false);
    await service.autoEdit(ctx(faces: () async => const [_box]));
    expect(engine.inputs.single.faces, const [_box]);
  });

  test('no loader, or a loader that fails: the edit still runs, from the '
      'whole frame', () async {
    final engine = _Recording();
    final service = AutoEditService(local: engine, isolateLocal: false);
    await service.autoEdit(ctx());
    await service.autoEdit(
      ctx(faces: () async => throw const FormatException('no models')),
    );
    expect(engine.inputs, hasLength(2));
    expect(engine.inputs.every((i) => i.faces.isEmpty), isTrue);
  });

  test('copyWith keeps the photo and swaps the loaders', () async {
    final base = ctx();
    final withFaces = base.copyWith(faces: () async => const [_box]);
    expect(withFaces.proxy, same(base.proxy));
    expect(await withFaces.faces!(), const [_box]);
    expect(withFaces.copyWith().faces, same(withFaces.faces));
  });

  test('with its face known, an under-exposed portrait is lifted for the '
      'face; the face boxes never enter the edit', () async {
    final service = AutoEditService(
      local: const LocalAutoEditProvider(),
      isolateLocal: false,
    );
    final blind = await service.autoEdit(ctx());
    final aware = await service.autoEdit(ctx(faces: () async => const [_box]));
    final ev = aware.outcome.settings.value(P.exposure);
    expect(ev, greaterThan(0.5));
    expect(ev, greaterThan(blind.outcome.settings.value(P.exposure)));
    final exposure = aware.record.changes.firstWhere(
      (c) => c.param == P.exposure,
    );
    expect(exposure.reason, contains('faces'));
    // Nothing about the face is stored with the edit.
    final json = aware.outcome.settings.toJson().toString();
    expect(json, isNot(contains('box')));
    expect(json, isNot(contains('landmark')));
    expect(aware.outcome.settings.portrait, DevelopSettings.defaults.portrait);
  });

  test('autoEnhanceFacesProvider: boxes from the face cache; none when '
      'analysis is unavailable', () async {
    final c = ProviderContainer(
      overrides: [
        faceAnalysisProvider.overrideWith((ref, id) async {
          if (id != 'portrait') throw StateError('no models here');
          return FaceCacheEntry(
            models: const {},
            analysis: const FaceAnalysis(
              imageWidth: 240,
              imageHeight: 160,
              modelVersion: 'test',
              faces: [DetectedFace(id: 'f0', box: _box)],
            ),
          );
        }),
      ],
    );
    addTearDown(c.dispose);
    final load = c.read(autoEnhanceFacesProvider);
    expect(await load('portrait'), const [_box]);
    expect(await load('landscape'), isEmpty);
  });
}
