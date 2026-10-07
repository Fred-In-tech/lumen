/// Real image samples for looks, presets and LUTs.
///
/// Every card renders its look on a real photo with the CPU twin
/// (`renderReference`, the same develop maths as the GPU) at
/// [kLookPreviewLongEdge], in a background isolate, two at a time. Results
/// are cached by look + photo + settings, so a card renders once per
/// photo until the look changes.
///
/// Which photo ([LookPreviewPhoto]):
/// * Home / Looks page: the cover of the most recently active project,
///   else the newest photo ([homePreviewPhotoProvider]).
/// * Editor: the photo being edited (`LookPreviewPhoto.fromProxy`).
/// * Empty library: a bundled CC0 sample (`app/assets/samples/`), chosen to
///   suit the look ([sampleFor]).
library;

import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;
import 'package:logging/logging.dart';
import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/app/providers.dart';
import 'package:lumen/data/catalog_repository.dart';
import 'package:lumen/engine/creative_lut_cache.dart';
import 'package:lumen/features/editor/renderer/image_bridge.dart';
import 'package:lumen/features/looks/look.dart';
import 'package:lumen/features/projects/project_providers.dart';
import 'package:lumen/import/photo_decoder.dart';
import 'package:lumen/platform/background.dart';

final _log = Logger('LookPreviews');

/// Long edge of a preview render (a card is ~190 px wide at 2× density).
const int kLookPreviewLongEdge = 360;

/// The bundled CC0 sample photos (credits in `assets/samples/README.md`).
enum SamplePhoto {
  portraitPink('portrait_pink.jpg'),
  portraitMoody('portrait_moody.jpg'),
  weddingCouple('wedding_couple.jpg'),
  sunsetLandscape('sunset_landscape.jpg');

  const SamplePhoto(this.file);
  final String file;
  String get asset => 'assets/samples/$file';
}

/// The sample that shows [look] best while the library is empty: portraits
/// for portrait looks, the dark scene for moody ones, the landscape for
/// golden hour and cinematic.
SamplePhoto sampleFor(Look look) {
  switch (look) {
    case StyleLook(:final style):
      return switch (style) {
        AiStyle.moody || AiStyle.bw => SamplePhoto.portraitMoody,
        AiStyle.goldenHour || AiStyle.cinematic => SamplePhoto.sunsetLandscape,
        AiStyle.film || AiStyle.cleanBright => SamplePhoto.weddingCouple,
        _ => SamplePhoto.portraitPink,
      };
    case PresetLook(:final preset):
      final n = '${preset.name} ${preset.group}'.toLowerCase();
      bool any(List<String> words) => words.any(n.contains);
      if (any(['moody', 'dark', 'matte', 'noir', 'b&w', 'mono'])) {
        return SamplePhoto.portraitMoody;
      }
      if (any(['sunset', 'golden', 'landscape', 'cinema', 'teal', 'travel'])) {
        return SamplePhoto.sunsetLandscape;
      }
      if (any(['wedding', 'airy', 'bright', 'film', 'kodak', 'fuji'])) {
        return SamplePhoto.weddingCouple;
      }
      if (preset.isLutOnly) return SamplePhoto.sunsetLandscape;
      return SamplePhoto.portraitPink;
  }
}

/// A small photo looks are rendered on.
class LookPreviewPhoto {
  const LookPreviewPhoto({
    required this.id,
    required this.pixels,
    this.isSample = false,
  });

  /// Stable identity (asset id, sample name), part of the cache key.
  final String id;
  final RgbaBuffer pixels;
  final bool isSample;

  /// [proxy] (the editor's analysis proxy) scaled to preview size.
  static Future<LookPreviewPhoto> fromProxy(
    String id,
    RgbaBuffer proxy,
  ) async => LookPreviewPhoto(
    id: id,
    pixels: await runInBackground(
      () => makeProxy(proxy, longEdge: kLookPreviewLongEdge),
    ),
  );
}

final Map<SamplePhoto, Future<LookPreviewPhoto>> _samples = {};

/// A bundled sample at preview size (decoded once per run).
Future<LookPreviewPhoto> loadSamplePhoto(SamplePhoto s) =>
    _samples[s] ??= () async {
      final data = await rootBundle.load(s.asset);
      return LookPreviewPhoto(
        id: 'sample:${s.name}',
        pixels: await _decode(data.buffer.asUint8List()),
        isSample: true,
      );
    }();

/// [assetId]'s unedited pixels at preview size, or null when unreadable.
Future<LookPreviewPhoto?> loadLibraryPhoto(
  CatalogRepository repo,
  String assetId,
) async {
  try {
    final bytes = await repo.readPixelSource(assetId);
    return LookPreviewPhoto(id: assetId, pixels: await _decode(bytes));
  } on Exception catch (e) {
    _log.fine('preview photo $assetId unavailable: $e');
    return null;
  }
}

Future<RgbaBuffer> _decode(Uint8List bytes) async {
  final image = await decodePhoto(bytes, maxLongEdge: kLookPreviewLongEdge);
  try {
    return await rgbaFromImage(image);
  } finally {
    image.dispose();
  }
}

