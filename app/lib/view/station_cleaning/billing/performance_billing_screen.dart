import 'package:crm_train/model/performance_billing_models.dart';
import 'package:crm_train/providers/auth_provider.dart';
import 'package:crm_train/services/api_services.dart';
import 'package:crm_train/utills/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'performance_bill_detail_screen.dart';
import 'performance_billing_config_screen.dart';
import 'performance_billing_scorecard_screen.dart';

class PerformanceBillingScreen extends StatefulWidget {
  final String? contractId;
  final String stationId;
  final String stationName;
  const PerformanceBillingScreen({super.key, this.contractId, required this.stationId, required this.stationName});

  @override
  State<PerformanceBillingScreen> createState() => _PerformanceBillingScreenState();
}

class _PerformanceBillingScreenState extends State<PerformanceBillingScreen> {
  int _selectedMonth = DateTime.now().month;
  int _selectedYear = DateTime.now().year;
  bool _loading = false;
  bool _generating = false;
  String? _resolvedContractId;
  String? _errorMessage;

  List<PerformanceBill> _bills = [];
  PerformanceBillingDashboard? _dashboard;

  @override
  void initState() {
    super.initState();
    _resolvedContractId = widget.contractId;
    if (_resolvedContractId == null || _resolvedContractId!.isEmpty) {
      _resolveContractId();
    } else {
      _loadAll();
    }
  }

