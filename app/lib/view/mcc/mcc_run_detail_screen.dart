import 'package:flutter/material.dart';
import 'package:crm_train/utills/app_colors.dart';
import 'package:crm_train/repositories/mcc_repository.dart';

class MccRunDetailScreen extends StatefulWidget {
  final String runId;
  final Map<String, dynamic>? initial;
  const MccRunDetailScreen({super.key, required this.runId, this.initial});
  @override
  State<MccRunDetailScreen> createState() => _MccRunDetailScreenState();
}

class _MccRunDetailScreenState extends State<MccRunDetailScreen> {
  Map<String, dynamic>? _run;
  List<Map<String, dynamic>> _tasks = [];
  bool _loading = true;
  String? _error;

  String get _runId => _run?['uid'] ?? widget.runId;

  @override
  void initState() {
    super.initState();
    _run = widget.initial;
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() => _loading = true);
    try {
      final resp = await MccRepository.getWashingRun(widget.runId);
      _run = resp['run'] ?? _run;
      _tasks = List<Map<String, dynamic>>.from((resp['tasks'] ?? []) as List);
      _error = null;
    } catch (e) {
      _error = e.toString();
    }
    if (mounted) setState(() => _loading = false);
  }

  Color _statusColor(String? status) {
    switch (status) {
      case 'APPROVED':
      case 'COMPLETED':
        return Colors.green;
      case 'SUBMITTED':
      case 'IN_PROGRESS':
        return kRailwayBlue;
      case 'REJECTED':
      case 'CANCELLED':
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
        title: Text(_run?['trainNo'] ?? 'Run Detail',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20)),
        backgroundColor: kRailwayBlue,
        elevation: 0,
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
    final status = _run?['status'] ?? 'SCHEDULED';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
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
                  Text(_run?['trainNo'] ?? 'N/A',
                      style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white)),
                  Chip(
                    label: Text(status),
                    labelStyle: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                    backgroundColor: _statusColor(status),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text('${_run?['trainName'] ?? ''} · ${_run?['depotName'] ?? ''}',
                  style: TextStyle(fontSize: 14, color: Colors.white.withValues(alpha: 0.85))),
              Text('${_run?['scheduledDate'] ?? ''} ${_run?['scheduledTime'] ?? ''}',
                  style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.7))),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _overviewCard('Coaches', '${(_run?['coachNos'] ?? []).length}'),
                  _overviewCard('Approved', '${_run?['approvedTaskCount'] ?? 0}'),
                  _overviewCard('Completed', '${_run?['completedTaskCount'] ?? 0}'),
                ],
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Coach Tasks',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87)),
              if (status == 'SCHEDULED')
                TextButton.icon(
                  onPressed: _startRun,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Start Run'),
                )
              else if (status == 'IN_PROGRESS')
                TextButton.icon(
                  onPressed: _completeRun,
                  icon: const Icon(Icons.flag),
                  label: const Text('Complete Run'),
                ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
          Text(title, style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.8))),
        ],
      ),
    );
  }

  Widget _buildTaskTile(Map<String, dynamic> task) {
    final status = task['status'] ?? 'OPEN';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _statusColor(status).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.train, color: _statusColor(status)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Coach ${task['coachNo'] ?? ''}',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Text(
                  'Assigned: ${task['assignedWorkerName'] ?? 'Unassigned'}',
                  style: TextStyle(color: Colors.grey[600], fontSize: 13),
                ),
              ],
            ),
          ),
          Chip(
            label: Text(status),
            labelStyle: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
            backgroundColor: _statusColor(status),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  Future<void> _startRun() async {
    try {
      await MccRepository.startWashingRun(_runId);
      _fetch();
    } catch (e) {
      _error = e.toString();
      _fetch();
    }
  }

  Future<void> _completeRun() async {
    try {
      await MccRepository.completeWashingRun(_runId);
      _fetch();
    } catch (e) {
      _error = e.toString();
      _fetch();
    }
  }
}