import 'dart:async';
import 'dart:typed_data';

import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/platform/platform_info.dart';

/// Cooperative cancellation for a model download.
class CancelToken {
  final Completer<void> _done = Completer<void>();

  bool get isCancelled => _done.isCompleted;

  /// Completes (never with an error) when [cancel] is called; also used as
  /// the HTTP abort trigger.
  Future<void> get whenCancelled => _done.future;

  void cancel() {
    if (!_done.isCompleted) _done.complete();
  }
}

enum ModelPhase { checking, downloading, verifying, ready, failed }

/// One progress event from [ModelStore.progress].
class ModelProgress {
  const ModelProgress({
    required this.modelId,
    required this.phase,
    this.receivedBytes = 0,
    this.totalBytes = 0,
  });

  final String modelId;
  final ModelPhase phase;
  final int receivedBytes;
  final int totalBytes;

  double? get fraction =>
      totalBytes <= 0 ? null : (receivedBytes / totalBytes).clamp(0.0, 1.0);

  @override
  String toString() =>
      'ModelProgress($modelId, ${phase.name}, $receivedBytes/$totalBytes)';
}

/// Why a model is not ready. Exhaustive: switch on it in the UI.
sealed class ModelStoreError implements Exception {
  const ModelStoreError();
  String get message;

  @override
  String toString() => '$runtimeType: $message';
}

/// The spec is unpinned or disabled ([ModelSpec.requireLoadable]).
final class ModelRefused extends ModelStoreError {
  const ModelRefused(this.cause);
  final ModelSpecException cause;

  @override
  String get message => cause.message;
}

/// The file's SHA-256 differs from the pinned one (file deleted).
final class ModelChecksumMismatch extends ModelStoreError {
  const ModelChecksumMismatch({required this.expected, required this.actual});
  final String expected;
  final String actual;

  @override
  String get message => 'SHA-256 $actual != pinned $expected';
}

/// The server sent more bytes than the spec allows (file deleted).
final class ModelSizeMismatch extends ModelStoreError {
  const ModelSizeMismatch({required this.expected, required this.actual});
  final int expected;
  final int actual;

  @override
  String get message => 'got $actual bytes, expected $expected';
}

/// Free space is below 2 × size + 200 MB.
final class InsufficientDiskSpace extends ModelStoreError {
  const InsufficientDiskSpace({
    required this.requiredBytes,
    required this.availableBytes,
  });
  final int requiredBytes;
  final int availableBytes;

  @override
  String get message =>
      'needs $requiredBytes bytes free, $availableBytes available';
}

/// Network/HTTP failure. The partial file is kept so the next try resumes.
final class ModelDownloadFailed extends ModelStoreError {
  const ModelDownloadFailed(this.message, {this.statusCode});
  @override
  final String message;
  final int? statusCode;
}

/// Cancelled through a [CancelToken]. The partial file is kept.
final class ModelDownloadCancelled extends ModelStoreError {
  const ModelDownloadCancelled();

  @override
  String get message => 'download cancelled';
}

/// A bundled model's asset is missing from the app build.
final class BundledModelMissing extends ModelStoreError {
  const BundledModelMissing(this.assetKey);
  final String assetKey;

  @override
  String get message => 'bundled asset $assetKey not found';
}

/// Reading or writing the model directory failed.
final class ModelStorageFailed extends ModelStoreError {
  const ModelStorageFailed(this.message);
  @override
  final String message;
}

sealed class ModelResult {
  const ModelResult(this.spec);
  final ModelSpec spec;
}

/// [path] is a file whose SHA-256 was verified in this session.
final class ModelReady extends ModelResult {
  const ModelReady(super.spec, this.path);
  final String path;
}

final class ModelFailed extends ModelResult {
  const ModelFailed(super.spec, this.error);
  final ModelStoreError error;
}

/// Loads a bundled asset's bytes; null when the asset is not in the build.
typedef BundledModelLoader = Future<Uint8List?> Function(String assetKey);

/// Download-on-first-use model cache (research 07 §6.2). Never hands out a
/// path to a file whose hash was not verified.
abstract interface class ModelStore {
  Stream<ModelProgress> get progress;

  /// Resolves [spec] to a verified local file: bundled asset, existing
  /// download, or a fresh/resumed download. Concurrent calls for the same
  /// spec share one operation (the first caller's [cancel] token governs).
  Future<ModelResult> ensure(ModelSpec spec, {CancelToken? cancel});

  /// The verified path if [spec] is already local; never downloads.
  Future<String?> readyPath(ModelSpec spec);

  /// Evicts least-recently-used downloaded models above the budget.
  Future<void> evictToBudget();

  Future<void> dispose();
}

/// Per-platform cache budgets for downloaded (non-bundled) models.
abstract final class ModelBudget {
  static const mobileBytes = 150 * 1024 * 1024;
  static const desktopBytes = 500 * 1024 * 1024;

  static int forPlatform(PlatformInfo p) =>
      p.isMobile ? mobileBytes : desktopBytes;
}

/// Disk guard: free space needed before downloading a model of [bytes].
int requiredFreeBytes(int bytes) => 2 * bytes + 200 * 1024 * 1024;
