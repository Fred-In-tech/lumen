import 'dart:async';

import 'package:lumen_core/lumen_core.dart' show InpaintCancelled;

import 'package:lumen/platform/cancellable_task_types.dart';

/// Web has no isolates here: runs inline; cancelling drops the result.
CancellableTask<R> runCancellable<R>(FutureOr<R> Function() fn) =>
    _InlineTask<R>(fn);

class _InlineTask<R> implements CancellableTask<R> {
  _InlineTask(FutureOr<R> Function() fn) {
    Future<R>(fn).then(
      (v) {
        if (!_done.isCompleted) _done.complete(v);
      },
      onError: (Object e, StackTrace st) {
        if (!_done.isCompleted) _done.completeError(e, st);
      },
    );
  }

  final Completer<R> _done = Completer<R>();
  bool _cancelled = false;

  @override
  Future<R> get result => _done.future;

  @override
  bool get isCancelled => _cancelled;

  @override
  void cancel() {
    if (_done.isCompleted) return;
    _cancelled = true;
    _done.completeError(const InpaintCancelled());
  }
}
