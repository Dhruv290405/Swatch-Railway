import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:crm_train/model/station_cleaning_models.dart';
import 'package:crm_train/repositories/station_cleaning_repository.dart';
import 'package:crm_train/utills/app_colors.dart';
import 'package:crm_train/utills/validators.dart';
import 'package:crm_train/repositories/worker_repo.dart';

class WorkerManagementScreen extends StatefulWidget {
  final String stationId;
  final String stationName;

  const WorkerManagementScreen({
    super.key,
    required this.stationId,
    required this.stationName,
  });

  @override
  State<WorkerManagementScreen> createState() => _WorkerManagementScreenState();
}

class _WorkerManagementScreenState extends State<WorkerManagementScreen> {
  bool _isLoading = true;
  List<SupervisorWorker> _workers = [];

  @override
  void initState() {
    super.initState();
    _loadWorkers();
  }

  Future<void> _loadWorkers() async {
    setState(() => _isLoading = true);
    try {
      final result = await StationCleaningRepository.listWorkers(stationId: widget.stationId);
      final list = (result['workers'] as List?) ?? [];
      setState(() {
        _workers = list.map((e) => SupervisorWorker.fromJson(e is Map<String, dynamic> ? e : {})).toList();
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: kErrorRed));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Text('Workers - ${widget.stationName}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: kRailwayBlue,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(icon: const Icon(Icons.refresh, color: Colors.white), onPressed: _loadWorkers),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: kRailwayBlue,
        child: const Icon(Icons.person_add, color: Colors.white),
        onPressed: () => _openWorkerForm(context),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _workers.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.people_outline, size: 80, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text('No workers created yet', style: TextStyle(fontSize: 16, color: Colors.grey[600])),
                      const SizedBox(height: 8),
                      ElevatedButton.icon(
                        onPressed: () => _openWorkerForm(context),
                        icon: const Icon(Icons.person_add),
                        label: const Text('Add Worker'),
                        style: ElevatedButton.styleFrom(backgroundColor: kRailwayBlue, foregroundColor: Colors.white),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadWorkers,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _workers.length,
                    itemBuilder: (context, index) {
                      final w = _workers[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: kRailwayBlue.withValues(alpha: 0.15),
                            child: w.employeePhotoUrl.isNotEmpty
                                ? ClipOval(child: Image.network(w.employeePhotoUrl, width: 40, height: 40, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Icon(Icons.person, color: kRailwayBlue)))
                                : Icon(Icons.person, color: kRailwayBlue),
                          ),
                          title: Text(w.fullName, style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text('${w.phone}\nAadhaar: ${w.aadhaarNumber.isNotEmpty ? '${w.aadhaarNumber.substring(0, 4)}XXXX' : 'N/A'}'),
                          trailing: PopupMenuButton<String>(
                            onSelected: (v) {
                              if (v == 'edit') _openWorkerForm(context, worker: w);
                              if (v == 'delete') _confirmDelete(w);
                              if (v == 'shift') _reassignShift(w);
                            },
                            itemBuilder: (_) => [
                              const PopupMenuItem(value: 'shift', child: ListTile(leading: Icon(Icons.published_with_changes), title: Text('Reassign Shift'))),
                              const PopupMenuItem(value: 'edit', child: ListTile(leading: Icon(Icons.edit), title: Text('Edit'))),
                              const PopupMenuItem(value: 'delete', child: ListTile(leading: Icon(Icons.delete, color: kErrorRed), title: Text('Delete'))),
                            ],
                          ),
                          onTap: () => _openWorkerForm(context, worker: w),
                        ),
                      );
                    },
                  ),
                ),
    );
  }

  Future<void> _confirmDelete(SupervisorWorker w) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Worker'),
        content: Text('Remove ${w.fullName}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete', style: TextStyle(color: kErrorRed))),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await StationCleaningRepository.deleteWorker(w.uid);
        _loadWorkers();
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Worker deleted'), backgroundColor: kSuccessGreen));
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: kErrorRed));
      }
    }
  }

  void _openWorkerForm(BuildContext context, {SupervisorWorker? worker}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _WorkerFormDialog(
        stationId: widget.stationId,
        worker: worker,
        onSaved: _loadWorkers,
      ),
    );
  }

  Future<void> _reassignShift(SupervisorWorker w) async {
    String? selected = 'morning';
    final chosen = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocalState) => AlertDialog(
          title: const Text('Reassign Shift'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Select a new shift for ${w.fullName}'),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: selected,
                decoration: const InputDecoration(labelText: 'Shift', border: OutlineInputBorder()),
                items: ['morning', 'afternoon', 'night']
                    .map((s) => DropdownMenuItem(value: s, child: Text(s[0].toUpperCase() + s.substring(1))))
                    .toList(),
                onChanged: (v) { if (v != null) selected = v; },
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(ctx, selected), child: const Text('Save', style: TextStyle(color: kRailwayBlue))),
          ],
        ),
      ),
    );
    if (chosen == null || !mounted) return;
    try {
      await StationCleaningRepository.reassignWorkerShift(workerId: w.uid, shiftType: chosen);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Shift reassigned to ${chosen[0].toUpperCase()}${chosen.substring(1)} for ${w.fullName}'), backgroundColor: kSuccessGreen),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: kErrorRed));
      }
    }
  }
}

