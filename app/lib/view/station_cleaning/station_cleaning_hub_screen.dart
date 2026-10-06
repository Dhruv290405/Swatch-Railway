import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:crm_train/providers/auth_provider.dart';
import 'package:crm_train/services/api_services.dart';
import 'package:crm_train/utills/app_colors.dart';
import 'package:crm_train/model/contracts_model.dart';
import 'package:crm_train/model/station_models.dart';
import '../common_railways/audit/audit_log_screen.dart';
import 'attendance/station_supervisor_attendance_screen.dart';
import 'billing/area_rate_config_screen.dart';
import 'billing/billing_support_pack_screen.dart';
import 'billing/daily_task_billing_screen.dart';
import 'billing/performance_billing_screen.dart';
import 'feedback/feedback_qr_screen.dart';
import 'feedback/passenger_feedback_form_screen.dart';
import 'feedback/passenger_feedback_list_screen.dart';
import 'inspection/inspection_list_screen.dart';
import 'reporting/report_list_screen.dart';
import '../common_railways/station_management/area_list_screen.dart';
import '../common_railways/station_management/supervisor_shift_assignment_screen.dart';
import '../common_railways/station_management/station_feedback_list_screen.dart';
import '../common_railways/station_management/task_generation_screen.dart';

class StationCleaningHubScreen extends StatefulWidget {
  final String stationId;
  final String stationName;
  final String? contractId;

  const StationCleaningHubScreen({
    super.key,
    required this.stationId,
    required this.stationName,
    this.contractId,
  });

  @override
  State<StationCleaningHubScreen> createState() => _StationCleaningHubScreenState();
}

class _StationCleaningHubScreenState extends State<StationCleaningHubScreen> {
  String _selectedStationId = '';
  String _selectedStationName = '';
  List<Station> _availableStations = [];
  bool _loadingStations = true;
  ContractModel? _stationContract;
  bool _loadingContract = false;

  @override
  void initState() {
    super.initState();
    _selectedStationId = widget.stationId;
    _selectedStationName = widget.stationName;
    _loadStations();
    _resolveStationContract();
  }

  Future<void> _resolveStationContract() async {
    if (_selectedStationId.isEmpty) return;
    setState(() => _loadingContract = true);
    try {
      final contracts = await ApiService.getStationContracts(_selectedStationId, contractType: 'station_cleaning');
      ContractModel? match;
      if (widget.contractId != null) {
        match = contracts.where((c) => c.uid == widget.contractId).firstOrNull;
      }
      match ??= contracts.where((c) => c.isActive ?? false).firstOrNull;
      match ??= contracts.isNotEmpty ? contracts.first : null;
      if (!mounted) return;
      setState(() {
        _stationContract = match;
        _loadingContract = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _stationContract = null;
        _loadingContract = false;
      });
    }
  }

  String? _effectiveContractId() {
    final resolved = _stationContract?.uid;
    if (resolved != null && resolved.isNotEmpty) return resolved;
    final own = widget.contractId;
    if (own != null && own.isNotEmpty) return own;
    return null;
  }

  void _loadStations() async {
    setState(() => _loadingStations = true);
    try {
      final all = await ApiService.getStations();
      setState(() {
        _availableStations = all;
        _loadingStations = false;
      });
    } catch (e) {
      setState(() => _loadingStations = false);
    }
  }

  void _onStationChanged(String? uid) {
    if (uid == null) return;
    final station = _availableStations.firstWhere((s) => s.uid == uid, orElse: () => Station(stationCode: '', stationName: '', zone: '', division: ''));
    setState(() {
      _selectedStationId = uid;
      _selectedStationName = station.stationName;
      _stationContract = null;
    });
    _resolveStationContract();
  }

  bool _canSwitchStation(String role) {
    final r = role.toUpperCase().replaceAll(' ', '_');
    const switchable = {'SUPER_ADMIN', 'ADMIN', 'RAILWAY_ADMIN', 'COMPANY_MASTER', 'RAILWAY_MASTER', 'CONTRACTOR_MASTER'};
    return switchable.contains(r);
  }

