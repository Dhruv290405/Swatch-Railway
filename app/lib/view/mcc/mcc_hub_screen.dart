import 'package:flutter/material.dart';
import 'package:crm_train/model/user_model.dart';
import 'package:crm_train/utills/app_colors.dart';
import 'package:crm_train/repositories/mcc_repository.dart';
import 'package:crm_train/providers/auth_provider.dart';
import 'package:provider/provider.dart';

import 'mcc_depots_screen.dart';
import 'mcc_washing_runs_screen.dart';
import 'mcc_attendance_screen.dart';
import 'mcc_supervisor_verify_screen.dart';

class MccHubScreen extends StatefulWidget {
  final UserModel user;
  const MccHubScreen({super.key, required this.user});
  @override
  State<MccHubScreen> createState() => _MccHubScreenState();
}

class _MccHubScreenState extends State<MccHubScreen> {
  Map<String, dynamic>? _dashboard;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() => _loading = true);
    try {
      final resp = await MccRepository.getDashboard();
      _dashboard = resp['dashboard'] ?? resp;
      _error = null;
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
        title: const Text('MCC - Washing Depot',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20)),
        backgroundColor: kRailwayBlue,
        elevation: 0,
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
        onRefresh: _fetch,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? _buildError()
                : _buildContent(),
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
        const Text('Connection Error',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
        const SizedBox(height: 8),
        Text('$_error', style: TextStyle(color: Colors.grey[600]), textAlign: TextAlign.center),
        const SizedBox(height: 24),
        ElevatedButton(onPressed: _fetch, child: const Text('Retry')),
      ],
    );
  }

  Widget _buildContent() {
    final runs = (_dashboard?['runs'] ?? {}) as Map<String, dynamic>? ?? const {};
    final tasks = (_dashboard?['tasks'] ?? {}) as Map<String, dynamic>? ?? const {};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
          child: Text('Depot Operations', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey[900])),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _buildGrid(),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
          child: Text('Washing Runs', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey[900])),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            children: [
              _buildRunRow('Scheduled', '${(runs['scheduled'] ?? 0)}', Icons.schedule, Colors.orange),
              _buildRunRow('In Progress', '${(runs['inProgress'] ?? 0)}', Icons.autorenew, kRailwayBlue),
              _buildRunRow('Completed', '${(runs['completed'] ?? 0)}', Icons.check_circle, Colors.green),
              _buildRunRow('Open Coach Tasks', '${(tasks['open'] ?? 0)}', Icons.pending_actions, Colors.redAccent),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
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
          Text(
            'Hello, ${widget.user.fullName}',
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 4),
          Text(
            'Mechanised Coach Cleaning · Washing Plant / Depot',
            style: TextStyle(fontSize: 14, color: Colors.white.withValues(alpha: 0.8)),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildOverviewCard('Depots', '${_dashboard?['depots'] ?? 0}', Icons.factory_outlined, Colors.cyanAccent),
              _buildOverviewCard('Runs', runsTotalString(), Icons.train, Colors.amberAccent),
              _buildOverviewCard('Approved', '${(_dashboard?['tasks'] ?? const {})['approved'] ?? 0}',
                  Icons.verified, Colors.greenAccent),
            ],
          ),
        ],
      ),
    );
  }

  String runsTotalString() {
    final runs = (_dashboard?['runs'] ?? {}) as Map<String, dynamic>? ?? const {};
    return '${(runs['total'] ?? 0)}';
  }

  Widget _buildOverviewCard(String title, String count, IconData icon, Color color) {
    return Container(
      width: 100,
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 8),
          Text(count, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 4),
          Text(title, style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.8))),
        ],
      ),
    );
  }

  Widget _buildGrid() {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.6,
      children: [
        _navTile(Icons.factory_outlined, 'Depots', _openDepots),
        _navTile(Icons.train, 'Washing Runs', _openRuns),
        _navTile(Icons.fingerprint, 'Attendance', _openAttendance),
        _navTile(Icons.verified_outlined, 'Verify Tasks', _openVerify),
      ],
    );
  }

  Widget _navTile(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: kRailwayBlue, size: 32),
            const SizedBox(height: 8),
            Text(label, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87)),
          ],
        ),
      ),
    );
  }

  Widget _buildRunRow(String title, String count, IconData icon, Color color) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 12),
          Expanded(child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
          Text(count, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black87)),
        ],
      ),
    );
  }

  void _openDepots() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const MccDepotsScreen()));
  }

  void _openRuns() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const MccWashingRunsScreen()));
  }

  void _openAttendance() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => MccAttendanceScreen(user: widget.user)));
  }

  void _openVerify() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => MccSupervisorVerifyScreen(user: widget.user)));
  }
}