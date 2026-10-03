/// Request DTOs of the gateway contract v1 (PLAN §1.9), shared by the app's
/// `GatewayClient` and the `lumen_server` routes.
library;

import '../model/exif_summary.dart';
import '../model/param_registry.dart';
import 'gateway_errors.dart';

/// `contractVersion` sent in every request and health response.
const int kContractVersion = 1;

/// Longest image edge the gateway accepts (Claude's standard-res limit).
const int kMaxImageLongEdge = 1568;
const int kMaxInstructionChars = 500;
const int kMaxVariants = 3;
const List<String> kSupportedImageMimes = [
  'image/jpeg',
  'image/png',
  'image/webp',
];

abstract final class GatewayPaths {
  static const health = '/v1/health';
  static const autoEdit = '/v1/auto-edit';
  static const instruct = '/v1/instruct';
}

/// The 9 AI styles, with their wire ids and display labels.
enum GatewayStyle {
  natural('natural', 'Natural'),
  vibrant('vibrant', 'Vibrant'),
  moody('moody', 'Moody'),
  cinematic('cinematic', 'Cinematic'),
  film('film', 'Film'),
  goldenHour('golden_hour', 'Golden Hour'),
  cleanBright('clean_bright', 'Clean & Bright'),
  bw('bw', 'B&W'),
  portraitSoft('portrait_soft', 'Portrait Soft');

  const GatewayStyle(this.wire, this.label);

  final String wire;
  final String label;

  static GatewayStyle? fromWire(Object? wire) {
    for (final s in values) {
      if (s.wire == wire) return s;
    }
    return null;
  }
}

Never _invalid(String message, [Map<String, Object?> details = const {}]) =>
    throw ContractViolation(message, details: details);

Map<Object?, Object?> _requireMap(Object? v, String field) =>
    v is Map ? v : _invalid('"$field" must be an object', {'field': field});

Map<ParamId, double> _paramValues(Object? v, String field) {
  if (v == null) return const {};
  final map = _requireMap(v, field);
  final out = <ParamId, double>{};
  for (final e in map.entries) {
    final spec = e.key is String
        ? ParamRegistry.tryById(e.key! as String)
        : null;
    final value = e.value;
    if (spec == null || value is! num || !value.isFinite) continue;
    out[spec.id] = spec.clamp(value.toDouble());
  }
  return Map.unmodifiable(out);
}

class ClientInfo {
  const ClientInfo({this.app = 'lumen', this.version = '', this.platform = ''});

  factory ClientInfo.fromJson(Object? json) {
    if (json is! Map) return const ClientInfo();
    String s(String k) => json[k] is String ? json[k]! as String : '';
    return ClientInfo(
      app: s('app'),
      version: s('version'),
      platform: s('platform'),
    );
  }

  final String app;
  final String version;
  final String platform;

  Map<String, Object?> toJson() => {
    'app': app,
    'version': version,
    'platform': platform,
  };
}

class ImagePayload {
  const ImagePayload({
    required this.mime,
    required this.width,
    required this.height,
    required this.base64,
  });

  factory ImagePayload.fromJson(Object? json) {
    final m = _requireMap(json, 'image');
    final mime = m['mime'];
    final w = m['width'];
    final h = m['height'];
    final data = m['base64'];
    if (mime is! String || !kSupportedImageMimes.contains(mime)) {
      _invalid('image.mime must be one of $kSupportedImageMimes');
    }
    if (w is! int || h is! int || w <= 0 || h <= 0) {
      _invalid('image.width and image.height must be positive integers');
    }
    if (data is! String || data.isEmpty) _invalid('image.base64 is required');
    return ImagePayload(mime: mime, width: w, height: h, base64: data);
  }

  final String mime;
  final int width;
  final int height;

  /// Standard base64 of the encoded image (no data: prefix).
  final String base64;

  int get longEdge => width > height ? width : height;

  Map<String, Object?> toJson() => {
    'mime': mime,
    'width': width,
    'height': height,
    'base64': base64,
  };
}

