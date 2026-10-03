import 'dart:convert';

import 'package:lumen_core/lumen_core.dart';
import 'package:shelf/shelf.dart';

import '../support.dart';

/// Reads the (already size-limited) body as UTF-8 JSON.
Future<Object?> readJsonBody(Request request) async {
  final String text;
  try {
    text = await request.readAsString(utf8);
  } on FormatException {
    throw const GatewayException(
      GatewayErrorCode.invalidRequest,
      'Body is not valid UTF-8',
    );
  }
  try {
    return jsonDecode(text);
  } on FormatException {
    throw const GatewayException(
      GatewayErrorCode.invalidRequest,
      'Body is not valid JSON',
    );
  }
}
