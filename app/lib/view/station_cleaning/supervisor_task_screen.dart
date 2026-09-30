import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import 'package:crm_train/services/api_services.dart';
import 'package:crm_train/repositories/station_cleaning_repository.dart';
import 'package:crm_train/repositories/task_type_repository.dart';
import 'package:crm_train/model/task_type_model.dart';
import 'package:crm_train/repositories/worker_repo.dart';
import 'package:crm_train/helper/api_error_handler.dart';
import 'package:crm_train/helper/app_snackbar.dart';
import 'package:crm_train/helper/location_helper.dart';
import 'package:crm_train/utills/app_colors.dart';
import 'shift_summary_screen.dart';

const List<Map<String, String>> _defaultCleaningActivities = [
  {'name': 'sweeping', 'label': 'Sweeping'},
  {'name': 'mopping', 'label': 'Mopping'},
  {'name': 'washing', 'label': 'Washing'},
  {'name': 'rag_picking', 'label': 'Rag Picking'},
  {'name': 'garbage_collection', 'label': 'Garbage Collection'},
  {'name': 'garbage_disposal', 'label': 'Garbage Disposal'},
  {'name': 'drain_cleaning', 'label': 'Drain Cleaning'},
  {'name': 'consumable_refill', 'label': 'Consumable Refill'},
  {'name': 'cobweb_removal', 'label': 'Cobweb Removal'},
  {'name': 'deep_cleaning', 'label': 'Deep Cleaning'},
];

List<TaskType> get _defaultCleaningActivitiesFallback => _defaultCleaningActivities
    .map((a) => TaskType(
          uid: a['name']!,
          name: a['name']!,
          label: a['label']!,
          createdAt: '',
          updatedAt: '',
        ))
    .toList();

class SupervisorTaskScreen extends StatefulWidget {
  final String stationId;
  final String stationName;
  final String supervisorId;
  final String supervisorName;

  const SupervisorTaskScreen({
    super.key,
    required this.stationId,
    required this.stationName,
    required this.supervisorId,
    required this.supervisorName,
  });

  @override
  State<SupervisorTaskScreen> createState() => _SupervisorTaskScreenState();
}

