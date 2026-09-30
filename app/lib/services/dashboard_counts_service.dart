import 'package:cloud_firestore/cloud_firestore.dart';
import '../repositories/obhs_repository.dart';

class FirebaseCountService {


  static Future<int> getUniqueZoneCount() async {
    try {
      final firestore = FirebaseFirestore.instance;

      print("Checking Firestore connection...");
      print("Firebase App: ${firestore.app.name}");
      print("Firebase Project ID: ${firestore.app.options.projectId}");

      final snapshot = await firestore.collection('users').get().timeout(const Duration(seconds: 4));

      print("Users collection fetched");
      print("Total documents: ${snapshot.size}");
      print("Docs length: ${snapshot.docs.length}");

      if (snapshot.docs.isEmpty) {
        print("WARNING: Users collection is EMPTY!");
        return 0;
      }

      for (int i = 0; i < (snapshot.docs.length > 3 ? 3 : snapshot.docs.length); i++) {
        print("Doc $i data: ${snapshot.docs[i].data()}");
      }

      final divisions = <String>{};

      for (var doc in snapshot.docs) {
        final data = doc.data();
        if (data.containsKey('zone') && data['zone'] != null && data['zone'].toString().isNotEmpty) {
          divisions.add(data['zone'].toString());
        }
      }

      print("Unique zones found: ${divisions.length}");
      print("Zones: $divisions");

      return divisions.length;
    } catch (e) {
      print("ERROR: $e");
      return 0;
    }
  }

  static Future<int> getUniqueDivisionCount({String? zone}) async {
    try {
      final firestore = FirebaseFirestore.instance;
      Query query = firestore.collection('users');

      if (zone != null && zone.isNotEmpty) {
        query = query.where('zone', isEqualTo: zone);
      }

      final snapshot = await query.get().timeout(const Duration(seconds: 4));

      final divisions = <String>{};

      for (var doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        if (data.containsKey('division') && data['division'] != null && data['division'].toString().isNotEmpty) {
          divisions.add(data['division'].toString());
        }
      }

      return divisions.length;
    } catch (e) {
      return 0;
    }
  }

  static Future<int> getUniqueDepotCount({String? zone, String? division}) async {
    try {
      final firestore = FirebaseFirestore.instance;
      Query query = firestore.collection('users');

      if (zone != null && zone.isNotEmpty) {
        query = query.where('zone', isEqualTo: zone);
      }

      if (division != null && division.isNotEmpty) {
        query = query.where('division', isEqualTo: division);
      }

      final snapshot = await query.get().timeout(const Duration(seconds: 4));

      final depots = <String>{};

      for (var doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        if (data.containsKey('depot') && data['depot'] != null && data['depot'].toString().isNotEmpty) {
          depots.add(data['depot'].toString());
        }
      }

      return depots.length;
    } catch (e) {
      print('Error fetching depot count: $e');
      return 0;
    }
  }

  static Future<int> getRailwayUserCount({String? zone, String? division, String? depot}) async {
    try {
      final firestore = FirebaseFirestore.instance;
      Query query = firestore.collection('users');

      query = query.where('userType', isEqualTo: 'railway');

      if (zone != null && zone.isNotEmpty) {
        query = query.where('zone', isEqualTo: zone);
      }

      if (division != null && division.isNotEmpty) {
        query = query.where('division', isEqualTo: division);
      }

      if (depot != null && depot.isNotEmpty) {
        query = query.where('depot', isEqualTo: depot);
      }

      final snapshot = await query.count().get().timeout(const Duration(seconds: 4));

      return snapshot.count ?? 0;
    } catch (e) {
      return 0;
    }
  }

  static Future<int> getContractorUserCount({String? zone, String? division, String? depot}) async {
    try {
      final firestore = FirebaseFirestore.instance;
      Query query = firestore.collection('users');

      query = query.where('userType', isEqualTo: 'contractor');

      if (zone != null && zone.isNotEmpty) {
        query = query.where('zone', isEqualTo: zone);
      }

      if (division != null && division.isNotEmpty) {
        query = query.where('division', isEqualTo: division);
      }

      if (depot != null && depot.isNotEmpty) {
        query = query.where('depot', isEqualTo: depot);
      }

      final snapshot = await query.count().get().timeout(const Duration(seconds: 4));

      return snapshot.count ?? 0;
    } catch (e) {
      return 0;
    }
  }

