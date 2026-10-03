import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:lumen_core/lumen_core.dart';
import 'package:shelf/shelf.dart';

import '../support.dart';

/// Compares two secrets in time independent of where they differ (both are
/// hashed first, so length differences do not leak either).
bool constantTimeEquals(String a, String b) {
  final da = sha256.convert(utf8.encode(a)).bytes;
  final db = sha256.convert(utf8.encode(b)).bytes;
  var diff = 0;
  for (var i = 0; i < da.length; i++) {
    diff |= da[i] ^ db[i];
  }
  return diff == 0;
}

/// When [token] is set, requires `Authorization: Bearer <token>` on every
/// path except [publicPaths]. Placeholder until per-user ID tokens.
Middleware bearerAuth(String? token, {Set<String> publicPaths = const {}}) {
  if (token == null || token.isEmpty) return (inner) => inner;
  return (inner) => (request) {
    if (publicPaths.contains(pathOf(request))) return inner(request);
    final header = request.headers['authorization'] ?? '';
    const prefix = 'bearer ';
    final ok =
        header.length > prefix.length &&
        header.substring(0, prefix.length).toLowerCase() == prefix &&
        constantTimeEquals(header.substring(prefix.length).trim(), token);
    if (!ok) {
      throw const GatewayException(
        GatewayErrorCode.unauthorized,
        'Missing or invalid bearer token',
      );
    }
    return inner(request);
  };
}
