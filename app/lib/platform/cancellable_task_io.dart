import 'dart:async';
import 'dart:isolate';

import 'package:lumen_core/lumen_core.dart' show InpaintCancelled;

import 'package:lumen/platform/cancellable_task_types.dart';

/// Runs [fn] on its own isolate; [CancellableTask.cancel] kills it.
CancellableTask<R> runCancellable<R>(FutureOr<R> Function() fn) =>
    _IsolateTask<R>(fn);

class _IsolateTask<R> implements CancellableTask<R> {
  _IsolateTask(FutureOr<R> Function() fn) {
    _port.handler = _onMessage;
    Isolate.spawn<_Request>(
      _runRequest,
      _Request(fn, _port.sendPort),
      onExit: _port.sendPort,
      onError: _port.sendPort,
    ).then(
      (isolate) {
        _isolate = isolate;
        if (_cancelled) isolate.kill(priority: Isolate.immediate);
      },
      onError: (Object e, StackTrace st) {
        _port.close();
        if (!_done.isCompleted) _done.completeError(e, st);
      },
    );
  }

  final RawReceivePort _port = RawReceivePort();
  final Completer<R> _done = Completer<R>();
  Isolate? _isolate;
  bool _cancelled = false;

  @override
  Future<R> get result => _done.future;

  @override
  bool get isCancelled => _cancelled;

  @override
  void cancel() {
    if (_done.isCompleted) return;
    _cancelled = true;
    _isolate?.kill(priority: Isolate.immediate);
    _port.close();
    _done.completeError(const InpaintCancelled());
  }

  void _onMessage(Object? message) {
    _port.close();
    if (_done.isCompleted) return;
    switch (message) {
      case _Ok(:final value):
        _done.complete(value as R);
      case _Failed(:final error, :final stack):
        _done.completeError(RemoteError(error, stack));
      // Uncaught async error reported by `onError`: [error, stack].
      case [final Object? error, final Object? stack]:
        _done.completeError(RemoteError('$error', '$stack'));
      default:
        _done.completeError(
          StateError('The background task ended without a result'),
        );
    }
  }
}

class _Request {
  const _Request(this.fn, this.port);
  final FutureOr<Object?> Function() fn;
  final SendPort port;
}

class _Ok {
  const _Ok(this.value);
  final Object? value;
}

class _Failed {
  const _Failed(this.error, this.stack);
  final String error;
  final String stack;
}

Future<void> _runRequest(_Request request) async {
  Object message;
  try {
    message = _Ok(await request.fn());
  } on Object catch (e, st) {
    // Everything crosses back as text: exception types do not survive the
    // isolate boundary.
    message = _Failed('$e', '$st');
  }
  Isolate.exit(request.port, message);
}
