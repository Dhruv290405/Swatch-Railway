import 'dart:convert';
import 'package:http_parser/http_parser.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../helper/api_error_handler.dart';
import '../services/api_services.dart';

class WorkerRepository {
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

  static Future<Map<String, dynamic>> getWorkerProfile() async {
    try {
      final token = await _getToken();
      if (token == null) {
        throw Exception('AUTH_ERROR');
      }

      final response = await _handleRequest(
        () => http.get(
          Uri.parse('$baseUrl/api/worker/profile'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
        ),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else if (response.statusCode == 401) {
        throw Exception('AUTH_ERROR');
      } else {
        throw Exception(
          ApiErrorHandler.getErrorMessage(response.body, response.statusCode),
        );
      }
    } catch (e) {
      if (e.toString().contains('AUTH_ERROR')) {
        rethrow;
      }
      throw Exception(ApiErrorHandler.getErrorMessage(e, null));
    }
  }

  static Future<Map<String, dynamic>> getWorkerStatistics() async {
    try {
      final token = await _getToken();
      if (token == null) {
        throw Exception('AUTH_ERROR');
      }

      final response = await _handleRequest(
        () => http.get(
          Uri.parse('$baseUrl/api/worker/statistics'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
        ),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else if (response.statusCode == 401) {
        throw Exception('AUTH_ERROR');
      } else {
        throw Exception(
          ApiErrorHandler.getErrorMessage(response.body, response.statusCode),
        );
      }
    } catch (e) {
      if (e.toString().contains('AUTH_ERROR')) {
        rethrow;
      }
      throw Exception(ApiErrorHandler.getErrorMessage(e, null));
    }
  }

  static Future<Map<String, dynamic>> getWorkerTasks() async {
    try {
      final token = await _getToken();
      if (token == null) {
        throw Exception('AUTH_ERROR');
      }

      final response = await _handleRequest(
        () => http.get(
          Uri.parse('$baseUrl/api/worker/tasks'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
        ),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else if (response.statusCode == 401) {
        throw Exception('AUTH_ERROR');
      } else {
        throw Exception(
          ApiErrorHandler.getErrorMessage(response.body, response.statusCode),
        );
      }
    } catch (e) {
      if (e.toString().contains('AUTH_ERROR')) {
        rethrow;
      }
      throw Exception(ApiErrorHandler.getErrorMessage(e, null));
    }
  }

  static Future<Map<String, dynamic>> getObhsTasksBoard({
    required String runInstanceId,
  }) async {
    try {
      final token = await _getToken();
      if (token == null) {
        throw Exception('AUTH_ERROR');
      }

      final uri = Uri.parse(
        '$baseUrl/api/obhs/tasks/board',
      ).replace(queryParameters: {'runInstanceId': runInstanceId});

      final response = await _handleRequest(
        () => http.get(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
        ),
      );

      debugPrint('OBHS tasks board status: ${response.statusCode}');
      debugPrint('OBHS tasks board body: ${response.body}');

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else if (response.statusCode == 401) {
        throw Exception('AUTH_ERROR');
      } else {
        throw Exception(
          ApiErrorHandler.getErrorMessage(response.body, response.statusCode),
        );
      }
    } catch (e) {
      if (e.toString().contains('AUTH_ERROR')) {
        rethrow;
      }
      throw Exception(ApiErrorHandler.getErrorMessage(e, null));
    }
  }

  static Future<Map<String, dynamic>> getObhsAttendanceStatus({
    required String runInstanceId,
  }) async {
    try {
      final token = await _getToken();
      if (token == null) {
        throw Exception('AUTH_ERROR');
      }

      final uri = Uri.parse(
        '$baseUrl/api/obhs/attendance/status',
      ).replace(queryParameters: {'runInstanceId': runInstanceId});

      final response = await _handleRequest(
        () => http.get(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
        ),
      );

      debugPrint('OBHS attendance status check: ${response.statusCode}');
      debugPrint('OBHS attendance status body: ${response.body}');

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else if (response.statusCode == 401) {
        throw Exception('AUTH_ERROR');
      } else {
        throw Exception(
          ApiErrorHandler.getErrorMessage(response.body, response.statusCode),
        );
      }
    } catch (e) {
      if (e.toString().contains('AUTH_ERROR')) {
        rethrow;
      }
      throw Exception(ApiErrorHandler.getErrorMessage(e, null));
    }
  }

  static Future<Map<String, dynamic>> markAttendance({
    required String type,
    String? runInstanceId,
    required String imageUrl,
    double? latitude,
    double? longitude,
    String? livenessChallenge,
  }) async {
    try {
      final token = await _getToken();
      if (token == null) {
        throw Exception('AUTH_ERROR');
      }

      if (runInstanceId == null || runInstanceId.isEmpty) {
        throw Exception('No run instance assigned for attendance.');
      }

      final body = <String, dynamic>{
        'runInstanceId': runInstanceId,
        'attendanceType': type,
        'imageUrl': imageUrl,
        'latitude': latitude?.toString() ?? '',
        'longitude': longitude?.toString() ?? '',
        'deviceTimestamp': DateTime.now().toUtc().toIso8601String(),
        if (livenessChallenge != null) 'livenessChallenge': livenessChallenge,
      };

      final response = await _handleRequest(
        () => http.post(
          Uri.parse('$baseUrl/api/obhs/attendance'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode(body),
        ),
      );
      debugPrint('OBHS attendance status: ${response.statusCode}');
      debugPrint('OBHS attendance body: ${response.body}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        return jsonDecode(response.body);
      } else {
        final message = ApiErrorHandler.getErrorMessage(response.body, response.statusCode);
        if (response.statusCode == 401 && (message.contains('Session expired') || message.contains('AUTH_ERROR'))) {
          throw Exception('AUTH_ERROR');
        }
        throw Exception(message);
      }
    } catch (e) {
      if (e.toString().contains('AUTH_ERROR')) {
        rethrow;
      }
      final message = ApiErrorHandler.getErrorMessage(e, null);
      throw Exception(message);
    }
  }

  static Future<String> uploadMedia(String filePath) async {
    try {
      final token = await _getToken();
      if (token == null) {
        throw Exception('AUTH_ERROR');
      }

      List<int>? fileBytes;
      String filename = 'upload.jpg';
      if (kIsWeb) {
        try {
          final res = await http.get(Uri.parse(filePath));
          fileBytes = res.bodyBytes;
          filename = filePath.split('/').last;
          if (!filename.contains('.')) filename += '.jpg';
        } catch (e) {
          debugPrint('Error reading web blob bytes: $e');
        }
      }

      http.Response? lastResponse;
      // Only try the field names currently supported by the backend: 'image' and 'file'
      for (final fieldName in ['image', 'file']) {
        final request = http.MultipartRequest(
          'POST',
          Uri.parse('$baseUrl/api/media/upload'),
        );
        request.headers['Authorization'] = 'Bearer $token';
        request.fields['folder'] = 'obhs_tasks';
        
        if (kIsWeb && fileBytes != null) {
          request.files.add(
            http.MultipartFile.fromBytes(
              fieldName,
              fileBytes,
              filename: filename,
              contentType: _mediaTypeForPath(filePath),
            ),
          );
        } else {
          request.files.add(
            await http.MultipartFile.fromPath(
              fieldName,
              filePath,
              contentType: _mediaTypeForPath(filePath),
            ),
          );
        }

        try {
          final streamedResponse = await request.send().timeout(
            const Duration(seconds: 30),
            onTimeout: () => throw Exception('Upload timeout'),
          );
          final response = await http.Response.fromStream(streamedResponse);
          lastResponse = response;

          if (response.statusCode == 200 || response.statusCode == 201) {
            final decoded = jsonDecode(response.body) as Map<String, dynamic>;
            final url = _extractMediaUrl(decoded);
            if (url != null && url.isNotEmpty) return url;
          }

          // If auth error, fail immediately
          if (response.statusCode == 401) {
            throw Exception('AUTH_ERROR');
          }

          // If it's a 4xx or 5xx error, don't keep trying other keys if we already tried 'image'
          if (response.statusCode >= 400) {
            final msg = ApiErrorHandler.getErrorMessage(response.body, response.statusCode);
            throw Exception(msg);
          }
        } catch (e) {
          if (e.toString().contains('AUTH_ERROR') || !e.toString().contains('Invalid field')) {
            rethrow;
          }
          // Continue to 'file' if 'image' failed with a specific "Invalid field" type error
        }
      }

      throw Exception(
        lastResponse == null
            ? 'Media upload failed.'
            : ApiErrorHandler.getErrorMessage(
                lastResponse.body,
                lastResponse.statusCode,
              ),
      );
    } catch (e) {
      if (e.toString().contains('AUTH_ERROR')) {
        rethrow;
      }
      throw Exception(ApiErrorHandler.getErrorMessage(e, null));
    }
  }

  static String? _extractMediaUrl(Map<String, dynamic> json) {
    for (final key in [
      'imageUrl',
      'url',
      'fileUrl',
      'mediaUrl',
      'downloadUrl',
    ]) {
      final value = json[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }

    final data = json['data'];
    if (data is Map<String, dynamic>) {
      return _extractMediaUrl(data);
    }

    final file = json['file'];
    if (file is Map<String, dynamic>) {
      return _extractMediaUrl(file);
    }

    return null;
  }

  static MediaType _mediaTypeForPath(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) {
      return MediaType('image', 'png');
    }
    return MediaType('image', 'jpeg');
  }

  static Future<Map<String, dynamic>> submitComplaint({
    required String title,
    required String description,
    String? category,
  }) async {
    try {
      final token = await _getToken();
      if (token == null) {
        throw Exception('AUTH_ERROR');
      }

      final response = await _handleRequest(
        () => http.post(
          Uri.parse('$baseUrl/api/worker/complaints'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode({
            'title': title,
            'description': description,
            'category': category,
            'timestamp': DateTime.now().toIso8601String(),
          }),
        ),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        return jsonDecode(response.body);
      } else if (response.statusCode == 401) {
        throw Exception('AUTH_ERROR');
      } else {
        throw Exception(
          ApiErrorHandler.getErrorMessage(response.body, response.statusCode),
        );
      }
    } catch (e) {
      if (e.toString().contains('AUTH_ERROR')) {
        rethrow;
      }
      throw Exception(ApiErrorHandler.getErrorMessage(e, null));
    }
  }

  static Future<Map<String, dynamic>> submitObhsTask({
    required String runInstanceId,
    required String taskId,
    required String taskType,
    required String coachNo,
    required String frequencyIndex,
    required String beforePhoto,
    required String afterPhoto,
    required String comment,
    double? gpsLatitude,
    double? gpsLongitude,
  }) async {
    try {
      final token = await _getToken();
      if (token == null) {
        throw Exception('AUTH_ERROR');
      }

      final response = await _handleRequest(
        () => http.post(
          Uri.parse('$baseUrl/api/obhs/tasks/submit'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode({
            'taskId': taskId,
            'taskInstanceId': taskId,
            'runInstanceId': runInstanceId,
            'taskType': taskType,
            'coachNo': coachNo,
            'frequencyIndex': frequencyIndex,
            'beforePhoto': beforePhoto,
            'afterPhoto': afterPhoto,
            'comment': comment,
            'gpsLatitude': gpsLatitude ?? 0.0,
            'gpsLongitude': gpsLongitude ?? 0.0,
            'deviceTimestamp': DateTime.now().toUtc().toIso8601String(),
          }),
        ),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final result = jsonDecode(response.body) as Map<String, dynamic>;
        return result;
      } else if (response.statusCode == 401) {
        throw Exception('AUTH_ERROR');
      } else {
        throw Exception(
          ApiErrorHandler.getErrorMessage(response.body, response.statusCode),
        );
      }
    } catch (e) {
      if (e.toString().contains('AUTH_ERROR')) {
        rethrow;
      }
      throw Exception(ApiErrorHandler.getErrorMessage(e, null));
    }
  }

  /// POST /api/obhs/complaints/raise
  /// Raises a new OBHS complaint for the logged-in worker.
  static Future<Map<String, dynamic>> raiseObhsComplaint({
    required String runInstanceId,
    required String coachNo,
    required String category,
    required String description,
    String? photoUrl,
  }) async {
    try {
      final token = await _getToken();
      if (token == null) throw Exception('AUTH_ERROR');

      final body = <String, dynamic>{
        'runInstanceId': runInstanceId,
        'coachNo': coachNo,
        'category': category,
        'description': description,
        if (photoUrl != null && photoUrl.isNotEmpty) 'photoUrl': photoUrl,
      };

      debugPrint('Raise complaint body: ${jsonEncode(body)}');

      final response = await _handleRequest(
        () => http.post(
          Uri.parse('$baseUrl/api/obhs/complaints/raise'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode(body),
        ),
      );

      debugPrint('Raise complaint status: ${response.statusCode}');
      debugPrint('Raise complaint body: ${response.body}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        final result = jsonDecode(response.body) as Map<String, dynamic>;
        return result;
      } else if (response.statusCode == 401) {
        throw Exception('AUTH_ERROR');
      } else {
        throw Exception(
          ApiErrorHandler.getErrorMessage(response.body, response.statusCode),
        );
      }
    } catch (e) {
      if (e.toString().contains('AUTH_ERROR')) rethrow;
      throw Exception(ApiErrorHandler.getErrorMessage(e, null));
    }
  }

  /// GET /api/obhs/worker/active-run — Returns worker's active run + coach assignments
  static Future<Map<String, dynamic>> getActiveRun() async {
    try {
      final token = await _getToken();
      if (token == null) throw Exception('AUTH_ERROR');

      final response = await _handleRequest(
        () => http.get(
          Uri.parse('$baseUrl/api/obhs/worker/active-run'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
        ),
      );

      debugPrint('Active run status: ${response.statusCode}');
      debugPrint('Active run body: ${response.body}');

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else if (response.statusCode == 401) {
        throw Exception('AUTH_ERROR');
      } else {
        throw Exception(
          ApiErrorHandler.getErrorMessage(response.body, response.statusCode),
        );
      }
    } catch (e) {
      if (e.toString().contains('AUTH_ERROR')) rethrow;
      throw Exception(ApiErrorHandler.getErrorMessage(e, null));
    }
  }

  /// GET /api/obhs/complaints?runInstanceId=...
  /// Fetches all complaints for a given run instance.
  /// Returns empty list gracefully if the endpoint is not yet available.
  static Future<Map<String, dynamic>> getObhsComplaints({
    String? runInstanceId,
    String? status,
  }) async {
    try {
      final token = await _getToken();
      if (token == null) throw Exception('AUTH_ERROR');

      final queryParams = <String, String>{};
      if (runInstanceId != null) queryParams['runInstanceId'] = runInstanceId;
      if (status != null) queryParams['status'] = status;

      final uri = Uri.parse('$baseUrl/api/obhs/complaints').replace(
        queryParameters: queryParams.isNotEmpty ? queryParams : null,
      );

      final response = await _handleRequest(
        () => http.get(uri, headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        }),
      );

      debugPrint('Get complaints status: ${response.statusCode}');
      debugPrint('Get complaints body: ${response.body.substring(0, response.body.length.clamp(0, 200))}');

      // If backend returns HTML (e.g. "Cannot GET ..."), treat as empty list
      final body = response.body.trim();
      final isHtml = body.startsWith('<') || body.contains('Cannot GET');
      if (isHtml) {
        throw Exception('API returned HTML. Endpoint might be incorrect.');
      }

      if (response.statusCode == 200 || response.statusCode == 201) {
        final decoded = jsonDecode(body);
        if (decoded is Map<String, dynamic>) return decoded;
        // If response is a bare List
        if (decoded is List) return {'success': true, 'complaints': decoded};
        return {'success': true, 'complaints': []};
      } else if (response.statusCode == 401) {
        throw Exception('AUTH_ERROR');
      } else {
        // Throw error so we can see what is wrong
        throw Exception('API error ${response.statusCode}: $body');
      }
    } catch (e) {
      if (e.toString().contains('AUTH_ERROR')) rethrow;
      rethrow;
    }
  }

  /// Resolves an existing complaint by ID.
  /// Submits admin remarks, resolution photo URL, and optionally an explicit status.
  static Future<Map<String, dynamic>> resolveComplaint({
    required String complaintId,
    required String adminRemarks,
    String? resolutionPhotoUrl,
    String? status, // 'SOLVED' or 'UNSOLVED' or 'CLOSED' etc. depending on backend
  }) async {
    try {
      final token = await _getToken();
      if (token == null) throw Exception('AUTH_ERROR');

      final body = <String, dynamic>{
        'adminRemarks': adminRemarks,
      };

      if (resolutionPhotoUrl != null && resolutionPhotoUrl.isNotEmpty) {
        body['resolutionPhotoUrl'] = resolutionPhotoUrl;
      }
      
      if (status != null && status.isNotEmpty) {
        body['status'] = status;
      }

      final response = await _handleRequest(
        () => http.patch(
          Uri.parse('$baseUrl/api/obhs/complaints/resolve/$complaintId'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode(body),
        ),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        return jsonDecode(response.body);
      } else if (response.statusCode == 401) {
        throw Exception('AUTH_ERROR');
      } else {
        throw Exception(
          ApiErrorHandler.getErrorMessage(response.body, response.statusCode),
        );
      }
    } catch (e) {
      debugPrint('Error resolving complaint: $e');
      rethrow;
    }
  }

  /// POST /api/obhs/feedback/passenger
  static Future<Map<String, dynamic>> submitPassengerFeedback({
    required String passengerName,
    String? pnrNumber,
    String? mobileNumber,
    required String coachNo,
    required Map<String, int> ratings,
    String? remarks,
    String? photoUrl,
    required String runInstanceId,
    String? workerId,
  }) async {
    try {
      final token = await _getToken();
      if (token == null) throw Exception('AUTH_ERROR');

      final body = <String, dynamic>{
        'passengerName': passengerName,
        'pnrNumber': pnrNumber ?? '',
        'mobileNumber': mobileNumber ?? '',
        'coachNo': coachNo,
        'ratings': ratings,
        'runInstanceId': runInstanceId,
        if (remarks != null && remarks.isNotEmpty) 'remarks': remarks,
        if (photoUrl != null && photoUrl.isNotEmpty) 'photoUrl': photoUrl,
        if (workerId != null && workerId.isNotEmpty) 'workerId': workerId,
      };

      debugPrint('Submit feedback body: ${jsonEncode(body)}');

      final response = await _handleRequest(
        () => http.post(
          Uri.parse('$baseUrl/api/obhs/feedback/passenger'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode(body),
        ),
      );

      debugPrint('Submit feedback status: ${response.statusCode}');
      debugPrint('Submit feedback body: ${response.body}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        return jsonDecode(response.body);
      } else if (response.statusCode == 401) {
        throw Exception('AUTH_ERROR');
      } else {
        throw Exception(
          ApiErrorHandler.getErrorMessage(response.body, response.statusCode),
        );
      }
    } catch (e) {
      if (e.toString().contains('AUTH_ERROR')) rethrow;
      throw Exception(ApiErrorHandler.getErrorMessage(e, null));
    }
  }

  /// POST /api/obhs/feedback/official
  static Future<Map<String, dynamic>> submitOfficialFeedback({
    required String inspectorName,
    required bool isRandomInspection,
    required String workerId,
    required String workerName,
    required String coachNo,
    required String raterType,
    required Map<String, int> ratings,
    String? remarks,
    String? photoUrl,
    String? runInstanceId,
  }) async {
    try {
      final token = await _getToken();
      if (token == null) throw Exception('AUTH_ERROR');

      final body = <String, dynamic>{
        'inspectorName': inspectorName,
        'isRandomInspection': isRandomInspection ? 'Yes' : 'No',
        'workerId': workerId,
        'workerName': workerName,
        'coachNo': coachNo,
        'raterType': raterType,
        'ratings': ratings,
        if (runInstanceId != null && runInstanceId.isNotEmpty) 'runInstanceId': runInstanceId,
        if (remarks != null && remarks.isNotEmpty) 'remarks': remarks,
        if (photoUrl != null && photoUrl.isNotEmpty) 'photoUrl': photoUrl,
      };

      debugPrint('Submit official feedback body: ${jsonEncode(body)}');

      final response = await _handleRequest(
        () => http.post(
          Uri.parse('$baseUrl/api/obhs/feedback/official'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode(body),
        ),
      );

      debugPrint('Submit official feedback status: ${response.statusCode}');
      debugPrint('Submit official feedback body: ${response.body}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        return jsonDecode(response.body);
      } else if (response.statusCode == 401) {
        throw Exception('AUTH_ERROR');
      } else {
        throw Exception(
          ApiErrorHandler.getErrorMessage(response.body, response.statusCode),
        );
      }
    } catch (e) {
      if (e.toString().contains('AUTH_ERROR')) rethrow;
      throw Exception(ApiErrorHandler.getErrorMessage(e, null));
    }
  }

  /// GET /api/obhs/feedback/worker-summary
  static Future<Map<String, dynamic>> getFeedbackSummary({
    String? runInstanceId,
    String? workerId,
  }) async {
    try {
      final token = await _getToken();
      if (token == null) throw Exception('AUTH_ERROR');

      final queryParams = <String, String>{};
      if (runInstanceId != null) queryParams['runInstanceId'] = runInstanceId;
      if (workerId != null) queryParams['workerId'] = workerId;

      final uri = Uri.parse('$baseUrl/api/obhs/feedback/worker-summary').replace(
        queryParameters: queryParams.isNotEmpty ? queryParams : null,
      );

      final response = await _handleRequest(
        () => http.get(uri, headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        }),
      );

      debugPrint('Get feedback summary status: ${response.statusCode}');
      final body = response.body.trim();
      debugPrint('Get feedback summary body: ${body.substring(0, body.length.clamp(0, 200))}');

      final isHtml = body.startsWith('<') || body.contains('Cannot GET');

      if (isHtml || response.statusCode == 404) {
        debugPrint('Feedback summary endpoint not available yet — returning empty data.');
        return {'success': true, 'data': []};
      }

      if (response.statusCode == 200) {
        final decoded = jsonDecode(body);
        if (decoded is Map<String, dynamic>) return decoded;
        if (decoded is List) return {'success': true, 'data': decoded};
        return {'success': true, 'data': []};
      } else if (response.statusCode == 401) {
        throw Exception('AUTH_ERROR');
      } else {
        debugPrint('Get feedback error ${response.statusCode}: $body');
        return {'success': true, 'data': []};
      }
    } catch (e) {
      if (e.toString().contains('AUTH_ERROR')) rethrow;
      debugPrint('Get feedback exception: $e');
      return {'success': true, 'data': []};
    }
  }

  static Future<Map<String, dynamic>> verifyFace({
    required String image1Url,
    required String image2Url,
  }) async {
    try {
      final token = await _getToken();
      if (token == null) throw Exception('AUTH_ERROR');

      final response = await _handleRequest(
        () => http.post(
          Uri.parse('$baseUrl/api/verifyFace'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode({
            'image1Url': image1Url,
            'image2Url': image2Url,
          }),
        ),
      );

      if (response.statusCode == 200 || response.statusCode == 400) {
        return jsonDecode(response.body);
      } else if (response.statusCode == 401) {
        throw Exception('AUTH_ERROR');
      } else {
        throw Exception(
          ApiErrorHandler.getErrorMessage(response.body, response.statusCode),
        );
      }
    } catch (e) {
      if (e.toString().contains('AUTH_ERROR')) rethrow;
      throw Exception(ApiErrorHandler.getErrorMessage(e, null));
    }
  }

  /// GET /api/passenger/tasks?trainNo=...&coachNo=...
  /// Fetches tasks raised by passengers.
  static Future<Map<String, dynamic>> getPassengerTasks({
    String? trainNo,
    String? coachNo,
  }) async {
    try {
      final token = await _getToken();
      if (token == null) throw Exception('AUTH_ERROR');

      final queryParams = <String, String>{};
      if (trainNo != null) queryParams['trainNo'] = trainNo;
      if (coachNo != null) queryParams['coachNo'] = coachNo;

      final uri = Uri.parse('$baseUrl/api/passenger/tasks').replace(
        queryParameters: queryParams.isNotEmpty ? queryParams : null,
      );

      final response = await _handleRequest(
        () => http.get(uri, headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        }),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else if (response.statusCode == 401) {
        throw Exception('AUTH_ERROR');
      } else {
        throw Exception(
          ApiErrorHandler.getErrorMessage(response.body, response.statusCode),
        );
      }
    } catch (e) {
      rethrow;
    }
  }

  static Future<Map<String, dynamic>> reportAttendanceIssue({
    required String runInstanceId,
    required String issueType,
    required String remark,
    String? photoUrl,
    required String attendanceType,
    double? latitude,
    double? longitude,
  }) async {
    try {
      final token = await _getToken();
      if (token == null) throw Exception('AUTH_ERROR');

      final response = await _handleRequest(
        () => http.post(
          Uri.parse('$baseUrl/api/obhs/attendance/report-issue'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode({
            'runInstanceId': runInstanceId,
            'issueType': issueType,
            'remark': remark,
            'photoUrl': photoUrl,
            'attendanceType': attendanceType,
            'latitude': latitude,
            'longitude': longitude,
          }),
        ),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        return jsonDecode(response.body);
      } else {
        throw Exception(ApiErrorHandler.getErrorMessage(response.body, response.statusCode));
      }
    } catch (e) {
      rethrow;
    }
  }
}

