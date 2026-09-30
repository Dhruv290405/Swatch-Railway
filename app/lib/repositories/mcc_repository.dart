import 'package:crm_train/repositories/base_repository.dart';

class MccRepository {
  static const String _base = '/api/mcc';

  static Future<Map<String, dynamic>> getDepots() {
    return BaseRepository.apiCall(
      method: 'GET',
      path: '$_base/depots',
      parser: (json) => json,
    );
  }

  static Future<Map<String, dynamic>> createDepot(Map<String, dynamic> body) {
    return BaseRepository.apiCall(
      method: 'POST',
      path: '$_base/depots',
      body: body,
      parser: (json) => json,
    );
  }

  static Future<Map<String, dynamic>> getWashingRuns({String? depotId, String? status}) {
    return BaseRepository.apiCall(
      method: 'GET',
      path: '$_base/washing-runs',
      queryParams: {
        if (depotId != null) 'depotId': depotId,
        if (status != null) 'status': status,
      },
      parser: (json) => json,
    );
  }

  static Future<Map<String, dynamic>> createWashingRun(Map<String, dynamic> body) {
    return BaseRepository.apiCall(
      method: 'POST',
      path: '$_base/washing-runs',
      body: body,
      parser: (json) => json,
    );
  }

  static Future<Map<String, dynamic>> getWashingRun(String runId) {
    return BaseRepository.apiCall(
      method: 'GET',
      path: '$_base/washing-runs/$runId',
      parser: (json) => json,
    );
  }

  static Future<Map<String, dynamic>> startWashingRun(String runId) {
    return BaseRepository.apiCall(
      method: 'POST',
      path: '$_base/washing-runs/$runId/start',
      parser: (json) => json,
    );
  }

  static Future<Map<String, dynamic>> completeWashingRun(String runId) {
    return BaseRepository.apiCall(
      method: 'POST',
      path: '$_base/washing-runs/$runId/complete',
      parser: (json) => json,
    );
  }

  static Future<Map<String, dynamic>> getWorkerTasks({String? status}) {
    return BaseRepository.apiCall(
      method: 'GET',
      path: '$_base/worker/tasks',
      queryParams: {if (status != null) 'status': status},
      parser: (json) => json,
    );
  }

  static Future<Map<String, dynamic>> submitTask(Map<String, dynamic> body) {
    return BaseRepository.apiCall(
      method: 'POST',
      path: '$_base/washing-tasks/submit',
      body: body,
      parser: (json) => json,
    );
  }

  static Future<Map<String, dynamic>> approveTask(String taskId, {String? remarks}) {
    return BaseRepository.apiCall(
      method: 'POST',
      path: '$_base/washing-tasks/$taskId/approve',
      body: {if (remarks != null) 'remarks': remarks},
      parser: (json) => json,
    );
  }

  static Future<Map<String, dynamic>> rejectTask(String taskId, {required String reason}) {
    return BaseRepository.apiCall(
      method: 'POST',
      path: '$_base/washing-tasks/$taskId/reject',
      body: {'reason': reason},
      parser: (json) => json,
    );
  }

  static Future<Map<String, dynamic>> markAttendance(Map<String, dynamic> body) {
    return BaseRepository.apiCall(
      method: 'POST',
      path: '$_base/attendance',
      body: body,
      parser: (json) => json,
    );
  }

  static Future<Map<String, dynamic>> getAttendanceStatus({String? runId, String? depotId}) {
    return BaseRepository.apiCall(
      method: 'GET',
      path: '$_base/attendance/status',
      queryParams: {
        if (runId != null) 'runId': runId,
        if (depotId != null) 'depotId': depotId,
      },
      parser: (json) => json,
    );
  }

  static Future<Map<String, dynamic>> getDashboard() {
    return BaseRepository.apiCall(
      method: 'GET',
      path: '$_base/dashboard',
      parser: (json) => json,
    );
  }
}