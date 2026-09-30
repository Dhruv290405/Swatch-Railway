import 'dart:convert';
import 'package:http/http.dart' as http;
import '../services/api_services.dart';
import '../model/task_type_model.dart';

class TaskTypeRepository {
  static String get baseUrl => ApiService.baseUrl;
  static Future<Map<String, String>> _headers() async {
    final token = await ApiService.getToken();
    return {'Content-Type': 'application/json', if (token != null) 'Authorization': 'Bearer $token'};
  }

  // Task types change rarely, so they are cached for a short window. Without the
  // cache every "start task" sheet paid a full round trip before it could show the
  // activity list, and a slow one left the spinner running forever.
  static List<TaskType>? _cache;
  static String? _cacheKey;
  static DateTime? _cachedAt;
  static const Duration _cacheTtl = Duration(minutes: 10);
  static Future<List<TaskType>>? _inFlight;

  static void clearCache() {
    _cache = null;
    _cacheKey = null;
    _cachedAt = null;
    _inFlight = null;
  }

  static Future<List<TaskType>> list({String? category, bool? isActive}) async {
    final params = <String, String>{};
    if (category != null) params['category'] = category;
    if (isActive != null) params['isActive'] = isActive.toString();
    final key = jsonEncode(params);

    final cached = _cache;
    if (cached != null && _cacheKey == key && _cachedAt != null &&
        DateTime.now().difference(_cachedAt!) < _cacheTtl) {
      return cached;
    }

    // Collapse concurrent callers (two sheets opened at once) into one request.
    final pending = _inFlight;
    if (pending != null && _cacheKey == key) return pending;

    final request = _fetch(params);
    _cacheKey = key;
    _inFlight = request;
    try {
      final result = await request;
      _cache = result;
      _cachedAt = DateTime.now();
      return result;
    } finally {
      _inFlight = null;
    }
  }

  static Future<List<TaskType>> _fetch(Map<String, String> params) async {
    final uri = Uri.parse('$baseUrl/api/task-types').replace(queryParameters: params.isNotEmpty ? params : null);
    final res = await ApiService.getWithRetry(uri, headers: await _headers());
    if (res.statusCode != 200) throw Exception('Failed to load task types');
    final decoded = jsonDecode(res.body);
    final raw = (decoded is Map ? (decoded['taskTypes'] ?? decoded['data'] ?? []) : decoded) as List;
    return raw.cast<Map<String, dynamic>>().map((e) => TaskType.fromJson(e)).toList();
  }

  static Future<void> create(Map<String, dynamic> data) async {
    final res = await http.post(Uri.parse('$baseUrl/api/task-types'), headers: await _headers(), body: jsonEncode(data));
    if (res.statusCode != 201 && res.statusCode != 200) {
      final err = jsonDecode(res.body);
      throw Exception(err['error'] ?? 'Failed to create task type');
    }
    clearCache();
  }

  static Future<void> update(String uid, Map<String, dynamic> data) async {
    final res = await http.put(Uri.parse('$baseUrl/api/task-types/$uid'), headers: await _headers(), body: jsonEncode(data));
    if (res.statusCode != 200) {
      final err = jsonDecode(res.body);
      throw Exception(err['error'] ?? 'Failed to update task type');
    }
    clearCache();
  }

  static Future<void> remove(String uid) async {
    final res = await http.delete(Uri.parse('$baseUrl/api/task-types/$uid'), headers: await _headers());
    if (res.statusCode != 200) throw Exception('Failed to delete task type');
    clearCache();
  }
}
