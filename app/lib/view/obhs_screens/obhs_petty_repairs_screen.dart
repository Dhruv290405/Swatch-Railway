import 'package:crm_train/model/petty_repair_model.dart';
import 'package:crm_train/repositories/repair_repository.dart';
import 'package:crm_train/utills/app_colors.dart';
import 'package:flutter/material.dart';

import 'widgets/obhs_run_scope.dart';

/// Cosmetic/minor defects found during a coach walk-round. Anything the crew
/// cannot clear on the move gets escalated to the depot.
class ObhsPettyRepairsScreen extends StatefulWidget {
  final String? initialRunInstanceId;

  const ObhsPettyRepairsScreen({super.key, this.initialRunInstanceId});

  @override
  State<ObhsPettyRepairsScreen> createState() => _ObhsPettyRepairsScreenState();
}

class _ObhsPettyRepairsScreenState extends State<ObhsPettyRepairsScreen> {
  static const _items = [
    'Seat fabric torn',
    'Window glass cracked',
    'Door rubber worn',
    'Coach light out',
    'Litter bin broken',
    'Washroom tap leaking',
    'Floor stain',
    'Curtain damaged',
  ];

  String? _runId;
  List<PettyRepairModel> _repairs = [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.initialRunInstanceId != null) {
      _runId = widget.initialRunInstanceId;
      _loadRepairs(widget.initialRunInstanceId!);
    }
  }

  Future<void> _loadRepairs(String runId) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repairs = await RepairRepository.getRepairs(runId);
      if (!mounted) return;
      setState(() {
        _repairs = repairs;
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

  int get _escalatedCount => _repairs.where((r) => r.isEscalated).length;

  Future<void> _openForm(PettyRepairModel? existing) async {
    final result = await showModalBottomSheet<_RepairResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _RepairFormSheet(
        runId: _runId!,
        existing: existing,
        catalogue: _items,
      ),
    );
    if (result == null) return;
    try {
      await RepairRepository.submitRepairInspection(
        repair: PettyRepairModel(
          id: existing?.id ?? '',
          runInstanceId: _runId!,
          coachNo: result.coachNo,
          inspectionTime: existing?.inspectionTime ??
              DateTime.now().toIso8601String(),
          items: result.items,
          isEscalated: existing?.isEscalated ?? false,
          escalatedTo: existing?.escalatedTo,
          status: 'COMPLETED',
          remarks: result.remarks,
          createdAt: existing?.createdAt ?? DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Inspection saved'),
          backgroundColor: kSuccessGreen,
        ),
      );
      await _loadRepairs(_runId!);
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

  Future<void> _escalate(PettyRepairModel repair) async {
    final controller = TextEditingController(text: 'supervisor');
    final target = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Escalate repair'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Escalate to',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Escalate'),
          ),
        ],
      ),
    );
    if (target == null || target.isEmpty) return;
    if (!mounted) return;
    // Block double-taps while the request is in flight, and guarantee the
    // dialog is dismissed even if the call throws — otherwise the screen
    // looks frozen and the back button stops responding.
    final nav = Navigator.of(context, rootNavigator: true);
    nav.push<void>(
      PageRouteBuilder(
        opaque: false,
        barrierDismissible: false,
        pageBuilder: (_, __, ___) =>
            const ColoredBox(color: Colors.black26, child: Center(child: CircularProgressIndicator())),
      ),
    );
      String? failure;
      try {
        await RepairRepository.escalateRepair(repair.id, escalatedTo: target);
      } catch (e) {
        failure = e.toString().replaceAll('Exception: ', '');
      } finally {
        try {
          if (nav.canPop()) nav.pop();
        } catch (_) {}
      }
      if (failure != null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(failure), backgroundColor: kErrorRed),
          );
        }
        return;
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Escalated'),
            backgroundColor: kSuccessGreen,
          ),
        );
      }
      if (_runId != null && _runId!.isNotEmpty) {
        await _loadRepairs(_runId!);
      }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Petty Repairs',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: kRailwayBlue,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (_runId != null)
            IconButton(
                icon: const Icon(Icons.refresh), onPressed: () => _loadRepairs(_runId!)),
        ],
      ),
      body: Column(
        children: [
          ObhsRunScope(
            initialRunInstanceId: widget.initialRunInstanceId,
            onRunChanged: (id) {
              setState(() => _runId = id);
              _loadRepairs(id);
            },
          ),
          if (_repairs.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: Row(
                children: [
                  Expanded(
                      child: _tile('Inspections', '${_repairs.length}',
                          kRailwayBlue)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _tile(
                      'Defects',
                      '${_repairs.fold<int>(0, (s, r) => s + r.items.length)}',
                      kWarningOrange,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _tile('Escalated', '$_escalatedCount',
                        _escalatedCount > 0 ? kErrorRed : kSuccessGreen),
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
                                onPressed: () => _loadRepairs(_runId ?? ''),
                                child: const Text('Retry')),
                          ],
                        ),
                      )
                    : _repairs.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text('No petty repairs for this run',
                                    style: TextStyle(color: Colors.grey)),
                                if (_runId != null) ...[
                                  const SizedBox(height: 12),
                                  ElevatedButton.icon(
                                    onPressed: () => _openForm(null),
                                    icon: const Icon(Icons.add, size: 18),
                                    label: const Text('New Inspection'),
                                    style: ElevatedButton.styleFrom(
                                        backgroundColor: kRailwayBlue),
                                  ),
                                ],
                              ],
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: () => _loadRepairs(_runId!),
                            child: ListView.builder(
                              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                              itemCount: _repairs.length + 1,
                              itemBuilder: (context, i) {
                                if (i == _repairs.length) {
                                  return Padding(
                                    padding: const EdgeInsets.only(top: 12),
                                    child: ElevatedButton.icon(
                                      onPressed: () => _openForm(null),
                                      icon: const Icon(Icons.add, size: 18),
                                      label: const Text('New Inspection'),
                                      style: ElevatedButton.styleFrom(
                                          backgroundColor: kRailwayBlue),
                                    ),
                                  );
                                }
                                final r = _repairs[i];
                                return _RepairCard(
                                  repair: r,
                                  onEdit: () => _openForm(r),
                                  onEscalate: r.isEscalated ? null : () => _escalate(r),
                                );
                              },
                            ),
                          ),
          ),
        ],
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

