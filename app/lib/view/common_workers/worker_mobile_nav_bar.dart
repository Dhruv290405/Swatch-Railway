import 'package:crm_train/controllers/worker_controller.dart';
import 'package:crm_train/model/user_model.dart';
import 'package:crm_train/repositories/station_run_repository.dart';
import 'package:crm_train/view/common_workers/worker_attendance_screen.dart';
import 'package:crm_train/view/common_workers/worker_complaints_screen.dart';
import 'package:crm_train/view/common_workers/worker_mobile_home_screen.dart';
import 'package:crm_train/view/common_workers/worker_rating_screen.dart';
import 'package:crm_train/view/common_workers/worker_task_screen.dart';
import 'package:crm_train/view/station_cleaning/attendance/worker_attendance_screen.dart'
    as station_cleaning;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:persistent_bottom_nav_bar/persistent_bottom_nav_bar.dart';
import '../../utills/app_colors.dart';

class WorkerMobileNavBar extends StatefulWidget {
  final UserModel user;

  const WorkerMobileNavBar({super.key, required this.user});

  @override
  State<WorkerMobileNavBar> createState() => _WorkerMobileNavBarState();
}

class _WorkerMobileNavBarState extends State<WorkerMobileNavBar> {
  late WorkerController workerController;

  @override
  void initState() {
    super.initState();

    workerController = Get.put(WorkerController());
    workerController.setUser(widget.user);
  }

  @override
  void dispose() {
    Get.delete<WorkerController>();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PersistentTabView(
      context,
      screens: _buildScreens(),
      items: _buildNavItems(),
      confineToSafeArea: true,
      backgroundColor: Colors.white,
      handleAndroidBackButtonPress: true,
      resizeToAvoidBottomInset: true,
      stateManagement: true,
      decoration: NavBarDecoration(
        borderRadius: BorderRadius.circular(15.0),
        colorBehindNavBar: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      navBarStyle: NavBarStyle.style12,
    );
  }

  List<Widget> _buildScreens() {
    return [
      WorkerMobileHomeScreen(),
      const WorkerTaskScreen(),
      const WorkerAttendanceScreen(),
      WorkerComplaintsScreen(),
      const WorkerRatingScreen(isOfficialMode: false),
    ];
  }

  List<PersistentBottomNavBarItem> _buildNavItems() {
    return [
      PersistentBottomNavBarItem(
        icon: const Icon(Icons.dashboard_rounded),
        title: "Home",
        activeColorPrimary: kRailwayBlue,
        inactiveColorPrimary: Colors.grey,
      ),
      PersistentBottomNavBarItem(
        icon: const Icon(Icons.event_note_rounded),
        title: "Tasks",
        activeColorPrimary: kRailwayBlue,
        inactiveColorPrimary: Colors.grey,
      ),
      PersistentBottomNavBarItem(
        icon: const Icon(Icons.fingerprint_rounded),
        title: "Attendance",
        activeColorPrimary: kRailwayBlue,
        inactiveColorPrimary: Colors.grey,
      ),
      PersistentBottomNavBarItem(
        icon: const Icon(Icons.report_rounded),
        title: "Complaints",
        activeColorPrimary: kRailwayBlue,
        inactiveColorPrimary: Colors.grey,
      ),
      PersistentBottomNavBarItem(
        icon: const Icon(Icons.star_rounded),
        title: "Ratings",
        activeColorPrimary: kRailwayBlue,
        inactiveColorPrimary: Colors.grey,
      ),
    ];
  }
}

class _AttendanceTab extends StatefulWidget {
  const _AttendanceTab();

  @override
  State<_AttendanceTab> createState() => _AttendanceTabState();
}

class _AttendanceTabState extends State<_AttendanceTab> {
  String? _runInstanceId;
  String? _stationId;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  Future<void> _resolve() async {
    final user = Get.find<WorkerController>().currentUser.value;
    final workerId = user?.uid ?? '';
    final today = DateTime.now().toIso8601String().split('T')[0];

    String? sid;
    try {
      final runs = await StationRunRepository.getMyStationRuns();
      if (runs.isNotEmpty) {
        sid = runs.first.stationId;
      }
    } catch (_) {}
    sid ??= user?.stationId;
    if (sid == null || sid.isEmpty) sid = workerId;

    if (mounted) {
      setState(() {
        _stationId = sid;
        _runInstanceId = '${sid}_$today';
        _loading = false;
      });
    }
  }

  void _openTypeDialog() {
    final user = Get.find<WorkerController>().currentUser.value;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Select Attendance Type'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _typeBtn(
              ctx,
              user?.uid ?? '',
              user?.fullName ?? '',
              'start',
              'Start Attendance',
              Icons.play_arrow,
              Colors.green,
            ),
            const SizedBox(height: 8),
            _typeBtn(
              ctx,
              user?.uid ?? '',
              user?.fullName ?? '',
              'mid',
              'Mid Attendance',
              Icons.pause,
              Colors.orange,
            ),
            const SizedBox(height: 8),
            _typeBtn(
              ctx,
              user?.uid ?? '',
              user?.fullName ?? '',
              'end',
              'End Attendance',
              Icons.stop,
              Colors.red,
            ),
          ],
        ),
      ),
    );
  }

  Widget _typeBtn(
    BuildContext context,
    String workerId,
    String workerName,
    String type,
    String label,
    IconData icon,
    Color color,
  ) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: () {
          Navigator.pop(context);
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => station_cleaning.StationWorkerAttendanceScreen(
                workerId: workerId,
                workerName: workerName,
                runInstanceId: _runInstanceId ?? '',
                stationId: _stationId ?? '',
                attendanceType: type,
              ),
            ),
          );
        },
        icon: Icon(icon),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text(
          'Attendance',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: kRailwayBlue,
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cleaning_services, size: 64, color: Colors.teal),
            const SizedBox(height: 16),
            const Text(
              'Station Cleaning Attendance',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _openTypeDialog,
              icon: const Icon(Icons.fingerprint),
              label: const Text('Mark Attendance'),
              style: ElevatedButton.styleFrom(
                backgroundColor: kRailwayBlue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
