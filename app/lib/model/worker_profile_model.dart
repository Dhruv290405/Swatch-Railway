class WorkerProfileModel {
  final String fullName;
  final String email;
  final String mobile;
  final String designation;
  final String division;
  final String zone;
  final String status;
  final String uid;
  final String userType;
  final List<AssignedRun> assignedRuns;

  WorkerProfileModel({
    required this.fullName,
    required this.email,
    required this.mobile,
    required this.designation,
    required this.division,
    required this.zone,
    required this.status,
    required this.uid,
    required this.userType,
    required this.assignedRuns,
  });

  factory WorkerProfileModel.fromJson(Map<String, dynamic> json) {
    final profile = json['profile'] ?? json;
    final runs = json['assignedRuns'] as List<dynamic>? ?? [];

    return WorkerProfileModel(
      fullName: profile['fullName'] ?? '',
      email: profile['email'] ?? '',
      mobile: profile['mobile'] ?? '',
      designation: profile['designation'] ?? '',
      division: profile['division'] ?? '',
      zone: profile['zone'] ?? '',
      status: profile['status'] ?? '',
      uid: profile['uid'] ?? '',
      userType: profile['userType'] ?? '',
      assignedRuns: runs
          .map((r) => AssignedRun.fromJson(r as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
    'profile': {
      'fullName': fullName,
      'email': email,
      'mobile': mobile,
      'designation': designation,
      'division': division,
      'zone': zone,
      'status': status,
      'uid': uid,
      'userType': userType,
    },
    'assignedRuns': assignedRuns.map((r) => r.toJson()).toList(),
  };

  WorkerProfileModel copyWith({
    String? fullName,
    String? email,
    String? mobile,
    String? designation,
    String? division,
    String? zone,
    String? status,
    String? uid,
    String? userType,
    List<AssignedRun>? assignedRuns,
  }) {
    return WorkerProfileModel(
      fullName: fullName ?? this.fullName,
      email: email ?? this.email,
      mobile: mobile ?? this.mobile,
      designation: designation ?? this.designation,
      division: division ?? this.division,
      zone: zone ?? this.zone,
      status: status ?? this.status,
      uid: uid ?? this.uid,
      userType: userType ?? this.userType,
      assignedRuns: assignedRuns ?? this.assignedRuns,
    );
  }
}

class AssignedRun {
  final String runInstanceId;
  final String instanceId;
  final String trainNo;
  final String trainName;
  final String departureDate;
  final String outboundTrainNo;
  final String inboundTrainNo;
  final String status;
  final CoachInfo? myCoach;

  AssignedRun({
    required this.runInstanceId,
    required this.instanceId,
    required this.trainNo,
    required this.trainName,
    required this.departureDate,
    required this.outboundTrainNo,
    required this.inboundTrainNo,
    required this.status,
    this.myCoach,
  });

  factory AssignedRun.fromJson(Map<String, dynamic> json) {
    return AssignedRun(
      runInstanceId: json['runInstanceId'] ?? json['id'] ?? '',
      instanceId: json['instanceId'] ?? '',
      trainNo: json['trainNo'] ?? '',
      trainName: json['trainName'] ?? '',
      departureDate: json['departureDate'] ?? '',
      outboundTrainNo: json['outboundTrainNo'] ?? '',
      inboundTrainNo: json['inboundTrainNo'] ?? '',
      status: json['status'] ?? '',
      myCoach: json['myCoach'] != null
          ? CoachInfo.fromJson(json['myCoach'] as Map<String, dynamic>)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'runInstanceId': runInstanceId,
    'instanceId': instanceId,
    'trainNo': trainNo,
    'trainName': trainName,
    'departureDate': departureDate,
    'outboundTrainNo': outboundTrainNo,
    'inboundTrainNo': inboundTrainNo,
    'status': status,
    'myCoach': myCoach?.toJson(),
  };

  String get dashboardLabel => '$trainNo  |  $trainName';

  String get instanceDisplay => instanceId;
}

class CoachInfo {
  final int coachPosition;
  final String coachType;
  final String attendanceStatus;
  final DateTime? lastUpdatedAt;

  CoachInfo({
    required this.coachPosition,
    required this.coachType,
    required this.attendanceStatus,
    this.lastUpdatedAt,
  });

  factory CoachInfo.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(dynamic raw) {
      if (raw == null) return null;
      if (raw is String && raw.isNotEmpty) return DateTime.tryParse(raw)?.toLocal();
      if (raw is int && raw > 0) {
        final ms = raw < 10000000000 ? raw * 1000 : raw;
        return DateTime.fromMillisecondsSinceEpoch(ms).toLocal();
      }
      return null;
    }

    return CoachInfo(
      // Positions are normally numeric, but a label like "S1" must not crash the whole worker home.
      coachPosition: json['coachPosition'] is int
          ? json['coachPosition'] as int
          : int.tryParse(
                RegExp(r'\d+').firstMatch('${json['coachPosition'] ?? ''}')?.group(0) ?? '',
              ) ??
              0,
      coachType: json['coachType'] ?? '',
      attendanceStatus: json['attendanceStatus'] ?? 'Pending',
      lastUpdatedAt: parseDate(
        json['lastUpdatedAt'] ??
            json['updatedAt'] ??
            json['markedAt'] ??
            json['attendanceDate'] ??
            json['date'],
      ),
    );
  }

  Map<String, dynamic> toJson() => {
    'coachPosition': coachPosition,
    'coachType': coachType,
    'attendanceStatus': attendanceStatus,
    if (lastUpdatedAt != null) 'lastUpdatedAt': lastUpdatedAt!.toIso8601String(),
  };
}
