import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/ai/auto_edit_service.dart';
import 'package:lumen/ai/gateway_client.dart';
import 'package:lumen/ai/vision_provider.dart';
import 'package:lumen/app/providers.dart';

/// Gateway reachability + vision availability. Refresh with `ref.invalidate`.
class GatewayStatus {
  const GatewayStatus({required this.url, required this.reachable, required this.visionAvailable, this.model, this.promptVersion, this.message});

  final String url;
  final bool reachable;
  final bool visionAvailable;
  final String? model;
  final String? promptVersion;
  final String? message;
}

final gatewayClientProvider = Provider<GatewayClient>((ref) {
  final settings = ref.watch(settingsProvider).value;
  final platform = ref.watch(platformInfoProvider);
  final client = GatewayClient(
    baseUrl: settings?.gatewayUrl ?? platform.defaultGatewayUrl,
    token: settings?.gatewayToken,
  );
  ref.onDispose(client.close);
  return client;
});

final gatewayStatusProvider = FutureProvider<GatewayStatus>((ref) async {
  final client = ref.watch(gatewayClientProvider);
  try {
    final h = await client.health();
    return GatewayStatus(
      url: client.baseUrl,
      reachable: true,
      visionAvailable: h.visionAvailable,
      model: h.model,
      promptVersion: h.promptVersion,
      message: h.visionAvailable ? null : 'The gateway has no AI key, so edits run on this device.',
    );
  } on GatewayFailure catch (e) {
    return GatewayStatus(url: client.baseUrl, reachable: false, visionAvailable: false, message: e.message);
  }
});

/// The on-device engine (always available).
final localAutoEditProvider = Provider<AutoEditProvider>((ref) => LocalAutoEditProvider());

final autoEditServiceProvider = Provider<AutoEditService>((ref) {
  final status = ref.watch(gatewayStatusProvider).value;
  final platform = ref.watch(platformInfoProvider);
  final vision = status != null && status.visionAvailable
      ? VisionAutoEditProvider(
          ref.watch(gatewayClientProvider),
          clientInfo: ClientInfo(app: 'lumen', version: '1.0.0', platform: platform.name),
        )
      : null;
  return AutoEditService(local: ref.watch(localAutoEditProvider), vision: vision, promptVersion: status?.promptVersion);
});
