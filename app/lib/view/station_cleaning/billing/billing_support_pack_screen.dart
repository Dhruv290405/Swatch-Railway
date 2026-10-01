import 'package:crm_train/model/station_cleaning_models.dart';
import 'package:crm_train/providers/auth_provider.dart';
import 'package:crm_train/repositories/station_billing_repository.dart';
import 'package:crm_train/services/api_services.dart';
import 'package:crm_train/services/pdf_report_service.dart';
import 'package:crm_train/utills/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';

class BillingSupportPackScreen extends StatefulWidget {
  final String? contractId;
  final String stationId;
  final String stationName;
  const BillingSupportPackScreen({super.key, this.contractId, required this.stationId, required this.stationName});

  @override
  State<BillingSupportPackScreen> createState() => _BillingSupportPackScreenState();
}

class _BillingSupportPackScreenState extends State<BillingSupportPackScreen> {
  bool _isLoading = false;
  int _selectedMonth = DateTime.now().month;
  int _selectedYear = DateTime.now().year;

  StationBillingPack? _billingPack;
  List<StationBillingPack> _historyPacks = [];
  bool _historyLoading = false;
  String? _errorMessage;
  final TextEditingController _rejectionReasonCtrl = TextEditingController();
  String? _resolvedContractId;
  bool _busy = false;
  String _busyMessage = '';

  @override
  void initState() {
    super.initState();
    _resolvedContractId = widget.contractId;
    if (_resolvedContractId == null || _resolvedContractId!.isEmpty) {
      _resolveContractId();
    } else {
      _loadHistory();
    }
  }

