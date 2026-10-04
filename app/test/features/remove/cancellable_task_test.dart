import 'dart:isolate' show RemoteError;

import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/platform/cancellable_task.dart';
import 'package:lumen_core/lumen_core.dart';

int _spin() {
  var x = 0;
  for (var i = 0; i < 1 << 62; i++) {
    x = (x * 31 + i) & 0xffff;
  }
  return x;
}

int _square(int v) => v * v;

int _fail() => throw StateError('boom');

void main() {
  test('returns the isolate result', () async {
    expect(await runCancellable(() => _square(12)).result, 144);
  });

  test('errors cross back with their message', () async {
    await expectLater(
      runCancellable(_fail).result,
      throwsA(
        isA<RemoteError>().having(
          (e) => e.toString(),
          'text',
          contains('boom'),
        ),
      ),
    );
  });

  test('cancel kills a busy isolate and completes at once', () async {
    final task = runCancellable(_spin);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final sw = Stopwatch()..start();
    task.cancel();
    await expectLater(task.result, throwsA(isA<InpaintCancelled>()));
    expect(task.isCancelled, isTrue);
    expect(sw.elapsedMilliseconds, lessThan(500));
    task.cancel(); // idempotent
  });

  test('cancel before the isolate starts still stops it', () async {
    final task = runCancellable(_spin)..cancel();
    await expectLater(task.result, throwsA(isA<InpaintCancelled>()));
  });
}
