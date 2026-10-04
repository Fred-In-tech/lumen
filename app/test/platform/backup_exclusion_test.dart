import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/platform/backup_exclusion_io.dart';
import 'package:lumen/platform/platform_info_io.dart';
import 'package:lumen_core/lumen_core.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('startup sweep excludes models and every asset cache folder', () async {
    final root = await Directory.systemTemp.createTemp('lumen_backup');
    addTearDown(() => root.delete(recursive: true));
    Future<void> mk(String rel) =>
        Directory(p.join(root.path, rel)).create(recursive: true);
    await mk('models/selfie/1');
    await mk('lumen_catalog_v1/assets/a1/cache/masks');
    await mk('lumen_catalog_v1/assets/a1/retouch');
    await mk('lumen_catalog_v1/assets/a2');

    final excluded = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('lumen/backup'), (
          call,
        ) async {
          expect(call.method, 'exclude');
          excluded.add((call.arguments as Map)['path'] as String);
          return true;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('lumen/backup'), null),
    );

    const mac = PlatformInfo(
      isMacOS: true,
      isWindows: false,
      isLinux: false,
      isIOS: false,
      isAndroid: false,
    );
    final n = await sweepBackupExclusions(
      root.path,
      'lumen_catalog_v1',
      platform: mac,
    );
    expect(n, 2);
    expect(excluded.map((e) => p.relative(e, from: root.path)).toSet(), {
      'models',
      p.join('lumen_catalog_v1', 'assets', 'a1', 'cache'),
    });
  });

  test('non-Apple platforms skip the native call', () async {
    const android = PlatformInfo(
      isMacOS: false,
      isWindows: false,
      isLinux: false,
      isIOS: false,
      isAndroid: true,
    );
    expect(await excludeFromBackup('/x', platform: android), isFalse);
    expect(await sweepBackupExclusions('/x', 'y', platform: android), 0);
  });

  test('Android backup rules exclude the library assets and models', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();
    expect(manifest, contains('android:fullBackupContent="@xml/backup_rules"'));
    expect(
      manifest,
      contains('android:dataExtractionRules="@xml/data_extraction_rules"'),
    );
    for (final f in ['backup_rules.xml', 'data_extraction_rules.xml']) {
      final xml = File('android/app/src/main/res/xml/$f').readAsStringSync();
      expect(xml, contains('path="${kBrand.storageId}/assets/"'), reason: f);
      expect(xml, contains('path="models/"'), reason: f);
    }
  });
}