  Future<void> _resolveContractId() async {
    setState(() => _loading = true);
    try {
      final contracts = await ApiService.getActiveContracts();
      final contract = contracts.firstWhere(
        (c) => c.stationIds.contains(widget.stationId),
        orElse: () => throw Exception('No active contract for this station'),
      );
      if (!mounted) return;
      setState(() {
        _resolvedContractId = contract.uid;
        _loading = false;
      });
      _loadAll();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage = e.toString();
      });
    }
  }

  Future<void> _loadAll() async {
    if (_resolvedContractId == null || _resolvedContractId!.isEmpty) return;
    setState(() => _loading = true);
    try {
      final bills = await ApiService.listPerformanceBills(
        contractId: _resolvedContractId,
        stationId: widget.stationId,
      );
      final dashboard = await ApiService.getPerformanceBillingDashboard(
        contractId: _resolvedContractId,
        stationId: widget.stationId,
      );
      if (!mounted) return;
      setState(() {
        _bills = bills;
        _dashboard = dashboard;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage = e.toString();
      });
    }
  }

  bool _can(String permission) {
    final user = Provider.of<AuthProvider>(context, listen: false).currentUser;
    if (user == null) return false;
    final r = user.role.toUpperCase().replaceAll(' ', '_');
    const perms = {
      'SUPER_ADMIN': {'VIEW', 'GENERATE', 'MANAGE', 'CONFIGURE', 'APPROVE', 'PAY'},
      'COMPANY_MASTER': {'VIEW', 'GENERATE', 'MANAGE', 'CONFIGURE', 'APPROVE', 'PAY'},
      'RAILWAY_MASTER': {'VIEW'},
      'ADMIN': {'VIEW', 'GENERATE', 'MANAGE', 'CONFIGURE', 'APPROVE', 'PAY'},
      'RAILWAY_ADMIN': {'VIEW', 'GENERATE', 'MANAGE', 'CONFIGURE', 'APPROVE', 'PAY'},
      'CONTRACTOR_MASTER': {'VIEW', 'CONFIGURE'},
      'CONTRACTOR_ADMIN': {'VIEW', 'GENERATE', 'MANAGE', 'APPROVE', 'PAY'},
      'CONTRACTOR_SUPERVISOR': {'VIEW'},
    };
    return (perms[r] ?? <String>{}).contains(permission);
  }

  List<int> get _years {
    final nowYear = DateTime.now().year;
    return List.generate(5, (i) => nowYear - 1 + i);
  }

  Future<void> _generateBill() async {
    if (_resolvedContractId == null || _resolvedContractId!.isEmpty) return;

    // Gate generation on a configured cleaning rate.
    try {
      final config = await ApiService.getPerformanceBillingConfig(_resolvedContractId!);
      if (config.ratePerSqft == null || config.ratePerSqft! <= 0) {
        if (!mounted) return;
        final open = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Cleaning rate not configured'),
            content: const Text(
                'Bill generation needs a default rate (₹/sqft per execution).\n\n'
                'Set it in Billing Configuration → General, or set per-area rates in the Area Rates tab.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(backgroundColor: kRailwayBlue, foregroundColor: Colors.white),
                child: const Text('Open Settings'),
              ),
            ],
          ),
        );
        if (open == true) _openConfig();
        return;
      }
    } catch (_) {
      // If config cannot be loaded, let generation attempt surface any error.
    }

    setState(() => _generating = true);
    try {
      final bill = await ApiService.generatePerformanceBill(
        contractId: _resolvedContractId!,
        stationId: widget.stationId,
        month: _selectedMonth,
        year: _selectedYear,
      );
      if (!mounted) return;
      setState(() => _generating = false);
      await Navigator.push(context, MaterialPageRoute(builder: (_) =>
          PerformanceBillDetailScreen(billUid: bill.uid, contractId: bill.contractId, stationId: widget.stationId, stationName: widget.stationName)));
      _loadAll();
    } catch (e) {
      if (!mounted) return;
      setState(() => _generating = false);
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e'), backgroundColor: kErrorRed));
    }
  }

  void _openScorecard() {
    if (_resolvedContractId == null || _resolvedContractId!.isEmpty) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) =>
        PerformanceBillingScorecardScreen(
          contractId: _resolvedContractId!,
          stationId: widget.stationId,
          stationName: widget.stationName,
          initialMonth: _selectedMonth,
          initialYear: _selectedYear,
        )));
  }

  void _openConfig() {
    if (_resolvedContractId == null || _resolvedContractId!.isEmpty) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) =>
        PerformanceBillingConfigScreen(contractId: _resolvedContractId!)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Performance Billing', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: kRailwayBlue,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (_resolvedContractId != null && !_resolvedContractId!.isEmpty && _can('CONFIGURE'))
            IconButton(
              icon: const Icon(Icons.tune, color: Colors.white),
              tooltip: 'Billing Configuration',
              onPressed: _openConfig,
            ),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            color: Colors.white,
            child: Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: _selectedMonth,
                    decoration: const InputDecoration(labelText: 'Month', border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8)),
                    items: List.generate(12, (i) => DropdownMenuItem(value: i + 1, child: Text('Month ${i + 1}'))),
                    onChanged: (v) { if (v != null) setState(() => _selectedMonth = v); },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: _selectedYear,
                    decoration: const InputDecoration(labelText: 'Year', border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8)),
                    items: _years.map((y) => DropdownMenuItem(value: y, child: Text(y.toString()))).toList(),
                    onChanged: (v) { if (v != null) setState(() => _selectedYear = v); },
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  children: [
                    SizedBox(
                      height: 44,
                      child: ElevatedButton.icon(
                        onPressed: _generating ? null : _can('GENERATE') ? _generateBill : _openScorecard,
                        icon: Icon(_can('GENERATE') ? Icons.add : Icons.search),
                        style: ElevatedButton.styleFrom(backgroundColor: kRailwayBlue, foregroundColor: Colors.white),
                        label: Text(_can('GENERATE') ? 'New Bill' : 'View'),
                      ),
                    ),
                    const SizedBox(height: 4),
                    SizedBox(
                      height: 34,
                      width: 132,
                      child: OutlinedButton.icon(
                        onPressed: _openScorecard,
                        icon: const Icon(Icons.insights, size: 16),
                        style: OutlinedButton.styleFrom(foregroundColor: kRailwayBlue, padding: const EdgeInsets.symmetric(horizontal: 8)),
                        label: const Text('Scorecard', style: TextStyle(fontSize: 11)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          _buildDashboardSummary(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _errorMessage != null
                    ? Center(child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.error_outline, size: 48, color: kErrorRed),
                          const SizedBox(height: 12),
                          Text(_errorMessage!, textAlign: TextAlign.center, style: const TextStyle(color: kErrorRed)),
                          const SizedBox(height: 12),
                          ElevatedButton(onPressed: _loadAll, child: const Text('Retry')),
                        ]),
                      ))
                    : RefreshIndicator(
                        onRefresh: _loadAll,
                        child: ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.all(12),
                          children: [
                            if (_bills.isEmpty)
                              const Padding(
                                padding: EdgeInsets.all(24),
                                child: Text('No bills yet. Tap "New Bill" to draft the monthly performance bill.',
                                    textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
                              )
                            else
                              ..._bills.map((b) => _billCard(b)),
                            const SizedBox(height: 24),
                          ],
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  String _inr(double v) {
    return v.toStringAsFixed(0).replaceAllMapped(
        RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
  }

  Widget _buildDashboardSummary() {
    final d = _dashboard;
    if (d == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      color: Colors.grey[100],
      child: Row(
        children: [
          Expanded(
            child: _stat('Bills', '${d.totalBills}', Icons.receipt_long, kRailwayBlue),
          ),
          Container(width: 1, height: 36, color: Colors.grey[300]),
          Expanded(
            child: _stat('Billed', '₹${_inr(d.totalBilled)}', Icons.currency_rupee, kSuccessGreen),
          ),
          Container(width: 1, height: 36, color: Colors.grey[300]),
          Expanded(
            child: _stat('To Pay', '₹${_inr(d.totalPayable)}', Icons.account_balance_wallet, Colors.deepOrange),
          ),
          Container(width: 1, height: 36, color: Colors.grey[300]),
          Expanded(
            child: _stat('Paid', '₹${_inr(d.totalPaid)}', Icons.check_circle, kSuccessGreen),
          ),
        ],
      ),
    );
  }

  Widget _stat(String label, String value, IconData icon, Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: color)),
            const SizedBox(height: 1),
            Text(label, style: TextStyle(fontSize: 10, color: Colors.grey[600])),
          ],
        ),
      ],
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'DRAFT': return kRailwayBlue;
      case 'CALCULATED': return Colors.indigo;
      case 'SUBMITTED': return kWarningOrange;
      case 'VERIFIED': return Colors.teal;
      case 'APPROVED': return kSuccessGreen;
      case 'LOCKED': return Colors.deepPurple;
      default: return Colors.grey;
    }
  }

  Widget _billCard(PerformanceBill b) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () async {
          await Navigator.push(context, MaterialPageRoute(builder: (_) =>
              PerformanceBillDetailScreen(billUid: b.uid, contractId: b.contractId, stationId: widget.stationId, stationName: widget.stationName)));
          _loadAll();
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(b.billNumber.isEmpty ? 'Bill' : b.billNumber,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
                  if (b.month == _selectedMonth && b.year == _selectedYear)
                    Container(
                      margin: const EdgeInsets.only(right: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: kRailwayBlue.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                      child: Text('MONTHLY BASE', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: kRailwayBlue)),
                    ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: _statusColor(b.status), borderRadius: BorderRadius.circular(12)),
                    child: Text(b.status, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text('${b.month}/${b.year}  •  ${b.stationName}  •  ${b.contractorName}',
                  style: TextStyle(fontSize: 12, color: Colors.grey[700])),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(6)),
                child: Row(
                  children: [
                    Expanded(
                      child: _cell('RATE', b.ratePerSqft > 0 ? '₹${b.ratePerSqft.toStringAsFixed(2)}' : '—'),
                    ),
                    Expanded(
                      child: _cell('SCHEDULED', '₹${_inr(b.scheduledWorkValue)}'),
                    ),
                    Expanded(
                      child: _cell('VERIFIED GROSS', '₹${_inr(b.grossWorkValue)}'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: Text('Overall', style: TextStyle(fontSize: 11, color: Colors.grey[600]))),
                  Expanded(child: Text('Less Exec.', style: TextStyle(fontSize: 11, color: Colors.grey[600]))),
                  Expanded(child: Text('Eligible', style: TextStyle(fontSize: 11, color: Colors.grey[600]))),
                  Expanded(child: Text('Payable', style: TextStyle(fontSize: 11, color: Colors.grey[600]))),
                ],
              ),
              Row(
                children: [
                  Expanded(child: Text('${b.scorecard.overallScore.toStringAsFixed(1)}%',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                  Expanded(child: Text('₹${_inr(b.lessExecutionAmount)}',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: kErrorRed))),
                  Expanded(child: Text('₹${_inr(b.eligibleAmount)}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                  Expanded(child: Text('₹${_inr(b.totalPayable)}',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.deepOrange))),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cell(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 9, color: Colors.grey[500], fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
      ],
    );
  }
}