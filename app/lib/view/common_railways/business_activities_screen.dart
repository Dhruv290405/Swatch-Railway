import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../providers/auth_provider.dart';
import '../../../services/api_services.dart';
import '../../../model/task_billing_models.dart';
import '../../../model/contracts_model.dart';
import '../../../repositories/task_billing_repository.dart';
import '../../../utills/app_colors.dart';

class BusinessActivitiesScreen extends StatefulWidget {
  const BusinessActivitiesScreen({super.key});

  @override
  State<BusinessActivitiesScreen> createState() => _BusinessActivitiesScreenState();
}

class _BusinessActivitiesScreenState extends State<BusinessActivitiesScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  bool _isLoading = true;
  String? _error;

  List<ContractModel> _contracts = [];
  DailyBillingMonth? _monthData;
  Map<String, dynamic> _billingSummary = {};
  Map<String, dynamic> _performanceDashboard = {};
  Map<String, dynamic> _areaWeightage = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final user = Provider.of<AuthProvider>(context, listen: false).currentUser;
      String stationId = '';
      if (user != null) {
        if (user.stationId != null && user.stationId!.isNotEmpty) {
          stationId = user.stationId!;
        } else if (user.stations != null && user.stations!.isNotEmpty) {
          stationId = user.stations!.first;
        }
      }

      final contracts = await ApiService.getStationContracts(
        stationId,
        contractType: 'station_cleaning',
      );

      if (contracts.isNotEmpty) {
        final contractId = contracts.first.uid;

        final futures = <Future>[
          TaskBillingRepository.list(contractId, stationId, DateTime.now().month, DateTime.now().year),
          ApiService.getBillingSummary(contractId),
          ApiService.getPerformanceBillingDashboard(),
          ApiService.getAreaWeightageConfig(contractId),
        ];

        final results = await Future.wait(futures);

        if (mounted) {
          setState(() {
            _contracts = contracts;
            _monthData = results[0] as DailyBillingMonth;
            _billingSummary = results[1] as Map<String, dynamic>;
            _performanceDashboard = results[2] as Map<String, dynamic>;
            _areaWeightage = results[3] as Map<String, dynamic>;
            _isLoading = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _error = 'No station cleaning contract found for this station';
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load data: $e';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Business Activities', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: kRailwayBlue,
        iconTheme: const IconThemeData(color: Colors.white),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(text: 'Overview'),
            Tab(text: 'Daily Billing'),
            Tab(text: 'Area Weightage'),
            Tab(text: 'Performance'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline, size: 48, color: Colors.grey),
                      const SizedBox(height: 12),
                      Text(_error!, style: const TextStyle(color: Colors.grey)),
                      const SizedBox(height: 12),
                      ElevatedButton(onPressed: _loadData, child: const Text('Retry')),
                    ],
                  ),
                )
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildOverviewTab(),
                    _buildDailyBillingTab(),
                    _buildAreaWeightageTab(),
                    _buildPerformanceTab(),
                  ],
                ),
    );
  }

  Widget _buildOverviewTab() {
    final totalBilled = _monthData?.totalNetAmount ?? 0;
    final totalCollected = _billingSummary['totalCollected'] ?? 0;
    final pending = _billingSummary['pending'] ?? 0;
    final contractCount = _contracts.length;

    return RefreshIndicator(
      onRefresh: _loadData,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildStatCard('Total Billed', NumberFormat.currency(locale: 'en_IN', symbol: '₹').format(totalBilled), Colors.blue),
            const SizedBox(height: 12),
            _buildStatCard('Total Collected', NumberFormat.currency(locale: 'en_IN', symbol: '₹').format(totalCollected), Colors.green),
            const SizedBox(height: 12),
            _buildStatCard('Pending Collection', NumberFormat.currency(locale: 'en_IN', symbol: '₹').format(pending), Colors.orange),
            const SizedBox(height: 12),
            _buildStatCard('Active Contracts', contractCount.toString(), Colors.purple),
            const SizedBox(height: 24),
            const Text('Recent Daily Bills', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
if (_monthData?.bills.isEmpty ?? true)
              Center(child: const Text('No daily bills generated yet'))
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: (_monthData?.bills.length ?? 0) > 5 ? 5 : (_monthData?.bills.length ?? 0),
                itemBuilder: (context, index) {
                  final bill = _monthData!.bills[index];
                  return Card(
                    child: ListTile(
                      leading: const Icon(Icons.receipt_long, color: kRailwayBlue),
                      title: Text(bill.date, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text('Net: ${NumberFormat.currency(locale: 'en_IN', symbol: '₹').format(bill.netAmount)}'),
                      trailing: Text(bill.status, style: TextStyle(color: bill.status == 'APPROVED' ? Colors.green : Colors.orange)),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDailyBillingTab() {
    final bills = _monthData?.bills ?? [];
    return RefreshIndicator(
      onRefresh: _loadData,
      child: bills.isEmpty
          ? const Center(child: Text('No daily bills generated yet. Generate bills from Daily Task Billing screen.'))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: bills.length,
              itemBuilder: (context, index) {
                final bill = bills[index];
return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ExpansionTile(
                    leading: const Icon(Icons.receipt_long, color: kRailwayBlue),
                    title: Text(bill.date, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text('Status: ${bill.status}'),
                    trailing: Text(NumberFormat.currency(locale: 'en_IN', symbol: '₹').format(bill.netAmount), style: const TextStyle(fontWeight: FontWeight.bold, color: kSuccessGreen)),
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildDetailRow('Gross Amount', NumberFormat.currency(locale: 'en_IN', symbol: '₹').format(bill.grossAmount)),
                            _buildDetailRow('Deductions', NumberFormat.currency(locale: 'en_IN', symbol: '₹').format(bill.deduction)),
                            _buildDetailRow('GST', NumberFormat.currency(locale: 'en_IN', symbol: '₹').format(bill.gstAmount)),
                            _buildDetailRow('Net Amount', NumberFormat.currency(locale: 'en_IN', symbol: '₹').format(bill.netAmount), isBold: true),
                            const SizedBox(height: 12),
                            const Text('Category Breakdown', style: TextStyle(fontWeight: FontWeight.bold)),
                            const SizedBox(height: 8),
                            ...bill.categories.map((c) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text('${c['name'] ?? c['category'] ?? 'Category'}'),
                                  Text(NumberFormat.currency(locale: 'en_IN', symbol: '₹').format((c['amount'] as num?)?.toDouble() ?? 0)),
                                ],
                              ),
                            )).toList(),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          );
  }

Widget _buildAreaWeightageTab() {
    return RefreshIndicator(
      onRefresh: _loadData,
      child: (_areaWeightage.isEmpty)
          ? const Center(child: Text('No area weightage configuration found. Configure from Area Rate Config screen.'))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: _areaWeightage.entries.map((entry) {
                final area = entry.key;
                final config = entry.value as Map<String, dynamic>;
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ExpansionTile(
                    leading: const Icon(Icons.area_chart, color: kRailwayBlue),
                    title: Text(area, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text('Weightage: ${config['weightage'] ?? 'N/A'}%'),
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildDetailRow('Weightage %', '${config['weightage'] ?? 'N/A'}%'),
                            _buildDetailRow('Rate/SqM', NumberFormat.currency(locale: 'en_IN', symbol: '₹').format(config['ratePerSqM'] ?? 0)),
                            _buildDetailRow('Min Area', '${config['minArea'] ?? 'N/A'} sqm'),
                            _buildDetailRow('Max Area', '${config['maxArea'] ?? 'N/A'} sqm'),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          );
  }

  Widget _buildPerformanceTab() {
    return RefreshIndicator(
      onRefresh: _loadData,
      child: (_performanceDashboard.isEmpty)
          ? const Center(child: Text('No performance billing data available. Configure from Performance Billing screen.'))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: _performanceDashboard.entries.map((entry) {
                final metric = entry.key;
                final value = entry.value;
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    leading: const Icon(Icons.assessment, color: kRailwayBlue),
                    title: Text(metric, style: const TextStyle(fontWeight: FontWeight.bold)),
                    trailing: Text(value.toString(), style: const TextStyle(fontWeight: FontWeight.bold, color: kRailwayBlue)),
                  ),
                );
              }).toList(),
            ),
          );
  }

  Widget _buildStatCard(String label, String value, Color color) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 14, color: color, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontWeight: isBold ? FontWeight.bold : FontWeight.normal)),
          Text(value, style: TextStyle(fontWeight: isBold ? FontWeight.bold : FontWeight.normal)),
        ],
      ),
    );
  }
}