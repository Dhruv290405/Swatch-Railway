import 'package:flutter/material.dart';
import 'package:crm_train/model/user_model.dart';
import 'package:crm_train/utills/app_colors.dart';
import 'package:crm_train/repositories/mcc_repository.dart';

class MccSupervisorVerifyScreen extends StatefulWidget {
  final UserModel user;
  const MccSupervisorVerifyScreen({super.key, required this.user});
  @override
  State<MccSupervisorVerifyScreen> createState() => _MccSupervisorVerifyScreenState();
}

class _MccSupervisorVerifyScreenState extends State<MccSupervisorVerifyScreen> {
  List<Map<String, dynamic>> _runs = [];
  Map<String, dynamic>? _selectedRun;
  List<Map<String, dynamic>> _tasks = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchRuns();
  }

  Future<void> _fetchRuns() async {
    setState(() => _loading = true);
    try {
      final resp = await MccRepository.getWashingRuns();
      _runs = List<Map<String, dynamic>>.from((resp['runs'] ?? []) as List)
          .where((r) => (r['status'] ?? '') != 'SCHEDULED')
          .toList();
      _error = null;
      if (_runs.isNotEmpty) {
        await _selectRun(_runs.first['uid'] ?? _runs.first['id']);
      } else {
        _selectedRun = null;
        _tasks = [];
      }
    } catch (e) {
      _error = e.toString();
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _selectRun(String runId) async {
    final resp = await MccRepository.getWashingRun(runId);
    _selectedRun = resp['run'];
    _tasks = List<Map<String, dynamic>>.from((resp['tasks'] ?? []) as List)
        .where((t) => ['SUBMITTED', 'REJECTED', 'APPROVED'].contains(t['status']))
        .toList();
  }

  Color _statusColor(String? status) {
    switch (status) {
      case 'APPROVED':
        return Colors.green;
      case 'SUBMITTED':
        return kRailwayBlue;
      case 'REJECTED':
        return Colors.red;
      default:
        return Colors.orange;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Verify Wash Tasks',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20)),
        backgroundColor: kRailwayBlue,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildError()
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: DropdownButtonFormField<String>(
                        initialValue: (_selectedRun?['uid'] ?? _selectedRun?['id']).toString(),
                        decoration: const InputDecoration(labelText: 'Select Run', filled: true, fillColor: Colors.white),
                        items: _runs
                            .map((r) => DropdownMenuItem<String>(
                                  value: (r['uid'] ?? r['id']).toString(),
                                  child: Text('${r['trainNo'] ?? ''} — ${r['status'] ?? ''}'),
                                ))
                            .toList(),
                        onChanged: (v) async {
                          if (v == null) return;
                          try {
                            await _selectRun(v);
                          } catch (e) {
                            _error = e.toString();
                          }
                          if (mounted) setState(() {});
                        },
                      ),
                    ),
                    if (_selectedRun == null)
                      Expanded(
                        child: Center(
                          child: Text('No runs to verify yet.', style: TextStyle(color: Colors.grey[500])),
                        ),
                      )
                    else
                      Expanded(
                        child: RefreshIndicator(
                          onRefresh: () => _selectRun(_selectedRun?['uid'] ?? _selectedRun?['id']),
                          child: ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            itemCount: _tasks.length,
                            itemBuilder: (_, i) => _buildTaskCard(_tasks[i]),
                          ),
                        ),
                      ),
                  ],
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
        ElevatedButton(onPressed: _fetchRuns, child: const Text('Retry')),
      ],
    );
  }

  Widget _buildTaskCard(Map<String, dynamic> task) {
    final status = task['status'] ?? '';
    final taskId = task['uid'] ?? task['id'];
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Coach ${task['coachNo'] ?? ''}',
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
              Chip(
                label: Text(status),
                labelStyle: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                backgroundColor: _statusColor(status),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text('Assigned: ${task['assignedWorkerName'] ?? 'Unassigned'}',
              style: TextStyle(color: Colors.grey[600], fontSize: 13)),
          if (task['rejectionReason'] != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('Rejected: ${task['rejectionReason']}',
                  style: const TextStyle(color: Colors.red, fontSize: 13)),
            ),
          if (status == 'SUBMITTED') ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _reject(taskId),
                    icon: const Icon(Icons.close),
                    label: const Text('Reject'),
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _approveWithRemarks(taskId),
                    icon: const Icon(Icons.check),
                    label: const Text('Approve'),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  void _approveWithRemarks(String taskId) {
    final remarksCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Approve Task'),
        content: TextField(
          controller: remarksCtrl,
          decoration: const InputDecoration(labelText: 'Remarks (optional)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _approve(taskId, remarks: remarksCtrl.text.trim());
            },
            child: const Text('Approve'),
          ),
        ],
      ),
    );
  }

  Future<void> _approve(String taskId, {String? remarks}) async {
    try {
      await MccRepository.approveTask(taskId, remarks: remarks);
      _reload();
    } catch (e) {
      _showSnack(e);
    }
  }

  Future<void> _reject(String taskId) async {
    final reasonCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reject Task'),
        content: TextField(
          controller: reasonCtrl,
          decoration: const InputDecoration(labelText: 'Reason *'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await MccRepository.rejectTask(taskId, reason: reasonCtrl.text.trim().isEmpty
                    ? 'Not satisfactory'
                    : reasonCtrl.text.trim());
                _reload();
              } catch (e) {
                _showSnack(e);
              }
            },
            child: const Text('Reject'),
          ),
        ],
      ),
    );
  }

  Future<void> _reload() async {
    final runId = _selectedRun?['uid'] ?? _selectedRun?['id'];
    if (runId == null) return;
    try {
      await _selectRun(runId);
    } catch (e) {
      _error = e.toString();
    }
    if (mounted) setState(() {});
  }

  void _showSnack(Object e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))));
  }
}