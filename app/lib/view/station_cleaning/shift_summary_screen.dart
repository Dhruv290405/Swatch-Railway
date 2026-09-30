import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:crm_train/helper/location_helper.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crm_train/services/api_services.dart';
import 'package:crm_train/model/station_models.dart';
import 'package:crm_train/repositories/worker_repo.dart';
import 'package:crm_train/utills/app_colors.dart';

class ShiftSummaryScreen extends StatefulWidget {
  final String stationId;
  final String stationName;
  final String supervisorId;
  final String supervisorName;
  final String shift;
  final String date;
  final List<Map<String, dynamic>> areas;
  final String? existingSummaryUid;
  final String? rejectionReason;
  final int missedCount;

  const ShiftSummaryScreen({
    super.key,
    required this.stationId,
    required this.stationName,
    required this.supervisorId,
    required this.supervisorName,
    required this.shift,
    required this.date,
    required this.areas,
    this.existingSummaryUid,
    this.rejectionReason,
    this.missedCount = 0,
  });

  @override
  State<ShiftSummaryScreen> createState() => _ShiftSummaryScreenState();
}

class _AreaEntry {
  final String key;
  final String areaId;
  String areaName;
  String mainArea;
  String activityType;
  double basicAreaSqFt;
  int boqTimesPerPeriod;
  int times;
  double tenderedAreaPerDay;
  String cleaningFrequency;
  final String scheduledTime;
  final String? taskId;
  final String? afterPhotoUrl;
  final String? taskRemarks;
  final double? taskGpsLat;
  final double? taskGpsLng;

  /// Every photo captured for this area during the current session, each with
  /// its own live GPS. Retaking a photo APPENDS instead of replacing, so an
  /// earlier photo is never deleted. All are uploaded on submit.
  final List<_CapturedPhoto> photos = [];
  final TextEditingController remarkCtrl;
  double? latitude;
  double? longitude;
  bool gpsCaptured = false;

  double get workDone => basicAreaSqFt * times;
  bool get hasReferencePhoto => afterPhotoUrl != null && afterPhotoUrl!.isNotEmpty;
  bool get isVerified => photos.isNotEmpty;
  bool get hasUsablePhoto =>
      photos.isNotEmpty ||
      (afterPhotoUrl != null && afterPhotoUrl!.isNotEmpty && latitude != null && longitude != null);

  _AreaEntry({
    required this.key,
    required this.areaId,
    this.areaName = '',
    this.mainArea = '',
    this.activityType = '',
    this.basicAreaSqFt = 0,
    this.boqTimesPerPeriod = 1,
    this.times = 1,
    this.tenderedAreaPerDay = 0,
    this.cleaningFrequency = 'daily',
    this.scheduledTime = '',
    this.taskId,
    this.afterPhotoUrl,
    this.taskRemarks,
    this.taskGpsLat,
    this.taskGpsLng,
    this.prefillLatitude,
    this.prefillLongitude,
    required String remark,
  })  : remarkCtrl = TextEditingController(text: remark),
        latitude = prefillLatitude,
        longitude = prefillLongitude;

  final double? prefillLatitude;
  final double? prefillLongitude;

  void dispose() => remarkCtrl.dispose();
}

/// A photo captured for a shift-summary area, frozen with its own live GPS.
class _CapturedPhoto {
  final XFile file;
  final double latitude;
  final double longitude;
  const _CapturedPhoto({required this.file, required this.latitude, required this.longitude});
}

class _ShiftSummaryScreenState extends State<ShiftSummaryScreen> {
  final _picker = ImagePicker();
  bool _isSubmitting = false;
  bool _loadingAreas = false;
  List<StationArea> _masterAreas = [];
  late List<_AreaEntry> _entries;

  static const int _minAreas = 1;

