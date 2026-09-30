import 'package:flutter/material.dart';
import 'package:crm_train/utills/app_colors.dart';
import 'package:crm_train/repositories/mcc_repository.dart';

import 'mcc_run_detail_screen.dart';

class MccWashingRunsScreen extends StatefulWidget {
  const MccWashingRunsScreen({super.key});
  @override
  State<MccWashingRunsScreen> createState() => _MccWashingRunsScreenState();
}

class _MccWashingRunsScreenState extends State<MccWashingRunsScreen> {
  List<Map<String, dynamic>> _runs = [];
  List<Map<String, dynamic>> _depots = [];
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
      final resp = await MccRepository.getWashingRuns();
      _runs = List<Map<String, dynamic>>.from((resp['runs'] ?? []) as List);
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
        title: const Text('Washing Runs',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20)),
        backgroundColor: kRailwayBlue,
        elevation: 0,
      ),
      body: RefreshIndicator(
        onRefresh: _fetch,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? _buildError()
                : _runs.isEmpty
                    ? _buildEmpty()
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _runs.length,
                        itemBuilder: (_, i) => _buildRunCard(_runs[i]),
                      ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateSheet,
        backgroundColor: kRailwayBlue,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Schedule Run', style: TextStyle(color: Colors.white)),
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

  Widget _buildEmpty() {
    return ListView(
      padding: const EdgeInsets.all(32),
      children: [
        const SizedBox(height: 60),
        Icon(Icons.train, size: 80, color: Colors.grey[300]),
        const SizedBox(height: 16),
        const Text('No washing runs scheduled.',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.black54),
            textAlign: TextAlign.center),
        const SizedBox(height: 8),
        Text('Tap "Schedule Run" to book a rake for a mechanised wash.',
            style: TextStyle(color: Colors.grey[500]), textAlign: TextAlign.center),
      ],
    );
  }

  Color _statusColor(String? status) {
    switch (status) {
      case 'COMPLETED':
        return Colors.green;
      case 'IN_PROGRESS':
        return kRailwayBlue;
      case 'CANCELLED':
        return Colors.red;
      default:
        return Colors.orange;
    }
  }

  Widget _buildRunCard(Map<String, dynamic> run) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: InkWell(
        onTap: () => Navigator.push(context, MaterialPageRoute(
          builder: (_) => MccRunDetailScreen(runId: run['uid'] ?? run['id'] ?? '', initial: run),
        )),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(run['trainNo'] ?? 'N/A',
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  Chip(
                    label: Text(run['status'] ?? 'SCHEDULED'),
                    labelStyle: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                    backgroundColor: _statusColor(run['status']),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text('${run['trainName'] ?? ''} · ${run['depotName'] ?? ''}',
                  style: TextStyle(color: Colors.grey[600], fontSize: 13)),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildMiniStat('Coaches', '${run['coachNos']?.length ?? 0}'),
                  _buildMiniStat('Approved', '${run['approvedTaskCount'] ?? 0}'),
                  _buildMiniStat('Tasks', '${run['taskCount'] ?? 0}'),
                  const Icon(Icons.chevron_right, color: Colors.grey),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMiniStat(String label, String value) {
    return Column(
      children: [
        Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87)),
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
      ],
    );
  }

  Future<void> _showCreateSheet() async {
    try {
      final depotResp = await MccRepository.getDepots();
      _depots = List<Map<String, dynamic>>.from((depotResp['depots'] ?? []) as List);
    } catch (_) {
      _depots = [];
    }
    if (!mounted) return;
    final trainCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    final dateCtrl = TextEditingController();
    final timeCtrl = TextEditingController();
    final coachesCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    String? selectedDepotId;
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
                const Text('Schedule Washing Run',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: selectedDepotId,
                  decoration: const InputDecoration(labelText: 'Depot *'),
                  items: _depots
                      .map((d) => DropdownMenuItem<String>(
                            value: (d['uid'] ?? d['id']).toString(),
                            child: Text('${d['name']}'),
                          ))
                      .toList(),
                  onChanged: (v) => selectedDepotId = v,
                  validator: (v) => v == null ? 'Select a depot' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: trainCtrl,
                  decoration: const InputDecoration(labelText: 'Train No *'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Train Name'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: coachesCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Coach Nos (comma separated)',
                    helperText: 'e.g. A1, A2, B1 (defaults to A1-A3, B1-B2)',
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: dateCtrl,
                        readOnly: true,
                        decoration: const InputDecoration(labelText: 'Date'),
                        onTap: () async {
                          final date = await showDatePicker(
                            context: ctx,
                            initialDate: DateTime.now(),
                            firstDate: DateTime.now().subtract(const Duration(days: 1)),
                            lastDate: DateTime.now().add(const Duration(days: 365)),
                          );
                          if (date != null) {
                            dateCtrl.text =
                                '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: timeCtrl,
                        readOnly: true,
                        decoration: const InputDecoration(labelText: 'Time'),
                        onTap: () async {
                          final time = await showTimePicker(context: ctx, initialTime: const TimeOfDay(hour: 6, minute: 0));
                          if (time != null) {
                            timeCtrl.text =
                                '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
                          }
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () async {
                      if (!formKey.currentState!.validate() || selectedDepotId == null) return;
                      final coachList = coachesCtrl.text
                          .split(',')
                          .map((e) => e.trim())
                          .where((e) => e.isNotEmpty)
                          .toList();
                      try {
                        await MccRepository.createWashingRun({
                          'depotId': selectedDepotId,
                          'trainNo': trainCtrl.text.trim(),
                          'trainName': nameCtrl.text.trim(),
                          'coachNos': coachList,
                          'scheduledDate': dateCtrl.text.isEmpty ? null : dateCtrl.text,
                          'scheduledTime': timeCtrl.text.isEmpty ? null : timeCtrl.text,
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
                    child: const Text('Schedule', style: TextStyle(color: Colors.white)),
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