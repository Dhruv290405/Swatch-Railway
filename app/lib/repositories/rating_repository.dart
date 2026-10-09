import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../helper/api_error_handler.dart';
import '../model/rating_model.dart';
import '../services/api_services.dart';

class RatingRepository {
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

  static Future<bool> submitRating({required String runInstanceId, required String source, required int rating, String? coachNo, String? employeeId, String? remarks}) async {
    try {
      final token = await _getToken();
      if (token == null) {
        throw 'AUTH_ERROR';
      }

      final body = <String, dynamic>{
        'runInstanceId': runInstanceId,
        'source': source,
        'rating': rating,
        'deviceTimestamp': DateTime.now().toUtc().toIso8601String(),
      };
      if (coachNo != null && coachNo.isNotEmpty) body['coachNo'] = coachNo;
      if (employeeId != null && employeeId.isNotEmpty) body['employeeId'] = employeeId;
      if (remarks != null && remarks.isNotEmpty) body['remarks'] = remarks;

      final response = await _handleRequest(
        () => http.post(
          Uri.parse('$baseUrl/api/obhs/ratings/submit'),
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

  static Future<List<RatingModel>> getRatingsForEmployee(String employeeId) async {
    try {
      final token = await _getToken();
      if (token == null) {
        throw 'AUTH_ERROR';
      }

      final uri = Uri.parse('$baseUrl/api/obhs/ratings/employee/$employeeId');

      final response = await _handleRequest(
        () => http.get(uri, headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final ratings = (data['ratings'] as List<dynamic>?)
                ?.map((r) => RatingModel.fromJson(r as Map<String, dynamic>))
                .toList() ??
            [];
        return ratings;
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

  static Future<Map<String, dynamic>> getPerformanceScore(String employeeId) async {
    try {
      final token = await _getToken();
      if (token == null) {
        throw 'AUTH_ERROR';
      }

      final response = await _handleRequest(
        () => http.get(
          Uri.parse('$baseUrl/api/obhs/ratings/performance/$employeeId'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
        ),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
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