/// `POST /v1/auto-edit` body.
class AutoEditRequest {
  const AutoEditRequest({
    this.requestId,
    this.client = const ClientInfo(),
    this.style = GatewayStyle.natural,
    this.variants = 1,
    required this.image,
    this.stats = const {},
    this.exif,
    this.baseline = const {},
    this.current = const {},
    this.locked = const [],
  });

  /// Throws [ContractViolation] when the body breaks the contract.
  factory AutoEditRequest.fromJson(Object? json) {
    final m = _requireMap(json, 'body');
    final version = m['contractVersion'];
    if (version != kContractVersion) {
      throw ContractViolation(
        'Unsupported contractVersion $version (server speaks '
        '$kContractVersion)',
        code: GatewayErrorCode.unsupportedContract,
        details: {'supported': kContractVersion},
      );
    }
    final styleRaw = m['style'] ?? GatewayStyle.natural.wire;
    final style =
        GatewayStyle.fromWire(styleRaw) ??
        _invalid('Unknown style "$styleRaw"');
    final variants = m['variants'];
    final stats = m['stats'];
    final locked = m['locked'];
    if (stats != null && stats is! Map) _invalid('"stats" must be an object');
    if (locked != null && locked is! List) _invalid('"locked" must be a list');
    final requestId = m['requestId'];
    return AutoEditRequest(
      requestId: requestId is String && requestId.isNotEmpty ? requestId : null,
      client: ClientInfo.fromJson(m['client']),
      style: style,
      variants: variants is int ? variants.clamp(1, kMaxVariants) : 1,
      image: ImagePayload.fromJson(m['image']),
      stats: stats is Map
          ? Map.unmodifiable(stats.cast<String, Object?>())
          : const {},
      exif: m['exif'] is Map ? ExifSummary.fromJson(m['exif']) : null,
      baseline: _paramValues(m['baseline'], 'baseline'),
      current: _paramValues(m['current'], 'current'),
      locked: locked is List
          ? List.unmodifiable(
              locked.whereType<String>().where(ParamRegistry.contains),
            )
          : const [],
    );
  }

  final String? requestId;
  final ClientInfo client;
  final GatewayStyle style;

  /// 1 (default) or up to [kMaxVariants] for a variations strip.
  final int variants;
  final ImagePayload image;

  /// `ImageStats.toJson()` from the app (opaque to the contract).
  final Map<String, Object?> stats;
  final ExifSummary? exif;

  /// The local engine's result ("technically neutral, no style").
  final Map<ParamId, double> baseline;

  /// The photo's current non-default values.
  final Map<ParamId, double> current;

  /// Params the user set manually; the AI must not change them.
  final List<ParamId> locked;

  Map<String, Object?> toJson() => {
    'contractVersion': kContractVersion,
    if (requestId != null) 'requestId': requestId,
    'client': client.toJson(),
    'style': style.wire,
    'variants': variants,
    'image': image.toJson(),
    'stats': stats,
    if (exif != null) 'exif': exif!.toJson(),
    'baseline': baseline,
    'current': current,
    'locked': locked,
  };
}

/// `POST /v1/instruct` body: an [AutoEditRequest] plus the instruction.
/// Values in the result are deltas from `current`.
class InstructRequest {
  const InstructRequest({required this.request, required this.instruction});

  factory InstructRequest.fromJson(Object? json) {
    final request = AutoEditRequest.fromJson(json);
    final raw = (json! as Map)['instruction'];
    final instruction = raw is String ? raw.trim() : '';
    if (instruction.isEmpty) _invalid('"instruction" is required');
    if (instruction.length > kMaxInstructionChars) {
      _invalid('"instruction" exceeds $kMaxInstructionChars characters');
    }
    return InstructRequest(request: request, instruction: instruction);
  }

  final AutoEditRequest request;
  final String instruction;

  Map<String, Object?> toJson() => {
    ...request.toJson(),
    'instruction': instruction,
  };
}
