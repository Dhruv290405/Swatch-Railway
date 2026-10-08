import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../model/railway_supervisor_model.dart';
import '../model/train_model.dart';
import '../model/cts_form_model.dart';
import '../services/api_services.dart';
import '../controller/contractor_nav_controller.dart';

class CTSFormController extends GetxController {

  final currentStep = 0.obs;
  final isSubmitting = false.obs;
  final isLoadingContracts = false.obs;
  final isLoadingTrains = false.obs;
  final isLoadingSupervisors = false.obs;

  bool isResubmit = false;
  String? formId;
  String? contractorRemarks;
  
  final userRole = Rx<String?>(null);
  final selectedZone = Rx<String?>(null);
  final selectedDivision = Rx<String?>(null);

  final contractUidString = ''.obs;
  final activeTrains = <TrainModel>[].obs;
  final selectedTrain = Rx<TrainModel?>(null);
  final supervisors = <RailwaySupervisor>[].obs;
  final selectedSupervisor = Rx<RailwaySupervisor?>(null);

  final depotName = ''.obs;
  final agreementDate = ''.obs;
  final contractorName = ''.obs;

  final jobDateTime = DateTime.now().obs;

  final actualArrivalDateTime = Rx<DateTime?>(null);

  final actualDepartureDateTime = Rx<DateTime?>(null);

  final workStartDateTime = Rx<DateTime?>(null);

  final workEndDateTime = Rx<DateTime?>(null);

  final selectedDate = DateTime.now().obs;
  final wttScheduledArrival = TimeOfDay.now().obs;
  final wttScheduledDeparture = TimeOfDay.now().obs;
  final actualStartTime = Rx<TimeOfDay?>(null);
  final actualEndTime = Rx<TimeOfDay?>(null);

  final totalTimeTaken = 0.obs;
  final isLate = 'No'.obs;
  final selectedCoachesInRake = 22.obs;
  final selectedCoachesAttended = 22.obs;
  final platformNumber = 1.obs;
  final allowedWindow = 0.obs;

  final staffMembers = <StaffMember>[].obs;

  final garbageDisposed = false.obs;
  final disposalLocationController = TextEditingController();
  final selectedDisposalLocation = 'Pune Station'.obs;
  final occupiedToiletsCount = 0.obs;
  final notesController = TextEditingController();
  final contractorRemarksController = TextEditingController();

  final signedBy = Rx<String?>(null);
  final signedAt = Rx<DateTime?>(null);

  @override
  void onInit() {
    super.onInit();
    loadContracts();
    fetchSupervisors();
    loadActiveTrains();

    ever(actualStartTime, (_) => _calculateTotalTime());
    ever(actualEndTime, (_) => _calculateTotalTime());

    ever(actualArrivalDateTime, (DateTime? arrivalTime) {
      if (arrivalTime != null && workStartDateTime.value == null) {
        workStartDateTime.value = arrivalTime;
      }
      _calculateAllowedWindow();
    });

    ever(actualDepartureDateTime, (DateTime? departureTime) {
      if (departureTime != null && workEndDateTime.value == null) {
        workEndDateTime.value = departureTime;
      }
      _calculateAllowedWindow();
    });

    ever(workStartDateTime, (_) => _calculateAllowedWindow());
    ever(workEndDateTime, (_) => _calculateAllowedWindow());

    ever(selectedCoachesInRake, (int rakeCount) {
      if (selectedCoachesAttended.value > rakeCount) {
        selectedCoachesAttended.value = rakeCount;
      }
    });

    ever(selectedTrain, (TrainModel? train) {
      if (train != null) {
        final now = DateTime.now();
        if (actualArrivalDateTime.value == null) {
          actualArrivalDateTime.value = now;
        }
        if (actualDepartureDateTime.value == null) {
          actualDepartureDateTime.value = now.add(const Duration(minutes: 30));
        }
      }
    });
  }

  void _calculateTotalTime() {
    if (actualStartTime.value != null && actualEndTime.value != null) {
      final start = DateTime(
        selectedDate.value.year,
        selectedDate.value.month,
        selectedDate.value.day,
        actualStartTime.value!.hour,
        actualStartTime.value!.minute,
      );
      final end = DateTime(
        selectedDate.value.year,
        selectedDate.value.month,
        selectedDate.value.day,
        actualEndTime.value!.hour,
        actualEndTime.value!.minute,
      );
      totalTimeTaken.value = end.difference(start).inMinutes;
    }
  }

