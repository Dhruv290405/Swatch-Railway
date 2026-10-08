import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../services/api_services.dart';
import '../../../utills/app_colors.dart';

class AuditLogScreen extends StatefulWidget {
  final String? stationId;
  final String? stationName;
  const AuditLogScreen({super.key, this.stationId, this.stationName});

  @override
  State<AuditLogScreen> createState() => _AuditLogScreenState();
}

class _AuditLogScreenState extends State<AuditLogScreen> {
  List<Map<String, dynamic>> _logs = [];
  bool _isLoading = true;
  String? _error;
  String? _selectedAction;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  final _dateFmt = DateFormat('dd MMM yyyy');
  final _timeFmt = DateFormat('hh:mm a');

  static const _actionLabels = {
    'PASSWORD_CHANGED': 'Password Changed',
    'COMPLAINT_ASSIGNED': 'Complaint Assigned',
    'COMPLAINT_ESCALATED': 'Complaint Escalated',
'COMPLAINT_AUTO_ROUTED': 'Complaint Auto Routed',
      'ESCALATION_CREATED': 'Escalation Created',
      'ESCALATED': 'Escalated',
      'APPROVED': 'Approved',
    'REJECTED': 'Rejected',
    'CREATED': 'Created',
    'SUBMITTED': 'Submitted',
    'SCORED': 'Score Recorded',
    'LOCKED': 'Bill Locked',
    'INVOICE_GENERATED': 'Invoice Generated',
    'GENERATED': 'Generated',
    'BILLING_CONFIG_UPDATED': 'Billing Configuration Updated',
    'BILLING_CONFIG_CREATED': 'Billing Configuration Created',
    'BILL_CREATED': 'Bill Created',
    'BILL_APPROVED': 'Bill Approved',
    'BILL_REJECTED': 'Bill Rejected',
    'BILL_DELETED': 'Bill Deleted',
    'TASK_EXECUTION_DAILY_BILL_GENERATED': 'Daily Task Bill Generated',
    'TASK_EXECUTION_DAILY_BILL_REUSED': 'Daily Task Bill Reused',
    'STATION_BILL_PACK_CREATED': 'Billing Pack Generated',
    'STATION_BILL_PACK_UPDATED': 'Billing Pack Updated',
    'STATION_BILL_PACK_SUBMITTED': 'Billing Pack Submitted',
    'STATION_BILL_PACK_APPROVED': 'Billing Pack Approved',
    'STATION_BILL_PACK_REJECTED': 'Billing Pack Rejected',
    'STATION_BILL_PACK_DELETED': 'Billing Pack Deleted',
    'STATION_BILL_PACK_PAYMENT_RECORDED': 'Payment Recorded',
    'STATION_BILL_PACK_COMPLIANCE_UPDATED': 'Compliance Checklist Updated',
    'STATION_BILL_PACK_RETURNED_TO_DRAFT': 'Billing Pack Returned to Draft',
    'PASSENGER_FEEDBACK_SUBMITTED': 'Passenger Feedback Recorded',
    'INSPECTION_CREATED': 'Inspection Created',
    'INSPECTION_STARTED': 'Inspection Started',
    'INSPECTION_RATINGS_SUBMITTED': 'Inspection Ratings Submitted',
    'INSPECTION_APPROVED': 'Inspection Approved',
    'INSPECTION_REJECTED': 'Inspection Rejected',
    'INSPECTION_RESUBMITTED': 'Inspection Resubmitted',
    'INSPECTION_DEFICIENCY_ADDED': 'Deficiency Added',
    'INSPECTION_DEFICIENCY_CLOSED': 'Deficiency Closed',
    'INSPECTION_DEFICIENCY_VERIFIED': 'Deficiency Closure Verified',
    'EXECUTION_SHEET_DAILY_SAVED': 'Daily Execution Sheet Saved',
    'EXECUTION_SHEET_DAILY_UPDATED': 'Daily Execution Sheet Updated',
    'EXECUTION_SHEET_DAILY_SUBMITTED': 'Daily Execution Sheet Submitted',
    'EXECUTION_SHEET_DAILY_VERIFIED': 'Daily Execution Sheet Verified',
    'PETTY_ISSUE_CREATED': 'Petty Issue Reported',
    'PETTY_ISSUE_STATUS_CHANGED': 'Petty Issue Status Changed',
    'EVIDENCE_UPLOADED': 'Evidence Uploaded',
    'EVIDENCE_DELETED': 'Evidence Deleted',
    'REPORT_GENERATED': 'Report Generated',
    'REPORT_EMAILED': 'Report Emailed',
  };

  static const _targetLabels = {
    'task_execution_daily_bills': 'Daily Bill',
    'billing_bills': 'Bill',
    'billing_reports': 'Billing Report',
    'billing_configs': 'Billing Rule',
    'billingRules': 'Billing Rule',
    'station_billing_packs': 'Billing Pack',
    'contracts': 'Contract',
    'contract_estimate_items': 'Estimate Item',
    'contract_variations': 'Variation',
    'contract_swos': 'SWO',
    'inspections': 'Inspection',
    'passenger_feedback': 'Feedback',
    'stations': 'Station',
    'stationCleaningForms': 'Cleaning Form',
    'shift_summaries': 'Shift Summary',
    'supervisor_daily_logs': 'Daily Log',
    'petty_issues': 'Petty Issue',
    'evidence': 'Evidence',
    'complaints': 'Complaint',
    'users': 'User',
  };

