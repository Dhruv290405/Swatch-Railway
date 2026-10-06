import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class StationCleaningApi {
  static const String baseUrl = 'https://swatch-railway-0zer.onrender.com';

  static Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('auth_token');
  }

  static Future<Map<String, String>> _headers() async {
    final token = await _getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  static Future<Map<String, dynamic>> get(String endpoint, {Map<String, String>? params}) async {
    try {
      final uri = Uri.parse('$baseUrl$endpoint').replace(queryParameters: params);
      final response = await http.get(uri, headers: await _headers()).timeout(const Duration(seconds: 30));
      return {'statusCode': response.statusCode, 'body': jsonDecode(response.body)};
    } catch (e) {
      return {'statusCode': 500, 'error': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> post(String endpoint, Map<String, dynamic> body) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl$endpoint'),
        headers: await _headers(),
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 30));
      return {'statusCode': response.statusCode, 'body': jsonDecode(response.body)};
    } catch (e) {
      return {'statusCode': 500, 'error': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> put(String endpoint, Map<String, dynamic> body) async {
    try {
      final response = await http.put(
        Uri.parse('$baseUrl$endpoint'),
        headers: await _headers(),
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 30));
      return {'statusCode': response.statusCode, 'body': jsonDecode(response.body)};
    } catch (e) {
      return {'statusCode': 500, 'error': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> uploadFile(String endpoint, String filePath, String fieldName, {Map<String, String>? fields}) async {
    try {
      final request = http.MultipartRequest('POST', Uri.parse('$baseUrl$endpoint'));
      final headers = await _headers();
      request.headers.addAll(headers);
      if (fields != null) request.fields.addAll(fields);
      
      if (kIsWeb) {
        final res = await http.get(Uri.parse(filePath));
        final bytes = res.bodyBytes;
        String filename = filePath.split('/').last;
        if (!filename.contains('.')) filename += '.jpg';
        request.files.add(http.MultipartFile.fromBytes(fieldName, bytes, filename: filename));
      } else {
        request.files.add(await http.MultipartFile.fromPath(fieldName, filePath));
      }
      
      final streamedResponse = await request.send().timeout(const Duration(seconds: 60));
      final response = await http.Response.fromStream(streamedResponse);
      return {'statusCode': response.statusCode, 'body': jsonDecode(response.body)};
    } catch (e) {
      return {'statusCode': 500, 'error': e.toString()};
    }
  }
}
