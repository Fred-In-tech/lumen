import 'package:logging/logging.dart';
import 'package:lumen_core/lumen_core.dart';
import 'package:shelf/shelf.dart';

import '../support.dart';

final Logger _log = Logger('lumen.errors');

/// Renders [GatewayException] and [ContractViolation] as the contract's error
/// envelope. Anything unexpected becomes a generic 500 without internals.
Middleware errorEnvelope() =>
    (inner) => (request) async {
      try {
        return await inner(request);
      } on HijackException {
        rethrow;
      } on GatewayException catch (e) {
        if (e.code.httpStatus >= 500 &&
            e.code != GatewayErrorCode.visionUnavailable) {
          _log.warning('${requestIdOf(request)} ${e.code.wire}: ${e.message}');
        }
        return errorResponse(e, requestIdOf(request));
      } on ContractViolation catch (e) {
        return errorResponse(
          GatewayException(e.code, e.message, details: e.details),
          requestIdOf(request),
        );
      } catch (e, st) {
        // Last-resort safety net: never leak internals to the client.
        _log.severe('${requestIdOf(request)} unhandled error', e, st);
        return errorResponse(
          const GatewayException(
            GatewayErrorCode.internalError,
            'Internal server error',
          ),
          requestIdOf(request),
        );
      }
    };
