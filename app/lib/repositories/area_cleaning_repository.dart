import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../helper/api_error_handler.dart';
import '../model/area_cleaning_models.dart';
import '../services/api_services.dart';

class AreaCleaningRepository {
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
        onTimeout: () => throw Exception('Request timeout'),
      );
      return response;
    } catch (e) {
      rethrow;
    }
  }

  static Future<T> _apiCall<T>({
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
          response = await _handleRequest(() => http.get(uri, headers: headers));
          break;
        case 'POST':
          response = await _handleRequest(() => http.post(uri, headers: headers, body: jsonEncode(body)));
          break;
        case 'PUT':
          response = await _handleRequest(() => http.put(uri, headers: headers, body: jsonEncode(body)));
          break;
        default:
          throw Exception('Unsupported method: $method');
      }

      if (response.statusCode == 200 || response.statusCode == 201) {
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

  // ─── Areas ───

  static Future<List<AreaConfig>> getAreas({String? stationId, String? platformId}) async {
    final queryParams = <String, String>{};
    if (stationId != null) queryParams['stationId'] = stationId;
    if (platformId != null) queryParams['platformId'] = platformId;

    final result = await _apiCall(
      method: 'GET',
      path: '/api/areas',
      queryParams: queryParams.isNotEmpty ? queryParams : null,
      parser: (data) {
        final list = data['data'] as List<dynamic>? ?? data['areas'] as List<dynamic>? ?? [];
        return list.map<AreaConfig>((e) => AreaConfig.fromJson(e as Map<String, dynamic>)).toList();
      },
    );
    return result;
  }

  static Future<AreaConfig> createArea(Map<String, dynamic> areaData) async {
    return await _apiCall(
      method: 'POST',
      path: '/api/areas',
      body: areaData,
      parser: (data) => AreaConfig.fromJson(data['data'] as Map<String, dynamic>? ?? data),
    );
  }

  static Future<AreaConfig> updateArea(String areaId, Map<String, dynamic> areaData) async {
    return await _apiCall(
      method: 'PUT',
      path: '/api/areas/$areaId',
      body: areaData,
      parser: (data) => AreaConfig.fromJson(data['data'] as Map<String, dynamic>? ?? data),
    );
  }

  static Future<Map<String, dynamic>> configureArea(String areaId, Map<String, dynamic> config) async {
    return await _apiCall(
      method: 'PUT',
      path: '/api/areas/$areaId/configure',
      body: config,
      parser: (data) => data,
    );
  }

  // ─── Area Worker Assignments ───

  static Future<List<AreaWorkerAssignment>> getAssignments(String areaId) async {
    final result = await _apiCall(
      method: 'GET',
      path: '/api/area-assignments',
      queryParams: {'areaId': areaId},
      parser: (data) {
        final list = data['data'] as List<dynamic>? ?? [];
        return list.map<AreaWorkerAssignment>((e) => AreaWorkerAssignment.fromJson(e as Map<String, dynamic>)).toList();
      },
    );
    return result;
  }

  static Future<AreaWorkerAssignment> createAssignment(Map<String, dynamic> data) async {
    return await _apiCall(
      method: 'POST',
      path: '/api/area-assignments',
      body: data,
      parser: (json) => AreaWorkerAssignment.fromJson(json['data'] as Map<String, dynamic>? ?? json),
    );
  }

  static Future<void> removeAssignment(String assignmentId) async {
    await _apiCall(
      method: 'PUT',
      path: '/api/area-assignments/$assignmentId/deactivate',
      parser: (_) => null,
    );
  }

  // ─── Cleaning Tasks ───

  static Future<List<CleaningTask>> getTasks({
    String? areaId,
    String? workerId,
    String? supervisorId,
    String? stationId,
    String? platformId,
    String? status,
    String? date,
    String? startDate,
    String? endDate,
  }) async {
    final queryParams = <String, String>{};
    if (areaId != null) queryParams['areaId'] = areaId;
    if (workerId != null) queryParams['workerId'] = workerId;
    if (supervisorId != null) queryParams['supervisorId'] = supervisorId;
    if (stationId != null) queryParams['stationId'] = stationId;
    if (platformId != null) queryParams['platformId'] = platformId;
    if (status != null) queryParams['status'] = status;
    if (date != null) queryParams['date'] = date;
    if (startDate != null) queryParams['startDate'] = startDate;
    if (endDate != null) queryParams['endDate'] = endDate;

    final result = await _apiCall(
      method: 'GET',
      path: '/api/tasks-v2',
      queryParams: queryParams.isNotEmpty ? queryParams : null,
      parser: (data) {
        final list = data['tasks'] as List<dynamic>? ?? data['data'] as List<dynamic>? ?? [];
        return list.map<CleaningTask>((e) => CleaningTask.fromJson(e as Map<String, dynamic>)).toList();
      },
    );
    return result;
  }

  static Future<CleaningTask> startTask(String taskId, {String? beforePhoto, double? gpsLat, double? gpsLng}) async {
    return await _apiCall(
      method: 'POST',
      path: '/api/tasks-v2/$taskId/start',
      body: {
        if (beforePhoto != null) 'beforePhoto': beforePhoto,
        if (gpsLat != null) 'gpsLat': gpsLat,
        if (gpsLng != null) 'gpsLng': gpsLng,
      },
      parser: (data) => CleaningTask.fromJson(data),
    );
  }

  static Future<CleaningTask> completeTask(String taskId, {String? afterPhoto, double? gpsLat, double? gpsLng, String? remarks}) async {
    return await _apiCall(
      method: 'POST',
      path: '/api/tasks-v2/$taskId/complete',
      body: {
        if (afterPhoto != null) 'afterPhoto': afterPhoto,
        if (gpsLat != null) 'gpsLat': gpsLat,
        if (gpsLng != null) 'gpsLng': gpsLng,
        if (remarks != null) 'remarks': remarks,
      },
      parser: (data) => CleaningTask.fromJson(data),
    );
  }

  static Future<CleaningTask> resubmitTask(String taskId, {String? afterPhoto, double? gpsLat, double? gpsLng, String? remarks}) async {
    return await _apiCall(
      method: 'POST',
      path: '/api/tasks-v2/$taskId/resubmit',
      body: {
        if (afterPhoto != null) 'afterPhoto': afterPhoto,
        if (gpsLat != null) 'gpsLat': gpsLat,
        if (gpsLng != null) 'gpsLng': gpsLng,
        if (remarks != null) 'remarks': remarks,
      },
      parser: (data) => CleaningTask.fromJson(data),
    );
  }

  static Future<List<CleaningTask>> getWorkerTasks(String workerId, {String? date}) async {
    final queryParams = <String, String>{'workerId': workerId};
    if (date != null) queryParams['date'] = date;

    final result = await _apiCall(
      method: 'GET',
      path: '/api/tasks-v2/worker',
      queryParams: queryParams,
      parser: (data) {
        final list = data['tasks'] as List<dynamic>? ?? [];
        return list.map<CleaningTask>((e) => CleaningTask.fromJson(e as Map<String, dynamic>)).toList();
      },
    );
    return result;
  }

static Future<Map<String, dynamic>> getFrequencyStatus({required String date, required List<String> areaIds, Map<String, int>? areaFrequencies}) async {
    if (areaIds.isEmpty) return {};
    return await _apiCall(
      method: 'GET',
      path: '/api/tasks-v2/frequency-status',
      queryParams: {
        'date': date,
        'areaIds': areaIds.join(','),
        if (areaFrequencies != null && areaFrequencies.isNotEmpty)
          'areaFrequencies': jsonEncode(areaFrequencies),
      },
      parser: (data) {
        return data['areas'] as Map<String, dynamic>? ?? {};
      },
    );
  }

  static Future<Map<String, dynamic>> generateTasks({List<String>? areaIds, String? date, List<String>? workerIds, String? supervisorId, String? shift, String? frequency, String? activityType, String? taskTypeId, String? taskTypeName, Map<String, dynamic>? areaActivities, Map<String, int>? areaFrequencies, Map<String, int>? areaTimes, Map<String, List<String>>? areaTimeSlots, bool normalize = false}) async {
    return await _apiCall(
      method: 'POST',
      path: '/api/tasks-v2/generate',
      body: {
        if (areaIds != null) 'areaIds': areaIds,
        if (date != null) 'date': date,
        if (workerIds != null && workerIds.isNotEmpty) 'workerIds': workerIds,
        if (supervisorId != null && supervisorId.isNotEmpty) 'supervisorId': supervisorId,
        if (shift != null && shift.isNotEmpty) 'shift': shift,
        if (frequency != null && frequency.isNotEmpty) 'frequency': frequency,
        if (activityType != null && activityType.isNotEmpty) 'activityType': activityType,
        if (taskTypeId != null && taskTypeId.isNotEmpty) 'taskTypeId': taskTypeId,
        if (taskTypeName != null && taskTypeName.isNotEmpty) 'taskTypeName': taskTypeName,
        if (areaActivities != null && areaActivities.isNotEmpty) 'areaActivities': areaActivities,
        if (areaFrequencies != null && areaFrequencies.isNotEmpty) 'areaFrequencies': areaFrequencies,
        if (areaTimes != null && areaTimes.isNotEmpty) 'areaTimes': areaTimes,
        if (areaTimeSlots != null && areaTimeSlots.isNotEmpty) 'areaTimeSlots': areaTimeSlots,
        if (normalize) 'normalize': true,
      },
      parser: (data) => data,
    );
  }

  // ─── Supervisor Shift Assignment (station-cleaning only) ───

  static Future<List<SupervisorShift>> getSupervisorShifts({required String stationId}) async {
    return await _apiCall(
      method: 'GET',
      path: '/api/station-cleaning/supervisor-shifts',
      queryParams: {'stationId': stationId},
      parser: (data) {
        final list = data['supervisors'] as List<dynamic>? ?? [];
        return list.map((e) => SupervisorShift.fromJson(e as Map<String, dynamic>)).toList();
      },
    );
  }

  static Future<Map<String, dynamic>> assignSupervisorShift({
    required String supervisorId,
    required String shift,
    required String stationId,
  }) async {
    return await _apiCall(
      method: 'PUT',
      path: '/api/station-cleaning/supervisor-shifts/$supervisorId',
      body: {'shift': shift, 'stationId': stationId},
      parser: (data) => data,
    );
  }

  // ─── Dashboards (5-level) ───

  static Future<AdminDashboard> getAdminDashboard() async {
    return await _apiCall(
      method: 'GET',
      path: '/api/dashboard/admin',
      parser: (data) => AdminDashboard.fromJson(data),
    );
  }

  static Future<ZoneDashboard> getZoneDashboard(String zoneId) async {
    return await _apiCall(
      method: 'GET',
      path: '/api/dashboard/zone/$zoneId',
      parser: (data) => ZoneDashboard.fromJson(data),
    );
  }

  static Future<StationDashboard> getStationDashboard(String stationId, {String? startDate, String? endDate}) async {
    final queryParams = <String, String>{};
    if (startDate != null) queryParams['startDate'] = startDate;
    if (endDate != null) queryParams['endDate'] = endDate;

    return await _apiCall(
      method: 'GET',
      path: '/api/dashboard/station/$stationId',
      queryParams: queryParams.isNotEmpty ? queryParams : null,
      parser: (data) => StationDashboard.fromJson(data['data'] as Map<String, dynamic>? ?? data),
    );
  }

  static Future<PlatformDashboard> getPlatformDashboard(String platformId, {String? date}) async {
    final queryParams = <String, String>{};
    if (date != null) queryParams['date'] = date;

    return await _apiCall(
      method: 'GET',
      path: '/api/dashboard/platform/$platformId',
      queryParams: queryParams.isNotEmpty ? queryParams : null,
      parser: (data) => PlatformDashboard.fromJson(data),
    );
  }

  static Future<AreaDashboard> getAreaDashboard(String areaId, {String? date}) async {
    final queryParams = <String, String>{};
    if (date != null) queryParams['date'] = date;

    return await _apiCall(
      method: 'GET',
      path: '/api/dashboard/area/$areaId',
      queryParams: queryParams.isNotEmpty ? queryParams : null,
      parser: (data) => AreaDashboard.fromJson(data),
    );
  }
}
