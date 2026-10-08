import 'package:crm_train/utills/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../model/train_model.dart';
import '../../model/run_instance_model.dart';
import '../../model/railway_worker_model.dart';
import '../../repositories/obhs_repository.dart';

class CoachData {
  final int coachNumber;
  final String displayNo;
  int? position;
  String? type;
  String? assignedJanitorId;
  String? assignedJanitorName;
  String? assignedAttendantId;
  String? assignedAttendantName;

  CoachData({
    required this.coachNumber,
    required this.displayNo,
    this.position,
    this.type,
    this.assignedJanitorId,
    this.assignedJanitorName,
    this.assignedAttendantId,
    this.assignedAttendantName,
  });
  
  bool get isAC => type != null && (type!.toUpperCase().contains('AC') || type!.toUpperCase().contains('A1') || type!.toUpperCase().contains('A2') || type!.toUpperCase().contains('A3') || type!.toUpperCase().contains('B1') || type!.toUpperCase().contains('CC'));
}

class OBHSCreateInstanceScreen extends StatefulWidget {
  final RunInstanceModel? editInstance;

  const OBHSCreateInstanceScreen({super.key, this.editInstance});

  @override
  State<OBHSCreateInstanceScreen> createState() =>
      _OBHSCreateInstanceScreenState();
}

class _OBHSCreateInstanceScreenState extends State<OBHSCreateInstanceScreen> {
  List<TrainModel> allTrains = [];
  List<RunInstanceModel> trainInstances = [];
  List<RailwayWorkerModel> allWorkers = []; // Store all approved workers

  bool _isLoadingTrains = false;
  bool _isLoadingInstances = false;
  bool _isLoadingWorkers = false;
  bool _isSubmitting = false;

  String? _trainsError;
  String? _instancesError;
  String? _workersError;

  int currentStep = 0;
  String? selectedTrainId;
  DateTime? selectedDepartureDate;
  RunInstanceModel? selectedInstance;
  int selectedCoachCount = 1;
  List<CoachData> coaches = [];

  // All approved workers, sorted with train-matched ones first
  List<RailwayWorkerModel> get filteredWorkers {
    final sorted = List<RailwayWorkerModel>.from(allWorkers);
    if (selectedTrainId != null) {
      sorted.sort((a, b) {
        final aMatch = a.trainIds?.contains(selectedTrainId) ?? false;
        final bMatch = b.trainIds?.contains(selectedTrainId) ?? false;
        if (aMatch && !bMatch) return -1;
        if (!aMatch && bMatch) return 1;
        return 0;
      });
    }
    return sorted;
  }

  final List<String> coachTypes = [
    'AC',
    'General',
    'Sleeper',
    'A1',
    'A2',
    'A3',
    'B1',
    'C1',
    'D1',
    'SL',
    'GS',
    'CC',
  ];

  bool get isEditMode => widget.editInstance != null;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    await Future.wait([
      _loadTrains(),
      _loadWorkers(),
    ]);

