import 'package:crm_train/model/run_instance_model.dart';
import 'package:crm_train/repositories/obhs_repository.dart';
import 'package:crm_train/utills/app_colors.dart';
import 'package:flutter/material.dart';

/// Loads OBHS run instances once and lets a screen bind to one of them.
///
/// Every OBHS field module (water, safety, repairs, ratings, analytics) is
/// scoped to a single run instance, so they all need the same picker.
class ObhsRunScope extends StatefulWidget {
  final void Function(String runInstanceId) onRunChanged;
  final String? initialRunInstanceId;

  const ObhsRunScope({
    super.key,
    required this.onRunChanged,
    this.initialRunInstanceId,
  });

  @override
  State<ObhsRunScope> createState() => _ObhsRunScopeState();
}

class _ObhsRunScopeState extends State<ObhsRunScope> {
  List<RunInstanceModel> _runs = [];
  bool _loading = true;
  String? _error;
  String? _selected;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
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
        final ids = runs.map(_idOf).where((id) => id.isNotEmpty).toList();
        // Prefer an explicit selection, else the newest run with work on it.
        _selected = widget.initialRunInstanceId != null &&
                ids.contains(widget.initialRunInstanceId)
            ? widget.initialRunInstanceId
            : (ids.isNotEmpty ? ids.first : null);
      });
      final id = _selected;
      if (id != null) widget.onRunChanged(id);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceAll('Exception: ', '');
        _loading = false;
      });
    }
  }

  static String _idOf(RunInstanceModel r) => r.runInstanceId ?? r.id ?? '';

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const LinearProgressIndicator(minHeight: 3);
    }
    if (_error != null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        color: kErrorRed.withOpacity(0.08),
        child: Row(
          children: [
            const Icon(Icons.error_outline, size: 18, color: kErrorRed),
            const SizedBox(width: 8),
            Expanded(
              child: Text(_error!,
                  style: const TextStyle(fontSize: 12, color: kErrorRed)),
            ),
            TextButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }
    if (_runs.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        color: kWarningOrange.withOpacity(0.1),
        child: const Row(
          children: [
            Icon(Icons.train, size: 18, color: kWarningOrange),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'No OBHS run instances yet. Create a run first.',
                style: TextStyle(fontSize: 12, color: kWarningOrange),
              ),
            ),
          ],
        ),
      );
    }

    final ids = _runs.map(_idOf).where((id) => id.isNotEmpty).toList();
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        children: [
          const Icon(Icons.train, size: 18, color: kRailwayBlue),
          const SizedBox(width: 8),
          const Text('Run:',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                isExpanded: true,
                value: ids.contains(_selected) ? _selected : null,
                hint: const Text('Select a run instance',
                    style: TextStyle(fontSize: 13)),
                items: ids.map((id) {
                  final run = _runs.firstWhere((r) => _idOf(r) == id);
                  return DropdownMenuItem<String>(
                    value: id,
                    child: Text(
                      '${run.trainNo ?? '?'} • ${run.instanceId} • ${run.status}',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13),
                    ),
                  );
                }).toList(),
                onChanged: (v) {
                  setState(() => _selected = v);
                  if (v != null) widget.onRunChanged(v);
                },
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh, size: 20),
            onPressed: _load,
            tooltip: 'Reload runs',
          ),
        ],
      ),
    );
  }
}

/// Small status pill used across the OBHS module lists.
class ObhsStatusPill extends StatelessWidget {
  final String label;
  final Color color;

  const ObhsStatusPill({super.key, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label.replaceAll('_', ' '),
        style: TextStyle(
            fontSize: 10, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }
}

/// Maps a check status string to a display colour.
Color obhsStatusColor(String? status) {
  switch ((status ?? '').toUpperCase()) {
    case 'COMPLETED':
    case 'OK':
    case 'FULL':
      return kSuccessGreen;
    case 'LOW':
    case 'PENDING':
    case 'NEEDS_ATTENTION':
      return kWarningOrange;
    case 'EMPTY':
    case 'DEFICIENT':
    case 'ESCALATED':
    case 'OUT_OF_SERVICE':
      return kErrorRed;
    default:
      return Colors.grey;
  }
}