  void _calculateAllowedWindow() {
    if (workStartDateTime.value != null && workEndDateTime.value != null) {
      final diff = workEndDateTime.value!.difference(workStartDateTime.value!);
      allowedWindow.value = diff.inMinutes;
    }
  }

  @override
  void onClose() {
    disposalLocationController.dispose();
    notesController.dispose();
    contractorRemarksController.dispose();
    for (var staff in staffMembers) {
      staff.dispose();
    }
    super.onClose();
  }

  Future<void> loadContracts() async {
    try {
      isLoadingContracts.value = true;
      final prefs = await SharedPreferences.getInstance();
      final userJson = prefs.getString('currentUser');

      if (userJson == null) {
        return;
      }

      final user = jsonDecode(userJson);
      final entityId = user['entityId'];
      final zone = user['zone'] ?? '';
      final division = user['division'] ?? '';
      
      userRole.value = user['role'];

      depotName.value = user['depot'] ?? 'N/A';
      contractorName.value = user['fullName'] ?? user['name'] ?? 'N/A';

      if (entityId == null || entityId.toString().isEmpty) {
        return;
      }

      final contractsList = await ApiService.getContractsByStatus(
        entityId,
        zone,
        division,
      );

      if (contractsList.isEmpty) {
        throw Exception('No contracts found');
      }

      // Prefer an active contract that covers CTS work — the backend rejects
      // the form otherwise.
      final eligible = contractsList.where((c) {
        final cats = (c.workCategories ?? '').toLowerCase();
        final type = (c.contractType ?? '').toLowerCase();
        return cats.contains('cts') || type == 'cts';
      }).toList();
      final activeEligible = eligible.where((c) => c.isActive == true).toList();
      final pool = activeEligible.isNotEmpty
          ? activeEligible
          : (eligible.isNotEmpty ? eligible : contractsList);

      contractUidString.value = pool.first.uid.toString();

      if (pool.first.startDate != null) {
        agreementDate.value = pool.first.startDate!;
      }
    } catch (e) {
      debugPrint('Failed to load contracts: $e');
    } finally {
      isLoadingContracts.value = false;
    }
  }

  Future<void> loadActiveTrains() async {
    try {
      isLoadingTrains.value = true;
      final trains = await ApiService.getCTSTrains();
      activeTrains.value = trains;
    } catch (e) {
      print('Failed to load trains: $e');
    } finally {
      isLoadingTrains.value = false;
    }
  }


  Future<void> fetchSupervisors({String? zone, String? division}) async {
    try {
      isLoadingSupervisors.value = true;
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');

      if (token == null) {
        throw Exception('No token found — please log in again.');
      }

      String urlStr = '${ApiService.baseUrl}/api/users/railway-supervisors';
      if (zone != null || division != null) {
        final queryParams = <String>[];
        if (zone != null) queryParams.add('zone=$zone');
        if (division != null) queryParams.add('division=$division');
        urlStr += '?${queryParams.join('&')}';
      }

      final url = Uri.parse(urlStr);
      final response = await http.get(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List supervisorsList = data['supervisors'];
        supervisors.value = supervisorsList
            .map((e) => RailwaySupervisor.fromJson(e))
            .toList();
        if (selectedSupervisor.value != null && !supervisors.any((s) => s.uid == selectedSupervisor.value!.uid)) {
          selectedSupervisor.value = null;
        }
      } else {
        throw Exception('Failed to load supervisors: ${response.statusCode}');
      }
    } catch (e) {
      print('Failed to load supervisors: $e');
    } finally {
      isLoadingSupervisors.value = false;
    }
  }

  void updateStaffCount(int count) {
    while (staffMembers.length > count) {
      staffMembers.last.dispose();
      staffMembers.removeLast();
    }

    while (staffMembers.length < count) {
      staffMembers.add(
        StaffMember(
          nameController: TextEditingController(),
          staffIdController: TextEditingController(),
          roleController: TextEditingController(),
          remarksController: TextEditingController(),
        ),
      );
    }
  }

