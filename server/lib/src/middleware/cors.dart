import 'package:shelf/shelf.dart';

import '../support.dart';

/// Permissive CORS for the web build. Bearer tokens, not cookies, so a
/// wildcard origin is safe; restrict with `LUMEN_CORS_ORIGIN`.
Middleware cors({String origin = '*'}) {
  final headers = {
    'access-control-allow-origin': origin,
    'access-control-allow-methods': 'GET, POST, OPTIONS',
    'access-control-allow-headers':
        'authorization, content-type, $kRequestIdHeader',
    'access-control-expose-headers': '$kRequestIdHeader, retry-after',
    'access-control-max-age': '600',
    if (origin != '*') 'vary': 'origin',
  };
  return (inner) => (request) async {
    if (request.method == 'OPTIONS') {
      return Response(204, headers: headers);
    }
    final response = await inner(request);
    return response.change(headers: headers);
  };
}
