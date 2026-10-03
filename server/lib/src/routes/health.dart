import 'package:lumen_core/lumen_core.dart';
import 'package:shelf/shelf.dart';

import '../config.dart';
import '../prompt/system_prompt.dart';
import '../support.dart';

/// `GET /v1/health`: liveness + capability. Never requires auth.
Handler healthHandler(GatewayConfig config) => (Request request) {
  final health = HealthResponse(
    status: 'ok',
    version: kServerVersion,
    visionAvailable: config.visionAvailable,
    model: config.visionAvailable ? config.model : null,
    promptVersion: kPromptVersion,
  );
  return jsonResponse(200, health.toJson());
};