class _WorkerFormDialog extends StatefulWidget {
  final String stationId;
  final SupervisorWorker? worker;
  final VoidCallback onSaved;

  const _WorkerFormDialog({required this.stationId, this.worker, required this.onSaved});

  @override
  State<_WorkerFormDialog> createState() => _WorkerFormDialogState();
}

class _WorkerFormDialogState extends State<_WorkerFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameCtrl;
  late TextEditingController _phoneCtrl;
  late TextEditingController _aadhaarCtrl;
  late TextEditingController _panCtrl;
  late TextEditingController _pfCtrl;
  late TextEditingController _policeCtrl;
  bool _submitting = false;

  String? _employeePhotoUrl;
  String? _aadhaarPhotoUrl;
  String? _panPhotoUrl;
  String? _pfDocUrl;
  String? _policeDocUrl;

  @override
  void initState() {
    super.initState();
    final w = widget.worker;
    _nameCtrl = TextEditingController(text: w?.fullName ?? '');
    _phoneCtrl = TextEditingController(text: w?.phone ?? '');
    _aadhaarCtrl = TextEditingController(text: w?.aadhaarNumber ?? '');
    _panCtrl = TextEditingController(text: w?.panNumber ?? '');
    _pfCtrl = TextEditingController(text: w?.pfUanNumber ?? '');
    _policeCtrl = TextEditingController(text: w?.policeVerificationNumber ?? '');
    _employeePhotoUrl = w?.employeePhotoUrl;
    _aadhaarPhotoUrl = w?.aadhaarPhotoUrl;
    _panPhotoUrl = w?.panPhotoUrl;
    _pfDocUrl = w?.pfDocumentUrl;
    _policeDocUrl = w?.policeVerificationDocUrl;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _aadhaarCtrl.dispose();
    _panCtrl.dispose();
    _pfCtrl.dispose();
    _policeCtrl.dispose();
    super.dispose();
  }

  Future<String?> _pickAndUploadImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.camera, imageQuality: 80, maxWidth: 1024);
    if (picked == null) return null;
    try {
      return await WorkerRepository.uploadMedia(picked.path);
    } catch (_) {
      return null;
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_employeePhotoUrl == null || _employeePhotoUrl!.trim().isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Employee identity photo is required'), backgroundColor: kWarningOrange),
        );
      }
      return;
    }
    setState(() => _submitting = true);
    try {
      final data = {
        'fullName': _nameCtrl.text.trim(),
        'phone': _phoneCtrl.text.trim(),
        'employeePhotoUrl': _employeePhotoUrl ?? '',
        'aadhaarNumber': _aadhaarCtrl.text.trim(),
        'aadhaarPhotoUrl': _aadhaarPhotoUrl ?? '',
        'panNumber': _panCtrl.text.trim().toUpperCase(),
        'panPhotoUrl': _panPhotoUrl ?? '',
        'pfUanNumber': _pfCtrl.text.trim(),
        'pfDocumentUrl': _pfDocUrl ?? '',
        'policeVerificationNumber': _policeCtrl.text.trim(),
        'policeVerificationDocUrl': _policeDocUrl ?? '',
        'stationId': widget.stationId,
      };

      if (widget.worker != null) {
        await StationCleaningRepository.updateWorker(widget.worker!.uid, data);
      } else {
        await StationCleaningRepository.createWorker(data);
      }

      if (mounted) Navigator.pop(context);
      widget.onSaved();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: kErrorRed));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Widget _photoField(String label, String? currentUrl, ValueChanged<String?> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
        const SizedBox(height: 4),
        Row(
          children: [
            if (currentUrl != null && currentUrl.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(currentUrl, width: 60, height: 60, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.image, size: 40)),
              ),
            if (currentUrl != null && currentUrl.isNotEmpty) const SizedBox(width: 8),
            TextButton.icon(
              onPressed: () async {
                final url = await _pickAndUploadImage();
                if (url != null) onChanged(url);
              },
              icon: Icon(currentUrl == null || currentUrl.isEmpty ? Icons.camera_alt : Icons.refresh, size: 18),
              label: Text(currentUrl == null || currentUrl.isEmpty ? 'Capture' : 'Retake'),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.worker != null;
    return AlertDialog(
      title: Text(isEdit ? 'Edit Worker' : 'Add Worker'),
      content: SizedBox(
        width: double.maxFinite,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(labelText: 'Full Name *', border: OutlineInputBorder()),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _phoneCtrl,
                  decoration: const InputDecoration(labelText: 'Phone *', border: OutlineInputBorder()),
                  keyboardType: TextInputType.phone,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(10),
                  ],
                  validator: AppValidators.mobile,
                ),
                const SizedBox(height: 12),
                _photoField('Employee Photo', _employeePhotoUrl, (v) => setState(() => _employeePhotoUrl = v)),
                const Divider(height: 24),
                TextFormField(
                  controller: _aadhaarCtrl,
                  decoration: const InputDecoration(labelText: 'Aadhaar Number *', border: OutlineInputBorder()),
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(12),
                  ],
                  validator: AppValidators.aadhaar,
                ),
                const SizedBox(height: 8),
                _photoField('Aadhaar Card Photo', _aadhaarPhotoUrl, (v) => setState(() => _aadhaarPhotoUrl = v)),
                const Divider(height: 24),
                TextFormField(
                  controller: _panCtrl,
                  textCapitalization: TextCapitalization.characters,
                  maxLength: 10,
                  decoration: const InputDecoration(labelText: 'PAN Number', border: OutlineInputBorder(), counterText: ''),
                  validator: (v) => AppValidators.pan(v, required: false),
                ),
                const SizedBox(height: 8),
                _photoField('PAN Card Photo', _panPhotoUrl, (v) => setState(() => _panPhotoUrl = v)),
                const Divider(height: 24),
                TextFormField(
                  controller: _pfCtrl,
                  decoration: const InputDecoration(labelText: 'PF (UAN) Number', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 8),
                _photoField('PF Document', _pfDocUrl, (v) => setState(() => _pfDocUrl = v)),
                const Divider(height: 24),
                TextFormField(
                  controller: _policeCtrl,
                  decoration: const InputDecoration(labelText: 'Police Verification Number', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 8),
                _photoField('Police Verification Document', _policeDocUrl, (v) => setState(() => _policeDocUrl = v)),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: _submitting ? null : _save,
          style: ElevatedButton.styleFrom(backgroundColor: kRailwayBlue, foregroundColor: Colors.white),
          child: _submitting ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : Text(isEdit ? 'Update' : 'Create'),
        ),
      ],
    );
  }
}
