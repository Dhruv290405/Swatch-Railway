import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../helper/api_error_handler.dart';
import '../model/petty_repair_model.dart';
import '../services/api_services.dart';

class RepairRepository {
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

  static Future<List<PettyRepairModel>> getRepairs(String runInstanceId) async {
    try {
      final token = await _getToken();
      if (token == null) {
        throw Exception('AUTH_ERROR');
      }

      final uri = Uri.parse('$baseUrl/api/obhs/petty-repairs').replace(
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
        final repairs = (data['repairs'] as List<dynamic>?)
                ?.map((r) => PettyRepairModel.fromJson(r as Map<String, dynamic>))
                .toList() ??
            [];
        return repairs;
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

  static Future<bool> submitRepairInspection({required PettyRepairModel repair}) async {
    try {
      final token = await _getToken();
      if (token == null) {
        throw Exception('AUTH_ERROR');
      }

      final response = await _handleRequest(
        () => http.post(
          Uri.parse('$baseUrl/api/obhs/petty-repairs'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode({
            ...repair.toJson(),
            // The backend keys updates off `repairId`; without this every edit
            // would be treated as a new inspection.
            'repairId': repair.id.isNotEmpty ? repair.id : null,
            'deviceTimestamp': DateTime.now().toUtc().toIso8601String(),
          }),
        ),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        return true;
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

  static Future<bool> escalateRepair(String repairId, {required String escalatedTo}) async {
    try {
      final token = await _getToken();
      if (token == null) {
        throw Exception('AUTH_ERROR');
      }

      final body = <String, dynamic>{
        'repairId': repairId,
        'escalatedTo': escalatedTo,
        'deviceTimestamp': DateTime.now().toUtc().toIso8601String(),
      };

      final response = await _handleRequest(
        () => http.post(
          Uri.parse('$baseUrl/api/obhs/petty-repairs/escalate'),
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
