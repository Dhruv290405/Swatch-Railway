import 'package:crm_train/model/contracts_model.dart';
import 'package:crm_train/services/api_services.dart';
import 'package:crm_train/utills/app_colors.dart';
import 'package:crm_train/model/billing_models.dart';
import 'package:flutter/material.dart';

class ContractBillingConfigScreen extends StatefulWidget {
  const ContractBillingConfigScreen({super.key});

  @override
  State<ContractBillingConfigScreen> createState() => _ContractBillingConfigScreenState();
}

class _ContractBillingConfigScreenState extends State<ContractBillingConfigScreen> {
  List<ContractBillingRule> configs = [];
  List<ContractModel> contracts = [];
  bool isLoading = true;
  String? loadError;

  static const _monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() { isLoading = true; loadError = null; });
    try {
      final results = await Future.wait([
        ApiService.getAllBillingConfigs(),
        ApiService.getActiveContracts(),
      ]);
      if (mounted) {
        setState(() {
          configs = results[0] as List<ContractBillingRule>;
          // These rules (coach / premise / OBHS weightages) apply to OBHS contracts only. Contracts with no
          // type are older OBHS contracts, so they stay in the list.
          contracts = (results[1] as List<ContractModel>)
              .where((c) => c.contractType != 'station_cleaning' && c.contractType != 'mcc')
              .toList();
          isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          isLoading = false;
          loadError = e.toString().replaceAll('Exception: ', '');
        });
      }
    }
  }

  void _snack(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), backgroundColor: color));
  }

  ContractBillingRule? _findConfig(String contractId) {
    try {
      return configs.firstWhere((c) => c.contractId == contractId);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Billing Configuration', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: kRailwayBlue,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(icon: const Icon(Icons.auto_mode), onPressed: _generateMissing, tooltip: 'Generate all missing monthly bills'),
          IconButton(icon: const Icon(Icons.add), onPressed: () => _showConfigDialog(), tooltip: 'Add New Configuration'),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadData, tooltip: 'Refresh'),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : loadError != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.error_outline, size: 48, color: Colors.red.shade300),
                  const SizedBox(height: 12),
                  Text('Could not load billing configurations', style: TextStyle(fontSize: 16, color: Colors.grey.shade700)),
                  const SizedBox(height: 6),
                  Text(loadError!, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(onPressed: _loadData, icon: const Icon(Icons.refresh), label: const Text('Retry')),
                ]),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text('Contract Billing Rules', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text('Configure billing rules and penalties for each contract', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                const SizedBox(height: 16),
                ...configs.map((c) => _buildContractCard(c)),
                if (configs.isEmpty)
                  Center(child: Column(children: [
                    const SizedBox(height: 40),
                    Icon(Icons.info_outline, size: 48, color: Colors.grey.shade300),
                    const SizedBox(height: 12),
                    Text('No billing configurations yet', style: TextStyle(fontSize: 16, color: Colors.grey.shade500)),
                    const SizedBox(height: 8),
                    ElevatedButton(onPressed: () => _showConfigDialog(), child: const Text('Add Configuration')),
                  ])),
              ],
            ),
    );
  }

  Widget _buildContractCard(ContractBillingRule config) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 1,
      child: ExpansionTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: kRailwayBlue.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
          child: const Icon(Icons.receipt_long, color: kRailwayBlue),
        ),
        title: Text(config.contractNumber, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: Text('${config.entityName} • ₹${_formatAmount(config.contractValue)}', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _infoRow('Division', config.division),
                _infoRow('Billing Cycle', config.billingCycle),
                _infoRow('Status', config.status),
                const Divider(),
                const Text('Score Weightages', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 4),
                _weightageBar('Coach Cleaning', config.coachWeightage, Colors.blue),
                _weightageBar('Premise Cleaning', config.premiseWeightage, Colors.green),
                _weightageBar('OBHS', config.obhsWeightage, Colors.orange),
                _weightageBar('Passenger Feedback', config.passengerFeedbackWeightage, Colors.purple),
                _weightageBar('AI Verification', config.aiVerificationWeightage, Colors.teal),
                const Divider(),
                const Text('Performance Deduction Rules', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 4),
                _penaltyRule('Score ≥ 90', '${config.penaltyScore90Plus}%'),
                _penaltyRule('Score 80 - 89', '${config.penaltyScore80To89}%'),
                _penaltyRule('Score 70 - 79', '${config.penaltyScore70To79}%'),
                _penaltyRule('Score < 70', '${config.penaltyScoreBelow70}%'),
                const Divider(),
                const Text('Additional Penalties', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 4),
                _penaltyRule('Manpower Shortage', '₹${config.manpowerShortagePenalty.toInt()}'),
                _penaltyRule('Machine Shortage', '₹${config.machineShortagePenalty.toInt()}'),
                _penaltyRule('Missed OBHS Complaint', '₹${config.missedObhsComplaintPenalty.toInt()}'),
                _penaltyRule('Late Task Completion', '₹${config.lateTaskCompletionPenalty.toInt()}'),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _showConfigDialog(existing: config),
                        icon: const Icon(Icons.edit, size: 16),
                        label: const Text('Edit'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _generateBill(config),
                        icon: const Icon(Icons.calculate, size: 16),
                        label: const Text('Generate Bill'),
                        style: ElevatedButton.styleFrom(backgroundColor: kRailwayBlue, foregroundColor: Colors.white),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _generateBill(ContractBillingRule config) async {
    final now = DateTime.now();
    final lastMonth = DateTime(now.year, now.month - 1, 1);
    int month = lastMonth.month;
    int year = lastMonth.year;
    final years = [for (var y = now.year; y >= now.year - 3; y--) y];

    final picked = await showDialog<List<int>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Generate Monthly Bill'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(config.contractNumber, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                value: month,
                decoration: const InputDecoration(labelText: 'Month', border: OutlineInputBorder(), isDense: true),
                items: [for (var i = 1; i <= 12; i++) DropdownMenuItem(value: i, child: Text(_monthNames[i - 1]))],
                onChanged: (v) => setDialogState(() => month = v ?? month),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<int>(
                value: year,
                decoration: const InputDecoration(labelText: 'Year', border: OutlineInputBorder(), isDense: true),
                items: [for (final y in years) DropdownMenuItem(value: y, child: Text('$y'))],
                onChanged: (v) => setDialogState(() => year = v ?? year),
              ),
              const SizedBox(height: 10),
              Text(
                "The score and deductions are calculated from that month's approved forms and this contract's billing rules.",
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, [month, year]), child: const Text('Generate')),
          ],
        ),
      ),
    );
    if (picked == null) return;

    final isFuture = DateTime(picked[1], picked[0], 1).isAfter(DateTime(now.year, now.month, 1));
    if (isFuture) {
      _snack('Choose a month that has already started.', Colors.orange);
      return;
    }
    try {
      final res = await ApiService.generateBill(contractId: config.contractId, month: picked[0], year: picked[1]);
      final label = '${_monthNames[picked[0] - 1]} ${picked[1]}';
      if (res['existing'] == true) {
        _snack('A bill for $label already exists.', Colors.orange);
      } else {
        _snack('Bill generated for $label.', Colors.green);
      }
    } catch (e) {
      _snack('Error: ${e.toString().replaceAll('Exception: ', '')}', Colors.red);
    }
  }

  Future<void> _generateMissing() async {
    try {
      final res = await ApiService.generateMissingMonthlyBills();
      final n = (res['generated'] ?? 0) as num;
      _snack(n == 0 ? 'All monthly bills are already up to date.' : '${n.toInt()} monthly bill(s) generated.', Colors.green);
    } catch (e) {
      _snack('Error: ${e.toString().replaceAll('Exception: ', '')}', Colors.red);
    }
  }

  void _showConfigDialog({ContractBillingRule? existing}) {
    final contractIdCtrl = TextEditingController(text: existing?.contractId ?? '');
    final contractNumCtrl = TextEditingController(text: existing?.contractNumber ?? '');
    final entityNameCtrl = TextEditingController(text: existing?.entityName ?? '');
    final divCtrl = TextEditingController(text: existing?.division ?? '');
    final zoneCtrl = TextEditingController(text: existing?.zone ?? '');
    final valCtrl = TextEditingController(text: existing?.contractValue.toString() ?? '');
    final coachWtCtrl = TextEditingController(text: existing?.coachWeightage.toString() ?? '35');
    final premiseWtCtrl = TextEditingController(text: existing?.premiseWeightage.toString() ?? '35');
    final obhsWtCtrl = TextEditingController(text: existing?.obhsWeightage.toString() ?? '15');
    final fbWtCtrl = TextEditingController(text: existing?.passengerFeedbackWeightage.toString() ?? '10');
    final aiWtCtrl = TextEditingController(text: existing?.aiVerificationWeightage.toString() ?? '5');
    final p90Ctrl = TextEditingController(text: existing?.penaltyScore90Plus.toString() ?? '0');
    final p89Ctrl = TextEditingController(text: existing?.penaltyScore80To89.toString() ?? '2');
    final p79Ctrl = TextEditingController(text: existing?.penaltyScore70To79.toString() ?? '5');
    final p70Ctrl = TextEditingController(text: existing?.penaltyScoreBelow70.toString() ?? '10');
    final mpCtrl = TextEditingController(text: existing?.manpowerShortagePenalty.toString() ?? '500');
    final mcCtrl = TextEditingController(text: existing?.machineShortagePenalty.toString() ?? '1000');
    final obCtrl = TextEditingController(text: existing?.missedObhsComplaintPenalty.toString() ?? '2000');
    final ltCtrl = TextEditingController(text: existing?.lateTaskCompletionPenalty.toString() ?? '500');
    final ncCtrl = TextEditingController(text: existing?.nonCompliancePenalty.toString() ?? '1000');

    String? selectedContractId = existing?.contractId;
    String? selectedContractNum = existing?.contractNumber;
    String? selectedEntityId = existing?.entityId;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(existing != null ? 'Edit Billing Rules' : 'New Billing Configuration'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (existing == null)
                  DropdownButtonFormField<String>(
                    decoration: const InputDecoration(labelText: 'Active Contract', border: OutlineInputBorder()),
                    items: contracts.map((c) => DropdownMenuItem(value: c.uid, child: Text('${c.contractNumber} - ${c.contractName ?? ""}'))).toList(),
                    onChanged: (v) {
                      final c = contracts.firstWhere((c) => c.uid == v);
                      setDialogState(() {
                        selectedContractId = v;
                        selectedContractNum = c.contractNumber;
                        selectedEntityId = c.entityId;
                        contractIdCtrl.text = v!;
                        contractNumCtrl.text = c.contractNumber ?? '';
                        entityNameCtrl.text = c.entityName ?? c.contractName ?? '';
                        divCtrl.text = c.division ?? '';
                        zoneCtrl.text = c.zone ?? '';
                        // Pre-fill from the contract; it used to be cleared, so the value saved as 0 unless retyped.
                        valCtrl.text = c.contractValue > 0 ? c.contractValue.toStringAsFixed(0) : '';
                      });
                    },
                  ),
                const SizedBox(height: 12),
                TextFormField(controller: contractNumCtrl, decoration: const InputDecoration(labelText: 'Contract Number', border: OutlineInputBorder(), isDense: true), enabled: existing != null),
                const SizedBox(height: 8),
                TextFormField(controller: entityNameCtrl, decoration: const InputDecoration(labelText: 'Entity Name', border: OutlineInputBorder(), isDense: true), enabled: existing != null),
                const SizedBox(height: 8),
                TextFormField(controller: divCtrl, decoration: const InputDecoration(labelText: 'Division', border: OutlineInputBorder(), isDense: true), enabled: existing != null),
                const SizedBox(height: 8),
                TextFormField(controller: valCtrl, decoration: const InputDecoration(labelText: 'Contract Value (₹)', border: OutlineInputBorder(), isDense: true), keyboardType: TextInputType.number),
                const SizedBox(height: 16),
                const Text('Score Weightages', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                TextFormField(controller: coachWtCtrl, decoration: const InputDecoration(labelText: 'Coach Weightage (%)', border: OutlineInputBorder(), isDense: true), keyboardType: TextInputType.number),
                const SizedBox(height: 8),
                TextFormField(controller: premiseWtCtrl, decoration: const InputDecoration(labelText: 'Premise Weightage (%)', border: OutlineInputBorder(), isDense: true), keyboardType: TextInputType.number),
                const SizedBox(height: 8),
                TextFormField(controller: obhsWtCtrl, decoration: const InputDecoration(labelText: 'OBHS Weightage (%)', border: OutlineInputBorder(), isDense: true), keyboardType: TextInputType.number),
                const SizedBox(height: 16),
                const Text('Performance Deduction (%)', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                TextFormField(controller: p90Ctrl, decoration: const InputDecoration(labelText: 'Score ≥ 90 Deduction %', border: OutlineInputBorder(), isDense: true), keyboardType: TextInputType.number),
                const SizedBox(height: 8),
                TextFormField(controller: p89Ctrl, decoration: const InputDecoration(labelText: 'Score 80-89 Deduction %', border: OutlineInputBorder(), isDense: true), keyboardType: TextInputType.number),
                const SizedBox(height: 8),
                TextFormField(controller: p79Ctrl, decoration: const InputDecoration(labelText: 'Score 70-79 Deduction %', border: OutlineInputBorder(), isDense: true), keyboardType: TextInputType.number),
                const SizedBox(height: 8),
                TextFormField(controller: p70Ctrl, decoration: const InputDecoration(labelText: 'Score < 70 Deduction %', border: OutlineInputBorder(), isDense: true), keyboardType: TextInputType.number),
                const SizedBox(height: 16),
                const Text('Additional Penalties (₹)', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                TextFormField(controller: mpCtrl, decoration: const InputDecoration(labelText: 'Manpower Shortage (₹)', border: OutlineInputBorder(), isDense: true), keyboardType: TextInputType.number),
                const SizedBox(height: 8),
                TextFormField(controller: mcCtrl, decoration: const InputDecoration(labelText: 'Machine Shortage (₹)', border: OutlineInputBorder(), isDense: true), keyboardType: TextInputType.number),
                const SizedBox(height: 8),
                TextFormField(controller: obCtrl, decoration: const InputDecoration(labelText: 'Missed OBHS Complaint (₹)', border: OutlineInputBorder(), isDense: true), keyboardType: TextInputType.number),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                if (selectedContractId == null && existing == null) {
                  _snack('Select a contract first.', Colors.orange);
                  return;
                }
                final contractValue = double.tryParse(valCtrl.text.trim()) ?? 0;
                if (contractValue <= 0) {
                  _snack('Enter the contract value (it must be greater than 0).', Colors.orange);
                  return;
                }
                final weightTotal = (double.tryParse(coachWtCtrl.text) ?? 35) +
                    (double.tryParse(premiseWtCtrl.text) ?? 35) +
                    (double.tryParse(obhsWtCtrl.text) ?? 15) +
                    (double.tryParse(fbWtCtrl.text) ?? 10) +
                    (double.tryParse(aiWtCtrl.text) ?? 5);
                if ((weightTotal - 100).abs() > 0.01) {
                  _snack('Score weightages must total 100% (currently ${weightTotal.toStringAsFixed(0)}%).', Colors.orange);
                  return;
                }
                final bands = [p90Ctrl, p89Ctrl, p79Ctrl, p70Ctrl].map((c) => double.tryParse(c.text));
                if (bands.any((v) => v != null && (v < 0 || v > 100))) {
                  _snack('Deduction percentages must be between 0 and 100.', Colors.orange);
                  return;
                }
                Navigator.pop(ctx);
                try {
                  await ApiService.saveBillingConfig(
                    contractId: existing?.contractId ?? selectedContractId!,
                    contractNumber: contractNumCtrl.text,
                    entityId: existing?.entityId ?? selectedEntityId ?? '',
                    entityName: entityNameCtrl.text,
                    division: divCtrl.text,
                    zone: zoneCtrl.text,
                    contractValue: contractValue,
                    billingCycle: 'Monthly',
                    serviceTypes: [],
                    coachWeightage: double.tryParse(coachWtCtrl.text) ?? 35,
                    premiseWeightage: double.tryParse(premiseWtCtrl.text) ?? 35,
                    obhsWeightage: double.tryParse(obhsWtCtrl.text) ?? 15,
                    passengerFeedbackWeightage: double.tryParse(fbWtCtrl.text) ?? 10,
                    aiVerificationWeightage: double.tryParse(aiWtCtrl.text) ?? 5,
                    penaltyScore90Plus: double.tryParse(p90Ctrl.text) ?? 0,
                    penaltyScore80To89: double.tryParse(p89Ctrl.text) ?? 2,
                    penaltyScore70To79: double.tryParse(p79Ctrl.text) ?? 5,
                    penaltyScoreBelow70: double.tryParse(p70Ctrl.text) ?? 10,
                    manpowerShortagePenalty: double.tryParse(mpCtrl.text) ?? 500,
                    machineShortagePenalty: double.tryParse(mcCtrl.text) ?? 1000,
                    missedObhsComplaintPenalty: double.tryParse(obCtrl.text) ?? 2000,
                    lateTaskCompletionPenalty: double.tryParse(ltCtrl.text) ?? 500,
                    nonCompliancePenalty: double.tryParse(ncCtrl.text) ?? 1000,
                  );
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Configuration saved'), backgroundColor: Colors.green));
                  _loadData();
                } catch (e) {
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
                }
              },
              child: const Text('Save Configuration'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Row(
      children: [
        SizedBox(width: 100, child: Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600))),
        Expanded(child: Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500))),
      ],
    ));
  }

  Widget _weightageBar(String label, double pct, Color color) {
    return Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Row(
      children: [
        SizedBox(width: 130, child: Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade700))),
        Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(value: pct / 100, backgroundColor: Colors.grey.shade200, valueColor: AlwaysStoppedAnimation<Color>(color), minHeight: 8))),
        const SizedBox(width: 8),
        SizedBox(width: 35, child: Text('${pct.toInt()}%', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color))),
      ],
    ));
  }

  Widget _penaltyRule(String label, String value) {
    return Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Row(
      children: [
        Icon(Icons.circle, size: 6, color: Colors.grey.shade400),
        const SizedBox(width: 8),
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
        const Spacer(),
        Text(value, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.red.shade700)),
      ],
    ));
  }

  String _formatAmount(double amount) {
    if (amount >= 10000000) return '${(amount / 10000000).toStringAsFixed(2)}Cr';
    if (amount >= 100000) return '${(amount / 100000).toStringAsFixed(2)}L';
    if (amount >= 1000) return '${(amount / 1000).toStringAsFixed(1)}K';
    return amount.toStringAsFixed(0);
  }
}