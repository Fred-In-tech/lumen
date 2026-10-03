import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:lumen_core/lumen_core.dart';
import 'package:lumen_server/lumen_server.dart';
import 'package:test/test.dart';

import '../support/fixtures.dart';

class _ExplodingClaude implements ClaudeClient {
  @override
  Future<MessagesReply> send(MessagesRequest request) =>
      throw StateError('bug in our code');
}

void main() {
  test(
    '400 invalid_request: malformed JSON, missing image, bad base64',
    () async {
      final g = gateway();
      await errorOf(
        await send(g.handler, 'POST', '/v1/auto-edit', body: '{not json'),
        GatewayErrorCode.invalidRequest,
      );
      await errorOf(
        await send(
          g.handler,
          'POST',
          '/v1/auto-edit',
          body: autoEditBody()..remove('image'),
        ),
        GatewayErrorCode.invalidRequest,
      );
      final badImage = autoEditBody();
      (badImage['image']! as Map)['base64'] = '***';
      await errorOf(
        await send(g.handler, 'POST', '/v1/auto-edit', body: badImage),
        GatewayErrorCode.invalidRequest,
      );
      expect(g.upstream.requests, isEmpty);
    },
  );

  test('400 unsupported_contract', () async {
    final g = gateway();
    final error = await errorOf(
      await send(
        g.handler,
        'POST',
        '/v1/auto-edit',
        body: autoEditBody()..['contractVersion'] = 99,
      ),
      GatewayErrorCode.unsupportedContract,
    );
    expect((error['details']! as Map)['supported'], 1);
  });

  test('401 unauthorized with a gateway token; 200 with it', () async {
    final g = gateway(
      config: const GatewayConfig(apiKey: kTestApiKey, gatewayToken: 'tok'),
      responses: [() => jsonHttp(messagesBody())],
    );
    await errorOf(
      await send(g.handler, 'POST', '/v1/auto-edit', body: autoEditBody()),
      GatewayErrorCode.unauthorized,
    );
    final ok = await send(
      g.handler,
      'POST',
      '/v1/auto-edit',
      body: autoEditBody(),
      headers: {'authorization': 'Bearer tok'},
    );
    expect(ok.statusCode, 200);
  });

  test('404 not_found for unknown routes and wrong methods', () async {
    final g = gateway();
    await errorOf(
      await send(g.handler, 'GET', '/v1/nope'),
      GatewayErrorCode.notFound,
    );
    await errorOf(
      await send(g.handler, 'GET', '/v1/auto-edit'),
      GatewayErrorCode.notFound,
    );
  });

  test(
    '413 payload_too_large: body over the limit, image edge > 1568',
    () async {
      final g = gateway(
        config: const GatewayConfig(apiKey: kTestApiKey, maxBodyBytes: 512),
      );
      await errorOf(
        await send(
          g.handler,
          'POST',
          '/v1/auto-edit',
          body: {...autoEditBody(), 'pad': 'x' * 600},
        ),
        GatewayErrorCode.payloadTooLarge,
      );
      final g2 = gateway();
      final error = await errorOf(
        await send(
          g2.handler,
          'POST',
          '/v1/auto-edit',
          body: autoEditBody(width: 2048, height: 1365),
        ),
        GatewayErrorCode.payloadTooLarge,
      );
      expect((error['details']! as Map)['maxLongEdge'], 1568);
    },
  );

  test('422 upstream_refusal carries details.category', () async {
    final g = gateway(
      responses: [
        () => jsonHttp(
          messagesBody(stopReason: 'refusal', stopDetails: {'category': 'x'}),
        ),
      ],
    );
    final res = await send(
      g.handler,
      'POST',
      '/v1/auto-edit',
      body: autoEditBody(),
    );
    final error = await errorOf(res, GatewayErrorCode.upstreamRefusal);
    expect((error['details']! as Map)['category'], 'x');
    expect(error['retryable'], isFalse);
  });

  test('429 rate_limited after the burst', () async {
    final g = gateway(
      config: const GatewayConfig(apiKey: kTestApiKey, burst: 2),
    );
    for (var i = 0; i < 2; i++) {
      await send(g.handler, 'POST', '/v1/auto-edit', body: '{}');
    }
    final res = await send(g.handler, 'POST', '/v1/auto-edit', body: '{}');
    await errorOf(res, GatewayErrorCode.rateLimited);
    expect(res.headers['retry-after'], isNotNull);
  });

  test('429 rate_limited when the upstream queue is full', () async {
    final release = Completer<http.Response>();
    final g = gateway(
      config: const GatewayConfig(
        apiKey: kTestApiKey,
        upstreamConcurrency: 1,
        upstreamQueue: 0,
      ),
      responses: [() => release.future],
    );
    final first = send(
      g.handler,
      'POST',
      '/v1/auto-edit',
      body: autoEditBody(),
    );
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    final busy = await send(
      g.handler,
      'POST',
      '/v1/auto-edit',
      body: autoEditBody(style: 'film'),
    );
    final error = await errorOf(busy, GatewayErrorCode.rateLimited);
    expect((error['details']! as Map)['reason'], 'upstream_queue_full');
    release.complete(jsonHttp(messagesBody()));
    expect((await first).statusCode, 200);
  });

  test('500 internal_error hides internals', () async {
    final handler = buildHandler(
      config: const GatewayConfig(apiKey: kTestApiKey),
      claude: _ExplodingClaude(),
      meter: RecordingMeter(),
    );
    final res = await send(
      handler,
      'POST',
      '/v1/auto-edit',
      body: autoEditBody(),
    );
    final error = await errorOf(res, GatewayErrorCode.internalError);
    expect(error['message'], isNot(contains('bug')));
  });

  test('502 upstream_error after a retried 500', () async {
    final g = gateway(
      responses: [() => jsonHttp({}, 500), () => jsonHttp({}, 500)],
    );
    await errorOf(
      await send(g.handler, 'POST', '/v1/auto-edit', body: autoEditBody()),
      GatewayErrorCode.upstreamError,
    );
    expect(g.sleeps, hasLength(1));
  });

  test('502 upstream_incomplete on max_tokens', () async {
    final g = gateway(
      responses: [() => jsonHttp(messagesBody(stopReason: 'max_tokens'))],
    );
    await errorOf(
      await send(g.handler, 'POST', '/v1/auto-edit', body: autoEditBody()),
      GatewayErrorCode.upstreamIncomplete,
    );
  });

  test(
    '502 upstream_invalid_output on malformed JSON or no variants',
    () async {
      final g = gateway(
        responses: [
          () => jsonHttp(messagesBody(text: '{"variants": [')),
          () => jsonHttp(
            messagesBody(output: {'intent': 'x', 'variants': <Object?>[]}),
          ),
        ],
      );
      await errorOf(
        await send(g.handler, 'POST', '/v1/auto-edit', body: autoEditBody()),
        GatewayErrorCode.upstreamInvalidOutput,
      );
      await errorOf(
        await send(
          g.handler,
          'POST',
          '/v1/auto-edit',
          body: autoEditBody(style: 'film'),
        ),
        GatewayErrorCode.upstreamInvalidOutput,
      );
    },
  );

  test('503 vision_unavailable without a key (no upstream call)', () async {
    final g = gateway(config: const GatewayConfig());
    for (final path in ['/v1/auto-edit', '/v1/instruct']) {
      await errorOf(
        await send(g.handler, 'POST', path, body: instructBody()),
        GatewayErrorCode.visionUnavailable,
      );
    }
    expect(g.upstream.requests, isEmpty);
  });

  test('504 upstream_timeout', () async {
    final never = Completer<http.Response>();
    final g = gateway(
      responses: [() => never.future],
      timeout: const Duration(milliseconds: 50),
    );
    await errorOf(
      await send(g.handler, 'POST', '/v1/auto-edit', body: autoEditBody()),
      GatewayErrorCode.upstreamTimeout,
    );
  });

  test('every error response carries x-request-id and CORS headers', () async {
    final g = gateway(config: const GatewayConfig());
    final res = await send(g.handler, 'POST', '/v1/auto-edit', body: '{}');
    expect(res.headers['x-request-id'], isNotEmpty);
    expect(res.headers['access-control-allow-origin'], '*');
    final json = await jsonOf(res);
    expect(json['requestId'], res.headers['x-request-id']);
    expect((json['error']! as Map)['code'], 'vision_unavailable');
  });
}
