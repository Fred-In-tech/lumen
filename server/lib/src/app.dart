/// Composes the gateway: middleware pipeline + routes.
library;

import 'package:http/http.dart' as http;
import 'package:lumen_core/lumen_core.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'cache/result_cache.dart';
import 'claude/claude_client.dart';
import 'claude/messages_request.dart';
import 'claude/messages_response.dart';
import 'config.dart';
import 'edit/edit_service.dart';
import 'edit/upstream_gate.dart';
import 'metering/usage_meter.dart';
import 'middleware/auth.dart';
import 'middleware/body_limit.dart';
import 'middleware/cors.dart';
import 'middleware/error_envelope.dart';
import 'middleware/rate_limit.dart';
import 'middleware/request_id.dart';
import 'routes/auto_edit.dart';
import 'routes/health.dart';
import 'routes/instruct.dart';
import 'support.dart';

const Set<String> _publicPaths = {GatewayPaths.health};

/// Used when no API key is configured; edit routes answer 503 before ever
/// reaching it.
class UnavailableClaudeClient implements ClaudeClient {
  const UnavailableClaudeClient();

  @override
  Future<MessagesReply> send(MessagesRequest request) =>
      throw const GatewayException(
        GatewayErrorCode.visionUnavailable,
        'Vision editing is not configured on this gateway',
      );
}

/// Real client for [config], or [UnavailableClaudeClient] without a key.
ClaudeClient createClaudeClient(GatewayConfig config, http.Client client) {
  final key = config.apiKey;
  if (key == null || key.isEmpty) return const UnavailableClaudeClient();
  return HttpClaudeClient(
    apiKey: key,
    messagesUri: config.messagesUri,
    httpClient: client,
    timeout: config.upstreamTimeout,
  );
}

/// request id → CORS → error envelope → auth → rate limit → body limit →
/// routes.
Handler buildHandler({
  required GatewayConfig config,
  required ClaudeClient claude,
  Clock clock = const SystemClock(),
  UsageMeter? meter,
  ResultCache? cache,
}) {
  final service = EditService(
    config: config,
    claude: claude,
    cache: cache ?? ResultCache(capacity: config.cacheSize),
    meter: meter ?? LogUsageMeter(),
    gate: UpstreamGate(
      concurrency: config.upstreamConcurrency,
      maxQueue: config.upstreamQueue,
    ),
    clock: clock,
  );
  final limiter = TokenBucketLimiter(
    ratePerMinute: config.ratePerMinute,
    burst: config.burst,
    clock: clock,
  );
  final router = Router(notFoundHandler: _notFound)
    ..get(GatewayPaths.health, healthHandler(config))
    ..post(GatewayPaths.autoEdit, autoEditHandler(service))
    ..post(GatewayPaths.instruct, instructHandler(service));

  return const Pipeline()
      .addMiddleware(requestId())
      .addMiddleware(cors(origin: config.corsOrigin))
      .addMiddleware(errorEnvelope())
      .addMiddleware(bearerAuth(config.gatewayToken, publicPaths: _publicPaths))
      .addMiddleware(
        rateLimit(
          limiter,
          trustProxy: config.trustProxy,
          exemptPaths: _publicPaths,
        ),
      )
      .addMiddleware(bodyLimit(config.maxBodyBytes))
      .addHandler(router.call);
}

Response _notFound(Request request) => throw GatewayException(
  GatewayErrorCode.notFound,
  'No route for ${request.method} ${pathOf(request)}',
);
