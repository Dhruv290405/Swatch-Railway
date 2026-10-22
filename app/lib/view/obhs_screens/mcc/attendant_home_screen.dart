import 'package:flutter/material.dart';
import 'package:crm_train/model/user_model.dart';
import 'package:crm_train/utills/app_colors.dart';
import 'package:crm_train/repositories/worker_repo.dart';
import '../../../providers/auth_provider.dart';
import 'package:provider/provider.dart';

import 'obhs_coach_checklist_screen.dart';
import 'attendant_linen_screen.dart';
import 'obhs_attendance_screen.dart';

class AttendantHomeScreen extends StatefulWidget {
  final UserModel user;
  const AttendantHomeScreen({super.key, required this.user});
  @override
  State<AttendantHomeScreen> createState() => _AttendantHomeScreenState();
}

class _AttendantHomeScreenState extends State<AttendantHomeScreen> {
  Map<String, dynamic>? _runData;
  List<Map<String, dynamic>> _coaches = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchAssignment();
  }

  Future<void> _fetchAssignment() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final resp = await WorkerRepository.getActiveRun();
      if (resp['success'] == true && resp['hasAssignment'] == true) {
        _runData = resp['run'];
        final allCoaches = List<Map<String, dynamic>>.from(resp['coaches'] ?? []);
        // Attendants are only responsible for AC coaches assigned to them.
        _coaches = allCoaches.where((c) {
          final isAtt = c['isAttendant'] == true ||
              (c['workerRole'] ?? '').toString().toLowerCase() == 'attendant';
          final coachType = (c['coachType'] ?? '').toString().toLowerCase();
          return isAtt || coachType.contains('ac');
        }).toList();
      } else {
        _runData = null;
        _coaches = [];
      }
    } catch (e) {
      _error = e.toString();
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('My Duty (Attendant)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20)),
        backgroundColor: kRailwayBlue, elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            onPressed: () {
              Provider.of<AuthProvider>(context, listen: false).logout();
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _fetchAssignment,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? _buildError()
                : _runData == null
                    ? _buildEmptyState()
                    : _buildContent(),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(context, MaterialPageRoute(builder: (_) => AttendantLinenScreen(user: widget.user)));
        },
        backgroundColor: kRailwayBlue,
        icon: const Icon(Icons.local_laundry_service, color: Colors.white),
        label: const Text('Manage Linen', style: TextStyle(color: Colors.white)),
      ),
    );
  }

  Widget _buildError() {
    return ListView(
      padding: const EdgeInsets.all(32),
      children: [
        const SizedBox(height: 60),
        const Icon(Icons.cloud_off, size: 64, color: Colors.grey),
        const SizedBox(height: 16),
        const Text('Connection Error', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
        const SizedBox(height: 8),
        Text('$_error', style: TextStyle(color: Colors.grey[600]), textAlign: TextAlign.center),
        const SizedBox(height: 24),
        ElevatedButton(onPressed: _fetchAssignment, child: const Text('Retry')),
      ],
    );
  }

  Widget _buildEmptyState() {
    return ListView(
      padding: const EdgeInsets.all(32),
      children: [
        const SizedBox(height: 60),
        Icon(Icons.check_circle_outline, size: 80, color: Colors.grey[300]),
        const SizedBox(height: 16),
        const Text('No AC coaches assigned yet.', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.black54)),
        const SizedBox(height: 8),
        Text('Wait for your supervisor to assign duties.', style: TextStyle(color: Colors.grey[500])),
        const SizedBox(height: 24),
        OutlinedButton(onPressed: _fetchAssignment, child: const Text('Refresh')),
      ],
    );
  }

  Widget _buildContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeaderAndOverview(),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text('My Assigned AC Coaches', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87)),
        ),
        if (_coaches.isEmpty)
          Expanded(child: Center(child: Text('No coaches assigned', style: TextStyle(color: Colors.grey[500]))))
        else
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _coaches.length,
              itemBuilder: (_, i) => _buildCoachTile(_coaches[i]),
            ),
          ),
      ],
    );
  }

  Widget _buildHeaderAndOverview() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.only(left: 20, right: 20, top: 20, bottom: 30),
      decoration: const BoxDecoration(
        color: kRailwayBlue,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(30),
          bottomRight: Radius.circular(30),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Hello, ${widget.user.fullName}',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Train: ${_runData?['trainNo'] ?? 'N/A'} ${_runData?['trainName'] ?? ''}',
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
              InkWell(
                onTap: () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => ObhsAttendanceScreen(user: widget.user)));
                },
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.greenAccent.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.greenAccent.withOpacity(0.5)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.fingerprint, color: Colors.greenAccent, size: 14),
                      SizedBox(width: 4),
                      Text('PRESENT', style: TextStyle(color: Colors.greenAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildOverviewCard('Linen Tasks', '${_coaches.length}', Icons.local_laundry_service, Colors.orange),
              _buildOverviewCard('Coaches', '${_coaches.length}', Icons.airline_seat_recline_extra, Colors.green),
              _buildOverviewCard('Requests', '0', Icons.person_pin_circle, Colors.red),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOverviewCard(String title, String count, IconData icon, Color color) {
    return Container(
      width: 100,
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 8),
          Text(
            count,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.8)),
          ),
        ],
      ),
    );
  }

  Widget _buildCoachTile(Map<String, dynamic> coach) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: InkWell(
        onTap: () => Navigator.push(context, MaterialPageRoute(
          builder: (_) => ObhsCoachChecklistScreen(
            user: widget.user, coachLabel: coach['coachNo'] ?? 'N/A',
            runInstanceId: _runData?['runInstanceId'],
          ))),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: kRailwayBlue.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.airline_seat_recline_extra, color: kRailwayBlue, size: 32),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Coach ${coach['coachNo']}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(coach['coachType'] ?? 'AC', style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }
}