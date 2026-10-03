import 'package:lumen_core/lumen_core.dart';
import 'package:lumen_server/lumen_server.dart';
import 'package:test/test.dart';

import '../support/fixtures.dart';

Map<String, double> _values(Map<String, Object?> json) {
  final result = json['result']! as Map<String, Object?>;
  final variant = (result['variants']! as List).single as Map;
  return {
    for (final a in variant['adjustments']! as List)
      (a as Map)['param']! as String: (a['value']! as num).toDouble(),
  };
}

void main() {
  group('/v1/auto-edit', () {
    test(
      'success: contract shape, clamping, unknown/locked params dropped',
      () async {
        final g = gateway(
          responses: [
            () => jsonHttp(
              messagesBody(
                output: modelOutput(
                  adjustments: [
                    {'param': 'exposure', 'value': 7.5, 'reason': 'Way up'},
                    {'param': 'shadows', 'value': 250, 'reason': 'Lift'},
                    {'param': 'temp', 'value': -10, 'reason': 'Cooler'},
                    {'param': 'sparkle', 'value': 5, 'reason': 'Made up'},
                  ],
                ),
              ),
            ),
          ],
        );
        final res = await send(
          g.handler,
          'POST',
          '/v1/auto-edit',
          body: autoEditBody(locked: ['temp']),
        );
        expect(res.statusCode, 200);
        final json = await jsonOf(res);
        expect(json['requestId'], 'req-123');
        expect(json['engine'], 'vision');
        expect(json['model'], 'claude-opus-5-5');
        expect(json['servedBy'], 'claude-opus-5-5');
        expect(json['promptVersion'], kPromptVersion);
        expect(json['cached'], isFalse);
        expect(json['valueMode'], 'absolute');
        expect(_values(json), {'exposure': 5.0, 'shadows': 100.0});
        expect((json['usage']! as Map)['cacheReadTokens'], 3020);

        final userText =
            (((g.upstream.bodyOf(0)['messages']! as List).single
                            as Map)['content']!
                        as List)
                    .last
                as Map;
        expect(userText['text'], contains('Style: Moody'));
        expect(userText['text'], contains('"iso":1600'));
        expect(g.meter.events.single.usage.inputTokens, 4210);
        expect(g.meter.events.single.route, '/v1/auto-edit');
      },
    );

    test(
      'same request twice → second cached:true, one upstream call',
      () async {
        final g = gateway(responses: [() => jsonHttp(messagesBody())]);
        final first = await jsonOf(
          await send(g.handler, 'POST', '/v1/auto-edit', body: autoEditBody()),
        );
        final second = await jsonOf(
          await send(g.handler, 'POST', '/v1/auto-edit', body: autoEditBody()),
        );
        expect(first['cached'], isFalse);
        expect(second['cached'], isTrue);
        expect(second['result'], first['result']);
        expect((second['usage']! as Map)['inputTokens'], 0);
        expect(g.upstream.requests, hasLength(1));
        expect(g.meter.events.map((e) => e.cached), [false, true]);
      },
    );

    test('a different style is a cache miss', () async {
      final g = gateway(
        responses: [
          () => jsonHttp(messagesBody()),
          () => jsonHttp(messagesBody()),
        ],
      );
      await send(g.handler, 'POST', '/v1/auto-edit', body: autoEditBody());
      await send(
        g.handler,
        'POST',
        '/v1/auto-edit',
        body: autoEditBody(style: 'film'),
      );
      expect(g.upstream.requests, hasLength(2));
    });
  });

  group('/v1/instruct', () {
    test('values are deltas clamped against current', () async {
      final g = gateway(
        responses: [
          () => jsonHttp(
            messagesBody(
              output: modelOutput(
                adjustments: [
                  {'param': 'shadows', 'value': 40, 'reason': 'Lift'},
                  {'param': 'temp', 'value': 12, 'reason': 'Warmer'},
                ],
              ),
            ),
          ),
        ],
      );
      final res = await send(
        g.handler,
        'POST',
        '/v1/instruct',
        body: instructBody(current: {'shadows': 90}),
      );
      final json = await jsonOf(res);
      expect(res.statusCode, 200);
      expect(json['valueMode'], 'delta');
      expect(_values(json), {'shadows': 10.0, 'temp': 12.0});
      final text = g.upstream.bodyOf(0).toString();
      expect(text, contains('Mode: refine'));
      expect(text, contains('<instruction>warmer and lift the shadows'));
    });

    test('missing instruction → 400', () async {
      final g = gateway();
      final res = await send(
        g.handler,
        'POST',
        '/v1/instruct',
        body: autoEditBody(),
      );
      await errorOf(res, GatewayErrorCode.invalidRequest);
    });

    test('done:true with no variants is accepted', () async {
      final g = gateway(
        responses: [
          () => jsonHttp(
            messagesBody(
              output: {...modelOutput(done: true), 'variants': <Object?>[]},
            ),
          ),
        ],
      );
      final res = await send(
        g.handler,
        'POST',
        '/v1/instruct',
        body: instructBody(),
      );
      expect(res.statusCode, 200);
      expect(((await jsonOf(res))['result']! as Map)['done'], isTrue);
    });
  });
}