  bool validateStep1() {
    if (selectedTrain.value == null) {
      Get.snackbar(
        'Validation Error',
        'Please select a train',
        snackPosition: SnackPosition.BOTTOM,
      );
      return false;
    }
    if (actualArrivalDateTime.value == null) {
      Get.snackbar(
        'Validation Error',
        'Please enter actual arrival date & time',
        snackPosition: SnackPosition.BOTTOM,
      );
      return false;
    }
    if (actualDepartureDateTime.value == null) {
      Get.snackbar(
        'Validation Error',
        'Please enter actual departure date & time',
        snackPosition: SnackPosition.BOTTOM,
      );
      return false;
    }
    if (workStartDateTime.value == null) {
      Get.snackbar(
        'Validation Error',
        'Please enter work start date & time',
        snackPosition: SnackPosition.BOTTOM,
      );
      return false;
    }
    if (workEndDateTime.value == null) {
      Get.snackbar(
        'Validation Error',
        'Please enter work end date & time',
        snackPosition: SnackPosition.BOTTOM,
      );
      return false;
    }
    if (selectedCoachesAttended.value > selectedCoachesInRake.value) {
      Get.snackbar(
        'Validation Error',
        'Coaches attended cannot exceed coaches in rake',
        snackPosition: SnackPosition.BOTTOM,
      );
      return false;
    }
    return true;
  }

  bool validateStep2() {
    if (staffMembers.isEmpty) {
      Get.snackbar(
        'Validation Error',
        'Please add at least one staff member',
        snackPosition: SnackPosition.BOTTOM,
      );
      return false;
    }
    for (var staff in staffMembers) {
      if (staff.nameController.text.trim().isEmpty) {
        Get.snackbar(
          'Validation Error',
          'Staff name is required',
          snackPosition: SnackPosition.BOTTOM,
        );
        return false;
      }
    }
    return true;
  }

  bool validateStep3() {
    if (garbageDisposed.value &&
        selectedDisposalLocation.value.isEmpty) {
      Get.snackbar(
        'Validation Error',
        'Please select disposal location',
        snackPosition: SnackPosition.BOTTOM,
      );
      return false;
    }
    return true;
  }

  void nextStep() {
    if (currentStep.value == 0 && !validateStep1()) return;
    if (currentStep.value == 1 && !validateStep2()) return;
    if (currentStep.value == 2 && !validateStep3()) return;

    if (currentStep.value < 3) {
      currentStep.value++;
    }
  }

  void previousStep() {
    if (currentStep.value > 0) {
      currentStep.value--;
    }
  }

