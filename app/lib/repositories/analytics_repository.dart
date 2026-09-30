import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../helper/api_error_handler.dart';
import '../model/analytics_model.dart';
import '../services/api_services.dart';

class AnalyticsRepository {
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
          throw Exception('Request timeout');
        },
      );
      return response;
    } catch (e) {
      rethrow;
    }
  }

  static Future<List<JanitorPerformanceModel>> getJanitorPerformance(String runInstanceId) async {
    try {
      final token = await _getToken();
      if (token == null) {
        throw Exception('AUTH_ERROR');
      }

      final uri = Uri.parse('$baseUrl/api/analytics/janitor-performance').replace(
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
        // The API returns its list under "performance".
        final list = (data['performance'] as List<dynamic>?)
                ?.map((item) => JanitorPerformanceModel.fromJson(item as Map<String, dynamic>))
                .toList() ??
            [];
        return list;
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        throw Exception('AUTH_ERROR');
      } else {
        throw Exception(ApiErrorHandler.getErrorMessage(response.body, response.statusCode));
      }
    } catch (e) {
      if (e.toString().contains('AUTH_ERROR')) {
        rethrow;
      }
      throw Exception(ApiErrorHandler.getErrorMessage(e, null));
    }
  }

  static Future<List<CoachCleanlinessModel>> getCoachCleanliness(String runInstanceId) async {
    try {
      final token = await _getToken();
      if (token == null) {
        throw Exception('AUTH_ERROR');
      }

      final uri = Uri.parse('$baseUrl/api/analytics/coach-cleanliness').replace(
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
        // The API returns its list under "coaches".
        final list = (data['coaches'] as List<dynamic>?)
                ?.map((item) => CoachCleanlinessModel.fromJson(item as Map<String, dynamic>))
                .toList() ??
            [];
        return list;
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        throw Exception('AUTH_ERROR');
      } else {
        throw Exception(ApiErrorHandler.getErrorMessage(response.body, response.statusCode));
      }
    } catch (e) {
      if (e.toString().contains('AUTH_ERROR')) {
        rethrow;
      }
      throw Exception(ApiErrorHandler.getErrorMessage(e, null));
    }
  }

  static Future<Map<String, dynamic>> getComplaintResolutionAnalytics({DateTime? startDate, DateTime? endDate}) async {
    try {
      final token = await _getToken();
      if (token == null) {
        throw Exception('AUTH_ERROR');
      }

      final queryParams = <String, String>{};
      if (startDate != null) queryParams['startDate'] = startDate.toIso8601String();
      if (endDate != null) queryParams['endDate'] = endDate.toIso8601String();

      final uri = Uri.parse('$baseUrl/api/analytics/complaint-resolution').replace(
        queryParameters: queryParams.isNotEmpty ? queryParams : null,
      );

      final response = await _handleRequest(
        () => http.get(uri, headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        }),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        throw Exception('AUTH_ERROR');
      } else {
        throw Exception(ApiErrorHandler.getErrorMessage(response.body, response.statusCode));
      }
    } catch (e) {
      if (e.toString().contains('AUTH_ERROR')) {
        rethrow;
      }
      throw Exception(ApiErrorHandler.getErrorMessage(e, null));
    }
  }

  static Future<Map<String, dynamic>> getAttendanceCompliance({required String runInstanceId}) async {
    try {
      final token = await _getToken();
      if (token == null) {
        throw Exception('AUTH_ERROR');
      }

      final uri = Uri.parse('$baseUrl/api/obhs/analytics/attendance-compliance').replace(
        queryParameters: {'runInstanceId': runInstanceId},
      );

      final response = await _handleRequest(
        () => http.get(uri, headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        }),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        throw Exception('AUTH_ERROR');
      } else {
        throw Exception(ApiErrorHandler.getErrorMessage(response.body, response.statusCode));
      }
    } catch (e) {
      if (e.toString().contains('AUTH_ERROR')) {
        rethrow;
      }
      throw Exception(ApiErrorHandler.getErrorMessage(e, null));
    }
  }

  static Future<Map<String, dynamic>> getTaskCompletionPercentage({required String runInstanceId}) async {
    try {
      final token = await _getToken();
      if (token == null) {
        throw Exception('AUTH_ERROR');
      }

      final uri = Uri.parse('$baseUrl/api/obhs/analytics/task-completion').replace(
        queryParameters: {'runInstanceId': runInstanceId},
      );

      final response = await _handleRequest(
        () => http.get(uri, headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        }),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        throw Exception('AUTH_ERROR');
      } else {
        throw Exception(ApiErrorHandler.getErrorMessage(response.body, response.statusCode));
      }
    } catch (e) {
      if (e.toString().contains('AUTH_ERROR')) {
        rethrow;
      }
      throw Exception(ApiErrorHandler.getErrorMessage(e, null));
    }
  }

  static Future<Map<String, dynamic>> getPassengerRatingTrend({required String runInstanceId}) async {
    try {
      final token = await _getToken();
      if (token == null) {
        throw Exception('AUTH_ERROR');
      }

      final uri = Uri.parse('$baseUrl/api/analytics/passenger-rating-trend').replace(
        queryParameters: {'runInstanceId': runInstanceId},
      );

      final response = await _handleRequest(
        () => http.get(uri, headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        }),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        throw Exception('AUTH_ERROR');
      } else {
        throw Exception(ApiErrorHandler.getErrorMessage(response.body, response.statusCode));
      }
    } catch (e) {
      if (e.toString().contains('AUTH_ERROR')) {
        rethrow;
      }
      throw Exception(ApiErrorHandler.getErrorMessage(e, null));
    }
  }

  static Future<Map<String, dynamic>> getPenaltyRiskReport({required String runInstanceId}) async {
    try {
      final token = await _getToken();
      if (token == null) {
        throw Exception('AUTH_ERROR');
      }

      final uri = Uri.parse('$baseUrl/api/analytics/penalty-risk').replace(
        queryParameters: {'runInstanceId': runInstanceId},
      );

      final response = await _handleRequest(
        () => http.get(uri, headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        }),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        throw Exception('AUTH_ERROR');
      } else {
        throw Exception(ApiErrorHandler.getErrorMessage(response.body, response.statusCode));
      }
    } catch (e) {
      if (e.toString().contains('AUTH_ERROR')) {
        rethrow;
      }
      throw Exception(ApiErrorHandler.getErrorMessage(e, null));
    }
  }
}