  static Future<int> getTotalEntityRegistered() async {
    try {
      final firestore = FirebaseFirestore.instance;
      final snapshot = await firestore.collection('entities').count().get().timeout(const Duration(seconds: 4));

      return snapshot.count ?? 0;
    } catch (e) {
      return 0;
    }
  }

  static Future<int> getTotalActiveContracts({String? zone, String? division, String? depot}) async {
    try {
      final firestore = FirebaseFirestore.instance;
      Query query = firestore.collection('contracts');

      query = query.where('status', isEqualTo: 'Active');

      if (zone != null && zone.isNotEmpty) {
        query = query.where('zone', isEqualTo: zone);
      }

      if (division != null && division.isNotEmpty) {
        query = query.where('division', isEqualTo: division);
      }

      if (depot != null && depot.isNotEmpty) {
        query = query.where('depot', isEqualTo: depot);
      }

      final snapshot = await query.count().get().timeout(const Duration(seconds: 4));

      return snapshot.count ?? 0;
    } catch (e) {
      print("Error fetching active contracts count: $e");
      return 0;
    }
  }

  static Future<int> getTotalFormsProcessed({String? zone, String? division}) async {
    try {
      final firestore = FirebaseFirestore.instance;

      Query premisesQuery = firestore.collection('premisesForms');
      if (zone != null && zone.isNotEmpty) {
        premisesQuery = premisesQuery.where('submittedByZone', isEqualTo: zone);
      }
      if (division != null && division.isNotEmpty) {
        premisesQuery = premisesQuery.where('submittedByDivision', isEqualTo: division);
      }

      Query coachQuery = firestore.collection('coachForms');
      if (zone != null && zone.isNotEmpty) {
        coachQuery = coachQuery.where('submittedByZone', isEqualTo: zone);
      }
      if (division != null && division.isNotEmpty) {
        coachQuery = coachQuery.where('submittedByDivision', isEqualTo: division);
      }

      final premisesSnapshot = await premisesQuery.count().get().timeout(const Duration(seconds: 4));
      final coachSnapshot = await coachQuery.count().get().timeout(const Duration(seconds: 4));

      final total = (premisesSnapshot.count ?? 0) + (coachSnapshot.count ?? 0);

      return total;
    } catch (e) {
      return 0;
    }
  }



  static Future<Map<String, int>> getRailwayUserFormCounts(String uid) async {
    try {
      final firestore = FirebaseFirestore.instance;


      final snapshot = await firestore
          .collection('coachForms')
          .where('submittedTo.railwayEmployeeId', isEqualTo: uid)
          .get()
          .timeout(const Duration(seconds: 4));


      int scoredCount = 0;
      int acceptedCount = 0;
      int locked = 0;
      int pendingCount = 0;
      int completedToday = 0;


      DateTime now = DateTime.now();
      DateTime startOfDay = DateTime(now.year, now.month, now.day);
      DateTime endOfDay = startOfDay.add(const Duration(days: 1));


      for (var doc in snapshot.docs) {
        final data = doc.data();
        final status = data['status'] ?? '';
        final ratedAt = data['ratedAt'];

        if (status == 'AUTO-APPROVED') {
          scoredCount++;


          if (ratedAt != null && ratedAt is Timestamp) {
            final ratedDate = ratedAt.toDate();
            if (ratedDate.isAfter(startOfDay) && ratedDate.isBefore(endOfDay)) {
              completedToday++;
            }
          }
        } else if (status == 'APPROVED_BY_RAILWAY') {
          acceptedCount++;
        } else if (status == 'LOCKED') {
          locked++;
        } else if (status == 'SUBMITTED') {
          pendingCount++;
        }
      }

      print("Scored: $scoredCount, Accepted: $acceptedCount, Pending: $pendingCount, Completed Today: $completedToday ,locked: $locked");

      return {
        'Scored': scoredCount,
        'Accepted': acceptedCount,
        'PENDING': pendingCount,
        'Completed Today': completedToday,
        'locked': locked,
      };
    } catch (e) {
      print("Error fetching form counts: $e");
      return {
        'APPROVED_BY_RAILWAY': 0,
        'ACCEPTED_BY_RAILWAY': 0,
        'PENDING': 0,
        'COMPLETED_TODAY': 0,
        'locked': 0,
      };
    }
  }


