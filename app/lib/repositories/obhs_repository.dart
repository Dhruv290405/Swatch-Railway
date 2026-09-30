import 'dart:convert';
import 'package:crm_train/services/api_services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../helper/api_error_handler.dart';
import '../model/run_instance_model.dart';
import '../model/railway_worker_model.dart';
import '../model/train_model.dart';

class OBHSRepository {

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


  static Future<List<TrainModel>> getOBHSTrains() async {
    try {
      final token = await _getToken();
      if (token == null) {
        throw Exception('AUTH_ERROR');
      }

      final response = await _handleRequest(
        () => http.get(
          Uri.parse('$baseUrl/api/trains?applicableFor=OBHS&status=active'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
        ),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final trains = (data['trains'] as List<dynamic>?)
                ?.map((train) => TrainModel.fromJson(train as Map<String, dynamic>))
                .toList() ??
            [];
        return trains;
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        throw Exception('AUTH_ERROR');
      } else {
        throw Exception(ApiErrorHandler.getErrorMessage(
          response.body,
          response.statusCode,
        ));
      }
    } catch (e) {
      if (e.toString().contains('AUTH_ERROR')) {
        rethrow;
      }
      throw Exception(ApiErrorHandler.getErrorMessage(e, null));
    }
  }


  static Future<List<RunInstanceModel>> getRunInstancesByTrain(
      String trainId) async {
    try {
      final token = await _getToken();
      if (token == null) {
        throw Exception('AUTH_ERROR');
      }

      final response = await _handleRequest(
        () => http.get(
          Uri.parse('$baseUrl/api/train-pairs/train/$trainId'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
        ),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final instances = (data['data'] as List<dynamic>?)
                ?.map((instance) =>
                    RunInstanceModel.fromJson(instance as Map<String, dynamic>))
                .toList() ??
            [];
        return instances;
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        throw Exception('AUTH_ERROR');
      } else {
        throw Exception(ApiErrorHandler.getErrorMessage(
          response.body,
          response.statusCode,
        ));
      }
    } catch (e) {
      if (e.toString().contains('AUTH_ERROR')) {
        rethrow;
      }
      throw Exception(ApiErrorHandler.getErrorMessage(e, null));
    }
  }


  static Future<List<RailwayWorkerModel>> getRailwayWorkers() async {
    try {
      final token = await _getToken();
      if (token == null) {
        throw Exception('AUTH_ERROR');
      }

      final response = await _handleRequest(
        () => http.get(
          Uri.parse('$baseUrl/api/admin/railway-workers'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
        ),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final workers = (data['workers'] as List<dynamic>?)
                ?.map((worker) =>
                    RailwayWorkerModel.fromJson(worker as Map<String, dynamic>))
                .toList() ??
            [];
        return workers;
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        throw Exception('AUTH_ERROR');
      } else {
        throw Exception(ApiErrorHandler.getErrorMessage(
          response.body,
          response.statusCode,
        ));
      }
    } catch (e) {
      if (e.toString().contains('AUTH_ERROR')) {
        rethrow;
      }
      throw Exception(ApiErrorHandler.getErrorMessage(e, null));
    }
  }


  static Future<RunInstanceModel> createRunInstance({
    required String instanceId,
    required List<CoachAssignment> coaches,
    required DateTime departureDate,
  }) async {
    try {
      final token = await _getToken();
      if (token == null) {
        throw Exception('AUTH_ERROR');
      }

      final requestBody = {
        'instanceId': instanceId,
        'coaches': coaches.map((coach) => coach.toJson()).toList(),
        'departureDate': '${departureDate.year}-'
            '${departureDate.month.toString().padLeft(2, '0')}-'
            '${departureDate.day.toString().padLeft(2, '0')}',
        'status': 'Active',
      };

      final response = await _handleRequest(
        () => http.post(
          Uri.parse('$baseUrl/api/run-instances'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode(requestBody),
        ),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        // Assuming the response contains the created instance in 'data' field
        final instanceData = data['data'] ?? data;
        final created = RunInstanceModel.fromJson(instanceData as Map<String, dynamic>);

        return created;
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        throw Exception('AUTH_ERROR');
      } else {
        throw Exception(ApiErrorHandler.getErrorMessage(
          response.body,
          response.statusCode,
        ));
      }
    } catch (e) {
      if (e.toString().contains('AUTH_ERROR')) {
        rethrow;
      }
      throw Exception(ApiErrorHandler.getErrorMessage(e, null));
    }
  }

  static Future<void> generateSchedule({
    required String trainId,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    try {
      final token = await _getToken();
      if (token == null) {
        throw Exception('AUTH_ERROR');
      }

      final requestBody = {
        'startDate': '${startDate.year}-${startDate.month.toString().padLeft(2, '0')}-${startDate.day.toString().padLeft(2, '0')}',
        'endDate': '${endDate.year}-${endDate.month.toString().padLeft(2, '0')}-${endDate.day.toString().padLeft(2, '0')}',
      };

      final response = await _handleRequest(
        () => http.post(
          Uri.parse('$baseUrl/api/trains/$trainId/generate-schedule'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode(requestBody),
        ),
      );

      if (response.statusCode != 200 && response.statusCode != 201) {
        throw Exception(ApiErrorHandler.getErrorMessage(response.body, response.statusCode));
      }
    } catch (e) {
      if (e.toString().contains('AUTH_ERROR')) {
        rethrow;
      }
      throw Exception(ApiErrorHandler.getErrorMessage(e, null));
    }
  }

  static Future<RunInstanceModel> updateRunInstance({
    required String runInstanceId,
    String? status,
    List<CoachAssignment>? coaches,
    DateTime? departureDate,
  }) async {
    try {
      final token = await _getToken();
      if (token == null) {
        throw Exception('AUTH_ERROR');
      }

      final requestBody = <String, dynamic>{};
      if (status != null) {
        requestBody['status'] = status;
      }
      if (coaches != null && coaches.isNotEmpty) {
        requestBody['coaches'] = coaches.map((coach) => coach.toJson()).toList();
      }
      if (departureDate != null) {
        requestBody['departureDate'] = '${departureDate.year}-'
            '${departureDate.month.toString().padLeft(2, '0')}-'
            '${departureDate.day.toString().padLeft(2, '0')}'; 
      }

      final response = await _handleRequest(
        () => http.put(
          Uri.parse('$baseUrl/api/run-instances/$runInstanceId'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode(requestBody),
        ),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final instanceData = data['data'] ?? data;
        return RunInstanceModel.fromJson(instanceData as Map<String, dynamic>);
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        throw Exception('AUTH_ERROR');
      } else {
        throw Exception(ApiErrorHandler.getErrorMessage(
          response.body,
          response.statusCode,
        ));
      }
    } catch (e) {
      if (e.toString().contains('AUTH_ERROR')) {
        rethrow;
      }
      throw Exception(ApiErrorHandler.getErrorMessage(e, null));
    }
  }

  /// Delete Run Instance
  /// [runInstanceId] - The run instance ID to delete
  /// Returns success message
  static Future<Map<String, dynamic>> deleteRunInstance(
      String runInstanceId) async {
    try {
      final token = await _getToken();
      if (token == null) {
        throw Exception('AUTH_ERROR');
      }

      final response = await _handleRequest(
        () => http.delete(
          Uri.parse('$baseUrl/api/run-instances/$runInstanceId'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
        ),
      );

      if (response.statusCode == 200 || response.statusCode == 204) {
        if (response.body.isNotEmpty) {
          return jsonDecode(response.body) as Map<String, dynamic>;
        } else {
          return {'message': 'Run instance deleted successfully'};
        }
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        throw Exception('AUTH_ERROR');
      } else {
        throw Exception(ApiErrorHandler.getErrorMessage(
          response.body,
          response.statusCode,
        ));
      }
    } catch (e) {
      if (e.toString().contains('AUTH_ERROR')) {
        rethrow;
      }
      throw Exception(ApiErrorHandler.getErrorMessage(e, null));
    }
  }

  /// Get OBHS Attendance List (admin view)
  static Future<List<Map<String, dynamic>>> getAttendanceList({String? runInstanceId}) async {
    try {
      final token = await _getToken();
      if (token == null) throw Exception('AUTH_ERROR');
      final params = <String, String>{};
      if (runInstanceId != null) params['runInstanceId'] = runInstanceId;
      final uri = Uri.parse('$baseUrl/api/obhs/attendance/list').replace(queryParameters: params.isNotEmpty ? params : null);
      final response = await _handleRequest(
        () => http.get(uri, headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'}),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return List<Map<String, dynamic>>.from(data['records'] ?? []);
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

  /// All task details generated for a run (used by reports + review queue).
  static Future<List<Map<String, dynamic>>> getRunTasks(String runInstanceId) async {
    try {
      final token = await _getToken();
      if (token == null) throw Exception('AUTH_ERROR');
      final uri = Uri.parse('$baseUrl/api/obhs/tasks/run/$runInstanceId');
      final response = await _handleRequest(
        () => http.get(uri, headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'}),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final list = data is List ? data : (data['data'] ?? data['tasks'] ?? data['records'] ?? []);
        return List<Map<String, dynamic>>.from(list as List);
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

  /// Complaints raised against a run.
  static Future<List<Map<String, dynamic>>> getRunComplaints(String runInstanceId) async {
    try {
      final token = await _getToken();
      if (token == null) throw Exception('AUTH_ERROR');
      final uri = Uri.parse('$baseUrl/api/obhs/complaints/run/$runInstanceId');
      final response = await _handleRequest(
        () => http.get(uri, headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'}),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return List<Map<String, dynamic>>.from(data['complaints'] ?? []);
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

  /// Get All Run Instances (for list screen)
  /// Returns all run instances across all trains
  static Future<List<RunInstanceModel>> getAllRunInstances() async {
    try {
      final token = await _getToken();
      if (token == null) {
        throw Exception('AUTH_ERROR');
      }

      final response = await _handleRequest(
        () => http.get(
          Uri.parse('$baseUrl/api/run-instances'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
        ),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        
        // Try multiple keys commonly used in the backend
        final list = (data['data'] ?? data['runInstances'] ?? data['records']) as List<dynamic>?;
        
        if (list == null) {
          // If no known key is found, and data itself isn't a list, return empty
          return [];
        }

        final instances = list
                .map((instance) =>
                    RunInstanceModel.fromJson(instance as Map<String, dynamic>))
                .toList();
        return instances;
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        throw Exception('AUTH_ERROR');
      } else {
        throw Exception(ApiErrorHandler.getErrorMessage(
          response.body,
          response.statusCode,
        ));
      }
    } catch (e) {
      if (e.toString().contains('AUTH_ERROR')) {
        rethrow;
      }
      throw Exception(ApiErrorHandler.getErrorMessage(e, null));
    }
  }

  // --- Supervisor / Contractor APIs ---

  // Contractor supervisors scoped server-side to the requester's entity and station.
  // Avoids fetching the entire workers collection (previously all users were loaded).
  static Future<List<RailwayWorkerModel>> getContractorSupervisors({String? stationId}) async {
    try {
      final token = await _getToken();
      if (token == null) throw Exception('AUTH_ERROR');

      final uri = Uri.parse('$baseUrl/api/users/contractor-supervisors').replace(
        queryParameters: stationId != null && stationId.isNotEmpty ? {'stationId': stationId} : null,
      );
      final response = await _handleRequest(() => http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final supervisorsData = data['supervisors'] as List<dynamic>? ?? [];
        return supervisorsData.map((w) => RailwayWorkerModel.fromJson(w as Map<String, dynamic>)).toList();
      } else if (response.statusCode == 401) {
        throw Exception('AUTH_ERROR');
      } else {
        throw Exception(ApiErrorHandler.getErrorMessage(response.body, response.statusCode));
      }
    } catch (e) {
      if (e.toString().contains('AUTH_ERROR')) rethrow;
      throw Exception(ApiErrorHandler.getErrorMessage(e, null));
    }
  }

  static Future<List<RailwayWorkerModel>> getWorkers() async {
    try {
      final token = await _getToken();
      if (token == null) throw Exception('AUTH_ERROR');

      final response = await _handleRequest(() => http.get(
        Uri.parse('$baseUrl/api/users/workers'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final workersData = data['workers'] as List<dynamic>? ?? [];
        return workersData.map((w) => RailwayWorkerModel.fromJson(w as Map<String, dynamic>)).toList();
      } else if (response.statusCode == 401) {
        throw Exception('AUTH_ERROR');
      } else {
        throw Exception(ApiErrorHandler.getErrorMessage(response.body, response.statusCode));
      }
    } catch (e) {
      if (e.toString().contains('AUTH_ERROR')) rethrow;
      throw Exception(ApiErrorHandler.getErrorMessage(e, null));
    }
  }

  static Future<List<dynamic>> getPendingReviewTasks(String runInstanceId) async {
    try {
      final token = await _getToken();
      if (token == null) throw Exception('AUTH_ERROR');

      final response = await _handleRequest(() => http.get(
        Uri.parse('$baseUrl/api/tasks/pending-review?runInstanceId=$runInstanceId'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return data['data'] as List<dynamic>? ?? [];
      } else if (response.statusCode == 401) {
        throw Exception('AUTH_ERROR');
      } else {
        throw Exception(ApiErrorHandler.getErrorMessage(response.body, response.statusCode));
      }
    } catch (e) {
      if (e.toString().contains('AUTH_ERROR')) rethrow;
      throw Exception(ApiErrorHandler.getErrorMessage(e, null));
    }
  }

  static Future<void> updateTaskStatus(String taskId, String status, {int? passengerScore, int? supervisorScore}) async {
    try {
      final token = await _getToken();
      if (token == null) throw Exception('AUTH_ERROR');

      final body = <String, dynamic>{
        'taskInstanceId': taskId,
        'verified': status.toLowerCase() == 'approved',
        'remarks': 'Reviewed via supervisor app'
      };
      if (supervisorScore != null) body['supervisorScore'] = supervisorScore;

      final response = await _handleRequest(() => http.post(
        Uri.parse('$baseUrl/api/v2/tasks/verify'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(body),
      ));

      if (response.statusCode == 200 || response.statusCode == 201) {
        return;
      } else if (response.statusCode == 401) {
        throw Exception('AUTH_ERROR');
      } else {
        throw Exception(ApiErrorHandler.getErrorMessage(response.body, response.statusCode));
      }
    } catch (e) {
      if (e.toString().contains('AUTH_ERROR')) rethrow;
      throw Exception(ApiErrorHandler.getErrorMessage(e, null));
    }
  }
}
