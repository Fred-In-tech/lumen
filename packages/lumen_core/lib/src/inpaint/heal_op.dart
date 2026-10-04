/// The non-destructive heal / remove / clone layer (§5.5): an ordered list
/// of ops, each pointing at an RGBA patch stored at original resolution.
library;

import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

import '../model/mask_shapes.dart';
import 'pixel_box.dart';

enum HealKind {
  /// Object removal (model or classical fill).
  remove,

  /// Healing brush: texture from elsewhere, colour from around the hole.
  heal,

  /// Clone stamp: a straight copy from [HealOp.cloneOffset].
  clone;

  /// Unknown or missing → [remove] (the patch is what renders).
  static HealKind parse(Object? v) =>
      values.firstWhere((k) => k.name == v, orElse: () => remove);
}

/// One heal op. [bbox] is in source pixels of a [srcWidth]×[srcHeight]
/// source; [patch] is a relative asset path (e.g. `retouch/h3.png`) of a
/// bbox-sized RGBA PNG with the feathered hole as alpha.
@immutable
class HealOp {
  const HealOp({
    required this.id,
    this.kind = HealKind.remove,
    this.engine = '',
    this.ai = false,
    this.strokes = const [],
    this.bbox = PixelBox.zero,
    this.srcWidth = 0,
    this.srcHeight = 0,
    this.patch = '',
    this.cloneOffset,
    this.hidden = false,
    this.createdAt,
    this.faceIntersect = false,
  });

  /// An op for a freshly generated patch covering [bbox] (source px); the
  /// app stores the PNG at `retouch/<id>.png`.
  factory HealOp.forPatch({
    required String id,
    required PixelBox bbox,
    required int srcWidth,
    required int srcHeight,
    required String engine,
    required bool ai,
    required List<BrushStroke> strokes,
    HealKind kind = HealKind.remove,
    (double, double)? cloneOffset,
    bool faceIntersect = false,
    DateTime? createdAt,
  }) => HealOp(
    id: id,
    kind: kind,
    engine: engine,
    ai: ai,
    strokes: List.unmodifiable(strokes),
    bbox: bbox,
    srcWidth: srcWidth,
    srcHeight: srcHeight,
    patch: 'retouch/$id.png',
    cloneOffset: cloneOffset,
    faceIntersect: faceIntersect,
    createdAt: (createdAt ?? DateTime.now()).toUtc(),
  );

  factory HealOp.fromJson(Map<String, Object?> j) {
    final mask = j['mask'];
    final strokes = mask is Map ? mask['strokes'] : null;
    final size = j['srcSize'];
    final src = j['src'];
    final hasSize =
        size is List && size.length >= 2 && size[0] is num && size[1] is num;
    return HealOp(
      id: j['id'] is String ? j['id'] as String : '',
      kind: HealKind.parse(j['kind']),
      engine: j['engine'] is String ? j['engine'] as String : '',
      ai: j['ai'] == true,
      strokes: strokes is List
          ? List.unmodifiable(
              strokes.whereType<Map<Object?, Object?>>().map(
                (s) => BrushStroke.fromJson(s.cast()),
              ),
            )
          : const [],
      bbox: PixelBox.tryFromJson(j['bbox']) ?? PixelBox.zero,
      srcWidth: hasSize ? (size[0] as num).round().clamp(0, 1 << 20) : 0,
      srcHeight: hasSize ? (size[1] as num).round().clamp(0, 1 << 20) : 0,
      patch: sanitizePatchRef(j['patch']),
      cloneOffset:
          src is List && src.length >= 2 && src[0] is num && src[1] is num
          ? ((src[0] as num).toDouble(), (src[1] as num).toDouble())
          : null,
      hidden: j['hidden'] == true,
      createdAt: j['createdAt'] is String
          ? DateTime.tryParse(j['createdAt'] as String)?.toUtc()
          : null,
      faceIntersect: j['faceWarning'] == true,
    );
  }

  final String id;
  final HealKind kind;

  /// Engine id and version, e.g. `migan@fp16-1`, `patchmatch@1`, `copy`.
  final String engine;

  /// AI-generated fill (C2PA / disclosure).
  final bool ai;

  /// The user's mask, normalized like mask brush strokes.
  final List<BrushStroke> strokes;

  final PixelBox bbox;
  final int srcWidth;
  final int srcHeight;
  final String patch;

  /// Clone source offset in normalized uv (clone ops only).
  final (double, double)? cloneOffset;

  final bool hidden;
  final DateTime? createdAt;

  /// The hole touched a detected face: the UI shows a warning (§5.4).
  final bool faceIntersect;

  /// Has what compositing needs (a patch ref, a box and a source size).
  bool get isRenderable =>
      patch.isNotEmpty && !bbox.isEmpty && srcWidth > 0 && srcHeight > 0;

  HealOp copyWith({
    bool? hidden,
    String? patch,
    PixelBox? bbox,
    String? engine,
    bool? ai,
    bool? faceIntersect,
  }) => HealOp(
    id: id,
    kind: kind,
    engine: engine ?? this.engine,
    ai: ai ?? this.ai,
    strokes: strokes,
    bbox: bbox ?? this.bbox,
    srcWidth: srcWidth,
    srcHeight: srcHeight,
    patch: patch ?? this.patch,
    cloneOffset: cloneOffset,
    hidden: hidden ?? this.hidden,
    createdAt: createdAt,
    faceIntersect: faceIntersect ?? this.faceIntersect,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind.name,
    'engine': engine,
    'ai': ai,
    'mask': {
      'strokes': [for (final s in strokes) s.toJson()],
    },
    'bbox': bbox.toJson(),
    'srcSize': [srcWidth, srcHeight],
    'patch': patch,
    if (cloneOffset case final o?) 'src': [o.$1, o.$2],
    if (hidden) 'hidden': true,
    if (createdAt case final t?) 'createdAt': t.toIso8601String(),
    if (faceIntersect) 'faceWarning': true,
  };

  @override
  bool operator ==(Object other) =>
      other is HealOp &&
      other.id == id &&
      other.kind == kind &&
      other.engine == engine &&
      other.ai == ai &&
      const ListEquality<BrushStroke>().equals(other.strokes, strokes) &&
      other.bbox == bbox &&
      other.srcWidth == srcWidth &&
      other.srcHeight == srcHeight &&
      other.patch == patch &&
      other.cloneOffset == cloneOffset &&
      other.hidden == hidden &&
      other.createdAt == createdAt &&
      other.faceIntersect == faceIntersect;

  @override
  int get hashCode => Object.hash(
    id,
    kind,
    engine,
    ai,
    const ListEquality<BrushStroke>().hash(strokes),
    bbox,
    srcWidth,
    srcHeight,
    patch,
    cloneOffset,
    hidden,
    createdAt,
    faceIntersect,
  );

  @override
  String toString() => 'HealOp($id, ${kind.name}, $engine, $bbox)';
}

/// Lenient list parse: non-map entries are skipped.
List<HealOp> parseHealOps(Object? json) => json is List
    ? List.unmodifiable(
        json.whereType<Map<Object?, Object?>>().map(
          (m) => HealOp.fromJson(m.cast()),
        ),
      )
    : const [];

/// A patch ref must be a relative path inside the photo's asset folder:
/// no absolute paths, drive letters, backslashes or `..` segments
/// (an edited document must never point the app at other files).
String sanitizePatchRef(Object? v) {
  if (v is! String || v.isEmpty) return '';
  if (v.startsWith('/') || v.contains(r'\') || v.contains(':')) return '';
  if (v.split('/').any((s) => s == '..' || s.isEmpty)) return '';
  return v;
}
