import 'package:lumen_core/lumen_core.dart';
import 'package:shelf/shelf.dart';

import '../edit/edit_service.dart';
import '../support.dart';
import 'json_body.dart';

/// `POST /v1/auto-edit`: style-driven edit, absolute values.
Handler autoEditHandler(EditService service) => (Request request) async {
  service.ensureAvailable();
  final body = AutoEditRequest.fromJson(await readJsonBody(request));
  final result = await service.autoEdit(
    body,
    requestId: requestIdOf(request) ?? '',
  );
  return jsonResponse(200, result.toJson());
};
