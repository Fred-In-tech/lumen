import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:lumen/ai/ondevice/ai_raster_store_io.dart';
import 'package:lumen/ai/ondevice/disk_space_probe.dart';
import 'package:lumen/ai/ondevice/face_cache.dart';
import 'package:lumen/ai/ondevice/face_cache_io.dart';
import 'package:lumen/ai/ondevice/model_store.dart';
import 'package:lumen/ai/ondevice/model_store_io.dart';
import 'package:lumen/platform/platform_info.dart';
import 'package:lumen_core/lumen_core.dart';
import 'package:path/path.dart' as p;

const _mac = PlatformInfo(
  isMacOS: true,
  isWindows: false,
  isLinux: false,
  isIOS: false,
  isAndroid: false,
);
const _id = '0123456789abcdef0123456789abcdef';
const _channel = MethodChannel('lumen/backup');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;
  late List<String> excluded;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('backup_hooks');
    excluded = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          excluded.add((call.arguments as Map)['path'] as String);
          return true;
        });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
    await tmp.delete(recursive: true);
  });

  String rel(String path) => p.relative(path, from: tmp.path);
  final cacheDir = p.join('assets', _id, 'cache');

  test('the first face-cache write excludes assets/<id>/cache once', () async {
    final cache = FileFaceCache(tmp.path, platform: _mac);
    final entry = FaceCacheEntry(
      models: const {'detector': 'd@1'},
      analysis: const FaceAnalysis(
        imageWidth: 4,
        imageHeight: 3,
        modelVersion: 'v',
      ),
    );
    await cache.write(_id, entry);
    await cache.write(_id, entry);
    await pumpEventQueue();
    expect(excluded.map(rel), [cacheDir]);
  });

  test('the AI raster store excludes the same cache folder', () async {
    final store = FileAiRasterStore(tmp.path, platform: _mac);
    await store.write(
      _id,
      'people.m-1',
      MaskRaster(2, 1, Uint8List.fromList([0, 255])),
    );
    await pumpEventQueue();
    expect(excluded.map(rel), [cacheDir]);
  });

  test('the model store excludes its root when it first creates it', () async {
    final bytes = Uint8List.fromList(List.generate(64, (i) => i));
    final spec = ModelSpec(
      id: 'b',
      version: '1',
      fileName: 'b.tflite',
      url: 'https://example.invalid/b',
      bytes: bytes.length,
      sha256: sha256.convert(bytes).toString(),
      license: '-',
      trainingDataNote: '-',
      bundled: true,
    );
    final client = http.Client();
    addTearDown(client.close);
    final store = FileModelStore(
      root: p.join(tmp.path, 'models'),
      client: client,
      diskProbe: const FixedDiskSpaceProbe.unknown(),
      budgetBytes: 1 << 20,
      bundled: (_) async => bytes,
      platform: _mac,
    );
    expect(await store.ensure(spec), isA<ModelReady>());
    await pumpEventQueue();
    expect(excluded.map(rel), ['models']);
  });

  test(
    'without a platform (tests, tools) the folder is only created',
    () async {
      await FileFaceCache(tmp.path).write(
        _id,
        FaceCacheEntry(
          models: const {},
          analysis: const FaceAnalysis(
            imageWidth: 1,
            imageHeight: 1,
            modelVersion: 'v',
          ),
        ),
      );
      await pumpEventQueue();
      expect(excluded, isEmpty);
      expect(Directory(p.join(tmp.path, cacheDir)).existsSync(), isTrue);
    },
  );

  test('off Apple platforms nothing is sent to the channel', () async {
    const linux = PlatformInfo(
      isMacOS: false,
      isWindows: false,
      isLinux: true,
      isIOS: false,
      isAndroid: false,
    );
    await FileAiRasterStore(
      tmp.path,
      platform: linux,
    ).write(_id, 'people.m-1', MaskRaster(1, 1, Uint8List(1)));
    await pumpEventQueue();
    expect(excluded, isEmpty);
  });
}
