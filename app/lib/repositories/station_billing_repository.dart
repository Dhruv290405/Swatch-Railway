import 'dart:convert';
import 'package:http/http.dart' as http;
import '../services/api_services.dart';
import '../model/station_cleaning_models.dart';

class StationBillingRepository {
  static String get baseUrl => ApiService.baseUrl;

  static Future<Map<String, String>> _headers() async {
    final token = await ApiService.getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  static Future<StationBillingPack> generate(String contractId, String stationId, int month, int year) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/station-billing/generate'),
      headers: await _headers(),
      body: jsonEncode({
        'contractId': contractId,
        'stationId': stationId,
        'month': month,
        'year': year,
      }),
    );
    if (response.statusCode == 201 || response.statusCode == 200) {
      final body = jsonDecode(response.body);
      return StationBillingPack.fromJson(body['pack'] ?? body);
    }
    throw jsonDecode(response.body)['message'] ?? 'Failed to generate billing pack';
  }

  static Future<List<StationBillingPack>> list(Map<String, String> query) async {
    final uri = Uri.parse('$baseUrl/api/station-billing').replace(queryParameters: query);
    final response = await http.get(uri, headers: await _headers());
    if (response.statusCode == 200) {
      final body = jsonDecode(response.body);
      final List list = body['packs'] ?? [];
      return list.map<StationBillingPack>((e) => StationBillingPack.fromJson(e)).toList();
    }
    throw 'Failed to load billing packs';
  }

  static Future<StationBillingPack> getById(String uid) async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/station-billing/$uid'),
      headers: await _headers(),
    );
    if (response.statusCode == 200) {
      return StationBillingPack.fromJson(jsonDecode(response.body));
    }
    throw 'Failed to load billing pack';
  }

  static Future<void> updateCompliance(String uid, Map<String, dynamic> checklist) async {
    final response = await http.patch(
      Uri.parse('$baseUrl/api/station-billing/$uid/compliance'),
      headers: await _headers(),
      body: jsonEncode({'checklist': checklist}),
    );
    if (response.statusCode != 200) {
      throw 'Failed to update compliance';
    }
  }

  static Future<void> submit(String uid) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/station-billing/$uid/submit'),
      headers: await _headers(),
    );
    if (response.statusCode != 200) {
      throw 'Failed to submit billing pack';
    }
  }

  static Future<void> approve(String uid) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/station-billing/$uid/approve'),
      headers: await _headers(),
    );
    if (response.statusCode != 200) {
      throw 'Failed to approve billing pack';
    }
  }

  static Future<void> reject(String uid, String reason) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/station-billing/$uid/reject'),
      headers: await _headers(),
      body: jsonEncode({'reason': reason}),
    );
    if (response.statusCode != 200) {
      throw 'Failed to reject billing pack';
    }
  }

  static Future<void> recordPayment(String uid, {required double amount, required String mode, String? reference, String? date}) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/station-billing/$uid/payment'),
      headers: await _headers(),
      body: jsonEncode({
        'amount': amount,
        'paymentRef': reference ?? '',
        'paymentDate': date ?? DateTime.now().toIso8601String(),
      }),
    );
    if (response.statusCode != 200) {
      throw 'Failed to record payment';
    }
  }
}
