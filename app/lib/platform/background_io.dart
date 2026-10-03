import 'dart:async';
import 'dart:isolate';

/// Runs [fn] on a short-lived background isolate (native platforms).
///
/// Call it from a top-level function so the closure captures only its
/// arguments, not UI objects (unsendable values throw).
Future<T> runInBackground<T>(FutureOr<T> Function() fn) => Isolate.run(fn);
