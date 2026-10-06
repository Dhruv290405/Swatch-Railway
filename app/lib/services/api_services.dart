import 'dart:async';
import 'dart:convert';
import 'package:crm_train/model/billing_models.dart';
import 'package:crm_train/model/cleaning_form_models.dart';
import 'package:crm_train/model/contracts_model.dart';
import 'package:crm_train/model/performance_billing_models.dart';
import 'package:crm_train/model/user_registeration_model.dart';
import 'package:crm_train/model/station_models.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../helper/api_error_handler.dart';
import '../model/coach_form_model.dart';
import '../model/cts_form_model.dart';
import '../model/premises_form_model.dart';
import '../model/train_model.dart';
import '../model/user_entity_model.dart';

class ApiService {
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

  static bool _isTransient(Object e, int? statusCode) {
    if (statusCode != null) {
      if (statusCode >= 500 || statusCode == 429 || statusCode == 408) return true;
      if (statusCode >= 200 && statusCode < 400) return false;
    }
    final text = e.toString();
    return text.contains('SocketException') ||
        text.contains('TimeoutException') ||
        text.contains('HttpException') ||
        text.contains('Connection closed') ||
        text.contains('Connection reset') ||
        text.contains('Request timeout') ||
        text.contains('HandshakeException') ||
        text.contains('temporarily unavailable');
  }

  /// GET with a hard timeout and a single automatic retry.
  ///
  /// Reads that run right after login used to hang forever on a flaky mobile
  /// connection (no timeout at all), which is what surfaced as the random
  /// "connection problem"/endless spinner after tapping Sign In.
  static Future<http.Response> getWithRetry(
    Uri uri, {
    Map<String, String>? headers,
    int retries = 1,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    Object? lastError;
    int? lastStatus;
    for (var attempt = 0; attempt <= retries; attempt++) {
      if (attempt > 0) {
        await Future.delayed(Duration(milliseconds: 600 * attempt));
      }
      try {
        final response = await http.get(uri, headers: headers).timeout(
              timeout,
              onTimeout: () => throw TimeoutException('Request timeout'),
            );
        if (response.statusCode >= 200 && response.statusCode < 400) return response;
        lastStatus = response.statusCode;
        lastError = Exception('HTTP ${response.statusCode}');
      } catch (e) {
        lastError = e;
      }
      if (!_isTransient(lastError, lastStatus)) {
        throw lastError ?? Exception('Request failed');
      }
    }
    throw lastError ?? Exception('Request failed');
  }

  static String baseUrl = 'https://swatch-railway-0zer.onrender.com';
  static void setBaseUrl(String url) { baseUrl = url; }

  static Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('token');
  }

