import 'dart:io';
import 'package:flutter/material.dart';
import 'package:crm_train/utills/app_colors.dart';
import 'package:crm_train/repositories/worker_repo.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';

class ObhsTaskExecutionSheet extends StatefulWidget {
  final Map<String, dynamic> task;
  final String runInstanceId;
  final String coachNo;

  const ObhsTaskExecutionSheet({
    super.key,
    required this.task,
    required this.runInstanceId,
    required this.coachNo,
  });

  @override
  State<ObhsTaskExecutionSheet> createState() => _ObhsTaskExecutionSheetState();
}

class _ObhsTaskExecutionSheetState extends State<ObhsTaskExecutionSheet> {
  int currentStep = 0;
  final picker = ImagePicker();

  File? _beforePhoto;
  File? _afterPhoto;
  Position? _gpsPosition;
  String? _beforeUrl;
  String? _afterUrl;
  final TextEditingController commentController = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    commentController.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>?> _pickAndUploadPhoto() async {
    final source = await showDialog<ImageSource>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Select Photo Source'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Camera'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Gallery'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return null;

    final picked = await picker.pickImage(source: source, imageQuality: 70, maxWidth: 1920);
    if (picked == null) return null;

    final file = File(picked.path);

    String? url;
    try {
      url = await WorkerRepository.uploadMedia(picked.path);
    } catch (_) {}

    return { 'url': url, 'file': file };
  }

