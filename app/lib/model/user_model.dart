class UserModel {
  final String uid;
  final String email;
  final String role;
  final String userType;
  final String fullName;
  final String? mobile;
  final String? designation;
  final String? zone;
  final String? division;
  final String? depot;
  final String? stationId;
  final String? platformId;
  final String? areaId;
  final String? entityId;
  final Map<String, dynamic>? entityDetails;
  final String? contractId;
  final String? contractType;
  final String? domain;
  final List<String> stations;
  final String? status;
  final List<String>? trainIds;
  final String? trainId;
  final DateTime? createdAt;
  final DateTime? submittedAt;
  final DateTime? approvedAt;

  UserModel({
    required this.uid,
    required this.email,
    required this.role,
    required this.userType,
    required this.fullName,
    this.mobile,
    this.designation,
    this.zone,
    this.division,
    this.depot,
    this.stationId,
    this.platformId,
    this.areaId,
    this.entityId,
    this.entityDetails,
    this.contractId,
    this.contractType,
    this.domain,
    this.stations = const [],
    this.trainIds,
    this.trainId,
    this.status,
    this.createdAt,
    this.submittedAt,
    this.approvedAt,
  });

  static String _normalizeRole(String? rawRole) {
    if (rawRole == null) return '';
    final roleUpper = rawRole.toUpperCase().replaceAll(' ', '_');
    switch (roleUpper) {
      case 'SUPER_ADMIN':
        return 'Super Admin';
      case 'COMPANY_MASTER':
        return 'Company Master';
      case 'RAILWAY_MASTER':
        return 'Railway Master';
      case 'ADMIN':
        return 'Admin';
      case 'RAILWAY_ADMIN':
        return 'Railway Admin';
      case 'RAILWAY_INSPECTOR':
        return 'Railway Inspector';
      case 'RAILWAY_SUPERVISOR':
        return 'Railway Supervisor';
      case 'CONTRACTOR_ADMIN':
        return 'Contractor Admin';
      case 'CONTRACTOR_SUPERVISOR':
        return 'Contractor Supervisor';
      case 'CTS':
        return 'CTS';
      case 'WORKER':
        return 'Worker';
      case 'RAILWAY_WORKER':
        return 'Railway Worker';
      case 'JANITOR':
        return 'Janitor';
      case 'ATTENDANT':
        return 'Attendant';
      case 'PASSENGER':
        return 'Passenger';
      default:
        return rawRole;
    }
  }

  factory UserModel.fromApiResponse(Map<String, dynamic> json) {
    final user = json['user'] is Map<String, dynamic> ? json['user'] : json;

    return UserModel(
      uid: user['uid'] ?? '',
      email: user['email'] ?? '',
      role: _normalizeRole(user['role']),
      userType: user['userType'] ?? '',
      fullName: user['fullName'] ?? user['name'] ?? '',
      mobile: user['mobile']?.toString(),
      designation: user['designation'],
      zone: user['zone'],
      division: user['division'],
      depot: user['depot'],
      stationId: user['stationId'],
      platformId: user['platformId'],
      areaId: user['areaId'],
      entityId: user['entityId'],
      entityDetails: user['entityDetails'] is Map<String, dynamic>
          ? user['entityDetails']
          : null,
      contractId: user['contractId'],
      contractType: user['contractType'],
      domain: user['domain'],
      stations: (user['stations'] as List?)?.cast<String>() ?? [],
      status: user['status'],
      createdAt: _parseTimestamp(user['createdAt']),
      submittedAt: _parseTimestamp(user['submitted_at']),
      approvedAt: _parseTimestamp(user['approved_at']),
    );
  }

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      uid: json['uid'] ?? '',
      email: json['email'] ?? '',
      role: _normalizeRole(json['role']),
      userType: json['userType'] ?? '',
      fullName: json['fullName'] ?? '',
      mobile: json['mobile'],
      designation: json['designation'],
      zone: json['zone'],
      division: json['division'],
      depot: json['depot'],
      stationId: json['stationId'],
      platformId: json['platformId'],
      areaId: json['areaId'],
      entityId: json['entityId'],
      entityDetails: json['entityDetails'] is Map<String, dynamic>
          ? json['entityDetails']
          : null,
      contractId: json['contractId'],
      contractType: json['contractType'],
      domain: json['domain'],
      stations: (json['stations'] as List?)?.cast<String>() ?? [],
      status: json['status'],
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'])
          : null,
      submittedAt: json['submittedAt'] != null
          ? DateTime.tryParse(json['submittedAt'])
          : null,
      approvedAt: json['approvedAt'] != null
          ? DateTime.tryParse(json['approvedAt'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'uid': uid,
      'email': email,
      'role': role,
      'userType': userType,
      'fullName': fullName,
      'mobile': mobile,
      'designation': designation,
      'zone': zone,
      'division': division,
      'depot': depot,
      'stationId': stationId,
      'platformId': platformId,
      'areaId': areaId,
      'entityId': entityId,
      'entityDetails': entityDetails,
      'contractId': contractId,
      'contractType': contractType,
      'domain': domain,
      'stations': stations,
      'status': status,
      'createdAt': createdAt?.toIso8601String(),
      'submittedAt': submittedAt?.toIso8601String(),
      'approvedAt': approvedAt?.toIso8601String(),
    };
  }

  static DateTime? _parseTimestamp(dynamic ts) {
    if (ts == null) return null;
    if (ts is Map && ts.containsKey('_seconds')) {
      return DateTime.fromMillisecondsSinceEpoch(ts['_seconds'] * 1000);
    }
    return null;
  }
}