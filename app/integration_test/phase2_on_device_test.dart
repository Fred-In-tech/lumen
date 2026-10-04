// Phase 2 GPU suites on a real backend (Metal on macOS/iOS): the headless
// tester rasterizes in software, so shader behaviour that only shows on a
// real GPU (precision, sampler limits, texture sizes) is caught here.
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/engine/backdrop_parity_test.dart' as backdrop;
import '../test/engine/mask_parity_test.dart' as masks;
import '../test/engine/retouch_parity_test.dart' as retouch;
import '../test/engine/warp_parity_test.dart' as warp;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  group('retouch on device', retouch.main);
  group('masks on device', masks.main);
  group('warp on device', warp.main);
  group('backdrop swap on device', backdrop.main);
}
