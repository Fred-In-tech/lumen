import 'dart:math';

import 'package:shelf/shelf.dart';

import '../support.dart';

final RegExp _validId = RegExp(r'^[A-Za-z0-9._-]{1,64}$');

String _generateId(Random random) {
  final bytes = List<int>.generate(12, (_) => random.nextInt(256));
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

/// Accepts a well-formed incoming `x-request-id` or generates one, exposes it
/// to inner handlers via the request context and echoes it on every response.
Middleware requestId({Random? random}) {
  final rng = random ?? Random.secure();
  return (inner) => (request) async {
    final incoming = request.headers[kRequestIdHeader];
    final id = incoming != null && _validId.hasMatch(incoming)
        ? incoming
        : _generateId(rng);
    final response = await inner(
      request.change(context: {kRequestIdContextKey: id}),
    );
    return response.change(headers: {kRequestIdHeader: id});
  };
}
