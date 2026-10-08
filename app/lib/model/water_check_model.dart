String _asString(dynamic value) {
  if (value == null) return '';
  return value is String ? value : value.toString();
}

class WaterCheckModel {
  final String id;
  final String runInstanceId;
  final String coachNo;
  final String checkTime;
  final String checkDate;
  final String waterStatus;
  final bool lowWaterAlert;
  final String? wateringPointSchedule;
  final String status;
  final String? photoUrl;

  WaterCheckModel({
    required this.id,
    required this.runInstanceId,
    required this.coachNo,
    required this.checkTime,
    required this.checkDate,
    this.waterStatus = 'empty',
    this.lowWaterAlert = false,
    this.wateringPointSchedule,
    this.status = 'PENDING',
    this.photoUrl,
  });

  factory WaterCheckModel.fromJson(Map<String, dynamic> json) {
    return WaterCheckModel(
      id: json['id'] as String? ?? '',
      runInstanceId: json['runInstanceId'] as String? ?? '',
      coachNo: _asString(json['coachNo']),
      checkTime: json['checkTime'] as String? ?? '',
      checkDate: json['checkDate'] as String? ?? '',
      waterStatus: json['waterStatus'] as String? ?? 'empty',
      lowWaterAlert: json['lowWaterAlert'] as bool? ?? false,
      wateringPointSchedule: json['wateringPointSchedule'] as String?,
      status: json['status'] as String? ?? 'PENDING',
      photoUrl: json['photoUrl'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'runInstanceId': runInstanceId,
      'coachNo': coachNo,
      'checkTime': checkTime,
      'checkDate': checkDate,
      'waterStatus': waterStatus,
      'lowWaterAlert': lowWaterAlert,
      if (wateringPointSchedule != null)
        'wateringPointSchedule': wateringPointSchedule,
      'status': status,
      if (photoUrl != null) 'photoUrl': photoUrl,
    };
  }

  WaterCheckModel copyWith({
    String? id,
    String? runInstanceId,
    String? coachNo,
    String? checkTime,
    String? checkDate,
    String? waterStatus,
    bool? lowWaterAlert,
    String? wateringPointSchedule,
    String? status,
    String? photoUrl,
  }) {
    return WaterCheckModel(
      id: id ?? this.id,
      runInstanceId: runInstanceId ?? this.runInstanceId,
      coachNo: coachNo ?? this.coachNo,
      checkTime: checkTime ?? this.checkTime,
      checkDate: checkDate ?? this.checkDate,
      waterStatus: waterStatus ?? this.waterStatus,
      lowWaterAlert: lowWaterAlert ?? this.lowWaterAlert,
      wateringPointSchedule:
          wateringPointSchedule ?? this.wateringPointSchedule,
      status: status ?? this.status,
      photoUrl: photoUrl ?? this.photoUrl,
    );
  }
}
