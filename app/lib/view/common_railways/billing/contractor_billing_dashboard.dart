import 'package:crm_train/model/billing_models.dart';
import 'package:crm_train/services/api_services.dart';
import 'package:crm_train/utills/app_colors.dart';
import 'package:crm_train/view/common_railways/billing/monthly_bill_screen.dart';
import 'package:crm_train/view/common_railways/billing/billing_report_screen.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

class ContractorBillingDashboard extends StatefulWidget {
  final String stationId;
  final String stationName;
  const ContractorBillingDashboard({super.key, this.stationId = '', this.stationName = ''});

  @override
  State<ContractorBillingDashboard> createState() => _ContractorBillingDashboardState();
}

class _ContractorBillingDashboardState extends State<ContractorBillingDashboard> {
  Map<String, dynamic>? data;
  bool isLoading = true;
  List<BillingReport> _allBills = [];
  DateTime? _from;
  DateTime? _to;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() { isLoading = true; });
    try {
      if (widget.stationId.isNotEmpty) {
        final contracts = await ApiService.getStationContracts(widget.stationId);
        final contractIds = contracts.map((c) => c.uid).toSet();
        final allBills = <BillingReport>[];
        for (final cid in contractIds) {
          try {
            allBills.addAll(await ApiService.getBillingReports(contractId: cid));
          } catch (_) {}
        }
        allBills.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        _allBills = allBills;
        double pending = 0, approved = 0, deductions = 0;
        for (final b in allBills) {
          deductions += b.totalDeduction;
          if (b.status == 'PENDING') pending += b.finalPayable;
          if (b.status == 'APPROVED') approved += b.finalPayable;
        }
        final stationData = <String, dynamic>{
          'configs': contracts.length,
          'totalBills': allBills.length,
          'pendingAmount': pending,
          'approvedAmount': approved,
          'totalDeductions': deductions,
          'recentBills': allBills.take(10).map((b) => b.toJson()).toList(),
        };
        if (mounted) setState(() { data = stationData; isLoading = false; });
      } else {
        final result = await ApiService.getContractorBillingData();
        if (mounted) setState(() { data = result; isLoading = false; });
      }
    } catch (e) {
      if (mounted) setState(() { isLoading = false; });
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _downloadInvoice(Map<String, dynamic>? bill) async {
    final uid = bill?['uid']?.toString() ?? '';
    if (uid.isEmpty) return _toast('No bill available');
    try {
      final token = await ApiService.getToken();
      final url = await ApiService.getInvoicePdfUrl(uid);
      final res = await http.get(Uri.parse(url), headers: {'Authorization': 'Bearer $token'});
      if (res.statusCode != 200) {
        return _toast('Invoice not available yet. It is generated once the bill is approved.');
      }
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/Invoice_$uid.pdf');
      await file.writeAsBytes(res.bodyBytes);
      await OpenFilex.open(file.path);
    } catch (e) {
      _toast('Could not download invoice');
    }
  }

  void _openBillSummary(Map<String, dynamic>? bill) {
    final uid = bill?['uid']?.toString() ?? '';
    if (uid.isEmpty) return _toast('No bill available');
    Navigator.push(context, MaterialPageRoute(builder: (_) => MonthlyBillScreen(billId: uid)));
  }

  @override
  Widget build(BuildContext context) {
    final stationSuffix = widget.stationName.isNotEmpty ? ' - ${widget.stationName}' : '';
    return Scaffold(
      appBar: AppBar(
        title: Text('My Billing$stationSuffix', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: kRailwayBlue,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _loadData, tooltip: 'Refresh')],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : data == null
              ? const Center(child: Text('Could not load billing data'))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildDateFilterBar(),
                      const SizedBox(height: 16),
                      _buildCurrentMonthBill(context),
                      const SizedBox(height: 20),
                      _buildStatsRow(),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          const Text('Bills', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          if (_from != null || _to != null) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(color: kRailwayBlue.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                              child: Text('${_fmtDate(_from)} - ${_fmtDate(_to)}', style: const TextStyle(fontSize: 11, color: kRailwayBlue, fontWeight: FontWeight.w600)),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 12),
                      ..._getFilteredBills().map((b) => _buildBillHistoryCard(context, b)),
                      if ((data!['recentBills'] as List?)?.isEmpty ?? true)
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            widget.stationName.isNotEmpty ? 'No bills found for ${widget.stationName}' : 'No bills yet',
                            style: const TextStyle(color: Colors.grey),
                          ),
                        ),
                      const SizedBox(height: 20),
                      const Text('Downloads', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      _buildDownloadTile(context, Icons.picture_as_pdf, 'Download Invoice', 'Latest invoice'),
                      _buildDownloadTile(context, Icons.table_chart, 'Download Bill Summary', 'Excel format'),
                    ],
                  ),
                ),
    );
  }

  Widget _buildDateFilterBar() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 6, offset: const Offset(2, 3))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Filter by Billing Date', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey)),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _buildDateTile(_from, 'From Date', () => _pickDate(true))),
              const SizedBox(width: 8),
              Expanded(child: _buildDateTile(_to, 'To Date', () => _pickDate(false))),
              const SizedBox(width: 8),
              if (_from != null || _to != null)
                IconButton(
                  onPressed: () => setState(() { _from = null; _to = null; }),
                  icon: const Icon(Icons.clear_all, color: kRailwayBlue),
                  tooltip: 'Clear dates',
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDateTile(DateTime? value, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(color: value != null ? kRailwayBlue : Colors.grey.shade300),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_today, size: 14, color: value != null ? kRailwayBlue : Colors.grey),
            const SizedBox(width: 6),
            Expanded(child: Text(value != null ? _fmtDate(value) : label, style: TextStyle(fontSize: 12, color: value != null ? Colors.black87 : Colors.grey))),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDate(bool isFrom) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: isFrom ? (_from ?? _to ?? now) : (_to ?? _from ?? now),
      firstDate: DateTime(now.year - 10),
      lastDate: now,
      helpText: isFrom ? 'Select From Date' : 'Select To Date',
    );
    if (picked != null) {
      setState(() {
        if (isFrom) _from = picked;
        else _to = picked;
      });
    }
  }

  String _fmtDate(DateTime? d) => d == null ? 'Any' : '${d.day}/${d.month}/${d.year}';

  List<Map<String, dynamic>> _getFilteredBills() {
    final serverBills = ((data!['recentBills'] as List?) ?? []).cast<Map<String, dynamic>>();
    if (_from == null && _to == null) {
      return serverBills;
    }
    final from = _from?.copyWith(hour: 0, minute: 0, second: 0, millisecond: 0, microsecond: 0);
    final to = _to?.copyWith(hour: 23, minute: 59, second: 59, millisecond: 999, microsecond: 999);
    final filtered = _allBills.where((b) {
      final c = b.createdAt;
      if (from != null && c.isBefore(from)) return false;
      if (to != null && c.isAfter(to)) return false;
      return true;
    }).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (filtered.isEmpty) return [];
    return filtered.map((b) => b.toJson()).toList();
  }

  Widget _buildCurrentMonthBill(BuildContext context) {
    final bills = (data!['recentBills'] as List?) ?? [];
    final latest = bills.isNotEmpty ? bills[0] as Map<String, dynamic> : null;
    final pendingAmount = (data!['pendingAmount'] ?? 0).toDouble();
    return Container(
      width: double.infinity, padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(gradient: kRailwayBannerGradient, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: kRailwayBlue.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 5))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Pending Bills Amount', style: TextStyle(color: Colors.white70, fontSize: 14)),
            SizedBox(height: 4),
            Text('Current Outstanding', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
          ]),
          Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), shape: BoxShape.circle), child: const Icon(Icons.account_balance_wallet, color: Colors.white, size: 32)),
        ]),
        const SizedBox(height: 20),
        Text('₹${_formatAmount(pendingAmount)}', style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        if (latest != null) ...[
          Row(children: [
            Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4), decoration: BoxDecoration(color: Colors.orange.withOpacity(0.2), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.orange)), child: Text(latest['status'] ?? 'PENDING', style: const TextStyle(color: Colors.orange, fontSize: 11, fontWeight: FontWeight.bold))),
            const SizedBox(width: 12),
            Text('Score: ${latest['overallScore'] ?? 'N/A'}%', style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 12)),
          ]),
          const SizedBox(height: 16),
        ],
        Row(children: [
          Expanded(child: OutlinedButton.icon(onPressed: () => _downloadInvoice(latest), icon: const Icon(Icons.download, size: 16), label: const Text('Download Invoice', style: TextStyle(fontSize: 11)), style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white)))),
          const SizedBox(width: 12),
          Expanded(child: OutlinedButton.icon(onPressed: () => _openBillSummary(latest), icon: const Icon(Icons.summarize, size: 16), label: const Text('Bill Summary', style: TextStyle(fontSize: 11)), style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white)))),
        ]),
      ]),
    );
  }

  Widget _buildStatsRow() {
    final deductions = (data!['totalDeductions'] ?? 0).toDouble();
    final approved = (data!['approvedAmount'] ?? 0).toDouble();
    final totalBills = (data!['totalBills'] ?? 0);
    return Row(children: [
      Expanded(child: _statCard('Total Deductions', '₹${_formatAmount(deductions)}', Colors.red)),
      const SizedBox(width: 12),
      Expanded(child: _statCard('Approved Amount', '₹${_formatAmount(approved)}', Colors.green)),
      const SizedBox(width: 12),
      Expanded(child: _statCard('Total Bills', '$totalBills', Colors.blue)),
    ]);
  }

  Widget _statCard(String title, String value, Color color) {
    return Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 6, offset: const Offset(2, 3))]),
      child: Column(children: [Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)), const SizedBox(height: 4), Text(title, textAlign: TextAlign.center, style: TextStyle(fontSize: 10, color: Colors.grey.shade600))]));
  }

  Widget _buildBillHistoryCard(BuildContext context, Map<String, dynamic> bill) {
    final status = bill['status'] ?? 'PENDING';
    final statusColor = status == 'APPROVED' ? Colors.green : Colors.orange;
    return Card(margin: const EdgeInsets.only(bottom: 10), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: kRailwayBlue.withOpacity(0.1), borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.receipt, color: kRailwayBlue, size: 24)),
        title: Text(bill['uid']?.toString().substring(0, 12) ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        subtitle: Text(bill['period'] ?? '', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
        trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('₹${_formatAmount((bill['finalPayable'] ?? 0).toDouble())}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: kRailwayBlue)),
          const SizedBox(height: 2),
          Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: statusColor.withOpacity(0.1), borderRadius: BorderRadius.circular(8)), child: Text(status, style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.bold))),
        ]),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => MonthlyBillScreen(billId: bill['uid'] ?? ''))),
      ),
    );
  }

  Widget _buildDownloadTile(BuildContext context, IconData icon, String title, String subtitle) {
    return Card(margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: kRailwayBlue.withOpacity(0.1), borderRadius: BorderRadius.circular(8)), child: Icon(icon, color: kRailwayBlue)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
        trailing: const Icon(Icons.download, color: kRailwayBlue),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => BillingReportScreen())),
      ),
    );
  }

  String _formatAmount(double amount) {
    if (amount >= 10000000) return '${(amount / 10000000).toStringAsFixed(2)}Cr';
    if (amount >= 100000) return '${(amount / 100000).toStringAsFixed(2)}L';
    if (amount >= 1000) return '${(amount / 1000).toStringAsFixed(1)}K';
    return amount.toStringAsFixed(0);
  }
}