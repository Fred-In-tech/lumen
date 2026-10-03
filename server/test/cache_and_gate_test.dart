import 'dart:async';

import 'package:lumen_core/lumen_core.dart';
import 'package:lumen_server/lumen_server.dart';
import 'package:lumen_server/src/edit/upstream_gate.dart';
import 'package:logging/logging.dart';
import 'package:test/test.dart';

GatewayEditResponse _resp(String id) => GatewayEditResponse(
  requestId: id,
  model: 'm',
  servedBy: 'm',
  promptVersion: 'p',
  result: const AutoEditResponse(),
);

const _image = ImagePayload(
  mime: 'image/jpeg',
  width: 4,
  height: 4,
  base64: 'AAAA',
);

String _key({
  AutoEditRequest request = const AutoEditRequest(image: _image),
  String? instruction,
  String model = 'm',
}) => resultCacheKey(
  request: request,
  instruction: instruction,
  model: model,
  effort: 'low',
  promptVersion: kPromptVersion,
);

void main() {
  group('ResultCache (LRU)', () {
    test('evicts the least recently used entry', () {
      final cache = ResultCache(capacity: 2)
        ..put('a', _resp('a'))
        ..put('b', _resp('b'));
      expect(cache.get('a')?.requestId, 'a'); // a is now most recent
      cache.put('c', _resp('c'));
      expect(cache.get('b'), isNull);
      expect(cache.get('a'), isNotNull);
      expect(cache.get('c'), isNotNull);
      expect(cache.length, 2);
    });

    test('capacity 0 disables caching', () {
      final cache = ResultCache(capacity: 0)..put('a', _resp('a'));
      expect(cache.get('a'), isNull);
    });
  });

  group('resultCacheKey', () {
    test('ignores requestId and client, depends on inputs', () {
      const a = AutoEditRequest(image: _image, requestId: 'x');
      const b = AutoEditRequest(
        image: _image,
        requestId: 'y',
        client: ClientInfo(platform: 'ios'),
      );
      expect(_key(request: a), _key(request: b));
      expect(_key(), isNot(_key(instruction: 'warmer')));
      expect(_key(), isNot(_key(model: 'other')));
      expect(
        _key(),
        isNot(
          _key(
            request: const AutoEditRequest(
              image: _image,
              current: {P.exposure: 1},
            ),
          ),
        ),
      );
    });
  });

  group('UpstreamGate', () {
    test('limits concurrency and hands slots to waiters in order', () async {
      final gate = UpstreamGate(concurrency: 1, maxQueue: 2);
      final first = Completer<void>();
      final order = <int>[];
      final f1 = gate.run(() async {
        await first.future;
        order.add(1);
      });
      final f2 = gate.run(() async => order.add(2));
      final f3 = gate.run(() async => order.add(3));
      await Future<void>.delayed(Duration.zero);
      expect(gate.active, 1);
      expect(gate.queued, 2);
      await expectLater(
        gate.run(() async {}),
        throwsA(isA<GatewayException>()),
      );
      first.complete();
      await Future.wait([f1, f2, f3]);
      expect(order, [1, 2, 3]);
      expect(gate.active, 0);
    });

    test('releases the slot when the task throws', () async {
      final gate = UpstreamGate(concurrency: 1, maxQueue: 0);
      await expectLater(
        gate.run<void>(() async => throw StateError('x')),
        throwsStateError,
      );
      expect(gate.active, 0);
      expect(await gate.run(() async => 7), 7);
    });
  });

  test('LogUsageMeter logs usage without throwing', () {
    final records = <LogRecord>[];
    final logger = Logger.detached('test.usage')
      ..level = Level.ALL
      ..onRecord.listen(records.add);
    LogUsageMeter(logger).record(
      const UsageEvent(
        requestId: 'r',
        route: '/v1/auto-edit',
        model: 'm',
        servedBy: 'm',
        usage: GatewayUsage(inputTokens: 5),
        cached: false,
        latencyMs: 12,
      ),
    );
    expect(records.single.message, contains('inputTokens: 5'));
  });
}
