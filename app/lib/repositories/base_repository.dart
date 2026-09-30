import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../helper/api_error_handler.dart';
import '../services/api_services.dart';

class BaseRepository {
  static String get baseUrl => ApiService.baseUrl;

  static Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('token');
  }

  static Future<http.Response> _handleRequest(
    Future<http.Response> Function() request, {
    bool allowRetry = false,
  }) async {
    for (var attempt = 0; ; attempt++) {
      try {
        final response = await request().timeout(
          const Duration(seconds: 30),
          onTimeout: () => throw TimeoutException('Request timeout'),
        );
        if (attempt == 0 || (response.statusCode >= 200 && response.statusCode < 400)) {
          return response;
        }
        // 5xx / 429 are worth one more shot; 4xx will fail again identically.
        if (response.statusCode < 500 && response.statusCode != 429) return response;
      } catch (e) {
        final text = e.toString();
        final transient = text.contains('SocketException') ||
            text.contains('TimeoutException') ||
            text.contains('HttpException') ||
            text.contains('Connection reset') ||
            text.contains('Connection closed') ||
            text.contains('Request timeout') ||
            text.contains('HandshakeException');
        if (!allowRetry || attempt > 0 || !transient) rethrow;
      }
      await Future.delayed(Duration(milliseconds: 600 * (attempt + 1)));
    }
  }

  static Future<T> apiCall<T>({
    required String method,
    required String path,
    Map<String, dynamic>? body,
    required T Function(Map<String, dynamic>) parser,
    Map<String, String>? queryParams,
  }) async {
    try {
      final token = await _getToken();
      if (token == null) throw Exception('AUTH_ERROR');

      final uri = Uri.parse('$baseUrl$path').replace(queryParameters: queryParams);
      final headers = {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      };

      late http.Response response;
      switch (method) {
        case 'GET':
          response = await _handleRequest(() => http.get(uri, headers: headers), allowRetry: true);
          break;
        case 'POST':
          response = await _handleRequest(() => http.post(uri, headers: headers, body: jsonEncode(body)));
          break;
        case 'PUT':
          response = await _handleRequest(() => http.put(uri, headers: headers, body: jsonEncode(body)));
          break;
        case 'DELETE':
          response = await _handleRequest(() => http.delete(uri, headers: headers));
          break;
        case 'PATCH':
          response = await _handleRequest(() => http.patch(uri, headers: headers, body: jsonEncode(body)));
          break;
        default:
          throw Exception('Unsupported method: $method');
      }

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return parser(data);
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        throw Exception('AUTH_ERROR');
      } else {
        throw Exception(ApiErrorHandler.getErrorMessage(response.body, response.statusCode));
      }
    } catch (e) {
      if (e.toString().contains('AUTH_ERROR')) rethrow;
      throw Exception(ApiErrorHandler.getErrorMessage(e, null));
    }
  }

  static Future<List<T>> apiCallList<T>({
    required String method,
    required String path,
    Map<String, dynamic>? body,
    required T Function(Map<String, dynamic>) parser,
    Map<String, String>? queryParams,
    String dataKey = 'data',
  }) async {
    return apiCall<List<T>>(
      method: method,
      path: path,
      body: body,
      queryParams: queryParams,
      parser: (json) {
        final list = json[dataKey] as List? ?? [];
        return list.map((e) => parser(e as Map<String, dynamic>)).toList();
      },
    );
  }
}