  bool get _stationScoped => widget.stationId != null && widget.stationId!.isNotEmpty;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final logs = _stationScoped
          ? await ApiService.getStationAuditLogs(stationId: widget.stationId!, action: _selectedAction, limit: 150)
          : await ApiService.getAuditLogs(action: _selectedAction, limit: 100);
      if (!mounted) return;
      setState(() {
        _logs = logs;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _isLoading = false;
      });
    }
  }

  String _humanAction(String action) {
    for (final entry in _actionLabels.entries) {
      if (action == entry.key) return entry.value;
      if (action.contains(entry.key)) {
        return action.replaceFirst(entry.key, entry.value);
      }
    }
    return action.split('_').where((w) => w.isNotEmpty).map((w) => w[0] + w.substring(1).toLowerCase()).join(' ');
  }

  String _humanTarget(String? type) {
    if (type == null || type.isEmpty) return '';
    return _targetLabels[type] ??
        type.split('_').where((w) => w.isNotEmpty).map((w) => w[0] + w.substring(1).toLowerCase()).join(' ');
  }

  Color _colorForAction(String action) {
    if (action.contains('REJECT') || action.contains('DELETED') || action.contains('FAILED')) return Colors.red;
    if (action.contains('APPROV') || action.contains('ACCEPT') || action.contains('LOCKED') || action.contains('VERIF')) return Colors.green;
    if (action.contains('BILL') || action.contains('INVOICE') || action.contains('PAYMENT') || action.contains('CONFIG') || action.contains('ESTIMATE') || action.contains('VARIATION') || action.contains('SWO')) return Colors.deepOrange;
    if (action.contains('FEEDBACK')) return Colors.amber.shade900;
    if (action.contains('INSPECTION')) return Colors.purple;
    if (action.contains('COMPLAINT')) return Colors.blue;
    if (action.contains('PASSWORD') || action.contains('LOGIN')) return Colors.orange;
    if (action.contains('EVIDENCE')) return Colors.teal;
    if (action.contains('ATTENDANCE')) return Colors.indigo;
    if (action.contains('SCORED') || action.contains('SUBMIT')) return Colors.indigo;
    return Colors.blueGrey;
  }

  IconData _iconForAction(String action) {
    if (action.contains('BILL') || action.contains('INVOICE') || action.contains('PAYMENT')) return Icons.receipt_long;
    if (action.contains('CONFIG')) return Icons.settings;
    if (action.contains('CONTRACT') || action.contains('SWO') || action.contains('VARIATION') || action.contains('ESTIMATE')) return Icons.request_quote;
    if (action.contains('FEEDBACK')) return Icons.feedback;
    if (action.contains('INSPECTION') || action.contains('SCORED')) return Icons.gavel;
    if (action.contains('COMPLAINT')) return Icons.report_problem;
    if (action.contains('PASSWORD')) return Icons.lock;
    if (action.contains('EVIDENCE')) return Icons.photo_library;
    if (action.contains('ATTENDANCE')) return Icons.badge;
    if (action.contains('TASK') || action.contains('EXECUTION')) return Icons.assignment;
    if (action.contains('PETTY')) return Icons.construction;
    if (action.contains('REPORT')) return Icons.assessment;
    if (action.contains('APPROV')) return Icons.verified;
    if (action.contains('CREATED') || action.contains('GENERATED') || action.contains('SUBMITTED')) return Icons.add_circle_outline;
    return Icons.history;
  }

  String _relativeTime(DateTime ts, DateTime now) {
    final diff = now.difference(ts);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'yesterday';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return _dateFmt.format(ts);
  }

  DateTime? _parseTs(dynamic ts) {
    if (ts == null) return null;
    if (ts is DateTime) return ts;
    if (ts is int) return DateTime.fromMillisecondsSinceEpoch(ts, isUtc: true);
    final str = '$ts';
    if (str.isEmpty) return null;
    // Try ISO 8601
    final parsed = DateTime.tryParse(str);
    if (parsed != null) return parsed;
    // Try common formats
    const formats = [
      'yyyy-MM-dd HH:mm:ss',
      'yyyy-MM-dd HH:mm:ss.SSS',
      'yyyy-MM-ddTHH:mm:ss',
      'yyyy-MM-ddTHH:mm:ssZ',
      'yyyy-MM-ddTHH:mm:ss.SSSZ',
      'dd/MM/yyyy HH:mm:ss',
      'MM/dd/yyyy HH:mm:ss',
    ];
    for (final fmt in formats) {
      try {
        return DateFormat(fmt).parse(str, true);
      } catch (_) {}
    }
    return null;
  }

  List<Map<String, dynamic>> _filteredLogs() {
    final q = _searchQuery.trim().toLowerCase();
    if (q.isEmpty) return _logs;
    return _logs.where((log) {
      final action = log['action'] as String? ?? '';
      final haystack = [
        action,
        _humanAction(action),
        log['actorName'] as String? ?? '',
        _humanTarget(log['targetType'] as String?),
        log['details'] as String? ?? '',
      ].join(' ').toLowerCase();
      return haystack.contains(q);
    }).toList();
  }

  List<String> _availableActions() {
    final seen = <String>{};
    for (final log in _logs) {
      final a = log['action'] as String? ?? '';
      if (a.isNotEmpty) seen.add(a);
    }
    return seen.toList()..sort();
  }

  Map<String, List<Map<String, dynamic>>> _groupByDay(List<Map<String, dynamic>> logs) {
    String day(DateTime? ts) => ts == null ? 'Unknown' : '${ts.year}-${ts.month.toString().padLeft(2, '0')}-${ts.day.toString().padLeft(2, '0')}';
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final log in logs) {
      final ts = _parseTs(log['timestamp']);
      groups.putIfAbsent(day(ts), () => []).add(log);
    }
    final entries = groups.entries.toList()
      ..sort((a, b) => b.key.compareTo(a.key));
    return {for (final e in entries) e.key: e.value};
  }

  String _dayLabel(DateTime? ts) {
    if (ts == null) return 'Unknown';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final that = DateTime(ts.year, ts.month, ts.day);
    final diff = today.difference(that).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    return _dateFmt.format(ts);
  }

  Widget _buildCard(Map<String, dynamic> log) {
    final action = log['action'] as String? ?? 'UNKNOWN';
    final color = _colorForAction(action);
    final ts = _parseTs(log['timestamp']);
    final target = _humanTarget(log['targetType'] as String?);
    final actor = log['actorName'] as String? ?? 'System';
    final details = log['details'] as String? ?? '';

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(_iconForAction(action), size: 20, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          _humanAction(action),
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: color),
                        ),
                      ),
                      if (ts != null)
                        Text(
                          _timeFmt.format(ts),
                          style: const TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                    ],
                  ),
                  if (details.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(details, style: const TextStyle(fontSize: 12.5, color: Colors.black87, height: 1.35)),
                  ],
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (ts != null)
                        _metaChip(Icons.schedule, _relativeTime(ts, DateTime.now()), Colors.grey.shade700),
                      _metaChip(Icons.person_outline, actor, Colors.grey.shade700),
                      if (target.isNotEmpty)
                        _metaChip(Icons.label_outline, target, color),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _metaChip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: Colors.grey.shade600),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        title: Text(_stationScoped ? 'Audit Log' : 'Audit Logs'),
        backgroundColor: kRailwayBlue,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _load,
          ),
        ],
      ),
      body: Column(
        children: [
          _headerBar(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _searchQuery = v),
              decoration: InputDecoration(
                hintText: 'Search action, person, or details...',
                prefixIcon: const Icon(Icons.search, size: 20),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
              ),
            ),
          ),
          _actionFilterBar(),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _headerBar() {
    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: kRailwayBlue.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.manage_search, color: kRailwayBlue, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _stationScoped ? (widget.stationName ?? 'Station') : 'All Activities',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                ),
                Text(
                  '${_logs.length} events ${_stationScoped ? 'for this station' : 'across the platform'}',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionFilterBar() {
    final actions = _availableActions();
    if (actions.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: FilterChip(
              label: const Text('All'),
              visualDensity: VisualDensity.compact,
              selected: _selectedAction == null,
              onSelected: (_) {
                if (_selectedAction != null) {
                  _selectedAction = null;
                  _load();
                }
              },
            ),
          ),
          ...actions.map((a) => Padding(
                padding: const EdgeInsets.only(right: 6),
                child: FilterChip(
                  label: Text(_humanAction(a), style: const TextStyle(fontSize: 11)),
                  visualDensity: VisualDensity.compact,
                  selected: _selectedAction == a,
                  onSelected: (_) {
                    _selectedAction = a;
                    _load();
                  },
                ),
              )),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off, size: 40, color: Colors.grey),
              const SizedBox(height: 12),
              const Text('Could not load audit logs', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(_error!, style: const TextStyle(fontSize: 12, color: Colors.grey), textAlign: TextAlign.center),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    if (_logs.isEmpty) {
      return const Center(child: Text('No audit logs found'));
    }
    final groups = _groupByDay(_filteredLogs());
    if (groups.isEmpty) {
      return const Center(child: Text('No entries match your search'));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          for (final entry in groups.entries) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
              child: Row(
                children: [
                  Text(
                    _dayLabel(_parseTs(entry.value.first['timestamp'])),
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Colors.black54),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Divider(color: Colors.grey.shade300, height: 1)),
                  const SizedBox(width: 8),
                  Text('${entry.value.length}',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade600)),
                ],
              ),
            ),
            ...entry.value.map(_buildCard),
          ],
        ],
      ),
    );
  }
}