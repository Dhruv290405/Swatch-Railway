import 'dart:convert';
import 'package:crm_train/model/premises_form_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:math';
import '../../../../model/railway_supervisor_model.dart';
import '../../../../providers/auth_provider.dart';
import '../../../../services/api_services.dart';
import '../../../../services/draft_storage_service.dart';
import '../../../../data/zone_database.dart';


class Employee {
  TextEditingController nameController = TextEditingController();
  TextEditingController designationController = TextEditingController();
  TextEditingController remarkController = TextEditingController();

  void dispose() {
    nameController.dispose();
    designationController.dispose();
    remarkController.dispose();
  }
}

class PremisesCleaningForm extends StatefulWidget {
  final FormData? existingForm;
  final bool isResubmit;
  final Map<String, dynamic>? draftData;

  const PremisesCleaningForm({
    super.key,
    this.existingForm,
    this.isResubmit = false,
    this.draftData,
  });

  @override
  State<PremisesCleaningForm> createState() => _PremisesCleaningFormState();
}

class _PremisesCleaningFormState extends State<PremisesCleaningForm> {
  final _formKey = GlobalKey<FormState>();

  int _currentStep = 0;
  bool _isSubmitting = false;
  bool _isLoading = false;
  String? _currentDraftId;
  String? _userRole;
  String? _selectedZone;
  String? _selectedDivision;
  final TextEditingController _divisionController = TextEditingController();
  bool _divisionEdited = false;


  TextEditingController supervisorController = TextEditingController();
  String selectedLocation = '';
  DateTime selectedDateTime = DateTime.now();
  List<String> locations = ['GICC', 'OWS', 'NWS', 'Platform', 'Pune Yard', 'Hadapsar', 'Khadki'];

  List<Employee> employees = [];

  List<RailwaySupervisor> _supervisors = [];
  RailwaySupervisor? _selectedSupervisor;

  TextEditingController contractorRemarksController = TextEditingController();

  TextEditingController signNameController = TextEditingController();
  TextEditingController signDateController = TextEditingController();

  bool isLoadingContracts = false;

  String contractUidString = "";

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

      // Prefer an active contract whose work categories allow premises
      // cleaning — the backend rejects the form otherwise.
      final eligible = contractsList.where((c) {
        final cats = (c.workCategories ?? '').toLowerCase();
        final type = (c.contractType ?? '').toLowerCase();
        return cats.contains('premise') ||
            cats.contains('premises') ||
            type == 'premises';
      }).toList();
      final activeEligible = eligible.where((c) => c.isActive == true).toList();
      final pool = activeEligible.isNotEmpty
          ? activeEligible
          : (eligible.isNotEmpty ? eligible : contractsList);

      // Take first contract ID only (API expects single ID, not comma-separated)
      contractUidString = pool.first.uid.toString();


