import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../helper/api_error_handler.dart';
import '../model/water_check_model.dart';
import '../services/api_services.dart';

class WaterRepository {
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

  static Future<List<WaterCheckModel>> getWaterChecks(String runInstanceId) async {
    try {
      final token = await _getToken();
      if (token == null) {
        throw 'AUTH_ERROR';
      }

      final uri = Uri.parse('$baseUrl/api/obhs/water-checks').replace(
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
                ?.map((c) => WaterCheckModel.fromJson(c as Map<String, dynamic>))
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

  static Future<bool> submitWaterCheck({required String runInstanceId, required String coachNo, required String checkTime, required String waterStatus, bool lowWaterAlert = false, String? photoUrl}) async {
    try {
      final token = await _getToken();
      if (token == null) {
        throw 'AUTH_ERROR';
      }

      final body = <String, dynamic>{
        'runInstanceId': runInstanceId,
        'coachNo': coachNo,
        'checkTime': checkTime,
        'waterStatus': waterStatus,
        'lowWaterAlert': lowWaterAlert,
        'deviceTimestamp': DateTime.now().toUtc().toIso8601String(),
      };
      if (photoUrl != null && photoUrl.isNotEmpty) {
        body['photoUrl'] = photoUrl;
      }

      final response = await _handleRequest(
        () => http.post(
          Uri.parse('$baseUrl/api/obhs/water-checks/submit'),
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

  static Future<List<WaterCheckModel>> getLowWaterAlerts(String runInstanceId) async {
    try {
      final token = await _getToken();
      if (token == null) {
        throw 'AUTH_ERROR';
      }

      final uri = Uri.parse('$baseUrl/api/obhs/water-checks/alerts').replace(
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
        final alerts = (data['alerts'] as List<dynamic>?)
                ?.map((a) => WaterCheckModel.fromJson(a as Map<String, dynamic>))
                .toList() ??
            [];
        return alerts;
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
