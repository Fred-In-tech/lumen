import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:lumen_core/lumen_core.dart';

/// A non-2xx gateway answer or a transport failure.
class GatewayFailure implements Exception {
  const GatewayFailure(this.code, this.message, {this.retryable = false, this.status});

  final String code;
  final String message;
  final bool retryable;
  final int? status;

  @override
  String toString() => 'GatewayFailure($code: $message)';
}

/// HTTP client for the Lumen AI gateway (contract v1, PLAN.md §1.9).
class GatewayClient {
  GatewayClient({required this.baseUrl, this.token, http.Client? client, this.timeout = const Duration(seconds: 45)})
      : _client = client ?? http.Client();

  final String baseUrl;
  final String? token;
  final Duration timeout;
  final http.Client _client;

  Uri _uri(String path) => Uri.parse(baseUrl.endsWith('/') ? '${baseUrl.substring(0, baseUrl.length - 1)}$path' : '$baseUrl$path');

  Map<String, String> get _headers => {
        'content-type': 'application/json',
        if (token != null && token!.isNotEmpty) 'authorization': 'Bearer $token',
      };

  Future<HealthResponse> health() async {
    try {
      final r = await _client.get(_uri(GatewayPaths.health), headers: _headers).timeout(const Duration(seconds: 4));
      if (r.statusCode != 200) throw GatewayFailure('http_${r.statusCode}', 'Gateway health check failed', status: r.statusCode);
      return HealthResponse.fromJson(jsonDecode(r.body));
    } on TimeoutException {
      throw const GatewayFailure('timeout', 'Gateway did not answer', retryable: true);
    } on http.ClientException catch (e) {
      throw GatewayFailure('offline', e.message, retryable: true);
    } on FormatException {
      throw const GatewayFailure('bad_response', 'Gateway sent an unreadable answer');
    }
  }

  Future<GatewayEditResponse> autoEdit(AutoEditRequest request) => _post(GatewayPaths.autoEdit, request.toJson());

  Future<GatewayEditResponse> instruct(InstructRequest request) => _post(GatewayPaths.instruct, request.toJson());

  Future<GatewayEditResponse> _post(String path, Map<String, Object?> body) async {
    try {
      final r = await _client.post(_uri(path), headers: _headers, body: jsonEncode(body)).timeout(timeout);
      final json = jsonDecode(r.body);
      if (r.statusCode == 200) return GatewayEditResponse.fromJson(json);
      final env = GatewayErrorEnvelope.fromJson(json);
      throw GatewayFailure(env.error.code.wire, env.error.message, retryable: env.error.retryable, status: r.statusCode);
    } on TimeoutException {
      throw const GatewayFailure('timeout', 'AI took too long', retryable: true);
    } on http.ClientException catch (e) {
      throw GatewayFailure('offline', e.message, retryable: true);
    } on FormatException {
      throw const GatewayFailure('bad_response', 'Gateway sent an unreadable answer');
    }
  }

  void close() => _client.close();
}
