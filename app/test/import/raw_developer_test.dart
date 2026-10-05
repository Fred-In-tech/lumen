import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/import/raw_developer_io.dart';
import 'package:lumen/import/raw_developer_types.dart';
import 'package:lumen/platform/platform_info_io.dart';

const _mac = PlatformInfo(
  isMacOS: true,
  isWindows: false,
  isLinux: false,
  isIOS: false,
  isAndroid: false,
);

PlatformInfo _only({bool android = false, bool windows = false}) =>
    PlatformInfo(
      isMacOS: false,
      isWindows: windows,
      isLinux: false,
      isIOS: false,
      isAndroid: android,
    );

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('lumen/raw');
  final raw = Uint8List.fromList([7, 7, 7]);

  void handle(Future<Object?> Function(MethodCall call)? handler) =>
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, handler);
  tearDown(() => handle(null));

  test(
    'Android and Windows: unsupported, and the channel is never called',
    () async {
      var calls = 0;
      handle((_) async => calls++);
      for (final platform in [_only(android: true), _only(windows: true)]) {
        await expectLater(
          PlatformRawDeveloper(platform: platform)
              .develop(raw, extension: 'cr3'),
          throwsA(
            isA<RawDevelopException>().having(
              (e) => e.message,
              'message',
              "RAW photos aren't supported on this device yet.",
            ),
          ),
        );
      }
      expect(calls, 0);
    },
  );

  test('Apple: hands the RAW over by path and returns the rendition; '
      'temp files are removed', () async {
    late Map<Object?, Object?> args;
    handle((call) async {
      expect(call.method, 'develop');
      args = call.arguments as Map<Object?, Object?>;
      expect(File(args['input']! as String).readAsBytesSync(), raw);
      File(args['output']! as String).writeAsBytesSync([1, 2, 3, 4]);
      return null;
    });

    final out = await const PlatformRawDeveloper(platform: _mac)
        .develop(raw, extension: 'cr3');

    expect(out, [1, 2, 3, 4]);
    expect(args['input'], endsWith('source.cr3'));
    expect(args['quality'], kRawRenditionQuality);
    expect(File(args['input']! as String).parent.existsSync(), isFalse);
  });

  test('Apple: a decoder error becomes a user-facing failure', () async {
    String? dir;
    handle((call) async {
      dir = File((call.arguments as Map)['input'] as String).parent.path;
      throw PlatformException(code: 'develop_failed', message: 'nope');
    });
    await expectLater(
      const PlatformRawDeveloper(platform: _mac).develop(raw, extension: 'cr2'),
      throwsA(
        isA<RawDevelopException>().having(
          (e) => '$e',
          'message',
          contains('could not be developed'),
        ),
      ),
    );
    expect(Directory(dir!).existsSync(), isFalse);
  });

  test(
    'Apple: a handler that writes nothing is a failure, not a crash',
    () async {
      handle((_) async => null);
      await expectLater(
        const PlatformRawDeveloper(platform: _mac)
            .develop(raw, extension: 'cr3'),
        throwsA(isA<RawDevelopException>()),
      );
    },
  );

  test('no native handler registered: unsupported', () async {
    await expectLater(
      const PlatformRawDeveloper(platform: _mac).develop(raw, extension: 'cr3'),
      throwsA(
        isA<RawDevelopException>().having(
          (e) => e.message,
          'message',
          kRawUnsupportedMessage,
        ),
      ),
    );
  });
}