  @override
  void initState() {
    super.initState();
    _entries = widget.areas.map((a) {
      final key = (a['key'] ?? a['areaId'] ?? a['areaName'] ?? '').toString();
      final master = _findMaster(key, (a['areaName'] ?? '').toString());
      final taskRemarks = (a['taskRemarks'] ?? '').toString();
      final afterPhotoUrl = (a['afterPhotoUrl'] ?? a['photoUrl'] ?? '').toString();
      return _AreaEntry(
        key: key.isEmpty ? 'area_${a['areaName']}' : key,
        areaId: (a['areaId'] ?? '').toString(),
        areaName: (a['areaName'] ?? master?.name ?? '').toString(),
        mainArea: (a['mainArea'] ?? master?.mainArea ?? '').toString(),
        activityType: (a['activityType'] ?? '').toString(),
        basicAreaSqFt: (a['basicAreaSqFt'] ?? master?.basicAreaSqFt ?? 0).toDouble(),
        boqTimesPerPeriod: (a['boqTimesPerPeriod'] ?? master?.boqTimesPerPeriod ?? 1).toInt(),
        times: (a['times'] ?? 1).toInt(),
        tenderedAreaPerDay: (a['tenderedAreaPerDay'] ?? master?.tenderedAreaPerDay ?? 0).toDouble(),
        cleaningFrequency: (a['cleaningFrequency'] ?? master?.cleaningFrequency ?? 'daily').toString(),
        scheduledTime: (a['scheduledTime'] ?? '').toString(),
        taskId: a['taskId']?.toString(),
        afterPhotoUrl: afterPhotoUrl.isNotEmpty ? afterPhotoUrl : null,
        taskRemarks: taskRemarks.isNotEmpty ? taskRemarks : null,
        taskGpsLat: ((a['gpsLat'] as num?)?.toDouble() ?? (a['latitude'] as num?)?.toDouble()),
        taskGpsLng: ((a['gpsLng'] as num?)?.toDouble() ?? (a['longitude'] as num?)?.toDouble()),
        prefillLatitude: (a['latitude'] as num?)?.toDouble(),
        prefillLongitude: (a['longitude'] as num?)?.toDouble(),
        remark: taskRemarks,
      );
    }).toList();
    _loadMasterAreas();
    if (_entries.isEmpty) _loadCompletedTasks();
  }