  static Future<Map<String, dynamic>> getPremisesCleaningStats({
    required String userRole,
    required String uid,
    String? zone,
    String? division,
    String? depot,
    String? entityId,
    String? contractId,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      final firestore = FirebaseFirestore.instance;
      Query query = firestore.collection('premisesForms');

      query = query.where('status', whereIn: ['LOCKED', 'AUTO-APPROVED']);

      if (userRole == 'Railway Supervisor') {
        query = query.where('submittedTo.railwayEmployeeId', isEqualTo: uid);
      } else if (userRole == 'Contractor Supervisor') {
        query = query.where('submittedById', isEqualTo: uid);
      } else if (userRole == 'Railway Admin') {
        if (division != null && division.isNotEmpty) {
          query = query.where('submittedByDivision', isEqualTo: division);
        }
      } else if (userRole == 'Contractor Admin') {
        if (division != null && division.isNotEmpty) {
          query = query.where('submittedByDivision', isEqualTo: division);
        }
        if (entityId != null && entityId.isNotEmpty) {
          query = query.where('submittedByEntityId', isEqualTo: entityId);
        }
      } else if (userRole == 'Railway Master') {
        if (zone != null && zone.isNotEmpty) {
          query = query.where('submittedByZone', isEqualTo: zone);
        }
      } else if (userRole == 'Contractor Master') {
        if (entityId != null && entityId.isNotEmpty) {
          query = query.where('submittedByEntityId', isEqualTo: entityId);
        }
      }

      if (contractId != null && contractId.isNotEmpty) {
        query = query.where('contractId', isEqualTo: contractId);
      }

      if (startDate != null) {
        query = query.where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(startDate));
      }
      if (endDate != null) {
        query = query.where('createdAt', isLessThanOrEqualTo: Timestamp.fromDate(endDate));
      }

      final snapshot = await query.get().timeout(const Duration(seconds: 4));

      int totalPremisesCleaned = 0;
      int manPowerDeployed = 0;
      double totalAreaCleaned = 0.0;


      int gradeAbove90 = 0;
      int grade81to90 = 0;
      int grade71to80 = 0;
      int gradeBelow70 = 0;

      for (var doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;

        totalPremisesCleaned++;


        if (data.containsKey('ratingDetails')) {
          final ratingDetails = data['ratingDetails'] as Map<String, dynamic>?;
          if (ratingDetails != null && ratingDetails.containsKey('summary')) {
            final summary = ratingDetails['summary'] as Map<String, dynamic>?;
            if (summary != null && summary.containsKey('overallAveragePct')) {
              final overallPctStr = summary['overallAveragePct']?.toString() ?? '0';
              final percentageValue = double.tryParse(overallPctStr.replaceAll('%', '').trim()) ?? 0.0;


              if (percentageValue > 90) {
                gradeAbove90++;
              } else if (percentageValue >= 81 && percentageValue <= 90) {
                grade81to90++;
              } else if (percentageValue >= 71 && percentageValue <= 80) {
                grade71to80++;
              } else if (percentageValue <= 70) {
                gradeBelow70++;
              }
            }
          }
        }


        if (data.containsKey('manpower') && data['manpower'] is List) {
          manPowerDeployed += (data['manpower'] as List).length;
        }


        if (data.containsKey('area')) {
          totalAreaCleaned += (data['area'] ?? 0).toDouble();
        }
      }


      double gradeAbove90Pct = totalPremisesCleaned > 0 ? (gradeAbove90 / totalPremisesCleaned * 100) : 0.0;
      double grade81to90Pct = totalPremisesCleaned > 0 ? (grade81to90 / totalPremisesCleaned * 100) : 0.0;
      double grade71to80Pct = totalPremisesCleaned > 0 ? (grade71to80 / totalPremisesCleaned * 100) : 0.0;
      double gradeBelow70Pct = totalPremisesCleaned > 0 ? (gradeBelow70 / totalPremisesCleaned * 100) : 0.0;

      return {
        'totalPremisesCleaned': totalPremisesCleaned,
        'manpower': manPowerDeployed,
        'totalAreaCleaned': totalAreaCleaned.toStringAsFixed(2),
        'totalAreaUncleaned': '0',
        'totalForms': snapshot.size,
        'gradeAbove90': gradeAbove90,
        'grade81to90': grade81to90,
        'grade71to80': grade71to80,
        'gradeBelow70': gradeBelow70,
        'gradeAbove90Pct': gradeAbove90Pct.toStringAsFixed(1),
        'grade81to90Pct': grade81to90Pct.toStringAsFixed(1),
        'grade71to80Pct': grade71to80Pct.toStringAsFixed(1),
        'gradeBelow70Pct': gradeBelow70Pct.toStringAsFixed(1),
      };
    } catch (e) {
      print("Error fetching premises stats: $e");
      return {
        'totalPremisesCleaned': 0,
        'manpower': 0,
        'totalAreaCleaned': '0.00',
        'totalAreaUncleaned': '0',
        'totalForms': 0,
        'gradeAbove90': 0,
        'grade81to90': 0,
        'grade71to80': 0,
        'gradeBelow70': 0,
        'gradeAbove90Pct': '0.0',
        'grade81to90Pct': '0.0',
        'grade71to80Pct': '0.0',
        'gradeBelow70Pct': '0.0',
      };
    }
  }


  static Future<Map<String, dynamic>> getCoachCleaningStats({
    required String userRole,
    required String uid,
    String? zone,
    String? division,
    String? depot,
    String? entityId,
    String? contractId,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      final firestore = FirebaseFirestore.instance;
      Query query = firestore.collection('coachForms');

      if (userRole == 'Railway Supervisor') {
        query = query.where('submittedTo.railwayEmployeeId', isEqualTo: uid);
      } else if (userRole == 'Contractor Supervisor') {
        if (entityId != null && entityId.isNotEmpty) {
          query = query.where('submittedByEntityId', isEqualTo: entityId);
        }
      } else if (userRole == 'Railway Admin') {
        if (division != null && division.isNotEmpty) {
          query = query.where('division', isEqualTo: division);
        }
      } else if (userRole == 'Contractor Admin') {
        if (entityId != null && entityId.isNotEmpty) {
          query = query.where('submittedByEntityId', isEqualTo: entityId);
        }
      } else if (userRole == 'Railway Master') {
        if (zone != null && zone.isNotEmpty) {
          query = query.where('zone', isEqualTo: zone);
        }
      } else if (userRole == 'Contractor Master') {
        if (entityId != null && entityId.isNotEmpty) {
          query = query.where('submittedByEntityId', isEqualTo: entityId);
        }
      }

      if (contractId != null && contractId.isNotEmpty) {
        query = query.where('contractId', isEqualTo: contractId);
      }

      final snapshot = await query.get().timeout(const Duration(seconds: 4));

      int totalCoachesCleaned = 0;
      int manPowerDeployed = 0;
      int scored = 0;
      int pending = 0;
      double totalPenalty = 0.0;


      int gradeA = 0;
      int gradeB = 0;
      int gradeC = 0;
      int gradeD = 0;


      int doorsLockingYes = 0;
      int doorsLockingNo = 0;
      int wateringYes = 0;
      int wateringNo = 0;
      int toiletriesYes = 0;
      int toiletriesNo = 0;

      for (var doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final status = data['status'] ?? '';


        if (status == 'LOCKED' || status == 'AUTO-APPROVED') {
          scored++;


          if (data.containsKey('ratingDetails')) {
            final ratingDetails = data['ratingDetails'] as Map<String, dynamic>?;
            if (ratingDetails != null && ratingDetails.containsKey('summary')) {
              final summary = ratingDetails['summary'] as Map<String, dynamic>?;
              if (summary != null) {

                if (summary.containsKey('totalCoaches')) {
                  totalCoachesCleaned += (summary['totalCoaches'] ?? 0) as int;
                }


                if (summary.containsKey('internal')) {
                  final internal = summary['internal'] as Map<String, dynamic>?;
                  if (internal != null) {
                    gradeA += (internal['A'] ?? 0) as int;
                    gradeB += (internal['B'] ?? 0) as int;
                    gradeC += (internal['C'] ?? 0) as int;
                    gradeD += (internal['D'] ?? 0) as int;
                  }
                }


                if (summary.containsKey('doorsLocking')) {
                  final doorsLocking = summary['doorsLocking'] as Map<String, dynamic>?;
                  if (doorsLocking != null) {
                    doorsLockingYes += (doorsLocking['Yes'] ?? 0) as int;
                    doorsLockingNo += (doorsLocking['No'] ?? 0) as int;
                  }
                }


                if (summary.containsKey('watering')) {
                  final watering = summary['watering'] as Map<String, dynamic>?;
                  if (watering != null) {
                    wateringYes += (watering['Yes'] ?? 0) as int;
                    wateringNo += (watering['No'] ?? 0) as int;
                  }
                }


                if (summary.containsKey('toiletries')) {
                  final toiletries = summary['toiletries'] as Map<String, dynamic>?;
                  if (toiletries != null) {
                    toiletriesYes += (toiletries['Yes'] ?? 0) as int;
                    toiletriesNo += (toiletries['No'] ?? 0) as int;
                  }
                }
              }
            }


            if (ratingDetails != null && ratingDetails.containsKey('totalPenalty')) {
              totalPenalty += (ratingDetails['totalPenalty'] ?? 0).toDouble();
            }
          }


          if (data.containsKey('manpower') && data['manpower'] is List) {
            manPowerDeployed += (data['manpower'] as List).length;
          }
        } else if (status == 'SUBMITTED' || status == 'RE-SUBMITTED') {
          pending++;
        }
      }


      final totalGraded = gradeA + gradeB + gradeC + gradeD;
      final gradeAPercent = totalGraded > 0 ? (gradeA / totalGraded * 100).toStringAsFixed(1) : '0.0';
      final gradeBPercent = totalGraded > 0 ? (gradeB / totalGraded * 100).toStringAsFixed(1) : '0.0';
      final gradeCPercent = totalGraded > 0 ? (gradeC / totalGraded * 100).toStringAsFixed(1) : '0.0';
      final gradeDPercent = totalGraded > 0 ? (gradeD / totalGraded * 100).toStringAsFixed(1) : '0.0';

      return {
        'totalCoachesCleaned': totalCoachesCleaned,
        'manpower': manPowerDeployed,
        'scored': scored,
        'pending': pending,
        'totalPenalty': totalPenalty.toStringAsFixed(0),
        'totalForms': snapshot.size,
        'gradeA': gradeA,
        'gradeB': gradeB,
        'gradeC': gradeC,
        'gradeD': gradeD,
        'gradeAPercent': gradeAPercent,
        'gradeBPercent': gradeBPercent,
        'gradeCPercent': gradeCPercent,
        'gradeDPercent': gradeDPercent,
        'doorsLockingYes': doorsLockingYes,
        'doorsLockingNo': doorsLockingNo,
        'wateringYes': wateringYes,
        'wateringNo': wateringNo,
        'toiletriesYes': toiletriesYes,
        'toiletriesNo': toiletriesNo,
      };
    } catch (e) {
      print("Error fetching coach stats: $e");
      return {
        'totalCoachesCleaned': 0,
        'manpower': 0,
        'scored': 0,
        'pending': 0,
        'totalPenalty': '0',
        'totalForms': 0,
        'gradeA': 0,
        'gradeB': 0,
        'gradeC': 0,
        'gradeD': 0,
        'gradeAPercent': '0.0',
        'gradeBPercent': '0.0',
        'gradeCPercent': '0.0',
        'gradeDPercent': '0.0',
        'doorsLockingYes': 0,
        'doorsLockingNo': 0,
        'wateringYes': 0,
        'wateringNo': 0,
        'toiletriesYes': 0,
        'toiletriesNo': 0,
      };
    }
  }

  /// OBHS – summary stats for the Reports > OBHS tab.
  /// Reads run instances from the OBHS API (authoritative `RunInstance`
  /// collection) and derives task counts from each run's task details.
  static Future<Map<String, dynamic>> getOBHSStats({
    String? zone,
    String? division,
  }) async {
    final empty = <String, dynamic>{
      'totalTrains': 0, 'totalInstances': 0, 'activeInstances': 0,
      'pendingInstances': 0, 'closedInstances': 0, 'completedInstances': 0,
      'totalCoaches': 0, 'coachesWithWorkers': 0, 'coachesWithoutWorkers': 0,
      'totalWorkersAssigned': 0, 'jobsCompleted': 0,
    };
    try {
      final runs = await OBHSRepository.getAllRunInstances();
      if (runs.isEmpty) return empty;

      final uniqueTrains = <String>{};
      int active = 0, pending = 0, closed = 0, completed = 0;
      int totalCoaches = 0, coachesWithWorkers = 0, workersAssigned = 0, jobsCompleted = 0;

      for (final run in runs) {
        if ((run.trainNo ?? '').isNotEmpty) uniqueTrains.add(run.trainNo!);
        switch (run.status.toLowerCase()) {
          case 'active':
          case 'ready':
          case 'running':
            active++;
            break;
          case 'pending':
          case 'allocated':
            pending++;
            break;
          case 'closed':
            closed++;
            break;
          case 'completed':
            completed++;
            break;
        }
        for (final c in run.coaches) {
          totalCoaches++;
          final hasWorker = (c.janitorId ?? '').isNotEmpty ||
              (c.attendantId ?? '').isNotEmpty;
          if (hasWorker) {
            coachesWithWorkers++;
            if ((c.janitorId ?? '').isNotEmpty) workersAssigned++;
            if ((c.attendantId ?? '').isNotEmpty) workersAssigned++;
          }
        }
        final runId = run.runInstanceId ?? run.id;
        if (runId != null && runId.isNotEmpty) {
          try {
            final tasks = await OBHSRepository.getRunTasks(runId);
            jobsCompleted += tasks
                .where((t) => (t['status'] ?? '').toString().toLowerCase() == 'completed')
                .length;
          } catch (_) {
            // A single unreadable run must not blank the whole dashboard.
          }
        }
      }

      return <String, dynamic>{
        'totalTrains': uniqueTrains.length,
        'totalInstances': runs.length,
        'activeInstances': active,
        'pendingInstances': pending,
        'closedInstances': closed,
        'completedInstances': completed,
        'totalCoaches': totalCoaches,
        'coachesWithWorkers': coachesWithWorkers,
        'coachesWithoutWorkers': totalCoaches - coachesWithWorkers,
        'totalWorkersAssigned': workersAssigned,
        'jobsCompleted': jobsCompleted,
      };
    } catch (e) {
      print('[FirebaseCountService] getOBHSStats error: $e');
      return empty;
    }
  }

  static Future<Map<String, dynamic>> getFormStatusCounts({
    required String formType,
    String? zone,
    String? division,
    String? entityId,
    String? contractId,
    int? days,
  }) async {
    try {
      final firestore = FirebaseFirestore.instance;
      String collectionName;
      
      if (formType == 'coach') {
        collectionName = 'coachForms';
      } else if (formType == 'premises' || formType == 'premise') {
        collectionName = 'premisesForms';
      } else if (formType == 'cts') {
        collectionName = 'ctsForms';
      } else {
        collectionName = 'cleaningForms';
      }

      Query query = firestore.collection(collectionName);

      if (zone != null && zone.isNotEmpty) {
        query = query.where('submittedByZone', isEqualTo: zone);
      }
      if (division != null && division.isNotEmpty) {
        query = query.where('submittedByDivision', isEqualTo: division);
      }
      if (entityId != null && entityId.isNotEmpty) {
        query = query.where('submittedByEntityId', isEqualTo: entityId);
      }
      if (contractId != null && contractId.isNotEmpty) {
        query = query.where('contractId', isEqualTo: contractId);
      }

      final snapshot = await query.get();
      
      DateTime? minDate;
      if (days != null) {
        final now = DateTime.now();
        minDate = now.subtract(Duration(days: days));
      }

      int total = 0, pending = 0, manpowerApproved = 0, rejected = 0;
      int scoringProgress = 0, autoApproved = 0, locked = 0;

      for (var doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        
        if (minDate != null && data['createdAt'] != null) {
          DateTime createdAt;
          if (data['createdAt'] is Timestamp) {
            createdAt = (data['createdAt'] as Timestamp).toDate();
          } else if (data['createdAt'] is String) {
            createdAt = DateTime.parse(data['createdAt']);
          } else {
            createdAt = DateTime.now();
          }
          if (createdAt.isBefore(minDate)) continue;
        }

        total++;
        final s = (data['status']?.toString() ?? '').toUpperCase().replaceAll('-', '_');
        
        if (['PENDING', 'SUBMITTED', 'RE_SUBMITTED', 'RESUBMITTED', 'DRAFT'].contains(s)) {
          pending++;
        } else if (['APPROVED', 'APPROVED_BY_RAILWAY', 'MANPOWER_APPROVED'].contains(s)) {
          manpowerApproved++;
        } else if (['REJECTED', 'REJECTED_BY_RAILWAY'].contains(s)) {
          rejected++;
        } else if (['SCORING_PROGRESS', 'SCORING_IN_PROGRESS', 'SCORED'].contains(s)) {
          scoringProgress++;
        } else if (['AUTO_APPROVED'].contains(s)) {
          autoApproved++;
        } else if (['LOCKED', 'ACKNOWLEDGED', 'COMPLETED'].contains(s)) {
          locked++;
        }
      }

      return {
        'total': total,
        'pending': pending,
        'manpowerApproved': manpowerApproved,
        'rejected': rejected,
        'scoringProgress': scoringProgress,
        'autoApproved': autoApproved,
        'locked': locked,
      };
    } catch (e) {
      print("Error fetching form status counts: $e");
      return {
        'total': 0, 'pending': 0, 'manpowerApproved': 0, 'rejected': 0,
        'scoringProgress': 0, 'autoApproved': 0, 'locked': 0,
      };
    }
  }
}
