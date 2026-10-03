// Real-key smoke test (PLAN P5.7, DoD 29). Never runs in `dart test`.
//
//   # against a running gateway:
//   LUMEN_GATEWAY_URL=http://localhost:8080 dart run tool/smoke_vision.dart
//   # or in-process (needs ANTHROPIC_API_KEY in the environment):
//   ANTHROPIC_API_KEY=... dart run tool/smoke_vision.dart
//
// Sends a synthetic dark tungsten interior, checks: 200, >= 3 adjustments,
// median luma after applying the edit in [0.30, 0.60], and that a second
// identical call is a cache hit or reports cacheReadTokens > 0.
// Exit codes: 0 pass or "not run: no key", 1 check failed, 2 transport error.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:lumen_core/lumen_core.dart';
import 'package:lumen_server/lumen_server.dart';
import 'package:shelf/shelf.dart' as shelf;

typedef Post = Future<(int, Map<String, Object?>)> Function(
  String path,
  Map<String, Object?> body,
);

/// Dark, warm interior with a small bright window (median luma ≈ 0.10).
RgbaBuffer darkInterior(int w, int h) {
  final buf = RgbaBuffer(w, h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final isWindow =
          x > w * 0.72 && x < w * 0.92 && y > h * 0.1 && y < h * 0.4;
      if (isWindow) {
        buf.setPixel(x, y, 222, 228, 236);
        continue;
      }
      final v =
          0.05 + 0.08 * (y / h) + 0.02 * math.sin(x / 37) + 0.04 * (x / w);
      int c(double k) => (v * k * 255).round().clamp(0, 255);
      buf.setPixel(x, y, c(1.35), c(1.0), c(0.62));
    }
  }
  return buf;
}

double medianLuma(RgbaBuffer b) {
  final lumas = List<double>.generate(b.pixelCount, (i) {
    final o = i * 4;
    return (0.2126 * b.data[o] +
            0.7152 * b.data[o + 1] +
            0.0722 * b.data[o + 2]) /
        255;
  })..sort();
  return lumas[lumas.length ~/ 2];
}

Map<String, Object?> statsOf(RgbaBuffer b) {
  final lumas = List<double>.generate(b.pixelCount, (i) {
    final o = i * 4;
    return (0.2126 * b.data[o] +
            0.7152 * b.data[o + 1] +
            0.0722 * b.data[o + 2]) /
        255;
  })..sort();
  double p(double q) => lumas[((lumas.length - 1) * q).round()];
  final clip = lumas.where((l) => l >= 0.995).length / lumas.length * 100;
  final crush = lumas.where((l) => l <= 0.01).length / lumas.length * 100;
  return {
    'lumaP': {
      'p0_5': p(0.005),
      'p5': p(0.05),
      'p50': p(0.5),
      'p95': p(0.95),
      'p99_5': p(0.995),
    },
    'clipPct': clip,
    'crushPct': crush,
    'wb': {'a': 0.45, 'm': -0.02, 'confidence': 0.8},
  };
}

Post httpPost(Uri base) => (path, body) async {
  final res = await http.post(
    base.resolve(path),
    headers: {
      'content-type': 'application/json',
      if (Platform.environment['LUMEN_GATEWAY_TOKEN'] case final t?)
        'authorization': 'Bearer $t',
    },
    body: jsonEncode(body),
  );
  return (res.statusCode, jsonDecode(res.body) as Map<String, Object?>);
};

Post inProcessPost(shelf.Handler handler) => (path, body) async {
  final res = await handler(
    shelf.Request(
      'POST',
      Uri.parse('http://localhost$path'),
      body: jsonEncode(body),
    ),
  );
  return (
    res.statusCode,
    jsonDecode(await res.readAsString()) as Map<String, Object?>,
  );
};

Future<void> main() async {
  final env = Platform.environment;
  final url = env['LUMEN_GATEWAY_URL'];
  final Post post;
  if (url != null) {
    post = httpPost(Uri.parse(url));
    final health = await http.get(Uri.parse(url).resolve(GatewayPaths.health));
    final h = HealthResponse.fromJson(jsonDecode(health.body));
    if (!h.visionAvailable) {
      stdout.writeln('not run: no key (gateway reports visionAvailable:false)');
      return;
    }
  } else {
    final config = GatewayConfig.fromEnv(env);
    if (!config.visionAvailable) {
      stdout.writeln(
        'not run: no key (set ANTHROPIC_API_KEY or LUMEN_GATEWAY_URL)',
      );
      return;
    }
    post = inProcessPost(
      buildHandler(
        config: config,
        claude: createClaudeClient(config, http.Client()),
      ),
    );
  }

  final full = darkInterior(1024, 683);
  final jpeg = img.encodeJpg(
    img.Image.fromBytes(
      width: full.width,
      height: full.height,
      bytes: full.data.buffer,
      numChannels: 4,
    ),
    quality: 88,
  );
  final request = AutoEditRequest(
    requestId: 'smoke-1',
    client: const ClientInfo(app: 'lumen', version: '1.0.0', platform: 'smoke'),
    style: GatewayStyle.natural,
    image: ImagePayload(
      mime: 'image/jpeg',
      width: full.width,
      height: full.height,
      base64: base64Encode(jpeg),
    ),
    stats: statsOf(full),
    exif: const ExifSummary(
      camera: 'Synthetic',
      iso: 1600,
      aperture: 2,
      focalMm: 35,
    ),
  );

  final failures = <String>[];
  final (status, json) = await post(GatewayPaths.autoEdit, request.toJson());
  stdout.writeln('first call: HTTP $status');
  if (status != 200) {
    stderr.writeln(const JsonEncoder.withIndent('  ').convert(json));
    exitCode = 2;
    return;
  }
  final first = GatewayEditResponse.fromJson(json);
  final variant = first.result.variants.first;
  stdout.writeln(
    'servedBy=${first.servedBy} latency=${first.latencyMs}ms '
    'usage=${first.usage.toJson()}',
  );
  for (final a in variant.adjustments) {
    stdout.writeln('  ${a.param} = ${a.value}  (${a.reason})');
  }
  if (variant.adjustments.length < 3) failures.add('fewer than 3 adjustments');

  final small = darkInterior(256, 171);
  final settings = DevelopSettings.defaults.withValues(variant.valuesByParam);
  final before = medianLuma(small);
  final after = medianLuma(renderReference(small, settings));
  stdout.writeln(
    'median luma: ${before.toStringAsFixed(3)} -> ${after.toStringAsFixed(3)}',
  );
  if (after < 0.30 || after > 0.60) {
    failures.add('median luma $after not in [0.30, 0.60]');
  }

  final (status2, json2) = await post(GatewayPaths.autoEdit, request.toJson());
  final second = GatewayEditResponse.fromJson(json2);
  stdout.writeln(
    'second call: HTTP $status2 cached=${second.cached} '
    'cacheReadTokens=${second.usage.cacheReadTokens}',
  );
  if (status2 != 200 || !(second.cached || second.usage.cacheReadTokens > 0)) {
    failures.add('second call was neither a cache hit nor a prompt-cache read');
  }

  if (failures.isEmpty) {
    stdout.writeln('SMOKE PASS');
  } else {
    stdout.writeln('SMOKE FAIL: ${failures.join('; ')}');
    exitCode = 1;
  }
  exit(exitCode);
}
