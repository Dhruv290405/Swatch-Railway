import 'package:crm_train/model/analytics_model.dart';
import 'package:crm_train/repositories/analytics_repository.dart';
import 'package:crm_train/utills/app_colors.dart';
import 'package:flutter/material.dart';

import 'widgets/obhs_run_scope.dart';

/// Performance dashboard for OBHS: per-janitor completion, per-coach
/// cleanliness, attendance compliance, task completion and penalty risk.
class ObhsAnalyticsScreen extends StatefulWidget {
  final String? initialRunInstanceId;

  const ObhsAnalyticsScreen({super.key, this.initialRunInstanceId});

  @override
  State<ObhsAnalyticsScreen> createState() => _ObhsAnalyticsScreenState();
}

class _ObhsAnalyticsScreenState extends State<ObhsAnalyticsScreen> {
  String? _runId;
  bool _loading = false;
  String? _error;

  List<JanitorPerformanceModel> _janitors = [];
  List<CoachCleanlinessModel> _coaches = [];
  Map<String, dynamic> _attendance = {};
  Map<String, dynamic> _tasks = {};
  Map<String, dynamic> _penalties = {};

  @override
  void initState() {
    super.initState();
    if (widget.initialRunInstanceId != null) {
      _runId = widget.initialRunInstanceId;
      _load(widget.initialRunInstanceId!);
    }
  }

