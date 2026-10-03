import 'dart:async';

/// Web has no isolates here: run inline (the web build is a demo target).
Future<T> runInBackground<T>(FutureOr<T> Function() fn) async => fn();
