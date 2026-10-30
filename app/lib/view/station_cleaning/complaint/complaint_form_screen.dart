import 'package:crm_train/model/station_cleaning_models.dart';
import 'package:crm_train/repositories/complaint_repository.dart';
import 'package:crm_train/utills/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:convert';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:crm_train/services/api_services.dart';

class ComplaintFormScreen extends StatefulWidget {
  final Complaint? complaint;
  final String stationId;
  final String stationName;
  const ComplaintFormScreen({super.key, this.complaint, required this.stationId, required this.stationName});

  @override
  State<ComplaintFormScreen> createState() => _ComplaintFormScreenState();
}

class _ComplaintFormScreenState extends State<ComplaintFormScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;

  late TextEditingController _descriptionCtrl;
  late TextEditingController _assigneeCtrl;
  late TextEditingController _resolutionCtrl;
  late TextEditingController _resolutionPhotoCtrl;
  late TextEditingController _reopenReasonCtrl;
  late TextEditingController _escalateToCtrl;

  String _category = 'Other';
  String _severity = 'medium';
  double? _latitude;
  double? _longitude;
  bool _uploadingPhoto = false;
  String? _photoUrl;

  bool get isEdit => widget.complaint != null;
  String get _currentStatus => widget.complaint?.status ?? '';

  @override
  void initState() {
    super.initState();
    final r = widget.complaint;
    _descriptionCtrl = TextEditingController(text: r?.description ?? '');
    _assigneeCtrl = TextEditingController();
    _resolutionCtrl = TextEditingController();
    _resolutionPhotoCtrl = TextEditingController();
    _reopenReasonCtrl = TextEditingController();
    _escalateToCtrl = TextEditingController();

    if (r != null) {
      _category = r.category;
    }
  }

  Future<void> _pickAndUploadPhoto() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.camera, imageQuality: 70);
    if (picked == null) return;
    setState(() => _uploadingPhoto = true);
    try {
      final bytes = await picked.readAsBytes();
      final token = await ApiService.getToken();
      if (token == null) return;
      final response = await http.post(
        Uri.parse('${ApiService.baseUrl}/api/evidence/upload/base64'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
        body: jsonEncode({
          'image': base64Encode(bytes),
          'fileName': 'complaint_${DateTime.now().millisecondsSinceEpoch}.jpg',
        }),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _photoUrl = data['url'] ?? data['imageUrl'] ?? '';
        });
      }
    } catch (_) {}
    if (mounted) setState(() => _uploadingPhoto = false);
  }

  @override
  void dispose() {
    _descriptionCtrl.dispose();
    _assigneeCtrl.dispose();
    _resolutionCtrl.dispose();
    _resolutionPhotoCtrl.dispose();
    _reopenReasonCtrl.dispose();
    _escalateToCtrl.dispose();
    super.dispose();
  }

  Future<void> _createComplaint() async {
    if (!_formKey.currentState!.validate()) return;
    if (_photoUrl == null || _photoUrl!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please capture a photo. Photo is mandatory.'), backgroundColor: kErrorRed),
      );
      return;
    }
    setState(() => _isLoading = true);
    try {
      final body = <String, dynamic>{
        'stationId': widget.stationId,
        'stationName': widget.stationName,
        'category': _category,
        'description': _descriptionCtrl.text.trim(),
        'severity': _severity,
        'photoUrl': _photoUrl,
      };
      if (_latitude != null) body['latitude'] = _latitude;
      if (_longitude != null) body['longitude'] = _longitude;
      await ComplaintRepository.create(body);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Complaint created'), backgroundColor: kSuccessGreen),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: kErrorRed),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _assign() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Assign Complaint'),
        content: TextField(
          controller: _assigneeCtrl,
          decoration: const InputDecoration(labelText: 'Assignee ID', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              if (_assigneeCtrl.text.trim().isEmpty) return;
              try {
                await ComplaintRepository.assign(widget.complaint!.uid, _assigneeCtrl.text.trim());
                if (mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Complaint assigned'), backgroundColor: kSuccessGreen),
                  );
                  Navigator.pop(context, true);
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error: $e'), backgroundColor: kErrorRed),
                  );
                }
              }
            },
            child: const Text('Assign'),
          ),
        ],
      ),
    );
  }

  Future<void> _startProgress() async {
    setState(() => _isLoading = true);
    try {
      await ComplaintRepository.startProgress(widget.complaint!.uid);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Progress started'), backgroundColor: kSuccessGreen),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: kErrorRed),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _resolve() {
    _resolutionCtrl.text = widget.complaint?.resolution ?? '';
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Resolve Complaint'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _resolutionCtrl,
                decoration: const InputDecoration(labelText: 'Resolution *', border: OutlineInputBorder()),
                maxLines: 3,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _resolutionPhotoCtrl,
                decoration: const InputDecoration(labelText: 'Photo URL (optional)', border: OutlineInputBorder()),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              if (_resolutionCtrl.text.trim().isEmpty) return;
              try {
                await ComplaintRepository.resolve(
                  widget.complaint!.uid,
                  _resolutionCtrl.text.trim(),
                  _resolutionPhotoCtrl.text.trim().isNotEmpty ? _resolutionPhotoCtrl.text.trim() : null,
                );
                if (mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Complaint resolved'), backgroundColor: kSuccessGreen),
                  );
                  Navigator.pop(context, true);
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error: $e'), backgroundColor: kErrorRed),
                  );
                }
              }
            },
            child: const Text('Resolve'),
          ),
        ],
      ),
    );
  }

  Future<void> _closeComplaint() async {
    setState(() => _isLoading = true);
    try {
      await ComplaintRepository.close(widget.complaint!.uid);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Complaint closed'), backgroundColor: kSuccessGreen),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: kErrorRed),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _reopen() {
    _reopenReasonCtrl.clear();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reopen Complaint'),
        content: TextField(
          controller: _reopenReasonCtrl,
          decoration: const InputDecoration(labelText: 'Reason *', border: OutlineInputBorder()),
          maxLines: 2,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              if (_reopenReasonCtrl.text.trim().isEmpty) return;
              try {
                await ComplaintRepository.reopen(widget.complaint!.uid, _reopenReasonCtrl.text.trim());
                if (mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Complaint reopened'), backgroundColor: kWarningOrange),
                  );
                  Navigator.pop(context, true);
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error: $e'), backgroundColor: kErrorRed),
                  );
                }
              }
            },
            child: const Text('Reopen'),
          ),
        ],
      ),
    );
  }

  void _escalate() {
    _escalateToCtrl.clear();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Escalate Complaint'),
        content: TextField(
          controller: _escalateToCtrl,
          decoration: const InputDecoration(labelText: 'Escalate To *', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              if (_escalateToCtrl.text.trim().isEmpty) return;
              try {
                await ComplaintRepository.escalate(widget.complaint!.uid, _escalateToCtrl.text.trim());
                if (mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Complaint escalated'), backgroundColor: kWarningOrange),
                  );
                  Navigator.pop(context, true);
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error: $e'), backgroundColor: kErrorRed),
                  );
                }
              }
            },
            child: const Text('Escalate'),
          ),
        ],
      ),
    );
  }

  void _rejectComplaint() {
    final reasonCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reject Complaint'),
        content: TextField(
          controller: reasonCtrl,
          decoration: const InputDecoration(labelText: 'Rejection Reason *', border: OutlineInputBorder()),
          maxLines: 3,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              if (reasonCtrl.text.trim().isEmpty) return;
              try {
                await ComplaintRepository.reject(widget.complaint!.uid, reasonCtrl.text.trim());
                if (mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Complaint rejected'), backgroundColor: kWarningOrange),
                  );
                  Navigator.pop(context, true);
                }
              } catch (e) {
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: kErrorRed));
              }
            },
            child: const Text('Reject'),
          ),
        ],
      ),
    );
  }

  Future<void> _verifyComplaint() async {
    setState(() => _isLoading = true);
    try {
      await ComplaintRepository.verify(widget.complaint!.uid);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Complaint verified'), backgroundColor: kSuccessGreen),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: kErrorRed));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _resubmitComplaint() async {
    final actionCtrl = TextEditingController();
    final photoCtrl = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Resubmit Complaint'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: actionCtrl,
                decoration: const InputDecoration(labelText: 'Updated Action Taken *', border: OutlineInputBorder()),
                maxLines: 3,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: photoCtrl,
                decoration: const InputDecoration(labelText: 'Closure Photo URL (optional)', border: OutlineInputBorder()),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              if (actionCtrl.text.trim().isEmpty) return;
              Navigator.pop(ctx, true);
            },
            child: const Text('Submit'),
          ),
        ],
      ),
    );
    if (result != true) return;
    setState(() => _isLoading = true);
    try {
      await ComplaintRepository.resubmit(
        widget.complaint!.uid,
        actionCtrl.text.trim(),
        photoCtrl.text.trim().isNotEmpty ? photoCtrl.text.trim() : null,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Complaint resubmitted'), backgroundColor: kWarningOrange),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: kErrorRed));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  bool _gpsLoading = false;

  Future<void> _captureGps() async {
    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      final granted = await Geolocator.requestPermission();
      if (granted == LocationPermission.denied || granted == LocationPermission.deniedForever) return;
    }
    setState(() => _gpsLoading = true);
    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high, timeLimit: const Duration(seconds: 15),
      );
      setState(() { _latitude = pos.latitude; _longitude = pos.longitude; });
    } catch (_) {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null) setState(() { _latitude = last.latitude; _longitude = last.longitude; });
    } finally {
      setState(() => _gpsLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.complaint;
    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? 'Complaint Detail' : 'New Complaint', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: kRailwayBlue,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      DropdownButtonFormField<String>(
                        value: _category,
                        decoration: const InputDecoration(labelText: 'Category *', border: OutlineInputBorder()),
                        items: const [
                          DropdownMenuItem(value: 'Broken Fittings', child: Text('Broken Fittings')),
                          DropdownMenuItem(value: 'Damaged Dustbin', child: Text('Damaged Dustbin')),
                          DropdownMenuItem(value: 'Leakage', child: Text('Leakage')),
                          DropdownMenuItem(value: 'Blocked Drain', child: Text('Blocked Drain')),
                          DropdownMenuItem(value: 'Damaged Tiles', child: Text('Damaged Tiles')),
                          DropdownMenuItem(value: 'Lighting Issue', child: Text('Lighting Issue')),
                          DropdownMenuItem(value: 'Signage Issue', child: Text('Signage Issue')),
                          DropdownMenuItem(value: 'Damaged Fixture', child: Text('Damaged Fixture')),
                          DropdownMenuItem(value: 'Plumbing', child: Text('Plumbing')),
                          DropdownMenuItem(value: 'Electrical', child: Text('Electrical')),
                          DropdownMenuItem(value: 'Other', child: Text('Other')),
                        ],
                        onChanged: isEdit ? null : (v) {
                          if (v != null) setState(() => _category = v);
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _descriptionCtrl,
                        decoration: const InputDecoration(labelText: 'Description *', border: OutlineInputBorder()),
                        maxLines: 4,
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                      ),
                      if (!isEdit) ...[
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          value: _severity,
                          decoration: const InputDecoration(labelText: 'Severity', border: OutlineInputBorder()),
                          items: const [
                            DropdownMenuItem(value: 'low', child: Text('Low')),
                            DropdownMenuItem(value: 'medium', child: Text('Medium')),
                            DropdownMenuItem(value: 'high', child: Text('High')),
                            DropdownMenuItem(value: 'critical', child: Text('Critical')),
                          ],
                          onChanged: (v) { if (v != null) setState(() => _severity = v); },
                        ),
                        const SizedBox(height: 12),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            ElevatedButton.icon(
                              onPressed: _uploadingPhoto ? null : _pickAndUploadPhoto,
                              icon: _uploadingPhoto
                                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                  : const Icon(Icons.camera_alt),
                              label: Text(_photoUrl != null && _photoUrl!.isNotEmpty ? 'Retake Photo' : 'Capture Photo *'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _photoUrl != null && _photoUrl!.isNotEmpty ? Colors.grey : kRailwayBlue,
                                foregroundColor: Colors.white,
                              ),
                            ),
                            if (_photoUrl != null && _photoUrl!.isNotEmpty) ...[
                              const SizedBox(width: 12),
                              const Icon(Icons.verified, color: kSuccessGreen, size: 20),
                              const SizedBox(width: 4),
                              const Text('Captured', style: TextStyle(color: kSuccessGreen, fontWeight: FontWeight.bold)),
                            ],
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: InputDecorator(
                                decoration: const InputDecoration(labelText: 'Latitude', border: OutlineInputBorder()),
                                child: Text(_latitude?.toStringAsFixed(6) ?? 'Not captured', style: const TextStyle(fontSize: 14)),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: InputDecorator(
                                decoration: const InputDecoration(labelText: 'Longitude', border: OutlineInputBorder()),
                                child: Text(_longitude?.toStringAsFixed(6) ?? 'Not captured', style: const TextStyle(fontSize: 14)),
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              height: 48,
                              child: ElevatedButton(
                                onPressed: _gpsLoading ? null : _captureGps,
                                style: ElevatedButton.styleFrom(backgroundColor: kRailwayBlue, foregroundColor: Colors.white),
                                child: _gpsLoading
                                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                    : const Icon(Icons.my_location, size: 20),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              if (r != null && r.slaDeadline != null) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: r.slaBreached ? kErrorRed.withOpacity(0.1) : kSuccessGreen.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: r.slaBreached ? kErrorRed : kSuccessGreen),
                  ),
                  child: Row(
                    children: [
                      Icon(r.slaBreached ? Icons.warning : Icons.access_time,
                          color: r.slaBreached ? kErrorRed : kSuccessGreen),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          r.slaBreached ? 'SLA BREACHED - Deadline: ${r.slaDeadline}' : 'SLA Deadline: ${r.slaDeadline}',
                          style: TextStyle(
                            color: r.slaBreached ? kErrorRed : kSuccessGreen,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (isEdit && (_currentStatus == 'reported' || _currentStatus == 'assigned' ||
                  _currentStatus == 'inProgress')) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: _escalate,
                    icon: const Icon(Icons.arrow_upward),
                    label: const Text('Escalate'),
                    style: ElevatedButton.styleFrom(backgroundColor: kWarningOrange, foregroundColor: Colors.white),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              if (_isLoading)
                const Center(child: CircularProgressIndicator())
              else ...[
                if (!isEdit)
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: _createComplaint,
                      style: ElevatedButton.styleFrom(backgroundColor: kRailwayBlue, foregroundColor: Colors.white),
                      child: const Text('Create Complaint'),
                    ),
                  ),
                if (isEdit && _currentStatus == 'reported') ...[
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: _assign,
                      style: ElevatedButton.styleFrom(backgroundColor: kWarningOrange, foregroundColor: Colors.white),
                      child: const Text('Assign'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: _startProgress,
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
                      child: const Text('Start Progress'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: () => _rejectComplaint(),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.grey, foregroundColor: Colors.white),
                      child: const Text('Reject'),
                    ),
                  ),
                ],
                if (isEdit && _currentStatus == 'inProgress')
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: _resolve,
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white),
                      child: const Text('Resolve'),
                    ),
                  ),
                if (isEdit && _currentStatus == 'resolved') ...[
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: () => _verifyComplaint(),
                      style: ElevatedButton.styleFrom(backgroundColor: kSuccessGreen, foregroundColor: Colors.white),
                      child: const Text('Verify'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: () => _rejectComplaint(),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.grey, foregroundColor: Colors.white),
                      child: const Text('Reject Resolution'),
                    ),
                  ),
                ],
                if (isEdit && _currentStatus == 'railwayVerified')
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: _closeComplaint,
                      style: ElevatedButton.styleFrom(backgroundColor: kSuccessGreen, foregroundColor: Colors.white),
                      child: const Text('Close'),
                    ),
                  ),
                if (isEdit && _currentStatus == 'rejected') ...[
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: _resubmitComplaint,
                      style: ElevatedButton.styleFrom(backgroundColor: kWarningOrange, foregroundColor: Colors.white),
                      child: const Text('Resubmit'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: _reopen,
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.purple, foregroundColor: Colors.white),
                      child: const Text('Reopen'),
                    ),
                  ),
                ],
                if (isEdit && _currentStatus == 'closed')
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: _reopen,
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.purple, foregroundColor: Colors.white),
                      child: const Text('Reopen'),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