/// The asset Home previews looks on: the cover of the most recently active
/// project with photos, else the newest photo; null for an empty library.
String? homePreviewAssetId(
  List<ProjectSummary> projects,
  List<CatalogEntry> library,
) {
  for (final s in projects) {
    if (s.isUnsorted) continue;
    final c = s.cover;
    if (c != null) return c.assetId;
  }
  return library.isEmpty ? null : library.first.assetId;
}

/// The asset id Home previews looks on (rebuilds dependents only when it
/// changes, not on every library update).
final homePreviewAssetIdProvider = Provider<String?>(
  (ref) => homePreviewAssetId(
    ref.watch(projectSummariesProvider),
    ref.watch(libraryProvider).value ?? const [],
  ),
);

/// Home's preview photo (null: use the samples).
final homePreviewPhotoProvider = FutureProvider<LookPreviewPhoto?>((ref) {
  final id = ref.watch(homePreviewAssetIdProvider);
  if (id == null) return Future.value();
  return loadLibraryPhoto(ref.watch(catalogRepositoryProvider), id);
});

/// What one preview job needs (sent to the isolate).
typedef _Job = ({
  RgbaBuffer pixels,
  DevelopSettings settings,
  AiStyle? style,
  CubeLut? lut,
});

Future<Uint8List> _runJob(_Job j) async {
  var settings = j.settings;
  final style = j.style;
  if (style != null) {
    final outcome = await const LocalAutoEditProvider().autoEdit(
      AutoEditInput(
        stats: ImageStats.compute(j.pixels),
        style: style,
        proxy: j.pixels,
      ),
    );
    settings = outcome.settings;
  }
  final out = renderReference(j.pixels, settings, creativeLut: j.lut);
  return encodePreviewJpeg(out);
}

// Top level, so the isolate closures capture only their argument.
Future<Uint8List> _jobInBackground(_Job job) =>
    runInBackground(() => _runJob(job));

Future<Uint8List> _encodeInBackground(RgbaBuffer b) =>
    runInBackground(() => encodePreviewJpeg(b));

/// [b] as a JPEG (quality 90): a few tens of KB per card.
Uint8List encodePreviewJpeg(RgbaBuffer b) {
  final image = img.Image.fromBytes(
    width: b.width,
    height: b.height,
    bytes: b.data.buffer,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  );
  return Uint8List.fromList(
    img.encodeJpg(image.convert(numChannels: 3), quality: 90),
  );
}

/// Renders and caches look previews.
class LookPreviewService {
  LookPreviewService({this.maxEntries = 240, this.concurrency = 2});

  final int maxEntries;
  final int concurrency;
  final LinkedHashMap<String, Future<Uint8List?>> _cache = LinkedHashMap();
  final Queue<Completer<void>> _waiting = Queue();
  int _running = 0;

  /// Renders done and their total time (diagnostics, docs).
  int renders = 0;
  Duration renderTime = Duration.zero;

  /// Settings [look] applies to an unedited photo (styles: null, they are
  /// computed per photo in the job).
  static DevelopSettings? settingsFor(Look look) => switch (look) {
    StyleLook() => null,
    PresetLook(:final preset) => preset.apply(DevelopSettings.defaults),
  };

  /// Cache key: look, photo and the settings it applies.
  static String keyFor(Look look, LookPreviewPhoto photo) =>
      '${look.id}|${photo.id}|${settingsFor(look)?.hashCode ?? 0}';

  /// The photo unedited (the "before" of hold-to-compare).
  Future<Uint8List?> before(LookPreviewPhoto photo) =>
      _cached('before|${photo.id}', () => _encodeInBackground(photo.pixels));

  /// [look] on [photo] as JPEG bytes; null when it cannot render.
  Future<Uint8List?> preview(Look look, LookPreviewPhoto photo) =>
      _cached(keyFor(look, photo), () async {
        final settings = settingsFor(look) ?? DevelopSettings.defaults;
        final job = (
          pixels: photo.pixels,
          settings: settings,
          style: look is StyleLook ? look.style : null,
          lut: await CreativeLuts.forSettings(settings),
        );
        return _limited(() async {
          final sw = Stopwatch()..start();
          final out = await _jobInBackground(job);
          renders++;
          renderTime += sw.elapsed;
          return out;
        });
      });

  Future<Uint8List?> _cached(String key, Future<Uint8List> Function() make) {
    final hit = _cache.remove(key);
    if (hit != null) return _cache[key] = hit;
    final f = make().then<Uint8List?>(
      (v) => v,
      onError: (Object e) {
        _log.warning('preview $key failed: $e');
        _cache.remove(key);
        return null;
      },
    );
    _cache[key] = f;
    while (_cache.length > maxEntries) {
      _cache.remove(_cache.keys.first);
    }
    return f;
  }

  Future<T> _limited<T>(Future<T> Function() body) async {
    if (_running >= concurrency) {
      final slot = Completer<void>();
      _waiting.add(slot);
      await slot.future;
    }
    _running++;
    try {
      return await body();
    } finally {
      _running--;
      if (_waiting.isNotEmpty) _waiting.removeFirst().complete();
    }
  }

  @visibleForTesting
  int get cacheSize => _cache.length;
}

final lookPreviewServiceProvider = Provider<LookPreviewService>(
  (ref) => LookPreviewService(),
);
