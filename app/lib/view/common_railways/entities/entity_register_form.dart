import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../model/user_entity_model.dart';
import '../../../providers/auth_provider.dart';
import '../../../services/api_services.dart';
import 'package:file_picker/file_picker.dart';
import '../../../services/draft_storage_service.dart';
import '../../../utills/app_colors.dart';
import '../../../utills/validators.dart';

class EntityRegisterForm extends StatefulWidget {
  final Map<String, dynamic>? draftData;
  final String? draftId;
  final EntityModel? entity;

  const EntityRegisterForm({
    super.key,
    this.draftData,
    this.draftId,
    this.entity,
  });

  @override
  State<EntityRegisterForm> createState() => _EntityRegisterFormState();
}

class _EntityRegisterFormState extends State<EntityRegisterForm> {
  final _step1FormKey = GlobalKey<FormState>();
  String? selectedType;
  int currentStep = 1;
  bool _isLoading = false;
  bool _isActive = true;

  String? gstCertFile;
  String? panFile;
  String? tradeLicenseFile;
  String? msmeCertFile;

  final TextEditingController _contractorNameCtrl = TextEditingController();
  final TextEditingController _panCtrl = TextEditingController();
  final TextEditingController _gstinCtrl = TextEditingController();
  final TextEditingController _addressCtrl = TextEditingController();
  final TextEditingController _contactCtrl = TextEditingController();
  final TextEditingController _alternateContactCtrl = TextEditingController();
  final TextEditingController _emailCtrl = TextEditingController();
  final TextEditingController _websiteCtrl = TextEditingController();
  final TextEditingController _yearCtrl = TextEditingController();
  final TextEditingController _gemIdCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.entity != null) {
      _loadEntityData();
    } else if (widget.draftData != null) {
      _loadDraftData();
    }
  }

  void _loadEntityData() {
    final entity = widget.entity!;
    setState(() {
      selectedType = entity.registrationType;
      _contractorNameCtrl.text = entity.contractorName ?? '';
      _panCtrl.text = entity.panNumber ?? '';
      _gstinCtrl.text = entity.gstinNumber ?? '';
      _addressCtrl.text = entity.registeredAddress ?? '';
      _contactCtrl.text = entity.contactNumber ?? '';
      _alternateContactCtrl.text = entity.alternateContact ?? '';
      _emailCtrl.text = entity.email ?? '';
      _websiteCtrl.text = entity.website ?? '';
      _yearCtrl.text = entity.yearOfEstablishment ?? '';
      _gemIdCtrl.text = entity.gemId ?? '';

      final status = entity.status?.toUpperCase() ?? '';
      _isActive = status == 'APPROVED' || status == 'ACTIVE';

      print('Entity status from API: ${entity.status}');
      print('Switch _isActive set to: $_isActive');
    });
  }

  void _loadDraftData() {
    final draft = widget.draftData!;
    setState(() {
      selectedType = draft['companyType'];
      _contractorNameCtrl.text = draft['companyName'] ?? '';
      _panCtrl.text = draft['panNumber'] ?? '';
      _gstinCtrl.text = draft['gstinNumber'] ?? '';
      _addressCtrl.text = draft['address'] ?? '';
      _contactCtrl.text = draft['contactNumber'] ?? '';
      _alternateContactCtrl.text = draft['alternateContactNumber'] ?? '';
      _emailCtrl.text = draft['emailId'] ?? '';
      _websiteCtrl.text = draft['website'] ?? '';
      _yearCtrl.text = draft['yearOfEstablishment'] ?? '';
      _gemIdCtrl.text = draft['gemId'] ?? '';
      gstCertFile = draft['gstCertFile'];
      panFile = draft['panFile'];
      tradeLicenseFile = draft['tradeLicenseFile'];
      msmeCertFile = draft['msmeCertFile'];
    });
  }

  @override
  void dispose() {
    _contractorNameCtrl.dispose();
    _panCtrl.dispose();
    _gstinCtrl.dispose();
    _addressCtrl.dispose();
    _contactCtrl.dispose();
    _alternateContactCtrl.dispose();
    _emailCtrl.dispose();
    _websiteCtrl.dispose();
    _yearCtrl.dispose();
    _gemIdCtrl.dispose();
    super.dispose();
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.green),
    );
  }

  Future<bool> _showDeactivateConfirmation() async {
    return await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: const [
            Text('Suspend Entity?'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text(
              'Are you sure you want to suspend this entity?',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
            ),
            SizedBox(height: 12),
            Text(
              'Warning:',
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Text(
              '• Entity status will be changed to SUSPENDED',
              style: TextStyle(fontSize: 13),
            ),
            SizedBox(height: 4),
            Text(
              '• All users associated with this entity will be automatically deactivated',
              style: TextStyle(fontSize: 13),
            ),
            SizedBox(height: 4),
            Text(
              '• All contractors linked to this entity will be automatically deactivated',
              style: TextStyle(fontSize: 13),
            ),
            SizedBox(height: 12),
            Text(
              'You can reactivate the entity later by turning the switch ON. This will change the status to APPROVED.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Yes, Suspend', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    ) ?? false;
  }

  Future<void> _submitForm() async {
    if (selectedType == null) {
      _showError("Please select a Registration Type");
      return;
    }

    if (selectedType!.isEmpty) {
      _showError("Please select a Registration Type");
      return;
    }

    if (_contractorNameCtrl.text.trim().isEmpty) {
      _showError("Contractor Name is required");
      return;
    }

    if (_panCtrl.text.trim().isEmpty) {
      _showError("PAN Number is required");
      return;
    }

    if (_gstinCtrl.text.trim().isEmpty) {
      _showError("GSTIN Number is required");
      return;
    }

    final panErr = AppValidators.pan(_panCtrl.text);
    if (panErr != null) {
      _showError(panErr);
      return;
    }
    final gstinErr = AppValidators.gstin(_gstinCtrl.text);
    if (gstinErr != null) {
      _showError(gstinErr);
      return;
    }

    if (_addressCtrl.text.trim().isEmpty) {
      _showError("Registered Address is required");
      return;
    }

    if (_contactCtrl.text.trim().isEmpty) {
      _showError("Contact Number is required");
      return;
    }

    if (_emailCtrl.text.trim().isEmpty) {
      _showError("Email is required");
      return;
    }

    if (_gemIdCtrl.text.trim().isEmpty) {
      _showError("GEM ID is required");
      return;
    }


    setState(() => _isLoading = true);

    try {
      final String contractorName = _contractorNameCtrl.text.trim();
      final String registrationType = selectedType!; // No ! operator
      final String panNumber = _panCtrl.text.trim();
      final String gstinNumber = _gstinCtrl.text.trim();
      final String registeredAddress = _addressCtrl.text.trim();
      final String contactNumber = _contactCtrl.text.trim();
      final String? alternateContact = _alternateContactCtrl.text.trim().isEmpty
          ? null
          : _alternateContactCtrl.text.trim();
      final String email = _emailCtrl.text.trim();
      final String? website = _websiteCtrl.text.trim().isEmpty
          ? null
          : _websiteCtrl.text.trim();
      final String? yearOfEstablishment = _yearCtrl.text.trim().isEmpty
          ? null
          : _yearCtrl.text.trim();
      final String gemId = _gemIdCtrl.text.trim();

      final Map<String, dynamic> result;

      if (widget.entity != null) {
        final entityData = {
          'companyName': contractorName,
          'registrationType': registrationType,
          'panNumber': panNumber,
          'gstinNumber': gstinNumber,
          'registeredAddress': registeredAddress,
          'contactNumber': contactNumber,
          'alternateContact': alternateContact,
          'email': email,
          'website': website,
          'yearOfEstablishment': yearOfEstablishment,
          'gemId': gemId,
          'status': 'PENDING',
        };

        result = await ApiService.updateEntity(
          uid: widget.entity!.uid,
          entityData: entityData,
        );
      } else {
        result = await ApiService.createEntity(
          contractorName: contractorName,
          registrationType: registrationType,
          panNumber: panNumber,
          gstinNumber: gstinNumber,
          registeredAddress: registeredAddress,
          contactNumber: contactNumber,
          alternateContact: alternateContact,
          email: email,
          website: website,
          yearOfEstablishment: yearOfEstablishment,
          gemId: gemId,
        );
      }

      setState(() => _isLoading = false);

      final message = result['message'] ??
          (widget.entity != null ? 'Entity updated successfully!' : 'Entity registered successfully!');
      _showSuccess(message);

      await Future.delayed(const Duration(milliseconds: 500));

      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e, stackTrace) {
      setState(() => _isLoading = false);
      _showError(widget.entity != null
          ? 'Failed to update entity: ${e.toString()}'
          : 'Failed to register entity: ${e.toString()}');
    }
  }

  Future<void> _saveDraft() async {
    final currentUser = Provider.of<AuthProvider>(context, listen: false).currentUser;

    if (currentUser?.uid == null) {
      _showError('User not logged in');
      return;
    }

    print('Saving entity draft for user: ${currentUser!.uid}');

    final draftData = {
      'companyType': selectedType,
      'companyName': _contractorNameCtrl.text.trim(),
      'panNumber': _panCtrl.text.trim(),
      'gstinNumber': _gstinCtrl.text.trim(),
      'address': _addressCtrl.text.trim(),
      'contactNumber': _contactCtrl.text.trim(),
      'alternateContactNumber': _alternateContactCtrl.text.trim(),
      'emailId': _emailCtrl.text.trim(),
      'website': _websiteCtrl.text.trim(),
      'yearOfEstablishment': _yearCtrl.text.trim(),
      'gemId': _gemIdCtrl.text.trim(),
      'gstCertFile': gstCertFile,
      'panFile': panFile,
      'tradeLicenseFile': tradeLicenseFile,
      'msmeCertFile': msmeCertFile,
    };

    print('Draft data: ${draftData.toString()}');

    setState(() => _isLoading = true);

    final success = await DraftStorageService.saveEntityDraft(
      currentUserId: currentUser.uid!,
      draftData: draftData,
      draftId: widget.draftId,
    );

    setState(() => _isLoading = false);

    print('Draft save result: $success');

    if (success) {
      _showSuccess('Draft saved successfully');
      await Future.delayed(const Duration(seconds: 1));
      Navigator.pop(context, true);
    } else {
      _showError('Failed to save draft');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.entity != null ? "Edit Entity" : "Entity Registration",
          style: const TextStyle(
            color: Colors.black87,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: _isLoading
          ? const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Submitting entity registration...'),
          ],
        ),
      )
          : SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildStepCircle("1", "Entity Info", currentStep > 1, currentStep == 1),
                _buildLine(),
                _buildStepCircle("2", "Documents", currentStep > 2, currentStep == 2),
              ],
            ),
            const SizedBox(height: 24),

            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 6,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: currentStep == 1 ? _buildBasicInfoForm() : _buildDocumentForm(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBasicInfoForm() {
    return Form(
      key: _step1FormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Entity Information",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              SizedBox(height: 4),
              Text(
                "Basic contractor entity details",
                style: TextStyle(color: Colors.grey),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _buildTextField(
            _contractorNameCtrl,
            "Company Name *",
            "Enter company name",
          ),
          _buildDropdown(
            "Registration Type *",
            "Select Type",
            ["Proprietorship", "Partnership", "Pvt Ltd", "LLP", "PSU"],
                (v) {
              setState(() => selectedType = v);
            },
          ),
          _buildTextField(
            _panCtrl,
            "PAN Number *",
            "ABCDE1234F",
            isPan: true,
          ),
          _buildTextField(
            _gstinCtrl,
            "GSTIN Number *",
            "22ABBCD1234F1Z5",
            isGst: true,
          ),
          _buildTextField(
            _addressCtrl,
            "Registered Address *",
            "Complete registered address as per incorporation",
            lines: 3,
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _buildTextField(
                  _contactCtrl,
                  "Contact Number *",
                  "10 digit number",
                  number: true,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildTextField(
                  _alternateContactCtrl,
                  "Alternate Contact",
                  "10 digit number",
                  number: true,
                ),
              ),
            ],
          ),
          _buildTextField(_emailCtrl, "Email *", "Enter your email"),
          _buildTextField(_websiteCtrl, "Website", "www.example.com"),
          _buildTextField(
            _yearCtrl,
            "Year of Establishment",
            "YYYY",
            number: true,
          ),
          _buildTextField(_gemIdCtrl, "GEM ID *", "G5FDVG529"),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                if (selectedType == null) {
                  _showError("Please select a Registration Type");
                  return;
                }
                if (_step1FormKey.currentState!.validate()) {
                  setState(() => currentStep = 2);
                }
              },
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                backgroundColor: Colors.blueAccent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text(
                "Next",
                style: TextStyle(fontSize: 16, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDocumentForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Document Upload",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            SizedBox(height: 4),
            Text(
              "Entity registration documents (Optional for now)",
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
        const SizedBox(height: 24),

        Row(
          children: [
            _buildFilePicker("PAN CARD", (f) => panFile = f),
            const SizedBox(width: 20),
            _buildFilePicker("GST Certificate", (f) => gstCertFile = f),
          ],
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildFilePicker(
              "Trade License /\nRegistration Certificate",
                  (f) => tradeLicenseFile = f,
            ),
            const SizedBox(width: 20),
            _buildFilePicker(
              "MSME / ISO\nCertificate",
                  (f) => msmeCertFile = f,
            ),
          ],
        ),

        const SizedBox(height: 16),

        if (widget.entity != null) ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _isActive ? Colors.green.shade200 : Colors.red.shade200,
                width: 2,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: (_isActive ? Colors.green : Colors.red).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        _isActive ? Icons.check_circle : Icons.cancel,
                        color: _isActive ? Colors.green : Colors.red,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Entity Status',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _isActive
                                ? 'APPROVED - Entity is active and operational'
                                : 'SUSPENDED - Entity is temporarily deactivated',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: _isActive,
                      activeColor: Colors.green,
                      inactiveThumbColor: Colors.red,
                      onChanged: (value) async {
                        if (!value) {
                          final confirmed = await _showDeactivateConfirmation();
                          if (confirmed) {
                            setState(() => _isActive = value);
                          }
                        } else {
                          setState(() => _isActive = value);
                        }
                      },
                    ),
                  ],
                ),
                if (!_isActive) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: const [
                        Icon(Icons.warning_amber_rounded, color: Colors.red, size: 20),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'This entity will be suspended along with all associated users and contractors.',
                            style: TextStyle(fontSize: 11, color: Colors.red),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Row(
            children: [
              Icon(Icons.info_outline, color: Colors.blueAccent),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  "Documents can be uploaded later. Click Submit to register the entity.",
                  style: TextStyle(fontSize: 12, color: Colors.black87),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 24),

        SizedBox(
          width: double.infinity,
          child: _navButton(
            "Previous",
            Colors.grey.shade200,
            Colors.black,
                () {
              setState(() => currentStep = 1);
            },
            Icons.arrow_back,
          ),
        ),

        const SizedBox(height: 12),

        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  side: BorderSide(color: kRailwayBlue, width: 2),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                icon: Icon(Icons.save_outlined, color: kRailwayBlue, size: 18),
                label: Text(
                  'Save as Draft',
                  style: TextStyle(color: kRailwayBlue, fontSize: 14),
                ),
                onPressed: _saveDraft,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: kRailwayBlue,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                icon: Icon(
                  widget.entity != null ? Icons.check : Icons.send,
                  color: Colors.white,
                  size: 18,
                ),
                label: Text(
                  widget.entity != null ? 'Update Entity' : 'Submit',
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
                onPressed: _submitForm,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildFilePicker(String label, Function(String) onPicked) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 6),
            OutlinedButton.icon(
              icon: const Icon(Icons.attach_file, size: 18),
              label: const Text("Choose File", style: TextStyle(fontSize: 12)),
              onPressed: () async {
                try {
                  FilePickerResult? result = await FilePicker.platform.pickFiles(
                    type: FileType.custom,
                    allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
                    allowMultiple: false,
                  );

                  if (result != null && result.files.isNotEmpty) {
                    final pickedFile = result.files.first;
                    final fileName = pickedFile.name;

                    onPicked(fileName);
                    setState(() {});

                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('$label selected: $fileName'),
                        backgroundColor: Colors.green,
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('No file selected'),
                        backgroundColor: Colors.orange,
                        duration: Duration(seconds: 1),
                      ),
                    );
                  }
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error picking file: $e'),
                      backgroundColor: Colors.red,
                      duration: const Duration(seconds: 2),
                    ),
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _navButton(
      String text,
      Color bg,
      Color textColor,
      VoidCallback onPressed,
      IconData icon,
      ) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      style: ElevatedButton.styleFrom(
        backgroundColor: bg,
        foregroundColor: textColor,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      label: Text(text, style: TextStyle(color: textColor, fontSize: 16)),
    );
  }

  Widget _buildDropdown(
      String label,
      String hint,
      List<String> items,
      Function(String) onSelect,
      ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            value: selectedType != null && items.contains(selectedType) ? selectedType : null,
            decoration: _inputDecoration(hint),
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
            onChanged: (v) {
              if (v != null) {
                onSelect(v);
              }
            },
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

  Widget _buildStepCircle(String number, String label, bool completed, bool active) {
    return Column(
      children: [
        CircleAvatar(
          radius: 16,
          backgroundColor: completed
              ? Colors.blue
              : (active ? Colors.blue : Colors.grey.shade300),
          child: completed
              ? const Icon(Icons.check, color: Colors.white, size: 16)
              : Text(
            number,
            style: TextStyle(
              color: active ? Colors.white : Colors.black54,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: active ? Colors.blue : (completed ? Colors.blue : Colors.grey),
          ),
        ),
      ],
    );
  }

  Widget _buildLine() {
    return Container(height: 1.5, width: 60, color: Colors.grey.shade300);
  }

  Widget _buildTextField(
      TextEditingController controller,
      String label,
      String hint, {
        int lines = 1,
        bool number = false,
        bool isPan = false,
        bool isGst = false,
      }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label),
          const SizedBox(height: 6),
          TextFormField(
            controller: controller,
            keyboardType: number ? TextInputType.number : TextInputType.text,
            textCapitalization: (isPan || isGst)
                ? TextCapitalization.characters
                : TextCapitalization.none,
            inputFormatters: (isPan || isGst)
                ? [
              LengthLimitingTextInputFormatter(isPan ? 10 : 15),
              FilteringTextInputFormatter.allow(
                RegExp(r'[A-Z0-9]'),
              ),
            ]
                : number
                ? [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(
                label.contains('Year') ? 4 : 10,
              ),
            ]
                : [],
            maxLines: lines,
            decoration: _inputDecoration(hint),
            validator: (value) {
              if (label.contains('*') && (value == null || value.isEmpty)) {
                return "Required field";
              }
              if (isPan && value != null && value.isNotEmpty) {
                final err = AppValidators.pan(value, required: false);
                if (err != null) return err;
              }
              if (isGst && value != null && value.isNotEmpty) {
                final err = AppValidators.gstin(value, required: false);
                if (err != null) return err;
              }
              if (label.contains('Email') &&
                  label.contains('*') &&
                  value != null &&
                  value.isNotEmpty) {
                if (AppValidators.email(value) != null) {
                  return 'Invalid email format';
                }
              }
              if (label.contains('Contact') &&
                  value != null &&
                  value.isNotEmpty) {
                final contactErr = AppValidators.mobile(value, required: false);
                if (contactErr != null) {
                  return contactErr;
                }
              }
              return null;
            },
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Colors.blueAccent, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Colors.red),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    );
  }
}