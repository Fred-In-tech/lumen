import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lumen_core/lumen_core.dart';
import 'package:lumen_server/lumen_server.dart';
import 'package:shelf/shelf.dart';

/// Test-only placeholder, never a real credential.
const String kTestApiKey = 'test-key-not-real';

class FakeClock implements Clock {
  FakeClock([DateTime? start]) : _now = start ?? DateTime.utc(2026, 10, 3);

  DateTime _now;

  @override
  DateTime now() => _now;

  void advance(Duration d) => _now = _now.add(d);
}

class RecordingMeter implements UsageMeter {
  final List<UsageEvent> events = [];

  @override
  void record(UsageEvent event) => events.add(event);
}

/// A valid `/v1/auto-edit` body (tiny fake JPEG bytes; never decoded).
Map<String, Object?> autoEditBody({
  String style = 'moody',
  int width = 1024,
  int height = 683,
  Map<String, Object?> current = const {},
  List<String> locked = const [],
}) => {
  'contractVersion': 1,
  'requestId': 'req-123',
  'client': {'app': 'lumen', 'version': '1.0.0', 'platform': 'macos'},
  'style': style,
  'variants': 1,
  'image': {
    'mime': 'image/jpeg',
    'width': width,
    'height': height,
    'base64': base64Encode(List<int>.generate(64, (i) => i)),
  },
  'stats': {
    'lumaP': {'p0_5': 0.02, 'p5': 0.05, 'p50': 0.18, 'p95': 0.71},
    'clipPct': 0.1,
    'crushPct': 3.2,
  },
  'exif': {'camera': 'X100V', 'iso': 1600, 'aperture': 2.0},
  'baseline': {'exposure': 0.62, 'shadows': 31},
  'current': current,
  'locked': locked,
};

Map<String, Object?> instructBody({
  String instruction = 'warmer and lift the shadows a bit',
  Map<String, Object?> current = const {},
}) => {...autoEditBody(current: current), 'instruction': instruction};

/// The structured-output JSON the model writes.
Map<String, Object?> modelOutput({
  List<Map<String, Object?>>? adjustments,
  bool done = false,
}) => {
  'scene': {
    'subject': 'interior',
    'lighting': 'dim tungsten',
    'timeOfDay': 'indoor',
    'keyIntent': 'normal',
  },
  'issues': [
    {'issue': 'underexposed', 'severity': 'high'},
  ],
  'intent': 'Brighter, warm and calm interior',
  'variants': [
    {
      'label': 'Moody',
      'confidence': 0.8,
      'targets': {
        'midLStar': 45,
        'wbStrength': 0.4,
        'contrastLevel': 'medium',
        'colorLevel': 'natural',
      },
      'presetAtoms': [
        {'atom': 'moody', 'amount': 0.7},
      ],
      'adjustments':
          adjustments ??
          [
            {'param': 'exposure', 'value': 0.8, 'reason': 'Brighten room'},
            {'param': 'shadows', 'value': 25, 'reason': 'Open the shadows'},
            {'param': 'temp', 'value': -10, 'reason': 'Tame tungsten cast'},
          ],
    },
  ],
  'done': done,
};

/// A `/v1/messages` 200 body.
Map<String, Object?> messagesBody({
  Object? output,
  String? text,
  String stopReason = 'end_turn',
  Object? stopDetails,
  String model = 'claude-opus-5-5',
  List<Map<String, Object?>> extraBlocksBefore = const [],
  List<Map<String, Object?>> iterations = const [],
}) => {
  'id': 'msg_test',
  'type': 'message',
  'role': 'assistant',
  'model': model,
  'stop_reason': stopReason,
  'stop_details': ?stopDetails,
  'content': [
    ...extraBlocksBefore,
    if (stopReason != 'refusal')
      {'type': 'text', 'text': text ?? jsonEncode(output ?? modelOutput())},
  ],
  'usage': {
    'input_tokens': 4210,
    'output_tokens': 612,
    'cache_read_input_tokens': 3020,
    'cache_creation_input_tokens': 0,
    if (iterations.isNotEmpty) 'iterations': iterations,
  },
};

http.Response jsonHttp(
  Object? body, [
  int status = 200,
  Map<String, String>? headers,
]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json', ...?headers},
);

/// MockClient that answers with [responses] in order and records requests.
class ScriptedUpstream {
  ScriptedUpstream(this.responses);

  final List<FutureOr<http.Response> Function()> responses;
  final List<http.Request> requests = [];

  MockClient get client => MockClient((request) async {
    requests.add(request);
    final i = requests.length - 1;
    if (i >= responses.length) {
      throw StateError('Unexpected upstream call #${i + 1}');
    }
    return responses[i]();
  });

  Map<String, Object?> bodyOf(int i) =>
      jsonDecode(requests[i].body) as Map<String, Object?>;
}

/// Builds the full handler with a scripted upstream and no real sleeps.
({
  Handler handler,
  ScriptedUpstream upstream,
  RecordingMeter meter,
  FakeClock clock,
  List<Duration> sleeps,
})
gateway({
  List<FutureOr<http.Response> Function()> responses = const [],
  GatewayConfig config = const GatewayConfig(apiKey: kTestApiKey),
  Duration timeout = const Duration(seconds: 90),
}) {
  final upstream = ScriptedUpstream(responses);
  final meter = RecordingMeter();
  final clock = FakeClock();
  final sleeps = <Duration>[];
  final claude = HttpClaudeClient(
    apiKey: config.apiKey ?? '',
    messagesUri: config.messagesUri,
    httpClient: upstream.client,
    timeout: timeout,
    sleep: (d) async => sleeps.add(d),
  );
  final handler = buildHandler(
    config: config,
    claude: claude,
    clock: clock,
    meter: meter,
  );
  return (
    handler: handler,
    upstream: upstream,
    meter: meter,
    clock: clock,
    sleeps: sleeps,
  );
}

Future<Response> send(
  Handler handler,
  String method,
  String path, {
  Object? body,
  Map<String, String> headers = const {},
}) async => handler(
  Request(
    method,
    Uri.parse('http://localhost$path'),
    body: body == null ? null : (body is String ? body : jsonEncode(body)),
    headers: {if (body != null) 'content-type': 'application/json', ...headers},
  ),
);

Future<Map<String, Object?>> jsonOf(Response response) async =>
    jsonDecode(await response.readAsString()) as Map<String, Object?>;

/// Asserts the error envelope and returns the error object.
Future<Map<String, Object?>> errorOf(
  Response response,
  GatewayErrorCode code,
) async {
  final json = await jsonOf(response);
  final error = json['error']! as Map<String, Object?>;
  if (response.statusCode != code.httpStatus || error['code'] != code.wire) {
    throw StateError(
      'Expected ${code.httpStatus} ${code.wire}, got '
      '${response.statusCode} ${error['code']}: ${error['message']}',
    );
  }
  return error;
}
