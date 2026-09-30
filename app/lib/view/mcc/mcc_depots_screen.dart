import 'package:flutter/material.dart';
import 'package:crm_train/utills/app_colors.dart';
import 'package:crm_train/repositories/mcc_repository.dart';

class MccDepotsScreen extends StatefulWidget {
  const MccDepotsScreen({super.key});
  @override
  State<MccDepotsScreen> createState() => _MccDepotsScreenState();
}

class _MccDepotsScreenState extends State<MccDepotsScreen> {
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
      final resp = await MccRepository.getDepots();
      _depots = List<Map<String, dynamic>>.from((resp['depots'] ?? []) as List);
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
        title: const Text('Washing Depots',
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
                : _depots.isEmpty
                    ? _buildEmpty()
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _depots.length,
                        itemBuilder: (_, i) => _buildDepotCard(_depots[i]),
                      ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateSheet,
        backgroundColor: kRailwayBlue,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Add Depot', style: TextStyle(color: Colors.white)),
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
        Icon(Icons.factory_outlined, size: 80, color: Colors.grey[300]),
        const SizedBox(height: 16),
        const Text('No depots yet.',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.black54),
            textAlign: TextAlign.center),
        const SizedBox(height: 8),
        Text('Add a washing-plant depot to start scheduling runs.',
            style: TextStyle(color: Colors.grey[500]), textAlign: TextAlign.center),
      ],
    );
  }

  Widget _buildDepotCard(Map<String, dynamic> depot) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: kRailwayBlue.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.factory_outlined, color: kRailwayBlue, size: 32),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(depot['name'] ?? 'Depot', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text('${depot['stationName'] ?? ''}',
                    style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                Text(
                    'Capacity: ${depot['capacity'] ?? 0} coaches · Machines: ${depot['machines'] ?? 0}',
                    style: TextStyle(color: Colors.grey[600], fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showCreateSheet() {
    final nameCtrl = TextEditingController();
    final stationCtrl = TextEditingController();
    final capacityCtrl = TextEditingController();
    final machinesCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
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
                const Text('Add Washing Depot',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                TextFormField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Depot Name'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: stationCtrl,
                  decoration: const InputDecoration(labelText: 'Station Name'),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: capacityCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Coach Capacity'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: machinesCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'No. of Machines'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () async {
                      if (!formKey.currentState!.validate()) return;
                      try {
                        await MccRepository.createDepot({
                          'name': nameCtrl.text.trim(),
                          'stationName': stationCtrl.text.trim(),
                          'capacity': int.tryParse(capacityCtrl.text.trim()) ?? 0,
                          'machines': int.tryParse(machinesCtrl.text.trim()) ?? 0,
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
                    child: const Text('Create Depot', style: TextStyle(color: Colors.white)),
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