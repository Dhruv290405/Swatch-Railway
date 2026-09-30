import 'package:crm_train/model/safety_check_model.dart';
import 'package:crm_train/repositories/safety_repository.dart';
import 'package:crm_train/utills/app_colors.dart';
import 'package:flutter/material.dart';

import 'widgets/obhs_run_scope.dart';

/// Fire extinguisher, FSDS, CCTV and emergency equipment checks for a run.
/// A check is only "ok" when all four subsystems pass; any failure is recorded
/// as a deficiency that the depot has to clear.
class ObhsSafetyChecksScreen extends StatefulWidget {
  final String? initialRunInstanceId;

  const ObhsSafetyChecksScreen({super.key, this.initialRunInstanceId});

  @override
  State<ObhsSafetyChecksScreen> createState() => _ObhsSafetyChecksScreenState();
}

class _ObhsSafetyChecksScreenState extends State<ObhsSafetyChecksScreen> {
  String? _runId;
  List<SafetyCheckModel> _checks = [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.initialRunInstanceId != null) {
      _runId = widget.initialRunInstanceId;
      _loadChecks(widget.initialRunInstanceId!);
    }
  }

  Future<void> _loadChecks(String runId) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final checks = await SafetyRepository.getSafetyChecks(runId);
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

  int get _deficientCount => _checks
      .where((c) =>
          c.fireExtinguisherStatus != 'ok' ||
          c.fsdsStatus != 'ok' ||
          c.cctvStatus != 'ok' ||
          c.emergencyEquipmentStatus != 'ok')
      .length;

  Future<void> _submit(SafetyCheckModel check) async {
    try {
      await SafetyRepository.submitSafetyCheck(check: check);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Safety check submitted'),
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

  Future<void> _reportDeficiency(SafetyCheckModel check) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Report deficiency'),
        content: TextField(
          controller: controller,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'What is deficient?',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Report'),
          ),
        ],
      ),
    );
    if (result == null || result.isEmpty) return;
    try {
      await SafetyRepository.reportDeficiency(
        checkId: check.id,
        deficiencyReport: result,
        photoUrl: '',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Deficiency reported'),
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
        title: const Text('Safety Checks',
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
                      child: _tile('Checks', '${_checks.length}', kRailwayBlue)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _tile(
                      'Deficient',
                      '$_deficientCount',
                      _deficientCount > 0 ? kErrorRed : kSuccessGreen,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _tile(
                      'Reports',
                      '${_checks.fold<int>(0, (s, c) => s + c.deficiencyReports.length)}',
                      kWarningOrange,
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
                                onPressed: () => _loadChecks(_runId ?? ''),
                                child: const Text('Retry')),
                          ],
                        ),
                      )
                    : _checks.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text('No safety checks for this run',
                                    style: TextStyle(color: Colors.grey)),
                                if (_runId != null) ...[
                                  const SizedBox(height: 12),
                                  ElevatedButton.icon(
                                    onPressed: () => _openForm(null),
                                    icon: const Icon(Icons.add, size: 18),
                                    label: const Text('Run Safety Check'),
                                    style: ElevatedButton.styleFrom(
                                        backgroundColor: kRailwayBlue),
                                  ),
                                ],
                              ],
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: () => _loadChecks(_runId!),
                            child: ListView.builder(
                              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                              itemCount: _checks.length + 1,
                              itemBuilder: (context, i) {
                                if (i == _checks.length) {
                                  return Padding(
                                    padding: const EdgeInsets.only(top: 12),
                                    child: ElevatedButton.icon(
                                      onPressed: () => _openForm(null),
                                      icon: const Icon(Icons.add, size: 18),
                                      label: const Text('New Safety Check'),
                                      style: ElevatedButton.styleFrom(
                                          backgroundColor: kRailwayBlue),
                                    ),
                                  );
                                }
                                return _SafetyCard(
                                  check: _checks[i],
                                  onSubmit: () => _openForm(_checks[i]),
                                  onReport: () => _reportDeficiency(_checks[i]),
                                );
                              },
                            ),
                          ),
          ),
        ],
      ),
    );
  }

  Future<void> _openForm(SafetyCheckModel? existing) async {
    final result = await showModalBottomSheet<_SafetyResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SafetyFormSheet(runId: _runId!, existing: existing),
    );
    if (result == null) return;
    final isUpdate = existing != null;
    await _submit(
      SafetyCheckModel(
        id: isUpdate ? existing.id : '',
        runInstanceId: _runId!,
        scheduledTime: existing?.scheduledTime ?? DateTime.now(),
        fireExtinguisherStatus: result.fireExtinguisher,
        fsdsStatus: result.fsds,
        cctvStatus: result.cctv,
        emergencyEquipmentStatus: result.emergency,
        photos: existing?.photos ?? const [],
        deficiencyReports: existing?.deficiencyReports ?? const [],
        status: result.status,
        remarks: result.remarks,
        completedAt: DateTime.now(),
      ),
    );
  }

  Widget _tile(String label, String value, Color color) {
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

class _SafetyResult {
  final String fireExtinguisher;
  final String fsds;
  final String cctv;
  final String emergency;
  final String status;
  final String? remarks;

  const _SafetyResult({
    required this.fireExtinguisher,
    required this.fsds,
    required this.cctv,
    required this.emergency,
    required this.status,
    this.remarks,
  });
}

class _SafetyFormSheet extends StatefulWidget {
  final String runId;
  final SafetyCheckModel? existing;

  const _SafetyFormSheet({required this.runId, this.existing});

  @override
  State<_SafetyFormSheet> createState() => _SafetyFormSheetState();
}

class _SafetyFormSheetState extends State<_SafetyFormSheet> {
  late String _ext;
  late String _fsds;
  late String _cctv;
  late String _emergency;
  late final TextEditingController _remarks;

  static const _options = ['ok', 'defective', 'missing'];

  @override
  void initState() {
    super.initState();
    _ext = widget.existing?.fireExtinguisherStatus ?? 'ok';
    _fsds = widget.existing?.fsdsStatus ?? 'ok';
    _cctv = widget.existing?.cctvStatus ?? 'ok';
    _emergency = widget.existing?.emergencyEquipmentStatus ?? 'ok';
    _remarks =
        TextEditingController(text: widget.existing?.remarks ?? '');
  }

  @override
  void dispose() {
    _remarks.dispose();
    super.dispose();
  }

  void _submit() {
    final allOk = _ext == 'ok' && _fsds == 'ok' && _cctv == 'ok' && _emergency == 'ok';
    Navigator.pop(
      context,
      _SafetyResult(
        fireExtinguisher: _ext,
        fsds: _fsds,
        cctv: _cctv,
        emergency: _emergency,
        status: allOk ? 'COMPLETED' : 'NEEDS_ATTENTION',
        remarks: _remarks.text.trim().isEmpty ? null : _remarks.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.existing == null ? 'New Safety Check' : 'Update Safety Check',
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 16),
            _section('Fire Extinguisher', _ext, (v) => setState(() => _ext = v)),
            _section('FSDS', _fsds, (v) => setState(() => _fsds = v)),
            _section('CCTV', _cctv, (v) => setState(() => _cctv = v)),
            _section('Emergency Equipment', _emergency,
                (v) => setState(() => _emergency = v)),
            const SizedBox(height: 12),
            TextField(
              controller: _remarks,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Remarks',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _submit,
                style: ElevatedButton.styleFrom(backgroundColor: kRailwayBlue),
                child: const Text('Submit Check'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _section(String label, String value, ValueChanged<String> onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style:
                  const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          const SizedBox(height: 6),
          Row(
            children: _options.map((o) {
              final selected = o == value;
              final color = o == 'ok' ? kSuccessGreen : kErrorRed;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: OutlinedButton(
                    onPressed: () => onChanged(o),
                    style: OutlinedButton.styleFrom(
                      backgroundColor: selected ? color.withOpacity(0.12) : null,
                      foregroundColor: selected ? color : Colors.grey,
                      side: BorderSide(
                          color: selected ? color : Colors.grey.shade300),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    child: Text(o[0].toUpperCase() + o.substring(1)),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class _SafetyCard extends StatelessWidget {
  final SafetyCheckModel check;
  final VoidCallback onSubmit;
  final VoidCallback onReport;

  const _SafetyCard({
    required this.check,
    required this.onSubmit,
    required this.onReport,
  });

  @override
  Widget build(BuildContext context) {
    final allOk = check.fireExtinguisherStatus == 'ok' &&
        check.fsdsStatus == 'ok' &&
        check.cctvStatus == 'ok' &&
        check.emergencyEquipmentStatus == 'ok';

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
                const Icon(Icons.verified_user_outlined,
                    color: kRailwayBlue, size: 20),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('Safety Check',
                      style: TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 15)),
                ),
                ObhsStatusPill(
                  label: check.status,
                  color: allOk ? kSuccessGreen : kErrorRed,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _item('Extinguisher', check.fireExtinguisherStatus),
                _item('FSDS', check.fsdsStatus),
                _item('CCTV', check.cctvStatus),
                _item('Emergency', check.emergencyEquipmentStatus),
              ],
            ),
            if (check.remarks != null && check.remarks!.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(check.remarks!,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
            ],
            if (check.deficiencyReports.isNotEmpty) ...[
              const SizedBox(height: 10),
              ...check.deficiencyReports.map((d) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.warning_amber, size: 14, color: kErrorRed),
                        const SizedBox(width: 6),
                        Expanded(
                            child: Text(d,
                                style: const TextStyle(
                                    fontSize: 12, color: kErrorRed))),
                      ],
                    ),
                  )),
            ],
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: onReport,
                  icon: const Icon(Icons.report_problem, size: 16),
                  label: const Text('Deficiency'),
                  style: TextButton.styleFrom(foregroundColor: kErrorRed),
                ),
                const SizedBox(width: 4),
                OutlinedButton.icon(
                  onPressed: onSubmit,
                  icon: const Icon(Icons.edit, size: 16),
                  label: const Text('Edit'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: kRailwayBlue,
                    side: const BorderSide(color: kRailwayBlue),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _item(String label, String status) {
    final color = status == 'ok' ? kSuccessGreen : kErrorRed;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 10)),
          Text(status,
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600, color: color)),
        ],
      ),
    );
  }
}
