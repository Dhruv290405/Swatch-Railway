import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../helper/api_error_handler.dart';
import '../model/safety_check_model.dart';
import '../services/api_services.dart';

class SafetyRepository {
  static String get baseUrl => ApiService.baseUrl;

  static Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('token');
  }

  static Future<http.Response> _handleRequest(
    Future<http.Response> Function() request,
  ) async {
    try {
      final response = await request().timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw 'Request timeout';
        },
      );
      return response;
    } catch (e) {
      rethrow;
    }
  }

  static Future<List<SafetyCheckModel>> getSafetyChecks(String runInstanceId) async {
    try {
      final token = await _getToken();
      if (token == null) {
        throw 'AUTH_ERROR';
      }

      final uri = Uri.parse('$baseUrl/api/obhs/safety-checks').replace(
        queryParameters: {'runInstanceId': runInstanceId},
      );

      final response = await _handleRequest(
        () => http.get(uri, headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final checks = (data['checks'] as List<dynamic>?)
                ?.map((c) => SafetyCheckModel.fromJson(c as Map<String, dynamic>))
                .toList() ??
            [];
        return checks;
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        throw 'AUTH_ERROR';
      } else {
        throw ApiErrorHandler.getErrorMessage(response.body, response.statusCode);
      }
    } catch (e) {
      if (e.toString().contains('AUTH_ERROR')) {
        rethrow;
      }
      throw ApiErrorHandler.getErrorMessage(e, null);
    }
  }

  static Future<bool> submitSafetyCheck({required SafetyCheckModel check}) async {
    try {
      final token = await _getToken();
      if (token == null) {
        throw 'AUTH_ERROR';
      }

      final response = await _handleRequest(
        () => http.post(
          Uri.parse('$baseUrl/api/obhs/safety-checks/submit'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode({
            ...check.toJson(),
            'deviceTimestamp': DateTime.now().toUtc().toIso8601String(),
          }),
        ),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        return true;
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        throw 'AUTH_ERROR';
      } else {
        throw ApiErrorHandler.getErrorMessage(response.body, response.statusCode);
      }
    } catch (e) {
      if (e.toString().contains('AUTH_ERROR')) {
        rethrow;
      }
      throw ApiErrorHandler.getErrorMessage(e, null);
    }
  }

  static Future<bool> reportDeficiency({required String checkId, required String deficiencyReport, required String photoUrl}) async {
    try {
      final token = await _getToken();
      if (token == null) {
        throw 'AUTH_ERROR';
      }

      final body = <String, dynamic>{
        'checkId': checkId,
        'deficiencyReport': deficiencyReport,
        'photoUrl': photoUrl,
        'deviceTimestamp': DateTime.now().toUtc().toIso8601String(),
      };

      final response = await _handleRequest(
        () => http.post(
          Uri.parse('$baseUrl/api/obhs/safety-checks/report-deficiency'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode(body),
        ),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        return true;
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        throw 'AUTH_ERROR';
      } else {
        throw ApiErrorHandler.getErrorMessage(response.body, response.statusCode);
      }
    } catch (e) {
      if (e.toString().contains('AUTH_ERROR')) {
        rethrow;
      }
      throw ApiErrorHandler.getErrorMessage(e, null);
    }
  }
}