class _RepairResult {
  final String coachNo;
  final Map<String, String> items;
  final String? remarks;

  const _RepairResult({
    required this.coachNo,
    required this.items,
    this.remarks,
  });
}

class _RepairFormSheet extends StatefulWidget {
  final String runId;
  final PettyRepairModel? existing;
  final List<String> catalogue;

  const _RepairFormSheet({
    required this.runId,
    required this.catalogue,
    this.existing,
  });

  @override
  State<_RepairFormSheet> createState() => _RepairFormSheetState();
}

class _RepairFormSheetState extends State<_RepairFormSheet> {
  late String _coachNo;
  late final Map<String, String> _items;
  late final TextEditingController _remarks;

  @override
  void initState() {
    super.initState();
    _coachNo = widget.existing?.coachNo ?? 'C1';
    _items = Map<String, String>.from(widget.existing?.items ?? {});
    _remarks =
        TextEditingController(text: widget.existing?.remarks ?? '');
  }

  @override
  void dispose() {
    _remarks.dispose();
    super.dispose();
  }

  void _toggle(String item) {
    setState(() {
      if (_items.containsKey(item)) {
        _items.remove(item);
      } else {
        _items[item] = 'reported';
      }
    });
  }

  void _submit() {
    Navigator.pop(
      context,
      _RepairResult(
        coachNo: _coachNo,
        items: Map<String, String>.from(_items),
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
            Text(
              widget.existing == null
                  ? 'New Petty Repair Inspection'
                  : 'Update Inspection',
              style:
                  const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Text('Coach:',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _coachNo,
                    items: List.generate(
                      24,
                      (i) => 'C${i + 1}',
                    )
                        .map((c) =>
                            DropdownMenuItem(value: c, child: Text(c)))
                        .toList(),
                    onChanged: (v) =>
                        setState(() => _coachNo = v ?? _coachNo),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text('Defects found',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: widget.catalogue.map((item) {
                final selected = _items.containsKey(item);
                return FilterChip(
                  label: Text(item, style: const TextStyle(fontSize: 12)),
                  selected: selected,
                  onSelected: (_) => _toggle(item),
                  selectedColor: kWarningOrange.withOpacity(0.25),
                  checkmarkColor: kWarningOrange,
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
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
                child: Text(
                    'Save Inspection (${_items.length} defect${_items.length == 1 ? '' : 's'})'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RepairCard extends StatelessWidget {
  final PettyRepairModel repair;
  final VoidCallback onEdit;
  final VoidCallback? onEscalate;

  const _RepairCard({
    required this.repair,
    required this.onEdit,
    this.onEscalate,
  });

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
                const Icon(Icons.build_outlined, color: kRailwayBlue, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Coach ${repair.coachNo}',
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 15)),
                ),
                ObhsStatusPill(
                  label: repair.status,
                  color: obhsStatusColor(repair.status),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text('Inspected: ${repair.inspectionTime}',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
            if (repair.items.isNotEmpty) ...[
              const SizedBox(height: 10),
              ...repair.items.keys.map((k) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.build_circle_outlined,
                            size: 14, color: kWarningOrange),
                        const SizedBox(width: 6),
                        Expanded(
                            child: Text(k,
                                style: const TextStyle(fontSize: 12))),
                      ],
                    ),
                  )),
            ] else
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('No defects recorded',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
              ),
            if (repair.isEscalated) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: kErrorRed.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.priority_high, size: 14, color: kErrorRed),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Escalated to ${repair.escalatedTo ?? 'supervisor'}',
                        style: const TextStyle(fontSize: 12, color: kErrorRed),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (repair.remarks != null && repair.remarks!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(repair.remarks!,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
            ],
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (onEscalate != null)
                  TextButton.icon(
                    onPressed: onEscalate,
                    icon: const Icon(Icons.priority_high, size: 16),
                    label: const Text('Escalate'),
                    style: TextButton.styleFrom(foregroundColor: kErrorRed),
                  ),
                const SizedBox(width: 4),
                OutlinedButton.icon(
                  onPressed: onEdit,
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
}
