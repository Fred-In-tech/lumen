import 'dart:typed_data';

import 'package:lumen_core/lumen_core.dart';
import 'package:shelf/shelf.dart';

import '../support.dart';

GatewayException _tooLarge(int max) => GatewayException(
  GatewayErrorCode.payloadTooLarge,
  'Request body exceeds $max bytes',
  details: {'maxBytes': max},
);

/// Rejects bodies over [maxBytes] with 413, by `content-length` up front and
/// by counting while reading (chunked uploads). Inner handlers get the
/// already-buffered body.
Middleware bodyLimit(int maxBytes) =>
    (inner) => (request) async {
      final declared = request.contentLength;
      if (declared != null && declared > maxBytes) throw _tooLarge(maxBytes);
      if (request.method == 'GET' || request.method == 'HEAD') {
        return inner(request);
      }
      final buffer = BytesBuilder(copy: false);
      await for (final chunk in request.read()) {
        buffer.add(chunk);
        if (buffer.length > maxBytes) throw _tooLarge(maxBytes);
      }
      return inner(request.change(body: buffer.takeBytes()));
    };
