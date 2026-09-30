import 'package:crm_train/repositories/rating_repository.dart';
import 'package:crm_train/utills/app_colors.dart';
import 'package:flutter/material.dart';

import 'widgets/obhs_run_scope.dart';

/// Feedback capture for OBHS staff. Sources are validated server-side against
/// `passenger`, `tte`, `supervisor` and `railway_official`.
class ObhsRatingsScreen extends StatefulWidget {
  final String? initialRunInstanceId;

  const ObhsRatingsScreen({super.key, this.initialRunInstanceId});

  @override
  State<ObhsRatingsScreen> createState() => _ObhsRatingsScreenState();
}

class _ObhsRatingsScreenState extends State<ObhsRatingsScreen> {
  static const _sources = {
    'passenger': 'Passenger',
    'tte': 'TTE',
    'supervisor': 'Supervisor',
    'railway_official': 'Railway Official',
  };

  String? _runId;
  bool _loading = false;
  int _count = 0;

  @override
  void initState() {
    super.initState();
    if (widget.initialRunInstanceId != null) {
      _runId = widget.initialRunInstanceId;
    }
  }

  Future<void> _record() async {
    final result = await showModalBottomSheet<_RatingResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _RatingSheet(runId: _runId!, sources: _sources),
    );
    if (result == null) return;
    setState(() => _loading = true);
    try {
      await RatingRepository.submitRating(
        runInstanceId: _runId!,
        source: result.source,
        rating: result.rating,
        coachNo: result.coachNo,
        employeeId: result.employeeId,
        remarks: result.remarks,
      );
      if (!mounted) return;
      setState(() => _count++);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Rating recorded'),
          backgroundColor: kSuccessGreen,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceAll('Exception: ', '')),
          backgroundColor: kErrorRed,
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('OBHS Ratings',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: kRailwayBlue,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Column(
        children: [
          ObhsRunScope(
            initialRunInstanceId: widget.initialRunInstanceId,
            onRunChanged: (id) => setState(() => _runId = id),
          ),
          Expanded(
            child: _runId == null
                ? const Center(
                    child: Text('Select a run instance to record ratings',
                        style: TextStyle(color: Colors.grey)),
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Card(
                          elevation: 1,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Record a rating',
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15)),
                                const SizedBox(height: 6),
                                Text(
                                  'Ratings come from passengers, TTE, '
                                  'supervisors or railway officials on a 1–5 scale.',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade600),
                                ),
                                const SizedBox(height: 14),
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                    onPressed: _loading ? null : _record,
                                    icon: const Icon(Icons.star_rounded,
                                        size: 18),
                                    label: const Text('Add Rating'),
                                    style: ElevatedButton.styleFrom(
                                        backgroundColor: kRailwayBlue),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text('Accepted sources',
                            style: TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 13)),
                        const SizedBox(height: 8),
                        ..._sources.entries.map((e) => Card(
                              margin: const EdgeInsets.only(top: 6),
                              elevation: 0,
                              color: Colors.grey.shade50,
                              shape: RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(10)),
                              child: ListTile(
                                dense: true,
                                leading: Icon(
                                  _iconFor(e.key),
                                  color: kRailwayBlue,
                                ),
                                title: Text(e.value,
                                    style: const TextStyle(fontSize: 14)),
                                subtitle: Text(e.key,
                                    style:
                                        const TextStyle(fontSize: 11)),
                              ),
                            )),
                        const SizedBox(height: 16),
                        if (_count > 0)
                          Text('$_count rating(s) recorded in this session',
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey.shade600)),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  static IconData _iconFor(String source) {
    switch (source) {
      case 'passenger':
        return Icons.people_outline;
      case 'tte':
        return Icons.train_outlined;
      case 'supervisor':
        return Icons.badge_outlined;
      default:
        return Icons.account_balance_outlined;
    }
  }
}

class _RatingResult {
  final String source;
  final int rating;
  final String? coachNo;
  final String? employeeId;
  final String? remarks;

  const _RatingResult({
    required this.source,
    required this.rating,
    this.coachNo,
    this.employeeId,
    this.remarks,
  });
}

class _RatingSheet extends StatefulWidget {
  final String runId;
  final Map<String, String> sources;

  const _RatingSheet({required this.runId, required this.sources});

  @override
  State<_RatingSheet> createState() => _RatingSheetState();
}

class _RatingSheetState extends State<_RatingSheet> {
  late String _source;
  int _rating = 0;
  final TextEditingController _coach = TextEditingController();
  final TextEditingController _employee = TextEditingController();
  final TextEditingController _remarks = TextEditingController();

  @override
  void initState() {
    super.initState();
    _source = widget.sources.keys.first;
  }

  @override
  void dispose() {
    _coach.dispose();
    _employee.dispose();
    _remarks.dispose();
    super.dispose();
  }

  void _submit() {
    if (_rating < 1) return;
    Navigator.pop(
      context,
      _RatingResult(
        source: _source,
        rating: _rating,
        coachNo: _coach.text.trim().isEmpty ? null : _coach.text.trim(),
        employeeId:
            _employee.text.trim().isEmpty ? null : _employee.text.trim(),
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
            const Text('New Rating',
                style:
                    TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 16),
            const Text('Source',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: widget.sources.entries.map((e) {
                final selected = e.key == _source;
                return ChoiceChip(
                  label: Text(e.value, style: const TextStyle(fontSize: 12)),
                  selected: selected,
                  onSelected: (_) => setState(() => _source = e.key),
                  selectedColor: kRailwayBlue.withOpacity(0.2),
                );
              }).toList(),
            ),
            const SizedBox(height: 18),
            const Text('Rating',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 6),
            Row(
              children: List.generate(5, (i) {
                final value = i + 1;
                final active = value <= _rating;
                return IconButton(
                  iconSize: 34,
                  onPressed: () => setState(() => _rating = value),
                  icon: Icon(
                    active ? Icons.star : Icons.star_border,
                    color: active ? kWarningOrange : Colors.grey.shade400,
                  ),
                );
              }),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _coach,
              decoration: const InputDecoration(
                labelText: 'Coach (optional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _employee,
              decoration: const InputDecoration(
                labelText: 'Employee ID (optional)',
                border: OutlineInputBorder(),
              ),
            ),
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
                onPressed: _rating < 1 ? null : _submit,
                style: ElevatedButton.styleFrom(backgroundColor: kRailwayBlue),
                child: const Text('Submit Rating'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
