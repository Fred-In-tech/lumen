import 'package:logging/logging.dart';
import 'package:lumen_core/lumen_core.dart';

class UsageEvent {
  const UsageEvent({
    required this.requestId,
    required this.route,
    required this.model,
    required this.servedBy,
    required this.usage,
    required this.cached,
    required this.latencyMs,
  });

  final String requestId;
  final String route;
  final String model;
  final String servedBy;
  final GatewayUsage usage;
  final bool cached;
  final int latencyMs;

  Map<String, Object?> toJson() => {
    'requestId': requestId,
    'route': route,
    'model': model,
    'servedBy': servedBy,
    'cached': cached,
    'latencyMs': latencyMs,
    ...usage.toJson(),
  };
}

/// Where token usage goes. Logged now; a Stripe meter later.
abstract interface class UsageMeter {
  void record(UsageEvent event);
}

class LogUsageMeter implements UsageMeter {
  LogUsageMeter([Logger? logger]) : _log = logger ?? Logger('lumen.usage');

  final Logger _log;

  @override
  void record(UsageEvent event) => _log.info('usage ${event.toJson()}');
}