class _SupervisorTaskScreenState extends State<SupervisorTaskScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = false;
  String? _error;

  // Attendance (3-step: start/mid/end)
  bool _startMarked = false;
  bool _midMarked = false;
  bool _endMarked = false;
  bool _attendanceLoading = false;
  bool _midPromptHandled = false;

  // Tasks
  List<Map<String, dynamic>> _tasks = [];
  String _selectedDate = DateTime.now().toIso8601String().split('T')[0];
  String _taskFilter = 'all';

  // Shift summary status (for the supervisor's own submissions)
  Map<String, dynamic>? _summary;
  bool _summaryLoading = false;

  // Photos
  static const _statusChips = ['all', 'overdue', 'pending', 'assigned', 'in_progress', 'completed', 'approved', 'rejected'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadAll();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() => _isLoading = true);
    await Future.wait([_loadAttendanceStatus(), _loadTasks(), _loadSummary()]);
    setState(() => _isLoading = false);
  }

  /// The shift this supervisor is working on [_selectedDate].
  ///
  /// A supervisor can hold two shifts at the same station on the same date, so
  /// everything about the shift summary (banner, submit gate, resubmit) has to be
  /// scoped to this one — otherwise one shift's summary blocks or replaces the
  /// other shift's.
  String? get _currentShift {
    for (final t in _tasks) {
      final s = (t['shift'] ?? '').toString().trim();
      if (s.isNotEmpty) return s;
    }
    return null;
  }

  String get _summaryStatus => (_summary?['status'] ?? '').toString().toLowerCase();

  /// True once a summary has been sent for this shift: it must never be sent
  /// again unless the railway rejected it.
  bool get _summaryAlreadySent => _summaryStatus == 'submitted' || _summaryStatus == 'approved';

  Future<void> _loadSummary() async {
    try {
      final shift = _currentShift;
      final result = await ApiService.getShiftSummaries(
        stationId: widget.stationId,
        date: _selectedDate,
        supervisorId: widget.supervisorId,
        shift: shift,
      );
      if (!mounted) return;
      var list = result.toList();
      if (shift != null) {
        list = list.where((s) => (s['shift'] ?? '').toString().trim().toLowerCase() == shift.toLowerCase()).toList();
      }
      list.sort((a, b) =>
          ((b['submittedAt'] ?? '') as String).compareTo((a['submittedAt'] ?? '') as String));
      setState(() {
        _summary = list.isEmpty ? null : list.first;
        _summaryLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _summaryLoading = false);
    }
  }

  Future<void> _loadAttendanceStatus() async {
    try {
      final result = await StationCleaningRepository.getStationAttendanceStatus(
        workerId: widget.supervisorId,
      );
      if (result['exists'] == true) {
        setState(() {
          _startMarked = result['isStartMarked'] == true;
          _midMarked = result['isMidMarked'] == true;
          _endMarked = result['isEndMarked'] == true;
        });
      }
    } catch (_) {}
  }

  Future<void> _loadTasks() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      if (token == null) return;

      final uri = Uri.parse('${ApiService.baseUrl}/api/tasks-v2/supervisor/${widget.supervisorId}')
          .replace(queryParameters: {'date': _selectedDate});
      final response = await http.get(
        uri,
        headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        final list = body['tasks'] as List<dynamic>? ?? [];
        setState(() => _tasks = list.cast<Map<String, dynamic>>());
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  List<Map<String, dynamic>> get _filteredTasks {
    var list = _tasks;
    if (_taskFilter == 'overdue') {
      list = list.where((t) => t['isOverdue'] == true).toList();
    } else if (_taskFilter != 'all') {
      list = list.where((t) => t['status'] == _taskFilter).toList();
    }
    list.sort((a, b) => ((a['scheduledTime'] ?? '00:00') as String).compareTo(b['scheduledTime'] ?? '00:00'));
    return list;
  }

  int get _pendingCount => _tasks.where((t) => _taskStatus(t) == 'pending').length;
  int get _overdueCount => _tasks.where(_isTaskOverdue).length;
  int get _inProgressCount => _tasks.where((t) => _taskStatus(t) == 'in_progress').length;
  int get _completedCount => _tasks.where(_isTaskDone).length;

  String _taskStatus(Map<String, dynamic> t) => (t['status'] ?? '').toString().trim().toLowerCase();

  bool _isTaskDone(Map<String, dynamic> t) => const {'completed', 'approved'}.contains(_taskStatus(t));

  /// Overdue = the task's 1h start window closed without it ever being started, or
  /// the backend already flagged it missed. Mirrors the backend isTaskMissed rule
  /// so the mid-attendance ratio, the overdue badge and the summary gate agree.
  bool _isTaskOverdue(Map<String, dynamic> t) {
    if (_taskStatus(t) == 'missed') return true;
    // Only an unstarted task can lapse — once it has been started the supervisor
    // owns it, so it stays in the ratio and keeps blocking the shift.
    return _isTaskWindowClosed(t);
  }

  /// Task the supervisor can still be expected to work on right now: not
  /// cancelled, not already done, not flagged missed, and its start window is
  /// still open. This is the summary gate blocker list — a task leaves it only
  /// once it reaches a terminal state.
  bool _isTaskActionable(Map<String, dynamic> t) {
    final status = _taskStatus(t);
    if (const {'cancelled', 'missed', 'completed', 'approved'}.contains(status)) return false;
    return !_isTaskWindowClosed(t);
  }

  /// Task that counts toward the mid-attendance "half done" denominator:
  /// cancelled, railway-flagged missed, and unstarted window-expired tasks are
  /// excluded because they can never be completed. Completed and approved tasks
  /// ARE counted — they are the progress being measured. Mirrors
  /// getTaskCompletion() in stationCleaningAttendanceService.js so the client
  /// prompt and the server gate agree on the ratio.
  bool _countsTowardMidRatio(Map<String, dynamic> t) {
    final status = _taskStatus(t);
    if (const {'cancelled', 'missed'}.contains(status)) return false;
    return !_isTaskWindowClosed(t);
  }

  /// A task is MISSED/overdue when its 1-hour start window (scheduledTime <= now
  /// < scheduledTime + 1h, IST) elapsed without it ever being started. Mirrors
  /// the backend _isTaskMissed rule in stationCleaningService.js.
  bool _isTaskWindowClosed(Map<String, dynamic> t) {
    final status = _taskStatus(t);
    if (!{'pending', 'assigned', ''}.contains(status)) return false;
    final scheduledDate = (t['scheduledDate'] ?? t['date'] ?? '').toString();
    final scheduledTime = (t['scheduledTime'] ?? '').toString();
    if (scheduledDate.isEmpty || scheduledTime.isEmpty) return false;
    final dm = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(scheduledDate);
    final tm = RegExp(r'^(\d{2}):(\d{2})$').firstMatch(scheduledTime);
    if (dm == null || tm == null) return false;
    final scheduledIST = DateTime.utc(
      int.parse(dm.group(1)!),
      int.parse(dm.group(2)!),
      int.parse(dm.group(3)!),
      int.parse(tm.group(1)!),
      int.parse(tm.group(2)!),
    );
    final nowIST = DateTime.now().toUtc().add(const Duration(milliseconds: 19800000));
    return !nowIST.isBefore(scheduledIST.add(const Duration(hours: 1)));
  }

  // ─── Attendance ──────────────────────────────────────────────────────────

  final _picker = ImagePicker();

  Future<void> _markAttendance(String type) async {
    bool proceed = false;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Liveness Check'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.camera_front, size: 50, color: kRailwayBlue),
            const SizedBox(height: 10),
            const Text(
              'Please take a clear selfie with your face visibly shown.\n\n(Identity is verified by face detection.)',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              proceed = true;
              Navigator.pop(ctx);
            },
            child: const Text('Open Camera'),
          ),
        ],
      ),
    );

    if (!proceed) return;

    final photo = await _picker.pickImage(
      source: ImageSource.camera,
      preferredCameraDevice: CameraDevice.front,
      imageQuality: 80,
      maxWidth: 1280,
    );
    if (photo == null) return;

    setState(() => _attendanceLoading = true);
    try {
      String? imageUrl;
      try {
        imageUrl = await WorkerRepository.uploadMedia(photo.path);
      } catch (_) {
        imageUrl = null;
      }
      if (imageUrl == null || imageUrl.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Photo upload failed. Please try again.'), backgroundColor: kErrorRed),
          );
        }
        return;
      }

      final pos = await captureGps();
      if (pos == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not get GPS. Check location permissions.'), backgroundColor: kWarningOrange),
          );
        }
        return;
      }

      await StationCleaningRepository.markStationAttendance(
        type: type,
        runInstanceId: widget.supervisorId,
        stationId: widget.stationId,
        imageUrl: imageUrl,
        latitude: pos.latitude,
        longitude: pos.longitude,
      );

      setState(() {
        if (type == 'start') _startMarked = true;
        if (type == 'mid') _midMarked = true;
        if (type == 'end') _endMarked = true;
      });

      if (mounted) {
        if (type == 'end') {
          // Nothing to prompt for when this shift's summary has already been sent.
          if (!_summaryAlreadySent) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('Shift ended — submit your photos for critical areas now'),
                backgroundColor: Colors.orange.shade800,
                duration: const Duration(seconds: 4),
                action: SnackBarAction(
                  label: 'SUBMIT',
                  textColor: Colors.white,
                  onPressed: () => _promptShiftSummary(),
                ),
              ),
            );
          }
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${type.toUpperCase()} attendance marked'), backgroundColor: kSuccessGreen),
          );
        }
      }

      if (type == 'end' && mounted && !_summaryAlreadySent) {
        _promptShiftSummary();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Attendance error: $e'), backgroundColor: kErrorRed),
        );
      }
    } finally {
      if (mounted) setState(() => _attendanceLoading = false);
    }
  }

  Future<void> _promptShiftSummary() async {
    await _loadTasks();
    await _loadSummary();

    final existingStatus = _summaryStatus;
    if (existingStatus == 'submitted' || existingStatus == 'approved') {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Your shift summary for this shift is already $existingStatus. It can only be sent again after the railway rejects it.'),
            backgroundColor: kRailwayBlue,
            duration: const Duration(seconds: 4),
          ),
        );
      }
      return;
    }

    // Mid-shift attendance must be marked before the shift can be closed out.
    if (!_midMarked) {
      await _loadAttendanceStatus();
    }
    if (!_midMarked) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Mark your mid-shift attendance (2/3) before submitting the shift summary.'),
            backgroundColor: kWarningOrange,
            duration: const Duration(seconds: 4),
          ),
        );
      }
      return;
    }

    // Gate: only still-workable tasks block the summary submission. Completed,
    // approved, cancelled and overdue/window-closed (missed) tasks never block.
    final blockers = _tasks.where(_isTaskActionable).toList();
    final missedTasks = _tasks.where(_isTaskOverdue).toList();
    if (blockers.isNotEmpty) {
      final uniqAreas = <String>{};
      for (final t in blockers) {
        uniqAreas.add((t['areaName'] ?? 'Unknown area').toString());
      }
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            icon: const Icon(Icons.rule, color: kWarningOrange),
            title: const Text('Pending Tasks Block Submission'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${blockers.length} task(s) are still pending or in progress for this shift. '
                    'Please complete or resolve them before submitting the shift summary.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    uniqAreas.take(10).join('\n'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  if (uniqAreas.length > 10)
                    const SizedBox(height: 6),
                  if (uniqAreas.length > 10)
                    Text('... and ${uniqAreas.length - 10} more', style: const TextStyle(fontSize: 12)),
                  if (missedTasks.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      '${missedTasks.length} task(s) were missed (start window lapsed) and will not block submission.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 12, color: kWarningOrange),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
      return;
    }

    final doneStatuses = {'completed', 'approved'};
    final areaMap = <String, Map<String, dynamic>>{};
    for (final t in _tasks) {
      if (!doneStatuses.contains((t['status'] ?? '').toString().toLowerCase())) continue;
      final areaId = (t['areaId'] ?? '').toString();
      if (areaId.isEmpty) continue;
      final key = '${t['uid'] ?? areaId}_$areaId';
      areaMap[key] = {
        'key': key,
        'areaId': areaId,
        'areaName': t['areaName'] ?? '',
        'mainArea': t['mainArea'] ?? '',
        'basicAreaSqFt': t['basicAreaSqFt'] ?? 0,
        'boqTimesPerPeriod': t['boqTimesPerPeriod'] ?? 1,
        'cleaningFrequency': t['cleaningFrequency'] ?? 'daily',
        'activityType': t['activityType'] ?? t['taskTypeName'] ?? '',
        'scheduledTime': t['scheduledTime'] ?? '',
        'taskId': t['uid'],
        'afterPhotoUrl': t['afterPhoto'] ?? '',
        'taskRemarks': t['remarks'] ?? '',
        'gpsLat': t['gpsLat'],
        'gpsLng': t['gpsLng'],
        'times': 1,
      };
    }
    final areas = areaMap.values.toList();

    if (areas.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No completed tasks found. Complete tasks before submitting shift summary.'),
            backgroundColor: kWarningOrange,
          ),
        );
      }
      return;
    }

    final primaryShift = _currentShift ?? (_tasks.isNotEmpty ? (_tasks.first['shift']?.toString() ?? 'Morning') : 'Morning');

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => WillPopScope(
        onWillPop: () async => false,
        child: AlertDialog(
          icon: const Icon(Icons.camera_alt, size: 48, color: Colors.orange),
          title: const Text('Shift Summary Required'),
          content: Text(
            missedTasks.isEmpty
                ? 'You have $areas.length completed area(s). Submit your shift summary with photos to complete your shift.'
                : 'You have $areas.length completed area(s) and ${missedTasks.length} missed task(s). Submit your shift summary with photos to complete your shift.',
            textAlign: TextAlign.center,
          ),
          actions: [
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(ctx);
                final submitted = await Navigator.push<bool>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ShiftSummaryScreen(
                      stationId: widget.stationId,
                      stationName: widget.stationName,
                      supervisorId: widget.supervisorId,
                      supervisorName: widget.supervisorName,
                      shift: primaryShift,
                      date: _selectedDate,
                      areas: areas,
                      missedCount: missedTasks.length,
                    ),
                  ),
                );
                if (submitted == true && mounted) {
                  // Submitting the shift summary auto-marks END attendance.
                  setState(() => _endMarked = true);
                  _loadAttendanceStatus();
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: kRailwayBlue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              child: const Text('Submit Photos'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openResubmit() async {
    final stored = _summary;
    if (stored == null) return;
    final existingUid = (stored['uid'] ?? stored['id'] ?? '').toString();
    if (existingUid.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not find the rejected shift summary. Pull to refresh and try again.'),
            backgroundColor: kErrorRed,
          ),
        );
      }
      return;
    }
    final rawAreas = (stored['areas'] as List?) ?? [];
    final areas = rawAreas.cast<Map<String, dynamic>>();
    final primaryShift = (stored['shift'] ?? 'Morning').toString();
    // Resubmit the very summary that was rejected, not whatever shift is on screen.
    final summaryDate = (stored['date'] ?? _selectedDate).toString();

    if (areas.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No previous summary areas found to resubmit.'),
            backgroundColor: kWarningOrange,
          ),
        );
      }
      return;
    }

    if (!mounted) return;
    final resubmitted = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ShiftSummaryScreen(
          stationId: widget.stationId,
          stationName: widget.stationName,
          supervisorId: widget.supervisorId,
          supervisorName: widget.supervisorName,
          shift: primaryShift,
          date: summaryDate,
          areas: areas,
          existingSummaryUid: existingUid,
          rejectionReason: (stored['rejectionReason'] ?? '').toString(),
          missedCount: _tasks.where(_isTaskOverdue).length,
        ),
      ),
    );
    if (resubmitted == true && mounted) {
      setState(() => _endMarked = true);
      _loadAttendanceStatus();
      _loadSummary();
    }
  }

  // ─── Task Assignment ─────────────────────────────────────────────────────

  // Ratio tasks = cancelled / railway-flagged missed / unstarted window-expired
  // tasks are dropped; everything else counts, including completed tasks. This
  // matches the backend getTaskCompletion() denominator exactly.
  int get _workableTaskCount => _tasks.where(_countsTowardMidRatio).length;

  bool get _hasCompletedHalf => _workableTaskCount > 0 && _completedCount >= (_workableTaskCount / 2).ceil();

  Future<void> _handleComplete(Map<String, dynamic> t) async {
    // Half the ratio tasks are already done before this one was completed (the
    // screen was resumed, or the previous prompt was dismissed). Ask once here so
    // mid attendance is not silently skipped; _midPromptHandled stops a second
    // prompt in _showCompleteSheet's onDone.
    if (!_midMarked && !_midPromptHandled && _hasCompletedHalf) {
      await _promptMidAttendance();
      if (!mounted) return;
    }
    _showCompleteSheet(t['uid'] ?? t['id']);
  }

  Future<void> _promptMidAttendance() async {
    if (!mounted || _midPromptHandled) return;
    _midPromptHandled = true;
    final markNow = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.pause_circle, color: kWarningOrange, size: 40),
        title: const Text('Mark Mid Attendance'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'You have completed $_completedCount of $_workableTaskCount task(s) for this shift. '
              'Mark your Mid attendance before finishing the remaining work.',
              textAlign: TextAlign.center,
            ),
            if (_overdueCount > 0) ...[
              const SizedBox(height: 8),
              Text(
                '$_overdueCount overdue task(s) whose start window closed are not counted.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: kWarningOrange),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Later'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: kWarningOrange, foregroundColor: Colors.white),
            child: const Text('Mark Mid Attendance'),
          ),
        ],
      ),
    );
    if (markNow == true && mounted) await _markAttendance('mid');
  }

  // ─── Task Execution ──────────────────────────────────────────────────────

  String? _startingTaskId;

  Future<void> _startTask(String taskId, [Map<String, dynamic>? task]) async {
    if (!_startMarked) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Mark start attendance first'), backgroundColor: kWarningOrange),
      );
      return;
    }

    if (task != null && !_canStartTask(task)) {
      final expired = _startWindowExpired(task);
      AppSnackbar.showInfo(
        context,
        expired
            ? 'The task start window has expired. This task could only be started within 1 hour of its scheduled time.'
            : 'This task cannot be started yet. You can start it at the scheduled time.',
      );
      return;
    }

    if (_startingTaskId == taskId) return;
    setState(() => _startingTaskId = taskId);

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      if (token == null) return;

      double? lat, lng;
      final fix = await captureGps();
      lat = fix?.latitude;
      lng = fix?.longitude;

      final body = <String, dynamic>{};
      if (lat != null) { body['gpsLat'] = lat; body['gpsLng'] = lng; }

      final response = await http.post(
        Uri.parse('${ApiService.baseUrl}/api/tasks-v2/$taskId/start'),
        headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Task started'), backgroundColor: kSuccessGreen));
        _loadTasks();
      } else {
        throw Exception(ApiErrorHandler.getErrorMessage(response.body, response.statusCode));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: kErrorRed));
      }
    } finally {
      if (mounted && _startingTaskId == taskId) setState(() => _startingTaskId = null);
    }
  }

  DateTime? _parseTaskISTDateTime(Map<String, dynamic> t) {
    final sDate = (t['scheduledDate'] ?? t['date'] ?? '').toString();
    final sTime = (t['scheduledTime'] ?? '').toString();
    final dm = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(sDate);
    final tm = RegExp(r'^(\d{2}):(\d{2})$').firstMatch(sTime);
    if (dm == null || tm == null) return null;
    return DateTime.utc(int.parse(dm.group(1)!), int.parse(dm.group(2)!), int.parse(dm.group(3)!),
        int.parse(tm.group(1)!), int.parse(tm.group(2)!));
  }

  DateTime get _nowIST => DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30));

  bool _canStartTask(Map<String, dynamic> t) {
    final scheduled = _parseTaskISTDateTime(t);
    if (scheduled == null) return true;
    final now = _nowIST;
    final windowEnd = scheduled.add(const Duration(hours: 1));
    return !now.isBefore(scheduled) && now.isBefore(windowEnd);
  }

  bool _startWindowExpired(Map<String, dynamic> t) {
    final scheduled = _parseTaskISTDateTime(t);
    if (scheduled == null) return false;
    return !_nowIST.isBefore(scheduled.add(const Duration(hours: 1)));
  }

  String _fmt12(int hour, int minute) {
    final h = hour % 12 == 0 ? 12 : hour % 12;
    final min = minute.toString().padLeft(2, '0');
    final ampm = hour >= 12 ? 'PM' : 'AM';
    return '$h:$min $ampm';
  }

  String _startWindowLabel(Map<String, dynamic> t) {
    final scheduled = _parseTaskISTDateTime(t);
    if (scheduled == null) return '';
    final end = scheduled.add(const Duration(hours: 1));
    return '${_fmt12(scheduled.hour, scheduled.minute)} – ${_fmt12(end.hour, end.minute)}';
  }

  Widget _startButton(BuildContext context, Map<String, dynamic> t) {
    if (_startWindowExpired(t)) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Task Start Window Expired',
            style: TextStyle(fontSize: 11, color: kErrorRed, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          ElevatedButton.icon(
            onPressed: null,
            icon: const Icon(Icons.lock_clock, size: 16),
            label: const Text('Start'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.grey.shade300, foregroundColor: Colors.grey.shade600),
          ),
        ],
      );
    }
    if (!_canStartTask(t)) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Available at ${_fmt12(_parseTaskISTDateTime(t)!.hour, _parseTaskISTDateTime(t)!.minute)} · Window ${_startWindowLabel(t)}',
            style: const TextStyle(fontSize: 11, color: Color(0xFF1565C0), fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          ElevatedButton.icon(
            onPressed: null,
            icon: const Icon(Icons.lock_clock, size: 16),
            label: const Text('Start'),
          ),
        ],
      );
    }
    final isStarting = _startingTaskId == taskIdOf(t);
    return ElevatedButton.icon(
      icon: isStarting
          ? const SizedBox(height: 14, width: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
          : const Icon(Icons.play_arrow, size: 16),
      label: Text(isStarting ? 'Starting...' : 'Start'),
      onPressed: isStarting ? null : () => _startTask(taskIdOf(t), t),
    );
  }

  String taskIdOf(Map<String, dynamic> t) => t['uid'] ?? t['id'];

  void _showCompleteSheet(String taskId) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SupervisorTaskExecutionSheet(
        taskId: taskId,
        mode: 'complete',
        onDone: () async {
          await _loadTasks();
          if (mounted) Navigator.pop(context);
          // Ask for mid attendance as soon as the half mark is crossed, rather
          // than waiting for the supervisor to tap the next complete button.
          // _midPromptHandled keeps it to one prompt per shift.
          if (mounted && !_midMarked && !_midPromptHandled && _hasCompletedHalf) {
            await _promptMidAttendance();
          }
        },
      ),
    );
  }

  void _showResubmitSheet(String taskId) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SupervisorTaskExecutionSheet(
        taskId: taskId,
        mode: 'resubmit',
        onDone: () async {
          await _loadTasks();
          if (mounted) Navigator.pop(context);
        },
      ),
    );
  }

  // ─── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.stationName} Tasks', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: kRailwayBlue,
        iconTheme: const IconThemeData(color: Colors.white),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: [
            const Tab(icon: Icon(Icons.fingerprint), text: 'Attendance'),
            Tab(icon: const Icon(Icons.cleaning_services), text: 'Tasks ($_pendingCount)'),
          ],
        ),
      ),
      body: Column(
        children: [
          if (_summary != null) _summaryStatusBanner(),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildAttendanceTab(),
                _buildTasksTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryStatusBanner() {
    final status = (_summary?['status'] ?? '').toString().toLowerCase();
    final Color bg;
    final Color fg;
    final IconData icon;
    final String text;
    switch (status) {
      case 'approved':
        bg = kSuccessGreen;
        fg = Colors.white;
        icon = Icons.verified_user;
        text = 'Shift summary approved for ${widget.stationName}';
        break;
      case 'rejected':
        bg = kErrorRed;
        fg = Colors.white;
        icon = Icons.error_outline;
        text = 'Shift summary rejected — please resubmit';
        break;
      default:
        bg = kRailwayBlue;
        fg = Colors.white;
        icon = Icons.schedule;
        text = 'Shift summary submitted — awaiting railway approval';
    }
    return Container(
      width: double.infinity,
      color: bg,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: fg, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: TextStyle(color: fg, fontWeight: FontWeight.w600, fontSize: 12)),
          ),
          if (status == 'rejected')
            TextButton(
              onPressed: _summaryLoading ? null : _openResubmit,
              style: TextButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: kErrorRed,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              ),
              child: const Text('Resubmit', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
        ],
      ),
    );
  }

  // ─── Attendance Tab ──────────────────────────────────────────────────────

  Widget _buildAttendanceTab() {
    return RefreshIndicator(
      onRefresh: () => _loadAttendanceStatus(),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Icon(Icons.fingerprint, size: 64, color: kRailwayBlue.withValues(alpha: 0.3)),
          const SizedBox(height: 8),
          Text('Mark Your Attendance', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
          const SizedBox(height: 4),
          Text(widget.supervisorName, style: TextStyle(color: Colors.grey[600]), textAlign: TextAlign.center),
          const SizedBox(height: 24),
          _attendanceCard(
            step: 'Start (1/3)',
            icon: Icons.login,
            marked: _startMarked,
            onMark: () => _markAttendance('start'),
            description: 'Mark shift start — take a selfie',
            unlocked: !_startMarked,
          ),
          const SizedBox(height: 12),
          _attendanceCard(
            step: 'Mid (2/3)',
            icon: Icons.pause_circle,
            marked: _midMarked,
            onMark: () => _markAttendance('mid'),
            description: 'Mark mid-shift check',
            unlocked: _startMarked && !_midMarked,
          ),
          const SizedBox(height: 12),
          _attendanceCard(
            step: 'End (3/3)',
            icon: Icons.logout,
            marked: _endMarked,
            onMark: () => _markAttendance('end'),
            description: _endMarked
                ? 'Auto-marked on shift summary submission'
                : 'Auto-marked when you submit the shift summary',
            unlocked: _startMarked && !_endMarked,
          ),
          const SizedBox(height: 24),
          if (_startMarked)
            SizedBox(
              width: double.infinity,
              child: _summaryAlreadySent
                  ? ElevatedButton.icon(
                      icon: const Icon(Icons.verified, size: 18),
                      label: Text(
                        _summaryStatus == 'approved'
                            ? 'Shift summary approved'
                            : 'Shift summary submitted — awaiting approval',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      onPressed: null,
                      style: ElevatedButton.styleFrom(
                        disabledBackgroundColor: kSuccessGreen.withValues(alpha: 0.35),
                        disabledForegroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    )
                  : ElevatedButton.icon(
                      icon: const Icon(Icons.camera_alt, size: 18),
                      label: Text(
                        _summaryStatus == 'rejected'
                            ? 'Resubmit Shift Summary (rejected)'
                            : 'Submit Shift Summary (auto-marks End)',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      onPressed: () => _summaryStatus == 'rejected' ? _openResubmit() : _promptShiftSummary(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _summaryStatus == 'rejected' ? kErrorRed : Colors.orange.shade800,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
            ),
        ],
      ),
    );
  }

  Widget _attendanceCard({
    required String step,
    required IconData icon,
    required bool marked,
    required VoidCallback onMark,
    required String description,
    required bool unlocked,
  }) {
    return Card(
      elevation: marked ? 1 : 2,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: marked ? kSuccessGreen : (unlocked ? kRailwayBlue : Colors.grey[300]),
          child: Icon(marked ? Icons.check : icon, color: Colors.white),
        ),
        title: Text('$step Attendance', style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(marked ? 'Completed' : description),
        trailing: _attendanceTrailing(marked, unlocked, onMark),
      ),
    );
  }

  Widget _attendanceTrailing(bool marked, bool unlocked, VoidCallback onMark) {
    if (_attendanceLoading) {
      return const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (marked) {
      return const Icon(Icons.check_circle, color: kSuccessGreen);
    }
    if (unlocked) {
      return ElevatedButton(
        onPressed: onMark,
        style: ElevatedButton.styleFrom(backgroundColor: kRailwayBlue, foregroundColor: Colors.white),
        child: const Text('Mark'),
      );
    }
    return const Text('');
  }

  // ─── Tasks Tab ───────────────────────────────────────────────────────────

  Widget _buildTasksTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: DateTime.parse(_selectedDate),
                      firstDate: DateTime(2024),
                      lastDate: DateTime(2030),
                    );
                    if (picked != null) {
                      setState(() => _selectedDate = picked.toIso8601String().split('T')[0]);
                      _loadTasks();
                    }
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(labelText: 'Date', prefixIcon: Icon(Icons.calendar_today)),
                    child: Text(_selectedDate),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(icon: const Icon(Icons.refresh), onPressed: _loadTasks),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Text('Pending: $_pendingCount  |  In Progress: $_inProgressCount  |  Overdue: $_overdueCount  |  Done: $_completedCount',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600])),
            ],
          ),
        ),
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            children: _statusChips.map((s) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: FilterChip(
                label: Text(s.replaceAll('_', ' ')),
                selected: _taskFilter == s,
                onSelected: (v) => setState(() => _taskFilter = s),
              ),
            )).toList(),
          ),
        ),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(child: Text('Error: $_error'))
                  : _filteredTasks.isEmpty
                      ? const Center(child: Text('No tasks for this date'))
                      : RefreshIndicator(
                          onRefresh: _loadTasks,
                          child: ListView.builder(
                            itemCount: _filteredTasks.length,
                            itemBuilder: (ctx, i) {
                              final t = _filteredTasks[i];
                              return _buildTaskCard(t);
                            },
                          ),
                        ),
        ),
      ],
    );
  }

  Widget _buildTaskCard(Map<String, dynamic> t) {
    final status = t['status'] ?? 'pending';
    final isOverdue = t['isOverdue'] == true;
    final areaName = t['areaName'] ?? '';
    final rawActivities = t['taskActivities'];
    final activityName = (rawActivities is List && rawActivities.isNotEmpty)
        ? (rawActivities.map((a) => (a is Map && a['label'] != null && a['label'].toString().isNotEmpty) ? a['label'] : (a is Map ? a['name'] ?? a['label'] ?? '' : a.toString())).toList().join(', '))
        : t['activityType'] ?? t['taskTypeName'] ?? 'Cleaning';
    final time = t['scheduledTime'] ?? '--:--';
    final workerName = t['workerName'] ?? '';
    final taskId = t['uid'] ?? t['id'];
    final rejectionReason = t['rejectionReason'];

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      shape: isOverdue
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: kErrorRed, width: 1.5),
            )
          : null,
      child: ExpansionTile(
        leading: Icon(isOverdue ? Icons.error : _statusIcon(status), color: isOverdue ? kErrorRed : _statusColor(status), size: 28),
        title: Text('$time - $activityName',
            style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14)),
        subtitle: Text(
          '${areaName.isNotEmpty ? areaName : 'Area'}'
          '${isOverdue ? ' | Overdue' : ''}'
          '${workerName.isNotEmpty ? ' | $workerName' : ''}',
          style: TextStyle(fontSize: 12, color: isOverdue ? kErrorRed : _statusColor(status)),
        ),
        children: [
          if (isOverdue)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: kErrorRed.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Icon(Icons.warning_amber, color: kErrorRed, size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Overdue — you missed the time of cleaning',
                      style: TextStyle(color: kErrorRed, fontWeight: FontWeight.w600, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          if (rejectionReason != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text('Rejection: $rejectionReason', style: const TextStyle(color: Colors.red, fontSize: 12)),
            ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                if (status == 'pending')
                  _startButton(context, t),
                if (status == 'in_progress')
                  ElevatedButton.icon(
                    icon: const Icon(Icons.check, size: 16),
                    label: const Text('Complete'),
                    onPressed: () => _handleComplete(t),
                  ),
                if (status == 'rejected')
                  ElevatedButton.icon(
                    icon: const Icon(Icons.replay, size: 16),
                    label: const Text('Resubmit'),
                    onPressed: () => _showResubmitSheet(taskId),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── Assign Tab removed: supervisor performs tasks manually ──────────────

  Color _statusColor(String status) {
    switch (status) {
      case 'pending': return Colors.orange;
      case 'assigned': return Colors.blue;
      case 'in_progress': return Colors.amber.shade700;
      case 'completed': return Colors.green;
      case 'approved': return Colors.teal;
      case 'rejected': return Colors.red;
      case 'resubmitted': return Colors.purple;
      default: return Colors.grey;
    }
  }

  IconData _statusIcon(String status) {
    switch (status) {
      case 'pending': return Icons.schedule;
      case 'in_progress': return Icons.cleaning_services;
      case 'completed': return Icons.check_circle_outline;
      case 'approved': return Icons.verified;
      case 'rejected': return Icons.cancel;
      case 'resubmitted': return Icons.replay;
      default: return Icons.circle;
    }
  }
}

// ─── Supervisor Task Execution Sheet ───────────────────────────────────────

class _SupervisorTaskExecutionSheet extends StatefulWidget {
  final String taskId;
  final String mode;
  final VoidCallback onDone;

  const _SupervisorTaskExecutionSheet({
    required this.taskId,
    required this.mode,
    required this.onDone,
  });

  @override
  State<_SupervisorTaskExecutionSheet> createState() => _SupervisorTaskExecutionSheetState();
}

class _SupervisorTaskExecutionSheetState extends State<_SupervisorTaskExecutionSheet> {
  final TextEditingController _commentCtrl = TextEditingController();
  final TextEditingController _scoreCtrl = TextEditingController();
  bool isSubmitting = false;
  List<Map<String, dynamic>>? _selectedActivities;
  List<TaskType> _activityOptions = _defaultCleaningActivitiesFallback;
  bool _loadingActivities = true;

  @override
  void initState() {
    super.initState();
    _loadActivities();
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    _scoreCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadActivities() async {
    try {
      final loaded = await TaskTypeRepository.list(category: 'cleaning', isActive: true);
      if (mounted && loaded.isNotEmpty) {
        setState(() => _activityOptions = loaded);
      }
    } catch (_) {}
    if (mounted) setState(() => _loadingActivities = false);
  }

  Future<void> _pickActivities() async {
    // Make sure the list is in hand *before* the sheet opens. The sheet used to
    // render from the parent's state, which cannot rebuild a modal bottom sheet
    // once it is showing - a slow first load left the spinner running until the
    // sheet was closed and reopened.
    if (_loadingActivities) {
      await _loadActivities();
    }
    if (!mounted) return;

    final selected = <String>{};
    for (final a in (_selectedActivities ?? [])) {
      final id = a['uid']?.toString() ?? '';
      if (id.isNotEmpty) selected.add(id);
    }
    final options = List<TaskType>.from(_activityOptions);
    final picked = await showModalBottomSheet<Map<String, dynamic>?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (sheetCtx, setSheetState) {
            return Container(
              height: MediaQuery.of(sheetCtx).size.height * 0.72,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              ),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.cleaning_services, color: kRailwayBlue),
                      const SizedBox(width: 8),
                      const Text('Select Activities', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(sheetCtx, null),
                      ),
                    ],
                  ),
                  const Text(
                    'Choose the activities performed for this task before completing. You can pick more than one.',
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: options.isEmpty
                        ? const Center(
                            child: Text('No activities available', style: TextStyle(color: Colors.black54)),
                          )
                        : ListView(
                            children: options.map((tt) {
                              return CheckboxListTile(
                                dense: true,
                                controlAffinity: ListTileControlAffinity.leading,
                                title: Text(tt.label.isNotEmpty ? tt.label : tt.name, style: const TextStyle(fontSize: 14)),
                                value: selected.contains(tt.uid),
                                onChanged: (v) => setSheetState(() {
                                  if (v == true) {
                                    selected.add(tt.uid);
                                  } else {
                                    selected.remove(tt.uid);
                                  }
                                }),
                              );
                            }).toList(),
                          ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.check),
                      label: Text('Confirm Activities${selected.isEmpty ? '' : ' (${selected.length})'}'),
                      onPressed: selected.isEmpty
                          ? null
                          : () {
                              final pickedList = options
                                  .where((tt) => selected.contains(tt.uid))
                                  .map((tt) => {'uid': tt.uid, 'name': tt.name, 'label': tt.label})
                                  .toList();
                              Navigator.pop(sheetCtx, {'activities': pickedList});
                            },
                      style: ElevatedButton.styleFrom(backgroundColor: kSuccessGreen, foregroundColor: Colors.white),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
    if (picked == null || picked['activities'] == null) return;
    final list = (picked['activities'] as List).cast<Map<String, dynamic>>();
    setState(() => _selectedActivities = list);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.mode == 'complete' ? 'Complete Task' : 'Resubmit Task',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                    ),
                  ),
                  IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
                ],
              ),
              const SizedBox(height: 16),
              const Text('Choose Activity (required)', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              const SizedBox(height: 12),
              InkWell(
                onTap: _pickActivities,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border.all(color: _selectedActivities == null || _selectedActivities!.isEmpty ? Colors.orange : kSuccessGreen),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _selectedActivities == null || _selectedActivities!.isEmpty
                            ? Icons.add_circle_outline
                            : Icons.check_circle,
                        color: _selectedActivities == null || _selectedActivities!.isEmpty ? kWarningOrange : kSuccessGreen,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          (_selectedActivities == null || _selectedActivities!.isEmpty)
                              ? 'Tap to select activity'
                              : _selectedActivities!.map((a) => a['label'] ?? a['name'] ?? '').join(', '),
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text('Remark the location', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              const SizedBox(height: 12),
              TextField(
                controller: _commentCtrl,
                minLines: 3,
                maxLines: 4,
                decoration: InputDecoration(
                  hintText: 'Enter remarks (optional)...',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  contentPadding: const EdgeInsets.all(12),
                ),
              ),
              const SizedBox(height: 20),
              const Text('Grade the cleaning done (optional)', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              const SizedBox(height: 8),
              TextField(
                controller: _scoreCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                maxLength: 3,
                decoration: InputDecoration(
                  hintText: 'Enter score 0 - 100',
                  counterText: '',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  contentPadding: const EdgeInsets.all(12),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: ((_selectedActivities != null && _selectedActivities!.isNotEmpty) && !isSubmitting) ? _submit : null,
                  style: ElevatedButton.styleFrom(backgroundColor: kRailwayBlue, foregroundColor: Colors.white),
                  child: Text(isSubmitting ? 'Submitting...' : (widget.mode == 'complete' ? 'Complete Task' : 'Resubmit Task')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    setState(() => isSubmitting = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      if (token == null) throw Exception('AUTH_ERROR');

      double? lat, lng;
      final fix = await captureGps();
      lat = fix?.latitude;
      lng = fix?.longitude;

      final body = <String, dynamic>{
        'remarks': _commentCtrl.text.trim(),
        'activities': _selectedActivities?.map((a) => {
          'id': a['uid'],
          'name': a['name'],
          'label': a['label'],
        }).toList() ?? [],
      };
      final scoreText = _scoreCtrl.text.trim();
      if (scoreText.isNotEmpty) {
        final score = int.tryParse(scoreText);
        if (score == null || score < 0 || score > 100) {
          if (mounted) {
            AppSnackbar.showInfo(context, 'Please enter a valid score between 0 and 100.');
            setState(() => isSubmitting = false);
          }
          return;
        }
        body['score'] = score;
      }
      if (lat != null) { body['gpsLat'] = lat; body['gpsLng'] = lng; }

      final endpoint = widget.mode == 'complete' ? 'complete' : 'resubmit';
      final response = await http.post(
        Uri.parse('${ApiService.baseUrl}/api/tasks-v2/${widget.taskId}/$endpoint'),
        headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.mode == 'complete' ? 'Task completed!' : 'Task resubmitted'),
            backgroundColor: kSuccessGreen,
          ),
        );
        widget.onDone();
      } else {
        throw Exception(ApiErrorHandler.getErrorMessage(response.body, response.statusCode));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceAll('Exception: ', '')), backgroundColor: kErrorRed),
      );
    } finally {
      if (mounted) setState(() => isSubmitting = false);
    }
  }
}
