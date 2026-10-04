import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/ai/ondevice/face_cache.dart';
import 'package:lumen/data/memory_catalog_repository.dart';
import 'package:lumen/features/cull/cull_service.dart';
import 'package:lumen/features/cull/cull_store.dart';
import 'package:lumen/features/cull/cull_store_io.dart';
import 'package:lumen/platform/platform_info.dart';
import 'package:lumen_core/lumen_core.dart';
import 'package:path/path.dart' as p;

Future<T> _inline<T>(FutureOr<T> Function() fn) async => fn();

/// A textured scene (random [block]-px greys from [seed]), optionally
/// blurred by box passes of radius [blur].
RgbaBuffer _scene(int seed, {int blur = 0, int block = 8}) {
  const w = 320, h = 240;
  final rnd = math.Random(seed);
  final bw = w ~/ block + 1;
  final cells = [
    for (var i = 0; i < bw * (h ~/ block + 1); i++) rnd.nextInt(256),
  ];
  var plane = Float32List.fromList([
    for (var y = 0; y < h; y++)
      for (var x = 0; x < w; x++)
        cells[(y ~/ block) * bw + x ~/ block].toDouble(),
  ]);
  for (var k = 0; k < 3 && blur > 0; k++) {
    plane = boxMean(plane, w, h, blur);
  }
  final img = RgbaBuffer(w, h);
  for (var i = 0; i < w * h; i++) {
    final v = plane[i].round().clamp(0, 255);
    img.data
      ..[i * 4] = v
      ..[i * 4 + 1] = v
      ..[i * 4 + 2] = v
      ..[i * 4 + 3] = 255;
  }
  return img;
}

CatalogEntry _entry(String id, int second) => CatalogEntry(
  assetId: id,
  fileName: '$id.jpg',
  originalPath: 'originals/$id.jpg',
  format: 'jpeg',
  width: 320,
  height: 240,
  bytes: 1,
  importedAt: DateTime.utc(2026, 10, 3),
  exif: ExifSummary(capturedAt: DateTime.utc(2026, 10, 3, 15, 0, second)),
);