  static Future<void> saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('token', token);
    await prefs.setString('auth_token', token);
  }

  static Future<void> clearToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    await prefs.remove('auth_token');
  }

  static Future<Map<String, dynamic>> createUser({
    required String userType,
    required String role,
    required String fullName,
    required String designation,
    required String email,
    required String password,
    required String mobile,
    String? aadhaarNumber,
    String? zone,
    String? division,
    String? depot,
    String? entityId,
    String? contractId,
    List<String>? stations,
    String? stationId,
    String? areaId,
    String? platformId,
    String? createdById,
    String? trainId,
    List<String>? trainIds,
    String? worker_type,
    String? signatureBase64,
  }) async {
    try {
      final token = await getToken();
      final response = await http.post(
        Uri.parse('$baseUrl/api/admin/createUser'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'userType': userType,
          'role': role,
          'fullName': fullName,
          'designation': designation,
          'email': email,
          'mobile': mobile,
          'aadhaarNumber': aadhaarNumber,
          'password': password,
          'zone': zone,
          'division': division,
          'depot': depot,
          'entityId': entityId,
          'contractId': contractId,
          'stations': stations,
          'stationId': stationId,
          'areaId': areaId,
          'platformId': platformId,
          'createdById': createdById,
          'trainId': trainId,
          'trainIds': trainIds,
          'worker_type': worker_type,
          'signatureBase64': signatureBase64,
        }),
      );

      if (response.statusCode == 201 || response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['error'] ?? 'Failed to create user');
      }
    } catch (e) {
      throw Exception('Error creating user: $e');
    }
  }

  static Future<Map<String, dynamic>> updateUser({
    required String uid,
    required String userType,
    required String role,
    required String fullName,
    required String designation,
    required String email,
    required String mobile,
    String? zone,
    String? division,
    String? depot,
    String? entityId,
    String? stationId,
    String? areaId,
    String? platformId,
    required String editedById,
    String? trainId,
    List<String>? trainIds,
    String? worker_type,
    String? status,
  }) async {
    try {
      final token = await getToken();
      final response = await http.put(
        Uri.parse('$baseUrl/api/admin/updateUser/$uid'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'userType': userType,
          'role': role,
          'fullName': fullName,
          'designation': designation,
          'email': email,
          'mobile': mobile,
          'zone': zone,
          'division': division,
          'depot': depot,
          'entityId': entityId,
          'stationId': stationId,
          'areaId': areaId,
          'platformId': platformId,
          'editedById': editedById,
          'trainId': trainId,
          'trainIds': trainIds,
          'worker_type': worker_type,
          'status': status,
        }),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['error'] ?? 'Failed to update user');
      }
    } catch (e) {
      throw Exception('Error updating user: $e');
    }
  }

  static Future<List<UserRegistrationModel>> getPendingUsers({
    String? entityId,
    int? page,
    int? limit,
  }) async {
    try {
      final token = await getToken();
      final uri = _userListUri(status: 'PENDING', entityId: entityId, page: page, limit: limit);
      final response = await getWithRetry(uri, headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      });

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        final List users = data['users'] ?? [];

        final parsedUsers = users
            .map<UserRegistrationModel?>((u) {
              try {
                final userMap = Map<String, dynamic>.from(u);
                final user = UserRegistrationModel.fromJson(userMap);
                return user;
              } catch (err, stack) {
                print(stack);
                return null;
              }
            })
            .whereType<UserRegistrationModel>()
            .toList();

        print('Successfully parsed ${parsedUsers.length} pending users');
        return parsedUsers;
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['error'] ?? 'Failed to fetch pending users');
      }
    } catch (e, stack) {
      print('Error fetching pending users: $e');
      print(stack);
      throw Exception('Error fetching pending users: $e');
    }
  }

  static Uri _userListUri({
    required String status,
    String? entityId,
    int? page,
    int? limit,
  }) {
    final params = <String, String>{'status': status};
    if (entityId != null && entityId.isNotEmpty) params['entityId'] = entityId;
    if (page != null && page > 0) params['page'] = '$page';
    if (limit != null && limit > 0) params['limit'] = '$limit';
    return Uri.parse('$baseUrl/api/admin/users').replace(queryParameters: params);
  }

  static Future<List<UserRegistrationModel>> getApprovedUsers({
    String? entityId,
    int? page,
    int? limit,
  }) async {
    try {
      final token = await getToken();
      final uri = _userListUri(status: 'APPROVED', entityId: entityId, page: page, limit: limit);
      final response = await getWithRetry(uri, headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      });

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        final List users = data['users'] ?? [];

        return users
            .map<UserRegistrationModel>(
              (u) =>
                  UserRegistrationModel.fromJson(Map<String, dynamic>.from(u)),
            )
            .toList();
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['error'] ?? 'Failed to fetch approved users');
      }
    } catch (e) {
      throw Exception('Error fetching approved users: $e');
    }
  }

  static Future<List<UserRegistrationModel>> getRejectedUsers({
    String? entityId,
    int? page,
    int? limit,
  }) async {
    try {
      final token = await getToken();
      final uri = _userListUri(status: 'REJECTED', entityId: entityId, page: page, limit: limit);
      final response = await getWithRetry(uri, headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      });

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        final List users = data['users'] ?? [];

        return users
            .map<UserRegistrationModel>(
              (u) =>
                  UserRegistrationModel.fromJson(Map<String, dynamic>.from(u)),
            )
            .toList();
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['error'] ?? 'Failed to fetch rejected users');
      }
    } catch (e) {
      throw Exception('Error fetching rejected users: $e');
    }
  }

  /// Walks the paginated user list and concatenates the pages.
  ///
  /// Screens that genuinely need every user (Users tab) now pull it in small
  /// chunks instead of one big response, so a dropped connection only loses the
  /// page that failed (each page is retried once) rather than the whole list.
  static Future<List<UserRegistrationModel>> getAllUsersByStatus(
    String status, {
    String? entityId,
    int pageSize = 100,
    int maxPages = 20,
  }) async {
    final token = await getToken();
    final all = <UserRegistrationModel>[];
    for (var page = 1; page <= maxPages; page++) {
      final uri = _userListUri(
        status: status,
        entityId: entityId,
        page: page,
        limit: pageSize,
      );
      final response = await getWithRetry(uri, headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      });
      if (response.statusCode != 200) break;
      final data = jsonDecode(response.body);
      final users = (data['users'] as List?) ?? [];
      for (final u in users) {
        try {
          all.add(UserRegistrationModel.fromJson(Map<String, dynamic>.from(u)));
        } catch (_) {
          // Skip malformed entries instead of failing the whole page.
        }
      }
      if (data['hasMore'] != true) break;
    }
    return all;
  }

  static Future<Map<String, dynamic>> approveUser(
    String uid, {
    String? approvedById,
  }) async {
    try {
      final token = await getToken();
      final response = await http.post(
        Uri.parse('$baseUrl/api/master/approveUser/$uid'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'approvedById': approvedById}),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['error'] ?? 'Failed to approve user');
      }
    } catch (e) {
      throw Exception('Error approving user: $e');
    }
  }

  static Future<Map<String, dynamic>> rejectUser(String uid) async {
    try {
      final token = await getToken();
      final response = await http.post(
        Uri.parse('$baseUrl/api/master/rejectUser/$uid'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['error'] ?? 'Failed to reject user');
      }
    } catch (e) {
      throw Exception('Error rejecting user: $e');
    }
  }

  //<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<Create Entity>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>

  static Future<Map<String, dynamic>> createEntity({
    required String contractorName,
    required String registrationType,
    required String panNumber,
    required String gstinNumber,
    required String registeredAddress,
    String? alternateContact,
    required String contactNumber,
    required String email,
    String? website,
    String? yearOfEstablishment,
    required String gemId,
  }) async {
    try {
      final token = await getToken();
      final response = await http.post(
        Uri.parse('$baseUrl/api/contractors'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'companyName': contractorName,
          'registrationType': registrationType,
          'panNumber': panNumber,
          'gstinNumber': gstinNumber,
          'registeredAddress': registeredAddress,
          'contactNumber': contactNumber,
          'alternateContact': alternateContact,
          'email': email,
          'website': website,
          'yearOfEstablishment': yearOfEstablishment,
          'gemId': gemId,
          'status': 'PENDING',
        }),
      );

      if (response.statusCode == 201 || response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['error'] ?? 'Failed to create user');
      }
    } catch (e) {
      throw Exception('Error creating user: $e');
    }
  }

  static Future<List<EntityModel>> getPendingEntity() async {
    try {
      final token = await getToken();
      final response = await http.get(
        Uri.parse('$baseUrl/api/contractors?status=PENDING'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        print('=== getPendingEntity API Response ===');
        print(
          'Response body (first 500 chars): ${response.body.substring(0, response.body.length > 500 ? 500 : response.body.length)}',
        );

        final List entity = data['contractors'] ?? [];

        if (entity.isNotEmpty) {
          print('First entity raw data: ${entity[0]}');
          print('createdAt from API: ${entity[0]['createdAt']}');
          print('createdByName from API: ${entity[0]['createdByName']}');
        }

        return entity
            .map<EntityModel>(
              (u) => EntityModel.fromJson(Map<String, dynamic>.from(u)),
            )
            .toList();
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['error'] ?? 'Failed to fetch pending users');
      }
    } catch (e) {
      throw Exception('Error fetching pending users: $e');
    }
  }

  static Future<List<Map<String, dynamic>>> getContractsForDropdown({String? entityId}) async {
    try {
      final token = await getToken();
      String url = '$baseUrl/api/contracts/for-user-creation';
      if (entityId != null && entityId.isNotEmpty) {
        url += '?entityId=$entityId';
      }
      final response = await http.get(
        Uri.parse(url),
        headers: { 'Authorization': 'Bearer $token' },
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return List<Map<String, dynamic>>.from(data['contracts'] ?? []);
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  static Future<List<EntityModel>> getApprovedEntity() async {
    try {
      final token = await getToken();
      final response = await http.get(
        Uri.parse('$baseUrl/api/contractors?status=APPROVED'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        print('=== getApprovedEntity API Response ===');
        print(
          'Response body (first 500 chars): ${response.body.substring(0, response.body.length > 500 ? 500 : response.body.length)}',
        );

        final List entity = data['contractors'] ?? [];

        if (entity.isNotEmpty) {
          print('First approved entity raw data: ${entity[0]}');
          print('createdAt from API: ${entity[0]['createdAt']}');
          print('createdByName from API: ${entity[0]['createdByName']}');
        }

        return entity
            .map<EntityModel>(
              (u) => EntityModel.fromJson(Map<String, dynamic>.from(u)),
            )
            .toList();
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['error'] ?? 'Failed to fetch pending users');
      }
    } catch (e) {
      throw Exception('Error fetching pending users: $e');
    }
  }

  static Future<List<EntityModel>> getRejectedEntity() async {
    try {
      final token = await getToken();
      final response = await http.get(
        Uri.parse('$baseUrl/api/contractors?status=REJECTED'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        final List entity = data['contractors'] ?? [];

        return entity
            .map<EntityModel>(
              (u) => EntityModel.fromJson(Map<String, dynamic>.from(u)),
            )
            .toList();
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['error'] ?? 'Failed to fetch pending users');
      }
    } catch (e) {
      throw Exception('Error fetching pending users: $e');
    }
  }

  static Future<List<EntityModel>> getSuspendedEntity() async {
    try {
      final token = await getToken();
      final response = await http.get(
        Uri.parse('$baseUrl/api/contractors?status=SUSPENDED'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        final List entity = data['contractors'] ?? [];

        return entity
            .map<EntityModel>(
              (u) => EntityModel.fromJson(Map<String, dynamic>.from(u)),
            )
            .toList();
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['error'] ?? 'Failed to fetch pending users');
      }
    } catch (e) {
      throw Exception('Error fetching pending users: $e');
    }
  }

  static Future<Map<String, dynamic>> approveEntity(String id) async {
    try {
      final token = await getToken();
      final response = await http.post(
        Uri.parse('$baseUrl/api/master/approveContractor/$id'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['error'] ?? 'Failed to approve user');
      }
    } catch (e) {
      print("Error in approveEntity: $e");
      throw Exception('Error approving user: $e');
    }
  }

  static Future<Map<String, dynamic>> rejectEntity(String id) async {
    try {
      final token = await getToken();
      final response = await http.post(
        Uri.parse('$baseUrl/api/master/rejectContractor/$id'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['error'] ?? 'Failed to reject user');
      }
    } catch (e) {
      throw Exception('Error rejecting user: $e');
    }
  }

  static Future<Map<String, dynamic>> updateEntity({
    required String uid,
    required Map<String, dynamic> entityData,
  }) async {
    try {
      final token = await getToken();
      final response = await http.put(
        Uri.parse('$baseUrl/api/contractors/$uid'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(entityData),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['error'] ?? 'Failed to update entity');
      }
    } catch (e) {
      print("Error in updateEntity: $e");
      throw Exception('Error updating entity: $e');
    }
  }

  //<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<Create Contracts>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>

  static Future<Map<String, dynamic>> createContract({
    required String contractNumber,
    required String contractName,
    required String entityId,
    required String zone,
    String? division,
    String? depot,
    List<String>? stationIds,
    List<String>? trainIds,
    required String startDate,
    required String endDate,
    double contractValue = 0,
    String? billingCycle,
    bool scoringApplicability = true,
    required String? workCategories,
    String? remarks,
    required String status,
    required String repName,
    required String repDesignation,
    required String repMobile,
    required String repEmail,
    required String repIdProofType,
    required String repIdProofNumber,
    String? contractType,
  }) async {
    try {
      final token = await getToken();
      final response = await http.post(
        Uri.parse('$baseUrl/api/contracts'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'contractNumber': contractNumber,
          'contractName': contractName,
          'zone': zone,
          'entityId': entityId,
          'division': division,
          'depot': depot,
          if (stationIds != null) 'stationIds': stationIds,
          if (trainIds != null) 'trainIds': trainIds,
          'startDate': startDate,
          'endDate': endDate,
          'contractValue': contractValue,
          if (billingCycle != null) 'billingCycle': billingCycle,
          'scoringApplicability': scoringApplicability,
          'remarks': remarks,
          'workCategories': workCategories,
          'status': status,
          'repName': repName,
          'repDesignation': repDesignation,
          'repMobile': repMobile,
          'repEmail': repEmail,
          'repIdProofType': repIdProofType,
          'repIdProofNumber': repIdProofNumber,
          if (contractType != null) 'contractType': contractType,
        }),
      );

      if (response.statusCode == 201 || response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['error'] ?? 'Failed to create user');
      }
    } catch (e) {
      throw Exception('Error creating user: $e');
    }
  }

  static Future<Map<String, dynamic>> updateContract({
    required String contractId,
    required String status,
    double? contractValue,
    String? billingCycle,
    bool? scoringApplicability,
    required String repName,
    required String repDesignation,
    required String repMobile,
    required String repEmail,
    required String repIdProofType,
    required String repIdProofNumber,
  }) async {
    try {
      final token = await getToken();
      final response = await http.put(
        Uri.parse('$baseUrl/api/contracts/$contractId'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'status': status,
          if (contractValue != null) 'contractValue': contractValue,
          if (billingCycle != null) 'billingCycle': billingCycle,
          if (scoringApplicability != null) 'scoringApplicability': scoringApplicability,
          'repName': repName,
          'repDesignation': repDesignation,
          'repMobile': repMobile,
          'repEmail': repEmail,
          'repIdProofType': repIdProofType,
          'repIdProofNumber': repIdProofNumber,
        }),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['error'] ?? 'Failed to update contract');
      }
    } catch (e) {
      throw Exception('Error updating contract: $e');
    }
  }

  static Future<List<ContractModel>> getActiveContracts({String? contractType}) async {
    final token = await getToken();
    String url = '$baseUrl/api/contracts?status=Active';
    if (contractType != null) url += '&contractType=$contractType';
    final response = await http.get(
      Uri.parse(url),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final List contracts = data['contracts'] ?? [];
      return contracts.map((e) => ContractModel.fromJson(e)).toList();
    } else {
      throw Exception('Failed to load active contracts');
    }
  }

  static Future<List<ContractModel>> getInActiveContracts({String? contractType}) async {
    final token = await getToken();
    String url = '$baseUrl/api/contracts?status=Inactive';
    if (contractType != null) url += '&contractType=$contractType';
    final response = await http.get(
      Uri.parse(url),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final List contracts = data['contracts'] ?? [];
      return contracts.map((e) => ContractModel.fromJson(e)).toList();
    } else {
      throw Exception('Failed to load inactive contracts');
    }
  }

  static Future<ContractModel> getContractByNumber(
    String contractNumber,
  ) async {
    try {
      final token = await getToken();
      final response = await http.get(
        Uri.parse('$baseUrl/api/contracts/number/$contractNumber'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return ContractModel.fromJson(Map<String, dynamic>.from(data));
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['error'] ?? 'Failed to fetch contract');
      }
    } catch (e) {
      throw Exception('Error fetching contract: $e');
    }
  }

  static Future<List<ContractModel>> getContractsContractor(
    String entityId, {
    String? contractType,
  }) async {
    final token = await getToken();
    String url = '$baseUrl/api/contracts/by-entity/$entityId';
    if (contractType != null) url += '?contractType=$contractType';
    final response = await getWithRetry(
      Uri.parse(url),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final List contracts = data['contracts'] ?? [];
      return contracts.map((e) => ContractModel.fromJson(e)).toList();
    } else {
      throw Exception('Failed to load inactive contracts');
    }
  }

  static Future<List<ContractModel>> getContractsByStatus(
    String entityId,
    String zone,
    String division, {
    String? contractType,
  }) async {
    final token = await getToken();
    String url = '$baseUrl/api/contracts/by-entity/$entityId?zone=$zone&division=$division';
    if (contractType != null) url += '&contractType=$contractType';
    final response = await http.get(
      Uri.parse(url),
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final List contracts = data['contracts'] ?? [];
      return contracts.map((e) => ContractModel.fromJson(e)).toList();
    } else {
      throw Exception('Failed to load inactive contracts');
    }
  }

  static Future<List<ContractModel>> getContractsActive(
    String entityId,
    String zone,
    String division, {
    String? contractType,
  }) async {
    final token = await getToken();
    String url = '$baseUrl/api/contracts/by-entity/$entityId?zone=$zone&division=$division&status=Active';
    if (contractType != null) url += '&contractType=$contractType';
    final response = await http.get(
      Uri.parse(url),
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final List contracts = data['contracts'] ?? [];
      return contracts.map((e) => ContractModel.fromJson(e)).toList();
    } else {
      throw Exception('Failed to load inactive contracts');
    }
  }

  static Future<List<ContractModel>> getStationContracts(
    String stationId, {
    String? contractType,
  }) async {
    final token = await getToken();
    final params = <String, String>{
      'stationId': stationId,
    };
    if (contractType != null) params['contractType'] = contractType;
    final uri = Uri.parse('$baseUrl/api/contracts').replace(queryParameters: params);
    final response = await http.get(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final List contracts = data['contracts'] ?? [];
      return contracts.map((e) => ContractModel.fromJson(e)).toList();
    }
    throw Exception('Failed to load contracts for station');
  }

  //<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<Train APis>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>

  static Future<Map<String, dynamic>> sendPassengerOtp({
    required String phone,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/passenger/send-otp'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'phone': phone}),
      );

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200 || response.statusCode == 201) {
        return data;
      }
      throw Exception(
        data['message'] ?? data['error'] ?? 'Failed to send passenger OTP',
      );
    } catch (e) {
      throw Exception('Error sending passenger OTP: $e');
    }
  }

  static Future<Map<String, dynamic>> verifyPassengerOtp({
    required String phone,
    required String otp,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/passenger/verify-otp'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'phone': phone, 'otp': otp}),
      );

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200 || response.statusCode == 201) {
        return data;
      }
      throw Exception(
        data['message'] ?? data['error'] ?? 'Failed to verify passenger OTP',
      );
    } catch (e) {
      throw Exception('Error verifying passenger OTP: $e');
    }
  }

  static Future<Map<String, dynamic>> createTrain({
    required String? trainNo,
    required String? trainName,
    required String? origin,
    required String? destination,
    required List<String> days,
    required String zone,
    required List<String> trainApplicableFor,
    required String division,
    String? depot,
    required String status,
    String? outboundTrainNo,
    String? inboundTrainNo,
    String? outboundTravelTime,
    String? inboundTravelTime,
    String? layoverDestination,
    String? layoverOrigin,
    String? journeyStartTime,
  }) async {
    try {
      final token = await getToken();

      final body = <String, dynamic>{
        'days': days,
        'zone': zone,
        'division': division,
        'status': status,
        'TrainApplicableFor': trainApplicableFor,
      };

      if (trainNo != null && trainNo.isNotEmpty) {
        body['trainNo'] = trainNo;
      }
      if (trainName != null && trainName.isNotEmpty) {
        body['trainName'] = trainName;
      }
      if (origin != null && origin.isNotEmpty) {
        body['origin'] = origin;
      }
      if (destination != null && destination.isNotEmpty) {
        body['destination'] = destination;
      }
      if (depot != null && depot.isNotEmpty) {
        body['depot'] = depot;
      }

      if (outboundTrainNo != null && outboundTrainNo.isNotEmpty) {
        body['outboundTrainNo'] = outboundTrainNo;
      }

      if (inboundTrainNo != null && inboundTrainNo.isNotEmpty) {
        body['inboundTrainNo'] = inboundTrainNo;
      }
      
      if (outboundTravelTime != null && outboundTravelTime.isNotEmpty) {
        body['outboundDurationStr'] = outboundTravelTime;
      }
      if (inboundTravelTime != null && inboundTravelTime.isNotEmpty) {
        body['inboundDurationStr'] = inboundTravelTime;
      }
      if (layoverDestination != null && layoverDestination.isNotEmpty) {
        body['layoverDestStr'] = layoverDestination;
      }
      if (layoverOrigin != null && layoverOrigin.isNotEmpty) {
        body['layoverOriginStr'] = layoverOrigin;
      }
      if (journeyStartTime != null && journeyStartTime.isNotEmpty) {
        body['journeyStartTime'] = journeyStartTime;
      }

      int totalHours = 0;
      int outboundAndLayoverHours = 0;

      int parseHours(String? timeStr) {
        if (timeStr == null || timeStr.isEmpty) return 0;
        final parts = timeStr.split(':');
        if (parts.length == 3) {
          int days = int.tryParse(parts[0]) ?? 0;
          int hours = int.tryParse(parts[1]) ?? 0;
          return (days * 24) + hours;
        }
        return 0;
      }

      final outH = parseHours(outboundTravelTime);
      final inH = parseHours(inboundTravelTime);
      final layDestH = parseHours(layoverDestination);
      final layOriH = parseHours(layoverOrigin);

      outboundAndLayoverHours = outH + layDestH;
      totalHours = outH + inH + layDestH + layOriH;

      if (totalHours > 0) {
        body['cycleLength'] = (totalHours / 24).ceil();
        if (body['cycleLength'] == 0) body['cycleLength'] = 1;
      }
      if (outboundAndLayoverHours > 0) {
        body['returnOffset'] = (outboundAndLayoverHours / 24).floor();
      }

      final response = await http.post(
        Uri.parse('$baseUrl/api/trains'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(body),
      );

      if (response.statusCode == 201 || response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['error'] ?? 'Failed to create train');
      }
    } catch (e) {
      throw Exception('Error creating train: $e');
    }
  }

  static Future<List<TrainModel>> getActiveTrains() async {
    try {
      final token = await getToken();
      final response = await http.get(
        Uri.parse('$baseUrl/api/trains?status=active'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List trains = data['trains'] ?? [];

        return trains
            .map<TrainModel>(
              (t) => TrainModel.fromJson(Map<String, dynamic>.from(t)),
            )
            .toList();
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['error'] ?? 'Failed to fetch active trains');
      }
    } catch (e) {
      throw Exception('Error fetching active trains: $e');
    }
  }

  static Future<List<TrainModel>> getInactiveTrains() async {
    try {
      final token = await getToken();
      final response = await http.get(
        Uri.parse('$baseUrl/api/trains?status=inactive'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List trains = data['trains'] ?? [];

        return trains
            .map<TrainModel>(
              (t) => TrainModel.fromJson(Map<String, dynamic>.from(t)),
            )
            .toList();
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['error'] ?? 'Failed to fetch inactive trains');
      }
    } catch (e) {
      throw Exception('Error fetching inactive trains: $e');
    }
  }

  static Future<List<TrainModel>> getAllTrains() async {
    try {
      final token = await getToken();
      final response = await http.get(
        Uri.parse('$baseUrl/api/trains'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List trains = data['trains'] ?? [];

        return trains
            .map<TrainModel>(
              (t) => TrainModel.fromJson(Map<String, dynamic>.from(t)),
            )
            .toList();
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['error'] ?? 'Failed to fetch trains');
      }
    } catch (e) {
      throw Exception('Error fetching trains: $e');
    }
  }

  static Future<Map<String, dynamic>> updateTrain({
    required String uid,
    required String? trainNo,
    required String? trainName,
    required String? origin,
    required String? destination,
    required List<String> days,
    required String zone,
    required List<String> trainApplicableFor,
    required String division,
    String? depot,
    required String status,
    String? outboundTrainNo,
    String? inboundTrainNo,
    String? outboundTravelTime,
    String? inboundTravelTime,
    String? layoverDestination,
    String? layoverOrigin,
    String? journeyStartTime,
  }) async {
    try {
      final token = await getToken();

      final body = <String, dynamic>{
        'days': days,
        'zone': zone,
        'division': division,
        'status': status,
        'TrainApplicableFor': trainApplicableFor,
      };

      if (trainNo != null && trainNo.isNotEmpty) {
        body['trainNo'] = trainNo;
      }
      if (trainName != null && trainName.isNotEmpty) {
        body['trainName'] = trainName;
      }
      if (origin != null && origin.isNotEmpty) {
        body['origin'] = origin;
      }
      if (destination != null && destination.isNotEmpty) {
        body['destination'] = destination;
      }
      if (depot != null && depot.isNotEmpty) {
        body['depot'] = depot;
      }

      if (outboundTrainNo != null && outboundTrainNo.isNotEmpty) {
        body['outboundTrainNo'] = outboundTrainNo;
      }

      if (inboundTrainNo != null && inboundTrainNo.isNotEmpty) {
        body['inboundTrainNo'] = inboundTrainNo;
      }
      
      if (outboundTravelTime != null && outboundTravelTime.isNotEmpty) {
        body['outboundDurationStr'] = outboundTravelTime;
      }
      if (inboundTravelTime != null && inboundTravelTime.isNotEmpty) {
        body['inboundDurationStr'] = inboundTravelTime;
      }
      if (layoverDestination != null && layoverDestination.isNotEmpty) {
        body['layoverDestStr'] = layoverDestination;
      }
      if (layoverOrigin != null && layoverOrigin.isNotEmpty) {
        body['layoverOriginStr'] = layoverOrigin;
      }
      if (journeyStartTime != null && journeyStartTime.isNotEmpty) {
        body['journeyStartTime'] = journeyStartTime;
      }

      int totalHours = 0;
      int outboundAndLayoverHours = 0;

      int parseHours(String? timeStr) {
        if (timeStr == null || timeStr.isEmpty) return 0;
        final parts = timeStr.split(':');
        if (parts.length == 3) {
          int days = int.tryParse(parts[0]) ?? 0;
          int hours = int.tryParse(parts[1]) ?? 0;
          return (days * 24) + hours;
        }
        return 0;
      }

      final outH = parseHours(outboundTravelTime);
      final inH = parseHours(inboundTravelTime);
      final layDestH = parseHours(layoverDestination);
      final layOriH = parseHours(layoverOrigin);

      outboundAndLayoverHours = outH + layDestH;
      totalHours = outH + inH + layDestH + layOriH;

      if (totalHours > 0) {
        body['cycleLength'] = (totalHours / 24).ceil();
        if (body['cycleLength'] == 0) body['cycleLength'] = 1;
      }
      if (outboundAndLayoverHours > 0) {
        body['returnOffset'] = (outboundAndLayoverHours / 24).floor();
      }

      // DO NOT send outboundDurationStr, inboundDurationStr, layoverDestStr, layoverOriginStr, journeyStartTime
      // as they are not in the backend schema and cause "Invalid field name." on PUT.

      final response = await http.put(
        Uri.parse('$baseUrl/api/trains/$uid'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(body),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['error'] ?? 'Failed to update train');
      }
    } catch (e) {
      throw Exception('Error updating train: $e');
    }
  }

  ////<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<Coach form>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>

  static Future<Map<String, dynamic>> submitCoachForm({
    required String trainId,
    required String formDateTime,
    required String contractId,
    required int coachCount,
    required List<String> machinesUsed,
    required Map<String, double> chemicals,
    required List<Map<String, String>> manpower,
    required Map<String, String> submittedTo,
    required Map<String, String> signature,
  }) async {
    try {
      final token = await getToken();

      final response = await http.post(
        Uri.parse('$baseUrl/api/coach-forms'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'trainId': trainId,
          'formDateTime': formDateTime,
          'coachCount': coachCount,
          'machinesUsed': machinesUsed,
          'chemicals': chemicals,
          'manpower': manpower,
          'submittedTo': submittedTo,
          'signature': signature,
          'contractId': contractId,
        }),
      );

      if (response.statusCode == 201 || response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['error'] ?? 'Failed to submit coach form');
      }
    } catch (e) {
      throw Exception('Error submitting coach form: $e');
    }
  }

  static Future<List<Map<String, dynamic>>> getSupervisors({String? module}) async {
    try {
      final token = await getToken();
      final params = <String, String>{};
      if (module != null) params['module'] = module;
      final uri = Uri.parse('$baseUrl/api/users/railway-supervisors').replace(queryParameters: params.isNotEmpty ? params : null);
      final response = await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List supervisors = data['supervisors'] ?? [];

        return supervisors.cast<Map<String, dynamic>>();
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['error'] ?? 'Failed to fetch supervisors');
      }
    } catch (e) {
      throw Exception('Error fetching supervisors: $e');
    }
  }

  static Future<List<Map<String, dynamic>>> getContractorSupervisors({String? stationId}) async {
    try {
      final token = await getToken();
      final params = <String, String>{};
      if (stationId != null) params['stationId'] = stationId;
      final uri = Uri.parse('$baseUrl/api/users/contractor-supervisors')
          .replace(queryParameters: params.isNotEmpty ? params : null);
      final response = await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List supervisors = data['supervisors'] ?? [];
        return supervisors.cast<Map<String, dynamic>>();
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['error'] ?? 'Failed to fetch contractor supervisors');
      }
    } catch (e) {
      throw Exception('Error fetching contractor supervisors: $e');
    }
  }

  Future<CoachFormsResponse?> getSubmittedCoachForms() async {
    try {
      final token = await getToken();
      final response = await http.get(
        Uri.parse('$baseUrl/api/coach-forms/submitted'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body);
        return CoachFormsResponse.fromJson(jsonData);
      } else {
        print('Error: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('Exception: $e');
      return null;
    }
  }

  //<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<Premises Form<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

  static Future<Map<String, dynamic>> submitPremisesForm({
    required String supervisor,
    required String location,
    required String contractId,
    required String formDateTime,
    required List<Map<String, String>> manpower,
    required Map<String, String> submittedTo,
    required Map<String, dynamic> signature,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');

      if (token == null) {
        throw Exception('No authentication token found. Please log in again.');
      }

      final url = Uri.parse('$baseUrl/api/premises-forms');

      final payload = {
        'supervisor': supervisor,
        'location': location,
        'formDateTime': formDateTime,
        'manpower': manpower,
        'contractId': contractId,
        'submittedTo': submittedTo,
        'signature': signature,
      };

      print('=== API REQUEST ===');
      print('URL: $url');
      print('Payload: ${jsonEncode(payload)}');

      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(payload),
      );

      print('Status Code: ${response.statusCode}');
      print('Response Body: ${response.body}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        print('=== SUCCESS ===');
        print('Response: $data');
        return data;
      } else {
        final errorData = jsonDecode(response.body);
        final errorMsg = errorData['message'] ?? 'Unknown error occurred';
        throw Exception(
          'Failed to submit form: $errorMsg (${response.statusCode})',
        );
      }
    } catch (e) {
      print('=== ERROR ===');
      print('Exception: $e');
      rethrow;
    }
  }

  Future<FormResponse?> getPendingPremiseForm() async {
    try {
      final token = await getToken();
      final response = await http.get(
        Uri.parse('$baseUrl/api/premises-forms'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body);
        return FormResponse.fromJson(jsonData);
      } else {
        print('Error: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('Exception: $e');
      return null;
    }
  }

  Future<FormResponse?> getSubmittedPremiseForm() async {
    try {
      final token = await getToken();
      final response = await http.get(
        Uri.parse('$baseUrl/api/premises-forms/submitted'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body);
        return FormResponse.fromJson(jsonData);
      } else {
        print('Error: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('Exception: $e');
      return null;
    }
  }

  //<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

  //Railway SIDE;

  Future<CoachFormsResponse?> getIncomingCoachForms() async {
    try {
      final token = await getToken();
      final response = await http.get(
        Uri.parse('$baseUrl/api/coach-forms'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body);
        return CoachFormsResponse.fromJson(jsonData);
      } else {
        print('Error: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('Exception: $e');
      return null;
    }
  }

  Future<CoachFormsResponse?> getScoredCoachForm() async {
    try {
      final token = await getToken();
      final response = await http.get(
        Uri.parse('$baseUrl/api/coach-forms?type=history'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body);
        return CoachFormsResponse.fromJson(jsonData);
      } else {
        print('Error: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('Exception: $e');
      return null;
    }
  }

  static Future<Map<String, dynamic>> approveManpower({
    required String formId,
  }) async {
    try {
      final token = await getToken();
      final String endpoint = "/api/coach-forms/$formId/approve-manpower";

      final Uri url = Uri.parse("$baseUrl$endpoint");

      print("Approve Manpower URL: $url");

      final response = await http.put(
        url,
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer $token",
        },
      );

      print("Response Status: ${response.statusCode}");
      print("Response Body: ${response.body}");

      if (response.statusCode == 200 || response.statusCode == 201) {
        return jsonDecode(response.body);
      } else {
        return {
          "success": false,
          "message": "Failed to approve manpower",
          "status": response.statusCode,
          "body": response.body,
        };
      }
    } catch (e) {
      return {
        "success": false,
        "message": "Error occurred",
        "error": e.toString(),
      };
    }
  }

  ////

  Future<CoachFormsResponse?> getIncomingApprovedCoachForms() async {
    try {
      final token = await getToken();
      final response = await http.get(
        Uri.parse('$baseUrl/api/coach-forms/pending/scoring'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body);
        return CoachFormsResponse.fromJson(jsonData);
      } else {
        print('Error: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('Exception: $e');
      return null;
    }
  }

  //

  static Future<Map<String, dynamic>> submitCoachScorecard({
    required String formId,
    required String workType,
    required String acwpStatus,
    required String railwaySignatureName,
    required List<Map<String, dynamic>> coachEvaluationTable,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');

      if (token == null) throw Exception('No authentication token found.');

      final url = Uri.parse('$baseUrl/api/coach-forms/$formId/scoring');

      final body = {
        "workType": workType,
        "acwpStatus": acwpStatus,
        "coachEvaluationTable": coachEvaluationTable,
        "railwaySignatureName": railwaySignatureName,
        "railwaySignatureDate": 'NA',
        "railwayRemarks": 'NA',
      };

      final response = await http.put(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(body),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200 || response.statusCode == 201) {
        return data;
      } else {
        throw Exception(data['message'] ?? 'Failed to submit scorecard');
      }
    } catch (e) {
      print('Submit Error: $e');
      rethrow;
    }
  }

  static Future<Map<String, dynamic>> saveScoringDraft({
    required String formId,
    required String workType,
    required String acwpStatus,
    required List<Map<String, dynamic>> coachEvaluationTable,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      if (token == null) throw Exception('No authentication token found.');

      final url = Uri.parse(
        '$baseUrl/api/coach-forms/$formId/scoring/draft',
      );

      final body = {
        "workType": workType,
        "acwpStatus": acwpStatus,
        "coachEvaluationTable": coachEvaluationTable,
      };

      final response = await http.put(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(body),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200 || response.statusCode == 201) {
        return data;
      } else {
        throw Exception(data['message'] ?? 'Failed to save draft');
      }
    } catch (e) {
      print('Draft Error: $e');
      rethrow;
    }
  }

  static Future<Map<String, dynamic>?> getScoringDraft({
    required String formId,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      if (token == null) throw Exception('No authentication token found.');

      final url = Uri.parse('$baseUrl/api/coach-forms/$formId');

      final response = await http.get(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data;
      } else {
        return null;
      }
    } catch (e) {
      print('Get Draft Error: $e');
      return null;
    }
  }

  Future<CoachFormsResponse?> getScoredCoachForms({
    String status = 'SCORED',
  }) async {
    try {
      final token = await getToken();

      if (token == null) {
        print('Error: No authentication token found');
        return null;
      }

      final response = await http.get(
        Uri.parse('$baseUrl/api/coach-forms?status=$status'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body);
        return CoachFormsResponse.fromJson(jsonData);
      } else if (response.statusCode == 401) {
        print('Error: Unauthorized - Token may have expired');
        return null;
      } else if (response.statusCode == 403) {
        print('Error: Forbidden - You do not have permission');
        return null;
      } else {
        print('Error: ${response.statusCode} - ${response.body}');
        return null;
      }
    } catch (e) {
      print('Exception in getScoredCoachForms: $e');
      return null;
    }
  }

  static Future<Map<String, dynamic>> acceptScoredForm({
    required String formId,
  }) async {
    try {
      final token = await getToken();
      final String endpoint = "/api/coach-forms/$formId/accept-rating";

      final Uri url = Uri.parse("$baseUrl$endpoint");

      print("Accept Scored URL: $url");

      final response = await http.put(
        url,
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer $token",
        },
      );

      print("Response Status: ${response.statusCode}");
      print("Response Body: ${response.body}");

      if (response.statusCode == 200 || response.statusCode == 201) {
        return jsonDecode(response.body);
      } else {
        return {
          "success": false,
          "message": "Failed to accept scored form",
          "status": response.statusCode,
          "body": response.body,
        };
      }
    } catch (e) {
      return {
        "success": false,
        "message": "Error occurred",
        "error": e.toString(),
      };
    }
  }

  static Future<Map<String, dynamic>> rejectCoachForm({
    required String formId,
    required String rejectRemark,
  }) async {
    try {
      final token = await getToken();
      final String endpoint = "/api/coach-forms/$formId/reject";

      final Uri url = Uri.parse("$baseUrl$endpoint");

      print("Reject Form URL: $url");

      final response = await http.put(
        url,
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer $token",
        },
        body: jsonEncode({"rejectionComments": rejectRemark}),
      );

      print("Response Status: ${response.statusCode}");
      print("Response Body: ${response.body}");

      if (response.statusCode == 200 || response.statusCode == 201) {
        return jsonDecode(response.body);
      } else {
        return {
          "success": false,
          "message": "Failed to reject coach form",
          "status": response.statusCode,
          "body": response.body,
        };
      }
    } catch (e) {
      return {
        "success": false,
        "message": "Error occurred",
        "error": e.toString(),
      };
    }
  }

  static Future<Map<String, dynamic>> rejectPremisesForm({
    required String formId,
    required String rejectRemark,
  }) async {
    try {
      final token = await getToken();
      final String endpoint = "/api/premises-forms/$formId/reject";

      final Uri url = Uri.parse("$baseUrl$endpoint");

      print("Reject Form URL: $url");

      final response = await http.put(
        url,
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer $token",
        },
        body: jsonEncode({"rejectionComments": rejectRemark}),
      );

      print("Response Status: ${response.statusCode}");
      print("Response Body: ${response.body}");

      if (response.statusCode == 200 || response.statusCode == 201) {
        return jsonDecode(response.body);
      } else {
        return {
          "success": false,
          "message": "Failed to reject coach form",
          "status": response.statusCode,
          "body": response.body,
        };
      }
    } catch (e) {
      return {
        "success": false,
        "message": "Error occurred",
        "error": e.toString(),
      };
    }
  }

  static Future<Map<String, dynamic>> resubmitPremisesForm({
    required String formId,
    required String contractorRemarks,
    required List<Map<String, String>> manpower,
    required Map<String, dynamic> resubmitSign,
  }) async {
    try {
      final token = await getToken();
      final String endpoint = "/api/premises-forms/$formId/resubmit";

      final Uri url = Uri.parse("$baseUrl$endpoint");

      print("Resubmit Form URL: $url");

      final response = await http.put(
        url,
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer $token",
        },
        body: jsonEncode({
          "contractorRemarks": contractorRemarks,
          "manpower": manpower,
          "resubmitSign": resubmitSign,
        }),
      );

      print("Response Status: ${response.statusCode}");
      print("Response Body: ${response.body}");

      if (response.statusCode == 200 || response.statusCode == 201) {
        return jsonDecode(response.body);
      } else {
        throw Exception("Failed to resubmit form: ${response.body}");
      }
    } catch (e) {
      throw Exception("Error resubmitting form: $e");
    }
  }

  static Future<Map<String, dynamic>> resubmitCoachForm({
    required String formId,
    required String contractorRemarks,
    required int coachCount,
    required List<String> machinesUsed,
    required Map<String, double> chemicals,
    required List<Map<String, String>> manpower,
    required Map<String, String> resubmitSign,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');

    if (token == null) {
      throw Exception('No token found');
    }

    final url = Uri.parse('$baseUrl/api/coach-forms/$formId/resubmit');

    final body = jsonEncode({
      'contractorRemarks': contractorRemarks,
      'coachCount': coachCount,
      'machinesUsed': machinesUsed,
      'chemicals': chemicals,
      'manpower': manpower,
      'resubmitSign': resubmitSign,
    });

    final response = await http.put(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: body,
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      return jsonDecode(response.body);
    } else {
      final error = jsonDecode(response.body);
      throw Exception(error['message'] ?? 'Failed to resubmit form');
    }
  }

  static Future<Map<String, dynamic>> approvePremisesForm({
    required String formId,
  }) async {
    try {
      final token = await getToken();
      final String endpoint = "/api/premises-forms/$formId/approve-manpower";

      final Uri url = Uri.parse("$baseUrl$endpoint");

      final response = await http.put(
        url,
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer $token",
        },
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        return jsonDecode(response.body);
      } else {
        return {
          "success": false,
          "message": "Failed to approve manpower",
          "status": response.statusCode,
          "body": response.body,
        };
      }
    } catch (e) {
      return {
        "success": false,
        "message": "Error occurred",
        "error": e.toString(),
      };
    }
  }

  Future<FormResponse?> getIncomingApprovedPremisesForms() async {
    try {
      final token = await getToken();
      final response = await http.get(
        Uri.parse('$baseUrl/api/premises-forms/pending/scoring'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body);
        if (jsonData is List) {
          return FormResponse(
            count: jsonData.length,
            forms: (jsonData as List).map((e) => FormData.fromJson(e)).toList(),
          );
        } else if (jsonData.containsKey('forms')) {
          return FormResponse.fromJson(jsonData);
        } else {
          return FormResponse(count: 1, forms: [FormData.fromJson(jsonData)]);
        }
      } else {
        print('Error: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('Exception: $e');
      return null;
    }
  }

  static Future<Map<String, dynamic>> submitPremisesScorecard({
    required String formId,
    required String railwaySignatureName,
    required String railwaySignatureDate,
    required List<Map<String, dynamic>> housekeepingItems,
    required List<Map<String, dynamic>> pitLineItems,
    required List<Map<String, dynamic>> disposalItems,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');

      if (token == null) throw Exception('No authentication token found.');

      final url = Uri.parse(
        '$baseUrl/api/premises-forms/$formId/scoring',
      );

      final body = {
        "railwaySignatureName": railwaySignatureName,
        "railwaySignatureDate": railwaySignatureDate,
        "housekeepingItems": housekeepingItems,
        "pitLineItems": pitLineItems,
        "disposalItems": disposalItems,
      };

      print('=== SUBMIT PREMISES SCORECARD REQUEST ===');
      print('URL: $url');
      print('Payload: ${jsonEncode(body)}');

      final response = await http.put(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(body),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200 || response.statusCode == 201) {
        return data;
      } else {
        throw Exception(data['message'] ?? 'Failed to submit scorecard');
      }
    } catch (e) {
      print('Submit Error: $e');
      rethrow;
    }
  }

  static Future<Map<String, dynamic>> acceptPremisesScoredForm({
    required String formId,
  }) async {
    try {
      final token = await getToken();
      final String endpoint = "/api/premises-forms/$formId/accept-rating";

      final Uri url = Uri.parse("$baseUrl$endpoint");

      final response = await http.put(
        url,
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer $token",
        },
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        return jsonDecode(response.body);
      } else {
        return {
          "success": false,
          "message": "Failed to accept scored form",
          "status": response.statusCode,
          "body": response.body,
        };
      }
    } catch (e) {
      return {
        "success": false,
        "message": "Error occurred",
        "error": e.toString(),
      };
    }
  }

  Future<FormResponse?> getScoredPremisesForm() async {
    try {
      final token = await getToken();
      final response = await http.get(
        Uri.parse('$baseUrl/api/premises-forms?type=history'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body);
        return FormResponse.fromJson(jsonData);
      } else {
        print('Error: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('Exception: $e');
      return null;
    }
  }

  ///<<<<<<<<<<<<<<<<<<<<<<<<<REPORT>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>

  static Future<dynamic> getPremisesReportData({
    required String startDate,
    required String endDate,
    required String areaType,
    String? depot,
    String? contractId,
    String? contractorId,
    String? division,
    required String zone,
  }) async {
    final token = await getToken();
    final uri = Uri.parse(
      "$baseUrl/api/reports/premises-data?"
      "areaType=$areaType&"
      "startDate=$startDate&"
      "endDate=$endDate&"
      "zone=$zone&"
      "division=$division&"
      "depot=$depot&"
      "contractorId=$contractorId&"
      "contractId=$contractId",
    );

    try {
      final response = await http.get(
        uri,
        headers: {
          "Authorization": "Bearer $token",
          "Content-Type": "application/json",
        },
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception("Failed: ${response.statusCode} - ${response.body}");
      }
    } catch (e) {
      throw Exception("Error: $e");
    }
  }

  // <<<<<<<<<<<<<<<<<<<<<<<<<<< Premises Report>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> -

  static Future<dynamic> getCoachReportData({
    String? startDate,
    String? endDate,
    String? depot,
    String? division,
    String? trainNo,
    String? contractId,
    String? coachNo,
    String? contractorId,
    String? zone,
  }) async {
    final token = await getToken();
    final uri = Uri.parse(
      "$baseUrl/api/reports/coach-data?"
      "startDate=$startDate&"
      "endDate=$endDate&"
      "zone=$zone&"
      "division=$division&"
      "depot=$depot&"
      "trainNo=$trainNo&"
      "contractorId=$contractorId&"
      "coachNo=$coachNo&"
      "contractId=$contractId",
    );

    try {
      final response = await http.get(
        uri,
        headers: {
          "Authorization": "Bearer $token",
          "Content-Type": "application/json",
        },
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception("Failed: ${response.statusCode} - ${response.body}");
      }
    } catch (e) {
      throw Exception("Error: $e");
    }
  }

  static Future<Map<String, dynamic>> getPremisesStatistics({
    required String userRole,
    required String uid,
    String? zone,
    String? division,
    String? depot,
  }) async {
    final token = await getToken();
    final uri = Uri.parse(
      "$baseUrl/api/reports/premises-statistics?"
      "userRole=$userRole&"
      "uid=$uid&"
      "zone=${zone ?? ''}&"
      "division=${division ?? ''}&"
      "depot=${depot ?? ''}",
    );

    try {
      final response = await http.get(
        uri,
        headers: {
          "Authorization": "Bearer $token",
          "Content-Type": "application/json",
        },
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception("Failed: ${response.statusCode} - ${response.body}");
      }
    } catch (e) {
      throw Exception("Error: $e");
    }
  }

  static Future<Map<String, dynamic>> getCoachStatistics({
    required String userRole,
    required String uid,
    String? zone,
    String? division,
    String? depot,
  }) async {
    final token = await getToken();
    final uri = Uri.parse(
      "$baseUrl/api/reports/coach-statistics?"
      "userRole=$userRole&"
      "uid=$uid&"
      "zone=${zone ?? ''}&"
      "division=${division ?? ''}&"
      "depot=${depot ?? ''}",
    );

    try {
      final response = await http.get(
        uri,
        headers: {
          "Authorization": "Bearer $token",
          "Content-Type": "application/json",
        },
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception("Failed: ${response.statusCode} - ${response.body}");
      }
    } catch (e) {
      throw Exception("Error: $e");
    }
  }

  static Future<Map<String, dynamic>> getDashboardStats({
    String? zone,
    String? division,
    String? startDate,
    String? endDate,
  }) async {
    try {
      final token = await getToken();
      if (token == null) {
        throw Exception('AUTH_ERROR');
      }

      final queryParams = <String, String>{};
      if (zone != null && zone.isNotEmpty) queryParams['zone'] = zone;
      if (division != null && division.isNotEmpty)
        queryParams['division'] = division;
      if (startDate != null && startDate.isNotEmpty)
        queryParams['startDate'] = startDate;
      if (endDate != null && endDate.isNotEmpty)
        queryParams['endDate'] = endDate;

      final uri = Uri.parse(
        "$baseUrl/api/dashboard/stats${queryParams.isNotEmpty ? '?' : ''}${queryParams.entries.map((e) => '${e.key}=${e.value}').join('&')}",
      );

      final response = await _handleRequest(
        () => http.get(
          uri,
          headers: {
            "Authorization": "Bearer $token",
            "Content-Type": "application/json",
          },
        ),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        await clearToken();
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
      print('Error in getDashboardStats: $e');
      throw Exception(ApiErrorHandler.getErrorMessage(e, null));
    }
  }

  static Future<Map<String, dynamic>> getUserStats({
    String? zone,
    String? division,
    String? depot,
  }) async {
    try {
      final token = await getToken();
      if (token == null) {
        throw Exception('AUTH_ERROR');
      }

      final queryParams = <String, String>{};
      if (zone != null && zone.isNotEmpty) queryParams['selectedZone'] = zone;
      if (division != null && division.isNotEmpty)
        queryParams['selectedDivision'] = division;
      if (depot != null && depot.isNotEmpty)
        queryParams['selectedDepot'] = depot;

      final uri = Uri.parse(
        "$baseUrl/api/dashboard/user-stats${queryParams.isNotEmpty ? '?' : ''}${queryParams.entries.map((e) => '${e.key}=${e.value}').join('&')}",
      );

      final response = await _handleRequest(
        () => http.get(
          uri,
          headers: {
            "Authorization": "Bearer $token",
            "Content-Type": "application/json",
          },
        ),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        await clearToken();
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
      print('Error in getUserStats: $e');
      throw Exception(ApiErrorHandler.getErrorMessage(e, null));
    }
  }

  static Future<Map<String, dynamic>> getTrainStats({
    String? zone,
    String? division,
    String? depot,
  }) async {
    try {
      final token = await getToken();
      if (token == null) {
        throw Exception('AUTH_ERROR');
      }

      final queryParams = <String, String>{};
      if (zone != null && zone.isNotEmpty) queryParams['selectedZone'] = zone;
      if (division != null && division.isNotEmpty)
        queryParams['selectedDivision'] = division;
      if (depot != null && depot.isNotEmpty)
        queryParams['selectedDepot'] = depot;

      final uri = Uri.parse(
        "$baseUrl/api/dashboard/train-stats${queryParams.isNotEmpty ? '?' : ''}${queryParams.entries.map((e) => '${e.key}=${e.value}').join('&')}",
      );

      final response = await _handleRequest(
        () => http.get(
          uri,
          headers: {
            "Authorization": "Bearer $token",
            "Content-Type": "application/json",
          },
        ),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        await clearToken();
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
      print('Error in getTrainStats: $e');
      throw Exception(ApiErrorHandler.getErrorMessage(e, null));
    }
  }

  static Future<Map<String, dynamic>> getFormsStats({
    required String formType,
    String? zone,
    String? division,
    int? days,
    String? entityId,
  }) async {
    try {
      final token = await getToken();
      if (token == null) {
        throw Exception('AUTH_ERROR');
      }

      final queryParams = <String, String>{'formType': formType};
      if (zone != null && zone.isNotEmpty) queryParams['zone'] = zone;
      if (division != null && division.isNotEmpty)
        queryParams['division'] = division;
      if (days != null) queryParams['days'] = days.toString();
      if (entityId != null && entityId.isNotEmpty)
        queryParams['entityId'] = entityId;

      final uri = Uri.parse(
        "$baseUrl/api/all-forms/stats?${queryParams.entries.map((e) => '${e.key}=${e.value}').join('&')}",
      );

      final response = await _handleRequest(
        () => http.get(
          uri,
          headers: {
            "Authorization": "Bearer $token",
            "Content-Type": "application/json",
          },
        ),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        await clearToken();
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
      print('Error in getFormsStats: $e');
      throw Exception(ApiErrorHandler.getErrorMessage(e, null));
    }
  }

  static Future<Map<String, dynamic>> getCoachStats() async {
    try {
      final token = await getToken();
      if (token == null) {
        throw Exception('AUTH_ERROR');
      }

      final response = await _handleRequest(
        () => http.get(
          Uri.parse('$baseUrl/api/reports/coach-stats'),
          headers: {
            "Authorization": "Bearer $token",
            "Content-Type": "application/json",
          },
        ),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        await clearToken();
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
      print('Error in getCoachStats: $e');
      throw Exception(ApiErrorHandler.getErrorMessage(e, null));
    }
  }

  static Future<Map<String, dynamic>> getPremisesStats() async {
    try {
      final token = await getToken();
      if (token == null) {
        throw Exception('AUTH_ERROR');
      }

      final response = await _handleRequest(
        () => http.get(
          Uri.parse('$baseUrl/api/reports/premises-stats'),
          headers: {
            "Authorization": "Bearer $token",
            "Content-Type": "application/json",
          },
        ),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        await clearToken();
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
      print('Error in getPremisesStats: $e');
      throw Exception(ApiErrorHandler.getErrorMessage(e, null));
    }
  }

  // cts - apis

  static Future<List<TrainModel>> getCTSTrains() async {
    try {
      final token = await getToken();
      final response = await http.get(
        Uri.parse('$baseUrl/api/trains?applicableFor=CTS&status=active'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List trains = data['trains'] ?? [];

        return trains
            .map<TrainModel>(
              (t) => TrainModel.fromJson(Map<String, dynamic>.from(t)),
            )
            .toList();
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['error'] ?? 'Failed to fetch active trains');
      }
    } catch (e) {
      throw Exception('Error fetching active trains: $e');
    }
  }

  static Future<Map<String, dynamic>> submitCTSForm({
    required String trainId,
    required String contractId,
    required String formDateTime,
    required String platform,
    required String actArrival,
    required String actDeparture,
    required String workStart,
    required String workEnd,
    required String allowedWindow,
    required String lateYN,
    required int coachesInRake,
    required int coachesAttended,
    required List<Map<String, String>> attendanceStaff,
    required bool garbageDisposed,
    required String nominatedLocation,
    required int occupiedToilets,
    required String notes,
    required Map<String, String> submittedTo,
    required Map<String, String> signature,
  }) async {
    try {
      final token = await getToken();

      final response = await http.post(
        Uri.parse('$baseUrl/api/cts-forms'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'trainId': trainId,
          'contractId': contractId,
          'formDateTime': formDateTime,
          'platform': platform,
          'actArrival': actArrival,
          'actDeparture': actDeparture,
          'workStart': workStart,
          'workEnd': workEnd,
          'allowedWindow': allowedWindow,
          'lateYN': lateYN,
          'coachesInRake': coachesInRake,
          'coachesAttended': coachesAttended,
          'attendanceStaff': attendanceStaff,
          'garbageDisposed': garbageDisposed,
          'nominatedLocation': nominatedLocation,
          'occupiedToilets': occupiedToilets,
          'notes': notes,
          'submittedTo': submittedTo,
          'signature': signature,
        }),
      );

      if (response.statusCode == 201 || response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['error'] ?? 'Failed to submit CTS form');
      }
    } catch (e) {
      throw Exception('Error submitting CTS form: $e');
    }
  }

  Future<CTSFormsResponse?> getSubmittedCTSForms() async {
    try {
      final token = await getToken();
      final response = await http.get(
        Uri.parse('$baseUrl/api/cts-forms'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body);
        return CTSFormsResponse.fromJson(jsonData);
      } else {
        print('Error: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('Exception: $e');
      return null;
    }
  }

  Future<CTSFormsResponse?> getPendingCTSForms() async {
    try {
      final token = await getToken();
      final response = await http.get(
        Uri.parse('$baseUrl/api/cts-forms?type=history'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body);
        return CTSFormsResponse.fromJson(jsonData);
      } else {
        print('Error: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('Exception: $e');
      return null;
    }
  }

  static Future<Map<String, dynamic>> approveCTSForm({
    required String formId,
  }) async {
    try {
      final token = await getToken();
      final String endpoint = "/api/cts-forms/$formId/approve-manpower";

      final Uri url = Uri.parse("$baseUrl$endpoint");

      final response = await http.post(
        url,
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer $token",
        },
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        return jsonDecode(response.body);
      } else {
        return {'success': false, 'message': 'Failed to approve CTS form'};
      }
    } catch (e) {
      return {'success': false, 'message': 'Error: $e'};
    }
  }

  static Future<Map<String, dynamic>> rejectCTSForm({
    required String formId,
    required String rejectRemark,
  }) async {
    try {
      final token = await getToken();
      final String endpoint = "/api/cts-forms/$formId/reject";

      final Uri url = Uri.parse("$baseUrl$endpoint");

      final response = await http.post(
        url,
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer $token",
        },
        body: jsonEncode({"rejectionComments": rejectRemark}),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final responseData = jsonDecode(response.body);
        return {
          'success': true,
          'message': 'CTS form rejected successfully',
          'data': responseData,
        };
      } else {
        return {
          'success': false,
          'message': 'Failed to reject CTS form: ${response.body}',
        };
      }
    } catch (e) {
      return {'success': false, 'message': 'Error rejecting CTS form: $e'};
    }
  }

  static Future<Map<String, dynamic>> submitCTSScorecard({
    required String formId,
    required Map<String, dynamic> inspectionHeader,
    required List<Map<String, dynamic>> coachEvaluationTable,
    required List<String> machinesUsed,
    required List<Map<String, dynamic>> chemicals,
    required String railwaySignatureName,
    required String railwaySignatureDate,
  }) async {
    try {
      final token = await getToken();
      final String endpoint = "/api/cts-forms/$formId/submit-scoring";

      final Uri url = Uri.parse("$baseUrl$endpoint");

      final requestBody = {
        "inspectionHeader": inspectionHeader,
        "coachEvaluationTable": coachEvaluationTable,
        "machinesUsed": machinesUsed,
        "chemicals": chemicals,
        "railwaySignatureName": railwaySignatureName,
        "railwaySignatureDate": railwaySignatureDate,
      };

      final response = await http.post(
        url,
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer $token",
        },
        body: jsonEncode(requestBody),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final responseData = jsonDecode(response.body);
        return {
          'success': true,
          'message': 'CTS scorecard submitted successfully',
          'data': responseData,
        };
      } else {
        return {
          'success': false,
          'message': 'Failed to submit CTS scorecard: ${response.body}',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Error submitting CTS scorecard: $e',
      };
    }
  }

  static Future<Map<String, dynamic>> acceptCTSScoredForm({
    required String formId,
  }) async {
    try {
      final token = await getToken();
      final String endpoint = "/api/cts-forms/$formId/accept-rating";

      final Uri url = Uri.parse("$baseUrl$endpoint");

      final response = await http.post(
        url,
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer $token",
        },
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        return jsonDecode(response.body);
      } else {
        return {
          "success": false,
          "message": "Failed to accept CTS scored form",
          "status": response.statusCode,
          "body": response.body,
        };
      }
    } catch (e) {
      return {
        "success": false,
        "message": "Error occurred",
        "error": e.toString(),
      };
    }
  }

  static Future<Map<String, dynamic>> resubmitCTSForm({
    required String formId,
    required String contractorRemarks,
    required String trainId,
    required String trainNumber,
    required String trainName,
    required String formDateTime,
    required String actArrival,
    required String actDeparture,
    required String workStart,
    required String workEnd,
    required String platform,
    required String allowedWindow,
    required String lateYN,
    required int coachesInRake,
    required int coachesAttended,
    required List<Map<String, String>> attendanceStaff,
    required bool garbageDisposed,
    required String nominatedLocation,
    required int occupiedToilets,
    required String notes,
    required Map<String, String> resubmitSign,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');

    if (token == null) {
      throw Exception('No token found');
    }

    final url = Uri.parse('$baseUrl/api/cts-forms/$formId/resubmit');

    final body = jsonEncode({
      'contractorRemarks': contractorRemarks,
      'trainId': trainId,
      'trainNumber': trainNumber,
      'trainName': trainName,
      'formDateTime': formDateTime,
      'actArrival': actArrival,
      'actDeparture': actDeparture,
      'workStart': workStart,
      'workEnd': workEnd,
      'platform': platform,
      'allowedWindow': allowedWindow,
      'lateYN': lateYN,
      'coachesInRake': coachesInRake,
      'coachesAttended': coachesAttended,
      'attendanceStaff': attendanceStaff,
      'garbageDisposed': garbageDisposed,
      'nominatedLocation': nominatedLocation,
      'occupiedToilets': occupiedToilets,
      'notes': notes,
      'resubmitSign': resubmitSign,
    });

    final response = await http.put(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: body,
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      return jsonDecode(response.body);
    } else {
      final error = jsonDecode(response.body);
      throw Exception(error['message'] ?? 'Failed to resubmit CTS form');
    }
  }

  static Future<Map<String, dynamic>> getCTSStatistics({
    required String userRole,
    required String uid,
    String? zone,
    String? division,
    String? depot,
  }) async {
    final token = await getToken();
    final uri = Uri.parse(
      "$baseUrl/api/reports/cts-stats?"
      "userRole=$userRole&"
      "uid=$uid&"
      "zone=${zone ?? ''}&"
      "division=${division ?? ''}&"
      "depot=${depot ?? ''}",
    );

    try {
      final response = await http.get(
        uri,
        headers: {
          "Authorization": "Bearer $token",
          "Content-Type": "application/json",
        },
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception("Failed: ${response.statusCode} - ${response.body}");
      }
    } catch (e) {
      throw Exception("Error: $e");
    }
  }

  static Future<dynamic> getCTSReportData({
    String? startDate,
    String? endDate,
    String? depot,
    String? division,
    String? trainNo,
    String? contractId,
    String? contractorId,
    String? zone,
  }) async {
    final token = await getToken();
    final uri = Uri.parse(
      "$baseUrl/api/reports/cts-data?"
      "startDate=$startDate&"
      "endDate=$endDate&"
      "zone=$zone&"
      "division=$division&"
      "depot=$depot&"
      "trainNo=$trainNo&"
      "contractorId=$contractorId&"
      "contractId=$contractId",
    );

    try {
      final response = await http.get(
        uri,
        headers: {
          "Authorization": "Bearer $token",
          "Content-Type": "application/json",
        },
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception("Failed: ${response.statusCode} - ${response.body}");
      }
    } catch (e) {
      throw Exception("Error: $e");
    }
  }

  static Future<Map<String, dynamic>> getCTSStats() async {
    try {
      final token = await getToken();
      if (token == null) {
        throw Exception('AUTH_ERROR');
      }

      final response = await _handleRequest(
        () => http.get(
          Uri.parse('$baseUrl/api/reports/cts-stats'),
          headers: {
            "Authorization": "Bearer $token",
            "Content-Type": "application/json",
          },
        ),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        await clearToken();
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
      print('Error in getCTSStats: $e');
      throw Exception(ApiErrorHandler.getErrorMessage(e, null));
    }
  }

  //<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<< Billing APIs >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>

  static Future<Map<String, dynamic>> saveBillingConfig({
    required String contractId,
    required String contractNumber,
    required String entityId,
    required String entityName,
    required String division,
    required String zone,
    required double contractValue,
    required String billingCycle,
    required List<String> serviceTypes,
    required double coachWeightage,
    required double premiseWeightage,
    required double obhsWeightage,
    required double passengerFeedbackWeightage,
    required double aiVerificationWeightage,
    required double penaltyScore90Plus,
    required double penaltyScore80To89,
    required double penaltyScore70To79,
    required double penaltyScoreBelow70,
    required double manpowerShortagePenalty,
    required double machineShortagePenalty,
    required double missedObhsComplaintPenalty,
    required double lateTaskCompletionPenalty,
    required double nonCompliancePenalty,
  }) async {
    try {
      final token = await getToken();
      final response = await http.post(
        Uri.parse('$baseUrl/api/billing/config'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'contractId': contractId,
          'contractNumber': contractNumber,
          'entityId': entityId,
          'entityName': entityName,
          'division': division,
          'zone': zone,
          'contractValue': contractValue,
          'billingCycle': billingCycle,
          'serviceTypes': serviceTypes,
          'coachWeightage': coachWeightage,
          'premiseWeightage': premiseWeightage,
          'obhsWeightage': obhsWeightage,
          'passengerFeedbackWeightage': passengerFeedbackWeightage,
          'aiVerificationWeightage': aiVerificationWeightage,
          'penaltyScore90Plus': penaltyScore90Plus,
          'penaltyScore80To89': penaltyScore80To89,
          'penaltyScore70To79': penaltyScore70To79,
          'penaltyScoreBelow70': penaltyScoreBelow70,
          'manpowerShortagePenalty': manpowerShortagePenalty,
          'machineShortagePenalty': machineShortagePenalty,
          'missedObhsComplaintPenalty': missedObhsComplaintPenalty,
          'lateTaskCompletionPenalty': lateTaskCompletionPenalty,
          'nonCompliancePenalty': nonCompliancePenalty,
        }),
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        return jsonDecode(response.body);
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['error'] ?? 'Failed to save billing config');
      }
    } catch (e) {
      throw Exception('Error saving billing config: $e');
    }
  }

  static Future<ContractBillingRule?> getBillingConfig(String contractId) async {
    try {
      final token = await getToken();
      final response = await http.get(
        Uri.parse('$baseUrl/api/billing/config/$contractId'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['config'] != null) {
          return ContractBillingRule.fromJson(data['config']);
        }
        return null;
      } else if (response.statusCode == 404) {
        return null;
      } else {
        throw Exception('Failed to get billing config');
      }
    } catch (e) {
      throw Exception('Error getting billing config: $e');
    }
  }

  static Future<List<ContractBillingRule>> getAllBillingConfigs() async {
    try {
      final token = await getToken();
      final response = await http.get(
        Uri.parse('$baseUrl/api/billing/config'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List configs = data['configs'] ?? [];
        return configs.map((e) => ContractBillingRule.fromJson(e)).toList();
      } else {
        throw Exception('Failed to fetch billing configs');
      }
    } catch (e) {
      throw Exception('Error fetching billing configs: $e');
    }
  }

  static Future<Map<String, dynamic>> generateBill({
    required String contractId,
    required int month,
    required int year,
    required double overallScore,
    required Map<String, dynamic>? scoreBreakdown,
    required int machineShortageCount,
    required int manpowerShortageCount,
    required int missedObhsCount,
    required double otherPenalties,
  }) async {
    try {
      final token = await getToken();
      final response = await http.post(
        Uri.parse('$baseUrl/api/billing/generate'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'contractId': contractId,
          'month': month,
          'year': year,
          'overallScore': overallScore,
          'scoreBreakdown': scoreBreakdown,
          'machineShortageCount': machineShortageCount,
          'manpowerShortageCount': manpowerShortageCount,
          'missedObhsCount': missedObhsCount,
          'otherPenalties': otherPenalties,
        }),
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        return jsonDecode(response.body);
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['error'] ?? 'Failed to generate bill');
      }
    } catch (e) {
      throw Exception('Error generating bill: $e');
    }
  }

  static Future<List<BillingReport>> getBillingReports({
    String? status,
    String? contractId,
    String? entityId,
    String? division,
    String? zone,
    int? month,
    int? year,
  }) async {
    try {
      final token = await getToken();
      final params = <String, String>{};
      if (status != null) params['status'] = status;
      if (contractId != null) params['contractId'] = contractId;
      if (entityId != null) params['entityId'] = entityId;
      if (division != null) params['division'] = division;
      if (zone != null) params['zone'] = zone;
      if (month != null) params['month'] = month.toString();
      if (year != null) params['year'] = year.toString();
      final uri = Uri.parse('$baseUrl/api/billing/reports').replace(queryParameters: params.isNotEmpty ? params : null);
      final response = await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List reports = data['reports'] ?? [];
        return reports.map((e) => BillingReport.fromJson(e)).toList();
      } else {
        throw Exception('Failed to fetch billing reports');
      }
    } catch (e) {
      throw Exception('Error fetching billing reports: $e');
    }
  }

  static Future<BillingReport?> getBillingReportDetail(String uid) async {
    try {
      final token = await getToken();
      final response = await http.get(
        Uri.parse('$baseUrl/api/billing/reports/$uid'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return BillingReport.fromJson(data['report']);
      } else {
        throw Exception('Failed to fetch billing report');
      }
    } catch (e) {
      throw Exception('Error fetching billing report: $e');
    }
  }

  static Future<Map<String, dynamic>> approveBill(String uid) async {
    try {
      final token = await getToken();
      final response = await http.post(
        Uri.parse('$baseUrl/api/billing/approve/$uid'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['error'] ?? 'Failed to approve bill');
      }
    } catch (e) {
      throw Exception('Error approving bill: $e');
    }
  }

  static Future<Map<String, dynamic>> rejectBill(String uid, {required String reason}) async {
    try {
      final token = await getToken();
      final response = await http.post(
        Uri.parse('$baseUrl/api/billing/reject/$uid'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'reason': reason}),
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['error'] ?? 'Failed to reject bill');
      }
    } catch (e) {
      throw Exception('Error rejecting bill: $e');
    }
  }

  static Future<BillingDashboardSummary> getBillingDashboard() async {
    try {
      final token = await getToken();
      final response = await http.get(
        Uri.parse('$baseUrl/api/billing/dashboard'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return BillingDashboardSummary.fromJson(data);
      } else {
        throw Exception('Failed to fetch billing dashboard');
      }
    } catch (e) {
      throw Exception('Error fetching billing dashboard: $e');
    }
  }

  static Future<Map<String, dynamic>> generateInvoice(String uid) async {
    try {
      final token = await getToken();
      final response = await http.post(
        Uri.parse('$baseUrl/api/billing/generate-invoice/$uid'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['error'] ?? 'Failed to generate invoice');
      }
    } catch (e) {
      throw Exception('Error generating invoice: $e');
    }
  }

  static Future<Map<String, dynamic>> getContractorBillingData() async {
    try {
      final token = await getToken();
      final response = await http.get(
        Uri.parse('$baseUrl/api/billing/contractor'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Failed to fetch contractor billing data');
      }
    } catch (e) {
      throw Exception('Error fetching contractor billing data: $e');
    }
  }

  static Future<Map<String, dynamic>> getSupervisorBillingData() async {
    try {
      final token = await getToken();
      final response = await http.get(
        Uri.parse('$baseUrl/api/billing/supervisor'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Failed to fetch supervisor billing data');
      }
    } catch (e) {
      throw Exception('Error fetching supervisor billing data: $e');
    }
  }

  //<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<< Notification APIs >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
  static Future<List<Map<String, dynamic>>> getNotifications({bool all = false}) async {
    try {
      final token = await getToken();
      final response = await http.get(
        Uri.parse('$baseUrl/api/notifications${all ? '?all=true' : ''}'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return List<Map<String, dynamic>>.from(data['notifications'] ?? []);
      } else {
        throw Exception('Failed to fetch notifications');
      }
    } catch (e) {
      throw Exception('Error fetching notifications: $e');
    }
  }

  static Future<void> markNotificationRead(String uid) async {
    try {
      final token = await getToken();
      await http.post(
        Uri.parse('$baseUrl/api/notifications/$uid/read'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
    } catch (e) {
      throw Exception('Error marking notification read: $e');
    }
  }

  static Future<void> markAllNotificationsRead() async {
    try {
      final token = await getToken();
      await http.post(
        Uri.parse('$baseUrl/api/notifications/read-all'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
    } catch (e) {
      throw Exception('Error marking all notifications read: $e');
    }
  }

  static Future<int> getUnreadNotificationCount() async {
    try {
      final token = await getToken();
      final response = await http.get(
        Uri.parse('$baseUrl/api/notifications/unread-count'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['count'] ?? 0;
      }
      return 0;
    } catch (e) {
      return 0;
    }
  }

  //<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<< Cleaning Form APIs >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
  static Future<Map<String, dynamic>> createCleaningForm(Map<String, dynamic> formData) async {
    try {
      final token = await getToken();
      final response = await http.post(
        Uri.parse('$baseUrl/api/cleaning-forms'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
        body: jsonEncode(formData),
      );
      if (response.statusCode == 201) return jsonDecode(response.body);
      throw Exception(jsonDecode(response.body)['error'] ?? 'Failed to create form');
    } catch (e) {
      throw Exception('Error creating cleaning form: $e');
    }
  }

  static Future<void> saveCleaningFormDraft(String uid, Map<String, dynamic> formData) async {
    try {
      final token = await getToken();
      await http.put(
        Uri.parse('$baseUrl/api/cleaning-forms/$uid/draft'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
        body: jsonEncode(formData),
      );
    } catch (e) {
      throw Exception('Error saving draft: $e');
    }
  }

  static Future<void> submitCleaningForm(String uid) async {
    try {
      final token = await getToken();
      final response = await http.put(
        Uri.parse('$baseUrl/api/cleaning-forms/$uid/submit'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
      );
      if (response.statusCode != 200) throw Exception(jsonDecode(response.body)['error'] ?? 'Failed to submit');
    } catch (e) {
      throw Exception('Error submitting form: $e');
    }
  }

  static Future<void> approveCleaningForm(String uid) async {
    try {
      final token = await getToken();
      final response = await http.put(
        Uri.parse('$baseUrl/api/cleaning-forms/$uid/approve'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
      );
      if (response.statusCode != 200) throw Exception(jsonDecode(response.body)['error'] ?? 'Failed to approve');
    } catch (e) {
      throw Exception('Error approving form: $e');
    }
  }

  static Future<void> rejectCleaningForm(String uid, {String reason = 'No reason provided'}) async {
    try {
      final token = await getToken();
      final response = await http.put(
        Uri.parse('$baseUrl/api/cleaning-forms/$uid/reject'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
        body: jsonEncode({'reason': reason}),
      );
      if (response.statusCode != 200) throw Exception(jsonDecode(response.body)['error'] ?? 'Failed to reject');
    } catch (e) {
      throw Exception('Error rejecting form: $e');
    }
  }

  static Future<Map<String, dynamic>> scoreCleaningForm(String uid, {required double totalScore, double maxTotalScore = 100, String? remarks, String? grade, List<Map<String, dynamic>>? criteria}) async {
    try {
      final token = await getToken();
      final response = await http.put(
        Uri.parse('$baseUrl/api/cleaning-forms/$uid/score'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
        body: jsonEncode({
          'totalScore': totalScore,
          'maxTotalScore': maxTotalScore,
          'remarks': remarks ?? '',
          'grade': grade ?? '',
          'scoringData': {'criteria': criteria ?? [], 'totalScore': totalScore, 'maxTotalScore': maxTotalScore, 'remarks': remarks ?? '', 'grade': grade ?? ''},
        }),
      );
      if (response.statusCode == 200) return jsonDecode(response.body);
      throw Exception(jsonDecode(response.body)['error'] ?? 'Failed to score');
    } catch (e) {
      throw Exception('Error scoring form: $e');
    }
  }

  static Future<void> acknowledgeCleaningForm(String uid) async {
    try {
      final token = await getToken();
      await http.put(
        Uri.parse('$baseUrl/api/cleaning-forms/$uid/acknowledge'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
      );
    } catch (e) {
      throw Exception('Error acknowledging form: $e');
    }
  }

  static Future<void> autoApproveCleaningForm(String uid) async {
    try {
      final token = await getToken();
      await http.put(
        Uri.parse('$baseUrl/api/cleaning-forms/$uid/auto-approve'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
      );
    } catch (e) {
      throw Exception('Error auto-approving form: $e');
    }
  }

  static Future<void> lockCleaningForm(String uid) async {
    try {
      final token = await getToken();
      await http.put(
        Uri.parse('$baseUrl/api/cleaning-forms/$uid/lock'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
      );
    } catch (e) {
      throw Exception('Error locking form: $e');
    }
  }

  static Future<Map<String, dynamic>> getCleaningFormDetail(String uid) async {
    try {
      final token = await getToken();
      final response = await http.get(
        Uri.parse('$baseUrl/api/cleaning-forms/$uid'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
      );
      if (response.statusCode == 200) return jsonDecode(response.body);
      throw Exception('Failed to fetch form details');
    } catch (e) {
      throw Exception('Error fetching form details: $e');
    }
  }

  static Future<Map<String, dynamic>> getCleaningFormReport(String uid) async {
    try {
      final token = await getToken();
      final response = await http.get(
        Uri.parse('$baseUrl/api/cleaning-forms/report/$uid'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
      );
      if (response.statusCode == 200) return jsonDecode(response.body);
      throw Exception('Failed to fetch report');
    } catch (e) {
      throw Exception('Error fetching report: $e');
    }
  }

  static Future<List<CleaningForm>> getCleaningForms({String? status, String? formType, String? contractId, String? division, String? depot}) async {
    try {
      final token = await getToken();
      final params = <String, String>{};
      if (status != null) params['status'] = status;
      if (formType != null) params['formType'] = formType;
      if (contractId != null) params['contractId'] = contractId;
      if (division != null) params['division'] = division;
      if (depot != null) params['depot'] = depot;
      final uri = Uri.parse('$baseUrl/api/cleaning-forms').replace(queryParameters: params.isNotEmpty ? params : null);
      final response = await http.get(uri, headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'});
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return (data['forms'] as List).map((f) => CleaningForm.fromJson(f)).toList();
      }
      throw Exception('Failed to fetch forms');
    } catch (e) {
      throw Exception('Error fetching forms: $e');
    }
  }

  static Future<CleaningDashboardSummary> getCleaningFormDashboard() async {
    try {
      final token = await getToken();
      final response = await http.get(
        Uri.parse('$baseUrl/api/cleaning-forms/dashboard/data'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        // Backend returns { count, forms } — compute summary stats locally
        final formsList = (data['forms'] as List? ?? [])
            .map((f) => CleaningForm.fromJson(f as Map<String, dynamic>))
            .toList();
        int draftForms = 0, submittedForms = 0, approvedForms = 0,
            rejectedForms = 0, scoredForms = 0, lockedForms = 0;
        double totalScore = 0;
        int scoredCount = 0;
        int totalManpower = 0, totalMachine = 0;
        for (final f in formsList) {
          switch (f.status) {
            case CleaningFormStatus.draft: draftForms++; break;
            case CleaningFormStatus.submitted: submittedForms++; break;
            case CleaningFormStatus.approved:
            case CleaningFormStatus.scoringInProgress:
            case CleaningFormStatus.contractorApproved:
            case CleaningFormStatus.autoApproved: approvedForms++; break;
            case CleaningFormStatus.rejected: rejectedForms++; break;
            case CleaningFormStatus.scored: scoredForms++; break;
            case CleaningFormStatus.locked: lockedForms++; break;
          }
          if (f.score != null) { totalScore += f.score!; scoredCount++; }
          totalManpower += f.manpowerCount;
          totalMachine += f.machineCount;
        }
        return CleaningDashboardSummary(
          draftForms: draftForms,
          submittedForms: submittedForms,
          approvedForms: approvedForms,
          rejectedForms: rejectedForms,
          scoredForms: scoredForms,
          lockedForms: lockedForms,
          pendingReview: submittedForms,
          scoringPending: approvedForms,
          averageScore: scoredCount > 0 ? totalScore / scoredCount : 0,
          totalManpower: totalManpower.toDouble(),
          totalMachine: totalMachine.toDouble(),
        );
      }
      throw Exception('Failed to fetch dashboard');
    } catch (e) {
      throw Exception('Error fetching dashboard: $e');
    }
  }

  //<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<< Station Management APIs >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>

  static Future<Map<String, dynamic>> createStation(Map<String, dynamic> data) async {
    try {
      final token = await getToken();
      final response = await http.post(
        Uri.parse('$baseUrl/api/stations'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
        body: jsonEncode(data),
      );
      if (response.statusCode == 200 || response.statusCode == 201) return jsonDecode(response.body);
      final errData = jsonDecode(response.body);
      throw Exception(errData['error'] ?? 'Failed to create station');
    } catch (e) {
      throw Exception('Error creating station: $e');
    }
  }

  static Future<Map<String, dynamic>> updateStation(String uid, Map<String, dynamic> data) async {
    try {
      final token = await getToken();
      final response = await http.put(
        Uri.parse('$baseUrl/api/stations/$uid'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
        body: jsonEncode(data),
      );
      if (response.statusCode == 200) return jsonDecode(response.body);
      throw Exception('Failed to update station');
    } catch (e) {
      throw Exception('Error updating station: $e');
    }
  }

  static Future<List<Station>> getStations({String? zone, String? division, String? category, bool? active, String? entityId}) async {
    try {
      final token = await getToken();
      final params = <String, String>{};
      if (zone != null) params['zone'] = zone;
      if (division != null) params['division'] = division;
      if (category != null) params['category'] = category;
      if (active != null) params['active'] = active.toString();
      if (entityId != null) params['entityId'] = entityId;
      final uri = Uri.parse('$baseUrl/api/stations').replace(queryParameters: params.isNotEmpty ? params : null);
      final response = await http.get(uri, headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'});
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final all = (data['stations'] as List).map((s) => Station.fromJson(s)).toList();
        // Deduplicate by uid to prevent Flutter dropdown assertion errors
        final seenIds = <String>{};
        return all.where((s) {
          if (s.uid == null || s.uid!.isEmpty) return false;
          return seenIds.add(s.uid!);
        }).toList();
      }
      throw Exception('Failed to fetch stations');
    } catch (e) {
      throw Exception('Error fetching stations: $e');
    }
  }

  static Future<Station> getStationById(String stationUid) async {
    try {
      final token = await getToken();
      final response = await http.get(
        Uri.parse('$baseUrl/api/stations/$stationUid'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final payload = Map<String, dynamic>.from(data);
        payload['uid'] = payload['uid'] ?? payload['id'];
        return Station.fromJson(payload);
      }
      throw Exception('Failed to fetch station');
    } catch (e) {
      throw Exception('Error fetching station: $e');
    }
  }

  static Future<Map<String, dynamic>> createStationArea(Map<String, dynamic> data) async {
    try {
      final token = await getToken();
      final response = await http.post(
        Uri.parse('$baseUrl/api/station-area/create'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
        body: jsonEncode(data),
      );
      if (response.statusCode == 200 || response.statusCode == 201) return jsonDecode(response.body);
      throw Exception('Failed to create station area');
    } catch (e) {
      throw Exception('Error creating station area: $e');
    }
  }

  static Future<List<StationArea>> getStationAreas(String stationId) async {
    try {
      final token = await getToken();
      final response = await http.get(
        Uri.parse('$baseUrl/api/station-area/list/$stationId'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final all = (data['areas'] as List).map((a) => StationArea.fromJson(a)).toList();
        // Deduplicate by uid to prevent Flutter dropdown assertion errors
        final seenIds = <String>{};
        return all.where((a) {
          if (a.uid == null || a.uid!.isEmpty) return false;
          return seenIds.add(a.uid!);
        }).toList();
      }
      throw Exception('Failed to fetch station areas');
    } catch (e) {
      throw Exception('Error fetching station areas: $e');
    }
  }

  static Future<Map<String, dynamic>> updateStationArea(String uid, Map<String, dynamic> data) async {
    try {
      final token = await getToken();
      final response = await http.put(
        Uri.parse('$baseUrl/api/station-area/update/$uid'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
        body: jsonEncode(data),
      );
      if (response.statusCode == 200) return jsonDecode(response.body);
      throw Exception('Failed to update area');
    } catch (e) {
      throw Exception('Error updating area: $e');
    }
  }

  static Future<void> deleteStationArea(String uid) async {
    try {
      final token = await getToken();
      final response = await http.delete(
        Uri.parse('$baseUrl/api/station-area/delete/$uid'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (response.statusCode != 200 && response.statusCode != 204) throw Exception('Failed to delete area');
    } catch (e) {
      throw Exception('Error deleting area: $e');
    }
  }

  static Future<Map<String, dynamic>> createStationZone(Map<String, dynamic> data) async {
    try {
      final token = await getToken();
      final response = await http.post(
        Uri.parse('$baseUrl/api/station-zone/create'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
        body: jsonEncode(data),
      );
      if (response.statusCode == 200 || response.statusCode == 201) return jsonDecode(response.body);
      throw Exception('Failed to create station zone');
    } catch (e) {
      throw Exception('Error creating station zone: $e');
    }
  }

  static Future<List<StationZone>> getStationZones(String stationId, {String? areaId}) async {
    try {
      final token = await getToken();
      final params = <String, String>{};
      if (areaId != null) params['areaId'] = areaId;
      final uri = Uri.parse('$baseUrl/api/station-zone/list/$stationId').replace(queryParameters: params.isNotEmpty ? params : null);
      final response = await http.get(uri, headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'});
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return (data['zones'] as List).map((z) => StationZone.fromJson(z)).toList();
      }
      throw Exception('Failed to fetch station zones');
    } catch (e) {
      throw Exception('Error fetching station zones: $e');
    }
  }

  static Future<Map<String, dynamic>> mapStationContractor(Map<String, dynamic> data) async {
    try {
      final token = await getToken();
      final response = await http.post(
        Uri.parse('$baseUrl/api/station-contractor/map'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
        body: jsonEncode(data),
      );
      if (response.statusCode == 200 || response.statusCode == 201) return jsonDecode(response.body);
      throw Exception('Failed to map station contractor');
    } catch (e) {
      throw Exception('Error mapping station contractor: $e');
    }
  }

  static Future<List<StationContractorMapping>> getStationContractors(String stationId) async {
    try {
      final token = await getToken();
      final response = await http.get(
        Uri.parse('$baseUrl/api/station-contractor/list/$stationId'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return (data['contractors'] as List).map((c) => StationContractorMapping.fromJson(c)).toList();
      }
      throw Exception('Failed to fetch station contractors');
    } catch (e) {
      throw Exception('Error fetching station contractors: $e');
    }
  }

  static Future<Map<String, dynamic>> createStationSchedule(Map<String, dynamic> data) async {
    try {
      final token = await getToken();
      final response = await http.post(
        Uri.parse('$baseUrl/api/station-schedule/create'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
        body: jsonEncode(data),
      );
      if (response.statusCode == 200 || response.statusCode == 201) return jsonDecode(response.body);
      throw Exception('Failed to create station schedule');
    } catch (e) {
      throw Exception('Error creating station schedule: $e');
    }
  }

  static Future<List<StationCleaningSchedule>> getStationSchedules(String stationId) async {
    try {
      final token = await getToken();
      final response = await http.get(
        Uri.parse('$baseUrl/api/station-schedule/list/$stationId'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return (data['schedules'] as List).map((s) => StationCleaningSchedule.fromJson(s)).toList();
      }
      throw Exception('Failed to fetch station schedules');
    } catch (e) {
      throw Exception('Error fetching station schedules: $e');
    }
  }

  static Future<Map<String, dynamic>> submitShiftSummary(Map<String, dynamic> data) async {
    try {
      final token = await getToken();
      final response = await http.post(
        Uri.parse('$baseUrl/api/station-cleaning/shift-summary'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
        body: jsonEncode(data),
      );
      if (response.statusCode == 200 || response.statusCode == 201) return jsonDecode(response.body);
      throw Exception('Failed to submit shift summary');
    } catch (e) {
      throw Exception('Error submitting shift summary: $e');
    }
  }

  static Future<Map<String, dynamic>> resubmitShiftSummary(String uid, Map<String, dynamic> data) async {
    try {
      final token = await getToken();
      final response = await http.post(
        Uri.parse('$baseUrl/api/station-cleaning/shift-summaries/$uid/resubmit'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
        body: jsonEncode(data),
      );
      if (response.statusCode == 200 || response.statusCode == 201) return jsonDecode(response.body);
      throw Exception('Failed to resubmit shift summary');
    } catch (e) {
      throw Exception('Error resubmitting shift summary: $e');
    }
  }

  static Future<List<Map<String, dynamic>>> getShiftSummaries({
    String? stationId,
    String? date,
    String? shift,
    String? supervisorId,
    String? status,
  }) async {
    try {
      final token = await getToken();
      final params = <String, String>{};
      if (stationId != null) params['stationId'] = stationId;
      if (date != null) params['date'] = date;
      if (shift != null) params['shift'] = shift;
      if (supervisorId != null) params['supervisorId'] = supervisorId;
      if (status != null) params['status'] = status;
      final uri = Uri.parse('$baseUrl/api/station-cleaning/shift-summaries')
          .replace(queryParameters: params.isNotEmpty ? params : null);
      final response = await http.get(uri, headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'});
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return (data['summaries'] as List).map((s) => Map<String, dynamic>.from(s as Map)).toList();
      }
      throw Exception('Failed to fetch shift summaries');
    } catch (e) {
      throw Exception('Error fetching shift summaries: $e');
    }
  }

  static Future<Map<String, dynamic>> getShiftSummary(String uid) async {
    try {
      final token = await getToken();
      final response = await http.get(
        Uri.parse('$baseUrl/api/station-cleaning/shift-summaries/$uid'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
      );
      if (response.statusCode == 200) return jsonDecode(response.body);
      throw Exception('Failed to fetch shift summary');
    } catch (e) {
      throw Exception('Error fetching shift summary: $e');
    }
  }

  static Future<Map<String, dynamic>> approveShiftSummary(String uid) async {
    try {
      final token = await getToken();
      final response = await http.post(
        Uri.parse('$baseUrl/api/station-cleaning/shift-summaries/$uid/approve'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
      );
      if (response.statusCode == 200) return jsonDecode(response.body);
      throw Exception('Failed to approve shift summary');
    } catch (e) {
      throw Exception('Error approving shift summary: $e');
    }
  }

  static Future<Map<String, dynamic>> rejectShiftSummary(String uid, String reason) async {
    try {
      final token = await getToken();
      final response = await http.post(
        Uri.parse('$baseUrl/api/station-cleaning/shift-summaries/$uid/reject'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
        body: jsonEncode({'reason': reason}),
      );
      if (response.statusCode == 200) return jsonDecode(response.body);
      throw Exception('Failed to reject shift summary');
    } catch (e) {
      throw Exception('Error rejecting shift summary: $e');
    }
  }

  static Future<Map<String, dynamic>> generateTasksFromSchedule(Map<String, dynamic> data) async {
    try {
      final token = await getToken();
      final response = await http.post(
        Uri.parse('$baseUrl/api/station-schedule/generate-tasks'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
        body: jsonEncode(data),
      );
      if (response.statusCode == 200 || response.statusCode == 201) return jsonDecode(response.body);
      throw Exception('Failed to generate tasks from schedule');
    } catch (e) {
      throw Exception('Error generating tasks: $e');
    }
  }

  static Future<Map<String, dynamic>> createStationCleaningForm(Map<String, dynamic> data) async {
    try {
      final token = await getToken();
      final response = await http.post(
        Uri.parse('$baseUrl/api/station-cleaning-form/create'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
        body: jsonEncode(data),
      );
      if (response.statusCode == 200 || response.statusCode == 201) return jsonDecode(response.body);
      throw Exception('Failed to create station cleaning form');
    } catch (e) {
      throw Exception('Error creating station cleaning form: $e');
    }
  }

  static Future<void> submitStationCleaningForm(String uid) async {
    try {
      final token = await getToken();
      await http.post(
        Uri.parse('$baseUrl/api/station-cleaning-form/submit/$uid'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
      );
    } catch (e) {
      throw Exception('Error submitting station cleaning form: $e');
    }
  }

  static Future<void> approveStationCleaningForm(String uid) async {
    try {
      final token = await getToken();
      await http.post(
        Uri.parse('$baseUrl/api/station-cleaning-form/approve/$uid'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
      );
    } catch (e) {
      throw Exception('Error approving station cleaning form: $e');
    }
  }

  static Future<void> rejectStationCleaningForm(String uid, {String reason = ''}) async {
    try {
      final token = await getToken();
      await http.post(
        Uri.parse('$baseUrl/api/station-cleaning-form/reject/$uid'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
        body: jsonEncode({'reason': reason}),
      );
    } catch (e) {
      throw Exception('Error rejecting station cleaning form: $e');
    }
  }

  static Future<Map<String, dynamic>> scoreStationCleaningForm(String uid, {required double totalScore, String? grade, Map<String, dynamic>? scoringData}) async {
    try {
      final token = await getToken();
      final body = <String, dynamic>{'totalScore': totalScore};
      if (grade != null) body['grade'] = grade;
      if (scoringData != null) body['scoringData'] = scoringData;
      final response = await http.post(
        Uri.parse('$baseUrl/api/station-cleaning-form/score/$uid'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
        body: jsonEncode(body),
      );
      if (response.statusCode == 200) return jsonDecode(response.body);
      throw Exception('Failed to score station cleaning form');
    } catch (e) {
      throw Exception('Error scoring station cleaning form: $e');
    }
  }

  static Future<void> lockStationCleaningForm(String uid) async {
    try {
      final token = await getToken();
      await http.post(
        Uri.parse('$baseUrl/api/station-cleaning-form/lock/$uid'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
      );
    } catch (e) {
      throw Exception('Error locking station cleaning form: $e');
    }
  }

  static Future<List<StationCleaningForm>> getStationCleaningForms({String? status, String? stationId, String? areaId, String? zoneId, String? division}) async {
    try {
      final token = await getToken();
      final params = <String, String>{};
      if (status != null) params['status'] = status;
      if (stationId != null) params['stationId'] = stationId;
      if (areaId != null) params['areaId'] = areaId;
      if (zoneId != null) params['zoneId'] = zoneId;
      if (division != null) params['division'] = division;
      final uri = Uri.parse('$baseUrl/api/station-cleaning-form/list').replace(queryParameters: params.isNotEmpty ? params : null);
      final response = await http.get(uri, headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'});
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return (data['forms'] as List).map((f) => StationCleaningForm.fromJson(f)).toList();
      }
      throw Exception('Failed to fetch station cleaning forms');
    } catch (e) {
      throw Exception('Error fetching station cleaning forms: $e');
    }
  }

  static Future<StationCleaningForm?> getStationCleaningFormDetail(String uid) async {
    try {
      final token = await getToken();
      final response = await http.get(
        Uri.parse('$baseUrl/api/station-cleaning-form/details/$uid'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data == null || data['form'] == null) return null;
        return StationCleaningForm.fromJson(data['form']);
      }
      throw Exception('Failed to fetch station cleaning form detail');
    } catch (e) {
      throw Exception('Error fetching station cleaning form detail: $e');
    }
  }

  static Future<StationDashboardSummary> getStationDashboard() async {
    try {
      final token = await getToken();
      final response = await http.get(
        Uri.parse('$baseUrl/api/station-dashboard'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
      );
      if (response.statusCode == 200) return StationDashboardSummary.fromJson(jsonDecode(response.body));
      throw Exception('Failed to fetch station dashboard');
    } catch (e) {
      throw Exception('Error fetching station dashboard: $e');
    }
  }

  // ================================================================
  // == DIVISION MANAGEMENT
  // ================================================================
  static Future<List<Map<String, dynamic>>> getDivisions({String? zone}) async {
    try {
      final token = await getToken();
      final params = <String, String>{};
      if (zone != null) params['zone'] = zone;
      final uri = Uri.parse('$baseUrl/api/divisions').replace(queryParameters: params.isNotEmpty ? params : null);
      final response = await http.get(uri, headers: {'Authorization': 'Bearer $token'});
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final raw = data['divisions'];
        if (raw is! List) return [];
        return raw.map((item) {
          final map = Map<String, dynamic>.from(item as Map);
          map['divisionId'] = map['id'] ?? map['uid'] ?? map['divisionId'];
          return map;
        }).toList();
      }
      throw Exception('Failed to fetch divisions');
    } catch (e) {
      throw Exception('Error fetching divisions: $e');
    }
  }

  static Future<void> createDivision(String name, String zone, {String? code}) async {
    try {
      final token = await getToken();
      final response = await http.post(
        Uri.parse('$baseUrl/api/divisions'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
        body: jsonEncode({'name': name, 'zone': zone, 'code': code}),
      );
      if (response.statusCode != 201) {
        final err = jsonDecode(response.body);
        throw Exception(err['error'] ?? 'Failed to create division');
      }
    } catch (e) {
      throw Exception('Error creating division: $e');
    }
  }

  static Future<void> updateDivision(String id, {String? name, String? zone, String? code}) async {
    try {
      final token = await getToken();
      final body = <String, dynamic>{};
      if (name != null) body['name'] = name;
      if (zone != null) body['zone'] = zone;
      if (code != null) body['code'] = code;
      final response = await http.put(
        Uri.parse('$baseUrl/api/divisions/$id'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
        body: jsonEncode(body),
      );
      if (response.statusCode != 200) {
        final err = jsonDecode(response.body);
        throw Exception(err['error'] ?? 'Failed to update division');
      }
    } catch (e) {
      throw Exception('Error updating division: $e');
    }
  }

  static Future<void> deleteDivision(String id) async {
    try {
      final token = await getToken();
      final response = await http.delete(
        Uri.parse('$baseUrl/api/divisions/$id'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (response.statusCode != 200) {
        final err = jsonDecode(response.body);
        throw Exception(err['error'] ?? 'Failed to delete division');
      }
    } catch (e) {
      throw Exception('Error deleting division: $e');
    }
  }

  // ================================================================
  // == PROFILE SELF-EDIT
  // ================================================================
  static Future<Map<String, dynamic>> updateProfile({
    String? fullName, String? designation, String? mobile,
  }) async {
    try {
      final token = await getToken();
      final body = <String, dynamic>{};
      if (fullName != null) body['fullName'] = fullName;
      if (designation != null) body['designation'] = designation;
      if (mobile != null) body['mobile'] = mobile;
      final response = await http.post(
        Uri.parse('$baseUrl/api/user/update-profile'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
        body: jsonEncode(body),
      );
      if (response.statusCode == 200) return jsonDecode(response.body);
      final err = jsonDecode(response.body);
      throw Exception(err['error'] ?? 'Failed to update profile');
    } catch (e) {
      throw Exception('Error updating profile: $e');
    }
  }

  // ================================================================
  // == COMPLAINT ACTIONS (Assign, Escalate)
  // ================================================================
  static Future<void> assignComplaint(String complaintId, String assignedTo, {String? assignedToName, String? remarks}) async {
    try {
      final token = await getToken();
      final response = await http.patch(
        Uri.parse('$baseUrl/api/obhs/complaints/assign/$complaintId'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
        body: jsonEncode({'assignedTo': assignedTo, 'assignedToName': assignedToName, 'remarks': remarks}),
      );
      if (response.statusCode != 200) {
        final err = jsonDecode(response.body);
        throw Exception(err['error'] ?? 'Failed to assign complaint');
      }
    } catch (e) {
      throw Exception('Error assigning complaint: $e');
    }
  }

  static Future<void> escalateComplaint(String complaintId, {String? escalationReason, String? escalatedTo}) async {
    try {
      final token = await getToken();
      final response = await http.patch(
        Uri.parse('$baseUrl/api/obhs/complaints/escalate/$complaintId'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
        body: jsonEncode({'escalationReason': escalationReason, 'escalatedTo': escalatedTo}),
      );
      if (response.statusCode != 200) {
        final err = jsonDecode(response.body);
        throw Exception(err['error'] ?? 'Failed to escalate complaint');
      }
    } catch (e) {
      throw Exception('Error escalating complaint: $e');
    }
  }

  static Future<void> autoRouteComplaint(String complaintId) async {
    try {
      final token = await getToken();
      final response = await http.post(
        Uri.parse('$baseUrl/api/obhs/complaints/auto-route'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
        body: jsonEncode({'complaintId': complaintId}),
      );
      if (response.statusCode != 200) {
        final err = jsonDecode(response.body);
        throw Exception(err['error'] ?? 'Failed to auto-route complaint');
      }
    } catch (e) {
      throw Exception('Error auto-routing complaint: $e');
    }
  }

  // ================================================================
  // == AUDIT LOGS
  // ================================================================
  static Future<List<Map<String, dynamic>>> getAuditLogs({String? action, String? targetEntity, int limit = 50}) async {
    try {
      final token = await getToken();
      final params = <String, String>{'limit': limit.toString()};
      if (action != null) params['action'] = action;
      if (targetEntity != null) params['targetEntity'] = targetEntity;
      final uri = Uri.parse('$baseUrl/api/audit/logs').replace(queryParameters: params);
      final response = await http.get(uri, headers: {'Authorization': 'Bearer $token'});
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return List<Map<String, dynamic>>.from(data['logs'] ?? []);
      }
      throw Exception('Failed to fetch audit logs');
    } catch (e) {
      throw Exception('Error fetching audit logs: $e');
    }
  }

  static Future<List<Map<String, dynamic>>> getStationAuditLogs({required String stationId, String? action, int limit = 100}) async {
    try {
      final token = await getToken();
      final params = <String, String>{'limit': limit.toString()};
      if (action != null) params['action'] = action;
      final uri = Uri.parse('$baseUrl/api/audit/logs/station/$stationId').replace(queryParameters: params);
      final response = await http.get(uri, headers: {'Authorization': 'Bearer $token'});
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return List<Map<String, dynamic>>.from(data['logs'] ?? []);
      }
      throw Exception('Failed to fetch station audit logs');
    } catch (e) {
      throw Exception('Error fetching station audit logs: $e');
    }
  }

  static Future<Map<String, dynamic>> getAuditLogStats() async {
    try {
      final token = await getToken();
      final response = await http.get(
        Uri.parse('$baseUrl/api/audit/logs/stats'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (response.statusCode == 200) return jsonDecode(response.body);
      throw Exception('Failed to fetch audit stats');
    } catch (e) {
      throw Exception('Error fetching audit stats: $e');
    }
  }

  // ================================================================
  // == INVOICE PDF DOWNLOAD
  // ================================================================
  static Future<String> getInvoicePdfUrl(String uid) async {
    return '$baseUrl/api/billing/invoice-pdf/$uid';
  }

  static Future<Map<String, dynamic>> sendAuditReportEmail(
      String reportType, String runInstanceId, String emailTo) async {
    try {
      final token = await getToken();
      final url = Uri.parse('$baseUrl/api/reports/send-email');
      
      final response = await http.post(
        url,
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer $token",
        },
        body: json.encode({
          "reportType": reportType,
          "runInstanceId": runInstanceId,
          "emailTo": emailTo
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        return json.decode(response.body);
      } else {
        throw Exception('Failed to send email: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error sending email: $e');
    }
  }

  // ─── PEST CONTROL API ────────────────────────────────────────────────────
  static Future<Map<String, dynamic>> recordPestControl(Map<String, dynamic> data) async {
    final token = await getToken();
    final response = await http.post(
      Uri.parse('$baseUrl/api/station-pest-control/record'),
      headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
      body: jsonEncode(data),
    );
    if (response.statusCode == 201) return jsonDecode(response.body);
    throw Exception(jsonDecode(response.body)['error'] ?? 'Failed to record pest control');
  }

  static Future<List> listPestControl(String stationId, {String? status, String? pestType}) async {
    final token = await getToken();
    final params = <String, String>{};
    if (status != null) params['status'] = status;
    if (pestType != null) params['pestType'] = pestType;
    final uri = Uri.parse('$baseUrl/api/station-pest-control/list/$stationId').replace(queryParameters: params.isNotEmpty ? params : null);
    final response = await http.get(uri, headers: {'Authorization': 'Bearer $token'});
    if (response.statusCode == 200) return jsonDecode(response.body)['data'] ?? [];
    throw Exception('Failed to load pest control records');
  }

  // ─── MACHINE / MATERIAL API ──────────────────────────────────────────────
  static Future<List> listMachines({String? stationId, String? status}) async {
    final token = await getToken();
    final params = <String, String>{};
    if (stationId != null) params['stationId'] = stationId;
    if (status != null) params['status'] = status;
    final uri = Uri.parse('$baseUrl/api/station-machines/list').replace(queryParameters: params.isNotEmpty ? params : null);
    final response = await http.get(uri, headers: {'Authorization': 'Bearer $token'});
    if (response.statusCode == 200) return jsonDecode(response.body)['data'] ?? [];
    throw Exception('Failed to load machines');
  }

  // ─── MACHINE MASTER API ─────────────────────────────────────────────────
  static Future<Map<String, dynamic>> createMachine(Map<String, dynamic> data) async {
    final token = await getToken();
    final response = await http.post(
      Uri.parse('$baseUrl/api/machines'),
      headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
      body: jsonEncode(data),
    );
    if (response.statusCode == 200 || response.statusCode == 201) return jsonDecode(response.body);
    throw Exception(jsonDecode(response.body)['error'] ?? 'Failed to create machine');
  }

  static Future<List> getMachines({String? stationId, String? status}) async {
    final token = await getToken();
    final params = <String, String>{};
    if (stationId != null) params['stationId'] = stationId;
    if (status != null) params['status'] = status;
    final uri = Uri.parse('$baseUrl/api/machines').replace(queryParameters: params.isNotEmpty ? params : null);
    final response = await http.get(uri, headers: {'Authorization': 'Bearer $token'});
    if (response.statusCode == 200) return jsonDecode(response.body)['machines'] ?? [];
    throw Exception('Failed to load machines');
  }

  static Future<Map<String, dynamic>> getMachineById(String uid) async {
    final token = await getToken();
    final response = await http.get(
      Uri.parse('$baseUrl/api/machines/$uid'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (response.statusCode == 200) return jsonDecode(response.body);
    throw Exception('Failed to load machine');
  }

  static Future<Map<String, dynamic>> updateMachine(String uid, Map<String, dynamic> data) async {
    final token = await getToken();
    final response = await http.put(
      Uri.parse('$baseUrl/api/machines/$uid'),
      headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
      body: jsonEncode(data),
    );
    if (response.statusCode == 200) return jsonDecode(response.body);
    throw Exception(jsonDecode(response.body)['error'] ?? 'Failed to update machine');
  }

  static Future<void> deleteMachine(String uid) async {
    final token = await getToken();
    final response = await http.delete(
      Uri.parse('$baseUrl/api/machines/$uid'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (response.statusCode != 200) throw Exception('Failed to delete machine');
  }

  // ─── STATION ARCHIVE API ──────────────────────────────────────────────────
  static Future<Map<String, dynamic>> triggerArchive(String stationId, String archiveType, int month, int year) async {
    final token = await getToken();
    final response = await http.post(
      Uri.parse('$baseUrl/api/station-archives/trigger'),
      headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
      body: jsonEncode({'stationId': stationId, 'archiveType': archiveType, 'month': month, 'year': year}),
    );
    if (response.statusCode == 200 || response.statusCode == 201) return jsonDecode(response.body);
    throw Exception(jsonDecode(response.body)['error'] ?? 'Failed to trigger archive');
  }

  static Future<Map<String, dynamic>> listArchives({String? stationId, String? archiveType, int? month, int? year, String? contractor, String? area, String? user, String? status, String? startDate, String? endDate, int limit = 50}) async {
    final token = await getToken();
    final params = <String, String>{};
    if (stationId != null) params['stationId'] = stationId;
    if (archiveType != null) params['archiveType'] = archiveType;
    if (month != null) params['month'] = month.toString();
    if (year != null) params['year'] = year.toString();
    if (contractor != null) params['contractor'] = contractor;
    if (area != null) params['area'] = area;
    if (user != null) params['user'] = user;
    if (status != null) params['status'] = status;
    if (startDate != null) params['startDate'] = startDate;
    if (endDate != null) params['endDate'] = endDate;
    if (limit != 50) params['limit'] = limit.toString();
    final uri = Uri.parse('$baseUrl/api/station-archives').replace(queryParameters: params.isNotEmpty ? params : null);
    final response = await http.get(uri, headers: {'Authorization': 'Bearer $token'});
    if (response.statusCode == 200) return jsonDecode(response.body);
    throw Exception('Failed to load archives');
  }

  static Future<Map<String, dynamic>> getArchiveById(String uid) async {
    final token = await getToken();
    final response = await http.get(
      Uri.parse('$baseUrl/api/station-archives/$uid'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (response.statusCode == 200) return jsonDecode(response.body);
    throw Exception('Failed to load archive');
  }

  // ─── GARBAGE DISPOSAL API ────────────────────────────────────────────────
  static Future<Map<String, dynamic>> recordGarbageDisposal(Map<String, dynamic> data) async {
    final token = await getToken();
    final response = await http.post(
      Uri.parse('$baseUrl/api/station-garbage/record'),
      headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
      body: jsonEncode(data),
    );
    if (response.statusCode == 201) return jsonDecode(response.body);
    throw Exception(jsonDecode(response.body)['error'] ?? 'Failed to record garbage disposal');
  }

  static Future<List> listGarbageRecords({String? stationId}) async {
    final token = await getToken();
    final params = <String, String>{};
    if (stationId != null) params['stationId'] = stationId;
    final uri = Uri.parse('$baseUrl/api/station-garbage/records').replace(queryParameters: params.isNotEmpty ? params : null);
    final response = await http.get(uri, headers: {'Authorization': 'Bearer $token'});
    if (response.statusCode == 200) return jsonDecode(response.body)['data'] ?? [];
    throw Exception('Failed to load garbage records');
  }

  //<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<< Performance Billing APIs (weightage/score based) >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
  static Future<BillingConfig> getPerformanceBillingConfig(String contractId) async {
    final token = await getToken();
    final response = await http.get(
      Uri.parse('$baseUrl/api/performance-billing/config/$contractId'),
      headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return BillingConfig.fromJson(data['config']);
    }
    throw Exception(jsonDecode(response.body)['error'] ?? 'Failed to load billing config');
  }

  static Future<BillingConfig> savePerformanceBillingConfig(String contractId, Map<String, dynamic> payload) async {
    final token = await getToken();
    final response = await http.put(
      Uri.parse('$baseUrl/api/performance-billing/config/$contractId'),
      headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
      body: jsonEncode(payload),
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return BillingConfig.fromJson(data['config']);
    }
    throw Exception(jsonDecode(response.body)['error'] ?? 'Failed to save billing config');
  }

  static Future<PerformanceScorecard> getPerformanceScorecard({
    required String contractId,
    required String stationId,
    required int month,
    required int year,
  }) async {
    final token = await getToken();
    final uri = Uri.parse('$baseUrl/api/performance-billing/scorecard').replace(queryParameters: {
      'contractId': contractId,
      'stationId': stationId,
      'month': '$month',
      'year': '$year',
    });
    final response = await http.get(uri, headers: {'Authorization': 'Bearer $token'});
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return PerformanceScorecard.fromJson(data['scorecard']);
    }
    throw Exception(jsonDecode(response.body)['error'] ?? 'Failed to load scorecard');
  }

  static Future<PerformanceBill> generatePerformanceBill({
    required String contractId,
    required String stationId,
    required int month,
    required int year,
  }) async {
    final token = await getToken();
    final response = await http.post(
      Uri.parse('$baseUrl/api/performance-billing/bills'),
      headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
      body: jsonEncode({'contractId': contractId, 'stationId': stationId, 'month': month, 'year': year}),
    );
    if (response.statusCode == 200 || response.statusCode == 201) {
      final data = jsonDecode(response.body);
      return PerformanceBill.fromJson(data['bill'] ?? data);
    }
    throw Exception(jsonDecode(response.body)['error'] ?? 'Failed to create bill');
  }

  static Future<List<PerformanceBill>> listPerformanceBills({
    String? contractId,
    String? stationId,
    int? month,
    int? year,
    String? status,
  }) async {
    final token = await getToken();
    final params = <String, String>{
      if (contractId != null) 'contractId': contractId,
      if (stationId != null) 'stationId': stationId,
      if (month != null) 'month': '$month',
      if (year != null) 'year': '$year',
      if (status != null) 'status': status,
    };
    final uri = Uri.parse('$baseUrl/api/performance-billing/bills').replace(queryParameters: params.isNotEmpty ? params : null);
    final response = await http.get(uri, headers: {'Authorization': 'Bearer $token'});
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return (data['bills'] as List<dynamic>? ?? [])
          .map((e) => PerformanceBill.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    throw Exception('Failed to load bills');
  }

  static Future<PerformanceBill> getPerformanceBill(String uid) async {
    final token = await getToken();
    final response = await http.get(
      Uri.parse('$baseUrl/api/performance-billing/bills/$uid'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return PerformanceBill.fromJson(data['bill']);
    }
    throw Exception('Failed to load bill');
  }

  static Future<PerformanceBill> performanceBillAction(String uid, String action, {Map<String, dynamic>? body}) async {
    final token = await getToken();
    final response = await http.post(
      Uri.parse('$baseUrl/api/performance-billing/bills/$uid/$action'),
      headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
      body: body == null ? null : jsonEncode(body),
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return PerformanceBill.fromJson(data['bill']);
    }
    throw Exception(jsonDecode(response.body)['error'] ?? 'Failed to run bill action: $action');
  }

  static Future<bool> deletePerformanceBill(String uid) async {
    final token = await getToken();
    final response = await http.delete(
      Uri.parse('$baseUrl/api/performance-billing/bills/$uid'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (response.statusCode == 200) return true;
    throw Exception('Failed to delete bill');
  }

  static Future<PerformanceBillingDashboard> getPerformanceBillingDashboard({String? contractId, String? stationId}) async {
    final token = await getToken();
    final params = <String, String>{
      if (contractId != null) 'contractId': contractId,
      if (stationId != null) 'stationId': stationId,
    };
    final uri = Uri.parse('$baseUrl/api/performance-billing/dashboard').replace(queryParameters: params.isNotEmpty ? params : null);
    final response = await http.get(uri, headers: {'Authorization': 'Bearer $token'});
    if (response.statusCode == 200) {
      return PerformanceBillingDashboard.fromJson(jsonDecode(response.body));
    }
    throw Exception('Failed to load billing dashboard');
  }

}

