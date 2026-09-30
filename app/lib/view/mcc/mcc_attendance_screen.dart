import 'package:flutter/material.dart';
import 'package:crm_train/model/user_model.dart';
import 'package:crm_train/utills/app_colors.dart';
import 'package:crm_train/repositories/mcc_repository.dart';

class MccAttendanceScreen extends StatefulWidget {
  final UserModel user;
  const MccAttendanceScreen({super.key, required this.user});
  @override
  State<MccAttendanceScreen> createState() => _MccAttendanceScreenState();
}

class _MccAttendanceScreenState extends State<MccAttendanceScreen> {
  bool _loading = true;
  bool _isStartMarked = false;
  bool _isMidMarked = false;
  bool _isEndMarked = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchStatus();
  }

  Future<void> _fetchStatus() async {
    setState(() => _loading = true);
    try {
      final resp = await MccRepository.getAttendanceStatus();
      _isStartMarked = resp['isStartMarked'] ?? false;
      _isMidMarked = resp['isMidMarked'] ?? false;
      _isEndMarked = resp['isEndMarked'] ?? false;
      _error = null;
    } catch (e) {
      _error = e.toString();
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _mark(String type) async {
    final photoCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${type.toUpperCase()} Attendance'),
        content: TextField(
          controller: photoCtrl,
          decoration: const InputDecoration(labelText: 'Face photo URL'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Submit')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await MccRepository.markAttendance({
        'attendanceType': type,
        'imageUrl': photoCtrl.text.trim().isEmpty ? null : photoCtrl.text.trim(),
      });
      _fetchStatus();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Depot Attendance',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20)),
        backgroundColor: kRailwayBlue,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildError()
              : RefreshIndicator(
                  onRefresh: _fetchStatus,
                  child: ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      const SizedBox(height: 10),
                      const Center(
                        child: Icon(Icons.fingerprint, size: 72, color: kRailwayBlue),
                      ),
                      const SizedBox(height: 12),
                      const Center(
                        child: Text('Mark your depot attendance',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(height: 6),
                      Center(
                        child: Text(widget.user.fullName,
                            style: TextStyle(color: Colors.grey[600])),
                      ),
                      const SizedBox(height: 24),
                      _buildAttendanceCard('Start', _isStartMarked, () => _mark('start')),
                      const SizedBox(height: 14),
                      _buildAttendanceCard('Mid', _isMidMarked, () => _mark('mid')),
                      const SizedBox(height: 14),
                      _buildAttendanceCard('End', _isEndMarked, () => _mark('end')),
                    ],
                  ),
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
        ElevatedButton(onPressed: _fetchStatus, child: const Text('Retry')),
      ],
    );
  }

  Widget _buildAttendanceCard(String label, bool marked, VoidCallback onTap) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Row(
        children: [
          Icon(
            marked ? Icons.check_circle : Icons.radio_button_unchecked,
            color: marked ? Colors.green : Colors.grey[400],
            size: 32,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text('$label Attendance',
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
          ),
          marked
              ? const Chip(
                  label: Text('Done'),
                  labelStyle: TextStyle(color: Colors.white, fontSize: 12),
                  backgroundColor: Colors.green,
                )
              : ElevatedButton(
                  onPressed: marked ? null : onTap,
                  style: ElevatedButton.styleFrom(
                      backgroundColor: kRailwayBlue, disabledBackgroundColor: Colors.grey[300]),
                  child: const Text('Mark', style: TextStyle(color: Colors.white)),
                ),
        ],
      ),
    );
  }
}