import 'dart:convert';
import 'package:crm_train/model/coach_form_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:math';
import '../../../../model/railway_supervisor_model.dart';
import '../../../../model/train_model.dart';
import '../../../../providers/auth_provider.dart';
import '../../../../services/api_services.dart';
import '../../../../services/draft_storage_service.dart';
import '../../../../data/zone_database.dart';


class NewCoachFormScreen extends StatefulWidget {
  final CoachForm? existingForm;
  final bool isResubmit;
  final Map<String, dynamic>? draftData;

  const NewCoachFormScreen({
    super.key,
    this.existingForm,
    this.isResubmit = false,
    this.draftData,
  });

  @override
  State<NewCoachFormScreen> createState() => _NewCoachFormScreenState();
}

class _NewCoachFormScreenState extends State<NewCoachFormScreen> {

  final _formKey = GlobalKey<FormState>();
  bool _isSubmitting = false;
  int _currentStep = 0;
  List<RailwaySupervisor> _supervisors = [];
  RailwaySupervisor? _selectedSupervisor;
  bool _isLoading = false;
  bool isLoadingContracts = false;
  String contractUidString = "";
  late final List<FocusNode> _chemicalFocusNodes;
  String? _currentDraftId;
  String? _userRole;
  String? _selectedZone;
  String? _selectedDivision;
  final TextEditingController _divisionController = TextEditingController();
  bool _divisionEdited = false;




  List<TrainModel> _activeTrains = [];
  TrainModel? _selectedTrain;
  bool _isLoadingTrains = false;

  DateTime _selectedDate = DateTime.now();
  TimeOfDay _selectedTime = TimeOfDay.now();
  int _selectedCoaches = 1;


  final TextEditingController spiralController = TextEditingController();
  final TextEditingController r3Controller = TextEditingController();
  final TextEditingController r7r2Controller = TextEditingController();
  final TextEditingController r5Controller = TextEditingController();
  final TextEditingController r1r6Controller = TextEditingController();
  final TextEditingController triadController = TextEditingController();
  final TextEditingController sumaController = TextEditingController();

