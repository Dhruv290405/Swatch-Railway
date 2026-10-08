import 'package:crm_train/model/run_instance_model.dart';
import 'package:crm_train/model/water_check_model.dart';
import 'package:crm_train/repositories/obhs_repository.dart';
import 'package:crm_train/repositories/water_repository.dart';
import 'package:crm_train/utills/app_colors.dart';
import 'package:flutter/material.dart';

import 'widgets/obhs_run_scope.dart';

/// Water points on a coach, checked per run. Low/empty tanks raise an alert
/// that the depot acts on before the next departure.
class ObhsWaterChecksScreen extends StatefulWidget {
  final String? initialRunInstanceId;

  const ObhsWaterChecksScreen({super.key, this.initialRunInstanceId});

  @override
  State<ObhsWaterChecksScreen> createState() => _ObhsWaterChecksScreenState();
}

class _ObhsWaterChecksScreenState extends State<ObhsWaterChecksScreen> {
  String? _runId;
  List<RunInstanceModel> _runs = [];
  List<WaterCheckModel> _checks = [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadRuns();
  }

  Future<void> _loadRuns() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final runs = await OBHSRepository.getAllRunInstances();
      if (!mounted) return;
      setState(() {
        _runs = runs;
        _loading = false;
        _runId = _resolveInitialRun(runs);
      });
      if (_runId != null) await _loadChecks(_runId!);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceAll('Exception: ', '');
        _loading = false;
      });
    }
  }

  String? _resolveInitialRun(List<RunInstanceModel> runs) {
    if (widget.initialRunInstanceId != null) return widget.initialRunInstanceId;
    for (final r in runs) {
      if (r.status.toLowerCase() == 'active' || r.status.toLowerCase() == 'ready') {
        return r.runInstanceId ?? r.id;
      }
    }
    return runs.isEmpty ? null : (runs.first.runInstanceId ?? runs.first.id);
  }

  Future<void> _loadChecks(String runId) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final checks = await WaterRepository.getWaterChecks(runId);
      if (!mounted) return;
      setState(() {
        _checks = checks;
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

  /// Backend may store coach numbers as `1`, `'1'` or `'C1'`; normalise so
  /// checks always match the coach card they belong to.
  String _norm(dynamic v) {
    var s = v.toString().trim().toUpperCase();
    if (s.startsWith('C') && s.length > 1) s = s.substring(1);
    return s;
  }

  List<String> get _coachNumbers {
    if (_runId == null) return [];
    final run = _runs.where((r) => (r.runInstanceId ?? r.id) == _runId);
    if (run.isEmpty) return [];
    return run.first.coaches
        .map((c) => 'C${c.coachPosition}')
        .toSet()
        .toList()
      ..sort((a, b) => _norm(a).compareTo(_norm(b)));
  }

  int get _alertCount =>
      _checks.where((c) => c.lowWaterAlert).length;

  Future<void> _recordCheck(String coachNo) async {
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _WaterCheckSheet(coachNo: coachNo),
    );
    if (result == null || _runId == null) return;

    try {
      await WaterRepository.submitWaterCheck(
        runInstanceId: _runId!,
        coachNo: coachNo,
        checkTime: DateTime.now().toIso8601String(),
        waterStatus: result,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Water check saved for $coachNo'),
          backgroundColor: kSuccessGreen,
        ),
      );
      await _loadChecks(_runId!);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceAll('Exception: ', '')),
          backgroundColor: kErrorRed,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Water Checks',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: kRailwayBlue,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (_runId != null)
            IconButton(
                icon: const Icon(Icons.refresh), onPressed: () => _loadChecks(_runId!)),
        ],
      ),
      body: Column(
        children: [
          ObhsRunScope(
            initialRunInstanceId: widget.initialRunInstanceId,
            onRunChanged: (id) {
              setState(() => _runId = id);
              _loadChecks(id);
            },
          ),
          if (_checks.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: Row(
                children: [
                  Expanded(
                    child: _summaryTile(
                        'Checks', '${_checks.length}', kRailwayBlue),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _summaryTile(
                        'Alerts', '$_alertCount',
                        _alertCount > 0 ? kErrorRed : kSuccessGreen),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _summaryTile(
                      'Coaches',
                      '${_coachNumbers.length}',
                      Colors.teal,
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? _ErrorView(message: _error!, onRetry: _loadRuns)
                    : _coachNumbers.isEmpty
                        ? const Center(
                            child: Text('No coaches on this run',
                                style: TextStyle(color: Colors.grey)))
                        : RefreshIndicator(
                            onRefresh: () => _loadChecks(_runId!),
                            child: ListView.builder(
                              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                              itemCount: _coachNumbers.length,
                              itemBuilder: (context, i) {
                                final coach = _coachNumbers[i];
                                final mine = _checks
                                    .where((c) => _norm(c.coachNo) == _norm(coach))
                                    .toList();
                                return _CoachWaterCard(
                                  coachNo: coach,
                                  checks: mine,
                                  onRecord: () => _recordCheck(coach),
                                );
                              },
                            ),
                          ),
          ),
        ],
      ),
    );
  }

  Widget _summaryTile(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Column(
        children: [
          Text(value,
              style: TextStyle(
                  fontSize: 20, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 11)),
        ],
      ),
    );
  }
}