  @override
  Widget build(BuildContext context) {
    final role = Provider.of<AuthProvider>(context).currentUser?.role ?? '';

    final billingCards = <Widget>[
      _moduleCard(context, Icons.edit_document, 'Billing', Colors.deepOrange, () => _openBilling(context)),
      if (role.toUpperCase().replaceAll(' ', '_') != 'CONTRACTOR_MASTER')
        _moduleCard(context, Icons.calendar_month, 'Daily Billing', Colors.teal.shade700, () => _openDailyBilling(context)),
      _moduleCard(context, Icons.payments, 'Performance Billing', Colors.redAccent, () => _openPerformanceBilling(context)),
      if (role.toUpperCase().replaceAll(' ', '_') != 'CONTRACTOR_ADMIN')
        _moduleCard(context, Icons.currency_rupee, 'Area Rates & Weightage', Colors.brown, () => _openAreaRates(context)),
    ];

    final sections = <(String, IconData, List<Widget>)>[
      (
        'Operations',
        Icons.handyman_outlined,
        [
          _moduleCard(context, Icons.assignment, 'Generate Task', Colors.deepPurple, () => _openTaskGen(context)),
          _moduleCard(context, Icons.badge, 'Supervisor Attendance', kRailwayBlue, () => _openSupervisorAttendance(context)),
          _moduleCard(context, Icons.nights_stay, 'Supervisor Shift', Colors.indigo.shade400, () => _openSupervisorShift(context)),
          _moduleCard(context, Icons.fact_check_outlined, 'Inspection', Colors.indigo.shade700, () => _openInspection(context)),
          _moduleCard(context, Icons.assessment, 'Reports', Colors.purple, () => _openReports(context)),
        ],
      ),
      (
        'Billing & Rates',
        Icons.receipt_long,
        billingCards,
      ),
      (
        'Records & Support',
        Icons.inventory_2_outlined,
        [
          _moduleCard(context, Icons.manage_search, 'Audit Log', Colors.cyan.shade700, () => _openAuditLog(context)),
          _moduleCard(context, Icons.map, 'Area Management', Colors.lightGreen.shade700, () => _openAreaConfig(context)),
          _moduleCard(context, Icons.feedback_outlined, 'Passenger Feedback', Colors.amber.shade800, () => _openFeedback(context)),
        ],
      ),
    ];

    final titleWidget = _loadingStations
        ? Text(_selectedStationName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))
        : _canSwitchStation(role)
            ? DropdownButton<String>(
                value: _availableStations.any((s) => s.uid == _selectedStationId) ? _selectedStationId : null,
                dropdownColor: kRailwayBlue,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                underline: const SizedBox(),
                icon: const Icon(Icons.arrow_drop_down, color: Colors.white),
                items: _availableStations.map((s) => DropdownMenuItem(
                  value: s.uid,
                  child: Text(s.stationName, style: const TextStyle(color: Colors.white)),
                )).toList(),
                onChanged: _onStationChanged,
              )
            : Text(_selectedStationName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold));

    return Scaffold(
      appBar: AppBar(
        title: titleWidget,
        backgroundColor: kRailwayBlue,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          _introBanner(),
          const SizedBox(height: 8),
          for (final (title, icon, cards) in sections) ...[
            _sectionHeader(title, icon),
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              mainAxisExtent: 104,
              children: cards,
            ),
            const SizedBox(height: 18),
          ],
        ],
      ),
    );
  }

  Widget _introBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [kRailwayBlue, Color(0xFF2F6BB3)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.apps, color: Colors.white, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Module Hub', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                Text('${_availableStations.length} station modules',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 11.5)),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: Colors.white70, size: 20),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 16, 2, 10),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: kRailwayBlue.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Icon(icon, size: 15, color: kRailwayBlue),
          ),
          const SizedBox(width: 8),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          const SizedBox(width: 10),
          Expanded(child: Container(height: 1, color: Colors.grey.shade300)),
        ],
      ),
    );
  }

  Widget _moduleCard(BuildContext context, IconData icon, String label, Color color, VoidCallback onTap) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 0,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 21),
              ),
              const SizedBox(height: 7),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, height: 1.2),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openSupervisorAttendance(BuildContext context) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => StationSupervisorAttendanceScreen(
      stationId: _selectedStationId,
      stationName: _selectedStationName,
    )));
  }

  void _openSupervisorShift(BuildContext context) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => SupervisorShiftAssignmentScreen(
      stationId: _selectedStationId,
      stationName: _selectedStationName,
    )));
  }

  void _openBilling(BuildContext context) {
    if (_loadingContract) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Checking contract for this station…')));
      return;
    }
    final contractId = _effectiveContractId();
    if (contractId != null) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => BillingSupportPackScreen(contractId: contractId, stationId: _selectedStationId, stationName: _selectedStationName)));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No contract linked to this station')));
    }
  }

  void _openDailyBilling(BuildContext context) {
    if (_loadingContract) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Checking contract for this station…')));
      return;
    }
    final contractId = _effectiveContractId();
    if (contractId != null) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => DailyTaskBillingScreen(contractId: contractId, stationId: _selectedStationId, stationName: _selectedStationName)));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No contract linked to this station')));
    }
  }

  void _openPerformanceBilling(BuildContext context) {
    if (_loadingContract) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Checking contract for this station…')));
      return;
    }
    final contractId = _effectiveContractId();
    if (contractId != null) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => PerformanceBillingScreen(
          contractId: contractId, stationId: _selectedStationId, stationName: _selectedStationName)));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No contract linked to this station')));
    }
  }

  void _openAreaRates(BuildContext context) {
    if (_loadingContract) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Checking contract for this station…')));
      return;
    }
    final contractId = _effectiveContractId();
    if (contractId != null) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => AreaRateConfigScreen(contractId: contractId)));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No contract linked to this station')));
    }
  }

  void _openAuditLog(BuildContext context) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => AuditLogScreen(
      stationId: _selectedStationId,
      stationName: _selectedStationName,
    )));
  }

  void _openReports(BuildContext context) {
    final role = Provider.of<AuthProvider>(context, listen: false).currentUser?.role ?? '';
    Navigator.push(context, MaterialPageRoute(builder: (_) => ReportListScreen(stationId: _selectedStationId, stationName: _selectedStationName, role: role)));
  }

  void _openInspection(BuildContext context) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => InspectionListScreen(stationId: _selectedStationId, stationName: _selectedStationName)));
  }

  void _openAreaConfig(BuildContext context) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => AreaListScreen(
      stationId: _selectedStationId,
      stationName: _selectedStationName,
    )));
  }

  void _openTaskGen(BuildContext context) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => TaskGenerationScreen(stationId: _selectedStationId, stationName: _selectedStationName)));
  }

  void _openFeedback(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(padding: EdgeInsets.all(16), child: Text('Feedback Options', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
            ListTile(
              leading: const CircleAvatar(backgroundColor: Colors.green, child: Icon(Icons.edit_note, color: Colors.white)),
              title: const Text('Submit Passenger Feedback'),
              subtitle: const Text('Ask a passenger, record PNR + ratings'),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.push(context, MaterialPageRoute(builder: (_) => PassengerFeedbackFormScreen(stationId: _selectedStationId, stationName: _selectedStationName)));
              },
            ),
            ListTile(
              leading: const CircleAvatar(backgroundColor: Colors.teal, child: Icon(Icons.list_alt, color: Colors.white)),
              title: const Text('View Feedback'),
              subtitle: const Text('Browse feedback recorded against PNRs'),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.push(context, MaterialPageRoute(builder: (_) => PassengerFeedbackListScreen(stationId: _selectedStationId, stationName: _selectedStationName)));
              },
            ),
            const Divider(),
            ListTile(
              leading: const CircleAvatar(child: Icon(Icons.qr_code, color: Colors.white)),
              title: const Text('Generate QR Code'),
              subtitle: const Text('Print & display for passenger feedback'),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.push(context, MaterialPageRoute(builder: (_) => FeedbackQrScreen(stationId: _selectedStationId, stationName: _selectedStationName)));
              },
            ),
            ListTile(
              leading: const CircleAvatar(backgroundColor: Colors.teal, child: Icon(Icons.list, color: Colors.white)),
              title: const Text('View Feedback'),
              subtitle: const Text('Browse submitted passenger feedback'),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.push(context, MaterialPageRoute(builder: (_) => StationFeedbackListScreen(stationId: _selectedStationId)));
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}