  Future<void> _loadHistory() async {
    if (_resolvedContractId == null || _resolvedContractId!.isEmpty) return;
    setState(() => _historyLoading = true);
    try {
      final packs = await StationBillingRepository.list({
        'contractId': _resolvedContractId!,
        'stationId': widget.stationId,
        'limit': '100',
      });
      if (!mounted) return;
      setState(() {
        _historyPacks = packs;
        _historyLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _historyLoading = false);
    }
  }

  Future<void> _resolveContractId() async {
    setState(() => _isLoading = true);
    try {
      final contracts = await ApiService.getActiveContracts();
      final contract = contracts.firstWhere(
        (c) => c.stationIds.contains(widget.stationId),
        orElse: () => throw Exception('No active contract found for this station'),
      );
      setState(() {
        _resolvedContractId = contract.uid;
        _isLoading = false;
      });
      _loadHistory();
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to resolve contract: $e'), backgroundColor: kErrorRed),
        );
      }
    }
  }

  @override
  void dispose() {
    _rejectionReasonCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchOrGenerate() async {
    if (!mounted) return;
    if (_resolvedContractId == null || _resolvedContractId!.isEmpty) {
      await _resolveContractId();
    }
    if (!mounted) return;
    if (_resolvedContractId == null || _resolvedContractId!.isEmpty) return;

    setState(() { _isLoading = true; _errorMessage = null; });
    try {
      StationBillingPack pack;
      if (_can('GENERATE')) {
        pack = await StationBillingRepository.generate(
          _resolvedContractId!,
          widget.stationId,
          _selectedMonth,
          _selectedYear,
        );
      } else {
        final existing = await StationBillingRepository.list({
          'contractId': _resolvedContractId!,
          'stationId': widget.stationId,
          'month': '$_selectedMonth',
          'year': '$_selectedYear',
        });
        if (existing.isEmpty) {
          if (!mounted) return;
          setState(() {
            _billingPack = null;
            _isLoading = false;
            _errorMessage = 'No billing pack exists for ${_selectedMonth}/${_selectedYear}. '
                'You have view-only access — generation is done by the contractor admin or railway. '
                'Pick a month below that has a pack (see Previous Billing Packs).';
          });
          return;
        }
        pack = existing.first;
      }
      if (!mounted) return;
      setState(() => _billingPack = pack);
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = e.toString());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e'), backgroundColor: kErrorRed),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _updateComplianceCheckbox(String key, bool val) async {
    if (_billingPack == null || _busy) return;
    final updatedChecklist = Map<String, dynamic>.from(_billingPack!.complianceChecklist);
    updatedChecklist[key] = val;
    try {
      await _runBusy('Saving compliance checklist...', () async {
        await StationBillingRepository.updateCompliance(_billingPack!.uid, updatedChecklist);
        await _fetchOrGenerate();
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e'), backgroundColor: kErrorRed),
        );
      }
    }
  }

  Future<void> _submitPack() async {
    if (_billingPack == null || _busy) return;
    try {
      await _runBusy('Submitting billing pack for review...', () async {
        await StationBillingRepository.submit(_billingPack!.uid);
        await _fetchOrGenerate();
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Submission failed: $e'), backgroundColor: kErrorRed),
        );
      }
    }
  }

  Future<void> _approvePack() async {
    if (_billingPack == null || _busy) return;
    try {
      await _runBusy('Approving billing pack...', () async {
        await StationBillingRepository.approve(_billingPack!.uid);
        await _fetchOrGenerate();
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Approval failed: $e'), backgroundColor: kErrorRed),
        );
      }
    }
  }

  Future<void> _rejectPack() async {
    if (_billingPack == null || _busy) return;
    try {
      await _runBusy('Rejecting billing pack...', () async {
        await StationBillingRepository.reject(_billingPack!.uid, _rejectionReasonCtrl.text.trim());
        await _fetchOrGenerate();
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Rejection failed: $e'), backgroundColor: kErrorRed),
        );
      }
    }
  }

  bool _can(String permission) {
    final user = Provider.of<AuthProvider>(context, listen: false).currentUser;
    if (user == null) return false;
    final r = user.role.toUpperCase().replaceAll(' ', '_');
    const perms = {
      'SUPER_ADMIN': {'VIEW', 'GENERATE', 'MANAGE', 'APPROVE', 'PAY'},
      'COMPANY_MASTER': {'VIEW', 'GENERATE', 'MANAGE', 'APPROVE', 'PAY'},
      'RAILWAY_MASTER': {'VIEW'},
      'ADMIN': {'VIEW', 'GENERATE', 'MANAGE', 'APPROVE', 'PAY'},
      'RAILWAY_ADMIN': {'VIEW', 'GENERATE', 'MANAGE', 'APPROVE', 'PAY'},
      'CONTRACTOR_MASTER': {'VIEW'},
      'CONTRACTOR_ADMIN': {'VIEW', 'GENERATE', 'MANAGE', 'APPROVE'},
      'CONTRACTOR_SUPERVISOR': {'VIEW'},
    };
    return (perms[r] ?? <String>{}).contains(permission);
  }

  Future<void> _runBusy(String message, Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _busyMessage = message;
    });
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _downloadPdf() async {
    if (_billingPack == null || _busy) return;
    try {
      await _runBusy('Generating PDF, please wait...', () async {
        // Let the progress overlay render before the heavy PDF work starts.
        await Future<void>.delayed(const Duration(milliseconds: 150));
        final pdfBytes = await PDFReportService.generateStationBillingPdf(_billingPack!);
        await Printing.sharePdf(
          bytes: pdfBytes,
          filename: 'BillingPack_${_billingPack!.contractNumber}_${_billingPack!.month}_${_billingPack!.year}.pdf',
        );
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Download failed: $e'), backgroundColor: kErrorRed),
        );
      }
    }
  }

  Future<void> _recordPayment() async {
    final amountCtrl = TextEditingController();
    final refCtrl = TextEditingController();
    String mode = 'bank_transfer';
    final modes = ['bank_transfer', 'cheque', 'cash', 'online'];
    final recorded = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Record Payment'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: amountCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Amount *', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: mode,
                decoration: const InputDecoration(labelText: 'Mode *', border: OutlineInputBorder()),
                items: modes.map((m) => DropdownMenuItem(value: m, child: Text(m.replaceAll('_', ' ').toUpperCase()))).toList(),
                onChanged: (v) { if (v != null) mode = v; },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: refCtrl,
                decoration: const InputDecoration(labelText: 'Reference *', border: OutlineInputBorder(), hintText: 'e.g. payment ref no.'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              final amount = double.tryParse(amountCtrl.text.trim());
              if (amount == null || amount <= 0) return;
              if (refCtrl.text.trim().isEmpty) return;
              Navigator.pop(ctx, {'amount': amountCtrl.text.trim(), 'mode': mode, 'reference': refCtrl.text.trim()});
            },
            child: const Text('Record Payment'),
          ),
        ],
      ),
    );
    if (recorded == null) return;
    try {
      await _runBusy('Recording payment...', () async {
        await StationBillingRepository.recordPayment(
          _billingPack!.uid,
          amount: double.parse(recorded['amount']!),
          mode: recorded['mode']!,
          reference: recorded['reference'],
        );
        await _fetchOrGenerate();
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Payment recorded'), backgroundColor: kSuccessGreen),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Payment failed: $e'), backgroundColor: kErrorRed),
        );
      }
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'DRAFT': return kRailwayBlue;
      case 'SUBMITTED': return kWarningOrange;
      case 'APPROVED': return kSuccessGreen;
      case 'REJECTED': return kErrorRed;
      default: return Colors.grey;
    }
  }

  Widget _summaryCard(String title, List<Widget> rows, {Color? headerColor}) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            color: headerColor ?? kRailwayBlue,
            child: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
          ),
          ...rows,
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value, {Color? valueColor, bool bold = true}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 160, child: Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 12))),
          Expanded(child: Text(value, style: TextStyle(fontWeight: bold ? FontWeight.w600 : FontWeight.normal, fontSize: 12, color: valueColor))),
        ],
      ),
    );
  }

  Widget _divider() => Divider(height: 1, color: Colors.grey[200]);

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Scaffold(
      appBar: AppBar(
        title: const Text('Billing Support Pack', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: kRailwayBlue,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (_billingPack != null)
            IconButton(
              icon: const Icon(Icons.download, color: Colors.white),
              tooltip: 'Download PDF',
              onPressed: _busy ? null : _downloadPdf,
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
                    value: _selectedMonth,
                    decoration: const InputDecoration(labelText: 'Month', border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8)),
                    items: List.generate(12, (i) => DropdownMenuItem(value: i + 1, child: Text(DateTime(2000, i + 1).month.toString()))),
                    onChanged: (v) { if (v != null) setState(() => _selectedMonth = v); },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    value: _selectedYear,
                    decoration: const InputDecoration(labelText: 'Year', border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8)),
                    items: [2024, 2025, 2026, 2027].map((y) => DropdownMenuItem(value: y, child: Text(y.toString()))).toList(),
                    onChanged: (v) { if (v != null) setState(() => _selectedYear = v); },
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 44,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _fetchOrGenerate,
                    style: ElevatedButton.styleFrom(backgroundColor: kRailwayBlue, foregroundColor: Colors.white),
                    child: Text(_can('GENERATE') ? 'Go' : 'View'),
                  ),
                ),
              ],
            ),
          ),
          _buildHistoryCard(),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _errorMessage != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.error_outline, size: 48, color: kErrorRed),
                              const SizedBox(height: 12),
                              Text(_errorMessage!, textAlign: TextAlign.center, style: const TextStyle(color: kErrorRed)),
                              const SizedBox(height: 12),
                              ElevatedButton(onPressed: _fetchOrGenerate, child: const Text('Retry')),
                            ],
                          ),
                        ),
                      )
                    : _billingPack == null
                        ? const Center(child: Text('Select month/year and tap Go to generate billing support pack.'))
                        : RefreshIndicator(
                            onRefresh: _fetchOrGenerate,
                            child: SingleChildScrollView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildHeaderSection(),
                                  const SizedBox(height: 12),
                                  _buildAttendanceSection(),
                                  _buildActivitySection(),
                                  _buildScorecardSection(),
                                  _buildInspectionSection(),
                                  _buildFeedbackSection(),
                                  _buildPettyIssueSection(),
                                  _buildEvidenceSection(),
                                  _buildMachineSection(),
                                  _buildTaskExecutionSection(),
                                  _buildExecutionSheetSection(),
                                  _buildInspectionBillingSection(),
                                  _buildObhsScoreSection(),
                                  _buildPenaltySection(),
                                  _buildFinancialSection(),
                                  _buildComplianceSection(),
                                  _buildActionButtons(),
                                  const SizedBox(height: 24),
                                ],
                              ),
                            ),
                          ),
          ),
        ],
      ),
    ),
        if (_busy) ...[
          const Positioned.fill(
            child: ModalBarrier(dismissible: false, color: Colors.black54),
          ),
          Center(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 40),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 12)],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(_busyMessage,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _openHistoryPack(StationBillingPack p) async {
    if (!mounted) return;
    setState(() {
      _selectedMonth = p.month;
      _selectedYear = p.year;
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final fresh = await StationBillingRepository.getById(p.uid);
      if (!mounted) return;
      setState(() {
        _billingPack = fresh;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _billingPack = p;
        _isLoading = false;
      });
    }
  }

  Widget _buildHistoryCard() {
    if (_historyLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 10),
        child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
      );
    }
    if (_historyPacks.isEmpty) return const SizedBox.shrink();
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.history, size: 16, color: kRailwayBlue),
                SizedBox(width: 6),
                Text('Previous Billing Packs', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${_historyPacks.length} month${_historyPacks.length != 1 ? 's' : ''} billed. Tap a month to view it.',
              style: TextStyle(fontSize: 11, color: Colors.grey[500]),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 46,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _historyPacks.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  final p = _historyPacks[i];
                  return InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => _openHistoryPack(p),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: p.uid == _billingPack?.uid ? kRailwayBlue.withOpacity(0.12) : Colors.white,
                        border: Border.all(color: p.uid == _billingPack?.uid ? kRailwayBlue : Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${p.month}/${p.year}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          Row(
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(color: _statusColor(p.status), shape: BoxShape.circle),
                              ),
                              const SizedBox(width: 4),
                              Text(p.status, style: TextStyle(fontSize: 9, color: Colors.grey[600])),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderSection() {
    final p = _billingPack!;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${p.contractorName}',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: _statusColor(p.status),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(p.status, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('Contract: ${p.contractNumber}', style: TextStyle(color: Colors.grey[600], fontSize: 12)),
            Text('Period: ${p.month}/${p.year} | Station: ${p.stationName}', style: TextStyle(color: Colors.grey[600], fontSize: 12)),
            if (p.status == 'REJECTED' && p.rejectionReason != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: kErrorRed.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
                child: Row(children: [
                  const Icon(Icons.error, color: kErrorRed, size: 16),
                  const SizedBox(width: 6),
                  Expanded(child: Text('Rejection: ${p.rejectionReason}', style: const TextStyle(color: kErrorRed, fontSize: 11))),
                ]),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAttendanceSection() {
    final s = _billingPack!.attendanceSummary;
    return _summaryCard('Attendance Summary', [
      _infoRow('Days Recorded', '${s['totalDaysRecorded'] ?? 0}'),
      _divider(),
      _infoRow('Total Entries', '${s['totalAttendanceEntries'] ?? 0}'),
      _infoRow('Present (incl. Late)', '${s['totalPresent'] ?? 0}', valueColor: kSuccessGreen),
      _infoRow('Absent', '${s['totalAbsent'] ?? 0}', valueColor: kErrorRed),
      _divider(),
      _infoRow('Avg Daily Manpower', '${s['averageDailyManpower'] ?? 0}'),
      _infoRow('Attendance %', '${s['attendancePercentage'] ?? 0}%',
          valueColor: (s['attendancePercentage'] ?? 0) >= 90 ? kSuccessGreen : kErrorRed),
    ]);
  }

  Widget _buildActivitySection() {
    final s = _billingPack!.activitySummary;
    return _summaryCard('Task Completion Summary', [
      _infoRow('Total Tasks', '${s['total'] ?? 0}'),
      _divider(),
      _infoRow('Approved', '${s['APPROVED'] ?? 0}', valueColor: kSuccessGreen),
      _infoRow('Completed', '${s['COMPLETED'] ?? 0}', valueColor: Colors.blue),
      _infoRow('In Progress', '${s['IN_PROGRESS'] ?? 0}', valueColor: kWarningOrange),
      _infoRow('Pending', '${s['PENDING'] ?? 0}', valueColor: Colors.grey),
      _infoRow('Rejected', '${s['REJECTED'] ?? 0}', valueColor: kErrorRed),
      _infoRow('Resubmitted', '${s['RESUBMITTED'] ?? 0}', valueColor: kWarningOrange),
      _divider(),
      _infoRow('Completion Rate', '${s['completionRate'] ?? 0}%',
          valueColor: (s['completionRate'] ?? 0) >= 80 ? kSuccessGreen : kErrorRed),
    ]);
  }

  Widget _buildScorecardSection() {
    final s = _billingPack!.scorecardSummary;
    final grades = s['gradeDistribution'] as Map<String, dynamic>? ?? {};
    return _summaryCard('Cleanliness Scorecard Summary', [
      _infoRow('Days with Scorecard', '${s['daysWithScorecard'] ?? 0}'),
      _infoRow('Average Score', '${s['averageScore'] ?? 0}',
          valueColor: (s['averageScore'] ?? 0) >= 70 ? kSuccessGreen : kErrorRed),
      _infoRow('Certified', '${s['certified'] == true ? 'Yes' : 'No'}'),
      _divider(),
      _infoRow('Grade A', '${grades['A'] ?? 0}', valueColor: kSuccessGreen),
      _infoRow('Grade B', '${grades['B'] ?? 0}', valueColor: Colors.blue),
      _infoRow('Grade C', '${grades['C'] ?? 0}', valueColor: kWarningOrange),
      _infoRow('Grade D', '${grades['D'] ?? 0}', valueColor: kErrorRed),
    ]);
  }

  Widget _buildInspectionSection() {
    final s = _billingPack!.inspectionSummary;
    if (s.isEmpty) return const SizedBox.shrink();
    return _summaryCard('Inspection Score Summary', [
      _infoRow('Total Inspections', '${s['totalInspections'] ?? 0}'),
      _infoRow('Average Score', '${s['averageScore'] ?? 0}',
          valueColor: (s['averageScore'] ?? 0) >= 70 ? kSuccessGreen : kErrorRed),
      _divider(),
      _infoRow('Total Deficiencies', '${s['totalDeficiencies'] ?? 0}', valueColor: kErrorRed),
      _infoRow('Closed Deficiencies', '${s['closedDeficiencies'] ?? 0}', valueColor: kSuccessGreen),
      _infoRow('Open Deficiencies', '${s['openDeficiencies'] ?? 0}',
          valueColor: (s['openDeficiencies'] ?? 0) > 0 ? kErrorRed : kSuccessGreen),
    ]);
  }

  Widget _buildFeedbackSection() {
    final s = _billingPack!.feedbackSummary;
    final fs = _billingPack!.feedbackScore;
    return _summaryCard('Passenger Feedback (30% Billing Component)', [
      _infoRow('Total Feedbacks', '${s['totalFeedbacks'] ?? 0}'),
      _infoRow('Average Rating', '${s['averageRating'] ?? 'N/A'}',
          valueColor: (s['averageRating'] ?? 5) >= 3.0 ? kSuccessGreen : kErrorRed),
      _infoRow('Negative Feedbacks', '${s['negativeFeedbacks'] ?? 0}',
          valueColor: (s['negativeFeedbacks'] ?? 0) > 0 ? kErrorRed : kSuccessGreen),
      if (fs != null) ...[
        _divider(),
        _infoRow('Feedback Score', '${fs.toStringAsFixed(1)}%',
            valueColor: fs >= 80 ? kSuccessGreen : fs >= 50 ? kWarningOrange : kErrorRed),
      ],
    ]);
  }

  Widget _buildPettyIssueSection() {
    final s = _billingPack!.pettyIssueSummary;
    if (s.isEmpty) return const SizedBox.shrink();
    return _summaryCard('Petty Issue Summary', [
      _infoRow('Total Petty Issues', '${s['total'] ?? 0}'),
      _infoRow('Resolved', '${s['resolved'] ?? 0}', valueColor: kSuccessGreen),
      _infoRow('Open', '${s['open'] ?? 0}', valueColor: (s['open'] ?? 0) > 0 ? kErrorRed : kSuccessGreen),
    ]);
  }

  Widget _buildEvidenceSection() {
    final s = _billingPack!.evidenceSummary;
    if (s.isEmpty) return const SizedBox.shrink();
    final rate = s['evidenceComplianceRate'] ?? 0;
    return _summaryCard('Photo Evidence Summary', [
      _infoRow('Total Forms', '${s['totalForms'] ?? 0}'),
      _infoRow('Forms with Photos', '${s['formsWithPhotos'] ?? 0}', valueColor: kSuccessGreen),
      _infoRow('Total Photos Uploaded', '${s['totalPhotos'] ?? 0}'),
      _divider(),
      _infoRow('Evidence Compliance', '$rate%',
          valueColor: rate >= 80 ? kSuccessGreen : kWarningOrange),
    ]);
  }

  Widget _buildMachineSection() {
    final s = _billingPack!.machineSummary;
    return _summaryCard('Machine & Equipment Summary', [
      _infoRow('Total Machines', '${s['total'] ?? 0}'),
      _infoRow('Deployed', '${s['deployed'] ?? 0}', valueColor: kSuccessGreen),
      _infoRow('In Maintenance', '${s['inMaintenance'] ?? 0}',
          valueColor: (s['inMaintenance'] ?? 0) > 0 ? kWarningOrange : kSuccessGreen),
      _divider(),
      _infoRow('Downtime Incidents', '${s['downtime']?['incidents'] ?? 0}'),
      _infoRow('Downtime Hours', '${s['downtime']?['totalHours'] ?? 0}'),
      _infoRow('Downtime Penalty', '₹${s['downtime']?['totalPenalty'] ?? 0}',
          valueColor: (s['downtime']?['totalPenalty'] ?? 0) > 0 ? kErrorRed : kSuccessGreen),
    ]);
  }

  Widget _buildTaskExecutionSection() {
    final s = _billingPack!.taskExecutionSummary;
    if (s.isEmpty || s['configured'] != true) return const SizedBox.shrink();
    final score = s['taskExecutionScore'] ?? 0;
    final shortfall = s['shortfallDeduction'] ?? 0;
    final achieved = s['achievedAmount'] ?? 0;
    final componentBase = s['taskExecutionComponentNetBase'] ?? 0;
    return _summaryCard('Task Execution (50% Billing Component)', [
      _infoRow('Task Execution Score', '$score%',
          valueColor: score >= 80 ? kSuccessGreen : score >= 50 ? kWarningOrange : kErrorRed),
      _infoRow('Approved Shift Summaries', '${s['approvedShiftSummaries'] ?? 0}'),
      _infoRow('Submitted (Awaiting Approval)', '${s['submittedShiftSummaries'] ?? 0}'),
      _infoRow('Approved Days', '${s['approvedDays'] ?? 0}'),
      _infoRow('Execution Rate (Work/Tendered)', '${s['shiftExecutionRate'] ?? 0}%',
          valueColor: (s['shiftExecutionRate'] ?? 0) >= 80 ? kSuccessGreen : kWarningOrange),
      _infoRow('Shift Photo Compliance', '${s['shiftPhotoComplianceRate'] ?? 0}%',
          valueColor: (s['shiftPhotoComplianceRate'] ?? 0) >= 80 ? kSuccessGreen : kWarningOrange),
      _divider(),
      _infoRow('Component Base (50%)', '₹$componentBase'),
      _infoRow('Achieved Amount', '₹$achieved', valueColor: kSuccessGreen),
      if (shortfall > 0)
        _infoRow('Shortfall Deduction', '₹$shortfall', valueColor: kErrorRed),
    ]);
  }

  Widget _buildExecutionSheetSection() {
    final s = _billingPack!.executionSheetSummary;
    if (s.isEmpty || s['configured'] != true) return const SizedBox.shrink();
    final score = s['executionScore'] ?? 0;
    final shortfall = s['shortfallDeduction'] ?? 0;
    final achieved = s['achievedAmount'] ?? 0;
    final componentBase = s['executionComponentNetBase'] ?? 0;
    final items = (s['itemScores'] as List<dynamic>?) ?? [];
    return _summaryCard('Work Execution Sheet (Annexure-AB, Reference)', [
      _infoRow('Execution Score', '$score%',
          valueColor: score >= 80 ? kSuccessGreen : score >= 50 ? kWarningOrange : kErrorRed),
      _infoRow('Items Configured', '${s['items'] ?? 0}'),
      _infoRow('Days Logged', '${s['daysLogged'] ?? 0}'),
      _infoRow('Days Area Executed', '${s['daysAreaExecuted'] ?? 0}'),
      _divider(),
      _infoRow('Component Base (50%)', '₹$componentBase'),
      _infoRow('Achieved Amount', '₹$achieved', valueColor: kSuccessGreen),
      if (shortfall > 0)
        _infoRow('Shortfall Deduction', '₹$shortfall', valueColor: kErrorRed),
      if (items.isNotEmpty) ...[
        _divider(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          child: Text('Item Breakdown', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey[600])),
        ),
        ...items.take(10).map((item) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          child: Row(
            children: [
              Expanded(
                child: Text('#${item['itemNo']} ${item['description'] ?? ''}',
                    style: const TextStyle(fontSize: 11), overflow: TextOverflow.ellipsis),
              ),
              Text('${item['achievedRatio'] ?? 0}%',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: (item['achievedRatio'] ?? 0) >= 80 ? kSuccessGreen : kWarningOrange,
                  )),
            ],
          ),
        )),
        if (items.length > 10)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
            child: Text('...and ${items.length - 10} more', style: TextStyle(fontSize: 10, color: Colors.grey[500])),
          ),
      ],
    ]);
  }

  Widget _buildInspectionBillingSection() {
    final s = _billingPack!.inspectionBillingSummary;
    if (s.isEmpty || s['configured'] != true) return const SizedBox.shrink();
    final score = s['inspectionScore'] ?? 0;
    final shortfall = s['shortfallDeduction'] ?? 0;
    final achieved = s['achievedAmount'] ?? 0;
    final componentBase = s['inspectionComponentNetBase'] ?? 0;
    final totalInspected = s['totalScoredInspections'] ?? 0;
    return _summaryCard('Inspection Score (20% Billing Component)', [
      _infoRow('Inspection Score', '$score',
          valueColor: score >= 80 ? kSuccessGreen : score >= 50 ? kWarningOrange : kErrorRed),
      _infoRow('Scored Inspections', '$totalInspected'),
      _divider(),
      _infoRow('Component Base (20%)', '₹$componentBase'),
      _infoRow('Achieved Amount', '₹$achieved', valueColor: kSuccessGreen),
      if (shortfall > 0)
        _infoRow('Shortfall Deduction', '₹$shortfall', valueColor: kErrorRed),
    ]);
  }

  Widget _buildObhsScoreSection() {
    final p = _billingPack!;
    final os = p.overallScore;
    if (os == null) return const SizedBox.shrink();
    final components = p.scoreBreakdown as List<dynamic>? ?? [];
    return _summaryCard('OBHS-Aligned Score (50% Task Execution + 20% Inspection + 30% Feedback)', [
      _infoRow('Overall Score', '${os.toStringAsFixed(1)}%',
          valueColor: os >= 80 ? kSuccessGreen : os >= 60 ? kWarningOrange : kErrorRed),
      _infoRow('Grade', '${p.grade ?? 'N/A'}',
          valueColor: os >= 80 ? kSuccessGreen : os >= 60 ? kWarningOrange : kErrorRed),
      _infoRow('Deduction Rate', '${p.deductionRate ?? 100}%'),
      _divider(),
      if (components.isEmpty)
        const Padding(
          padding: EdgeInsets.all(14),
          child: Text('No scored components available for this period.', style: TextStyle(color: Colors.grey)),
        )
      else
        ...components.map((c) => _infoRow(
          '${c['component'] ?? ''} (${c['weight'] ?? 0}%)',
          '${((c['score'] ?? 0) as num).toStringAsFixed(1)}%',
          valueColor: (c['score'] ?? 0) >= 80 ? kSuccessGreen : (c['score'] ?? 0) >= 50 ? kWarningOrange : kErrorRed,
        )),
    ]);
  }

  Widget _buildPenaltySection() {
    final p = _billingPack!.penalties;
    final deductions = (p['deductions'] as List<dynamic>?) ?? [];
    return _summaryCard('Penalties & Deductions', [
      if (deductions.isEmpty)
        const Padding(
          padding: EdgeInsets.all(14),
          child: Text('No deductions applied', style: TextStyle(color: Colors.grey)),
        )
      else
        ...deductions.map((d) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              child: Row(
                children: [
                  Expanded(child: Text('${d['reason'] ?? ''}', style: const TextStyle(fontSize: 12))),
                  Text('₹${d['amount'] ?? 0}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: kErrorRed)),
                ],
              ),
            ),
            if (d['percentage'] != null && (d['percentage'] as num) > 0)
              Padding(
                padding: const EdgeInsets.only(left: 14, bottom: 4),
                child: Text('${d['percentage']}%', style: TextStyle(fontSize: 10, color: Colors.grey[500])),
              ),
            _divider(),
          ],
        )),
      _divider(),
      _infoRow('Total Penalty', '₹${p['totalPenaltyAmount'] ?? 0}',
          valueColor: (p['totalPenaltyAmount'] ?? 0) > 0 ? kErrorRed : kSuccessGreen),
    ]);
  }

  Widget _buildFinancialSection() {
    final p = _billingPack!;
    final os = p.overallScore;
    return _summaryCard('Financial Summary', [
      _infoRow('Monthly Contract Value', '₹${p.monthlyContractValue}'),
      if (os != null)
        _infoRow('Overall Score', '${os.toStringAsFixed(1)}%', valueColor: os >= 80 ? kSuccessGreen : kErrorRed),
      _infoRow('Total Deductions', '₹${p.penalties['totalPenaltyAmount'] ?? 0}', valueColor: kErrorRed),
      _divider(),
      _infoRow('Net Billable', '₹${p.billableAmount}', valueColor: kSuccessGreen, bold: true),
      _infoRow('GST (${p.gstRate}%)', '₹${p.gstAmount}'),
      _infoRow('Total Payable (incl. GST)', '₹${p.totalPayableWithGst}',
          valueColor: Colors.deepOrange, bold: true),
    ]);
  }

  Widget _buildComplianceSection() {
    final checklist = _billingPack!.complianceChecklist;
    return _summaryCard('Compliance Document Checklist', [
      ...checklist.keys.map((key) {
        final val = checklist[key] == true;
        return CheckboxListTile(
          dense: true,
          title: Text(key
            .replaceAll('Attached', '')
            .replaceAllMapped(RegExp(r'[A-Z]'), (m) => ' ${m.group(0)}')
            .trim()
            .toUpperCase(),
            style: const TextStyle(fontSize: 12)),
          value: val,
          activeColor: kRailwayBlue,
          onChanged: _can('MANAGE')
              ? (v) { if (v != null) _updateComplianceCheckbox(key, v); }
              : null,
        );
      }),
    ]);
  }

  Widget _buildActionButtons() {
    final p = _billingPack!;
    if (p.status == 'DRAFT' && _can('MANAGE')) {
      return SizedBox(
        width: double.infinity,
        height: 48,
        child: ElevatedButton.icon(
          onPressed: _busy ? null : _submitPack,
          icon: const Icon(Icons.send),
          style: ElevatedButton.styleFrom(backgroundColor: kRailwayBlue, foregroundColor: Colors.white),
          label: const Text('Submit Pack for Review'),
        ),
      );
    }
    if (p.status == 'SUBMITTED' && _can('APPROVE')) {
      return Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 48,
              child: ElevatedButton.icon(
                onPressed: _busy ? null : _approvePack,
                icon: const Icon(Icons.check_circle),
                style: ElevatedButton.styleFrom(backgroundColor: kSuccessGreen, foregroundColor: Colors.white),
                label: const Text('Approve'),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: SizedBox(
              height: 48,
              child: ElevatedButton.icon(
                onPressed: _busy
                  ? null
                  : () {
                      _rejectionReasonCtrl.clear();
                      showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Reject Billing Pack'),
                      content: TextField(
                        controller: _rejectionReasonCtrl,
                        decoration: const InputDecoration(
                          hintText: 'Enter reason for rejection',
                          border: OutlineInputBorder(),
                        ),
                        maxLines: 3,
                      ),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                        TextButton(
                          onPressed: () {
                            Navigator.pop(ctx);
                            _rejectPack();
                          },
                          style: TextButton.styleFrom(foregroundColor: kErrorRed),
                          child: const Text('Reject'),
                        ),
                      ],
                    ),
                  );
                },
                icon: const Icon(Icons.cancel),
                style: ElevatedButton.styleFrom(backgroundColor: kErrorRed, foregroundColor: Colors.white),
                label: const Text('Reject'),
              ),
            ),
          ),
        ],
      );
    }
    if (p.status == 'APPROVED' && _can('PAY')) {
      return SizedBox(
        width: double.infinity,
        height: 48,
        child: ElevatedButton.icon(
          onPressed: _busy ? null : _recordPayment,
          icon: const Icon(Icons.payment),
          style: ElevatedButton.styleFrom(backgroundColor: kSuccessGreen, foregroundColor: Colors.white),
          label: const Text('Record Payment'),
        ),
      );
    }
    return const SizedBox.shrink();
  }
}
