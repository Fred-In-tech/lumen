import 'package:lumen_core/lumen_core.dart';
import 'package:shelf/shelf.dart';

import '../edit/edit_service.dart';
import '../support.dart';
import 'json_body.dart';

/// `POST /v1/instruct`: natural-language edit, values are deltas from
/// `current`.
Handler instructHandler(EditService service) => (Request request) async {
  service.ensureAvailable();
  final body = InstructRequest.fromJson(await readJsonBody(request));
  final result = await service.instruct(
    body,
    requestId: requestIdOf(request) ?? '',
  );
  return jsonResponse(200, result.toJson());
};
