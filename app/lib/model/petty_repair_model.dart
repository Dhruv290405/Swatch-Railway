String _asString(dynamic value) {
  if (value == null) return '';
  return value is String ? value : value.toString();
}

class PettyRepairModel {
  final String id;
  final String runInstanceId;
  final String coachNo;
  final String inspectionTime;
  final Map<String, String> items;
  final bool isEscalated;
  final String? escalatedTo;
  final String status;
  final String? remarks;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  PettyRepairModel({
    required this.id,
    required this.runInstanceId,
    required this.coachNo,
    required this.inspectionTime,
    this.items = const {},
    this.isEscalated = false,
    this.escalatedTo,
    this.status = 'PENDING',
    this.remarks,
    this.createdAt,
    this.updatedAt,
  });

  factory PettyRepairModel.fromJson(Map<String, dynamic> json) {
    return PettyRepairModel(
      id: json['id'] as String? ?? '',
      runInstanceId: json['runInstanceId'] as String? ?? '',
      coachNo: _asString(json['coachNo']),
      inspectionTime: _asString(json['inspectionTime']),
      items: (json['items'] as Map<String, dynamic>?)
              ?.map((k, v) => MapEntry(k, _asString(v))) ??
          {},
      isEscalated: json['isEscalated'] as bool? ?? false,
      escalatedTo: json['escalatedTo'] as String?,
      status: json['status'] as String? ?? 'PENDING',
      remarks: json['remarks'] as String?,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'] as String)
          : null,
      updatedAt: json['updatedAt'] != null
          ? DateTime.tryParse(json['updatedAt'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'runInstanceId': runInstanceId,
      'coachNo': coachNo,
      'inspectionTime': inspectionTime,
      'items': items,
      'isEscalated': isEscalated,
      if (escalatedTo != null) 'escalatedTo': escalatedTo,
      'status': status,
      if (remarks != null) 'remarks': remarks,
      if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
      if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
    };
  }

  PettyRepairModel copyWith({
    String? id,
    String? runInstanceId,
    String? coachNo,
    String? inspectionTime,
    Map<String, String>? items,
    bool? isEscalated,
    String? escalatedTo,
    String? status,
    String? remarks,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return PettyRepairModel(
      id: id ?? this.id,
      runInstanceId: runInstanceId ?? this.runInstanceId,
      coachNo: coachNo ?? this.coachNo,
      inspectionTime: inspectionTime ?? this.inspectionTime,
      items: items ?? this.items,
      isEscalated: isEscalated ?? this.isEscalated,
      escalatedTo: escalatedTo ?? this.escalatedTo,
      status: status ?? this.status,
      remarks: remarks ?? this.remarks,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
