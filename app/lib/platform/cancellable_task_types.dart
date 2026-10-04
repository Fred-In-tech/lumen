import 'dart:async';

/// A background computation that can be abandoned.
///
/// [cancel] completes [result] with `InpaintCancelled` at once; on native
/// platforms it also kills the worker isolate, so the CPU is freed.
abstract interface class CancellableTask<R> {
  Future<R> get result;

  bool get isCancelled;

  void cancel();
}

/// Starts [fn] in the background. Like `runInBackground`, call it from a
/// top-level function so the closure captures only sendable arguments.
typedef CancellableRunner = CancellableTask<R> Function<R>(
  FutureOr<R> Function() fn,
);
