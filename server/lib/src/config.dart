/// Gateway configuration, read once from the environment at startup.
///
/// The Anthropic API key only ever comes from `ANTHROPIC_API_KEY`; it is never
/// logged ([toString] redacts it).
library;

const String kDefaultModel = 'claude-opus-5-5';
const String kDefaultEffort = 'low';
const String kDefaultAnthropicBaseUrl = 'https://api.anthropic.com';
const String kServerVersion = '1.0.0';
const Set<String> kAllowedEfforts = {'low', 'medium', 'high', 'xhigh', 'max'};

class ConfigException implements Exception {
  const ConfigException(this.message);
  final String message;

  @override
  String toString() => 'ConfigException: $message';
}

class GatewayConfig {
  const GatewayConfig({
    this.apiKey,
    this.model = kDefaultModel,
    this.effort = kDefaultEffort,
    this.port = 8080,
    this.gatewayToken,
    this.ratePerMinute = 20,
    this.burst = 5,
    this.maxBodyBytes = 4194304,
    this.upstreamConcurrency = 4,
    this.upstreamQueue = 16,
    this.anthropicBaseUrl = kDefaultAnthropicBaseUrl,
    this.upstreamTimeout = const Duration(seconds: 90),
    this.maxTokens = 16000,
    this.cacheSize = 256,
    this.trustProxy = false,
    this.corsOrigin = '*',
  });

  /// Throws [ConfigException] on malformed values (fail fast at startup).
  factory GatewayConfig.fromEnv(Map<String, String> env) {
    String? str(String k) {
      final v = env[k]?.trim();
      return v == null || v.isEmpty ? null : v;
    }

    int integer(String k, int fallback, {int min = 1}) {
      final raw = str(k);
      if (raw == null) return fallback;
      final v = int.tryParse(raw);
      if (v == null || v < min) {
        throw ConfigException('$k must be an integer >= $min (got "$raw")');
      }
      return v;
    }

    final effort = str('LUMEN_EFFORT') ?? kDefaultEffort;
    if (!kAllowedEfforts.contains(effort)) {
      throw ConfigException('LUMEN_EFFORT must be one of $kAllowedEfforts');
    }
    final baseUrl = str('ANTHROPIC_BASE_URL') ?? kDefaultAnthropicBaseUrl;
    final parsed = Uri.tryParse(baseUrl);
    if (parsed == null || !parsed.hasScheme || parsed.host.isEmpty) {
      throw const ConfigException('ANTHROPIC_BASE_URL is not a valid URL');
    }
    return GatewayConfig(
      apiKey: str('ANTHROPIC_API_KEY'),
      model: str('LUMEN_MODEL') ?? kDefaultModel,
      effort: effort,
      port: integer('PORT', 8080, min: 0),
      gatewayToken: str('LUMEN_GATEWAY_TOKEN'),
      ratePerMinute: integer('LUMEN_RPM', 20),
      burst: integer('LUMEN_BURST', 5),
      maxBodyBytes: integer('LUMEN_MAX_BODY_BYTES', 4194304),
      upstreamConcurrency: integer('LUMEN_UPSTREAM_CONCURRENCY', 4),
      upstreamQueue: integer('LUMEN_UPSTREAM_QUEUE', 16, min: 0),
      anthropicBaseUrl: baseUrl.endsWith('/')
          ? baseUrl.substring(0, baseUrl.length - 1)
          : baseUrl,
      upstreamTimeout: Duration(
        seconds: integer('LUMEN_UPSTREAM_TIMEOUT_S', 90),
      ),
      cacheSize: integer('LUMEN_CACHE_SIZE', 256, min: 0),
      trustProxy: str('LUMEN_TRUST_PROXY') == '1',
      corsOrigin: str('LUMEN_CORS_ORIGIN') ?? '*',
    );
  }

  /// `ANTHROPIC_API_KEY`; null disables vision (503 `vision_unavailable`).
  final String? apiKey;

  /// `LUMEN_MODEL`.
  final String model;

  /// `LUMEN_EFFORT`, always sent explicitly as `output_config.effort`.
  final String effort;
  final int port;

  /// `LUMEN_GATEWAY_TOKEN`; when set, edit routes need `Bearer <token>`.
  final String? gatewayToken;
  final int ratePerMinute;
  final int burst;
  final int maxBodyBytes;
  final int upstreamConcurrency;
  final int upstreamQueue;
  final String anthropicBaseUrl;
  final Duration upstreamTimeout;
  final int maxTokens;
  final int cacheSize;

  /// `LUMEN_TRUST_PROXY=1`: rate-limit by the first `x-forwarded-for` hop
  /// (set this behind Cloud Run / a load balancer).
  final bool trustProxy;
  final String corsOrigin;

  bool get visionAvailable => apiKey != null && apiKey!.isNotEmpty;

  Uri get messagesUri => Uri.parse('$anthropicBaseUrl/v1/messages');

  @override
  String toString() =>
      'GatewayConfig(model: $model, effort: $effort, port: $port, '
      'vision: ${visionAvailable ? 'on' : 'off'}, '
      'auth: ${gatewayToken == null ? 'off' : 'on'}, '
      'rpm: $ratePerMinute, burst: $burst, maxBody: $maxBodyBytes, '
      'upstream: $upstreamConcurrency/$upstreamQueue, base: $anthropicBaseUrl)';
}
