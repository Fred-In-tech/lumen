// The float editing path on a real GPU (Metal on macOS / iOS): the same
// suites as `flutter test --enable-impeller test/engine/float_*_test.dart`,
// which the default headless renderer skips (docs/HIGH_BIT_DEPTH.md).
//
//   flutter test integration_test/float_engine_on_device_test.dart -d macos
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lumen/engine/gpu_pass.dart';
import 'package:lumen/engine/hbd_capability.dart';
import 'package:lumen/engine/shader_library.dart';

import '../test/engine/float_export_test.dart' as float_export;
import '../test/engine/float_path_test.dart' as path;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test('this device passes the float probe', () async {
    final ok = await HbdCapability.probe(await ShaderLibrary.load());
    debugPrint('RESULT on-device float probe: $ok');
    // Apple GPUs must pass; elsewhere the suites below skip themselves.
    if (defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.iOS) {
      expect(ok, isTrue);
    }
    expect(EngineImages.live, 0);
  });

  group('float path on device', path.main);
  group('float export on device', float_export.main);
}
