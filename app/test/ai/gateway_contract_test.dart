import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lumen/ai/auto_edit_service.dart';
import 'package:lumen/ai/gateway_client.dart';
import 'package:lumen/ai/vision_provider.dart';
import 'package:lumen/app/providers.dart';
import 'package:lumen/data/memory_catalog_repository.dart';
import 'package:lumen/features/editor/editor_controller.dart';
import 'package:lumen_core/lumen_core.dart';
import 'package:lumen_server/lumen_server.dart';
import 'package:shelf/shelf.dart' as shelf;

const _fakeKey = 'test-key-not-real';

Map<String, Object?> _modelOutput() => {
  'scene': {
    'subject': 'interior',
    'lighting': 'dim',
    'timeOfDay': 'indoor',
    'keyIntent': 'normal',
  },
  'issues': [
    {'issue': 'underexposed', 'severity': 'high'},
  ],
  'intent': 'Brighter, warm and calm interior',
  'variants': [
    {
      'label': 'Natural',
      'confidence': 0.8,
      'targets': {
        'midLStar': 50,
        'wbStrength': 0.6,
        'contrastLevel': 'medium',
        'colorLevel': 'natural',
      },
      'presetAtoms': <Object?>[],
      'adjustments': [
        {'param': 'exposure', 'value': 1.2, 'reason': 'Brighten the room'},
        {'param': 'shadows', 'value': 30, 'reason': 'Open the shadows'},
        {'param': 'temp', 'value': 9999, 'reason': 'Out of range on purpose'},
      ],
    },
  ],
  'done': false,
};

http.Response _claude(String stopReason) => http.Response(
  jsonEncode({
    'id': 'msg_test',
    'type': 'message',
    'role': 'assistant',
    'model': 'claude-opus-5-5',
    'stop_reason': stopReason,
    'content': [
      if (stopReason != 'refusal')
        {'type': 'text', 'text': jsonEncode(_modelOutput())},
    ],
    'usage': {'input_tokens': 10, 'output_tokens': 10},
  }),
  200,
  headers: {'content-type': 'application/json'},
);

/// App GatewayClient wired to the real shelf handler (no network).
GatewayClient _gateway({
  String stopReason = 'end_turn',
  String? apiKey = _fakeKey,
}) {
  final upstream = MockClient((req) async => _claude(stopReason));
  final config = GatewayConfig(apiKey: apiKey);
  final handler = buildHandler(
    config: config,
    claude: apiKey == null
        ? createClaudeClient(config, http.Client())
        : HttpClaudeClient(
            apiKey: apiKey,
            messagesUri: Uri.parse('https://api.test/v1/messages'),
            httpClient: upstream,
          ),
  );
  final bridge = MockClient((req) async {
    final res = await handler(
      shelf.Request(
        req.method,
        req.url,
        headers: req.headers,
        body: req.bodyBytes,
      ),
    );
    return http.Response.bytes(
      await res.read().expand((c) => c).toList(),
      res.statusCode,
      headers: res.headers,
    );
  });
  return GatewayClient(baseUrl: 'http://gateway.test', client: bridge);
}

RgbaBuffer _proxy() =>
    SyntheticScenes.build(SceneId.darkInterior, longEdge: 256).image;

AiPhotoContext _ctx() => AiPhotoContext(
  proxy: _proxy(),
  current: DevelopSettings.defaults,
  visionJpeg: () async => Uint8List.fromList(List<int>.generate(64, (i) => i)),
);

void main() {
  test(
    'health reports vision when the gateway has a key, not without',
    () async {
      expect((await _gateway().health()).visionAvailable, isTrue);
      expect((await _gateway(apiKey: null).health()).visionAvailable, isFalse);
    },
  );

  test(
    'vision result becomes clamped, editable sliders with reasons',
    () async {
      final client = _gateway();
      final service = AutoEditService(
        local: const LocalAutoEditProvider(),
        vision: VisionAutoEditProvider(
          client,
          clientInfo: const ClientInfo(
            app: 'lumen',
            version: 'test',
            platform: 'test',
          ),
        ),
        isolateLocal: false,
      );
      final r = await service.autoEdit(_ctx());
      expect(r.outcome.engineUsed, AutoEditEngine.vision);
      expect(r.record.engine, 'vision');
      expect(r.outcome.settings.value(P.exposure), closeTo(1.2, 1e-9));
      expect(
        r.outcome.settings.value(P.temp),
        100,
        reason: 'clamped to the registry range',
      );
      final reasons = {for (final c in r.outcome.changes) c.param: c.reason};
      expect(reasons[P.exposure], 'Brighten the room');
      expect(reasons[P.shadows], 'Open the shadows');
      expect(r.label, 'AI Auto · Natural');
    },
  );

  test(
    'refusal from Claude falls back to the local engine with a reason',
    () async {
      final service = AutoEditService(
        local: const LocalAutoEditProvider(),
        vision: VisionAutoEditProvider(
          _gateway(stopReason: 'refusal'),
          clientInfo: const ClientInfo(),
        ),
        isolateLocal: false,
      );
      final r = await service.autoEdit(_ctx());
      expect(r.outcome.engineUsed, AutoEditEngine.local);
      expect(r.record.degradedReason, 'upstream_refusal');
      expect(r.outcome.settings.value(P.exposure), greaterThan(0.3));
    },
  );

  test('instruct applies deltas from the gateway', () async {
    final service = AutoEditService(
      local: const LocalAutoEditProvider(),
      vision: VisionAutoEditProvider(
        _gateway(),
        clientInfo: const ClientInfo(),
      ),
      isolateLocal: false,
    );
    final ctx = AiPhotoContext(
      proxy: _proxy(),
      current: DevelopSettings.defaults.withValue(P.shadows, 10),
      visionJpeg: () async => Uint8List(8),
    );
    final r = await service.instruct(ctx, 'brighter and open the shadows');
    expect(r.outcome.settings.value(P.shadows), greaterThan(10));
    expect(r.label, contains('brighter and open the shadows'));
  });

  test(
    'applied to the editor: one history entry, Explain reasons, AI amount',
    () async {
      final repo = MemoryCatalogRepository();
      final c = ProviderContainer(
        overrides: [catalogRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(c.dispose);
      await c.read(editorProvider('x').future);
      final service = AutoEditService(
        local: const LocalAutoEditProvider(),
        vision: VisionAutoEditProvider(
          _gateway(),
          clientInfo: const ClientInfo(),
        ),
        isolateLocal: false,
      );
      final r = await service.autoEdit(_ctx());
      c
          .read(editorProvider('x').notifier)
          .applyAi(r.outcome.settings, r.record, label: r.label);
      final s = c.read(editorProvider('x')).value!;
      expect(s.history.entries.single.kind, HistoryKind.ai);
      expect(
        s.doc.ai!.changes.any((ch) => ch.reason == 'Brighten the room'),
        isTrue,
      );
      final half = applyAiAmount(
        pre: s.doc.ai!.preAi,
        ai: s.doc.ai!.postAi!,
        percent: 50,
      );
      expect(half.value(P.exposure), closeTo(0.6, 1e-9));
    },
  );
}
