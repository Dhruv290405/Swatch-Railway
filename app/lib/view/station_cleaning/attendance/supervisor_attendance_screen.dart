import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:crm_train/model/station_run_model.dart';
import 'package:crm_train/repositories/station_attendance_repository.dart';
import 'package:crm_train/repositories/station_cleaning_repository.dart';
import 'package:crm_train/repositories/worker_repo.dart';
import 'package:crm_train/utills/app_colors.dart';

class SupervisorAttendanceScreen extends StatefulWidget {
  final String stationId;
  final String stationName;
  final String supervisorId;
  final String supervisorName;

  const SupervisorAttendanceScreen({
    super.key,
    required this.stationId,
    required this.stationName,
    required this.supervisorId,
    required this.supervisorName,
  });

  @override
  State<SupervisorAttendanceScreen> createState() =>
      _SupervisorAttendanceScreenState();
}

class _SupervisorAttendanceScreenState extends State<SupervisorAttendanceScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  final _picker = ImagePicker();

  String? _runInstanceId;
  String _shift = 'morning';
  bool _statusLoading = true;
  bool _isStartMarked = false;
  bool _isMidMarked = false;
  bool _isEndMarked = false;
  String _attendanceStatus = 'PENDING';
  String _identityAuditStatus = '';

  bool _selfSubmitting = false;

  List<Map<String, dynamic>> _workers = [];
  bool _workersLoading = false;
  final Map<String, String> _workerStatus = {};
  final Map<String, String> _workerReasons = {};
  bool _bulkSubmitting = false;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _resolveRunAndStatus();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _resolveRunAndStatus() async {
    setState(() => _statusLoading = true);
    try {
      final runsRes =
          await StationCleaningRepository.getSupervisorRuns(widget.supervisorId);
      final raw = runsRes['data'] as List? ?? [];
      final runs = raw
          .map<StationCleaningRunModel>(
              (e) => StationCleaningRunModel.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      final today = DateTime.now().toIso8601String().split('T')[0];
      StationCleaningRunModel? todayRun;
      try {
        todayRun = runs.firstWhere((r) =>
            r.date == today &&
            ['scheduled', 'in progress', 'active'].contains(r.status.toLowerCase()));
      } catch (_) {
        try {
          todayRun = runs.firstWhere((r) => r.date == today);
        } catch (_) {
          todayRun = runs.isNotEmpty ? runs.first : null;
        }
      }
      if (todayRun != null) {
        _runInstanceId = todayRun.runInstanceId.isEmpty ? null : todayRun.runInstanceId;
        if (todayRun.shift.isNotEmpty) _shift = todayRun.shift;
      }
    } catch (e) {
      debugPrint('Resolve run failed: $e');
    }
    await _refreshStatus();
    if (mounted) setState(() => _statusLoading = false);
  }

  Future<void> _refreshStatus() async {
    try {
      final res = await StationCleaningRepository.getStationAttendanceStatus(
          workerId: widget.supervisorId);
      setState(() {
        _isStartMarked = res['isStartMarked'] == true;
        _isMidMarked = res['isMidMarked'] == true;
        _isEndMarked = res['isEndMarked'] == true;
        _attendanceStatus =
            res['attendanceStatus']?.toString() ?? _attendanceStatus;
        _identityAuditStatus = res['identityAuditStatus']?.toString() ?? '';
      });
    } catch (e) {
      debugPrint('Status refresh failed: $e');
    }
  }

  Future<Position?> _captureGps() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return null;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }

      try {
        return await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.medium,
          timeLimit: const Duration(seconds: 20),
        );
      } catch (e) {
        try {
          final lastKnown = await Geolocator.getLastKnownPosition();
          if (lastKnown != null) return lastKnown;
        } catch (_) {}

        try {
          return await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.low,
            timeLimit: const Duration(seconds: 15),
          );
        } catch (e2) {
          return Position(
            longitude: 0.0,
            latitude: 0.0,
            timestamp: DateTime.now(),
            accuracy: 0.0,
            altitude: 0.0,
            heading: 0.0,
            speed: 0.0,
            speedAccuracy: 0.0,
            altitudeAccuracy: 0.0,
            headingAccuracy: 0.0,
          );
        }
      }
    } catch (_) {
      return null;
    }
  }

  Future<bool> _livenessDialog() async {
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
            Text(
              'Please take a clear selfie with your face visibly shown.\n\n(Identity is verified by face detection.)',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
    return proceed;
  }

  Future<bool> _submitSelfAttendance(String type) async {
    final proceed = await _livenessDialog();
    if (!proceed) return false;

    File? photo;
    try {
      final picked = await _picker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.front,
        imageQuality: 80,
        maxWidth: 1280,
      );
      if (picked == null) return false;
      photo = File(picked.path);
    } catch (_) {
      return false;
    }

    final position = await _captureGps();
    if (position == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not get GPS. Check location permissions.'),
            backgroundColor: kWarningOrange,
          ),
        );
      }
      return false;
    }

    setState(() => _selfSubmitting = true);
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
            const SnackBar(
              content: Text('Photo upload failed. Please try again.'),
              backgroundColor: kErrorRed,
            ),
          );
        }
        return false;
      }

      final response = await StationCleaningRepository.markStationAttendance(
        type: type,
        runInstanceId: _runInstanceId ?? '',
        stationId: widget.stationId,
        imageUrl: imageUrl,
        latitude: position.latitude,
        longitude: position.longitude,
      ).timeout(
        const Duration(seconds: 40),
        onTimeout: () => throw Exception(
            'Attendance server timeout. Please check your internet and try again.'),
      );

      final responseMessage =
          response['message']?.toString() ?? response['error']?.toString() ?? '';
      final isAlready = responseMessage.toLowerCase().contains('already') &&
          responseMessage.toLowerCase().contains('submitted');
      final isSuccess = response['success'] == true || responseMessage.isNotEmpty;

      if (isSuccess && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isAlready
                ? responseMessage
                : '${type.toUpperCase()} attendance marked successfully'),
            backgroundColor: isAlready ? kWarningOrange : kSuccessGreen,
          ),
        );
        await _refreshStatus();
        return true;
      }
    } catch (e) {
      final msg = e.toString().replaceAll('Exception: ', '');
      final isAlready =
          msg.toLowerCase().contains('already') && msg.toLowerCase().contains('submitted');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isAlready ? msg : 'Error: $msg'),
            backgroundColor: isAlready ? kWarningOrange : kErrorRed,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _selfSubmitting = false);
    }
    return false;
  }

  Future<void> _loadWorkers() async {
    setState(() => _workersLoading = true);
    try {
      final res = await StationCleaningRepository.listWorkers(
          stationId: widget.stationId);
      final raw = res['workers'] as List? ?? [];
      setState(() {
        _workers = raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        for (final w in _workers) {
          final uid = w['uid']?.toString() ?? '';
          if (uid.isNotEmpty && !_workerStatus.containsKey(uid)) {
            _workerStatus[uid] = 'present';
            _workerReasons[uid] = '';
          }
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load workers: $e'), backgroundColor: kErrorRed),
        );
      }
    } finally {
      if (mounted) setState(() => _workersLoading = false);
    }
  }

  Future<void> _submitWorkerAttendance() async {
    final date = DateTime.now().toIso8601String().split('T')[0];
    final workersPayload = <Map<String, dynamic>>[];
    for (final w in _workers) {
      final uid = w['uid']?.toString() ?? '';
      final status = _workerStatus[uid] ?? 'present';
      if (uid.isEmpty) continue;
      workersPayload.add({
        'workerId': uid,
        'workerName': w['fullName']?.toString() ?? 'Unknown',
        'status': status,
        'captureMode': 'manual',
        'reason': status == 'present' ? '' : (_workerReasons[uid] ?? ''),
      });
    }
    setState(() => _bulkSubmitting = true);
    try {
      await StationAttendanceRepository.bulkMark({
        'stationId': widget.stationId,
        'date': date,
        'shift': _shift,
        'workers': workersPayload,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Worker attendance saved successfully!'),
            backgroundColor: kSuccessGreen,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Submission failed: $e'), backgroundColor: kErrorRed),
        );
      }
    } finally {
      if (mounted) setState(() => _bulkSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Supervisor Attendance',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: kRailwayBlue,
        iconTheme: const IconThemeData(color: Colors.white),
        bottom: TabBar(
          controller: _tabCtrl,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(text: 'My Attendance'),
            Tab(text: 'Workers'),
          ],
        ),
      ),
      body: TabBarView(
          controller: _tabCtrl,
          children: [
            _buildSelfAttendanceTab(),
            _buildWorkersTab(),
          ],
        ),
    );
  }

  Widget _buildSelfAttendanceTab() {
    final canMid = _isStartMarked && !_isMidMarked;
    final canEnd = _isStartMarked && _isMidMarked && !_isEndMarked;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Supervisor: ${widget.supervisorName}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  const SizedBox(height: 4),
                  Text('Station: ${widget.stationName}',
                      style: const TextStyle(color: kTextSecondary)),
                  const SizedBox(height: 4),
                  Text('Date: ${DateTime.now().toIso8601String().split('T')[0]}',
                      style: const TextStyle(color: kTextSecondary)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _chip('Start', _isStartMarked ? kSuccessGreen : Colors.grey, _isStartMarked),
                      const SizedBox(width: 6),
                      _chip('Mid', _isMidMarked ? Colors.orange : Colors.grey, _isMidMarked),
                      const SizedBox(width: 6),
                      _chip('End', _isEndMarked ? kErrorRed : Colors.grey, _isEndMarked),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text('Status: $_attendanceStatus',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  if (_identityAuditStatus.isNotEmpty)
                    Text('Audit: $_identityAuditStatus',
                        style: const TextStyle(fontSize: 12, color: kTextSecondary)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          _attendanceButton(
            icon: Icons.play_arrow,
            color: Colors.green,
            label: _isStartMarked ? 'Start (Already Marked)' : 'Mark Start Attendance',
            onPress: _selfSubmitting || _statusLoading || _isStartMarked
                ? null
                : () => _submitSelfAttendance('start'),
          ),
          const SizedBox(height: 12),
          _attendanceButton(
            icon: Icons.pause,
            color: Colors.orange,
            label: _isMidMarked
                ? 'Mid (Already Marked)'
                : (canMid ? 'Mark Mid Attendance' : 'Mid locked until Start is marked'),
            onPress: _selfSubmitting || canMid ? () => _submitSelfAttendance('mid') : null,
          ),
          const SizedBox(height: 12),
          _attendanceButton(
            icon: Icons.stop,
            color: kErrorRed,
            label: _isEndMarked
                ? 'End (Already Marked)'
                : (canEnd ? 'Mark End Attendance' : 'End locked until Mid is marked'),
            onPress: _selfSubmitting || canEnd ? () => _submitSelfAttendance('end') : null,
          ),
          const SizedBox(height: 16),
          const Text(
            'Mid requires at least half of your tasks completed and End requires all tasks completed today.',
            style: TextStyle(fontSize: 11, color: kTextSecondary),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _attendanceButton(
      {required IconData icon,
      required Color color,
      required String label,
      required VoidCallback? onPress}) {
    return ElevatedButton.icon(
      onPressed: onPress,
      icon: Icon(icon),
      label: Text(label, textAlign: TextAlign.center),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Widget _buildWorkersTab() {
    Widget list;
    if (_workersLoading) {
      list = const Expanded(child: Center(child: CircularProgressIndicator()));
    } else if (_workers.isEmpty) {
      list = Expanded(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.group_off, size: 72, color: Colors.grey[300]),
              const SizedBox(height: 12),
              const Text('No workers assigned to this station',
                  style: TextStyle(color: Colors.grey, fontSize: 15)),
            ],
          ),
        ),
      );
    } else {
      list = Expanded(
        child: RefreshIndicator(
          onRefresh: _loadWorkers,
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: _workers.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, i) => _buildWorkerCard(_workers[i]),
          ),
        ),
      );
    }

    return Column(
      children: [
        Card(
          margin: const EdgeInsets.all(16),
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                const Icon(Icons.calendar_today, color: kRailwayBlue, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Date: ${DateTime.now().toIso8601String().split('T')[0]}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
                DropdownButton<String>(
                  value: _shift,
                  items: const [
                    DropdownMenuItem(value: 'morning', child: Text('Morning')),
                    DropdownMenuItem(value: 'afternoon', child: Text('Afternoon')),
                    DropdownMenuItem(value: 'night', child: Text('Night')),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _shift = v);
                  },
                ),
              ],
            ),
          ),
        ),
        list,
        if (_workers.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _bulkSubmitting ? null : _submitWorkerAttendance,
                style: ElevatedButton.styleFrom(
                  backgroundColor: kRailwayBlue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _bulkSubmitting
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('Save Worker Attendance',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildWorkerCard(Map<String, dynamic> w) {
    final uid = w['uid']?.toString() ?? '';
    final name = w['fullName']?.toString() ?? 'Unknown Worker';
    final status = _workerStatus[uid] ?? 'present';
    final needsReason = status != 'present';

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: kRailwayBlue.withOpacity(0.1),
                  child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                      style: const TextStyle(color: kRailwayBlue, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(name,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                ),
                DropdownButton<String>(
                  value: status,
                  items: const [
                    DropdownMenuItem(value: 'present', child: Text('Present', style: TextStyle(color: kSuccessGreen))),
                    DropdownMenuItem(value: 'absent', child: Text('Absent', style: TextStyle(color: kErrorRed))),
                    DropdownMenuItem(value: 'late', child: Text('Late', style: TextStyle(color: kWarningOrange))),
                    DropdownMenuItem(value: 'half_day', child: Text('Half Day', style: TextStyle(color: Colors.blueGrey))),
                    DropdownMenuItem(value: 'on_leave', child: Text('On Leave', style: TextStyle(color: Colors.grey))),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _workerStatus[uid] = v);
                  },
                ),
              ],
            ),
            if (needsReason)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: TextField(
                  decoration: const InputDecoration(
                    labelText: 'Reason',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (val) => _workerReasons[uid] = val,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, Color color, bool active) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: active ? color.withOpacity(0.15) : Colors.grey.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: active ? color : Colors.grey.shade300),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: active ? color : Colors.grey)),
    );
  }
}