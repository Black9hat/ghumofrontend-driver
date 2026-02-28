// lib/services/api_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import '../config.dart';

class ApiException implements Exception {
  final String message;
  final int? statusCode;
  ApiException(this.message, [this.statusCode]);

  @override
  String toString() => 'ApiException($statusCode): $message';
}

class ApiService {
  ApiService._private();
  static final ApiService instance = ApiService._private();

  Future<String?> _getToken() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    return await user.getIdToken();
  }

  Map<String, String> _authHeaders(String token, {String? contentType}) {
    final headers = <String, String>{
      'Authorization': 'Bearer $token',
      'Accept': 'application/json',
    };
    if (contentType != null) headers['Content-Type'] = contentType;
    return headers;
  }

  Future<http.Response> postJson(String path, Map<String, dynamic> body) async {
    final token = await _getToken();
    if (token == null) throw ApiException('Not authenticated');

    final uri = Uri.parse('${AppConfig.backendBaseUrl}$path');

    final res = await http
        .post(
          uri,
          headers: _authHeaders(token, contentType: 'application/json'),
          body: jsonEncode(body),
        )
        .timeout(Duration(seconds: AppConfig.requestTimeoutSeconds));

    if (res.statusCode >= 200 && res.statusCode < 300) return res;

    // try to parse friendly message
    try {
      final j = jsonDecode(res.body);
      if (j is Map && j['message'] != null) {
        throw ApiException(j['message'].toString(), res.statusCode);
      }
    } catch (_) {
      // ignore parse
    }
    throw ApiException(res.body, res.statusCode);
  }

  /// Performs multipart upload. Caller should populate request.files/fields.
  Future<http.StreamedResponse> multipartUpload(
    String path,
    http.MultipartRequest request,
  ) async {
    final token = await _getToken();
    if (token == null) throw ApiException('Not authenticated');

    // The URL must be set when constructing the MultipartRequest, not here.
    // If you need to set the URL, create the request like:
    // final request = http.MultipartRequest('POST', Uri.parse('${AppConfig.backendBaseUrl}$path'));
    // and then pass it to this method.

    // Add auth headers, keep any existing headers.
    request.headers.addAll(_authHeaders(token));

    final streamed = await request.send().timeout(
      Duration(seconds: AppConfig.requestTimeoutSeconds),
    );

    if (streamed.statusCode >= 200 && streamed.statusCode < 300)
      return streamed;

    // Read response body for error details
    final res = await http.Response.fromStream(streamed);
    try {
      final j = jsonDecode(res.body);
      if (j is Map && j['message'] != null) {
        throw ApiException(j['message'].toString(), res.statusCode);
      }
    } catch (_) {}
    throw ApiException(res.body, res.statusCode);
  }
}
