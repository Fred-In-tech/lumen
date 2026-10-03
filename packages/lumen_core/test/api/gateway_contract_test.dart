import 'dart:convert';

import 'package:lumen_core/lumen_core.dart';
import 'package:test/test.dart';

AutoEditRequest _request() => const AutoEditRequest(
  requestId: 'req-1',
  client: ClientInfo(app: 'lumen', version: '1.0.0', platform: 'macos'),
  style: GatewayStyle.moody,
  variants: 1,
  image: ImagePayload(
    mime: 'image/jpeg',
    width: 1024,
    height: 683,
    base64: 'AAAA',
  ),
  stats: {
    'lumaP': {'p50': 0.18},
    'clipPct': 0.1,
  },
  exif: ExifSummary(camera: 'X100V', iso: 1600, aperture: 2),
  baseline: {P.exposure: 0.62, P.shadows: 31},
  current: {},
  locked: [P.temp],
);

/// Encode → decode through a real JSON string, as the wire does.
Object? _wire(Object? json) => jsonDecode(jsonEncode(json));

void main() {
  test('contract version is 1', () {
    expect(kContractVersion, 1);
  });

  group('AutoEditRequest', () {
    test('round-trips through JSON', () {
      final r = _request();
      final back = AutoEditRequest.fromJson(_wire(r.toJson()));
      expect(back.toJson(), r.toJson());
      expect(r.toJson()['contractVersion'], 1);
      expect(r.toJson()['style'], 'moody');
      expect(back.exif?.iso, 1600);
      expect(back.locked, [P.temp]);
    });

    test('rejects an unknown contractVersion', () {
      final json = _request().toJson()..['contractVersion'] = 2;
      expect(
        () => AutoEditRequest.fromJson(json),
        throwsA(
          isA<ContractViolation>().having(
            (e) => e.code,
            'code',
            GatewayErrorCode.unsupportedContract,
          ),
        ),
      );
    });

    test('rejects missing image, bad style, bad mime, bad stats', () {
      for (final mutate in <void Function(Map<String, Object?>)>[
        (j) => j.remove('image'),
        (j) => j['style'] = 'psychedelic',
        (j) => (j['image']! as Map)['mime'] = 'image/gif',
        (j) => (j['image']! as Map)['base64'] = '',
        (j) => j['stats'] = 'high',
        (j) => j['locked'] = 'temp',
      ]) {
        final json = _wire(_request().toJson())! as Map<String, Object?>;
        mutate(json);
        expect(
          () => AutoEditRequest.fromJson(json),
          throwsA(
            isA<ContractViolation>().having(
              (e) => e.code,
              'code',
              GatewayErrorCode.invalidRequest,
            ),
          ),
        );
      }
      expect(
        () => AutoEditRequest.fromJson('x'),
        throwsA(isA<ContractViolation>()),
      );
    });

    test('drops unknown param ids from baseline/current/locked and clamps '
        'variants to 1..3', () {
      final json = _wire(_request().toJson())! as Map<String, Object?>;
      json['baseline'] = {'exposure': 9, 'bogus': 1};
      json['locked'] = ['temp', 'bogus'];
      json['variants'] = 7;
      final r = AutoEditRequest.fromJson(json);
      expect(r.baseline, {P.exposure: 5.0});
      expect(r.locked, [P.temp]);
      expect(r.variants, 3);
    });

    test('image long edge helper', () {
      expect(_request().image.longEdge, 1024);
    });
  });

  group('InstructRequest', () {
    test('round-trips and requires an instruction', () {
      final r = InstructRequest(
        request: _request(),
        instruction: 'warmer and lift the shadows a bit',
      );
      final json = r.toJson();
      expect(json['instruction'], 'warmer and lift the shadows a bit');
      expect(json['style'], 'moody');
      final back = InstructRequest.fromJson(_wire(json));
      expect(back.toJson(), json);

      final blank = _wire(json)! as Map<String, Object?>;
      blank['instruction'] = '   ';
      expect(
        () => InstructRequest.fromJson(blank),
        throwsA(isA<ContractViolation>()),
      );
      final long = _wire(json)! as Map<String, Object?>;
      long['instruction'] = 'a' * (kMaxInstructionChars + 1);
      expect(
        () => InstructRequest.fromJson(long),
        throwsA(isA<ContractViolation>()),
      );
    });
  });

  group('responses', () {
    test('HealthResponse round-trips', () {
      const h = HealthResponse(
        status: 'ok',
        version: '1.0.0',
        visionAvailable: true,
        model: 'claude-opus-5-5',
        promptVersion: '2026-10-03.1',
      );
      final back = HealthResponse.fromJson(_wire(h.toJson()));
      expect(back.toJson(), h.toJson());
      expect(h.toJson()['contractVersion'], 1);
      expect(HealthResponse.fromJson({}).visionAvailable, isFalse);
    });

    test('GatewayEditResponse round-trips', () {
      final resp = GatewayEditResponse(
        requestId: 'req-1',
        model: 'claude-opus-5-5',
        servedBy: 'claude-opus-5-5',
        promptVersion: 'p1',
        cached: false,
        latencyMs: 5400,
        valueMode: ValueMode.absolute,
        result: AutoEditResponse.fromJson({
          'intent': 'x',
          'variants': [
            {
              'label': 'A',
              'confidence': 0.5,
              'adjustments': [
                {'param': 'shadows', 'value': 28, 'reason': 'r'},
              ],
            },
          ],
        }),
        usage: const GatewayUsage(
          inputTokens: 4210,
          outputTokens: 612,
          cacheReadTokens: 3020,
          cacheWriteTokens: 0,
          fallbackUsed: false,
        ),
      );
      final json = resp.toJson();
      expect(json['engine'], 'vision');
      expect(json['valueMode'], 'absolute');
      final back = GatewayEditResponse.fromJson(_wire(json));
      expect(back.toJson(), json);
      expect(back.copyWith(cached: true).cached, isTrue);
    });

    test('error envelope round-trips; codes map to HTTP status', () {
      const e = GatewayErrorEnvelope(
        requestId: 'r',
        error: GatewayError(
          code: GatewayErrorCode.rateLimited,
          message: 'slow down',
          retryAfterMs: 1500,
        ),
      );
      final json = e.toJson();
      expect((json['error']! as Map)['code'], 'rate_limited');
      expect((json['error']! as Map)['retryable'], isTrue);
      final back = GatewayErrorEnvelope.fromJson(_wire(json));
      expect(back.toJson(), json);

      const expected = {
        'invalid_request': 400,
        'unsupported_contract': 400,
        'unauthorized': 401,
        'not_found': 404,
        'payload_too_large': 413,
        'upstream_refusal': 422,
        'rate_limited': 429,
        'internal_error': 500,
        'upstream_error': 502,
        'upstream_incomplete': 502,
        'upstream_invalid_output': 502,
        'vision_unavailable': 503,
        'upstream_timeout': 504,
      };
      expect({
        for (final c in GatewayErrorCode.values) c.wire: c.httpStatus,
      }, expected);
      expect(GatewayErrorCode.fromWire('???'), GatewayErrorCode.internalError);
    });
  });

  test('GatewayStyle wire names and labels', () {
    expect(GatewayStyle.values, hasLength(9));
    expect(GatewayStyle.cleanBright.wire, 'clean_bright');
    expect(GatewayStyle.fromWire('golden_hour'), GatewayStyle.goldenHour);
    expect(GatewayStyle.fromWire('nope'), isNull);
    expect(GatewayStyle.bw.label, 'B&W');
  });
}
