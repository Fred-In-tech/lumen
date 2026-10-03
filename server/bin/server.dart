import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:lumen_server/lumen_server.dart';
import 'package:shelf/shelf_io.dart';

/// GatewayConfig.fromEnv → buildHandler → serve(PORT).
Future<void> main(List<String> args) async {
  Logger.root.level = Level.INFO;
  Logger.root.onRecord.listen((r) {
    final error = r.error == null ? '' : ' ${r.error}';
    stdout.writeln(
      '${r.time.toIso8601String()} ${r.level.name} '
      '${r.loggerName}: ${r.message}$error',
    );
  });
  final log = Logger('lumen.server');

  final GatewayConfig config;
  try {
    config = GatewayConfig.fromEnv(Platform.environment);
  } on ConfigException catch (e) {
    log.severe(e.message);
    exitCode = 64;
    return;
  }

  final httpClient = http.Client();
  final handler = buildHandler(
    config: config,
    claude: createClaudeClient(config, httpClient),
  );
  final server = await serve(handler, InternetAddress.anyIPv4, config.port);
  log.info('Listening on port ${server.port} with $config');
  if (!config.visionAvailable) {
    log.warning('ANTHROPIC_API_KEY not set: vision routes answer 503');
  }

  Future<void> shutdown(ProcessSignal signal) async {
    log.info('Received $signal, shutting down');
    await server.close();
    httpClient.close();
    exit(0);
  }

  ProcessSignal.sigint.watch().listen(shutdown);
  if (!Platform.isWindows) ProcessSignal.sigterm.watch().listen(shutdown);
}