  Future<void> _loadContracts() async {
    final provider = Provider.of<AuthProvider>(context, listen: false);
    final user = provider.currentUser;

    if (user?.entityId == null && user?.role != 'SUPER_ADMIN') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("User entity information not found")),
      );
      return;
    }

    setState(() {
      _userRole = user?.role;
      isLoadingContracts = true;
    });

    try {
      final contractsList = await ApiService.getContractsByStatus(
        user!.entityId!,
        user.zone ?? '',
        user.division ?? '',
      );

      if (contractsList.isEmpty) {
        throw Exception('No contracts found');
      }

      // Prefer an active contract whose work categories allow coach cleaning —
      // the backend rejects the form otherwise ("This Contract does not allow
      // Coach Cleaning work."). Fall back to the first contract only if no
      // category-specific match exists.
      final eligible = contractsList.where((c) {
        final cats = (c.workCategories ?? '').toLowerCase();
        final type = (c.contractType ?? '').toLowerCase();
        return cats.contains('coach') || type == 'coach';
      }).toList();
      final activeEligible = eligible.where((c) => c.isActive == true).toList();
      final pool = activeEligible.isNotEmpty
          ? activeEligible
          : (eligible.isNotEmpty ? eligible : contractsList);

      // Take first contract ID only (API expects single ID, not comma-separated)
      contractUidString = pool.first.uid.toString();

      print("Contract ID for API: $contractUidString");

      setState(() => isLoadingContracts = false);
    } catch (e) {
      setState(() => isLoadingContracts = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error loading contracts: $e")),
        );
      }
    }
  }




  bool _validateStep3() {
    final List<Map<String, dynamic>> fields = [
      {'label': 'Spiral', 'controller': spiralController},
      {'label': 'R3', 'controller': r3Controller},
      {'label': 'R7/R2', 'controller': r7r2Controller},
      {'label': 'R5', 'controller': r5Controller},
      {'label': 'R1/R6', 'controller': r1r6Controller},
      {'label': 'TRIAD-III', 'controller': triadController},
      {'label': 'Suma lnox', 'controller': sumaController},
    ];

    final reg = RegExp(r'^\d{1,4}(\.\d{1,2})?$');

    for (var f in fields) {
      final text = f['controller'].text.trim();
      if (text.isEmpty) {
        _showSnack('${f['label']} quantity is required');
        return false;
      }
      if (!reg.hasMatch(text)) {
        _showSnack('Invalid value for ${f['label']} (use numbers up to 2 decimals)');
        return false;
      }
    }

    return true;
  }

  void _nextStep() {
    if (_currentStep == 0) {
      if (!_validateStep1()) return;
    } else if (_currentStep == 2) {
      if (!_validateStep3()) return;
    } else if (_currentStep == 3) {
      if (!_validateStep4()) return;
    }

    setState(() => _currentStep = min(4, _currentStep + 1));
  }

  Future<void> _loadActiveTrains() async {
    setState(() {
      _isLoadingTrains = true;
    });

    try {
      final trains = await ApiService.getActiveTrains();
      setState(() {
        _activeTrains = trains;
        _isLoadingTrains = false;
      });
    } catch (e) {
      setState(() {
        _isLoadingTrains = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading trains: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  final List<_MachineItem> _machines = [
    _MachineItem('High-pressure Jet'),
    _MachineItem('High-pressure Jet (Small)'),
    _MachineItem('Single Disc'),
    _MachineItem('Handheld Scrubber'),
    _MachineItem('Wet & Dry Vacuum'),
    _MachineItem('Buffing'),
    _MachineItem('Form Cleaning'),
    _MachineItem('Steam Machine'),
  ];

  final List<_ChemicalRow> _chemicals = [
    _ChemicalRow(nameController: TextEditingController(), qtyController: TextEditingController()),
  ];

  final List<_EmployeeRow> _employees = [];
  int _selectedEmployeeCount = 1;

  String? _signedBy;
  DateTime? _signedAt;
  String? _resubmitSignedBy;
  DateTime? _resubmitSignedAt;
  final TextEditingController contractorRemarksController = TextEditingController();



  void _backStep() {
    setState(() => _currentStep = max(0, _currentStep - 1));
  }

  bool _validateStep1() {
    if (_selectedTrain == null ) {
      _showSnack('Please select a train');
      return false;
    }
    return true;
  }


  bool _validateStep4() {
    if (widget.isResubmit) {
      if (contractorRemarksController.text.trim().isEmpty) {
        _showSnack('Please provide contractor remarks before proceeding');
        return false;
      }
    }
    if (_employees.length > 22) {
      _showSnack('Maximum 22 employees allowed');
      return false;
    }
    for (var e in _employees) {
      if (e.nameController.text.trim().isEmpty) {
        _showSnack('Employee name required');
        return false;
      }
    }
    return true;
  }

  void _showSnack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));


  void _updateEmployeeCount(int count) {
    setState(() {
      while (_employees.length > count) {
        _employees.last.dispose();
        _employees.removeLast();
      }

      while (_employees.length < count) {
        _employees.add(_EmployeeRow(
          nameController: TextEditingController(),
          designationController: TextEditingController(),
          remarkController: TextEditingController(),
        ));
      }

      _selectedEmployeeCount = count;
    });
  }

  Future<void> _fetchSupervisors({String? zone, String? division}) async {
    setState(() => _isLoading = true);
    try {
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
        final List supervisors = data['supervisors'];
        setState(() {
          _supervisors =
              supervisors.map((e) => RailwaySupervisor.fromJson(e)).toList();
          // Reset selected supervisor if it's no longer in the list
          if (_selectedSupervisor != null && !_supervisors.any((s) => s.uid == _selectedSupervisor!.uid)) {
            _selectedSupervisor = null;
          }
        });
      } else {
        throw Exception('Failed to load supervisors: ${response.statusCode}');
      }
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _openSignDialog() async {
    final controller = TextEditingController();
    final res = await showDialog<String?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Provide digital signature (type name)'),
        content:
        TextField(controller: controller, decoration: const InputDecoration(hintText: 'Your full name')),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(null), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.of(ctx).pop(controller.text.trim()), child: const Text('Sign')),
        ],
      ),
    );

    if (res != null && res.isNotEmpty) {
      setState(() {
        _signedBy = res;
        _signedAt = DateTime.now();
      });
      _showSnack('Signed by $_signedBy');
    }
  }

  Future<void> _openResubmitSignDialog() async {
    final controller = TextEditingController();
    final res = await showDialog<String?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Provide resubmit signature (type name)'),
        content:
        TextField(controller: controller, decoration: const InputDecoration(hintText: 'Your full name')),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(null), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.of(ctx).pop(controller.text.trim()), child: const Text('Sign')),
        ],
      ),
    );

    if (res != null && res.isNotEmpty) {
      setState(() {
        _resubmitSignedBy = res;
        _resubmitSignedAt = DateTime.now();
      });
      _showSnack('Signed by $_resubmitSignedBy');
    }
  }

  Future<void> _loadDraftData(Map<String, dynamic> draftData) async {
    _currentDraftId = draftData['draftId'];

    setState(() {
      if (draftData['trainId'] != null && draftData['trainId'].toString().isNotEmpty) {
        _selectedTrain = _activeTrains.firstWhere(
              (t) => t.uid == draftData['trainId'],
          orElse: () => TrainModel(
            trainName: draftData['trainName'] ?? '',
            trainNo: draftData['trainNo'] ?? '',
            uid: draftData['trainId'] ?? '',
            days: [],
            zone: '',
            division: '',
            status: 'active',
          ),
        );
      }

      if (draftData['selectedDate'] != null) {
        _selectedDate = DateTime.parse(draftData['selectedDate']);
      }
      if (draftData['selectedTime'] != null) {
        final timeParts = draftData['selectedTime'].toString().split(':');
        _selectedTime = TimeOfDay(
          hour: int.parse(timeParts[0]),
          minute: int.parse(timeParts[1]),
        );
      }

      _selectedCoaches = draftData['coachCount'] ?? 1;

      if (draftData['machinesUsed'] != null) {
        final List<String> usedMachines = List<String>.from(draftData['machinesUsed']);
        for (var machine in _machines) {
          machine.selected = usedMachines.contains(machine.name);
        }
      }

      if (draftData['chemicals'] != null) {
        final chemicals = draftData['chemicals'];
        spiralController.text = chemicals['spiral']?.toString() ?? '';
        r3Controller.text = chemicals['r3']?.toString() ?? '';
        r7r2Controller.text = chemicals['r7_r2']?.toString() ?? '';
        r5Controller.text = chemicals['r5']?.toString() ?? '';
        r1r6Controller.text = chemicals['r1_r6']?.toString() ?? '';
        triadController.text = chemicals['triad_iii']?.toString() ?? '';
        sumaController.text = chemicals['suma_inox']?.toString() ?? '';
      }

      if (draftData['manpower'] != null) {
        _employees.clear();
        final List manpower = draftData['manpower'];
        for (var emp in manpower) {
          _employees.add(_EmployeeRow(
            nameController: TextEditingController(text: emp['name'] ?? ''),
            designationController: TextEditingController(text: emp['designation'] ?? ''),
            remarkController: TextEditingController(text: emp['remark'] ?? ''),
          ));
        }
      }

      if (draftData['supervisorId'] != null && _supervisors.isNotEmpty) {
        _selectedSupervisor = _supervisors.firstWhere(
              (s) => s.uid == draftData['supervisorId'],
          orElse: () => _supervisors.first,
        );
      }
    });
  }

  Future<void> _saveDraft() async {
    try {
      final user = Provider.of<AuthProvider>(context, listen: false).currentUser;

      List<String> machinesUsed = _machines
          .where((m) => m.selected)
          .map((m) => m.name)
          .toList();

      Map<String, double> chemicals = {
        'spiral': double.tryParse(spiralController.text.trim()) ?? 0.0,
        'r3': double.tryParse(r3Controller.text.trim()) ?? 0.0,
        'r7_r2': double.tryParse(r7r2Controller.text.trim()) ?? 0.0,
        'r5': double.tryParse(r5Controller.text.trim()) ?? 0.0,
        'r1_r6': double.tryParse(r1r6Controller.text.trim()) ?? 0.0,
        'triad_iii': double.tryParse(triadController.text.trim()) ?? 0.0,
        'suma_inox': double.tryParse(sumaController.text.trim()) ?? 0.0,
      };

      List<Map<String, String>> manpower = _employees.map((e) {
        return {
          'name': e.nameController.text.trim(),
          'designation': e.designationController.text.trim(),
          'remark': e.remarkController.text.trim(),
        };
      }).toList();

      final draftData = {
        'trainId': _selectedTrain?.uid ?? '',
        'trainName': _selectedTrain?.trainName ?? '',
        'trainNo': _selectedTrain?.trainNo ?? '',
        'selectedDate': _selectedDate.toIso8601String(),
        'selectedTime': '${_selectedTime.hour}:${_selectedTime.minute}',
        'coachCount': _selectedCoaches,
        'machinesUsed': machinesUsed,
        'chemicals': chemicals,
        'manpower': manpower,
        'supervisorId': _selectedSupervisor?.uid ?? '',
        'supervisorName': _selectedSupervisor?.fullName ?? '',
        'division': _selectedSupervisor?.division ?? user?.division ?? '',
        'depot': _selectedSupervisor?.depot ?? user?.depot ?? '',
        'submittedByName': user?.fullName ?? '',
        // 'submittedByEntityName': user?.entityDetails ?? '',
        'isDraft': true,
      };


      await DraftStorageService.saveDraft(draftData, existingDraftId: _currentDraftId);

      if (_currentDraftId != null) {
        _showSnack('Draft updated successfully!');
      } else {
        _showSnack('Draft saved successfully!');
      }

      Navigator.of(context).pop(true);
    } catch (e) {
      _showSnack('Error saving draft: $e');
    }
  }

  void _submitForm() async {
    if (widget.isResubmit) {
      _resubmitForm();
      return;
    }


    final String? draftIdToDelete = _currentDraftId;

    if (_selectedSupervisor == null) {
      _showSnack('Select a railway employee to submit to');
      return;
    }
    if (_signedBy == null) {
      _showSnack('Please provide digital signature before submit');
      return;
    }
    if (_selectedTrain == null) {
      _showSnack('Please select a train');
      return;
    }
    if (contractUidString.trim().isEmpty) {
      _showSnack(
          'No contract linked to your account. Contact your administrator to link a Coach Cleaning contract, then reopen this form.');
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      List<String> machinesUsed = _machines
          .where((m) => m.selected)
          .map((m) => m.name)
          .toList();

      Map<String, double> chemicals = {
        'spiral': double.tryParse(spiralController.text.trim()) ?? 0.0,
        'r3': double.tryParse(r3Controller.text.trim()) ?? 0.0,
        'r7_r2': double.tryParse(r7r2Controller.text.trim()) ?? 0.0,
        'r5': double.tryParse(r5Controller.text.trim()) ?? 0.0,
        'r1_r6': double.tryParse(r1r6Controller.text.trim()) ?? 0.0,
        'triad_iii': double.tryParse(triadController.text.trim()) ?? 0.0,
        'suma_inox': double.tryParse(sumaController.text.trim()) ?? 0.0,
      };

      List<Map<String, String>> manpower = _employees.map((e) {
        return {
          'name': e.nameController.text.trim(),
          'designation': e.designationController.text.trim(),
          'remark': e.remarkController.text.trim(),
        };
      }).toList();

      final dateTime = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
        _selectedTime.hour,
        _selectedTime.minute,
      );
      final formDateTime = dateTime.toUtc().toIso8601String();

      Map<String, String> submittedTo = {
        'railwayEmployeeId': _selectedSupervisor!.uid,
        'division': _divisionController.text.trim().isNotEmpty
            ? _divisionController.text.trim()
            : (_selectedSupervisor!.division ?? ''),
        'depot': _selectedSupervisor!.depot ?? '',
      };

      Map<String, String> signature = {
        'name': _signedBy!,
        'date': _signedAt!.toIso8601String().split('T')[0],
      };

      final response = await ApiService.submitCoachForm(
        trainId: _selectedTrain!.uid ?? '',
        contractId: contractUidString,
        formDateTime: formDateTime,
        coachCount: _selectedCoaches,
        machinesUsed: machinesUsed,
        chemicals: chemicals,
        manpower: manpower,
        submittedTo: submittedTo,
        signature: signature,
      );

      setState(() => _isSubmitting = false);

      if (draftIdToDelete != null) {
        await DraftStorageService.deleteDraft(draftIdToDelete);
      }

      if (mounted) {
        _showSnack('Coach Form submitted successfully! UID: ${response['uid']}');

        await Future.delayed(const Duration(seconds: 2));
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      setState(() => _isSubmitting = false);

      if (mounted) {
        _showSnack('Error submitting form: $e');
      }
    }
  }

  void _resubmitForm() async {
    if (contractorRemarksController.text.trim().isEmpty) {
      _showSnack('Please provide contractor remarks');
      return;
    }

    if (_resubmitSignedBy == null) {
      _showSnack('Please provide resubmit signature');
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      List<String> machinesUsed = _machines
          .where((m) => m.selected)
          .map((m) => m.name)
          .toList();


      Map<String, double> chemicals = {
        'spiral': double.tryParse(spiralController.text.trim()) ?? 0.0,
        'r3': double.tryParse(r3Controller.text.trim()) ?? 0.0,
        'r7_r2': double.tryParse(r7r2Controller.text.trim()) ?? 0.0,
        'r5': double.tryParse(r5Controller.text.trim()) ?? 0.0,
        'r1_r6': double.tryParse(r1r6Controller.text.trim()) ?? 0.0,
        'triad_iii': double.tryParse(triadController.text.trim()) ?? 0.0,
        'suma_inox': double.tryParse(sumaController.text.trim()) ?? 0.0,
      };

      List<Map<String, String>> manpower = _employees.map((e) {
        return {
          'name': e.nameController.text.trim(),
          'designation': e.designationController.text.trim(),
          'remark': e.remarkController.text.trim(),
        };
      }).toList();

      Map<String, String> resubmitSign = {
        'name': _resubmitSignedBy!,
        'date': _resubmitSignedAt!.toIso8601String().split('T')[0],
      };


      await ApiService.resubmitCoachForm(
        formId: widget.existingForm!.uid,
        contractorRemarks: contractorRemarksController.text.trim(),
        coachCount: _selectedCoaches,
        machinesUsed: machinesUsed,
        chemicals: chemicals,
        manpower: manpower,
        resubmitSign: resubmitSign,
      );

      setState(() => _isSubmitting = false);

      if (mounted) {
        _showSnack('Form resubmitted successfully!');
        await Future.delayed(const Duration(seconds: 1));
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      setState(() => _isSubmitting = false);
      if (mounted) {
        _showSnack('Error resubmitting form: $e');
      }
    }
  }


  Widget _buildStepHeader() {
    final titles = ['Basic', 'Machines', 'Chemicals', 'Manpower', 'Submit'];
    return Row(
      children: List.generate(5, (i) {
        final active = i == _currentStep;
        final done = i < _currentStep;
        return Expanded(
          child: Column(
            children: [
              CircleAvatar(
                radius: active ? 18 : 14,
                backgroundColor:
                done ? Colors.green : (active ? Colors.blue : Colors.grey.shade400),
                child: Text(
                  '${i + 1}',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 6),
              Text(titles[i],
                  style: TextStyle(
                      fontSize: 12, fontWeight: active ? FontWeight.w600 : FontWeight.normal)),
            ],
          ),
        );
      }),
    );
  }

  @override
  void initState() {
    super.initState();

    _chemicalFocusNodes = List.generate(7, (_) => FocusNode());

    _loadContracts();
    _loadActiveTrains().then((_) {
      if (widget.isResubmit && widget.existingForm != null) {
        _populateExistingData();
      } else if (widget.draftData != null) {
        _loadDraftData(widget.draftData!);
      }
    });
    _fetchSupervisors();
  }

  void _populateExistingData() {
    final form = widget.existingForm!;
    
    _selectedTrain = _activeTrains.firstWhere(
      (t) => t.trainName == form.trainName,
      orElse: () => TrainModel(
        trainName: form.trainName,
        trainNo: '',
        uid: '',
        days: [],
        zone: '',
        division: '',
        status: 'active',
      ),
    );
    
    final dateTime = DateTime.parse(form.formDateTime);
    _selectedDate = dateTime;
    _selectedTime = TimeOfDay.fromDateTime(dateTime);
    
    _selectedCoaches = form.coachCount;
    
    for (var machine in _machines) {
      machine.selected = form.machinesUsed.contains(machine.name);
    }
    
    spiralController.text = form.chemicals.spiral.toString();
    r3Controller.text = form.chemicals.r3.toString();
    r7r2Controller.text = form.chemicals.r7R2.toString();
    r5Controller.text = form.chemicals.r5.toString();
    r1r6Controller.text = form.chemicals.r1R6.toString();
    triadController.text = form.chemicals.triadIii.toString();
    sumaController.text = form.chemicals.sumaInox.toString();
    
    for (var emp in form.manpower) {
      _employees.add(_EmployeeRow(
        nameController: TextEditingController(text: emp.name),
        designationController: TextEditingController(text: emp.designation),
        remarkController: TextEditingController(text: emp.remark),
      ));
    }
    
    Future.delayed(Duration.zero, () {
      if (_supervisors.isNotEmpty) {
        setState(() {
          _selectedSupervisor = _supervisors.firstWhere(
            (s) => s.uid == form.submittedTo.railwayEmployeeId,
            orElse: () => _supervisors.first,
          );
        });
      }
    });
    
    _signedBy = form.signature.name;
    _signedAt = DateTime.parse(form.signature.date);
  }

  @override
  void dispose() {
    for (var c in _chemicals) {
      c.nameController.dispose();
      c.qtyController.dispose();
    }
    for (var e in _employees) e.dispose();
    contractorRemarksController.dispose();

    for (final node in _chemicalFocusNodes) {
      node.dispose();
    }
    _divisionController.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isResubmit ? 'Resubmit Coach Form' : 'New Coach Form'),
        centerTitle: true,
      ),
      body: Form(
        key: _formKey,
        child: Column(
          children: [
            const SizedBox(height: 12),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: _buildStepHeader()),
            const Divider(height: 20),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    if (_currentStep == 0) _buildStep1(),
                    if (_currentStep == 1) _buildStep2(),
                    if (_currentStep == 2) _buildStep3(),
                    if (_currentStep == 3) _buildStep4(),
                    if (_currentStep == 4) _buildStep5(),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(10.0),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey.withOpacity(0.25),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    )
                  ],
                ),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    if (_currentStep > 0)
                    OutlinedButton.icon(
                      onPressed: _backStep,
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.blue, width: 1),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        minimumSize: const Size(0, 40),
                      ),
                      icon: const Icon(Icons.arrow_back_outlined, size: 18),
                      label: const Text('Back', style: TextStyle(color: Colors.blue, fontSize: 14)),
                    ),

                    OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.blue, width: 1),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        minimumSize: const Size(0, 40),
                      ),
                      child: const Text('Cancel', style: TextStyle(color: Colors.blue, fontSize: 14)),
                    ),

                    if (_currentStep < 4)
                      ElevatedButton(
                        onPressed: _nextStep,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          minimumSize: const Size(0, 40),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: const Text('Next', style: TextStyle(fontSize: 14)),
                      )
                    else ...[
                      if (!widget.isResubmit)
                        OutlinedButton(
                          onPressed: _saveDraft,
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Colors.blue, width: 1),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            minimumSize: const Size(0, 40),
                          ),
                          child: const Text('Draft', style: TextStyle(color: Colors.blue, fontSize: 14)),
                        ),
                      ElevatedButton(
                        onPressed: _isSubmitting
                            ? null
                            : () {
                          if (widget.isResubmit) {
                            if (_resubmitSignedBy == null) {
                              _openResubmitSignDialog().then((_) {
                                if (_resubmitSignedBy != null) _submitForm();
                              });
                            } else {
                              _submitForm();
                            }
                          } else {
                            if (_signedBy == null) {
                              _openSignDialog().then((_) {
                                if (_signedBy != null) _submitForm();
                              });
                            } else {
                              _submitForm();
                            }
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _isSubmitting ? Colors.grey : Colors.blue,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          minimumSize: const Size(0, 40),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: _isSubmitting
                            ? const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            ),
                            SizedBox(width: 8),
                            Text('Submitting...', style: TextStyle(fontSize: 14)),
                          ],
                        )
                            : Text(widget.isResubmit ? 'Resubmit' : 'Submit', style: const TextStyle(fontSize: 14)),
                      ),
                    ],
                  ],
                ),
              ),
            )


          ],
        ),
      ),
    );
  }


  Widget _buildStep1() {
    final user = Provider.of<AuthProvider>(context).currentUser;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Basic Info', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: LinearProgressIndicator(
              value: (_currentStep + 1) / 5,
              backgroundColor: Colors.grey.shade300,
              color: Colors.blue,
              minHeight: 8,
            ),
          ),
          const SizedBox(height: 16),
          _labeledField('Supervisor *',
              child: TextFormField(
                initialValue: user?.fullName,
                readOnly: true,
                decoration: InputDecoration(
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
              )),
          Text('Auto-populated from your profile', style: const TextStyle(fontSize: 12,color: Colors.blue)),
          const SizedBox(height: 12),
          _labeledField('Select Train *',
              child:  _isLoadingTrains
                  ? const Card(
                child: Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 12),
                      Text('Loading trains...'),
                    ],
                  ),
                ),
              )
                  : DropdownButtonFormField<TrainModel>(
                value: _selectedTrain,
                decoration: InputDecoration(
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                hint: const Text('Choose a train'),
                isExpanded: true,
                items: _activeTrains.map((train) {
                  return DropdownMenuItem<TrainModel>(
                    value: train,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${train.trainNo ?? 'N/A'} - ${train.trainName ?? 'Unknown'}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
                onChanged: widget.isResubmit ? null : (TrainModel? newValue) {
                  setState(() {
                    _selectedTrain = newValue;
                  });
                },
                validator: (value) {
                  if (value == null) {
                    return 'Please select a train';
                  }
                  return null;
                },
              ),),
          const SizedBox(height: 12),
          _labeledField(
            'Date & Time *',
            child: InputDecorator(
              decoration: InputDecoration(
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                suffixIcon: const Icon(Icons.calendar_today_outlined),
              ),
              child: Text(
                '${_selectedDate.day.toString().padLeft(2, '0')}/${_selectedDate.month.toString().padLeft(2, '0')}/${_selectedDate.year}   ${_selectedTime.format(context)}',
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ),
          Text('Auto-filled with cureent date & time (editable)', style: const TextStyle(fontSize: 12,color: Colors.blue)),
          const SizedBox(height: 12),
          _labeledField(
              'No. of coaches',
              child: DropdownButtonFormField<int>(
                hint: const Text('Select number of coaches...'),
                value: _selectedCoaches,
                onChanged: (v) => setState(() => _selectedCoaches = v ?? 1),
                items: List.generate(30, (i) => i + 1)
                    .map((n) => DropdownMenuItem(value: n, child: Text('$n')))
                    .toList(),
                decoration: InputDecoration(
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
              )),
        ],
      ),
    );
  }

  Widget _buildStep2() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Machines used',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: LinearProgressIndicator(
              value: (_currentStep + 1) / 5,
              backgroundColor: Colors.grey.shade300,
              color: Colors.blue,
              minHeight: 8,
            ),
          ),
          const SizedBox(height: 16),
          const Text('Select machines used for cleaning (multi-select):'),
          const SizedBox(height: 8),

          ..._machines.map((m) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                border: Border.all(color:  Colors.grey,),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Checkbox(
                    value: m.selected,
                    onChanged: (v) => setState(() => m.selected = v ?? false),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      m.name,
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                  Container(
                    padding: EdgeInsets.symmetric(vertical: 5,horizontal: 10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(30),
                      color: m.selected ?Colors.green.shade100 : Colors.grey.shade100
                    ),
                    child: Text(
                      m.selected ? 'Used' : 'Not Used',
                      style: TextStyle(
                        fontSize: 12,
                        color: m.selected ? Colors.green : Colors.black,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ],
      ),
    );
  }


  Widget _buildStep3() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Chemicals Consumption',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          const Text(
            'Enter quantity in milliliters (ml)',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 12),

          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: LinearProgressIndicator(
              value: (_currentStep + 1) / 5,
              minHeight: 8,
            ),
          ),

          const SizedBox(height: 20),

          _buildChemicalTable(),
        ],
      ),
    );
  }

  Widget _buildChemicalTable() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        children: [
          _tableHeader(),
          _tableRow('Spiral', spiralController, 0),
          _tableRow('R3', r3Controller, 1),
          _tableRow('R7 / R2', r7r2Controller, 2),
          _tableRow('R5', r5Controller, 3),
          _tableRow('R1 / R6', r1r6Controller, 4),
          _tableRow('TRIAD-III', triadController, 5),
          _tableRow('Suma Inox', sumaController, 6),
        ],
      ),
    );
  }

  Widget _tableHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
      ),
      child: Row(
        children: const [
          Expanded(
            flex: 2,
            child: Text(
              'Chemical',
              style: TextStyle(fontWeight: FontWeight.bold),
              textAlign: TextAlign.left,
            ),
          ),
          Expanded(
            flex: 1,
            child: Text(
              'Quantity (ml)',
              style: TextStyle(fontWeight: FontWeight.bold),
              textAlign: TextAlign.left,
            ),
          ),
        ],
      ),
    );
  }


  Widget _tableRow(
      String name,
      TextEditingController controller,
      int index,
      ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: Colors.grey.shade300),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              name,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            flex: 1,
            child: TextField(
              controller: controller,
              focusNode: _chemicalFocusNodes[index],
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textInputAction:
              index == _chemicalFocusNodes.length - 1
                  ? TextInputAction.done
                  : TextInputAction.next,
              onSubmitted: (_) {
                if (index < _chemicalFocusNodes.length - 1) {
                  FocusScope.of(context)
                      .requestFocus(_chemicalFocusNodes[index + 1]);
                } else {
                  FocusScope.of(context).unfocus();
                }
              },
              textAlign: TextAlign.left,
              textDirection: TextDirection.ltr,
              inputFormatters: [
                FilteringTextInputFormatter.allow(
                  RegExp(r'^\d*\.?\d{0,2}'),
                ),
              ],
              decoration: InputDecoration(
                hintText: '0.00',
                isDense: true,
                contentPadding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }





  Widget _buildStep4() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Manpower',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),

          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: LinearProgressIndicator(
              value: (_currentStep + 1) / 5,
              backgroundColor: Colors.grey.shade300,
              color: Colors.blue,
              minHeight: 8,
            ),
          ),

          const SizedBox(height: 16),

          if (widget.isResubmit) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.orange.shade700),
                      const SizedBox(width: 8),
                      Text(
                        'Railway Rejection Reason',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.orange.shade900,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.existingForm?.rejectionComments ?? 'No remarks provided',
                    style: TextStyle(color: Colors.orange.shade900),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Your Response (Contractor Remarks) *',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: contractorRemarksController,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: 'Explain what changes you made to address the rejection...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],

          const Text('Add staff working in cleaning section (max 22)'),
          const SizedBox(height: 12),

          Row(
            children: [
              const Icon(Icons.people, size: 20),
              const SizedBox(width: 8),
              const Text(
                'Number of Employees:',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 70,
                child: DropdownButtonFormField<int>(
                  value: _employees.isEmpty ? null : _employees.length,
                  decoration: InputDecoration(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    isDense: true,
                  ),
                  hint: const Text('0', style: TextStyle(fontSize: 14)),
                  isExpanded: true,
                  items: List.generate(22, (i) => i + 1)
                      .map((count) => DropdownMenuItem(
                            value: count,
                            child: Text('$count', style: const TextStyle(fontSize: 14)),
                          ))
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      _updateEmployeeCount(value);
                    }
                  },
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          if (_employees.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: const [
                  Icon(Icons.info_outline, size: 16, color: Colors.blue),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Fill in employee details in the table below',
                      style: TextStyle(fontSize: 12, color: Colors.blue),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(8),
                  topRight: Radius.circular(8),
                ),
              ),
              child: Row(
                children: const [
                  SizedBox(width: 40, child: Text('#', style: TextStyle(fontWeight: FontWeight.bold))),
                  Expanded(flex: 2, child: Text('Name *', style: TextStyle(fontWeight: FontWeight.bold))),
                  SizedBox(width: 8),
                  Expanded(flex: 2, child: Text('Designation', style: TextStyle(fontWeight: FontWeight.bold))),
                  SizedBox(width: 8),
                  Expanded(flex: 2, child: Text('Remark', style: TextStyle(fontWeight: FontWeight.bold))),
                ],
              ),
            ),

            Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(8),
                  bottomRight: Radius.circular(8),
                ),
              ),
              child: ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _employees.length,
                itemBuilder: (ctx, idx) {
                  final e = _employees[idx];
                  return Container(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: idx < _employees.length - 1
                            ? BorderSide(color: Colors.grey.shade200)
                            : BorderSide.none,
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 40,
                          child: Text(
                            '${idx + 1}',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: TextFormField(
                            controller: e.nameController,
                            style: const TextStyle(fontSize: 14),
                            decoration: InputDecoration(
                              hintText: 'Name',
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(6),
                              ),
                            ),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z\s\.\-]')),
                            ],
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) {
                                return 'Full Name is required';
                              }
                              if (v.trim().length < 2) {
                                return 'Name must be at least 2 characters';
                              }
                              if (v.trim().length > 50) {
                                return 'Name must not exceed 50 characters';
                              }
                              if (!RegExp(r'^[a-zA-Z\s\.\-]+$').hasMatch(v.trim())) {
                                return 'Name can only contain letters, spaces, dots and hyphens';
                              }
                              if (!RegExp(r'^[a-zA-Z]').hasMatch(v.trim())) {
                                return 'Name must start with a letter';
                              }
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: TextField(
                            controller: e.designationController,
                            style: const TextStyle(fontSize: 14),
                            decoration: InputDecoration(
                              hintText: 'Designation',
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(6),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: TextField(
                            controller: e.remarkController,
                            style: const TextStyle(fontSize: 14),
                            decoration: InputDecoration(
                              hintText: 'Remark',
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(6),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ] else ...[
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.people_outline, size: 48, color: Colors.grey.shade400),
                    const SizedBox(height: 12),
                    Text(
                      'Select number of employees from the dropdown above',
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
            ),
          ],

          const SizedBox(height: 8),
        ],
      ),
    );
  }


  Widget _buildStep5() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Submit To',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: LinearProgressIndicator(
              value: (_currentStep + 1) / 5,
              backgroundColor: Colors.grey.shade300,
              color: Colors.blue,
              minHeight: 8,
            ),
          ),
          const SizedBox(height: 16),

          const Text('Railway Employee',
              style: TextStyle(fontWeight: FontWeight.bold)),

          const SizedBox(height: 5,),


        _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            if (_userRole == 'SUPER_ADMIN') ...[
              const Text('Select Zone (Super Admin)',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 5),
              DropdownButtonFormField<String>(
                decoration: InputDecoration(
                  hintText: 'Select Zone',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                value: _selectedZone,
                onChanged: (v) {
                  setState(() {
                    _selectedZone = v;
                    _selectedDivision = null;
                    _selectedSupervisor = null;
                    _supervisors.clear();
                  });
                },
                items: DepotDatabase.zoneData.keys
                    .map((z) => DropdownMenuItem(value: z, child: Text(z)))
                    .toList(),
              ),
              const SizedBox(height: 20),
              const Text('Select Division (Super Admin)',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 5),
              DropdownButtonFormField<String>(
                decoration: InputDecoration(
                  hintText: 'Select Division',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                value: _selectedDivision,
                onChanged: _selectedZone == null
                    ? null
                    : (v) {
                  setState(() {
                    _selectedDivision = v;
                    _selectedSupervisor = null;
                    _supervisors.clear();
                  });
                  if (v != null) {
                    _fetchSupervisors(zone: _selectedZone, division: v);
                  }
                },
                items: _selectedZone == null
                    ? []
                    : DepotDatabase.zoneData[_selectedZone]!.keys
                    .map((d) => DropdownMenuItem(value: d, child: Text(d)))
                    .toList(),
              ),
              const SizedBox(height: 20),
            ],

            if (_supervisors.isEmpty)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: Colors.orange),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'No Railway Employee found for your Division. Please ensure supervisors exist for your division before submitting.',
                        style: TextStyle(color: Colors.orange, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              )
            else
              DropdownButtonFormField<RailwaySupervisor>(
                decoration: InputDecoration(
                  hintText: 'Select Railway Employee',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                value: _selectedSupervisor,
                onChanged: (v) {
                  setState(() {
                    _selectedSupervisor = v;
                    // Prefill division unless the user typed one themselves.
                    if (!_divisionEdited) {
                      _divisionController.text = v?.division ?? '';
                    }
                  });
                },
                items: _supervisors
                    .map(
                      (sup) => DropdownMenuItem(
                    value: sup,
                    child: Text(sup.fullName),
                  ),
                )
                    .toList(),
              ),

            const SizedBox(height: 20),
            if (_userRole != 'SUPER_ADMIN') ...[
              const Text('Division *',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 5),
              TextFormField(
                // Editable: the field is prefilled from the selected supervisor
                // but the user can correct it before submitting.
                decoration: InputDecoration(
                  hintText: 'Division',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                controller: _divisionController,
                onChanged: (_) => _divisionEdited = true,
              ),
            ],

            const SizedBox(height: 5),
            const Text(
              'Prefilled from your assignment — edit if needed',
              style: TextStyle(color: Colors.blue, fontSize: 13),
            ),

            const SizedBox(height: 20),


            if(_selectedSupervisor?.depot != null && _selectedSupervisor!.depot!.trim().isNotEmpty)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Depot (Optional)',
                    style: TextStyle(fontWeight: FontWeight.bold)),

            const SizedBox(height: 5),
            TextFormField(
              readOnly: true,
              decoration: InputDecoration(
                hintText: 'Auto populated Depot',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              controller: TextEditingController(
                  text: _selectedSupervisor?.depot ?? ''),
            ),

            const SizedBox(height: 5),
            const Text(
              'Auto-populated from your assignment',
              style: TextStyle(color: Colors.blue, fontSize: 13),
            ),
              ],
            ),
          ],
        ),

          const SizedBox(height: 16),

          Container(
            padding: EdgeInsets.all(20),
            decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10)
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Digital Signature', style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 10),

                if (widget.isResubmit && _resubmitSignedBy == null) ...[
                  Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10)
                    ),
                    padding: EdgeInsets.all(30),
                    child: Column(
                      children: [
                        Icon(Icons.draw, size: 40, color: Colors.grey),
                        const SizedBox(height: 10),
                        Text('No Signature Yet', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                        Text(
                          textAlign: TextAlign.center,
                          'Signature will be recorded upon\nresubmission',
                          style: TextStyle(color: Colors.grey, fontSize: 12),
                        )
                      ],
                    ),
                  ),
                ] else if (widget.isResubmit && _resubmitSignedBy != null) ...[
                  Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.green, width: 2),
                    ),
                    padding: EdgeInsets.all(20),
                    child: Column(
                      children: [
                        Icon(Icons.check_circle, size: 40, color: Colors.green),
                        const SizedBox(height: 10),
                        Text('Signed by: $_resubmitSignedBy', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                        Text(
                          'Date: ${_resubmitSignedAt!.toIso8601String().split('T')[0]}',
                          style: TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ] else if (!widget.isResubmit && _signedBy == null) ...[
                  const Text('Click "Sign & Submit" button to provide your digital signature'),
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10)
                    ),
                    padding: EdgeInsets.all(30),
                    child: Column(
                      children: [
                        Icon(Icons.draw, size: 40, color: Colors.grey),
                        const SizedBox(height: 10),
                        Text('No Signature Yet', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                        Text(
                          textAlign: TextAlign.center,
                          'Signature will be recorded upon\nsubmission',
                          style: TextStyle(color: Colors.grey, fontSize: 12),
                        )
                      ],
                    ),
                  ),
                ] else if (!widget.isResubmit && _signedBy != null) ...[
                  Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.green, width: 2),
                    ),
                    padding: EdgeInsets.all(20),
                    child: Column(
                      children: [
                        Icon(Icons.check_circle, size: 40, color: Colors.green),
                        const SizedBox(height: 10),
                        Text('Signed by: $_signedBy', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                        Text(
                          'Date: ${_signedAt!.toIso8601String().split('T')[0]}',
                          style: TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 16,),


          Container(
            padding: EdgeInsets.all(20),
            decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10)
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Form Summary',style: TextStyle(color: Colors.black87,fontWeight: FontWeight.bold),),

                const SizedBox(height: 10,),

                Row(children: [ Text('Supervisor: ',style: TextStyle(fontWeight: FontWeight.bold),), Text(_selectedSupervisor?.fullName ?? 'Not selected')]),
                const SizedBox(height: 5,),
                Row(children: [ Text('Train: ',style: TextStyle(fontWeight: FontWeight.bold),), Text('${_selectedTrain?.trainNo ?? 'N/A'} - ${_selectedTrain?.trainName ?? 'Not selected'}')]),
                const SizedBox(height: 5,),
                Row(children: [ Text('Date & Time: ',style: TextStyle(fontWeight: FontWeight.bold),), Text('${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}, ${_selectedTime.format(context)}')]),
                const SizedBox(height: 5,),
                Row(children: [ Text('Coaches: ',style: TextStyle(fontWeight: FontWeight.bold),), Text('$_selectedCoaches')]),
                const SizedBox(height: 5,),
                Row(children: [ Text('Machine Used: ',style: TextStyle(fontWeight: FontWeight.bold),), Text('${_machines.where((m) => m.selected).length} of ${_machines.length}')]),
                const SizedBox(height: 5,),
                Row(children: [ Text('Employees: ',style: TextStyle(fontWeight: FontWeight.bold),), Text('${_employees.length}')]),
                const SizedBox(height: 5,),
                Row(children: [ Text('Division: ',style: TextStyle(fontWeight: FontWeight.bold),), Text(_selectedSupervisor?.division ?? 'N/A')]),
                if(_selectedSupervisor?.depot != null && _selectedSupervisor!.depot!.trim().isNotEmpty)
                const SizedBox(height: 5,),
                if(_selectedSupervisor?.depot != null && _selectedSupervisor!.depot!.trim().isNotEmpty)
                Row(children: [ Text('Depot: ',style: TextStyle(fontWeight: FontWeight.bold),), Text(_selectedSupervisor!.depot!.trim())]),
                const SizedBox(height: 5,),
                Row(children: [ Text('Submit to : ',style: TextStyle(fontWeight: FontWeight.bold),), Text(_selectedSupervisor?.fullName ?? 'Not selected')]),
                const SizedBox(height: 5,),
                Row(children: [ Text('Submit by: ',style: TextStyle(fontWeight: FontWeight.bold),), Text(_signedBy ?? 'Not signed yet')]),

              ],
            ),
          )


        ],
      ),
    );
  }

  Widget _labeledField(String label, {required Widget child}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        const SizedBox(height: 4),
        child,
      ],
    );
  }

  Widget _buildResubmitSummary() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Review & Submit',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: LinearProgressIndicator(
              value: 1.0,
              backgroundColor: Colors.grey.shade300,
              color: Colors.blue,
              minHeight: 8,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.orange.shade700),
                    const SizedBox(width: 8),
                    Text(
                      'Railway Rejection Reason',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.orange.shade900,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  widget.existingForm?.railwayRemarks ?? 'No remarks provided',
                  style: TextStyle(color: Colors.orange.shade900),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blue.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.comment, color: Colors.blue.shade700),
                    const SizedBox(width: 8),
                    Text(
                      'Your Response',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.blue.shade900,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  contractorRemarksController.text.trim().isEmpty
                      ? 'No response provided'
                      : contractorRemarksController.text.trim(),
                  style: TextStyle(color: Colors.blue.shade900),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.green.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.people, color: Colors.green.shade700),
                    const SizedBox(width: 8),
                    Text(
                      'Updated Manpower (${_employees.length})',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.green.shade900,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ..._employees.asMap().entries.map((entry) {
                  final i = entry.key + 1;
                  final e = entry.value;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Text('$i. ',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.green.shade900)),
                        Expanded(
                          child: Text(
                            '${e.nameController.text} - ${e.designationController.text}',
                            style: TextStyle(color: Colors.green.shade900),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}


class _MachineItem {
  String name;
  bool selected;
  _MachineItem(this.name, {this.selected = false});
}

class _ChemicalRow {
  final TextEditingController nameController;
  final TextEditingController qtyController;
  _ChemicalRow({required this.nameController, required this.qtyController});
}

class _EmployeeRow {
  final TextEditingController nameController;
  final TextEditingController designationController;
  final TextEditingController remarkController;
  _EmployeeRow({
    required this.nameController,
    required this.designationController,
    required this.remarkController,
  });

  void dispose() {
    nameController.dispose();
    designationController.dispose();
    remarkController.dispose();
  }
}
