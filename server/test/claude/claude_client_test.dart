import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:lumen_core/lumen_core.dart';
import 'package:lumen_server/lumen_server.dart';
import 'package:test/test.dart';

import '../support/fixtures.dart';

MessagesRequest _request({String model = 'claude-opus-5-5'}) => MessagesRequest(
  model: model,
  effort: 'low',
  maxTokens: 16000,
  systemPrompt: kSystemPrompt,
  schema: AutoEditResponseSchema.build(),
  imageMime: 'image/jpeg',
  imageBase64: 'AAAA',
  userText: 'Image 1: photo to edit.',
);

({HttpClaudeClient client, ScriptedUpstream upstream, List<Duration> sleeps})
_client(
  List<FutureOr<http.Response> Function()> responses, {
  Duration timeout = const Duration(seconds: 90),
}) {
  final upstream = ScriptedUpstream(responses);
  final sleeps = <Duration>[];
  final client = HttpClaudeClient(
    apiKey: kTestApiKey,
    messagesUri: Uri.parse('https://api.anthropic.com/v1/messages'),
    httpClient: upstream.client,
    timeout: timeout,
    sleep: (d) async => sleeps.add(d),
  );
  return (client: client, upstream: upstream, sleeps: sleeps);
}

Matcher _throwsCode(GatewayErrorCode code) =>
    throwsA(isA<GatewayException>().having((e) => e.code, 'code', code));