    if (isEditMode && widget.editInstance != null) {
      _preFillEditData();
    }
  }

  void _preFillEditData() {
    final instance = widget.editInstance!;

    setState(() {
      currentStep = 0;

      selectedTrainId = instance.parentTrainId;
      selectedInstance = instance;
      selectedCoachCount = instance.coaches.length;
      selectedDepartureDate = instance.departureDate;

      coaches = instance.coaches.asMap().entries.map((entry) {
        final index = entry.key;
        final coach = entry.value;

        return CoachData(
          coachNumber: index + 1,
          displayNo: 'C${(index + 1).toString().padLeft(2, '0')}',
          position: coach.coachPosition,
          type: coach.coachType,
          assignedJanitorId: coach.janitorId,
          assignedJanitorName: coach.janitorName,
          assignedAttendantId: coach.attendantId,
          assignedAttendantName: coach.attendantName,
        );
      }).toList();
    });
    
    // Ensure we load workers after pre-filling train ID
    if (selectedTrainId != null) {
      _loadInstancesForTrain(selectedTrainId!);
    }
  }

  Future<void> _loadTrains() async {
    setState(() {
      _isLoadingTrains = true;
      _trainsError = null;
    });

    try {
      final trains = await OBHSRepository.getOBHSTrains();
      if (mounted) {
        setState(() {
          allTrains = trains;
          _isLoadingTrains = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _trainsError = e.toString().replaceAll('Exception: ', '');
          _isLoadingTrains = false;
        });

        if (_trainsError!.contains('AUTH_ERROR')) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Session expired. Please login again.'),
              backgroundColor: kErrorRed,
            ),
          );
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
      }
    }
  }

  Future<void> _loadInstancesForTrain(String trainId) async {
    setState(() {
      _isLoadingInstances = true;
      _instancesError = null;
      trainInstances = [];
      selectedInstance = null;
    });

    try {
      final instances = await OBHSRepository.getRunInstancesByTrain(trainId);
      if (mounted) {
        setState(() {
          trainInstances = instances;
          _isLoadingInstances = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _instancesError = e.toString().replaceAll('Exception: ', '');
          _isLoadingInstances = false;
        });
      }
    }
  }

  Future<void> _loadWorkers() async {
    setState(() {
      _isLoadingWorkers = true;
      _workersError = null;
    });

    try {
      final workersList = await OBHSRepository.getRailwayWorkers();
      for (var w in workersList) {
      }
      if (mounted) {
        setState(() {
          allWorkers = workersList.where((w) {
            final statusUpper = w.status.toUpperCase();
            final isApproved = statusUpper == 'APPROVED' || statusUpper == 'ACTIVE' || statusUpper == 'VERIFIED';
            return isApproved;
          }).toList();
          _isLoadingWorkers = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _workersError = e.toString().replaceAll('Exception: ', '');
          _isLoadingWorkers = false;
        });
      }
    }
  }

  TrainModel? getSelectedTrain() {
    return allTrains.firstWhereOrNull((t) => t.uid == selectedTrainId);
  }

  bool canProceedStep1() {
    if (isEditMode) {
      return selectedCoachCount > 0 && selectedDepartureDate != null;
    } else {
      return selectedTrainId != null &&
          selectedInstance != null &&
          selectedCoachCount > 0 &&
          selectedDepartureDate != null;
    }
  }

  bool isCoachComplete(CoachData coach) {
    if (coach.type == null || coach.position == null) return false;
    
    // For AC coaches, both janitor and attendant are required
    if (coach.isAC) {
      return coach.assignedJanitorId != null && coach.assignedAttendantId != null;
    }
    // For non-AC coaches, only janitor is required
    return coach.assignedJanitorId != null;
  }

  bool allCoachesComplete() {
    return coaches.isNotEmpty && coaches.every((c) => isCoachComplete(c));
  }

  void goToStep2() {
    if (isEditMode) {
      setState(() {
        final currentCoachCount = coaches.length;

        if (selectedCoachCount > currentCoachCount) {
          for (int i = currentCoachCount + 1; i <= selectedCoachCount; i++) {
            coaches.add(CoachData(
              coachNumber: i,
              displayNo: 'C${i.toString().padLeft(2, '0')}',
              position: i,
            ));
          }
        } else if (selectedCoachCount < currentCoachCount) {
          coaches.removeRange(selectedCoachCount, currentCoachCount);
        }

        currentStep = 1;
      });
    } else {
      coaches.clear();
      for (int i = 1; i <= selectedCoachCount; i++) {
        coaches.add(CoachData(
          coachNumber: i,
          displayNo: 'C${i.toString().padLeft(2, '0')}',
          position: i,
        ));
      }
      setState(() {
        currentStep = 1;
      });
    }
  }

  Future<void> submitForm({bool stayOnScreen = false}) async {
    if (!allCoachesComplete()) {
      // Tell the user which coaches are incomplete instead of silently
      // doing nothing when the submit button is tapped.
      final pending = coaches
          .where((c) => !isCoachComplete(c))
          .map((c) => c.displayNo)
          .join(', ');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(pending.isEmpty
                ? 'Please complete all coach assignments before submitting.'
                : 'Assign staff to complete coaches: $pending'),
            backgroundColor: kErrorRed,
          ),
        );
      }
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final apiCoaches = coaches.map((coach) {
        bool isAC = coach.isAC;
        return CoachAssignment(
          coachPosition: coach.position!,
          coachType: coach.type!,
          janitorId: isAC ? coach.assignedJanitorId : coach.assignedJanitorId,
          janitorName: isAC ? coach.assignedJanitorName : coach.assignedJanitorName,
          attendantId: isAC ? coach.assignedAttendantId : null,
          attendantName: isAC ? coach.assignedAttendantName : null,
        );
      }).toList();

      if (isEditMode) {
        final updatedInstance = await OBHSRepository.updateRunInstance(
          runInstanceId: widget.editInstance!.runInstanceId ?? widget.editInstance!.id!,
          status: widget.editInstance!.status,
          coaches: apiCoaches,
          departureDate: selectedDepartureDate!,
        );

        if (mounted) {
          setState(() => _isSubmitting = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  'Instance updated successfully with ${coaches.length} coaches!'),
              backgroundColor: kSuccessGreen,
            ),
          );
          Navigator.pop(context, true);
        }
      } else {
        final createdInstance = await OBHSRepository.createRunInstance(
          instanceId: selectedInstance!.instanceId,
          coaches: apiCoaches,
          departureDate: selectedDepartureDate!,
        );

        if (mounted) {
          setState(() => _isSubmitting = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  'Instance created successfully for ${DateFormat('yyyy-MM-dd').format(selectedDepartureDate!)}!'),
              backgroundColor: kSuccessGreen,
            ),
          );
          
          if (stayOnScreen) {
             // Reset for next one but keep train and coaches
             setState(() {
               selectedDepartureDate = null;
               currentStep = 0; // Go back to step 1 to pick next date/instance
             });
          } else {
             Navigator.pop(context, true);
          }
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        final errorMessage = e.toString().replaceAll('Exception: ', '');

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Failed to ${isEditMode ? 'update' : 'create'} instance: $errorMessage'),
            backgroundColor: kErrorRed,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Text(
          isEditMode ? 'Edit Instance' : 'Create Instance',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 22,
          ),
        ),
        backgroundColor: kRailwayBlue,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          if (isEditMode && widget.editInstance != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.orange[50],
                border: Border(
                  bottom: BorderSide(color: Colors.orange[200]!, width: 1),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.edit, color: Colors.orange[700], size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Editing Instance',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.editInstance!.instanceId,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[700],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          _buildStepIndicator(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: currentStep == 0 ? _buildStep1() : _buildStep2(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: currentStep == 0
                ? _buildStep1Actions()
                : _buildStep2Actions(),
          ),
        ],
      ),
    );
  }

  Widget _buildStepIndicator() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      child: Row(
        children: [
          _buildCircle(1, true),
          Expanded(
            child: Container(
              height: 2,
              color: currentStep >= 1 ? kRailwayBlue : Colors.grey[300],
              margin: const EdgeInsets.symmetric(horizontal: 8),
            ),
          ),
          _buildCircle(2, currentStep >= 1),
        ],
      ),
    );
  }

  Widget _buildCircle(int step, bool active) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: active ? kRailwayBlue : Colors.grey[300],
      ),
      child: Center(
        child: Text(
          '$step',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
      ),
    );
  }

  Widget _buildStep1() {
    final selectedTrain = getSelectedTrain();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildInfoBox(
          isEditMode
              ? 'Review instance details and adjust number of coaches'
              : 'Select train, instance and number of coaches',
        ),
        const SizedBox(height: 24),

        if (isEditMode) ...[
          _buildLabel('Train (View Only)'),
          const SizedBox(height: 10),
          _buildViewOnlyTrainCard(),
          const SizedBox(height: 24),

          _buildLabel('Instance (View Only)'),
          const SizedBox(height: 10),
          _buildViewOnlyInstanceCard(),
          const SizedBox(height: 24),
          _buildDatePicker(),
          const SizedBox(height: 24),
          _buildLabel('Number of Coaches (Editable)'),
          const SizedBox(height: 10),
          _buildCoachCountDropdown(),
          const SizedBox(height: 24),
        ] else ...[
          _buildLabel('Select Train'),
          const SizedBox(height: 10),
          _isLoadingTrains
              ? _buildLoadingIndicator()
              : _trainsError != null
                  ? _buildErrorBox(_trainsError!, _loadTrains)
                  : _buildTrainDropdown(),
          const SizedBox(height: 24),

          if (selectedTrain != null) ...[
            _buildLabel('Select Instance'),
            const SizedBox(height: 10),
            _isLoadingInstances
                ? _buildLoadingIndicator()
                : _instancesError != null
                    ? _buildErrorBox(_instancesError!, () =>
                        _loadInstancesForTrain(selectedTrainId!))
                    : trainInstances.isEmpty
                        ? _buildEmptyBox('No instances found for this train')
                        : _buildInstancesList(trainInstances),
            const SizedBox(height: 24),
          ],

          if (selectedInstance != null) ...[
            _buildDatePicker(),
            const SizedBox(height: 10),
            _buildLabel('Number of Coaches'),
            const SizedBox(height: 10),
            _buildCoachCountDropdown(),
            const SizedBox(height: 24),
          ],
        ],
      ],
    );
  }

  Widget _buildLoadingIndicator() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Center(
        child: Column(
          children: [
            const CircularProgressIndicator(
              strokeWidth: 2,
              color: kRailwayBlue,
            ),
            const SizedBox(height: 12),
            Text(
              'Loading...',
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorBox(String error, VoidCallback onRetry) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red[50],
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.red[200]!),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: kErrorRed, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              error,
              style: const TextStyle(fontSize: 12, color: Colors.black87),
            ),
          ),
          TextButton(
            onPressed: onRetry,
            child: const Text('Retry', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyBox(String message) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Center(
        child: Column(
          children: [
            Icon(Icons.inbox_outlined, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 12),
            Text(
              message,
              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTrainDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: selectedTrainId != null ? kRailwayBlue : Colors.grey[300]!,
          width: selectedTrainId != null ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: selectedTrainId,
          hint: Text(
            'Choose a train',
            style: TextStyle(color: Colors.grey[600], fontSize: 13),
          ),
          items: allTrains
              .map((train) => DropdownMenuItem(
                    value: train.uid,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '${train.trainNo} - ${train.trainName}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                        Text(
                          '${train.origin} → ${train.destination}',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ))
              .toList(),
          onChanged: (value) {
            if (value != null) {
              setState(() {
                selectedTrainId = value;
                selectedInstance = null;
              });
              _loadInstancesForTrain(value);
            }
          },
          isExpanded: true,
          icon: Icon(Icons.keyboard_arrow_down, color: kRailwayBlue),
        ),
      ),
    );
  }

  Widget _buildInstancesList(List<RunInstanceModel> instances) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: List.generate(instances.length, (index) {
          final inst = instances[index];
          final isSelected = selectedInstance?.instanceId == inst.instanceId;

          return Column(
            children: [
              InkWell(
                onTap: () {
                  setState(() {
                    selectedInstance = inst;
                    selectedCoachCount = 1;
                  });
                },
                child: Container(
                  padding: const EdgeInsets.all(12),
                  color: isSelected ? Colors.blue[50] : Colors.white,
                  child: Row(
                    children: [
                      Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isSelected ? kRailwayBlue : Colors.grey[400]!,
                            width: isSelected ? 6 : 2,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              inst.instanceId,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Down: ${inst.outboundTrainNo ?? 'N/A'} | Up: ${inst.inboundTrainNo ?? 'N/A'}',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (isSelected)
                        Icon(
                          Icons.check_circle,
                          color: kRailwayBlue,
                          size: 20,
                        ),
                    ],
                  ),
                ),
              ),
              if (index < instances.length - 1)
                Divider(height: 1, color: Colors.grey[200]),
            ],
          );
        }),
      ),
    );
  }

  Widget _buildCoachCountDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey[300]!),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(Icons.train_rounded, color: kRailwayBlue, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: selectedCoachCount,
                items: List.generate(30, (i) => i + 1)
                    .map((c) => DropdownMenuItem(
                          value: c,
                          child: Text(
                            '$c Coach${c > 1 ? 'es' : ''}',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => selectedCoachCount = v);
                },
                isExpanded: true,
                icon: Icon(Icons.keyboard_arrow_down, color: kRailwayBlue),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDatePicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLabel('Departure Date *'),
        const SizedBox(height: 10),
        InkWell(
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: selectedDepartureDate ?? DateTime.now(),
              firstDate: DateTime(2020),
              lastDate: DateTime(2030),
              builder: (context, child) {
                return Theme(
                  data: Theme.of(context).copyWith(
                    colorScheme: ColorScheme.light(
                      primary: kRailwayBlue,
                      onPrimary: Colors.white,
                      surface: Colors.white,
                    ),
                  ),
                  child: child!,
                );
              },
            );
            if (picked != null) {
              setState(() => selectedDepartureDate = picked);
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: selectedDepartureDate != null ? kRailwayBlue : Colors.grey[300]!,
                width: selectedDepartureDate != null ? 1.5 : 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                Icon(Icons.calendar_today, color: kRailwayBlue, size: 18),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    selectedDepartureDate != null
                        ? '${selectedDepartureDate!.day.toString().padLeft(2, '0')}/'
                        '${selectedDepartureDate!.month.toString().padLeft(2, '0')}/'
                        '${selectedDepartureDate!.year}'
                        : 'Select departure date',
                    style: TextStyle(
                      fontSize: 13,
                      color: selectedDepartureDate != null
                          ? Colors.black87
                          : Colors.grey[500],
                      fontWeight: selectedDepartureDate != null
                          ? FontWeight.w500
                          : FontWeight.normal,
                    ),
                  ),
                ),
                if (selectedDepartureDate != null)
                  GestureDetector(
                    onTap: () => setState(() => selectedDepartureDate = null),
                    child: Icon(Icons.close, size: 16, color: Colors.grey[500]),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildViewOnlyTrainCard() {
    final instance = widget.editInstance!;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Row(
        children: [
          Icon(Icons.train, color: Colors.grey[600], size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  instance.trainName ?? 'Train',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: Colors.black87,
                  ),
                ),
                if (instance.trainNo != null)
                  Text(
                    'Train #${instance.trainNo}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
              ],
            ),
          ),
          Icon(Icons.lock, color: Colors.grey[400], size: 16),
        ],
      ),
    );
  }

  Widget _buildViewOnlyInstanceCard() {
    final instance = widget.editInstance!;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Row(
        children: [
          Icon(Icons.tag, color: Colors.grey[600], size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  instance.instanceId,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: Colors.black87,
                  ),
                ),
                if (instance.outboundTrainNo != null ||
                    instance.inboundTrainNo != null)
                  Text(
                    'Down: ${instance.outboundTrainNo ?? 'N/A'} | Up: ${instance.inboundTrainNo ?? 'N/A'}',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey[600],
                    ),
                  ),
              ],
            ),
          ),
          Icon(Icons.lock, color: Colors.grey[400], size: 16),
        ],
      ),
    );
  }

  Widget _buildStep2() {
    if (coaches.isEmpty) return const SizedBox();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildInfoBox('Assign details for all ${coaches.length} coaches'),
        const SizedBox(height: 12),
        _buildProgressBar(),
        const SizedBox(height: 12),

        if (coaches.length > 1) ...[
          _buildQuickFillSection(),
          const SizedBox(height: 12),
        ],

        if (_isLoadingWorkers)
          _buildLoadingIndicator()
        else if (_workersError != null)
          _buildErrorBox(_workersError!, _loadWorkers)
        else
          _buildCoachTable(),
      ],
    );
  }

  Widget _buildCoachTable() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: kRailwayBlue.withOpacity(0.08),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(11),
                topRight: Radius.circular(11),
              ),
            ),
            child: Row(
              children: [
                SizedBox(width: 28, child: Text('#', style: _headerStyle())),
                SizedBox(width: 52, child: Text('Pos', style: _headerStyle())),
                Expanded(flex: 3, child: Text('Type', style: _headerStyle())),
                const SizedBox(width: 8),
                Expanded(flex: 4, child: Text('Worker', style: _headerStyle())),
              ],
            ),
          ),

          ...List.generate(coaches.length, (index) {
            final coach = coaches[index];
            final isComplete = isCoachComplete(coach);
            final isLast = index == coaches.length - 1;

            return Column(
              children: [
                Container(
                  color: isComplete
                      ? Colors.green[50]
                      : index.isEven
                      ? Colors.white
                      : Colors.grey[50],
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 28,
                        child: Text(
                          '${coach.coachNumber}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey[800],
                          ),
                        ),
                      ),

                      SizedBox(
                        width: 52,
                        child: Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: TextFormField(
                            initialValue: coach.position?.toString() ?? '',
                            keyboardType: TextInputType.number,
                            style: const TextStyle(fontSize: 11),
                            decoration: InputDecoration(
                              hintText: 'Pos',
                              hintStyle: TextStyle(fontSize: 10, color: Colors.grey[400]),
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(6),
                                borderSide: BorderSide(color: Colors.grey[300]!),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(6),
                                borderSide: BorderSide(color: Colors.grey[300]!),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(6),
                                borderSide: BorderSide(color: kRailwayBlue, width: 1.5),
                              ),
                            ),
                            onChanged: (v) {
                              setState(() {
                                coach.position = int.tryParse(v.trim());
                              });
                            },
                          ),
                        ),
                      ),

                      Expanded(
                        flex: 3,
                        child: _buildCompactTypeDropdown(coach),
                      ),
                      const SizedBox(width: 8),

                      Expanded(
                        flex: 4,
                        child: _buildCompactWorkerDropdown(coach),
                      ),
                    ],
                  ),
                ),
                if (!isLast) Divider(height: 1, color: Colors.grey[200]),
              ],
            );
          }),
        ],
      ),
    );
  }

  TextStyle _headerStyle() {
    return TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      color: Colors.grey[700],
    );
  }

  Widget _buildQuickFillSection() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.purple[50],
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.purple[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.flash_on, color: Colors.purple[700], size: 16),
              const SizedBox(width: 6),
              Text(
                'Quick Fill',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Colors.purple[900],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildQuickFillButton(
                'All AC',
                () => _applyTypeToAll('AC'),
                Colors.blue,
              ),
              _buildQuickFillButton(
                'All General',
                () => _applyTypeToAll('General'),
                Colors.green,
              ),
              _buildQuickFillButton(
                'All Sleeper',
                () => _applyTypeToAll('Sleeper'),
                Colors.orange,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuickFillButton(String label, VoidCallback onTap, Color color) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: Colors.black,
          ),
        ),
      ),
    );
  }

  void _applyTypeToAll(String type) {
    setState(() {
      for (var coach in coaches) {
        coach.type = type;
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Applied "$type" to all coaches'),
        duration: const Duration(seconds: 1),
        backgroundColor: kRailwayBlue,
      ),
    );
  }

  Widget _buildCompactTypeDropdown(CoachData coach) {
    final availableTypes = [...coachTypes];
    if (coach.type != null && !availableTypes.contains(coach.type)) {
      availableTypes.add(coach.type!);
    }

    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey[300]!),
        borderRadius: BorderRadius.circular(6),
        color: Colors.white,
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: coach.type,
          hint: Text('Type', style: TextStyle(fontSize: 10, color: Colors.grey[500])),
          items: availableTypes
              .map((t) => DropdownMenuItem(
            value: t,
            child: Text(t, style: const TextStyle(fontSize: 11)),
          ))
              .toList(),
          onChanged: (v) => setState(() => coach.type = v),
          isExpanded: true,
          icon: Icon(Icons.arrow_drop_down, size: 16, color: kRailwayBlue),
          isDense: true,
        ),
      ),
    );
  }

  Widget _buildCompactWorkerDropdown(CoachData coach) {
    if (coach.isAC) {
      // AC Coach: Two side-by-side dropdowns for Janitor and Attendant
      return Row(
        children: [
          // Janitor Dropdown
          Expanded(
            flex: 1,
            child: _buildRoleDropdown(
              coach,
              label: 'Janitor',
              role: 'Janitor',
              value: coach.assignedJanitorId,
              onChanged: (v) {
                setState(() {
                  coach.assignedJanitorId = v;
                  if (v != null) {
                    final worker = allWorkers.firstWhere((w) => w.uid == v);
                    coach.assignedJanitorName = worker.fullName;
                  } else {
                    coach.assignedJanitorName = null;
                  }
                });
              },
              isJanitor: true,
            ),
          ),
          const SizedBox(width: 8),
          // Attendant Dropdown
          Expanded(
            flex: 1,
            child: _buildRoleDropdown(
              coach,
              label: 'Attendant',
              role: 'Attendant',
              value: coach.assignedAttendantId,
              onChanged: (v) {
                setState(() {
                  coach.assignedAttendantId = v;
                  if (v != null) {
                    final worker = allWorkers.firstWhere((w) => w.uid == v);
                    coach.assignedAttendantName = worker.fullName;
                  } else {
                    coach.assignedAttendantName = null;
                  }
                });
              },
              isJanitor: false,
            ),
          ),
        ],
      );
    } else {
      // Non-AC Coach: Single dropdown for Janitor only
      return _buildRoleDropdown(
        coach,
        label: 'Janitor',
        role: 'Janitor',
        value: coach.assignedJanitorId,
        onChanged: (v) {
          setState(() {
            coach.assignedJanitorId = v;
            if (v != null) {
              final worker = allWorkers.firstWhere((w) => w.uid == v);
              coach.assignedJanitorName = worker.fullName;
            } else {
              coach.assignedJanitorName = null;
            }
          });
        },
        isJanitor: true,
      );
    }
  }

  Widget _buildRoleDropdown(CoachData coach, {
    required String label,
    required String role,
    required String? value,
    required ValueChanged<String?> onChanged,
    required bool isJanitor,
  }) {
    final workers = allWorkers.where((w) => w.workerType == role).toList();
    
    // Filter out already assigned workers based on role
    final assignedIds = <String>{};
    for (final c in coaches) {
      if (isJanitor) {
        if (c.assignedJanitorId != null && c.assignedJanitorId != value) {
          assignedIds.add(c.assignedJanitorId!);
        }
      } else {
        if (c.assignedAttendantId != null && c.assignedAttendantId != value) {
          assignedIds.add(c.assignedAttendantId!);
        }
      }
    }
    
    // For janitors, filter out those assigned to 3+ coaches
    final availableWorkers = workers.where((w) {
      // For attendants: block if already assigned to another coach
      if (!isJanitor && assignedIds.contains(w.uid)) return false;
      
      if (isJanitor) {
        // Count how many coaches this janitor is already assigned to
        int count = 0;
        for (final c in coaches) {
          if (c.assignedJanitorId == w.uid) count++;
        }
        if (count >= 3) return false; // Janitor max 3 coaches
      } else {
        // Attendant can only be assigned to 1 coach
        if (assignedIds.contains(w.uid)) return false;
      }
      return true;
    }).toList();

    // Ensure current value is in the list (for edit mode)
    if (value != null && !availableWorkers.any((w) => w.uid == value)) {
      final existingWorker = allWorkers.firstWhere((w) => w.uid == value);
      if (existingWorker != null) {
        availableWorkers.insert(0, existingWorker);
      }
    }

    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey[300]!),
        borderRadius: BorderRadius.circular(6),
        color: Colors.white,
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          hint: Text(label, style: TextStyle(fontSize: 10, color: Colors.grey[500])),
          items: availableWorkers
              .map((w) => DropdownMenuItem(
            value: w.uid,
            child: Text(
              '${w.fullName.split(' ')[0]} ${w.trainIds != null && w.trainIds!.isNotEmpty ? '🔗' : ''}',
              style: const TextStyle(fontSize: 11),
              overflow: TextOverflow.ellipsis,
            ),
          ))
              .toList(),
          onChanged: onChanged,
          isExpanded: true,
          icon: Icon(Icons.arrow_drop_down, size: 16, color: kRailwayBlue),
          isDense: true,
        ),
      ),
    );
  }

  Widget _buildProgressBar() {
    int done = coaches.where((c) => isCoachComplete(c)).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Progress',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.grey[700],
              ),
            ),
            Text(
              '$done/${coaches.length}',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: kRailwayBlue,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: coaches.isEmpty ? 0 : done / coaches.length,
            minHeight: 6,
            backgroundColor: Colors.grey[300],
            valueColor: const AlwaysStoppedAnimation<Color>(kRailwayBlue),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoBox(String text) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue[200]!),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: kRailwayBlue, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                color: Colors.blue[900],
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: Colors.black87,
      ),
    );
  }

  Widget _buildStep1Actions() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: () => Navigator.pop(context),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
              side: const BorderSide(color: Colors.grey),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text(
              'Cancel',
              style: TextStyle(
                color: Colors.black87,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton(
            onPressed: canProceedStep1() ? goToStep2 : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: kRailwayBlue,
              disabledBackgroundColor: Colors.grey[300],
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text(
              'Next',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStep2Actions() {
    final completedCount = coaches.where((c) => isCoachComplete(c)).length;
    final canSubmit = allCoachesComplete() && !_isSubmitting;

    return Column(
      children: [
        if (!canSubmit)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: Colors.orange[50],
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.orange[200]!),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: Colors.orange[700], size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Complete all coaches: $completedCount/${coaches.length} done',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.orange[900],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),

        // Action Buttons
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: isEditMode
                    ? () => Navigator.pop(context)
                    : () => setState(() => currentStep = 0),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  side: const BorderSide(color: Colors.grey),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: Text(
                  isEditMode ? 'Cancel' : 'Back',
                  style: const TextStyle(
                    color: Colors.black87,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
            if (!isEditMode) ...[
              Expanded(
                flex: 1,
                child: ElevatedButton(
                  onPressed: canSubmit ? () => submitForm(stayOnScreen: true) : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    side: const BorderSide(color: kRailwayBlue),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: _isSubmitting
                      ? const SizedBox.shrink()
                      : const Text(
                          'Save & Add another',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: kRailwayBlue,
                            fontWeight: FontWeight.w600,
                            fontSize: 10,
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              flex: 2,
              child: ElevatedButton(
                onPressed: canSubmit ? () => submitForm(stayOnScreen: false) : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: kRailwayBlue,
                  disabledBackgroundColor: Colors.grey[300],
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: _isSubmitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
                        ),
                      )
                    : Text(
                        canSubmit
                            ? (isEditMode ? 'Update Instance' : 'Create Instance')
                            : 'Complete All Coaches',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

extension on List {
  T? firstWhereOrNull<T>(bool Function(T) test) {
    try {
      return firstWhere((element) => test(element as T)) as T;
    } catch (e) {
      return null;
    }
  }
}