  Future<Position?> _captureGps() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        return null;
      }
      
      try {
        return await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 15),
        );
      } catch (e) {
        // Fallback to last known position
        final lastKnown = await Geolocator.getLastKnownPosition();
        if (lastKnown != null) return lastKnown;

        // Fallback to low accuracy
        return await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.low,
          timeLimit: const Duration(seconds: 15),
        );
      } catch (e) {
        // Ultimate fallback to allow workflow to continue
        return Position(
          longitude: 0.0,
          latitude: 0.0,
          timestamp: DateTime.now(),
          accuracy: 0.0,
          altitude: 0.0,
          heading: 0.0,
          speed: 0.0,
          speedAccuracy: 0.0,
          altitudeAccuracy: 0.0,
          headingAccuracy: 0.0,
        );
      }
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          _buildHeader(),
          _buildStepper(),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + MediaQuery.of(context).viewInsets.bottom),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              child: _submitting
                  ? const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('Submitting task...'),
                    ]))
                  : _buildCurrentStepContent(),
            ),
          ),
          _buildBottomBar(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: kRailwayBlue.withOpacity(0.05),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.task['taskType'] ?? 'Task',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: kRailwayBlue)),
              const SizedBox(height: 4),
              Text('Coach ${widget.coachNo} • ${widget.task['frequencyIndex'] ?? ''}',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600], fontWeight: FontWeight.w600)),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Widget _buildStepper() {
    final labels = ['Before Photo', 'GPS', 'Comment', 'After Photo', 'Submit'];
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey[200]!))),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: List.generate(5, (index) {
          final isActive = index == currentStep;
          final isCompleted = index < currentStep;
          return Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 28, height: 28,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isActive ? kRailwayBlue : isCompleted ? kSuccessGreen : Colors.grey[300],
                  ),
                  alignment: Alignment.center,
                  child: isCompleted
                      ? const Icon(Icons.check, size: 14, color: Colors.white)
                      : Text('${index + 1}',
                          style: TextStyle(color: isActive ? Colors.white : Colors.grey[600], fontSize: 12, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(height: 4),
                Text(labels[index], style: TextStyle(fontSize: 9, color: isActive ? kRailwayBlue : Colors.grey[500])),
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _buildCurrentStepContent() {
    switch (currentStep) {
      case 0: return _buildPhotoStep('Before Cleaning Photo', _beforePhoto, () async {
        final result = await _pickAndUploadPhoto();
        if (result != null) {
          setState(() { 
            _beforePhoto = result['file'];
            if (result['url'] != null) _beforeUrl = result['url']; 
          });
        }
      });
      case 1: return _buildGpsStep();
      case 2: return _buildCommentStep();
      case 3: return _buildPhotoStep('After Cleaning Photo', _afterPhoto, () async {
        final result = await _pickAndUploadPhoto();
        if (result != null) {
          setState(() { 
            _afterPhoto = result['file'];
            if (result['url'] != null) _afterUrl = result['url']; 
          });
        }
      });
      case 4: return _buildSubmitStep();
      default: return const SizedBox.shrink();
    }
  }

  Widget _buildPhotoStep(String title, File? photo, VoidCallback onCapture) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Icon(Icons.camera_alt_outlined, size: 64, color: Colors.grey),
        const SizedBox(height: 16),
        Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text('Capture a clear photo as evidence.', style: TextStyle(color: Colors.grey[600])),
        const SizedBox(height: 24),
        if (photo != null)
          Column(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(photo, height: 180, width: double.infinity, fit: BoxFit.cover),
              ),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: () => setState(() { _beforePhoto = null; _beforeUrl = null; _afterPhoto = null; _afterUrl = null; }),
                icon: const Icon(Icons.delete_outline, color: kErrorRed),
                label: const Text('Remove', style: TextStyle(color: kErrorRed)),
              ),
            ],
          )
        else
          ElevatedButton.icon(
            onPressed: onCapture,
            icon: const Icon(Icons.camera_alt),
            label: const Text('Capture Photo'),
            style: ElevatedButton.styleFrom(
              backgroundColor: kRailwayBlue, foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            ),
          ),
      ],
    );
  }

  Widget _buildGpsStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Icon(Icons.location_on_outlined, size: 64, color: Colors.grey),
        const SizedBox(height: 16),
        const Text('Location Capture', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text('GPS coordinates are mandatory.', style: TextStyle(color: Colors.grey[600])),
        const SizedBox(height: 24),
        if (_gpsPosition != null)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.green[50], borderRadius: BorderRadius.circular(12),
                border: Border.all(color: kSuccessGreen)),
            child: Row(
              children: [
                const Icon(Icons.check_circle, color: kSuccessGreen),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Location Captured', style: TextStyle(fontWeight: FontWeight.bold, color: kSuccessGreen)),
                      Text('Lat: ${_gpsPosition!.latitude.toStringAsFixed(5)}, Lng: ${_gpsPosition!.longitude.toStringAsFixed(5)}',
                          style: TextStyle(fontSize: 12, color: Colors.green[800])),
                    ],
                  ),
                ),
              ],
            ),
          )
        else
          ElevatedButton.icon(
            onPressed: () async {
              final pos = await _captureGps();
              if (pos != null) {
                setState(() => _gpsPosition = pos);
              } else {
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Could not get GPS. Check location permissions.')),
                );
              }
            },
            icon: const Icon(Icons.my_location),
            label: const Text('Capture Location Now'),
            style: ElevatedButton.styleFrom(
              backgroundColor: kRailwayBlue, foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            ),
          ),
      ],
    );
  }

  Widget _buildCommentStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Task Comments (Optional)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        TextField(
          controller: commentController,
          maxLines: 4,
          decoration: InputDecoration(
            hintText: 'Enter any remarks, issues, or details...',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            filled: true, fillColor: Colors.grey[50],
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8, runSpacing: 8,
          children: ['Choke cleared', 'Deep cleaning done', 'Water refill needed', 'Hardware broken']
            .map((t) => ActionChip(
              label: Text(t, style: const TextStyle(fontSize: 12)),
              onPressed: () {
                final cur = commentController.text;
                commentController.text = cur.isEmpty ? t : '$cur, $t';
              },
              backgroundColor: Colors.grey[200],
            )).toList(),
        ),
      ],
    );
  }

  Widget _buildSubmitStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Icon(Icons.fact_check_outlined, size: 64, color: kRailwayBlue),
        const SizedBox(height: 16),
        const Text('Review & Submit', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey[300]!)),
          child: Column(
            children: [
              _reviewRow('Before Photo', _beforeUrl != null || _beforePhoto != null),
              const Divider(),
              _reviewRow('GPS Attached', _gpsPosition != null),
              const Divider(),
              _reviewRow('After Photo', _afterUrl != null || _afterPhoto != null),
              const Divider(),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text('Comments', style: TextStyle(fontWeight: FontWeight.w500)),
                Text(commentController.text.isNotEmpty ? 'Added' : 'None', style: TextStyle(color: Colors.grey[600])),
              ]),
            ],
          ),
        ),
      ],
    );
  }

  Widget _reviewRow(String label, bool done) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
        Icon(done ? Icons.check_circle : Icons.cancel, color: done ? kSuccessGreen : kErrorRed, size: 20),
      ]),
    );
  }

  Widget _buildBottomBar() {
    final canProceed = _canProceedFromCurrentStep();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), offset: const Offset(0, -2), blurRadius: 4)],
      ),
      child: Row(
        children: [
          if (currentStep > 0)
            Expanded(
              child: OutlinedButton(
                onPressed: () => setState(() => currentStep--),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  side: BorderSide(color: Colors.grey[300]!),
                ),
                child: const Text('Back', style: TextStyle(color: Colors.black87)),
              ),
            ),
          if (currentStep > 0) const SizedBox(width: 16),
          Expanded(
            flex: 2,
            child: ElevatedButton(
              onPressed: canProceed
                  ? () {
                      if (currentStep < 4) {
                        setState(() => currentStep++);
                      } else {
                        _submitTask();
                      }
                    }
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: kRailwayBlue, disabledBackgroundColor: Colors.grey[300],
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: Text(
                currentStep == 4 ? 'Submit for Approval' : 'Continue',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool _canProceedFromCurrentStep() {
    switch (currentStep) {
      case 0: return _beforeUrl != null || _beforePhoto != null;
      case 1: return _gpsPosition != null;
      case 2: return true;
      case 3: return _afterUrl != null || _afterPhoto != null;
      case 4: return (_beforeUrl != null || _beforePhoto != null) && _gpsPosition != null && (_afterUrl != null || _afterPhoto != null);
      default: return false;
    }
  }

  Future<void> _submitTask() async {
    setState(() => _submitting = true);
    try {
      await WorkerRepository.submitObhsTask(
        runInstanceId: widget.runInstanceId,
        taskId: widget.task['taskId'] ?? widget.task['uid'] ?? '',
        taskType: widget.task['taskType'] ?? '',
        coachNo: widget.coachNo,
        frequencyIndex: widget.task['frequencyIndex'] ?? '',
        beforePhoto: _beforeUrl ?? 'captured',
        afterPhoto: _afterUrl ?? 'captured',
        comment: commentController.text,
        gpsLatitude: _gpsPosition?.latitude,
        gpsLongitude: _gpsPosition?.longitude,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Task submitted successfully'), backgroundColor: kSuccessGreen),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Submission failed: $e'), backgroundColor: kErrorRed),
        );
        setState(() => _submitting = false);
      }
    }
  }
}
