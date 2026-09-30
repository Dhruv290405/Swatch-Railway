class RatingModel {
  final String id;
  final String runInstanceId;
  final String? coachNo;
  final String? employeeId;
  final String? taskId;
  final String source;
  final int rating;
  final String? journeyId;
  final String? remarks;
  final DateTime createdAt;

  RatingModel({
    required this.id,
    required this.runInstanceId,
    this.coachNo,
    this.employeeId,
    this.taskId,
    required this.source,
    required this.rating,
    this.journeyId,
    this.remarks,
    required this.createdAt,
  });

  factory RatingModel.fromJson(Map<String, dynamic> json) {
    return RatingModel(
      id: json['id'] as String? ?? '',
      runInstanceId: json['runInstanceId'] as String? ?? '',
      coachNo: json['coachNo'] as String?,
      employeeId: json['employeeId'] as String?,
      taskId: json['taskId'] as String?,
      source: json['source'] as String? ?? '',
      rating: json['rating'] is num
          ? (json['rating'] as num).toInt()
          : int.tryParse('${json['rating']}') ?? 0,
      journeyId: json['journeyId'] as String?,
      remarks: json['remarks'] as String?,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'runInstanceId': runInstanceId,
      if (coachNo != null) 'coachNo': coachNo,
      if (employeeId != null) 'employeeId': employeeId,
      if (taskId != null) 'taskId': taskId,
      'source': source,
      'rating': rating,
      if (journeyId != null) 'journeyId': journeyId,
      if (remarks != null) 'remarks': remarks,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  RatingModel copyWith({
    String? id,
    String? runInstanceId,
    String? coachNo,
    String? employeeId,
    String? taskId,
    String? source,
    int? rating,
    String? journeyId,
    String? remarks,
    DateTime? createdAt,
  }) {
    return RatingModel(
      id: id ?? this.id,
      runInstanceId: runInstanceId ?? this.runInstanceId,
      coachNo: coachNo ?? this.coachNo,
      employeeId: employeeId ?? this.employeeId,
      taskId: taskId ?? this.taskId,
      source: source ?? this.source,
      rating: rating ?? this.rating,
      journeyId: journeyId ?? this.journeyId,
      remarks: remarks ?? this.remarks,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
