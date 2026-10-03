import 'package:lumen_server/lumen_server.dart';
import 'package:test/test.dart';

void main() {
  test('defaults match the plan', () {
    final c = GatewayConfig.fromEnv(const {});
    expect(c.apiKey, isNull);
    expect(c.visionAvailable, isFalse);
    expect(c.model, 'claude-opus-5-5');
    expect(c.effort, 'low');
    expect(c.port, 8080);
    expect(c.gatewayToken, isNull);
    expect(c.ratePerMinute, 20);
    expect(c.burst, 5);
    expect(c.maxBodyBytes, 4194304);
    expect(c.upstreamConcurrency, 4);
    expect(c.upstreamQueue, 16);
    expect(c.upstreamTimeout, const Duration(seconds: 90));
    expect(c.messagesUri.toString(), 'https://api.anthropic.com/v1/messages');
  });

  test('reads every variable', () {
    final c = GatewayConfig.fromEnv(const {
      'ANTHROPIC_API_KEY': 'k',
      'LUMEN_MODEL': 'claude-haiku-4-5',
      'LUMEN_EFFORT': 'medium',
      'PORT': '9000',
      'LUMEN_GATEWAY_TOKEN': 'tok',
      'LUMEN_RPM': '60',
      'LUMEN_BURST': '10',
      'LUMEN_MAX_BODY_BYTES': '1000',
      'LUMEN_UPSTREAM_CONCURRENCY': '2',
      'ANTHROPIC_BASE_URL': 'http://localhost:9999/',
      'LUMEN_TRUST_PROXY': '1',
    });
    expect(c.visionAvailable, isTrue);
    expect(c.model, 'claude-haiku-4-5');
    expect(c.effort, 'medium');
    expect(c.port, 9000);
    expect(c.gatewayToken, 'tok');
    expect(c.ratePerMinute, 60);
    expect(c.burst, 10);
    expect(c.maxBodyBytes, 1000);
    expect(c.upstreamConcurrency, 2);
    expect(c.trustProxy, isTrue);
    expect(c.messagesUri.toString(), 'http://localhost:9999/v1/messages');
  });

  test('blank key means no vision', () {
    expect(
      GatewayConfig.fromEnv(const {'ANTHROPIC_API_KEY': '  '}).visionAvailable,
      isFalse,
    );
  });

  test('malformed values fail fast', () {
    for (final env in [
      {'PORT': 'abc'},
      {'LUMEN_RPM': '0'},
      {'LUMEN_EFFORT': 'turbo'},
      {'ANTHROPIC_BASE_URL': 'not a url'},
    ]) {
      expect(
        () => GatewayConfig.fromEnv(env),
        throwsA(isA<ConfigException>()),
        reason: '$env',
      );
    }
  });

  test('toString never reveals secrets', () {
    final c = GatewayConfig.fromEnv(const {
      'ANTHROPIC_API_KEY': 'super-secret-value',
      'LUMEN_GATEWAY_TOKEN': 'other-secret',
    });
    expect(c.toString(), isNot(contains('super-secret-value')));
    expect(c.toString(), isNot(contains('other-secret')));
  });
}
