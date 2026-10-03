import 'dart:async';
import 'dart:convert';

import 'package:lumen_core/lumen_core.dart';
import 'package:lumen_server/src/middleware/auth.dart';
import 'package:lumen_server/src/middleware/body_limit.dart';
import 'package:lumen_server/src/middleware/cors.dart';
import 'package:lumen_server/src/middleware/error_envelope.dart';
import 'package:lumen_server/src/middleware/rate_limit.dart';
import 'package:lumen_server/src/middleware/request_id.dart';
import 'package:lumen_server/src/support.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import '../support/fixtures.dart';

Response _ok(Request r) => Response.ok('ok');

Handler _wrap(Middleware m, [Handler inner = _ok]) => const Pipeline()
    .addMiddleware(errorEnvelope())
    .addMiddleware(m)
    .addHandler(inner);

Request _req(
  String path, {
  String method = 'GET',
  Map<String, String> headers = const {},
  Object? body,
}) => Request(
  method,
  Uri.parse('http://localhost$path'),
  headers: headers,
  body: body,
);

void main() {
  group('request id', () {
    final handler = const Pipeline()
        .addMiddleware(requestId())
        .addHandler((r) => Response.ok(requestIdOf(r)));

    test('generates one when absent and echoes it', () async {
      final res = await handler(_req('/x'));
      final id = res.headers[kRequestIdHeader]!;
      expect(id, matches(RegExp(r'^[0-9a-f]{24}$')));
      expect(await res.readAsString(), id);
    });

    test('keeps a well-formed incoming id, replaces a hostile one', () async {
      final kept = await handler(
        _req('/x', headers: {kRequestIdHeader: 'abc-123'}),
      );
      expect(kept.headers[kRequestIdHeader], 'abc-123');
      final replaced = await handler(
        _req('/x', headers: {kRequestIdHeader: 'bad id\nInjected: 1'}),
      );
      expect(replaced.headers[kRequestIdHeader], isNot(contains('bad')));
    });
  });

  group('error envelope', () {
    test('renders GatewayException with retry-after', () async {
      final h = _wrap(
        (inner) =>
            (r) => throw const GatewayException(
              GatewayErrorCode.rateLimited,
              'slow',
              retryAfter: Duration(milliseconds: 1500),
            ),
      );
      final res = await h(_req('/x'));
      final error = await errorOf(res, GatewayErrorCode.rateLimited);
      expect(error['retryAfterMs'], 1500);
      expect(error['retryable'], isTrue);
      expect(res.headers['retry-after'], '2');
    });

    test('renders ContractViolation as 400', () async {
      final h = _wrap(
        (inner) =>
            (r) => throw const ContractViolation('bad'),
      );
      await errorOf(await h(_req('/x')), GatewayErrorCode.invalidRequest);
    });

    test('hides unexpected errors behind a generic 500', () async {
      final h = _wrap(
        (inner) =>
            (r) => throw StateError('db password=xyz'),
      );
      final res = await h(_req('/x'));
      final error = await errorOf(res, GatewayErrorCode.internalError);
      expect(error['message'], isNot(contains('xyz')));
    });
  });

  group('CORS', () {
    final h = const Pipeline().addMiddleware(cors()).addHandler(_ok);

    test('answers preflight with 204 and allow headers', () async {
      final res = await h(_req('/v1/auto-edit', method: 'OPTIONS'));
      expect(res.statusCode, 204);
      expect(res.headers['access-control-allow-origin'], '*');
      expect(
        res.headers['access-control-allow-headers'],
        contains('authorization'),
      );
    });

    test('decorates normal responses and exposes the request id', () async {
      final res = await h(_req('/x'));
      expect(res.headers['access-control-allow-origin'], '*');
      expect(
        res.headers['access-control-expose-headers'],
        contains(kRequestIdHeader),
      );
    });
  });

  group('bearer auth', () {
    final h = _wrap(bearerAuth('s3cret', publicPaths: {GatewayPaths.health}));

    test('no token configured lets everything through', () async {
      final open = _wrap(bearerAuth(null));
      expect((await open(_req('/v1/auto-edit'))).statusCode, 200);
    });

    test('missing or wrong token is 401', () async {
      await errorOf(
        await h(_req('/v1/auto-edit')),
        GatewayErrorCode.unauthorized,
      );
      await errorOf(
        await h(
          _req('/v1/auto-edit', headers: {'authorization': 'Bearer nope'}),
        ),
        GatewayErrorCode.unauthorized,
      );
      await errorOf(
        await h(_req('/v1/auto-edit', headers: {'authorization': 's3cret'})),
        GatewayErrorCode.unauthorized,
      );
    });

    test('right token (any case scheme) passes; health is public', () async {
      final res = await h(
        _req('/v1/auto-edit', headers: {'authorization': 'bearer s3cret'}),
      );
      expect(res.statusCode, 200);
      expect((await h(_req(GatewayPaths.health))).statusCode, 200);
    });

    test('constantTimeEquals', () {
      expect(constantTimeEquals('abc', 'abc'), isTrue);
      expect(constantTimeEquals('abc', 'abd'), isFalse);
      expect(constantTimeEquals('abc', 'abcd'), isFalse);
    });
  });

  group('rate limit', () {
    late FakeClock clock;
    late Handler h;

    setUp(() {
      clock = FakeClock();
      final limiter = TokenBucketLimiter(
        ratePerMinute: 20,
        burst: 5,
        clock: clock,
      );
      h = _wrap(
        rateLimit(limiter, trustProxy: true, exemptPaths: {'/v1/health'}),
      );
    });

    Future<Response> hit([String ip = '1.1.1.1']) => Future.value(
      h(_req('/v1/auto-edit', headers: {'x-forwarded-for': ip})),
    );

    test('burst of 5, then 429 with Retry-After; refills over time', () async {
      for (var i = 0; i < 5; i++) {
        expect((await hit()).statusCode, 200, reason: 'request $i');
      }
      final limited = await hit();
      final error = await errorOf(limited, GatewayErrorCode.rateLimited);
      expect(error['retryAfterMs'], 3000); // 20/min = one token per 3 s
      expect(limited.headers['retry-after'], '3');

      clock.advance(const Duration(seconds: 3));
      expect((await hit()).statusCode, 200);
      expect((await hit()).statusCode, 429);
    });

    test('keys are independent; health is exempt', () async {
      for (var i = 0; i < 5; i++) {
        await hit('1.1.1.1');
      }
      expect((await hit('1.1.1.1')).statusCode, 429);
      expect((await hit('2.2.2.2')).statusCode, 200);
      for (var i = 0; i < 10; i++) {
        expect((await h(_req('/v1/health'))).statusCode, 200);
      }
    });

    test('ignores x-forwarded-for unless trustProxy', () {
      final r = _req('/x', headers: {'x-forwarded-for': '9.9.9.9'});
      expect(clientKeyOf(r), 'unknown');
      expect(clientKeyOf(r, trustProxy: true), '9.9.9.9');
    });
  });

  group('body limit', () {
    final h = _wrap(
      bodyLimit(10),
      (r) async => Response.ok(await r.readAsString()),
    );

    test('small bodies pass through intact', () async {
      final res = await h(_req('/x', method: 'POST', body: 'hello'));
      expect(await res.readAsString(), 'hello');
    });

    test('declared content-length over the limit is 413', () async {
      final res = await h(_req('/x', method: 'POST', body: 'x' * 11));
      final error = await errorOf(res, GatewayErrorCode.payloadTooLarge);
      expect((error['details']! as Map)['maxBytes'], 10);
    });

    test('chunked body over the limit is 413 while streaming', () async {
      final stream = Stream<List<int>>.fromIterable([
        utf8.encode('123456'),
        utf8.encode('789012'),
      ]);
      final res = await h(_req('/x', method: 'POST', body: stream));
      await errorOf(res, GatewayErrorCode.payloadTooLarge);
    });
  });
}
