class SafetyCheckModel {
  final String id;
  final String runInstanceId;
  final String coachNo;
  final DateTime scheduledTime;

  static DateTime _parseTime(dynamic value) {
    if (value == null || value is! String || value.isEmpty) {
      return DateTime.now();
    }
    final full = DateTime.tryParse(value);
    if (full != null) return full;
    // Backend seeds time slots like "06:00" instead of a full ISO timestamp.
    final parts = value.split(':');
    final hour = int.tryParse(parts.isNotEmpty ? parts[0] : '');
    final minute = int.tryParse(parts.length > 1 ? parts[1] : '');
    if (hour == null) return DateTime.now();
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day, hour, minute ?? 0);
  }
  final String fireExtinguisherStatus;
  final String fsdsStatus;
  final String cctvStatus;
  final String emergencyEquipmentStatus;
  final List<String> photos;
  final List<String> deficiencyReports;
  final String status;
  final String? remarks;
  final DateTime? completedAt;

  SafetyCheckModel({
    required this.id,
    required this.runInstanceId,
    this.coachNo = '',
    required this.scheduledTime,
    this.fireExtinguisherStatus = 'ok',
    this.fsdsStatus = 'ok',
    this.cctvStatus = 'ok',
    this.emergencyEquipmentStatus = 'ok',
    this.photos = const [],
    this.deficiencyReports = const [],
    this.status = 'PENDING',
    this.remarks,
    this.completedAt,
  });

  factory SafetyCheckModel.fromJson(Map<String, dynamic> json) {
    return SafetyCheckModel(
      id: json['id'] as String? ?? '',
      runInstanceId: json['runInstanceId'] as String? ?? '',
      coachNo: json['coachNo'] == null
          ? ''
          : (json['coachNo'] is String
              ? json['coachNo'] as String
              : json['coachNo'].toString()),
      scheduledTime: _parseTime(json['scheduledTime']),
      fireExtinguisherStatus:
          json['fireExtinguisherStatus'] as String? ?? 'ok',
      fsdsStatus: json['fsdsStatus'] as String? ?? 'ok',
      cctvStatus: json['cctvStatus'] as String? ?? 'ok',
      emergencyEquipmentStatus:
          json['emergencyEquipmentStatus'] as String? ?? 'ok',
      photos: (json['photos'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      deficiencyReports: (json['deficiencyReports'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      status: json['status'] as String? ?? 'PENDING',
      remarks: json['remarks'] as String?,
      completedAt: json['completedAt'] != null
          ? DateTime.tryParse(json['completedAt'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'checkId': id,
      'id': id,
      'runInstanceId': runInstanceId,
      'coachNo': coachNo,
      'scheduledTime': scheduledTime.toIso8601String(),
      'fireExtinguisherStatus': fireExtinguisherStatus,
      'fsdsStatus': fsdsStatus,
      'cctvStatus': cctvStatus,
      'emergencyEquipmentStatus': emergencyEquipmentStatus,
      'photos': photos,
      'deficiencyReports': deficiencyReports,
      'status': status,
      if (remarks != null) 'remarks': remarks,
      if (completedAt != null) 'completedAt': completedAt!.toIso8601String(),
    };
  }

  SafetyCheckModel copyWith({
    String? id,
    String? runInstanceId,
    DateTime? scheduledTime,
    String? fireExtinguisherStatus,
    String? fsdsStatus,
    String? cctvStatus,
    String? emergencyEquipmentStatus,
    List<String>? photos,
    List<String>? deficiencyReports,
    String? status,
    String? remarks,
    DateTime? completedAt,
  }) {
    return SafetyCheckModel(
      id: id ?? this.id,
      runInstanceId: runInstanceId ?? this.runInstanceId,
      scheduledTime: scheduledTime ?? this.scheduledTime,
      fireExtinguisherStatus:
          fireExtinguisherStatus ?? this.fireExtinguisherStatus,
      fsdsStatus: fsdsStatus ?? this.fsdsStatus,
      cctvStatus: cctvStatus ?? this.cctvStatus,
      emergencyEquipmentStatus:
          emergencyEquipmentStatus ?? this.emergencyEquipmentStatus,
      photos: photos ?? this.photos,
      deficiencyReports: deficiencyReports ?? this.deficiencyReports,
      status: status ?? this.status,
      remarks: remarks ?? this.remarks,
      completedAt: completedAt ?? this.completedAt,
    );
  }
}
