import 'dart:async';

import 'package:lumen/platform/background.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/ai/ai_providers.dart';
import 'package:lumen/ai/auto_edit_service.dart';
import 'package:lumen/ai/preview_encoder.dart';
import 'package:lumen/data/catalog_repository.dart';
import 'package:lumen/features/editor/editor_controller.dart';
import 'package:lumen/features/editor/renderer/image_bridge.dart';
import 'package:lumen/features/editor/renderer/photo_renderer.dart';

final _log = Logger('EditorSession');

/// Live resources for the photo open in the editor: renderer, stats, thumbs.
class EditorSession {
  EditorSession({
    required this.assetId,
    required this.renderer,
    required this.repo,
  });

  final String assetId;
  final PhotoRenderer renderer;
  final CatalogRepository repo;
  final ValueNotifier<bool> ready = ValueNotifier(false);
  final ValueNotifier<Histogram?> histogram = ValueNotifier(null);
  ImageStats? _stats;
  CatalogEntry? entry;
  Timer? _thumbTimer;
  Timer? _histTimer;
  bool _disposed = false;

  Future<void> open() async {
    entry = await repo.get(assetId);
    final Uint8List bytes = await repo.readOriginal(assetId);
    await renderer.open(bytes);
    if (_disposed) return;
    renderer.output.addListener(_scheduleHistogram);
    ready.value = true;
  }

  void render(DevelopSettings settings, {bool interactive = false}) {
    if (!ready.value) return;
    renderer.update(settings, interactive: interactive);
  }

  void _scheduleHistogram() {
    _histTimer?.cancel();
    _histTimer = Timer(const Duration(milliseconds: 100), () async {
      final img = renderer.output.value;
      if (img == null || _disposed) return;
      try {
        final small = await resizeImage(img, 256);
        final buf = await rgbaFromImage(small);
        small.dispose();
        if (!_disposed) histogram.value = Histogram.compute(buf);
      } on StateError catch (e) {
        _log.fine('histogram skipped: $e');
      }
    });
  }

  /// Re-renders the library thumbnail 1 s after the last committed change.
  void scheduleThumbnail(DevelopSettings settings) {
    _thumbTimer?.cancel();
    _thumbTimer = Timer(
      const Duration(seconds: 1),
      () => unawaited(_writeThumb(settings)),
    );
  }

  Future<void> _writeThumb(DevelopSettings settings) async {
    if (_disposed || !ready.value) return;
    try {
      final png = await renderer.renderThumbnail(settings);
      await repo.writeThumb(assetId, png);
      final e = await repo.get(assetId);
      if (e != null) {
        await repo.update(
          e.copyWith(
            thumbVersion: e.thumbVersion + 1,
            hasEdits: !settings.isDefault,
          ),
        );
      }
    } on Exception catch (e) {
      _log.warning('thumbnail failed: $e');
    }
  }

  Future<ImageStats?> stats() async {
    final proxy = renderer.analysisProxy;
    if (proxy == null) return null;
    return _stats ??= await AutoEditService.computeStats(proxy);
  }

  /// Context for an AI run on the current settings.
  Future<AiPhotoContext?> aiContext(EditorState state) async {
    final proxy = renderer.analysisProxy;
    if (proxy == null) return null;
    return AiPhotoContext(
      proxy: proxy,
      current: state.settings,
      exif: entry?.exif,
      locked: state.lockedByUser,
      cachedStats: await stats(),
      visionJpeg: () async {
        final before = renderer.before;
        if (before == null) return encodeJpegNoMetadata(proxy);
        final small = await resizeImage(before, 1024);
        final buf = await rgbaFromImage(small);
        small.dispose();
        return encodeJpegNoMetadata(buf);
      },
    );
  }

  Future<Map<AiStyle, Uint8List>>? _stylePreviews;

  /// Each AI style applied to this photo (local engine), rendered as a small
  /// PNG. Computed once per session in parallel isolates.
  Future<Map<AiStyle, Uint8List>> stylePreviews(
    AutoEditProvider local,
    DevelopSettings base,
  ) {
    // Not cached until the photo is open, so an early call can't pin an empty result.
    if (!ready.value || renderer.analysisProxy == null) {
      return Future.value(const {});
    }
    return _stylePreviews ??= _computeStylePreviews(local, base);
  }

  Future<Map<AiStyle, Uint8List>> _computeStylePreviews(
    AutoEditProvider local,
    DevelopSettings base,
  ) async {
    final proxy = renderer.analysisProxy;
    final st = await stats();
    if (proxy == null || st == null) return const {};
    final out = <AiStyle, Uint8List>{};
    await Future.wait([
      for (final style in AiStyle.values)
        () async {
          try {
            final input = AutoEditInput(
              stats: st,
              style: style,
              current: base,
              proxy: proxy,
              exif: entry?.exif,
            );
            final outcome = await _autoEditIsolated(local, input);
            if (_disposed) return;
            out[style] = await renderer.renderThumbnail(
              outcome.settings,
              longEdge: 240,
            );
          } on Exception catch (e) {
            _log.fine('style preview ${style.id} failed: $e');
          }
        }(),
    ]);
    return out;
  }

  void dispose() {
    _disposed = true;
    _thumbTimer?.cancel();
    _histTimer?.cancel();
    renderer.output.removeListener(_scheduleHistogram);
    renderer.dispose();
    ready.dispose();
    histogram.dispose();
  }
}

/// Runs auto-edit for the photo in [session] and applies it to the editor.
Future<AiRunResult?> runAutoEdit(
  WidgetRef ref,
  EditorSession session, {
  AiStyle style = AiStyle.natural,
}) async {
  final ctl = ref.read(editorProvider(session.assetId).notifier);
  final state = ref.read(editorProvider(session.assetId)).value;
  if (state == null) return null;
  final ctx = await session.aiContext(state);
  if (ctx == null) return null;
  final service = ref.read(autoEditServiceProvider);
  ctl.setAiBusy(
    true,
    status: service.visionAvailable ? 'Reading the light…' : 'Developing…',
  );
  try {
    final result = await service.autoEdit(
      ctx,
      style: style,
      onLocal: (local) {
        if (service.visionAvailable) {
          ctl.preview(local.settings);
          ctl.setAiBusy(true, status: 'Developing…');
        }
      },
    );
    ctl.preview(state.settings);
    ctl.applyAi(result.outcome.settings, result.record, label: result.label);
    return result;
  } finally {
    ctl.setAiBusy(false);
  }
}

/// Runs a describe-an-edit instruction.
Future<AiRunResult?> runInstruction(
  WidgetRef ref,
  EditorSession session,
  String instruction,
) async {
  final ctl = ref.read(editorProvider(session.assetId).notifier);
  final state = ref.read(editorProvider(session.assetId)).value;
  if (state == null) return null;
  final ctx = await session.aiContext(state);
  if (ctx == null) return null;
  final service = ref.read(autoEditServiceProvider);
  ctl.setAiBusy(
    true,
    status: service.visionAvailable ? 'Reading the light…' : 'Applying…',
  );
  try {
    final result = await service.instruct(
      ctx,
      instruction,
      baseline: state.doc.ai?.preAi,
    );
    if (result.outcome.changes.isNotEmpty) {
      ctl.applyAi(
        result.outcome.settings,
        result.record,
        label: result.label,
        kind: HistoryKind.instruction,
      );
    }
    return result;
  } finally {
    ctl.setAiBusy(false);
  }
}

Future<AutoEditOutcome> _autoEditIsolated(
  AutoEditProvider engine,
  AutoEditInput input,
) => runInBackground(() => engine.autoEdit(input));
