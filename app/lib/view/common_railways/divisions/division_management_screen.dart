import 'package:flutter/material.dart';
import '../../../data/zone_database.dart';
import '../../../services/api_services.dart';
import '../../../utills/app_colors.dart';

class DivisionManagementScreen extends StatefulWidget {
  const DivisionManagementScreen({super.key});

  @override
  State<DivisionManagementScreen> createState() => _DivisionManagementScreenState();
}

class _DivisionManagementScreenState extends State<DivisionManagementScreen> {
  List<Map<String, dynamic>> _divisions = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadDivisions();
  }

  Future<void> _loadDivisions() async {
    setState(() => _isLoading = true);
    try {
      _divisions = await ApiService.getDivisions();
    } catch (e) {
      //
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _showCreateEditDialog({Map<String, dynamic>? division}) async {
    final nameController = TextEditingController(text: division?['name'] ?? '');
    final codeController = TextEditingController(text: division?['code'] ?? '');
    String selectedZone = division?['zone'] ?? (DepotDatabase.zoneData.keys.isNotEmpty ? DepotDatabase.zoneData.keys.first : '');
    final isEdit = division != null;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(isEdit ? 'Edit Division' : 'Create Division'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: selectedZone,
                  decoration: const InputDecoration(labelText: 'Zone', border: OutlineInputBorder()),
                  items: DepotDatabase.zoneData.keys.map((z) => DropdownMenuItem(value: z, child: Text(z))).toList(),
                  onChanged: (v) => setDialogState(() => selectedZone = v ?? selectedZone),
                ),
                const SizedBox(height: 12),
                TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Division Name', border: OutlineInputBorder())),
                const SizedBox(height: 12),
                TextField(controller: codeController, decoration: const InputDecoration(labelText: 'Code (optional)', border: OutlineInputBorder())),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                if (nameController.text.trim().isEmpty) return;
                try {
                  if (isEdit) {
                    final id = division['divisionId'] as String?;
                    if (id == null || id.isEmpty) {
                      throw Exception('Division id missing');
                    }
                    await ApiService.updateDivision(id, name: nameController.text.trim(), zone: selectedZone, code: codeController.text.trim());
                  } else {
                    await ApiService.createDivision(nameController.text.trim(), selectedZone, code: codeController.text.trim());
                  }
                  Navigator.pop(ctx, true);
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: Colors.red));
                }
              },
              child: Text(isEdit ? 'Update' : 'Create'),
            ),
          ],
        ),
      ),
    );
    if (result == true) _loadDivisions();
  }

  Future<void> _deleteDivision(Map<String, dynamic> division) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Division'),
        content: Text('Delete "${division['name']}"? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final id = division['divisionId'] as String?;
      if (id == null || id.isEmpty) {
        throw Exception('Division id missing');
      }
      await ApiService.deleteDivision(id);
      _loadDivisions();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FC),
      appBar: AppBar(
        title: const Text('Division Management'),
        backgroundColor: kRailwayBlue,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(icon: const Icon(Icons.add), onPressed: () => _showCreateEditDialog()),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _divisions.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.map_outlined, size: 64, color: Colors.grey),
                      const SizedBox(height: 16),
                      const Text('No divisions found', style: TextStyle(fontSize: 16, color: Colors.grey)),
                      const SizedBox(height: 8),
                      ElevatedButton.icon(
                        onPressed: () => _showCreateEditDialog(),
                        icon: const Icon(Icons.add),
                        label: const Text('Add Division'),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadDivisions,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _divisions.length,
                    itemBuilder: (context, index) {
                      final div = _divisions[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: kRailwayBlue.withOpacity(0.1),
                            child: Text(div['code'] ?? div['name']?.substring(0, 2).toUpperCase() ?? '?',
                                style: const TextStyle(fontWeight: FontWeight.bold, color: kRailwayBlue)),
                          ),
                          title: Text(div['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text('Zone: ${div['zone'] ?? 'N/A'}  |  Code: ${div['code'] ?? 'N/A'}'),
                          trailing: PopupMenuButton<String>(
                            onSelected: (v) {
                              if (v == 'edit') _showCreateEditDialog(division: div);
                              if (v == 'delete') _deleteDivision(div);
                            },
                            itemBuilder: (_) => [
                              const PopupMenuItem(value: 'edit', child: Row(children: [Icon(Icons.edit, size: 18), SizedBox(width: 8), Text('Edit')])),
                              const PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete, size: 18, color: Colors.red), SizedBox(width: 8), Text('Delete', style: TextStyle(color: Colors.red))])),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}