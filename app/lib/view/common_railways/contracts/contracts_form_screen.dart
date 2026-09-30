import 'package:crm_train/services/api_services.dart';
import 'package:crm_train/model/station_models.dart';
import 'package:crm_train/model/train_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';

import '../../../model/contracts_model.dart';
import '../../../providers/auth_provider.dart';
import '../../../utills/validators.dart';
import '../widgets/approve_entity_dropdown.dart';
import '../widgets/rolevise_dropdowns.dart';


class ContractFormScreen extends StatefulWidget {
  final ContractModel? contract;

  const ContractFormScreen({super.key, this.contract});

  @override
  State<ContractFormScreen> createState() => _ContractFormScreenState();
}

class _ContractFormScreenState extends State<ContractFormScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;

  TextEditingController contractNoController = TextEditingController();
  TextEditingController contractNameController = TextEditingController();
  TextEditingController remarksController = TextEditingController();
  TextEditingController repNameController = TextEditingController();
  TextEditingController repDesignationController = TextEditingController();
  TextEditingController repMobileController = TextEditingController();
  TextEditingController repEmailController = TextEditingController();
  TextEditingController repIdNumberController = TextEditingController();
  TextEditingController contractValueController = TextEditingController();

  String? selectedEntity;
  String? selectedZone;
  String? selectedDivision;
  String? selectedDepot;
  String? selectedStatus;
  String? selectedIDType;
  List<String> selectedWorkCategories = [];
  List<String> selectedStationIds = [];
  List<String> selectedStationNames = [];
  List<String> selectedTrainIds = [];
  List<String> selectedTrainNames = [];
  List<Station> _availableStations = [];
  List<TrainModel> _availableTrains = [];
  bool _stationsLoading = false;
  String? _manualStationId;
  String? _manualStationName;
  String? selectedBillingCycle;
  String? selectedContractType;
  double contractValue = 0;
  bool scoringApplicability = true;

  DateTime? startDate;
  DateTime? endDate;

  String? gemAwardLetterFile;
  String? declarationFormFile;
  String? idProofFile;

  bool get isEditMode => widget.contract != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final user = Provider.of<AuthProvider>(context, listen: false).currentUser;
      if (isEditMode) {
        _loadContractData();
      } else {
        setState(() {
          selectedZone = user?.zone;
          selectedDivision = user?.division;
          selectedDepot = user?.depot;
        });
      }
      _loadStations();
      _loadTrains();
      if (selectedDivision != null) {
        _loadStations(division: selectedDivision);
      }
    });
  }

  Future<void> _loadStations({String? division}) async {
    setState(() => _stationsLoading = true);
    try {
      _availableStations = await ApiService.getStations(active: true, division: division);
    } catch (_) {}
    if (mounted) setState(() => _stationsLoading = false);
  }

  Future<void> _loadTrains() async {
    try {
      _availableTrains = await ApiService.getActiveTrains();
    } catch (_) {}
  }

  void _loadContractData() {
    final c = widget.contract!;

    contractNoController.text = c.contractNumber ?? '';
    contractValueController.text = (c.contractValue ?? 0).toStringAsFixed(0);
    contractNameController.text = c.contractName ?? '';
    remarksController.text = c.remarks ?? '';
    selectedEntity = c.entityId;
    selectedZone = c.zone;
    selectedDivision = c.division;
    selectedDepot = c.depot;

    selectedWorkCategories = (c.workCategories != null && c.workCategories!.isNotEmpty)
        ? c.workCategories!.split(',').map((e) => e.trim()).toList()
        : [];

    startDate = (c.startDate != null && c.startDate!.isNotEmpty)
        ? DateTime.tryParse(c.startDate!)
        : null;
    endDate = (c.endDate != null && c.endDate!.isNotEmpty)
        ? DateTime.tryParse(c.endDate!)
        : null;

    selectedStatus = c.status;
    selectedContractType = c.contractType != null
        ? (c.contractType == 'station_cleaning'
            ? 'Station Cleaning'
            : (c.contractType == 'obhs' ? 'OBHS' : 'MCC'))
        : null;
    repNameController.text = c.repName ?? '';
    repDesignationController.text = c.repDesignation ?? '';
    repMobileController.text = c.repMobile ?? '';
    repEmailController.text = c.repEmail ?? '';
    repIdNumberController.text = c.repIdProofNumber ?? '';
    selectedIDType = c.repIdProofType;

    if (c.stationIds != null && c.stationIds.isNotEmpty) {
      _manualStationId = c.stationIds.first;
      _manualStationName = c.stationNames.isNotEmpty ? c.stationNames.first : c.stationIds.first;
    }

    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final user = Provider.of<AuthProvider>(context).currentUser;
    if (user == null) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: Text(
          isEditMode ? "Edit Contract" : "Add Contract",
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF1565C0),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildCard(
                    title: "Basic Information",
                    icon: Icons.info_outline,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildTextField(
                          "Contract Number *",
                          "Enter contract number",
                          contractNoController,
                          enabled: !isEditMode,
                        ),
                        _buildTextField(
                          "Contract Name *",
                          "Enter contract name",
                          contractNameController,
                          enabled: !isEditMode,
                        ),
                        const Text('Select Entity',
                            style: TextStyle(fontWeight: FontWeight.w500)),
                        const SizedBox(height: 6),
                        AbsorbPointer(
                          absorbing: isEditMode,
                          child: Opacity(
                            opacity: isEditMode ? 0.5 : 1.0,
                            child: ApprovedEntityDropdown(
                              initialValue: selectedEntity,
                              onSelected: (name) {
                                setState(() {
                                  selectedEntity = name;
                                });
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  _buildCard(
                    title: "Location Details",
                    icon: Icons.location_on,
                    child: AbsorbPointer(
                      absorbing: isEditMode,
                      child: Opacity(
                        opacity: isEditMode ? 0.5 : 1.0,
                        child: ZoneDivisionDepotDropdowns(
                          key: ValueKey('${selectedZone}_${selectedDivision}_$selectedDepot'),
                          user: user!,
                          initialZone: selectedZone,
                          initialDivision: selectedDivision,
                          initialDepot: selectedDepot,
                          onChangedWithZone: (zone, division, depot) {
                            setState(() {
                              selectedZone = zone;
                              selectedDivision = division;
                              selectedDepot = depot;
                            });
                            if (selectedContractType == 'Station Cleaning' || selectedContractType == 'MCC') {
                              _loadStations(division: division);
                            }
                          },
                        ),
                      ),
                    ),
                  ),
                  if (selectedContractType == 'Station Cleaning' || selectedContractType == 'MCC') ...[
                    const SizedBox(height: 16),
                    _buildCard(
                      title: "Station Assignment",
                      icon: Icons.train,
                      child: _stationsLoading
                          ? const SizedBox(height: 40, child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
                          : AbsorbPointer(
                              absorbing: isEditMode,
                              child: Opacity(
                                opacity: isEditMode ? 0.5 : 1.0,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _buildDropdown(
                                      "Select Station *",
                                      "Choose station",
                                      _availableStations
                                          .map((s) => s.stationName ?? '')
                                          .where((n) => n.isNotEmpty)
                                          .toList(),
                                      _manualStationName,
                                      (v) {
                                        if (v == null || v.isEmpty) return;
                                        final match = _availableStations.firstWhere(
                                          (s) => s.stationName == v,
                                          orElse: () => Station(stationCode: '', stationName: '', zone: '', division: ''),
                                        );
                                        setState(() {
                                          _manualStationId = match.uid;
                                          _manualStationName = match.stationName;
                                        });
                                      },
                                      enabled: !isEditMode,
                                    ),
                                    if (_availableStations.isEmpty && !_stationsLoading)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 4),
                                        child: Text(
                                          'No stations found for the selected division.',
                                          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                    ),
                  ],
                  const SizedBox(height: 16),

                  _buildCard(
                    title: "Contract Details",
                    icon: Icons.description,
                    child: Column(
                      children: [
                        _buildDateField("Start Date *", startDate, (date) {
                          if (!isEditMode) setState(() => startDate = date);
                        }, enabled: !isEditMode),
                        _buildDateField("End Date *", endDate, (date) {
                          if (!isEditMode) setState(() => endDate = date);
                        }, enabled: !isEditMode),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _buildTextField(
                                "Contract Value (₹)",
                                "Enter value",
                                contractValueController,
                                enabled: !isEditMode,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _buildDropdown(
                                'Contract Type',
                                'Select type',
                                ['Station Cleaning', 'MCC'],
                                selectedContractType,
                                (v) {
                                  setState(() {
                                    selectedContractType = v;
                                    selectedStationIds = [];
                                    selectedStationNames = [];
                                    selectedTrainIds = [];
                                    selectedTrainNames = [];
                                  });
                                  if ((v == 'Station Cleaning' || v == 'MCC') && selectedDivision != null) {
                                    _loadStations(division: selectedDivision);
                                  }
                                },
                                enabled: !isEditMode,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _buildDropdown(
                                'Billing Cycle',
                                'Select cycle',
                                ['Monthly', 'Quarterly', 'Half Yearly', 'Yearly'],
                                selectedBillingCycle,
                                (v) => setState(() => selectedBillingCycle = v),
                                enabled: !isEditMode,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        SwitchListTile(
                          title: const Text('Enable Scoring'),
                          subtitle: Text(scoringApplicability ? 'Scorecards will be generated' : 'Scoring disabled'),
                          value: scoringApplicability,
                          onChanged: !isEditMode ? (v) => setState(() => scoringApplicability = v) : null,
                          contentPadding: EdgeInsets.zero,
                          activeColor: Colors.blue,
                        ),
                        _buildMultiSelectDropdown(
                          "Work Categories *",
                          "Select Categories",
                          ["Premise Cleaning", "Coach Cleaning", "CTS Form", "OBHS Form", "Station Cleaning"],
                          selectedWorkCategories,
                              (values) {
                            if (!isEditMode) {
                              setState(() => selectedWorkCategories = values);
                            }
                          },
                          enabled: !isEditMode,
                        ),
                        _buildDropdown(
                          'Status *',
                          'Choose Status',
                          ["Active", "Inactive", "Expired", "Suspended"],
                          selectedStatus,
                              (v) => setState(() => selectedStatus = v),
                          enabled: true,
                        ),
                        // OBHS → train picker
                        if (selectedContractType == 'OBHS') ...[
                          const SizedBox(height: 12),
                          const Text('Assigned Trains *', style: TextStyle(fontWeight: FontWeight.w500)),
                          const SizedBox(height: 4),
                          _buildMultiSelectDropdown(
                            "Trains",
                            "Select trains",
                            _availableTrains.map((t) => '${t.trainNo ?? ""} - ${t.trainName ?? ""}').toList(),
                            selectedTrainNames,
                            (values) {
                              setState(() {
                                selectedTrainNames = values;
                                selectedTrainIds = values.map((v) {
                                  final match = _availableTrains.firstWhere(
                                    (t) => '${t.trainNo ?? ""} - ${t.trainName ?? ""}' == v,
                                    orElse: () => _availableTrains.first,
                                  );
                                  return match.uid ?? '';
                                }).toList();
                              });
                            },
                            enabled: !isEditMode,
                          ),
                        ],

                        if (selectedContractType != null && selectedContractType != 'Station Cleaning' && selectedContractType != 'OBHS' && selectedContractType != 'MCC') ...[
                          const SizedBox(height: 12),
                          const Text('Assigned Stations *', style: TextStyle(fontWeight: FontWeight.w500)),
                          const SizedBox(height: 4),
                          _stationsLoading
                              ? const SizedBox(height: 40, child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
                              : AbsorbPointer(
                                  absorbing: isEditMode,
                                  child: Opacity(
                                    opacity: isEditMode ? 0.5 : 1.0,
                                    child: _buildMultiSelectDropdown(
                                      "Stations",
                                      "Select stations",
                                      _availableStations.map((s) => '${s.stationCode} - ${s.stationName}').toList(),
                                      selectedStationNames,
                                      (values) {
                                        setState(() {
                                          selectedStationNames = values;
                                          selectedStationIds = values.map((v) {
                                            final match = _availableStations.firstWhere(
                                              (s) => '${s.stationCode} - ${s.stationName}' == v,
                                              orElse: () => _availableStations.first,
                                            );
                                            return match.uid ?? match.stationCode;
                                          }).toList();
                                        });
                                      },
                                      enabled: !isEditMode,
                                    ),
                                  ),
                                ),
                        ],
                        _buildTextField(
                          "Remarks",
                          "Notes about scope or location",
                          remarksController,
                          lines: 3,
                          enabled: !isEditMode,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  _buildCard(
                    title: "Authorized Representative",
                    icon: Icons.person,
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: _buildTextField(
                                "Name *",
                                "Representative Name",
                                repNameController,
                                enabled: true,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _buildTextField(
                                "Designation *",
                                "Enter Designation",
                                repDesignationController,
                                enabled: true,
                              ),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: _buildTextField(
                                "Mobile Number *",
                                "Mobile Number",
                                repMobileController,
                                number: true,
                                enabled: true,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _buildTextField(
                                "Email ID *",
                                "Representative Email",
                                repEmailController,
                                enabled: true,
                              ),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: _buildDropdown(
                                'ID Proof Type *',
                                'Choose ID',
                                ["Passport", "PAN", "Aadhaar"],
                                selectedIDType,
                                    (v) => setState(() => selectedIDType = v),
                                enabled: true,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _buildTextField(
                                "ID Proof Number *",
                                "Enter Number",
                                repIdNumberController,
                                enabled: true,
                              ),
                            ),
                          ],
                        ),
                        if (!isEditMode)
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              const Text('Upload ID Proof *',
                                  style: TextStyle(fontSize: 13)),
                              const Spacer(),
                              OutlinedButton.icon(
                                icon: const Icon(Icons.attach_file, size: 18),
                                label: Text(
                                  idProofFile ?? "Choose File",
                                  style: const TextStyle(fontSize: 12),
                                ),
                                onPressed: () async {
                                  FilePickerResult? result =
                                  await FilePicker.platform.pickFiles(type: FileType.any);
                                   if (result != null) {
                                     setState(() {
                                       idProofFile = result.files.single.name;
                                     });
                                   }
                                },
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  if (!isEditMode)
                    _buildCard(
                      title: "Contract Documents",
                      icon: Icons.folder,
                      child: Row(
                        children: [
                          Expanded(
                            child: _buildFilePicker(
                              "Contract Copy /\nGEM Agreement *",
                              gemAwardLetterFile,
                                  (f) => setState(() => gemAwardLetterFile = f),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _buildFilePicker(
                              "Declaration\nForm *",
                              declarationFormFile,
                                  (f) => setState(() => declarationFormFile = f),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 16),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isLoading ? null : _saveContract,
                      icon: _isLoading
                          ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                          : const Icon(Icons.save, color: Colors.white),
                      label: Text(
                        _isLoading
                            ? "Saving..."
                            : (isEditMode ? "Update Contract" : "Save Contract"),
                        style: const TextStyle(fontSize: 16, color: Colors.white),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2E7D32),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_isLoading)
            Container(
              color: Colors.black26,
              child: const Center(
                child: CircularProgressIndicator(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCard({
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF1565C0).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: const Color(0xFF1565C0)),
              ),
              const SizedBox(width: 12),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1565C0),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          child,
        ],
      ),
    );
  }

  Widget _buildTextField(
      String label,
      String hint,
      TextEditingController controller, {
        int lines = 1,
        bool number = false,
        bool enabled = true,
      }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
          const SizedBox(height: 6),
          TextFormField(
            controller: controller,
            enabled: enabled,
            keyboardType: number ? TextInputType.number : TextInputType.text,
            inputFormatters: number
                ? [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(10),
            ]
                : [],
            maxLines: lines,
            decoration: InputDecoration(
              hintText: hint,
              filled: !enabled,
              fillColor: Colors.grey[200],
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFF1565C0), width: 2),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            validator: (value) {
              if (label.contains('*') && (value == null || value.isEmpty)) {
                return "Required field";
              }
              if (label.contains('Email') && value != null && value.isNotEmpty) {
                if (AppValidators.email(value) != null) {
                  return "Enter valid email";
                }
              }
              if (label.contains('Mobile') && value != null && value.isNotEmpty) {
                final mobileErr = AppValidators.mobile(value, required: false);
                if (mobileErr != null) {
                  return mobileErr;
                }
              }
              if (label.contains('ID Proof Number') && value != null && value.isNotEmpty && selectedIDType != null) {
                final trimmed = value.trim().toUpperCase();
                if (selectedIDType == 'Aadhaar') {
                  if (!RegExp(r'^\d{12}$').hasMatch(value.trim())) {
                    return 'Enter valid 12-digit Aadhaar number';
                  }
                } else if (selectedIDType == 'PAN') {
                  if (!RegExp(r'^[A-Z]{5}[0-9]{4}[A-Z]$').hasMatch(trimmed)) {
                    return 'Enter valid PAN number';
                  }
                } else if (selectedIDType == 'Passport') {
                  if (value.trim().length < 6) {
                    return 'Enter valid Passport number';
                  }
                }
              }
              return null;
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDropdown(
      String label,
      String hint,
      List<String> items,
      String? value,
      Function(String?) onSelect, {
        bool enabled = true,
      }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            value: value != null && items.contains(value) ? value : null,
            decoration: InputDecoration(
              hintText: hint,
              filled: !enabled,
              fillColor: Colors.grey[200],
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFF1565C0), width: 2),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            isExpanded: true,
            items: items
                .map(
                  (v) => DropdownMenuItem(
                value: v,
                child: Text(
                  v,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
            )
                .toList(),
            onChanged: enabled ? onSelect : null,
            validator: (value) {
              if (label.contains('*') && value == null) {
                return "Required field";
              }
              return null;
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMultiSelectDropdown(
      String label,
      String hint,
      List<String> items,
      List<String> selectedItems,
      Function(List<String>) onSelect, {
        bool enabled = true,
      }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
          const SizedBox(height: 6),
          InkWell(
            onTap: !enabled
                ? null
                : () async {
              final List<String>? result = await showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: Text(label),
                  content: StatefulBuilder(
                    builder: (context, setDialogState) {
                      return SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: items.map((item) {
                            final isSelected = selectedItems.contains(item);
                            return CheckboxListTile(
                              value: isSelected,
                              title: Text(item),
                              onChanged: (checked) {
                                setDialogState(() {
                                  if (checked == true) {
                                    selectedItems.add(item);
                                  } else {
                                    selectedItems.remove(item);
                                  }
                                });
                              },
                            );
                          }).toList(),
                        ),
                      );
                    },
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, null),
                      child: const Text("Cancel"),
                    ),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, selectedItems),
                      child: const Text("OK"),
                    ),
                  ],
                ),
              );

              if (result != null) {
                onSelect(result);
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              decoration: BoxDecoration(
                color: !enabled ? Colors.grey[200] : null,
                border: Border.all(color: Colors.grey.shade400),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      selectedItems.isEmpty ? hint : selectedItems.join(', '),
                      style: TextStyle(
                        color: selectedItems.isEmpty ? Colors.grey : Colors.black,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (enabled) const Icon(Icons.arrow_drop_down),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateField(String label, DateTime? date, Function(DateTime) onSelect,
      {bool enabled = true}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
          const SizedBox(height: 6),
          InkWell(
            onTap: !enabled
                ? null
                : () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: date ?? DateTime.now(),
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
              );
              if (picked != null) {
                onSelect(picked);
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              decoration: BoxDecoration(
                color: !enabled ? Colors.grey[200] : null,
                border: Border.all(color: Colors.grey.shade400),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    date != null ? "${date.day}/${date.month}/${date.year}" : "Select Date",
                    style: TextStyle(
                      color: date == null ? Colors.grey : Colors.black,
                    ),
                  ),
                  if (enabled) const Icon(Icons.calendar_today, size: 18),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilePicker(String label, String? fileName, Function(String) onPicked) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
        const SizedBox(height: 6),
        OutlinedButton.icon(
          icon: const Icon(Icons.attach_file, size: 18),
          label: Text(
            fileName ?? "Choose File",
            style: const TextStyle(fontSize: 12),
            overflow: TextOverflow.ellipsis,
          ),
          onPressed: () async {
            FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.any);
            if (result != null) {
              onPicked(result.files.single.name);
            }
          },
        ),
      ],
    );
  }

  Future<void> _saveContract() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (isEditMode) {
      if (selectedStatus == null) {
        _showErrorSnackBar("Please select a status");
        return;
      }
      if (repNameController.text.isEmpty ||
          repDesignationController.text.isEmpty ||
          repMobileController.text.isEmpty ||
          repEmailController.text.isEmpty || selectedIDType == null ||
          repIdNumberController.text.isEmpty) {
        _showErrorSnackBar("Please fill all representative details");
        return;
      }
    } else {
      if (contractNoController.text.isEmpty || contractNameController.text.isEmpty) {
        _showErrorSnackBar("Please provide Contract Number and Contract Name");
        return;
      }
      if (selectedEntity == null) {
        _showErrorSnackBar("Please select an entity");
        return;
      }
      if (selectedZone == null) {
        _showErrorSnackBar("Please select a zone");
        return;
      }
      if (startDate == null || endDate == null) {
        _showErrorSnackBar("Please select start and end dates");
        return;
      }
      if (selectedWorkCategories.isEmpty) {
        _showErrorSnackBar("Please select at least one work category");
        return;
      }
      if (selectedContractType == 'OBHS' && selectedTrainIds.isEmpty) {
        _showErrorSnackBar("Please select at least one train");
        return;
      }
      if (selectedContractType != 'Station Cleaning' && selectedContractType != 'OBHS' && selectedStationIds.isEmpty) {
        _showErrorSnackBar("Please select at least one station");
        return;
      }
    }

    setState(() => _isLoading = true);

    try {
      final response;

      if (isEditMode) {
        response = await ApiService.updateContract(
          contractId: widget.contract!.uid,
          status: selectedStatus!,
          contractValue: double.tryParse(contractValueController.text),
          billingCycle: selectedBillingCycle,
          scoringApplicability: scoringApplicability,
          repName: repNameController.text,
          repDesignation: repDesignationController.text,
          repMobile: repMobileController.text,
          repEmail: repEmailController.text,
          repIdProofType: selectedIDType!,
          repIdProofNumber: repIdNumberController.text,
        );
      } else {
        String formattedStartDate = startDate!.toIso8601String();
        String formattedEndDate = endDate!.toIso8601String();
        String workCategoriesString = selectedWorkCategories.join(',');

        response = await ApiService.createContract(
          contractNumber: contractNoController.text,
          contractName: contractNameController.text,
          entityId: selectedEntity!,
          zone: selectedZone!,
          division: selectedDivision,
          depot: selectedDepot,
          stationIds: (selectedContractType == 'Station Cleaning' || selectedContractType == 'MCC')
              ? (_manualStationId != null ? [_manualStationId!] : null)
              : (selectedStationIds.isNotEmpty ? selectedStationIds : null),
          trainIds: selectedContractType == 'OBHS' ? (selectedTrainIds.isNotEmpty ? selectedTrainIds : null) : null,
          startDate: formattedStartDate,
          endDate: formattedEndDate,
          contractValue: double.tryParse(contractValueController.text) ?? 0,
          billingCycle: selectedBillingCycle,
          scoringApplicability: scoringApplicability,
          workCategories: workCategoriesString,
          remarks: remarksController.text.isEmpty ? null : remarksController.text,
          status: selectedStatus ?? 'Active',
          repName: repNameController.text,
          repDesignation: repDesignationController.text,
          repMobile: repMobileController.text,
          repEmail: repEmailController.text,
          repIdProofType: selectedIDType!,
          repIdProofNumber: repIdNumberController.text,
          contractType: selectedContractType != null ? selectedContractType!.toLowerCase().replaceAll(' ', '_') : null,
        );

        if (mounted) {
          _showSuccessSnackBar(
              response['message'] ??
                  (isEditMode
                      ? "Contract updated successfully!"
                      : "Contract created successfully!"));
          Navigator.pop(context, true);
        }
      }
    } catch (e) {
      if (mounted) {
        _showErrorSnackBar("Failed to save contract: ${e.toString()}");
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}