class _CoachWaterCard extends StatelessWidget {
  final String coachNo;
  final List<WaterCheckModel> checks;
  final VoidCallback onRecord;

  const _CoachWaterCard({
    required this.coachNo,
    required this.checks,
    required this.onRecord,
  });

  @override
  Widget build(BuildContext context) {
    final latest = checks.isEmpty ? null : checks.last;
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
                const Icon(Icons.water_drop, color: kRailwayBlue, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Coach $coachNo',
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 15)),
                ),
                if (latest != null)
                  ObhsStatusPill(
                    label: latest.waterStatus,
                    color: obhsStatusColor(latest.waterStatus),
                  )
                else
                  const ObhsStatusPill(
                      label: 'not checked', color: Colors.grey),
              ],
            ),
            if (latest != null) ...[
              const SizedBox(height: 8),
              Text(
                'Last checked: ${latest.checkTime}',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),
              if (latest.photoUrl != null && latest.photoUrl!.isNotEmpty) ...[
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    latest.photoUrl!,
                    height: 120,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
              ],
            ],
            if (checks.length > 1) ...[
              const SizedBox(height: 8),
              Text('${checks.length} checks recorded for this coach',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
            ],
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                onPressed: onRecord,
                icon: const Icon(Icons.add, size: 16),
                label: Text(checks.isEmpty ? 'Record Check' : 'Update'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: kRailwayBlue,
                  side: const BorderSide(color: kRailwayBlue),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WaterCheckSheet extends StatefulWidget {
  final String coachNo;

  const _WaterCheckSheet({required this.coachNo});

  @override
  State<_WaterCheckSheet> createState() => _WaterCheckSheetState();
}

class _WaterCheckSheetState extends State<_WaterCheckSheet> {
  String _status = 'full';

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
          left: 20, right: 20, top: 20, bottom: MediaQuery.of(context).viewInsets.bottom + 20),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Water status — Coach ${widget.coachNo}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 16),
          ...['full', 'low', 'empty'].map((s) => RadioListTile<String>(
                value: s,
                groupValue: _status,
                onChanged: (v) => setState(() => _status = v ?? 'full'),
                activeColor: obhsStatusColor(s),
                title: Text(s[0].toUpperCase() + s.substring(1)),
                contentPadding: EdgeInsets.zero,
              )),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context, _status),
              style: ElevatedButton.styleFrom(backgroundColor: kRailwayBlue),
              child: const Text('Save Check'),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 48, color: Colors.grey),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey)),
          ),
          const SizedBox(height: 12),
          ElevatedButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