  Future<void> _loadCompletedTasks() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      if (token == null) return;
      final uri = Uri.parse('${ApiService.baseUrl}/api/tasks-v2/supervisor/${widget.supervisorId}')
          .replace(queryParameters: {'date': widget.date});
      final response = await http.get(
        uri,
        headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 30));
      if (response.statusCode != 200 || !mounted) return;
      final body = jsonDecode(response.body);
      final tasks = (body['tasks'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
      final doneStatuses = {'completed', 'approved'};
      final completed = tasks
          .where((t) => doneStatuses.contains((t['status'] ?? '').toString().toLowerCase()))
          .where((t) => (t['areaId'] ?? '').toString().isNotEmpty)
          .toList();
      if (completed.isEmpty) return;
      final grouped = <String, Map<String, dynamic>>{};
      for (final t in completed) {
        final areaId = (t['areaId'] ?? '').toString();
        final key = '${t['uid'] ?? areaId}_$areaId';
        grouped[key] = {
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
      if (grouped.isEmpty || !mounted) return;
      final entries = grouped.values.map((a) {
        final key = (a['key'] ?? a['areaId'] ?? a['areaName'] ?? '').toString();
        final master = _findMaster(key, (a['areaName'] ?? '').toString());
        final taskRemarks = (a['taskRemarks'] ?? '').toString();
        final afterPhotoUrl = (a['afterPhotoUrl'] ?? a['photoUrl'] ?? '').toString();
        return _AreaEntry(
          key: key.isEmpty ? 'area_${a['areaName']}' : key,
          areaId: (a['areaId'] ?? '').toString(),
          areaName: (a['areaName'] ?? master?.name ?? '').toString(),
          mainArea: (a['mainArea'] ?? master?.mainArea ?? '').toString(),
          activityType: (a['activityType'] ?? '').toString(),
          basicAreaSqFt: (a['basicAreaSqFt'] ?? master?.basicAreaSqFt ?? 0).toDouble(),
          boqTimesPerPeriod: (a['boqTimesPerPeriod'] ?? master?.boqTimesPerPeriod ?? 1).toInt(),
          times: (a['times'] ?? 1).toInt(),
          tenderedAreaPerDay: (a['tenderedAreaPerDay'] ?? master?.tenderedAreaPerDay ?? 0).toDouble(),
          cleaningFrequency: (a['cleaningFrequency'] ?? master?.cleaningFrequency ?? 'daily').toString(),
          scheduledTime: (a['scheduledTime'] ?? '').toString(),
          taskId: a['taskId']?.toString(),
          afterPhotoUrl: afterPhotoUrl.isNotEmpty ? afterPhotoUrl : null,
          taskRemarks: taskRemarks.isNotEmpty ? taskRemarks : null,
          taskGpsLat: (a['gpsLat'] as num?)?.toDouble(),
          taskGpsLng: (a['gpsLng'] as num?)?.toDouble(),
          remark: taskRemarks,
        );
      }).toList();
      for (final e in _entries) {
        e.dispose();
      }
      setState(() => _entries = entries);
      _loadMasterAreas();
    } catch (_) {}
  }

  @override
  void dispose() {
    for (final e in _entries) {
      e.dispose();
    }
    super.dispose();
  }

  StationArea? _findMaster(String id, String name) {
    if (id.isEmpty && name.isEmpty) return null;
    final byId = _masterAreas.where((m) => m.uid == id).toList();
    if (byId.isNotEmpty) return byId.first;
    return _masterAreas.where((m) => m.name.toLowerCase() == name.toLowerCase()).toList().firstOrNull;
  }

  Future<void> _loadMasterAreas() async {
    setState(() => _loadingAreas = true);
    try {
      final areas = await ApiService.getStationAreas(widget.stationId);
      if (!mounted) return;
      setState(() {
        _masterAreas = areas;
        for (final e in _entries) {
          final m = _findMaster(e.areaId.isNotEmpty ? e.areaId : e.key, e.areaName);
          if (m != null) {
            e
              ..areaName = m.name
              ..mainArea = m.mainArea ?? e.mainArea
              ..basicAreaSqFt = e.basicAreaSqFt > 0 ? e.basicAreaSqFt : (m.basicAreaSqFt ?? 0)
              ..boqTimesPerPeriod = e.boqTimesPerPeriod > 0 ? e.boqTimesPerPeriod : (m.boqTimesPerPeriod ?? 1)
              ..tenderedAreaPerDay = e.tenderedAreaPerDay > 0 ? e.tenderedAreaPerDay : (m.tenderedAreaPerDay ?? 0)
              ..cleaningFrequency = e.cleaningFrequency != 'daily' ? e.cleaningFrequency : (m.cleaningFrequency ?? 'daily');
          }
        }
      });
    } catch (_) {
      // Master areas are optional enrichment; proceed with provided values.
    } finally {
      if (mounted) setState(() => _loadingAreas = false);
    }
  }

  int get _photoCount => _entries.where((e) => e.hasUsablePhoto).length;
  int get _remarkCount => _entries.where((e) => e.remarkCtrl.text.trim().isNotEmpty).length;
  double get _totalWorkDone => _entries.fold(0, (sum, e) => sum + e.workDone);
  int get _requiredPhotoCount => _entries.length > 5 ? 5 : _entries.length;
  String get _photoRequirementMessage => _entries.length > 5
      ? 'At least 5 photos are required to submit the shift summary when more than 5 tasks are submitted.'
      : 'Photos are required for every area worked.';
  bool get _canSubmit => _entries.length >= _minAreas && _photoCount >= _requiredPhotoCount && _remarkCount == _entries.length;

  Future<Position?> _captureGps() async => captureGps();

  Future<void> _takePhoto(_AreaEntry entry) async {
    final photo = await _picker.pickImage(source: ImageSource.camera, imageQuality: 80, maxWidth: 1280);
    if (photo == null) return;

    final position = await _captureGps();
    if (position == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Live location could not be captured. Please enable location and retake the photo.'),
            backgroundColor: kWarningOrange,
          ),
        );
      }
      return;
    }

    setState(() {
      // Append so earlier captures are preserved — never replace/delete.
      entry.photos.add(_CapturedPhoto(file: photo, latitude: position.latitude, longitude: position.longitude));
      if (entry.latitude == null) {
        entry
          ..latitude = position.latitude
          ..longitude = position.longitude;
      }
      entry.gpsCaptured = true;
    });
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() => _isSubmitting = true);
    try {
      final isResubmit = widget.existingSummaryUid != null && widget.existingSummaryUid!.isNotEmpty;

      // Upload every photo up front, a few at a time. Uploading them one-by-one
      // while building the payload made the final submit take as long as the sum
      // of all uploads, which is what looked like a hanging submit.
      final pending = <({int entryIndex, int photoIndex, String path})>[];
      final slotOf = <String, int>{};
      for (var ei = 0; ei < _entries.length; ei++) {
        final photos = _entries[ei].photos;
        for (var pi = 0; pi < photos.length; pi++) {
          slotOf['$ei:$pi'] = pending.length;
          pending.add((entryIndex: ei, photoIndex: pi, path: photos[pi].file.path));
        }
      }
      final uploaded = List<String?>.filled(pending.length, null);
      const uploadBatch = 3;
      for (var start = 0; start < pending.length; start += uploadBatch) {
        final end = start + uploadBatch < pending.length ? start + uploadBatch : pending.length;
        final batch = pending.sublist(start, end);
        final urls = await Future.wait(batch.map((p) async {
          final url = await WorkerRepository.uploadMedia(p.path);
          return url.isEmpty ? null : url;
        }));
        for (var i = 0; i < batch.length; i++) {
          uploaded[start + i] = urls[i];
        }
      }

      final areasPayload = <Map<String, dynamic>>[];
      for (var ei = 0; ei < _entries.length; ei++) {
        final e = _entries[ei];
        final photoUrls = <String>[];
        for (var pi = 0; pi < e.photos.length; pi++) {
          final slot = slotOf['$ei:$pi'];
          final url = slot == null ? null : uploaded[slot];
          if (url != null && url.isNotEmpty) photoUrls.add(url);
        }
        // Resubmission: carry the previous summary photo forward when no new
        // photo was taken for the area, so it is not lost.
        if (photoUrls.isEmpty &&
            isResubmit &&
            e.hasUsablePhoto &&
            e.afterPhotoUrl != null &&
            e.afterPhotoUrl!.isNotEmpty) {
          photoUrls.add(e.afterPhotoUrl!);
        }

        areasPayload.add({
          'areaId': e.areaId.isNotEmpty ? e.areaId : e.key,
          'areaName': e.areaName,
          'mainArea': e.mainArea,
          'basicAreaSqFt': e.basicAreaSqFt,
          'boqTimesPerPeriod': e.boqTimesPerPeriod,
          'times': e.times,
          'cleaningFrequency': e.cleaningFrequency,
          'tenderedAreaPerDay': e.tenderedAreaPerDay,
          'photoUrl': photoUrls.isEmpty ? '' : photoUrls.first,
          'photoUrls': photoUrls,
          'remark': e.isVerified ? e.remarkCtrl.text.trim() : (e.taskRemarks ?? e.remarkCtrl.text.trim()),
          'scheduledTime': e.scheduledTime,
          'taskId': e.taskId,
          'latitude': e.photos.isNotEmpty ? e.photos.first.latitude : (e.latitude ?? 0),
          'longitude': e.photos.isNotEmpty ? e.photos.first.longitude : (e.longitude ?? 0),
        });
      }

      final payload = {
        'supervisorId': widget.supervisorId,
        'supervisorName': widget.supervisorName,
        'stationId': widget.stationId,
        'stationName': widget.stationName,
        'date': widget.date,
        'shift': widget.shift,
        'areas': areasPayload,
      };

      if (isResubmit) {
        await ApiService.resubmitShiftSummary(widget.existingSummaryUid!, payload);
      } else {
        await ApiService.submitShiftSummary(payload);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isResubmit ? 'Shift summary resubmitted for approval!' : 'Shift summary submitted for approval!'),
            backgroundColor: kSuccessGreen,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: kErrorRed),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existingSummaryUid != null
            ? 'Shift Summary Resubmit — ${widget.stationName}'
            : 'Shift Summary — ${widget.stationName}'),
        backgroundColor: kRailwayBlue,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: kRailwayBlue.withValues(alpha: 0.08),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${widget.shift} Shift — ${widget.date}',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text('Completed: ${_entries.length} • Missed: ${widget.missedCount}',
                    style: TextStyle(color: Colors.grey[600])),
                const SizedBox(height: 4),
                Text('End-of-shift photos: $_photoCount/$_requiredPhotoCount',
                    style: TextStyle(color: Colors.grey[600])),
                const SizedBox(height: 4),
                Text('Total Work Done: ${_totalWorkDone.toStringAsFixed(0)} sqft',
                    style: TextStyle(color: const Color(0xFF1B5E20), fontWeight: FontWeight.w700)),
                if (widget.existingSummaryUid != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: kErrorRed.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: kErrorRed),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline, color: kErrorRed, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            widget.rejectionReason != null && widget.rejectionReason!.isNotEmpty
                                ? 'Resubmitting after rejection. Reason: ${widget.rejectionReason}'
                                : 'This summary was rejected. Please correct the issues and resubmit.',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: kErrorRed),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (_photoCount < _requiredPhotoCount) ...[
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: kWarningOrange.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: kWarningOrange),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.warning_amber_rounded, color: kWarningOrange, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '$_photoRequirementMessage Photos Uploaded: $_photoCount/${_requiredPhotoCount}',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else if (_photoCount >= 5) ...[
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: kSuccessGreen.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: kSuccessGreen),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.check_circle, color: kSuccessGreen, size: 20),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Photos Uploaded: 5 / 5 — Minimum requirement completed',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: kSuccessGreen),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: _entries.isEmpty
                ? Center(
                    child: _loadingAreas
                        ? const CircularProgressIndicator()
                        : const Text('No areas selected'),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _entries.length,
                    itemBuilder: (ctx, i) => _buildAreaCard(_entries[i]),
                  ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      icon: _isSubmitting
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.check_circle),
                      label: Text(_isSubmitting
                          ? 'Submitting...'
                          : _entries.isEmpty
                              ? 'No areas to submit'
                              : (_photoCount < _requiredPhotoCount || _remarkCount < _entries.length)
                                  ? 'End-of-shift photos: $_photoCount/$_requiredPhotoCount'
                                  : (widget.existingSummaryUid != null
                                      ? 'Resubmit Summary ($_photoCount areas)'
                                      : 'Submit Summary ($_photoCount areas)')),
                      onPressed: (_canSubmit && !_isSubmitting) ? _submit : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kSuccessGreen,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: Colors.grey[300],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAreaCard(_AreaEntry entry) {
    final capturedPhotos = entry.photos;
    final hasTaskPhoto = entry.afterPhotoUrl != null && entry.afterPhotoUrl!.isNotEmpty;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.cleaning_services, size: 20, color: kRailwayBlue),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    entry.areaName.isEmpty ? 'Unnamed Area' : entry.areaName,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                if (entry.activityType.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(right: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: kRailwayBlue.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      entry.activityType,
                      style: TextStyle(color: kRailwayBlue, fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                  ),
                if (entry.scheduledTime.isNotEmpty)
                  Text(entry.scheduledTime, style: TextStyle(color: Colors.grey[500], fontSize: 12)),
              ],
            ),
            if (entry.mainArea.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(entry.mainArea, style: TextStyle(color: Colors.grey[500], fontSize: 12)),
            ],
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.blueGrey[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Work: ${entry.basicAreaSqFt.toStringAsFixed(0)} sqft × ${entry.times}X = ${entry.workDone.toStringAsFixed(0)} sqft',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
            if (entry.boqTimesPerPeriod - entry.times > 0) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.orange[50],
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.orange[200]!),
                ),
                child: Text(
                  '${entry.boqTimesPerPeriod - entry.times}X need to clean',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.orange[800]),
                ),
              ),
            ],
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(
                  entry.isVerified ? Icons.gps_fixed : Icons.gps_off,
                  size: 14,
                  color: entry.isVerified ? Colors.green[700] : Colors.redAccent,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    entry.isVerified
                        ? 'Live GPS: ${entry.latitude!.toStringAsFixed(5)}, ${entry.longitude!.toStringAsFixed(5)}'
                        : entry.taskGpsLat != null
                            ? 'Task GPS: ${entry.taskGpsLat!.toStringAsFixed(5)}, ${entry.taskGpsLng!.toStringAsFixed(5)} (reference)'
                            : 'Fresh photo with live location required',
                    style: TextStyle(
                      fontSize: 12,
                      color: entry.isVerified ? Colors.green[800] : Colors.grey[600],
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (capturedPhotos.isNotEmpty)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Stack(
                    children: [
                      Container(
                        width: double.infinity,
                        height: 160,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          image: DecorationImage(
                            image: FileImage(File(capturedPhotos.last.file.path)),
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                      if (entry.isVerified)
                        Positioned(
                          top: 8,
                          left: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.green[700],
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.check_circle, color: Colors.white, size: 14),
                                SizedBox(width: 4),
                                Text('End-of-shift photo verified',
                                    style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (capturedPhotos.length > 1) ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 48,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: capturedPhotos.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 6),
                        itemBuilder: (context, i) {
                          final p = capturedPhotos[i];
                          return ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: Image.file(
                              File(p.file.path),
                              width: 64,
                              height: 48,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                width: 64,
                                height: 48,
                                color: Colors.grey[200],
                                child: const Icon(Icons.broken_image, color: Colors.grey),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'All ${capturedPhotos.length} photos for this area are kept.',
                      style: TextStyle(color: Colors.green[800], fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                  ],
                ],
              )
            else if (hasTaskPhoto)
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      entry.afterPhotoUrl!,
                      width: double.infinity,
                      height: 160,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: double.infinity,
                        height: 120,
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey[300]!),
                          borderRadius: BorderRadius.circular(8),
                          color: Colors.grey[50],
                        ),
                        child: const Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.broken_image, size: 36, color: Colors.grey),
                              SizedBox(height: 8),
                              Text('Task photo could not be loaded', style: TextStyle(color: Colors.grey)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.blueGrey[600],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        widget.existingSummaryUid != null && entry.hasUsablePhoto
                            ? 'Existing photo (resubmit)'
                            : 'Reference photo (from task)',
                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              )
            else
              Container(
                width: double.infinity,
                height: 120,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey[300]!),
                  borderRadius: BorderRadius.circular(8),
                  color: Colors.grey[50],
                ),
                child: const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.camera_alt, size: 36, color: Colors.grey),
                      SizedBox(height: 8),
                      Text('Fresh photo required — tap to take', style: TextStyle(color: Colors.grey)),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: Icon((entry.isVerified || entry.hasUsablePhoto) ? Icons.fact_check : Icons.camera_alt, size: 16),
                label: Text(
                  (entry.isVerified || (widget.existingSummaryUid != null && entry.hasUsablePhoto))
                      ? 'Add End-of-Shift Photo'
                      : 'Take End-of-Shift Photo',
                ),
                onPressed: () => _takePhoto(entry),
                style: OutlinedButton.styleFrom(
                  foregroundColor: (entry.isVerified || entry.hasUsablePhoto) ? Colors.green[800] : kRailwayBlue,
                  backgroundColor: (entry.isVerified || entry.hasUsablePhoto) ? Colors.green[50] : null,
                ),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: entry.remarkCtrl,
              minLines: 2,
              maxLines: 2,
              decoration: InputDecoration(
                hintText: 'Remark (required)',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                contentPadding: const EdgeInsets.all(12),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
      ),
    );
  }
}
