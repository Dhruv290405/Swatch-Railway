import 'package:flutter/material.dart';
import 'package:crm_train/repositories/base_repository.dart';
import 'package:crm_train/utills/app_colors.dart';
import 'package:crm_train/view/station_cleaning/garbage/garbage_form_screen.dart';
import 'package:crm_train/view/station_cleaning/pest_control/pest_control_form_screen.dart';

class StationWorkerDashboard extends StatefulWidget {
  final Map<String, dynamic> run;
  final String workerId;
  final String workerName;

  const StationWorkerDashboard({
    super.key,
    required this.run,
    required this.workerId,
    required this.workerName,
  });

  @override
  State<StationWorkerDashboard> createState() => _StationWorkerDashboardState();
}

class _StationWorkerDashboardState extends State<StationWorkerDashboard> {
  bool _isLoading = false;
  String _attendanceStatus = 'Pending';
  bool _isRunCompleted = false;

  @override
  void initState() {
    super.initState();
    _isRunCompleted = widget.run['status'] == 'completed' || widget.run['status'] == 'approved';
    _checkAttendance();
  }

  Future<void> _checkAttendance() async {
    setState(() => _isLoading = true);
    try {
      final res = await BaseRepository.apiCall(
        method: 'GET',
        path: '/api/obhs/attendance/status',
        queryParams: {
          'runInstanceId': widget.run['uid'] ?? widget.run['id'],
          'workerId': widget.workerId,
        },
        parser: (d) => d,
      );
      if (res['isStartMarked'] == true) {
        _attendanceStatus = 'Started';
      }
      if (res['isEndMarked'] == true) {
        _attendanceStatus = 'Completed';
      }
    } catch (e) {
      debugPrint('Error checking attendance: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _markAttendance(String type) async {
    // Basic placeholder for attendance flow (similar to OBHS)
    setState(() => _isLoading = true);
    try {
      await BaseRepository.apiCall(
        method: 'POST',
        path: '/api/obhs/attendance',
        body: {
          'runInstanceId': widget.run['uid'] ?? widget.run['id'],
          'attendanceType': type,
          'imageUrl': 'https://via.placeholder.com/150', // placeholder until photo upload is integrated
          'deviceTimestamp': DateTime.now().toIso8601String(),
        },
        parser: (d) => d,
      );
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Attendance $type marked successfully!'), backgroundColor: kSuccessGreen));
      _checkAttendance();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: kErrorRed));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _completeRun() async {
    setState(() => _isLoading = true);
    try {
      await BaseRepository.apiCall(
        method: 'PUT',
        path: '/api/station-runs/${widget.run['uid'] ?? widget.run['id']}',
        body: {
          'status': 'completed',
        },
        parser: (d) => d,
      );
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Station Run Completed!'), backgroundColor: kSuccessGreen));
      setState(() {
        _isRunCompleted = true;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: kErrorRed));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final stationName = widget.run['stationName'] ?? 'Station';
    final shift = widget.run['shiftType'] ?? widget.run['shift'] ?? 'Shift';
    final date = widget.run['date'] ?? '';

    return Scaffold(
      appBar: AppBar(
        title: Text('$stationName - $shift', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: kRailwayBlue,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Card(
                    color: kRailwayBlue.withOpacity(0.05),
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: kRailwayBlue.withOpacity(0.2))),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Date: $date', style: const TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          Text('Worker: ${widget.workerName}'),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const Text('Attendance: '),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: _attendanceStatus == 'Pending' ? kWarningOrange.withOpacity(0.1) : kSuccessGreen.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(_attendanceStatus, style: TextStyle(
                                  color: _attendanceStatus == 'Pending' ? kWarningOrange : kSuccessGreen,
                                  fontWeight: FontWeight.bold,
                                )),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  if (_attendanceStatus == 'Pending')
                    ElevatedButton.icon(
                      onPressed: () => _markAttendance('start'),
                      icon: const Icon(Icons.login),
                      label: const Text('Start Attendance'),
                      style: ElevatedButton.styleFrom(backgroundColor: kRailwayBlue, foregroundColor: Colors.white, padding: const EdgeInsets.all(16)),
                    )
                  else if (_attendanceStatus == 'Started' && !_isRunCompleted) ...[
                    ElevatedButton.icon(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => GarbageFormScreen(
                            stationId: (widget.run['stationId'] ?? '').toString(),
                            stationName: (widget.run['stationName'] ?? '').toString(),
                          ),
                        ),
                      ),
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Log Garbage Disposal'),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white, padding: const EdgeInsets.all(16)),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => PestControlFormScreen(
                            stationId: (widget.run['stationId'] ?? '').toString(),
                            stationName: (widget.run['stationName'] ?? '').toString(),
                          ),
                        ),
                      ),
                      icon: const Icon(Icons.bug_report),
                      label: const Text('Log Pest Control'),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.purple, foregroundColor: Colors.white, padding: const EdgeInsets.all(16)),
                    ),
                    const SizedBox(height: 32),
                    ElevatedButton.icon(
                      onPressed: _completeRun,
                      icon: const Icon(Icons.check_circle),
                      label: const Text('Complete Run'),
                      style: ElevatedButton.styleFrom(backgroundColor: kSuccessGreen, foregroundColor: Colors.white, padding: const EdgeInsets.all(16)),
                    ),
                  ] else if (_isRunCompleted) ...[
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32.0),
                        child: Column(
                          children: [
                            Icon(Icons.check_circle, size: 64, color: kSuccessGreen),
                            SizedBox(height: 16),
                            Text('Run Completed', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: kSuccessGreen)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}
