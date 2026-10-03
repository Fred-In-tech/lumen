import 'package:lumen_server/lumen_server.dart';
import 'package:test/test.dart';

import '../support/fixtures.dart';

void main() {
  test('no key → visionAvailable:false, model null', () async {
    final g = gateway(config: const GatewayConfig());
    final res = await send(g.handler, 'GET', '/v1/health');
    expect(res.statusCode, 200);
    expect(res.headers['x-request-id'], isNotEmpty);
    expect(await jsonOf(res), {
      'status': 'ok',
      'version': '1.0.0',
      'contractVersion': 1,
      'visionAvailable': false,
      'model': null,
      'promptVersion': kPromptVersion,
    });
  });

  test('key → visionAvailable:true with the configured model', () async {
    final g = gateway(
      config: const GatewayConfig(
        apiKey: kTestApiKey,
        model: 'claude-haiku-4-5',
      ),
    );
    final json = await jsonOf(await send(g.handler, 'GET', '/v1/health'));
    expect(json['visionAvailable'], isTrue);
    expect(json['model'], 'claude-haiku-4-5');
  });

  test('health is public even when a gateway token is set', () async {
    final g = gateway(
      config: const GatewayConfig(apiKey: kTestApiKey, gatewayToken: 't'),
    );
    expect((await send(g.handler, 'GET', '/v1/health')).statusCode, 200);
  });
}