      if (mounted) {
        setState(() => isLoadingContracts = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => isLoadingContracts = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error loading contracts: $e")),
        );
      }
    }
  }


  Future<void> _fetchSupervisors({String? zone, String? division}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      if (token == null) return;

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
          if (_selectedSupervisor != null && !_supervisors.any((s) => s.uid == _selectedSupervisor!.uid)) {
            _selectedSupervisor = null;
          }
        });
      } else {
        throw Exception('Failed to load supervisors: ${response.statusCode}');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  String? _signedBy;
  DateTime? _signedAt;
  String? _resubmitSignedBy;
  DateTime? _resubmitSignedAt;

  @override
  @override
  void initState() {
    super.initState();
    _loadContracts();
    final user = Provider.of<AuthProvider>(context, listen: false).currentUser;
    supervisorController.text = user?.fullName ?? "";
    signNameController.text = user?.fullName ?? "";
    signDateController.text = DateFormat('yyyy-MM-dd').format(DateTime.now());
    _fetchSupervisors().then((_) {
      if (widget.isResubmit && widget.existingForm != null) {
        _prefillFormIfResubmit();
      } else if (widget.draftData != null) {
        _loadDraftData(widget.draftData!);
      }
    });
  }

  void _prefillFormIfResubmit() {
    if (widget.isResubmit && widget.existingForm != null) {
      final form = widget.existingForm!;
      selectedLocation = form.location;
      selectedDateTime = form.formDateTime;

      employees = form.manpower.map((m) {
        final emp = Employee();
        emp.nameController.text = m.name;
        emp.designationController.text = m.designation;
        emp.remarkController.text = m.remark;
        return emp;
      }).toList();

      if (form.submittedTo != null) {
        final railwayEmployeeId = form.submittedTo!.railwayEmployeeId;
        _selectedSupervisor = _supervisors.firstWhere(
          (sup) => sup.uid == railwayEmployeeId,
          orElse: () => RailwaySupervisor(
            uid: railwayEmployeeId,
            fullName: form.submittedTo!.railwayEmployeeName ?? 'N/A',
            division: form.submittedTo!.division,
            depot: form.submittedTo!.depot ?? '',
          ),
        );
      }


      if (form.signature != null) {
        _signedBy = form.signature!.name;
        try {
          _signedAt = DateTime.parse(form.signature!.date);
        } catch (e) {
          _signedAt = DateTime.now();
        }
      }
    }
  }

  @override
  void dispose() {
    supervisorController.dispose();
    signNameController.dispose();
    signDateController.dispose();
    contractorRemarksController.dispose();
    _divisionController.dispose();
    for (var emp in employees) {
      emp.dispose();
    }
    super.dispose();
  }

  bool _validateStep1() {
    if (selectedLocation.isEmpty) {
      _showSnack('Please select a Location before proceeding');
      return false;
    }
    return true;
  }

  bool _validateStep2() {
    if (widget.isResubmit) {
      if (contractorRemarksController.text.trim().isEmpty) {
        _showSnack('Please provide contractor remarks before proceeding');
        return false;
      }
    }
    if (employees.isEmpty) {
      _showSnack('Please add at least one employee');
      return false;
    }
    for (var e in employees) {
      if (e.nameController.text.trim().isEmpty) {
        _showSnack('Employee name is required');
        return false;
      }
    }
    return true;
  }

  bool _validateStep3() {
    if (widget.isResubmit) {
      if (contractorRemarksController.text.trim().isEmpty) {
        _showSnack('Please provide contractor remarks');
        return false;
      }
      if (_resubmitSignedBy == null) {
        _showSnack('Please provide digital signature for resubmission');
        return false;
      }
      return true;
    }
    if (_selectedSupervisor == null) {
      _showSnack('Please select a Railway Employee');
      return false;
    }
    if (_signedBy == null) {
      _showSnack('Please provide digital signature');
      return false;
    }
    if (contractUidString.trim().isEmpty) {
      _showSnack(
          'No contract linked to your account. Contact your administrator to link a Premises Cleaning contract, then reopen this form.');
      return false;
    }
    return true;
  }

  void _nextStep() {
    if (_currentStep == 0) {
      if (!_validateStep1()) return;
    } else if (_currentStep == 1) {
      if (!_validateStep2()) return;
    } else if (_currentStep == 2) {
      if (!_validateStep3()) return;
    }
    setState(() => _currentStep = min(2, _currentStep + 1));
  }

  void _backStep() {
    setState(() => _currentStep = max(0, _currentStep - 1));
  }

  void _showSnack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));


  void _updateEmployeeCount(int count) {
    setState(() {
      while (employees.length > count) {
        employees.last.dispose();
        employees.removeLast();
      }

      while (employees.length < count) {
        employees.add(Employee());
      }
    });
  }

  Future<void> _openSignDialog() async {
    final controller = TextEditingController();
    final res = await showDialog<String?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Provide digital signature (type name)'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'Your full name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Sign'),
          ),
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
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'Your full name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Sign'),
          ),
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

  Future<void> _saveDraft() async {
    try {
      final user = Provider.of<AuthProvider>(context, listen: false).currentUser;

      List<Map<String, String>> manpower = employees.map((e) {
        return {
          'name': e.nameController.text.trim(),
          'designation': e.designationController.text.trim(),
          'remark': e.remarkController.text.trim(),
        };
      }).toList();

      final draftData = {
        'supervisor': supervisorController.text.trim(),
        'location': selectedLocation,
        'selectedDateTime': selectedDateTime.toIso8601String(),
        'manpower': manpower,
        'supervisorId': _selectedSupervisor?.uid ?? '',
        'supervisorName': _selectedSupervisor?.fullName ?? '',
        'division': _selectedSupervisor?.division ?? user?.division ?? '',
        'depot': _selectedSupervisor?.depot ?? user?.depot ?? '',
        'submittedByName': user?.fullName ?? '',
        // 'submittedByEntityName': user?.entityDetails ?? '',
        'isDraft': true,
        'formType': 'premises',
      };

      await DraftStorageService.savePremisesDraft(draftData, existingDraftId: _currentDraftId);

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

  Future<void> _loadDraftData(Map<String, dynamic> draftData) async {

    _currentDraftId = draftData['draftId'];

    setState(() {
      if (draftData['supervisor'] != null) {
        supervisorController.text = draftData['supervisor'];
      }

      if (draftData['location'] != null && draftData['location'].toString().isNotEmpty) {
        selectedLocation = draftData['location'];
      }

      if (draftData['selectedDateTime'] != null) {
        selectedDateTime = DateTime.parse(draftData['selectedDateTime']);
      }
      if (draftData['manpower'] != null) {
        employees.clear();
        final List manpower = draftData['manpower'];
        for (var emp in manpower) {
          final employee = Employee();
          employee.nameController.text = emp['name'] ?? '';
          employee.designationController.text = emp['designation'] ?? '';
          employee.remarkController.text = emp['remark'] ?? '';
          employees.add(employee);
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

  void _submitForm() async {
    if (!_validateStep3()) return;

    final String? draftIdToDelete = _currentDraftId;

    if (mounted) {
      setState(() => _isSubmitting = true);
    }

    try {
      List<Map<String, String>> manpower = employees.map((e) {
        return {
          'name': e.nameController.text.trim(),
          'designation': e.designationController.text.trim(),
          'remark': e.remarkController.text.trim(),
        };
      }).toList();

      if (widget.isResubmit && widget.existingForm != null) {

        Map<String, dynamic> resubmitSign = {
          "name": _resubmitSignedBy!,
          "date": _resubmitSignedAt!.toIso8601String().split('T')[0],
        };


        final response = await ApiService.resubmitPremisesForm(
          formId: widget.existingForm!.uid,
          contractorRemarks: contractorRemarksController.text.trim(),
          manpower: manpower,
          resubmitSign: resubmitSign,
        );

        if (mounted) {
          setState(() => _isSubmitting = false);
          _showSnack('Form resubmitted successfully!');
          await Future.delayed(const Duration(seconds: 2));
          Navigator.of(context).pop(true);
        }
      } else {
        final formDateTime = selectedDateTime.toUtc().toIso8601String();

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

        final response = await ApiService.submitPremisesForm(
          supervisor: supervisorController.text.trim(),
          location: selectedLocation,
          formDateTime: formDateTime,
          contractId: contractUidString,
          manpower: manpower,
          submittedTo: submittedTo,
          signature: signature,
        );

        if (mounted) {
          setState(() => _isSubmitting = false);
        }

        if (draftIdToDelete != null) {
          await DraftStorageService.deletePremisesDraft(draftIdToDelete);
        }

        if (mounted) {
          _showSnack('Form submitted successfully! UID: ${response['uid'] ?? 'N/A'}');
          _showSubmissionSummary(response);
          await Future.delayed(const Duration(seconds: 3));
          Navigator.of(context).pop(true);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        _showSnack('Error: $e');
      }
    }
  }

  void _showSubmissionSummary(Map<String, dynamic> response) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Form Submitted Successfully'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _summaryRow('UID', response['uid']?.toString() ?? 'N/A'),
              _summaryRow('Supervisor', supervisorController.text),
              _summaryRow('Location', selectedLocation),
              _summaryRow('Employees', '${employees.length}'),
              _summaryRow('Signed By', _signedBy),
              _summaryRow(
                'Date & Time',
                DateFormat('yyyy-MM-dd – kk:mm').format(selectedDateTime),
              ),
              _summaryRow('Division', _selectedSupervisor!.division),
              if (_selectedSupervisor?.depot != null &&
                  _selectedSupervisor!.depot!.isNotEmpty)
                _summaryRow('Depot', _selectedSupervisor!.depot!),

            ],
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String? value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(
            '$label: ',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          Expanded(
            child: Text(value ?? 'N/A'),
          ),
        ],
      ),
    );
  }

  Widget _buildStepHeader() {
    final titles = ['Basic Info', 'Manpower', 'Submit'];
    return Row(
      children: List.generate(3, (i) {
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
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                titles[i],
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: active ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    double progress = (_currentStep + 1) / 3;

    return Scaffold(
      appBar: AppBar(
        iconTheme: IconThemeData(color: Colors.white),
        title: Text(
          widget.isResubmit ? "Resubmit Premises Form" : "Premises Cleaning Form",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20),
        ),
        backgroundColor: Colors.blueAccent,
      ),
      body: Form(
        key: _formKey,
        child: Column(
          children: [
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: _buildStepHeader(),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 6,
                borderRadius: BorderRadius.circular(10),
                color: Colors.blueAccent,
                backgroundColor: Colors.grey[300],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    if (_currentStep == 0) _buildStep1(),
                    if (_currentStep == 1) _buildStep2(),
                    if (_currentStep == 2) _buildStep3(),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
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
                    ),
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
                    if (_currentStep < 2)
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
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStep1() {
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
            'Basic Info',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: LinearProgressIndicator(
              value: (_currentStep + 1) / 3,
              backgroundColor: Colors.grey.shade300,
              color: Colors.blue,
              minHeight: 8,
            ),
          ),
          const SizedBox(height: 16),
          _labeledField(
            'Supervisor *',
            child: TextFormField(
              controller: supervisorController,
              readOnly: true,
              decoration: InputDecoration(
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
          const Text(
            'Auto-populated from your profile',
            style: TextStyle(fontSize: 12, color: Colors.blue),
          ),
          const SizedBox(height: 16),
          _labeledField(
            'Location *',
            child: DropdownButtonFormField<String>(
              value: selectedLocation.isEmpty ? null : selectedLocation,
              hint: const Text('Select Location'),
              items: locations
                  .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                  .toList(),

              onChanged: widget.isResubmit
                  ? null
                  : (val) {
                setState(() {
                  selectedLocation = val ?? '';
                });
              },

              decoration: InputDecoration(
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),

                filled: widget.isResubmit,
                fillColor: widget.isResubmit ? Colors.grey.shade100 : null,
              ),
            ),
          ),
          const SizedBox(height: 16),
          _labeledField(
            'Date & Time *',
            child: InputDecorator(
              decoration: InputDecoration(
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                suffixIcon: const Icon(Icons.calendar_today_outlined),
              ),
              child: Text(
                DateFormat('yyyy-MM-dd – kk:mm').format(selectedDateTime),
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ),
          const Text(
            'Auto-filled with current date & time.',
            style: TextStyle(fontSize: 12, color: Colors.blue),
          ),
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
            'Manpower',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: LinearProgressIndicator(
              value: (_currentStep + 1) / 3,
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
            if (_userRole != 'SUPER_ADMIN') ...[
              const Text('Division *',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 5),
              TextFormField(
                // Editable: prefilled from the selected supervisor.
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
          ],

          const Text('Add staff working in premises cleaning (max 22)'),
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
                  value: employees.isEmpty ? null : employees.length,
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

          if (employees.isNotEmpty) ...[
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
                itemCount: employees.length,
                itemBuilder: (ctx, idx) {
                  final e = employees[idx];
                  return Container(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: idx < employees.length - 1
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

  Widget _buildStep3() {
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
            'Submit To',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: LinearProgressIndicator(
              value: (_currentStep + 1) / 3,
              backgroundColor: Colors.grey.shade300,
              color: Colors.blue,
              minHeight: 8,
            ),
          ),
          const SizedBox(height: 16),
          const Text('Railway Employee',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 5),
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
                      if (!_divisionEdited) {
                        _divisionController.text = v?.division ?? '';
                      }
                    });
                  },
                  items: _supervisors
                      .map((sup) => DropdownMenuItem(
                    value: sup,
                    child: Text(sup.fullName),
                  ))
                      .toList(),
                ),
              const SizedBox(height: 20),
              const Text('Division *',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 5),
              TextFormField(
                // Editable: prefilled from the selected supervisor, but the
                // user can correct it before submitting.
                decoration: InputDecoration(
                  hintText: 'Division',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                controller: _divisionController,
                onChanged: (_) => _divisionEdited = true,
              ),
              const SizedBox(height: 5),
              const Text(
                'Prefilled from your assignment — edit if needed',
                style: TextStyle(color: Colors.blue, fontSize: 13),
              ),
              if (_selectedSupervisor?.depot != null &&
                  _selectedSupervisor!.depot!.isNotEmpty) ...[
                const SizedBox(height: 20),
                const Text(
                  'Depot (Optional)',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 5),
                TextFormField(
                  readOnly: true,
                  controller: TextEditingController(
                    text: _selectedSupervisor!.depot!,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Auto populated Depot',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 5),
                const Text(
                  'Auto-populated from your assignment',
                  style: TextStyle(color: Colors.blue, fontSize: 13),
                ),
              ],


            ],
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Digital Signature',
                  style: TextStyle(
                    color: Colors.black87,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 10),
                if (widget.isResubmit && _resubmitSignedBy == null)
                  Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.all(30),
                    child: Column(
                      children: [
                        const Icon(Icons.draw, size: 40, color: Colors.grey),
                        const SizedBox(height: 10),
                        const Text(
                          'No Signature Yet',
                          style: TextStyle(
                            color: Colors.grey,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Text(
                          'Signature will be recorded upon\nresubmission',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                      ],
                    ),
                  )
                else if (widget.isResubmit && _resubmitSignedBy != null)
                  Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.green, width: 2),
                    ),
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        const Icon(Icons.check_circle, size: 40, color: Colors.green),
                        const SizedBox(height: 10),
                        Text(
                          'Signed by: $_resubmitSignedBy',
                          style: const TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Date: ${_resubmitSignedAt!.toIso8601String().split('T')[0]}',
                          style: const TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                      ],
                    ),
                  )
                else if (!widget.isResubmit && _signedBy == null)
                  Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.all(30),
                    child: Column(
                      children: [
                        const Icon(Icons.draw, size: 40, color: Colors.grey),
                        const SizedBox(height: 10),
                        const Text(
                          'No Signature Yet',
                          style: TextStyle(
                            color: Colors.grey,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Text(
                          'Signature will be recorded upon\nsubmission',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                      ],
                    ),
                  )
                else if (!widget.isResubmit && _signedBy != null)
                  Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.green, width: 2),
                    ),
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        const Icon(Icons.check_circle, size: 40, color: Colors.green),
                        const SizedBox(height: 10),
                        Text(
                          'Signed by: $_signedBy',
                          style: const TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Date: ${_signedAt!.toIso8601String().split('T')[0]}',
                          style: const TextStyle(color: Colors.grey, fontSize: 12),
                        ),  
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Form Summary',
                  style: TextStyle(
                    color: Colors.black87,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 10),
                if (!widget.isResubmit) _summaryRow('Supervisor', supervisorController.text),
                _summaryRow('Location', selectedLocation),
                _summaryRow(
                  'Date & Time',
                  DateFormat('yyyy-MM-dd – kk:mm').format(selectedDateTime),
                ),
                _summaryRow('Employees', '${employees.length}'),
                if (!widget.isResubmit) ...[
                  _summaryRow('Division', _selectedSupervisor?.division ?? ''),
                  if (_selectedSupervisor?.depot != null &&
                      _selectedSupervisor!.depot!.isNotEmpty)
                    _summaryRow('Depot', _selectedSupervisor!.depot!),
                  _summaryRow('Submit To', _selectedSupervisor?.fullName ?? ''),
                ],
                if (widget.isResubmit) ...[
                  _summaryRow('Railway Rejection Reason', widget.existingForm?.rejectionComments ?? 'N/A'),
                  _summaryRow('Your Response', contractorRemarksController.text.isEmpty ? 'Not provided' : contractorRemarksController.text),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _labeledField(String label, {required Widget child}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
        const SizedBox(height: 4),
        child,
      ],
    );
  }
}