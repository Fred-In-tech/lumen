import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/ai/ondevice/inference_backend.dart';
import 'package:lumen/ai/ondevice/model_store.dart';
import 'package:lumen/ai/ondevice/ondevice_providers.dart';
import 'package:lumen/features/remove/migan_inpaint_model.dart';

final _log = Logger('AiRemover');

enum AiRemoverPhase {
  /// Not loaded (never asked for, or the user turned AI fill off first).
  off,

  /// Looking for an earlier download.
  checking,
  downloading,

  /// Downloaded and verified; the runtime is loading it.
  loading,
  ready,

  /// Download or load failed; classic fill is used. Retry is possible.
  failed,

  /// No on-device runtime here (web); classic fill only.
  unavailable,
}

/// The on-device AI remover (MI-GAN) as the Remove panel shows it.
class AiRemoverState {
  const AiRemoverState({
    this.phase = AiRemoverPhase.off,
    this.enabled = false,
    this.progress,
    this.message,
    this.model,
  });

  final AiRemoverPhase phase;

  /// The user wants AI fill for large objects.
  final bool enabled;

  /// Download progress (0–1), null when unknown.
  final double? progress;

  /// Why the remover is failed or unavailable, written for the user.
  final String? message;
  final InpaintModel? model;

  /// AI fill will be used for the next large removal.
  bool get usable => enabled && phase == AiRemoverPhase.ready && model != null;

  bool get busy =>
      phase == AiRemoverPhase.checking ||
      phase == AiRemoverPhase.downloading ||
      phase == AiRemoverPhase.loading;

  AiRemoverState copyWith({
    AiRemoverPhase? phase,
    bool? enabled,
    double? progress,
    String? message,
    InpaintModel? model,
  }) => AiRemoverState(
    phase: phase ?? this.phase,
    enabled: enabled ?? this.enabled,
    progress: progress,
    message: message,
    model: model ?? this.model,
  );
}

/// Finds, downloads and loads the AI remover.
abstract interface class AiRemoverLoader {
  /// Download size, for "Downloading AI remover · 16 MB".
  int get downloadBytes;

  /// True when an earlier (user-approved) download is on this device.
  Future<bool> isInstalled();

  /// Downloads (if needed, reporting [onProgress]) and loads the model.
  Future<InpaintModel> load({
    required void Function(double? fraction) onProgress,
    CancelToken? cancel,
  });
}

/// The real loader: the shared `ModelStore` (SHA-256 verified download)
/// and the LiteRT backend, with the tensor contract asserted.
class StoreAiRemoverLoader implements AiRemoverLoader {
  StoreAiRemoverLoader(this._ref);

  final Ref _ref;

  @override
  int get downloadBytes => kMiganSpec.bytes;

  @override
  Future<bool> isInstalled() async {
    final store = await _ref.read(modelStoreProvider.future);
    return await store.readyPath(kMiganSpec) != null;
  }

  @override
  Future<InpaintModel> load({
    required void Function(double? fraction) onProgress,
    CancelToken? cancel,
  }) async {
    final store = await _ref.read(modelStoreProvider.future);
    final sub = store.progress
        .where((p) => p.modelId == kMiganSpec.id)
        .listen((p) => onProgress(p.fraction));
    try {
      final result = await store.ensure(kMiganSpec, cancel: cancel);
      final path = switch (result) {
        ModelReady(:final path) => path,
        ModelFailed(:final error) => throw error,
      };
      final session = await loadVerifiedSession(
        _ref.read(inferenceBackendProvider),
        kMiganSpec,
        ModelFileSource(path),
      );
      try {
        return MiganInpaintModel(session);
      } on ModelContractMismatch {
        await session.dispose();
        rethrow;
      }
    } finally {
      await sub.cancel();
    }
  }
}

final aiRemoverLoaderProvider = Provider<AiRemoverLoader>(
  StoreAiRemoverLoader.new,
);

/// "16 MB" for [bytes].
String megabytes(int bytes) => '${(bytes / 1e6).round()} MB';

class AiRemoverNotifier extends Notifier<AiRemoverState> {
  CancelToken? _cancel;
  bool _probed = false;

  /// Kept outside [state]: `state` is off limits while disposing.
  InpaintModel? _model;

  AiRemoverLoader get _loader => ref.read(aiRemoverLoaderProvider);

  @override
  AiRemoverState build() {
    ref.onDispose(() {
      _cancel?.cancel();
      final m = _model;
      if (m is MiganInpaintModel) unawaited(m.dispose());
    });
    return const AiRemoverState();
  }

  /// Called when the Remove panel opens: an earlier download is loaded and
  /// switched on (that download was the user's approval). Never downloads.
  Future<void> probe() async {
    if (_probed) return;
    _probed = true;
    state = state.copyWith(phase: AiRemoverPhase.checking);
    try {
      if (await _loader.isInstalled()) {
        await _load();
      } else {
        state = state.copyWith(phase: AiRemoverPhase.off);
      }
    } on Exception catch (e) {
      _log.info('AI remover probe failed: $e');
      state = state.copyWith(
        phase: AiRemoverPhase.unavailable,
        message: _unavailableMessage,
      );
    }
  }

  /// The user switched AI fill on: downloads on first use, then loads.
  Future<void> enable() async {
    state = state.copyWith(enabled: true, phase: state.phase);
    if (state.phase == AiRemoverPhase.ready || state.busy) return;
    if (state.phase == AiRemoverPhase.unavailable) return;
    await _load();
  }

  /// AI fill off: removals use the classic engines (the model stays loaded).
  void disable() => state = state.copyWith(enabled: false, phase: state.phase);

  void cancelDownload() => _cancel?.cancel();

  static const _unavailableMessage =
      'AI fill isn’t available on this device; classic fill is used.';

  Future<void> _load() async {
    final cancel = _cancel = CancelToken();
    state = state.copyWith(enabled: true, phase: AiRemoverPhase.downloading);
    try {
      final model = await _loader.load(
        cancel: cancel,
        onProgress: (f) {
          if (state.phase == AiRemoverPhase.downloading) {
            state = state.copyWith(
              phase: AiRemoverPhase.downloading,
              progress: f,
            );
          }
          if (f != null && f >= 1) {
            state = state.copyWith(phase: AiRemoverPhase.loading);
          }
        },
      );
      _model = model;
      state = state.copyWith(
        phase: AiRemoverPhase.ready,
        enabled: true,
        model: model,
      );
    } on ModelDownloadCancelled {
      state = state.copyWith(phase: AiRemoverPhase.off, enabled: false);
    } on InferenceUnavailable {
      state = state.copyWith(
        phase: AiRemoverPhase.unavailable,
        enabled: false,
        message: _unavailableMessage,
      );
    } on ModelStoreError catch (e) {
      _fail('the download failed (${e.message})', e);
    } on InferenceException catch (e) {
      _fail('the model could not start (${e.message})', e);
    } on Exception catch (e) {
      _fail('$e', e);
    } finally {
      if (identical(_cancel, cancel)) _cancel = null;
    }
  }

  void _fail(String why, Object e) {
    _log.warning('AI remover failed: $e');
    state = state.copyWith(
      phase: AiRemoverPhase.failed,
      enabled: false,
      message: 'AI remover unavailable: $why. Classic fill is used.',
    );
  }
}

final aiRemoverProvider = NotifierProvider<AiRemoverNotifier, AiRemoverState>(
  AiRemoverNotifier.new,
);