void main() {
  group('request shape', () {
    test('exact headers and body for Opus 5.5', () async {
      final c = _client([() => jsonHttp(messagesBody())]);
      await c.client.send(_request());
      final req = c.upstream.requests.single;
      expect(req.method, 'POST');
      expect(req.url.toString(), 'https://api.anthropic.com/v1/messages');
      expect(req.headers['x-api-key'], kTestApiKey);
      expect(req.headers['anthropic-version'], '2023-06-01');
      expect(req.headers['anthropic-beta'], 'server-side-fallback-2026-07-01');
      expect(req.headers['content-type'], startsWith('application/json'));

      final body = c.upstream.bodyOf(0);
      expect(body['model'], 'claude-opus-5-5');
      expect(body['max_tokens'], 16000);
      expect(body['fallbacks'], 'default');
      final system = (body['system']! as List).single as Map;
      expect(system['type'], 'text');
      expect(system['text'], kSystemPrompt);
      expect(system['cache_control'], {'type': 'ephemeral'});

      final message = (body['messages']! as List).single as Map;
      expect(message['role'], 'user');
      final content = message['content']! as List;
      expect([for (final b in content) (b as Map)['type']], ['image', 'text']);
      expect((content.first as Map)['source'], {
        'type': 'base64',
        'media_type': 'image/jpeg',
        'data': 'AAAA',
      });

      final output = body['output_config']! as Map;
      expect((output['format']! as Map)['type'], 'json_schema');
      expect((output['format']! as Map)['schema'], isA<Map<String, Object?>>());
      expect(output['effort'], 'low');

      for (final banned in [
        'temperature',
        'top_p',
        'tool_choice',
        'thinking',
      ]) {
        expect(body.containsKey(banned), isFalse, reason: banned);
      }
      expect((body['messages']! as List).length, 1, reason: 'no prefill');
    });

    test('haiku gets no fallbacks field and no beta header', () async {
      final c = _client([() => jsonHttp(messagesBody())]);
      await c.client.send(_request(model: 'claude-haiku-4-5'));
      expect(c.upstream.requests.single.headers['anthropic-beta'], isNull);
      expect(c.upstream.bodyOf(0).containsKey('fallbacks'), isFalse);
    });
  });

  group('response handling', () {
    test(
      'skips thinking and fallback blocks; reads usage and servedBy',
      () async {
        final c = _client([
          () => jsonHttp(
            messagesBody(
              model: 'claude-sonnet-5-5',
              extraBlocksBefore: [
                {'type': 'thinking', 'thinking': 'hmm', 'signature': 's'},
                {'type': 'fallback', 'from': 'claude-opus-5-5'},
              ],
              iterations: [
                {'type': 'message', 'input_tokens': 10},
                {'type': 'fallback_message', 'input_tokens': 20},
              ],
            ),
          ),
        ]);
        final reply = await c.client.send(_request());
        expect(reply.decodeJson()['intent'], isNotEmpty);
        expect(reply.servedBy, 'claude-sonnet-5-5');
        expect(reply.usage.inputTokens, 4210);
        expect(reply.usage.outputTokens, 612);
        expect(reply.usage.cacheReadTokens, 3020);
        expect(reply.usage.fallbackUsed, isTrue);
      },
    );

    test('refusal → upstream_refusal with category (or null)', () async {
      final c = _client([
        () => jsonHttp(
          messagesBody(
            stopReason: 'refusal',
            stopDetails: {'type': 'refusal', 'category': 'cyber'},
          ),
        ),
        () => jsonHttp(messagesBody(stopReason: 'refusal')),
      ]);
      await expectLater(
        c.client.send(_request()),
        throwsA(
          isA<GatewayException>()
              .having((e) => e.code, 'code', GatewayErrorCode.upstreamRefusal)
              .having((e) => e.details['category'], 'category', 'cyber'),
        ),
      );
      await expectLater(
        c.client.send(_request()),
        throwsA(
          isA<GatewayException>().having(
            (e) => e.details['category'],
            'category',
            isNull,
          ),
        ),
      );
    });

    test('max_tokens → upstream_incomplete', () async {
      final c = _client([
        () => jsonHttp(messagesBody(stopReason: 'max_tokens')),
      ]);
      await expectLater(
        c.client.send(_request()),
        _throwsCode(GatewayErrorCode.upstreamIncomplete),
      );
    });

    test('non-JSON text → upstream_invalid_output', () async {
      final c = _client([
        () => jsonHttp(messagesBody(text: 'Sure! Here are my edits: ...')),
      ]);
      final reply = await c.client.send(_request());
      expect(
        reply.decodeJson,
        _throwsCode(GatewayErrorCode.upstreamInvalidOutput),
      );
    });

    test(
      'no text block or a non-JSON body → upstream_invalid_output',
      () async {
        final c = _client([
          () => jsonHttp({
            'model': 'claude-opus-5-5',
            'stop_reason': 'end_turn',
            'content': [
              {'type': 'thinking', 'thinking': '...'},
            ],
          }),
          () => http.Response('<html>oops</html>', 200),
        ]);
        await expectLater(
          c.client.send(_request()),
          _throwsCode(GatewayErrorCode.upstreamInvalidOutput),
        );
        await expectLater(
          c.client.send(_request()),
          _throwsCode(GatewayErrorCode.upstreamInvalidOutput),
        );
      },
    );
  });

  group('retries and timeouts', () {
    test('429 retried once honoring retry-after', () async {
      final c = _client([
        () => jsonHttp({}, 429, {'retry-after': '2'}),
        () => jsonHttp(messagesBody()),
      ]);
      await c.client.send(_request());
      expect(c.upstream.requests, hasLength(2));
      expect(c.sleeps, [const Duration(seconds: 2)]);
    });

    test('529 overloaded is retried', () async {
      final c = _client([
        () => jsonHttp({}, 529),
        () => jsonHttp(messagesBody()),
      ]);
      await c.client.send(_request());
      expect(c.sleeps, [const Duration(seconds: 1)]);
    });

    test('500 twice → upstream_error after exactly one retry', () async {
      final c = _client([
        () => jsonHttp({
          'type': 'error',
          'error': {'type': 'api_error'},
        }, 500),
        () => jsonHttp({
          'type': 'error',
          'error': {'type': 'api_error'},
        }, 500),
      ]);
      await expectLater(
        c.client.send(_request()),
        throwsA(
          isA<GatewayException>()
              .having((e) => e.code, 'code', GatewayErrorCode.upstreamError)
              .having((e) => e.details['upstreamType'], 'type', 'api_error'),
        ),
      );
      expect(c.upstream.requests, hasLength(2));
    });

    test('429 twice → rate_limited with retry hint', () async {
      final c = _client([
        () => jsonHttp({}, 429, {'retry-after': '5'}),
        () => jsonHttp({}, 429, {'retry-after': '7'}),
      ]);
      await expectLater(
        c.client.send(_request()),
        throwsA(
          isA<GatewayException>()
              .having((e) => e.code, 'code', GatewayErrorCode.rateLimited)
              .having(
                (e) => e.retryAfter,
                'retryAfter',
                const Duration(seconds: 7),
              ),
        ),
      );
    });

    test('400 is not retried', () async {
      final c = _client([() => jsonHttp({}, 400)]);
      await expectLater(
        c.client.send(_request()),
        _throwsCode(GatewayErrorCode.upstreamError),
      );
      expect(c.upstream.requests, hasLength(1));
    });

    test('network error retried, then upstream_error', () async {
      final c = _client([
        () => throw http.ClientException('connection reset'),
        () => throw http.ClientException('connection reset'),
      ]);
      await expectLater(
        c.client.send(_request()),
        _throwsCode(GatewayErrorCode.upstreamError),
      );
      expect(c.upstream.requests, hasLength(2));
    });

    test('no answer within the deadline → upstream_timeout', () async {
      final never = Completer<http.Response>();
      final c = _client([
        () => never.future,
      ], timeout: const Duration(milliseconds: 50));
      await expectLater(
        c.client.send(_request()),
        _throwsCode(GatewayErrorCode.upstreamTimeout),
      );
    });
  });

  test('request JSON is encodable as-is', () {
    expect(() => jsonEncode(_request().toJson()), returnsNormally);
  });
}