  Future<void> _load(String runId) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Fetch the panels independently so one failing metric does not blank
      // the whole dashboard.
      final results = await Future.wait([
        _guard(() => AnalyticsRepository.getJanitorPerformance(runId)),
        _guard(() => AnalyticsRepository.getCoachCleanliness(runId)),
        _guard(() => AnalyticsRepository.getAttendanceCompliance(runInstanceId: runId)),
        _guard(() => AnalyticsRepository.getTaskCompletionPercentage(runInstanceId: runId)),
        _guard(() => AnalyticsRepository.getPenaltyRiskReport(runInstanceId: runId)),
      ]);
      if (!mounted) return;
      setState(() {
        _janitors = (results[0] as List?)?.cast<JanitorPerformanceModel>() ?? [];
        _coaches = (results[1] as List?)?.cast<CoachCleanlinessModel>() ?? [];
        _attendance = (results[2] as Map?)?.cast<String, dynamic>() ?? {};
        _tasks = (results[3] as Map?)?.cast<String, dynamic>() ?? {};
        _penalties = (results[4] as Map?)?.cast<String, dynamic>() ?? {};
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceAll('Exception: ', '');
        _loading = false;
      });
    }
  }

  Future<T?> _guard<T>(Future<T> Function() fn) async {
    try {
      return await fn();
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('OBHS Analytics',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: kRailwayBlue,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (_runId != null)
            IconButton(
                icon: const Icon(Icons.refresh), onPressed: () => _load(_runId!)),
        ],
      ),
      body: Column(
        children: [
          ObhsRunScope(
            initialRunInstanceId: widget.initialRunInstanceId,
            onRunChanged: (id) {
              setState(() => _runId = id);
              _load(id);
            },
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.error_outline,
                                size: 48, color: Colors.grey),
                            const SizedBox(height: 12),
                            Text(_error!,
                                style: const TextStyle(color: Colors.grey)),
                            const SizedBox(height: 12),
                            ElevatedButton(
                                onPressed: () => _load(_runId ?? ''),
                                child: const Text('Retry')),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: () => _load(_runId!),
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                          children: [
                            _complianceRow(),
                            const SizedBox(height: 16),
                            _sectionTitle('Task completion'),
                            _kvCard(_tasks, const ['completionPercentage', 'completedTasks', 'pendingTasks', 'overdueTasks', 'totalTasks']),
                            const SizedBox(height: 16),
                            _sectionTitle('Penalty risk'),
                            _kvCard(_penalties, const ['riskScore', 'riskLevel', 'atRiskWorkers', 'penaltiesPending']),
                            const SizedBox(height: 16),
                            _sectionTitle('Janitor performance'),
                            if (_janitors.isEmpty)
                              _empty('No janitor data for this run')
                            else
                              ..._janitors.map((j) => _JanitorTile(model: j)),
                            const SizedBox(height: 16),
                            _sectionTitle('Coach cleanliness'),
                            if (_coaches.isEmpty)
                              _empty('No coach cleanliness data for this run')
                            else
                              ..._coaches.map((c) => _CoachTile(model: c)),
                          ],
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _complianceRow() {
    return Row(
      children: [
        Expanded(
          child: _metricCard(
            'Attendance',
            _pct(_attendance['compliancePercentage']),
            kRailwayBlue,
            Icons.event_available,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _metricCard(
            'Task completion',
            _pct(_tasks['completionPercentage']),
            kSuccessGreen,
            Icons.check_circle_outline,
          ),
        ),
      ],
    );
  }

  static String _pct(dynamic v) {
    if (v is num) {
      final n = v.toDouble();
      // Backend sends either 0-1 ratios or 0-100 percentages.
      final pctv = n <= 1.0 ? n * 100 : n;
      return '${pctv.toStringAsFixed(1)}%';
    }
    final parsed = double.tryParse('$v');
    if (parsed == null) return '—';
    final pctv = parsed <= 1.0 ? parsed * 100 : parsed;
    return '${pctv.toStringAsFixed(1)}%';
  }

  Widget _metricCard(String label, String value, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 10),
          Text(value,
              style: TextStyle(
                  fontSize: 24, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }

  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(t,
            style: const TextStyle(
                fontWeight: FontWeight.bold, fontSize: 15)),
      );

  Widget _empty(String msg) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(msg,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
      );

  Widget _kvCard(Map<String, dynamic> data, List<String> keys) {
    final entries =
        keys.where((k) => data.containsKey(k) && data[k] != null).toList();
    if (entries.isEmpty) return _empty('No data available');
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        child: Column(
          children: entries.map((k) {
            final v = data[k];
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(_humanise(k),
                        style: const TextStyle(fontSize: 13)),
                  ),
                  Text(
                    v is num ? v.toString() : '$v',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  static String _humanise(String key) {
    final words =
        key.replaceAllMapped(RegExp('([A-Z])'), (m) => ' ${m[1]}').trim();
    return words[0].toUpperCase() + words.substring(1);
  }
}

class _JanitorTile extends StatelessWidget {
  final JanitorPerformanceModel model;

  const _JanitorTile({required this.model});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(top: 8),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: kRailwayBlue.withOpacity(0.1),
                  child: Text(
                    model.workerName.isEmpty
                        ? '?'
                        : model.workerName.substring(0, 1).toUpperCase(),
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, color: kRailwayBlue),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    model.workerName.isEmpty ? 'Unassigned' : model.workerName,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                ),
                ObhsStatusPill(
                  label: model.completionPercentage >= 90
                      ? 'excellent'
                      : model.completionPercentage >= 70
                          ? 'on track'
                          : 'at risk',
                  color: model.completionPercentage >= 90
                      ? kSuccessGreen
                      : model.completionPercentage >= 70
                          ? kWarningOrange
                          : kErrorRed,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _stat('Done', '${model.tasksCompleted}', kSuccessGreen),
                _stat('Missed', '${model.tasksMissed}', kErrorRed),
                _stat('Overdue', '${model.tasksOverdue}', kWarningOrange),
                _stat('Rating',
                    model.averageRating.toStringAsFixed(1), kRailwayBlue),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: (model.completionPercentage / 100).clamp(0.0, 1.0),
                minHeight: 7,
                backgroundColor: Colors.grey.shade200,
                valueColor: AlwaysStoppedAnimation<Color>(
                  model.completionPercentage >= 90
                      ? kSuccessGreen
                      : model.completionPercentage >= 70
                          ? kWarningOrange
                          : kErrorRed,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stat(String label, String value, Color color) {
    return Expanded(
      child: Column(
        children: [
          Text(value,
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.bold, color: color)),
          Text(label, style: const TextStyle(fontSize: 10)),
        ],
      ),
    );
  }
}

class _CoachTile extends StatelessWidget {
  final CoachCleanlinessModel model;

  const _CoachTile({required this.model});

  @override
  Widget build(BuildContext context) {
    final color = model.cleanlinessScore >= 80
        ? kSuccessGreen
        : model.cleanlinessScore >= 50
            ? kWarningOrange
            : kErrorRed;
    return Card(
      margin: const EdgeInsets.only(top: 8),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.train, size: 18, color: kRailwayBlue),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Coach ${model.coachNo}',
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 14)),
                ),
                Text(
                  '${model.cleanlinessScore.toStringAsFixed(0)}%',
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold, color: color),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: (model.cleanlinessScore / 100).clamp(0.0, 1.0),
                minHeight: 7,
                backgroundColor: Colors.grey.shade200,
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Toilets ${model.toiletCompletions}/${model.totalToiletTasks}',
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
                Text('Water issues: ${model.waterIssues}',
                    style: const TextStyle(fontSize: 11)),
                const SizedBox(width: 12),
                Text('Garbage: ${model.garbageIssues}',
                    style: const TextStyle(fontSize: 11)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
