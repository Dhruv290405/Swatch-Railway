import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../utills/app_colors.dart';
import 'package:provider/provider.dart';
import 'package:crm_train/providers/auth_provider.dart';
import '../../services/api_services.dart';
class WorkerAuditScreen extends StatefulWidget {
  const WorkerAuditScreen({super.key});

  @override
  State<WorkerAuditScreen> createState() => _WorkerAuditScreenState();
}

class _WorkerAuditScreenState extends State<WorkerAuditScreen> {
  bool _isLoading = false;
  List _logs = [];
  String? _error;
  String _selectedType = 'All';

  final _types = ['All', 'Attendance', 'Task', 'Cleaning', 'Complaint', 'Feedback', 'Pest Control', 'Garbage', 'Machine', 'Escalation'];

  Future<String?> _getAuthToken() async {
    final authProvider = context.read<AuthProvider>();
    if (authProvider.token != null) return authProvider.token;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('auth_token') ?? prefs.getString('token');
  }

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  Future<void> _loadLogs() async {
    setState(() { _isLoading = true; _error = null; });
    try {
      final token = await _getAuthToken();
      if (token == null) {
        setState(() { _logs = []; _isLoading = false; });
        return;
      }
      String url = '${ApiService.baseUrl}/api/audit-logs';
      if (_selectedType != 'All') {
        url += '?type=${Uri.encodeComponent(_selectedType)}';
      }
      final resp = await http.get(
        Uri.parse(url),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (mounted) {
        if (resp.statusCode == 200) {
          final data = json.decode(resp.body);
          setState(() { _logs = data['data'] ?? []; _isLoading = false; });
        } else {
          setState(() { _error = 'Failed to load: ${resp.statusCode}'; _isLoading = false; });
        }
      }
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _isLoading = false; });
    }
  }

  IconData _iconFor(String type) {
    switch (type) {
      case 'Attendance': return Icons.fact_check;
      case 'Task': return Icons.task_alt;
      case 'Cleaning': return Icons.cleaning_services;
      case 'Complaint': return Icons.report_problem;
      case 'Feedback': return Icons.feedback;
      case 'Pest Control': return Icons.bug_report;
      case 'Garbage': return Icons.delete;
      case 'Machine': return Icons.precision_manufacturing;
      case 'Escalation': return Icons.warning_amber_rounded;
      default: return Icons.history;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Audit Trail', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.brown[700],
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            color: Colors.white,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _types.map((t) => Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(t),
                    selected: _selectedType == t,
                    onSelected: (v) => setState(() { _selectedType = t; _loadLogs(); }),
                    selectedColor: kRailwayBlue,
                    labelStyle: TextStyle(color: _selectedType == t ? Colors.white : Colors.black87),
                  ),
                )).toList(),
              ),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _logs.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.history, size: 80, color: Colors.grey[300]),
                            const SizedBox(height: 16),
                            const Text('No audit logs yet', style: TextStyle(color: Colors.grey, fontSize: 16)),
                            const Text('Your activity history will appear here', style: TextStyle(color: Colors.grey)),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: _logs.length,
                        itemBuilder: (context, index) {
                          final log = _logs[index];
                          return Card(
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: kRailwayBlue.withValues(alpha: 0.1),
                                child: Icon(_iconFor(log['type'] ?? ''), color: kRailwayBlue),
                              ),
                              title: Text(log['action'] ?? 'Activity'),
                              subtitle: Text(log['timestamp'] ?? ''),
                              trailing: Icon(Icons.chevron_right, color: Colors.grey[400]),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}