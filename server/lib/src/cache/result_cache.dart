import 'dart:collection';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:lumen_core/lumen_core.dart';

/// Deterministic cache key: sha256 over the image plus everything else that
/// changes the answer (style, instruction, variants, stats, EXIF, baseline,
/// current, locked, model, effort, prompt version). Never `requestId`.
String resultCacheKey({
  required AutoEditRequest request,
  required String? instruction,
  required String model,
  required String effort,
  required String promptVersion,
}) {
  final imageHash = sha256.convert(utf8.encode(request.image.base64));
  final canonical = jsonEncode({
    'image': imageHash.toString(),
    'mime': request.image.mime,
    'style': request.style.wire,
    'variants': request.variants,
    'instruction': instruction,
    'stats': request.stats,
    'exif': request.exif?.toJson(),
    'baseline': request.baseline,
    'current': request.current,
    'locked': request.locked,
    'model': model,
    'effort': effort,
    'promptVersion': promptVersion,
  });
  return sha256.convert(utf8.encode(canonical)).toString();
}

/// Bounded LRU of gateway results (in-memory, per instance).
class ResultCache {
  ResultCache({this.capacity = 256});

  final int capacity;
  final LinkedHashMap<String, GatewayEditResponse> _entries = LinkedHashMap();

  int get length => _entries.length;

  GatewayEditResponse? get(String key) {
    final hit = _entries.remove(key);
    if (hit != null) _entries[key] = hit; // move to most-recent
    return hit;
  }

  void put(String key, GatewayEditResponse value) {
    if (capacity <= 0) return;
    _entries.remove(key);
    _entries[key] = value;
    while (_entries.length > capacity) {
      _entries.remove(_entries.keys.first);
    }
  }
}
