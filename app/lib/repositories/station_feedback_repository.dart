import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../model/station_feedback_model.dart';
import '../services/api_services.dart';

class StationFeedbackRepository {
  static String get baseUrl => ApiService.baseUrl;

  static Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('token');
  }

  static Future<Map<String, dynamic>> _handleResponse(http.Response response) async {
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw 'AUTH_ERROR';
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> sendOtp(String phone, {String? stationId}) async {
    final body = <String, dynamic>{'phone': phone};
    if (stationId != null) body['stationId'] = stationId;
    final response = await http.post(
      Uri.parse('$baseUrl/api/station-feedback/send-otp'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> verifyOtp(String phone, String otp) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/station-feedback/verify-otp'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'phone': phone, 'otp': otp}),
    );
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> submit(Map<String, dynamic> body) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/station-feedback/submit'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  static Future<List<StationFeedback>> list({String? stationId, String? category}) async {
    final token = await _getToken();
    if (token == null) throw 'AUTH_ERROR';
    var url = '$baseUrl/api/station-feedback/list?';
    if (stationId != null) url += 'stationId=$stationId&';
    if (category != null) url += 'category=$category&';
    final response = await http.get(
      Uri.parse(url),
      headers: {'Authorization': 'Bearer $token'},
    );
    final data = await _handleResponse(response);
    return (data['feedbacks'] as List<dynamic>?)?.map<StationFeedback>((e) => StationFeedback.fromJson(e)).toList() ?? <StationFeedback>[];
  }

  static Future<FeedbackSummary> getSummary(String stationId) async {
    final token = await _getToken();
    if (token == null) throw 'AUTH_ERROR';
    final response = await http.get(
      Uri.parse('$baseUrl/api/station-feedback/summary/$stationId'),
      headers: {'Authorization': 'Bearer $token'},
    );
    final data = await _handleResponse(response);
    return FeedbackSummary.fromJson(data);
  }

  static Future<Map<String, dynamic>> getQrData(String stationId) async {
    final token = await _getToken();
    if (token == null) throw 'AUTH_ERROR';
    final response = await http.get(
      Uri.parse('$baseUrl/api/station-feedback/qr/$stationId'),
      headers: {'Authorization': 'Bearer $token'},
    );
    return jsonDecode(response.body) as Map<String, dynamic>;
  }
}
