import 'package:flutter/material.dart';
import 'package:crm_train/model/user_model.dart';
import 'package:crm_train/utills/app_colors.dart';
import 'package:crm_train/repositories/mcc_repository.dart';
import 'package:crm_train/providers/auth_provider.dart';
import 'package:provider/provider.dart';

import 'mcc_attendance_screen.dart';

class MccWorkerTaskBoardScreen extends StatefulWidget {
  final UserModel user;
  const MccWorkerTaskBoardScreen({super.key, required this.user});
  @override
  State<MccWorkerTaskBoardScreen> createState() => _MccWorkerTaskBoardScreenState();
}

class _MccWorkerTaskBoardScreenState extends State<MccWorkerTaskBoardScreen> {
  List<Map<String, dynamic>> _tasks = [];
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
      final resp = await MccRepository.getWorkerTasks();
      _tasks = List<Map<String, dynamic>>.from((resp['tasks'] ?? []) as List);
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
        title: const Text('My Wash Tasks',
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(context, MaterialPageRoute(builder: (_) => MccAttendanceScreen(user: widget.user)));
        },
        backgroundColor: kRailwayBlue,
        icon: const Icon(Icons.fingerprint, color: Colors.white),
        label: const Text('Attendance', style: TextStyle(color: Colors.white)),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 30),
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
              Text('Hello, ${widget.user.fullName}',
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
              const SizedBox(height: 4),
              Text('Mechanised Coach Cleaning · Your wash duties',
                  style: TextStyle(fontSize: 14, color: Colors.white.withValues(alpha: 0.85))),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _overviewCard('My Tasks', '${_tasks.length}'),
                  _overviewCard(
                      'Pending', '${_tasks.where((t) => !['SUBMITTED', 'APPROVED'].contains(t['status'])).length}'),
                  _overviewCard(
                      'Approved', '${_tasks.where((t) => t['status'] == 'APPROVED').length}'),
                ],
              ),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text('Assigned Coaches', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87)),
        ),
        Expanded(
          child: _tasks.isEmpty
              ? Center(child: Text('No wash tasks assigned.', style: TextStyle(color: Colors.grey[500])))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _tasks.length,
                  itemBuilder: (_, i) => _buildTaskTile(_tasks[i]),
                ),
        ),
      ],
    );
  }

  Widget _overviewCard(String title, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
          Text(title, style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.85))),
        ],
      ),
    );
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

  Widget _buildTaskTile(Map<String, dynamic> task) {
    final status = task['status'] ?? 'OPEN';
    final open = !['SUBMITTED', 'APPROVED', 'REJECTED'].contains(status);
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: InkWell(
        onTap: open ? () => _showSubmitSheet(task) : null,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(18),
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
              const SizedBox(height: 8),
              if (task['rejectionReason'] != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text('Rejected: ${task['rejectionReason']}',
                      style: const TextStyle(color: Colors.red, fontSize: 13)),
                ),
              if (open)
                const Text('Tap to submit washing evidence.',
                    style: TextStyle(color: Colors.grey, fontSize: 13))
              else
                Text('Submitted ${_fmtTime(task['submittedAt'])}',
                    style: TextStyle(color: Colors.grey[500], fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }

  String _fmtTime(String? iso) {
    if (iso == null) return '';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    final local = dt.toLocal();
    return '${local.day}/${local.month} ${local.hour}:${local.minute.toString().padLeft(2, '0')}';
  }

  void _showSubmitSheet(Map<String, dynamic> task) {
    final afterPhotoCtrl = TextEditingController();
    final remarksCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final taskId = task['uid'] ?? task['id'];
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Submit Wash — Coach ${task['coachNo'] ?? ''}',
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                TextFormField(
                  controller: afterPhotoCtrl,
                  decoration: const InputDecoration(labelText: 'After-wash photo URL *'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: remarksCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Remarks'),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () async {
                      if (!formKey.currentState!.validate()) return;
                      try {
                        await MccRepository.submitTask({
                          'taskId': taskId,
                          'afterPhoto': afterPhotoCtrl.text.trim(),
                          'remarks': remarksCtrl.text.trim(),
                        });
                        if (ctx.mounted) Navigator.pop(ctx);
                        _fetch();
                      } catch (e) {
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                              SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))));
                        }
                      }
                    },
                    style: ElevatedButton.styleFrom(backgroundColor: kRailwayBlue),
                    child: const Text('Submit', style: TextStyle(color: Colors.white)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}