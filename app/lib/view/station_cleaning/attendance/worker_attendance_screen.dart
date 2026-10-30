import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:crm_train/repositories/station_cleaning_repository.dart';
import 'package:crm_train/utills/app_colors.dart';

class StationWorkerAttendanceScreen extends StatefulWidget {
  final String workerId;
  final String workerName;
  final String? runInstanceId;
  final String? stationId;
  final String attendanceType;

  const StationWorkerAttendanceScreen({
    super.key,
    required this.workerId,
    required this.workerName,
    this.runInstanceId,
    this.stationId,
    required this.attendanceType,
  });

  @override
  State<StationWorkerAttendanceScreen> createState() => _StationWorkerAttendanceScreenState();
}

class _StationWorkerAttendanceScreenState extends State<StationWorkerAttendanceScreen> {
  final picker = ImagePicker();

  File? _selfie;
  Position? _gpsPosition;
  bool _submitting = false;
  String _livenessChallenge = '';

  bool _isCapturingSelfie = false;
  bool _isCapturingGps = false;

  @override
  void initState() {
    super.initState();
    _generateChallenge();
  }

  void _generateChallenge() {
    _livenessChallenge = 'SMILE';
  }

  Future<File?> _captureSelfie() async {
    final picked = await picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 80,
      maxWidth: 1280,
      preferredCameraDevice: CameraDevice.front,
    );
    if (picked == null) return null;
    return File(picked.path);
  }

  Future<Position?> _captureGps() async {
    // GPS fallback chain mirroring the OBHS worker attendance flow.
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return null;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        return null;
      }

      try {
        return await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.medium,
          timeLimit: const Duration(seconds: 20),
        );
      } catch (e) {
        try {
          final lastKnown = await Geolocator.getLastKnownPosition();
          if (lastKnown != null) return lastKnown;
        } catch (_) {}

        try {
          return await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.low,
            timeLimit: const Duration(seconds: 15),
          );
        } catch (e2) {
          return Position(
            longitude: 0.0, latitude: 0.0,
            timestamp: DateTime.now(),
            accuracy: 0.0, altitude: 0.0, heading: 0.0, speed: 0.0,
            speedAccuracy: 0.0, altitudeAccuracy: 0.0, headingAccuracy: 0.0,
          );
        }
      }
    } catch (_) {
      return null;
    }
  }

  Future<void> _submitAttendance() async {
    if (_selfie == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please capture your selfie first.'), backgroundColor: kWarningOrange),
      );
      return;
    }
    if (_gpsPosition == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('GPS location is required'), backgroundColor: kWarningOrange),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      final response = await StationCleaningRepository.markStationAttendance(
        type: widget.attendanceType,
        runInstanceId: widget.runInstanceId ?? '',
        stationId: widget.stationId ?? '',
        imageUrl: '',
        latitude: _gpsPosition!.latitude,
        longitude: _gpsPosition!.longitude,
        livenessChallenge: _livenessChallenge,
      ).timeout(
        const Duration(seconds: 40),
        onTimeout: () => throw Exception('Attendance server timeout. Please check your internet and try again.'),
      );

      final responseMessage =
          response['message']?.toString() ?? response['error']?.toString() ?? '';
      final isAlreadySubmitted = responseMessage.toLowerCase().contains('already') &&
          responseMessage.toLowerCase().contains('submitted');
      final isSuccess = response['success'] == true || responseMessage.isNotEmpty;

      if (isSuccess && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isAlreadySubmitted
                ? responseMessage
                : '${widget.attendanceType.toUpperCase()} attendance marked successfully'),
            backgroundColor: isAlreadySubmitted ? kWarningOrange : kSuccessGreen,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      final msg = e.toString().replaceAll('Exception: ', '');
      final isAlreadySubmitted =
          msg.toLowerCase().contains('already') && msg.toLowerCase().contains('submitted');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isAlreadySubmitted ? msg : 'Error: $msg'),
            backgroundColor: isAlreadySubmitted ? kWarningOrange : kErrorRed,
          ),
        );
        if (isAlreadySubmitted) {
          Navigator.pop(context, true);
        } else {
          setState(() => _submitting = false);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.attendanceType == 'start' ? 'Start Attendance' :
        widget.attendanceType == 'mid' ? 'Mid Check-in' : 'End Attendance';

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: kRailwayBlue,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _submitting
          ? const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Submitting attendance...'),
            ]))
          : Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Daily Attendance',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: kRailwayBlue),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Show a wide smile in your selfie.\nCamera capture only.',
                    style: const TextStyle(color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 48),

                  _buildVerificationCard(
                    title: 'Selfie Verification',
                    subtitle: _selfie != null ? 'Selfie captured successfully' : 'Take a selfie with a wide smile',
                    icon: Icons.camera_front,
                    isVerified: _selfie != null,
                    isVerifying: _isCapturingSelfie,
                    onVerify: () async {
                      setState(() => _isCapturingSelfie = true);
                      try {
                        final result = await _captureSelfie();
                        if (result != null) {
                          setState(() {
                            _selfie = result;
                          });
                        }
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('$e'), backgroundColor: kErrorRed),
                          );
                        }
                      }
                      if (mounted) setState(() => _isCapturingSelfie = false);
                    },
                    onRemove: _selfie != null ? () => setState(() { _selfie = null; _generateChallenge(); }) : null,
                  ),
                  const SizedBox(height: 24),

                  _buildVerificationCard(
                    title: 'Location Verification',
                    subtitle: _gpsPosition != null
                        ? 'GPS: ${_gpsPosition!.latitude.toStringAsFixed(5)}, ${_gpsPosition!.longitude.toStringAsFixed(5)}'
                        : 'Verify your current location',
                    icon: Icons.location_on,
                    isVerified: _gpsPosition != null,
                    isVerifying: _isCapturingGps,
                    onVerify: () async {
                      setState(() => _isCapturingGps = true);
                      final pos = await _captureGps();
                      if (pos != null) {
                        setState(() => _gpsPosition = pos);
                      } else {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Could not get GPS. Check location permissions.')),
                          );
                        }
                      }
                      if (mounted) setState(() => _isCapturingGps = false);
                    },
                  ),

                  const Spacer(),

                  ElevatedButton(
                    onPressed: (_selfie != null && _gpsPosition != null) ? _submitAttendance : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kRailwayBlue,
                      disabledBackgroundColor: Colors.grey[300],
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text(
                      'Mark Present',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }

  Widget _buildVerificationCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isVerified,
    required bool isVerifying,
    required VoidCallback onVerify,
    VoidCallback? onRemove,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isVerified ? kSuccessGreen : Colors.grey[300]!, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isVerified ? kSuccessGreen.withOpacity(0.1) : kRailwayBlue.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: isVerified ? kSuccessGreen : kRailwayBlue, size: 32),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 4),
                Text(subtitle, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
              ],
            ),
          ),
          if (isVerified)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (onRemove != null)
                  GestureDetector(
                    onTap: onRemove,
                    child: const Icon(Icons.delete_outline, color: kErrorRed, size: 20),
                  ),
                const SizedBox(width: 8),
                const Icon(Icons.check_circle, color: kSuccessGreen, size: 32),
              ],
            )
          else if (isVerifying)
            const SizedBox(
              width: 24, height: 24,
              child: CircularProgressIndicator(strokeWidth: 2, color: kRailwayBlue),
            )
          else
            TextButton(
              onPressed: onVerify,
              style: TextButton.styleFrom(
                backgroundColor: kRailwayBlue.withOpacity(0.1),
                foregroundColor: kRailwayBlue,
              ),
              child: const Text('Verify'),
            ),
        ],
      ),
    );
  }
}
