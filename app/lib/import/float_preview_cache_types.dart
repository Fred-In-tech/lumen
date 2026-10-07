import 'dart:typed_data';

import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/import/float_decoder_types.dart';

/// Version of the cached preview files. Must equal
/// `FloatPreviewFile.formatVersion` on the native side; bump both when the
/// decoder settings or the layout change (old entries then miss and age
/// out of the cache).
const int kFloatPreviewCacheVersion = 1;

/// Size cap of the preview cache. A 2560 px preview of a 45 MP RAW is about
/// 17 MB, so 2 GB keeps roughly the last 120 opened or imported RAWs.
const int kFloatPreviewCacheMaxBytes = 2 * 1024 * 1024 * 1024;

/// Length of the file header the Dart side reads (`FloatPreviewFile`).
const int kFloatPreviewHeaderBytes = 64;

const int _magic = 0x3150464C; // "LFP1"

/// Ids that cannot escape the cache folder (no separators, no `..`).
final _safeId = RegExp(r'^[A-Za-z0-9_-]{1,128}$');

/// `<assetId>.v<version>.<width>x<height>.lfp`, or null for an id that is
/// not a plain token.
String? floatPreviewFileName(String assetId, int width, int height) {
  if (!_safeId.hasMatch(assetId) || width <= 0 || height <= 0) return null;
  return '$assetId.v$kFloatPreviewCacheVersion.${width}x$height.lfp';
}

/// The asset id of a cache file name of the current version, else null.
String? assetIdOfFloatPreview(String fileName) {
  final m = RegExp(r'^([A-Za-z0-9_-]{1,128})\.v(\d+)\.\d+x\d+\.lfp$')
      .firstMatch(fileName);
  if (m == null || int.parse(m.group(2)!) != kFloatPreviewCacheVersion) {
    return null;
  }
  return m.group(1);
}

/// What the header of a cache file says about the original: its full
/// upright size and develop profile (no RAW decode needed to open it).
/// Null when [header] is not a header of the current version.
FloatSourceInfo? parseFloatPreviewHeader(Uint8List header) {
  if (header.length < kFloatPreviewHeaderBytes) return null;
  final b = ByteData.sublistView(header);
  if (b.getUint32(0, Endian.little) != _magic) return null;
  if (b.getUint32(4, Endian.little) != kFloatPreviewCacheVersion) return null;
  final fw = b.getUint32(16, Endian.little);
  final fh = b.getUint32(20, Endian.little);
  if (fw == 0 || fh == 0) return null;
  final knee = b.getFloat64(24, Endian.little);
  final gain = b.getFloat64(32, Endian.little);
  if (!knee.isFinite || !gain.isFinite) return null;
  return FloatSourceInfo(
    width: fw,
    height: fh,
    profile: HbdProfile(shoulderKnee: knee, highlightGain: gain),
  );
}

/// Where float previews are cached. The native decoder writes and reads
/// the files (`floatRender` with `cachePath`, `floatPreviewBuild`,
/// `floatPreviewRead`); this side names them, tracks use and keeps the
/// folder under its size cap.
abstract interface class FloatPreviewCache {
  /// Path of the entry of [assetId] at [width]×[height], or null when this
  /// platform has no preview cache.
  Future<String?> pathFor(String assetId, int width, int height);

  /// Full size and profile of [assetId] from any of its cached entries,
  /// else null.
  Future<FloatSourceInfo?> infoFor(String assetId);

  /// True when an entry file of that size exists (validity is checked when
  /// it is read).
  Future<bool> contains(String assetId, int width, int height);

  /// Marks [path] as just used (eviction is least recently used first).
  Future<void> touch(String path);

  /// Deletes least recently used entries until the folder is under its
  /// cap, never one of [keep]. Returns the bytes freed.
  Future<int> trim({Set<String> keep = const {}});

  /// Total size of the entries (diagnostics, tests).
  Future<int> sizeInBytes();

  /// Deletes every entry of [assetId] (the photo was deleted).
  Future<void> remove(String assetId);
}

/// No preview cache (web, tests): every open decodes.
class NoFloatPreviewCache implements FloatPreviewCache {
  const NoFloatPreviewCache();

  @override
  Future<String?> pathFor(String assetId, int width, int height) async => null;

  @override
  Future<FloatSourceInfo?> infoFor(String assetId) async => null;

  @override
  Future<bool> contains(String assetId, int width, int height) async => false;

  @override
  Future<void> touch(String path) async {}

  @override
  Future<int> trim({Set<String> keep = const {}}) async => 0;

  @override
  Future<int> sizeInBytes() async => 0;

  @override
  Future<void> remove(String assetId) async {}
}
