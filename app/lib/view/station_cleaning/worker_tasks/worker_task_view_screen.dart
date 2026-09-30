import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crm_train/services/api_services.dart';
import 'package:crm_train/repositories/station_cleaning_repository.dart';
import 'package:crm_train/repositories/task_type_repository.dart';
import 'package:crm_train/model/task_type_model.dart';
import 'package:crm_train/helper/api_error_handler.dart';
import 'package:crm_train/helper/location_helper.dart';
import 'package:crm_train/utills/app_colors.dart';

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

class WorkerTaskViewScreen extends StatefulWidget {
  final String workerId;
  final String workerName;

  const WorkerTaskViewScreen({
    super.key,
    required this.workerId,
    required this.workerName,
  });

  @override
  State<WorkerTaskViewScreen> createState() => _WorkerTaskViewScreenState();
}

class _WorkerTaskViewScreenState extends State<WorkerTaskViewScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _tasks = [];
  String? _error;
  String _selectedDate = DateTime.now().toIso8601String().split('T')[0];

  bool _startAttendanceMarked = false;
  bool _midAttendanceMarked = false;
  bool _endAttendanceMarked = false;

  bool _startInProgress = false;

  final List<String> _statusChips = ['all', 'pending', 'in_progress', 'completed', 'approved', 'rejected'];
  String _statusFilter = 'all';

  @override
  void initState() {
    super.initState();
    _loadAttendanceStatus();
    _loadTasks();
  }

  Future<void> _loadAttendanceStatus() async {
    try {
      final result = await StationCleaningRepository.getStationAttendanceStatus(
        workerId: widget.workerId,
      );
      if (result['exists'] == true) {
        setState(() {
          _startAttendanceMarked = result['isStartMarked'] == true;
          _midAttendanceMarked = result['isMidMarked'] == true;
          _endAttendanceMarked = result['isEndMarked'] == true;
        });
      }
    } catch (_) {}
  }

  Future<void> _loadTasks() async {
    setState(() => _isLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      if (token == null) throw Exception('AUTH_ERROR');

      final queryParams = <String, String>{
        'workerId': widget.workerId,
        'date': _selectedDate,
      };

      final uri = Uri.parse('${ApiService.baseUrl}/api/tasks-v2').replace(queryParameters: queryParams);
      final response = await http.get(
        uri,
        headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        final list = body['tasks'] as List<dynamic>? ?? body['data'] as List<dynamic>? ?? [];
        setState(() {
          _tasks = list.cast<Map<String, dynamic>>();
          _isLoading = false;
        });
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        throw Exception('AUTH_ERROR');
      } else {
        throw Exception(ApiErrorHandler.getErrorMessage(response.body, response.statusCode));
      }
    } catch (e) {
      setState(() {
        _error = e.toString().contains('AUTH_ERROR') ? 'Session expired' : e.toString();
        _isLoading = false;
      });
    }
  }

  List<Map<String, dynamic>> get _filteredTasks {
    var list = _tasks;
    if (_statusFilter != 'all') {
      list = list.where((t) => t['status'] == _statusFilter).toList();
    }
    list.sort((a, b) => ((a['scheduledTime'] ?? '00:00') as String).compareTo(b['scheduledTime'] ?? '00:00'));
    return list;
  }

  int get _completedTaskCount => _tasks.where((t) => t['status'] == 'approved' || t['status'] == 'completed').length;
  int get _totalTaskCount => _tasks.length;

  Future<Map<String, double>?> _captureGps() async {
    final pos = await captureGps();
    if (pos == null) return null;
    return {'lat': pos.latitude, 'lng': pos.longitude};
  }

  Future<void> _startTask(String taskId) async {
    if (!_startAttendanceMarked) {
      _showAttendanceRequiredBanner();
      return;
    }
    setState(() => _startInProgress = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      if (token == null) throw Exception('AUTH_ERROR');

      final gps = await _captureGps();
      final body = <String, dynamic>{};
      if (gps != null) {
        body['gpsLat'] = gps['lat']!;
        body['gpsLng'] = gps['lng']!;
      }

      final response = await http.post(
        Uri.parse('${ApiService.baseUrl}/api/tasks-v2/$taskId/start'),
        headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final body = response.body.isEmpty ? <String, dynamic>{} : (jsonDecode(response.body) as Map<String, dynamic>);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(body['shiftWarning'] == true
                ? 'Task started. You are doing a task outside your ${body['assignedShift']} shift.'
                : 'Task started'),
            backgroundColor: body['shiftWarning'] == true ? kWarningOrange : null,
          ),
        );
        _loadTasks();
      } else {
        throw Exception(ApiErrorHandler.getErrorMessage(response.body, response.statusCode));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      setState(() => _startInProgress = false);
    }
  }

  void _showAttendanceRequiredBanner() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Please mark Start Attendance first from the Attendance tab.'),
        backgroundColor: kWarningOrange,
        duration: Duration(seconds: 4),
      ),
    );
  }

  void _openTaskExecutionSheet(Map<String, dynamic> task) {
    final taskId = task['uid'] ?? task['id'];
    final status = task['status'] ?? 'pending';
    if (!_startAttendanceMarked) {
      _showAttendanceRequiredBanner();
      return;
    }
    if (status == 'in_progress') {
      _showCompleteSheet(taskId);
    } else if (status == 'rejected') {
      _showResubmitSheet(taskId);
    }
  }

  void _showCompleteSheet(String taskId) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _TaskExecutionSheet(
        taskId: taskId,
        mode: 'complete',
        onDone: () { _loadTasks(); Navigator.pop(context); },
      ),
    );
  }

  void _showResubmitSheet(String taskId) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _TaskExecutionSheet(
        taskId: taskId,
        mode: 'resubmit',
        onDone: () { _loadTasks(); Navigator.pop(context); },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Tasks - ${widget.workerName}'),
        backgroundColor: kRailwayBlue,
        foregroundColor: Colors.white,
      ),
      body: !_startAttendanceMarked
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.lock_outline, size: 80, color: kWarningOrange.withOpacity(0.5)),
                    const SizedBox(height: 24),
                    const Text('Start Attendance Required',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: kWarningOrange)),
                    const SizedBox(height: 12),
                    Text(
                      'Please mark your Start Attendance from the Attendance tab before viewing tasks.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey[600], fontSize: 14),
                    ),
                  ],
                ),
              ),
            )
          : Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
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
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              children: [
                Text('Completed: $_completedTaskCount/$_totalTaskCount',
                    style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
                const Spacer(),
                if (_startAttendanceMarked &&
                    !_midAttendanceMarked &&
                    _completedTaskCount >= (_totalTaskCount > 0 ? ((_totalTaskCount / 2).ceil()) : 1))
                  Text('Mid attendance available', style: TextStyle(color: Colors.orange[700], fontSize: 11)),
                if (_midAttendanceMarked && !_endAttendanceMarked && _completedTaskCount >= _totalTaskCount && _totalTaskCount > 0)
                  Text('End attendance available', style: TextStyle(color: Colors.green[700], fontSize: 11)),
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
                  selected: _statusFilter == s,
                  onSelected: (v) { setState(() => _statusFilter = s); },
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
                        ? const Center(child: Text('No tasks found'))
                        : RefreshIndicator(
                            onRefresh: _loadTasks,
                            child: ListView.builder(
                              itemCount: _filteredTasks.length,
                              itemBuilder: (ctx, i) {
                                final t = _filteredTasks[i];
                                final status = t['status'] ?? 'pending';
                                final areaName = t['areaName'] ?? '';
                                final activityName = t['activityType'] ?? t['taskTypeName'] ?? 'Cleaning';
                                final time = t['scheduledTime'] ?? '--:--';
                                final rejectionReason = t['rejectionReason'];

                                return Card(
                                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                  child: ExpansionTile(
                                    leading: Icon(_statusIcon(status), color: _statusColor(status), size: 28),
                                    title: Text('$time - $activityName',
                                        style: const TextStyle(fontWeight: FontWeight.w500)),
                                    subtitle: Row(
                                      children: [
                                        Flexible(
                                          child: Text('${areaName.isNotEmpty ? areaName : 'Area'} | Status: ${status.replaceAll('_', ' ')}'),
                                        ),
                                        if (t['shift'] != null) ...[
                                          const SizedBox(width: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: kRailwayBlue.withOpacity(0.1),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              '${t['shift']} shift',
                                              style: const TextStyle(color: kRailwayBlue, fontSize: 10, fontWeight: FontWeight.w600),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                    children: [
                                      if (rejectionReason != null)
                                        Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 16),
                                          child: Text('Rejection: $rejectionReason',
                                              style: const TextStyle(color: Colors.red)),
                                        ),
                                      Padding(
                                        padding: const EdgeInsets.all(12),
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                          children: [
                                            if (status == 'pending')
                                              ElevatedButton.icon(
                                                icon: const Icon(Icons.play_arrow, size: 16),
                                                label: Text(_startInProgress ? '...' : 'Start'),
                                                onPressed: _startInProgress ? null : () => _startTask(t['uid'] ?? t['id']),
                                              ),
                                            if (status == 'in_progress')
                                              ElevatedButton.icon(
                                                icon: const Icon(Icons.check, size: 16),
                                                label: const Text('Complete'),
                                                onPressed: () => _openTaskExecutionSheet(t),
                                              ),
                                            if (status == 'rejected')
                                              ElevatedButton.icon(
                                                icon: const Icon(Icons.replay, size: 16),
                                                label: const Text('Resubmit'),
                                                onPressed: () => _openTaskExecutionSheet(t),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
          ),
        ],
      ),
    );
  }

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

// ─── Simple Task Execution Bottom Sheet (no photos) ────────────────────────

class _TaskExecutionSheet extends StatefulWidget {
  final String taskId;
  final String mode;
  final VoidCallback onDone;

  const _TaskExecutionSheet({
    required this.taskId,
    required this.mode,
    required this.onDone,
  });

  @override
  State<_TaskExecutionSheet> createState() => _TaskExecutionSheetState();
}

class _TaskExecutionSheetState extends State<_TaskExecutionSheet> {
  final TextEditingController commentController = TextEditingController();
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
    commentController.dispose();
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
    final selected = <String>{};
    for (final a in (_selectedActivities ?? [])) {
      final id = a['uid']?.toString() ?? '';
      if (id.isNotEmpty) selected.add(id);
    }
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
                    child: _loadingActivities
                        ? const Center(child: CircularProgressIndicator())
                        : ListView(
                            children: _activityOptions.map((tt) {
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
                              final pickedList = _activityOptions
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
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.mode == 'complete' ? 'Complete Task' : 'Resubmit Task',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: Colors.black87),
                    ),
                  ),
                  IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
                ],
              ),
              const SizedBox(height: 20),
              const Text('Choose Activity (required)', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Colors.black87)),
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
              const SizedBox(height: 20),
              const Text('Add Comments', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Colors.black87)),
              const SizedBox(height: 12),
              TextField(
                controller: commentController,
                minLines: 3,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: 'Enter comments (optional)...',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  contentPadding: const EdgeInsets.all(12),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: ((_selectedActivities != null && _selectedActivities!.isNotEmpty) && !isSubmitting)
                      ? _submit
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kRailwayBlue,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: Text(
                    isSubmitting ? 'Submitting...' : (widget.mode == 'complete' ? 'Complete Task' : 'Resubmit Task'),
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                  ),
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

      double? lat;
      double? lng;
      final pos = await captureGps();
      if (pos != null) {
        lat = pos.latitude;
        lng = pos.longitude;
      }

      final body = <String, dynamic>{
        'remarks': commentController.text.trim(),
        'activities': _selectedActivities?.map((a) => {
          'id': a['uid'],
          'name': a['name'],
          'label': a['label'],
        }).toList() ?? [],
      };
      if (lat != null) { body['gpsLat'] = lat; body['gpsLng'] = lng; }

      final endpoint = widget.mode == 'complete' ? 'complete' : 'resubmit';
      final response = await http.post(
        Uri.parse('${ApiService.baseUrl}/api/tasks-v2/${widget.taskId}/$endpoint'),
        headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        if (!mounted) return;
        final resBody = response.body.isEmpty ? <String, dynamic>{} : (jsonDecode(response.body) as Map<String, dynamic>);
        final warning = resBody['shiftWarning'] == true;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.mode == 'complete'
                ? (warning ? 'Task completed outside your ${resBody['assignedShift']} shift.' : 'Task completed!')
                : (warning ? 'Resubmitted outside your ${resBody['assignedShift']} shift.' : 'Task resubmitted')),
            backgroundColor: warning ? kWarningOrange : kSuccessGreen,
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