  Future<void> selectTime(
    BuildContext context,
    Rx<TimeOfDay?> timeObservable,
    TimeOfDay? initialTime,
  ) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: initialTime ?? TimeOfDay.now(),
    );
    if (picked != null) {
      timeObservable.value = picked;
    }
  }

  Future<void> selectDateTime(
    BuildContext context,
    Rx<DateTime?> dateTimeObservable,
    {DateTime? initialDateTime}
  ) async {
    final initial = initialDateTime ?? dateTimeObservable.value ?? DateTime.now();

    final pickedDate = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );

    if (pickedDate != null) {
      final pickedTime = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(initial),
      );

      if (pickedTime != null) {
        final newDateTime = DateTime(
          pickedDate.year,
          pickedDate.month,
          pickedDate.day,
          pickedTime.hour,
          pickedTime.minute,
        );

        if (dateTimeObservable == actualDepartureDateTime) {
          if (actualArrivalDateTime.value != null &&
              newDateTime.isBefore(actualArrivalDateTime.value!)) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Departure time cannot be before arrival time'),
                  backgroundColor: Colors.red,
                ),
              );
            }
            return;
          }
        }

        if (dateTimeObservable == workEndDateTime) {
          if (workStartDateTime.value != null &&
              newDateTime.isBefore(workStartDateTime.value!)) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Work end time cannot be before work start time'),
                  backgroundColor: Colors.red,
                ),
              );
            }
            return;
          }
        }

        dateTimeObservable.value = newDateTime;
      }
    }
  }

  Future<void> selectJobDateTime(BuildContext context) async {
    final initial = jobDateTime.value;

    final pickedDate = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );

    if (pickedDate != null) {
      final pickedTime = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(initial),
      );

      if (pickedTime != null) {
        jobDateTime.value = DateTime(
          pickedDate.year,
          pickedDate.month,
          pickedDate.day,
          pickedTime.hour,
          pickedTime.minute,
        );
      }
    }
  }

  Future<void> openSignDialog() async {
    final controller = TextEditingController();
    final result = await Get.dialog<String>(
      AlertDialog(
        title: const Text('Provide digital signature (type name)'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'Your full name'),
        ),
        actions: [
          TextButton(onPressed: () => Get.back(), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Get.back(result: controller.text.trim()),
            child: const Text('Sign'),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      signedBy.value = result;
      signedAt.value = DateTime.now();
    }
  }

  void resetForm() {
    selectedTrain.value = null;
    selectedSupervisor.value = null;
    jobDateTime.value = DateTime.now();
    actualArrivalDateTime.value = null;
    actualDepartureDateTime.value = null;
    workStartDateTime.value = null;
    workEndDateTime.value = null;
    selectedDate.value = DateTime.now();
    selectedCoachesInRake.value = 22;
    selectedCoachesAttended.value = 22;
    platformNumber.value = 1;
    allowedWindow.value = 0;
    isLate.value = 'No';

    for (var staff in staffMembers) {
      staff.dispose();
    }
    staffMembers.clear();

    garbageDisposed.value = false;
    selectedDisposalLocation.value = 'Pune Station';
    occupiedToiletsCount.value = 0;
    notesController.clear();

    signedBy.value = null;
    signedAt.value = null;

    currentStep.value = 0;
  }

  Future<void> loadExistingForm(CTSForm form) async {
    isResubmit = true;
    formId = form.uid;
    contractorRemarks = form.rejectionComments ?? '';

    await loadActiveTrains();

    if (form.trainNumber.isNotEmpty) {
      final train = activeTrains.firstWhereOrNull(
        (t) => t.trainNo == form.trainNumber,
      );
      if (train != null) {
        selectedTrain.value = train;
      }
    }

    if (form.submittedTo.railwayEmployeeId.isNotEmpty) {
      final supervisor = supervisors.firstWhereOrNull(
        (s) => s.uid == form.submittedTo.railwayEmployeeId,
      );
      if (supervisor != null) {
        selectedSupervisor.value = supervisor;
      }
    }

    try {
      if (form.formDateTime.isNotEmpty) {
        jobDateTime.value = DateTime.parse(form.formDateTime);
      }
      if (form.actArrival.isNotEmpty) {
        actualArrivalDateTime.value = DateTime.parse(form.actArrival);
      }
      if (form.actDeparture.isNotEmpty) {
        actualDepartureDateTime.value = DateTime.parse(form.actDeparture);
      }
      if (form.workStart.isNotEmpty) {
        workStartDateTime.value = DateTime.parse(form.workStart);
      }
      if (form.workEnd.isNotEmpty) {
        workEndDateTime.value = DateTime.parse(form.workEnd);
      }
    } catch (e) {
      print('Error parsing dates: $e');
    }

    selectedCoachesInRake.value = form.coachesInRake;
    selectedCoachesAttended.value = form.coachesAttended;
    platformNumber.value = int.tryParse(form.platform) ?? 1;
    allowedWindow.value = int.tryParse(form.allowedWindow) ?? 0;
    isLate.value = form.lateYN;

    staffMembers.clear();
    for (var staff in form.attendanceStaff) {
      staffMembers.add(StaffMember(
        nameController: TextEditingController(text: staff.name),
        staffIdController: TextEditingController(text: staff.staffId),
        roleController: TextEditingController(text: staff.role),
        remarksController: TextEditingController(text: staff.remarks),
      ));
    }

    garbageDisposed.value = form.garbageDisposed;

    if (form.nominatedLocation.isNotEmpty) {
      selectedDisposalLocation.value = form.nominatedLocation;
    } else {
      selectedDisposalLocation.value = 'Pune Station';
    }

    selectedDisposalLocation.value = form.nominatedLocation.isNotEmpty
        ? form.nominatedLocation
        : 'Pune Station';
    occupiedToiletsCount.value = form.occupiedToilets;
    notesController.text = form.notes;
  }

  Future<void> submitForm(BuildContext context) async {
    if (selectedSupervisor.value == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a railway employee to submit to'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    if (signedBy.value == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please provide digital signature before submit'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    try {
      isSubmitting.value = true;

      final duration = workEndDateTime.value != null && workStartDateTime.value != null
          ? workEndDateTime.value!.difference(workStartDateTime.value!).inMinutes
          : 0;

      List<Map<String, String>> attendance = staffMembers.map((s) {
        return {
          'name': s.nameController.text.trim(),
          'staffId': s.staffIdController.text.trim(),
          'role': s.roleController.text.trim(),
          'remarks': s.remarksController.text.trim(),
        };
      }).toList();

      if (isResubmit && formId != null) {
        await ApiService.resubmitCTSForm(
          formId: formId!,
          contractorRemarks: contractorRemarksController.text.trim(),
          trainId: selectedTrain.value!.uid ?? '',
          trainNumber: selectedTrain.value!.trainNo ?? '',
          trainName: selectedTrain.value!.trainName ?? '',
          formDateTime: jobDateTime.value.toIso8601String(),
          actArrival: actualArrivalDateTime.value?.toIso8601String() ?? '',
          actDeparture: actualDepartureDateTime.value?.toIso8601String() ?? '',
          workStart: workStartDateTime.value?.toIso8601String() ?? '',
          workEnd: workEndDateTime.value?.toIso8601String() ?? '',
          platform: platformNumber.value.toString(),
          allowedWindow: allowedWindow.value.toString(),
          lateYN: isLate.value,
          coachesInRake: selectedCoachesInRake.value,
          coachesAttended: selectedCoachesAttended.value,
          attendanceStaff: attendance,
          garbageDisposed: garbageDisposed.value,
          nominatedLocation: garbageDisposed.value ? selectedDisposalLocation.value : '',
          occupiedToilets: occupiedToiletsCount.value,
          notes: notesController.text.trim(),
          resubmitSign: {
            'name': signedBy.value!,
            'date': signedAt.value!.toIso8601String(),
          },
        );
      } else {
        await ApiService.submitCTSForm(
          trainId: selectedTrain.value!.uid ?? '',
          contractId: contractUidString.value,
          formDateTime: jobDateTime.value.toIso8601String(),
          platform: platformNumber.value.toString(),
          actArrival: actualArrivalDateTime.value?.toIso8601String() ?? '',
          actDeparture: actualDepartureDateTime.value?.toIso8601String() ?? '',
          workStart: workStartDateTime.value?.toIso8601String() ?? '',
          workEnd: workEndDateTime.value?.toIso8601String() ?? '',
          allowedWindow: allowedWindow.value.toString(),
          lateYN: isLate.value,
          coachesInRake: selectedCoachesInRake.value,
          coachesAttended: selectedCoachesAttended.value,
          attendanceStaff: attendance,
          garbageDisposed: garbageDisposed.value,
          nominatedLocation: garbageDisposed.value ? selectedDisposalLocation.value : '',
          occupiedToilets: occupiedToiletsCount.value,
          notes: notesController.text.trim(),
          submittedTo: {
            'railwayEmployeeId': selectedSupervisor.value!.uid,
            'division': (selectedDivision.value ?? '').trim().isNotEmpty
                ? selectedDivision.value!.trim()
                : (selectedSupervisor.value?.division ?? ''),
            'depot': selectedSupervisor.value?.depot ?? '',
          },
          signature: {
            'name': signedBy.value!,
            'date': signedAt.value!.toIso8601String(),
          },
        );
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isResubmit
                  ? 'CTS Form resubmitted successfully!'
                  : 'CTS Form submitted successfully!',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }

      resetForm();

      // Navigate back to root and switch to Forms tab with CTS inner tab
      final navController = Get.find<ContractorNavController>();
      navController.navigateToFormsTab(2); // CTS tab (index 2)

      // Pop all screens until we reach the root
      if (context.mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to submit form: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      isSubmitting.value = false;
    }
  }
}

class StaffMember {
  final TextEditingController nameController;
  final TextEditingController staffIdController;
  final TextEditingController roleController;
  final TextEditingController remarksController;

  StaffMember({
    required this.nameController,
    required this.staffIdController,
    required this.roleController,
    required this.remarksController,
  });

  void dispose() {
    nameController.dispose();
    staffIdController.dispose();
    roleController.dispose();
    remarksController.dispose();
  }
}