void main() {
  late MemoryCatalogRepository catalog;
  late MemoryCullStore store;
  late Map<String, RgbaBuffer> photos;
  late List<String> decoded;

  setUp(() async {
    catalog = MemoryCatalogRepository();
    store = MemoryCullStore();
    decoded = [];
    photos = {
      'sharp': _scene(1),
      'soft': _scene(1, blur: 3),
      'twin': _scene(1, blur: 1),
      'other': _scene(7),
    };
    var t = 0;
    for (final id in photos.keys) {
      await catalog.add(_entry(id, t), Uint8List(1));
      t += id == 'twin' ? 120 : 2;
    }
  });

  SmartCullService service({CullFaceLoader? faces}) => SmartCullService(
    store: store,
    catalog: catalog,
    pixels: (id) async {
      decoded.add(id);
      final px = photos[id]!;
      return (pixels: px, sourceWidth: px.width, sourceHeight: px.height);
    },
    faces: faces ?? (id, px) async => null,
    facesKey: 'faces@1',
    runner: _inline,
  );

  test(
    'a burst is clustered, the sharp shot picked, the soft one rejected',
    () async {
      final out = await service().run(['sharp', 'soft', 'twin', 'other']);

      expect(out.failed, isEmpty);
      final s = out.result.suggestions;
      expect(s['sharp']!.decision, CullDecision.pick);
      expect(s['soft']!.decision, CullDecision.reject);
      expect(s['soft']!.reasons, contains(CullReason.blurry));
      expect(s['sharp']!.clusterId, s['soft']!.clusterId);
      // "twin" is the same scene two minutes later: a near-duplicate.
      expect(s['twin']!.clusterId, s['sharp']!.clusterId);
      expect(s['other']!.clusterId, isNull);
      // Stored as pending; the second run reuses the measured signals.
      expect((await store.read('sharp'))!.pending!.decision, CullDecision.pick);
      expect(decoded, hasLength(4));
      await service().run(['sharp', 'soft']);
      expect(decoded, hasLength(4));
    },
  );

  test('faces from the face cache drive the eye rule', () async {
    final closed = List<double>.filled(MeshKeypoints.pointCount * 2, 0.5);
    void put(int i, double x, double y) {
      closed[2 * i] = x;
      closed[2 * i + 1] = y;
    }

    for (final (eye, cx) in [
      (MeshKeypoints.rightEyeEar, 0.44),
      (MeshKeypoints.leftEyeEar, 0.56),
    ]) {
      put(eye[0], cx - 0.03, 0.4);
      put(eye[3], cx + 0.03, 0.4);
      for (final k in [1, 2, 4, 5]) {
        put(eye[k], cx, 0.4);
      }
    }
    final entry = FaceCacheEntry(
      models: const {},
      analysis: FaceAnalysis(
        imageWidth: 320,
        imageHeight: 240,
        modelVersion: 'v',
        faces: [
          DetectedFace(
            id: 'f',
            box: const FaceBox(0.35, 0.3, 0.3, 0.4),
            landmarks: closed,
          ),
        ],
      ),
    );
    final out = await service(
      faces: (id, px) async => id == 'other' ? entry : null,
    ).run(['other']);
    final s = out.result.suggestions['other']!;
    expect(s.decision, CullDecision.reject);
    expect(s.reasons, contains(CullReason.eyesClosed));
  });

  test('cancellation stops measuring; failures are reported', () async {
    var calls = 0;
    final out = await service().run([
      'sharp',
      'missing',
      'soft',
      'other',
    ], isCancelled: () => ++calls > 3);
    expect(out.cancelled, isTrue);
    expect(out.failed, ['missing']);
    expect(out.records.keys, ['sharp', 'soft']);
  });

  test('records round-trip through JSON; other versions read as a miss', () {
    final r = CullRecord(
      signalsKey: 'k',
      signals: CullSignals(
        sharpness: 0.2,
        highlightClip: 0.01,
        shadowClip: 0,
        meanLuma: 0.4,
        dHash: '0123456789abcdef',
      ),
      suggestion: CullSuggestion(
        assetId: 'x',
        decision: CullDecision.pick,
        score: 0.8,
      ),
      status: SuggestionStatus.dismissed,
    );
    final back = CullRecord.tryFromJson(r.toJson())!;
    expect(back.signals, r.signals);
    expect(back.status, SuggestionStatus.dismissed);
    expect(back.pending, isNull);
    expect(back.suggestion!.decision, CullDecision.pick);
    expect(CullRecord.tryFromJson({'cacheVersion': 2}), isNull);
  });

  group('FileCullStore', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel('lumen/backup');
    const id = '0123456789abcdef0123456789abcdef';

    test(
      'writes assets/<id>/cache/cull.json and excludes the folder',
      () async {
        final tmp = await Directory.systemTemp.createTemp('cull_store');
        addTearDown(() => tmp.delete(recursive: true));
        final excluded = <String>[];
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              excluded.add((call.arguments as Map)['path'] as String);
              return true;
            });
        addTearDown(
          () => TestDefaultBinaryMessengerBinding
              .instance
              .defaultBinaryMessenger
              .setMockMethodCallHandler(channel, null),
        );
        const mac = PlatformInfo(
          isMacOS: true,
          isWindows: false,
          isLinux: false,
          isIOS: false,
          isAndroid: false,
        );
        final s = FileCullStore(tmp.path, platform: mac);
        final record = CullRecord(
          signalsKey: 'k',
          signals: CullSignals(
            sharpness: 1,
            highlightClip: 0,
            shadowClip: 0,
            meanLuma: 0.5,
            dHash: 'ffffffffffffffff',
          ),
        );
        await s.write(id, record);
        await pumpEventQueue();
        expect(
          s.pathFor(id),
          p.join(tmp.path, 'assets', id, 'cache', 'cull.json'),
        );
        expect((await s.read(id))!.signals, record.signals);
        expect(excluded.map((e) => p.relative(e, from: tmp.path)), [
          p.join('assets', id, 'cache'),
        ]);
        expect(() => s.pathFor('../x'), throwsArgumentError);
      },
    );
  });
}
