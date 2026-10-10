import 'package:crm_train/data/zone_database.dart';
import 'package:crm_train/providers/auth_provider.dart';
import 'package:crm_train/services/api_services.dart';
import 'package:crm_train/services/draft_storage_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'dart:math';
import '../../../utills/app_colors.dart';
import '../../../utills/validators.dart';
import '../../../model/train_model.dart';
import '../../../model/station_models.dart';
import '../../../model/platform_model.dart';
import '../../../repositories/platform_repository.dart';
import '../widgets/approve_entity_dropdown.dart';
import '../widgets/contract_dropdown.dart';
import 'package:file_picker/file_picker.dart';
import 'package:signature/signature.dart';
import 'dart:convert';

class UserRegistrationScreen extends StatefulWidget {
  final Map<String, dynamic>? draftData;
  final String? draftId;

  const UserRegistrationScreen({super.key, this.draftData, this.draftId});

  @override
  State<UserRegistrationScreen> createState() => _UserRegistrationScreenState();
}

class _UserRegistrationScreenState extends State<UserRegistrationScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _fullName = TextEditingController();
  final TextEditingController _designation = TextEditingController();
  final TextEditingController _email = TextEditingController();
  final TextEditingController _mobile = TextEditingController();
  final TextEditingController _aadhaar = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final SignatureController _signatureController = SignatureController(
    penStrokeWidth: 3,
    penColor: Colors.black,
    exportBackgroundColor: Colors.transparent,
  );
  final TextEditingController _stationNameController = TextEditingController();

  String _selectedUserType = 'railway';
  String? _selectedRole;
  String? _selectedCompany;
  String? _selectedCompanyName;
  String? _zone;
  String? _division;
  String? _depot;
  bool _obscurePassword = true;

  List<String> zones = [];
  List<String> divisions = [];
  List<String> depots = [];
  List<dynamic> contractorCompanies = [];
  List<TrainModel> allTrains = [];
  String? _workerType;
  String? _trainId;
  List<String> _selectedTrainIds = [];

  String? _selectedStationId;
  String? _selectedAreaId;
  String? _selectedPlatformId;

  Map<String, String> pickedDocs = {};

  bool _isLoading = false;
  List<Station> _entityStations = [];

  String? _selectedContractId;
  Map<String, dynamic>? _selectedContractData;
  List<String> _selectedContractStationIds = [];
  String? _contractDivision;
  bool _isContractAutoAssigned = false;
  bool _isEntityAutoAssigned = false;

  // Contractor Admin / Contractor Master (or any contractor-role user) can
  // only ever create contractor users — they must never be offered the
  // 'Railway' user type.
  bool get _isContractorRoleUser {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final role = auth.currentUser?.role;
    if (role == 'Contractor Admin' || role == 'Contractor Master' || role == 'Contractor Supervisor' || role == 'CTS') return true;
    return (auth.currentUser?.userType ?? '').toLowerCase() == 'contractor';
  }

  List<String> get _userTypeOptions =>
      _isContractorRoleUser ? const ['contractor'] : const ['railway', 'contractor'];

  @override
  void initState() {
    super.initState();
    zones = DepotDatabase.zoneData.keys.toList();
    _generatePassword();

    if (widget.draftData != null) {
      _loadDraftData(widget.draftData!);
    }
    // Contractor-role users default to (and are locked into) 'contractor'.
    if (_isContractorRoleUser && _selectedUserType != 'contractor') {
      _selectedUserType = 'contractor';
      _selectedRole = null;
    }
    _loadAllTrains();
  }

  Future<void> _loadAllTrains() async {
    try {
      final trains = await ApiService.getActiveTrains();
      setState(() => allTrains = trains);
    } catch (e) {
      print('Error loading trains: $e');
    }
  }

  Future<void> _loadEntityStations(String entityId) async {
    try {
      final stations = await ApiService.getStations(entityId: entityId);
      final uniqueZones = <String>{};
      for (final s in stations) {
        if (s.zone.isNotEmpty) {
          for (final z in DepotDatabase.zoneData.keys) {
            if (z.toLowerCase().contains(s.zone.toLowerCase()) || s.zone.toLowerCase().contains(z.toLowerCase())) {
              uniqueZones.add(z);
              break;
            }
          }
        }
      }
      setState(() {
        final sortedUnique = uniqueZones.toList()..sort();
        zones = uniqueZones.isNotEmpty ? sortedUnique : (DepotDatabase.zoneData.keys.toList()..sort());
        _zone = null;
        _division = null;
        _depot = null;
        divisions = [];
        depots = [];
        _entityStations = [];
        _selectedStationId = null;
      });
    } catch (e) {
      print('Error loading entity stations: $e');
    }
  }

  Future<void> _loadDivisionStations(String division) async {
    try {
      final stations = await ApiService.getStations(division: division, active: true);
      setState(() => _entityStations = stations);
    } catch (e) {
      print('Error loading division stations: $e');
    }
  }

  String _entityLabel() {
    final name = _selectedCompanyName?.isNotEmpty == true ? _selectedCompanyName : null;
    return name ?? _selectedCompany ?? 'Auto-assigned';
  }

  Future<void> _autoAssignFromCurrentUser() async {
    final currentUser = Provider.of<AuthProvider>(context, listen: false).currentUser;
    final role = currentUser?.role;
    if (role != 'Contractor Admin' && role != 'Contractor Master' && role != 'Contractor Supervisor' && role != 'CTS') return;
    if (currentUser?.entityId == null || currentUser!.entityId!.isEmpty) return;
    try {
      final contracts = await ApiService.getContractsForDropdown(entityId: currentUser.entityId);
      final isMaster = role == 'Contractor Master';

      if (isMaster) {
        final first = contracts.isNotEmpty ? contracts.first : null;
        setState(() {
          _isEntityAutoAssigned = true;
          _isContractAutoAssigned = false;
          _selectedCompany = currentUser.entityId;
          _selectedCompanyName = (first?['entityName'] as String?)?.isNotEmpty == true ? first!['entityName'] as String? : null;
          _zone = _normalizeZoneFromContract(currentUser.zone);
          _division = _normalizeDivisionFromContract(_zone, currentUser.division);
          if (_zone != null && _zone!.isNotEmpty) {
            divisions = DepotDatabase.zoneData[_zone]?.keys.toList() ?? [];
          }
        });
        return;
      }

      Map<String, dynamic>? match;
      if (currentUser.contractId != null && currentUser.contractId!.isNotEmpty) {
        match = contracts.where((c) => c['uid'] == currentUser.contractId).firstOrNull;
      }
      match ??= contracts.where((c) => c['contractType'] == 'station_cleaning' || c['contractType'] == 'obhs').firstOrNull;
      match ??= contracts.firstOrNull;

      if (match != null) {
        final contractData = match;
        final rawZone = contractData['zone'] as String?;
        final rawDivision = contractData['division'] as String?;
        final normZone = _normalizeZoneFromContract(rawZone ?? currentUser.zone);
        final normDivision = _normalizeDivisionFromContract(normZone, rawDivision ?? currentUser.division);
        final zoneDivisions = normZone.isNotEmpty
            ? (DepotDatabase.zoneData[normZone]?.keys.toList() ?? <String>[])
            : <String>[];
        final contractStationIds = (contractData['stationIds'] as List?)?.cast<String>() ?? [];
        setState(() {
          _isEntityAutoAssigned = true;
          _isContractAutoAssigned = true;
          _selectedCompany = currentUser.entityId;
          _selectedCompanyName = (contractData['entityName'] as String?)?.isNotEmpty == true ? contractData['entityName'] as String? : null;
          _selectedContractId = contractData['uid'] as String? ?? currentUser.contractId;
          _selectedContractData = contractData;
          _selectedContractStationIds = contractStationIds;
          _selectedStationId = null;
          _zone = normZone;
          _division = normDivision;
          divisions = zoneDivisions;
          if (currentUser.trainId != null && currentUser.trainId!.isNotEmpty) {
            _trainId ??= currentUser.trainId;
            _selectedTrainIds = currentUser.trainIds?.isNotEmpty == true
                ? List<String>.from(currentUser.trainIds!)
                : [currentUser.trainId!];
          }
          if (normZone.isNotEmpty && !zones.contains(normZone)) {
            zones = [...zones, normZone];
          }
        });
        return;
      }
      setState(() {
        _isEntityAutoAssigned = true;
        _selectedCompany = currentUser.entityId;
        _zone = _normalizeZoneFromContract(currentUser.zone);
        _division = _normalizeDivisionFromContract(_zone, currentUser.division);
        if (currentUser.trainId != null && currentUser.trainId!.isNotEmpty) {
          _trainId ??= currentUser.trainId;
          _selectedTrainIds = currentUser.trainIds?.isNotEmpty == true
              ? List<String>.from(currentUser.trainIds!)
              : [currentUser.trainId!];
        }
        if (_zone != null && _zone!.isNotEmpty) {
          divisions = DepotDatabase.zoneData[_zone]?.keys.toList() ?? [];
        }
      });
    } catch (_) {}
  }

  void _loadDraftData(Map<String, dynamic> draft) {
    setState(() {
      _fullName.text = draft['fullName'] ?? '';
      _designation.text = draft['designation'] ?? '';
      _email.text = draft['email'] ?? '';
      _mobile.text = draft['mobile'] ?? '';
      _aadhaar.text = draft['aadhaarNumber'] ?? '';
      _password.text = draft['password'] ?? '';
      _selectedUserType = draft['userType'] ?? 'railway';
      _selectedRole = draft['role'];
      _selectedCompany = draft['entityId'];
      _selectedCompanyName = draft['entityName']?.toString().isNotEmpty == true ? draft['entityName'] as String? : null;
      _selectedContractId = draft['contractId'];
      _selectedContractStationIds = List<String>.from(draft['stations'] ?? []);
      if (_selectedContractStationIds.isNotEmpty) {
        _stationNameController.text = _selectedContractStationIds.first;
      }
      _zone = draft['zone'];
      _division = draft['division'];
      _depot = draft['depot'];
      _workerType = draft['worker_type'];
      _trainId = draft['trainId'];
      _selectedTrainIds = List<String>.from(draft['trainIds'] ?? []);

      if (_zone != null) {
        divisions = DepotDatabase.zoneData[_zone]?.keys.toList() ?? [];
        if (_division != null) {
          depots = DepotDatabase.zoneData[_zone]?[_division] ?? [];
        }
      }

      if (draft['documents'] != null && draft['documents'] is Map) {
        pickedDocs = Map<String, String>.from(draft['documents']);
      }
    });
  }


  void _generatePassword() {
    const chars = 'AaBbCcDdEeFfGgHhIiJjKkLlMmNnOoPpQqRrSsTtUuVvWwXxYyZz1234567890@#\$%&';
    final rand = Random.secure();
    final password = List.generate(12, (_) => chars[rand.nextInt(chars.length)]).join();
    _password.text = password;
  }

  void _loadDivisions(String zone) {
    final allDivs = DepotDatabase.zoneData[zone]?.keys.toList() ?? [];
    List<String> filtered = allDivs;
    if (_entityStations.isNotEmpty && _selectedCompany != null) {
      final entityDivs = _entityStations
          .where((s) => s.zone.isNotEmpty && (zone.toLowerCase().contains(s.zone.toLowerCase()) || s.zone.toLowerCase().contains(zone.toLowerCase())))
          .map((s) => s.division)
          .where((d) => d != null && d.isNotEmpty)
          .map((d) => d!)
          .toSet()
          .toList();
      if (entityDivs.isNotEmpty) {
        final matched = <String>{};
        for (final ed in entityDivs) {
          for (final dd in allDivs) {
            if (dd.toLowerCase().contains(ed.toLowerCase()) || ed.toLowerCase().contains(dd.toLowerCase())) {
              matched.add(dd);
              break;
            }
          }
        }
        final sortedMatched = matched.toList()..sort();
        filtered = matched.isNotEmpty ? sortedMatched : allDivs;
      }
    }
    setState(() {
      divisions = filtered;
      _division = null;
      depots = [];
      _depot = null;
    });
  }

  void _loadDepots(String zone, String division) {
    setState(() {
      depots = DepotDatabase.zoneData[zone]?[division] ?? [];
      _depot = null;
    });
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }


  bool _shouldShowZone() {
    if (_selectedRole == null) return false;
    return true;
  }

  bool _shouldShowDivision() {
    if (_selectedRole == null || _zone == null) return false;
    return _selectedRole!.contains('Admin') || _selectedRole!.contains('Supervisor') || _selectedRole!.contains('Worker') || _selectedRole!.contains('Inspector');
  }

  bool _shouldShowDepot() {
    if (_selectedRole == null || _division == null) return false;
    if (_selectedRole!.toLowerCase().contains('contractor supervisor')) return false;
    if (_selectedRole!.toLowerCase().contains('railway supervisor')) return true;
    return _selectedRole!.contains('Worker');
  }

  bool _shouldShowWorkerType() {
    if (_selectedRole == null) return false;
    final r = _selectedRole!.toLowerCase();
    return r.contains('worker') || r == 'janitor' || r == 'attendant';
  }

  bool _shouldShowTrainSelection() {
    if (_selectedRole == null) return false;
    final r = _selectedRole!.toUpperCase();
    if (r.contains('WORKER') || r == 'JANITOR' || r == 'ATTENDANT') return true;
    if (r.contains('SUPERVISOR') || r.contains('CTS')) {
      if (_selectedContractData != null) {
        final ct = _selectedContractData!['contractType'] as String?;
        if (ct == 'station_cleaning') return false;
      }
      return true;
    }
    return false;
  }

  bool _isContractorAdminOrSupervisor() {
    if (_selectedRole == null) return false;
    final r = _selectedRole!.toUpperCase().replaceAll(' ', '_');
    return r == 'CONTRACTOR_ADMIN' || r == 'CONTRACTOR_SUPERVISOR' || r == 'CTS' || r == 'CONTRACTOR_WORKER' || r == 'JANITOR' || r == 'ATTENDANT';
  }

  bool _isContractorMaster() {
    if (_selectedRole == null) return false;
    return _selectedRole!.toUpperCase().replaceAll(' ', '_') == 'CONTRACTOR_MASTER';
  }

  bool _shouldShowStationSelection() {
    if (_selectedRole == null) return false;
    if (_selectedRole!.toLowerCase().contains('master')) return false;
    if (_selectedRole!.toLowerCase().contains('worker')) return true;
    if (_selectedRole!.toLowerCase().contains('inspector')) return true;
    if (_selectedUserType == 'contractor' && _selectedCompany != null) return true;
    return false;
  }

  List<Station> _getFilteredStations() {
    return _entityStations;
  }

  Widget _buildStationDropdown() {
    if (_selectedUserType == 'contractor') {
      if (_division == null) {
        return const Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: Text('Select division first to see available stations', style: TextStyle(color: Colors.grey)),
        );
      }
      if (_entityStations.isEmpty) {
        return const Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: Text('No stations available in this division', style: TextStyle(color: Colors.grey)),
        );
      }
      final stations = _getFilteredStations();
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: DropdownButtonFormField<String>(
          value: (_selectedStationId != null && stations.any((s) => s.uid == _selectedStationId)) ? _selectedStationId : null,
          decoration: const InputDecoration(labelText: 'Station *', border: OutlineInputBorder()),
          items: stations.map((s) => DropdownMenuItem(value: s.uid, child: Text(s.stationName))).toList(),
          validator: (v) => v == null ? 'Select station' : null,
          onChanged: (v) => setState(() => _selectedStationId = v),
        ),
      );
    }
    // Non-contractor: load all stations via FutureBuilder
    return FutureBuilder<List<Station>>(
      future: ApiService.getStations(),
      builder: (ctx, snap) {
        if (snap.connectionState != ConnectionState.done) return const Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: Center(child: CircularProgressIndicator()),
        );
        if (snap.hasError) return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text('Error loading stations', style: TextStyle(color: Colors.red)),
        );
        final rawStations = snap.data ?? [];
        final seenStationIds = <String>{};
        final stations = rawStations.where((s) {
          if (s.uid == null || s.uid!.isEmpty) return false;
          return seenStationIds.add(s.uid!);
        }).toList();
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: DropdownButtonFormField<String>(
            value: (_selectedStationId != null && stations.any((s) => s.uid == _selectedStationId)) ? _selectedStationId : null,
            decoration: InputDecoration(
              labelText: _selectedRole?.toLowerCase().contains('worker') == true
                  ? 'Station (Required for Station Worker)'
                  : 'Station *',
              border: const OutlineInputBorder(),
            ),
            items: stations.map((s) => DropdownMenuItem(value: s.uid, child: Text(s.stationName))).toList(),
            validator: (v) {
              return null;
            },
            onChanged: (v) => setState(() {
              _selectedStationId = v;
              _selectedAreaId = null;
              _selectedPlatformId = null;
            }),
          ),
        );
      },
    );
  }

  Widget _buildContractStationDropdown() {
    // If contract has stationIds, auto-assign and show read-only
    if (_selectedContractData != null) {
      final contractStationIds = (_selectedContractData!['stationIds'] as List?)?.cast<String>() ?? [];
      final contractStationNames = (_selectedContractData!['stationNames'] as List?)?.cast<String>() ?? [];
      if (contractStationIds.isNotEmpty) {
        _selectedContractStationIds = contractStationIds;
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Assigned Station', style: TextStyle(fontWeight: FontWeight.w500)),
              const SizedBox(height: 4),
              Chip(
                avatar: const Icon(Icons.check_circle, color: Colors.green, size: 18),
                label: Text(contractStationNames.isNotEmpty ? contractStationNames.first : contractStationIds.first),
              ),
            ],
          ),
        );
      }
    }
    // Fall back to manual text field
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: _stationNameController,
        decoration: const InputDecoration(
          labelText: 'Assigned Station *',
          hintText: 'Type station name',
          border: OutlineInputBorder(),
        ),
        validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
        onChanged: (v) {
          setState(() {
            _selectedContractStationIds = v.trim().isEmpty ? [] : [v.trim()];
          });
        },
      ),
    );
  }

  bool _isMultiTrainExport() {
    if (_selectedRole == null) return false;
    return _selectedRole!.toUpperCase() == 'RAILWAY SUPERVISOR';
  }

  bool _isZoneReadOnly() {
    final currentUser = Provider.of<AuthProvider>(context, listen: false).currentUser;
    return currentUser?.role == 'Railway Admin' ||
        currentUser?.role == 'Railway Master' ||
        currentUser?.role == 'Contractor Admin' ||
        currentUser?.role == 'Contractor Master';
  }

  bool _isDivisionReadOnly() {
    final currentUser = Provider.of<AuthProvider>(context, listen: false).currentUser;
    return currentUser?.role == 'Railway Admin' ||
        currentUser?.role == 'Contractor Admin';
  }

  bool _isContractAreaLocked() {
    return _isContractorAdminOrSupervisor() && _selectedContractId != null;
  }

  String _normalizeZoneFromContract(String? contractZone) {
    if (contractZone == null || contractZone.isEmpty) return '';
    if (DepotDatabase.zoneData.containsKey(contractZone)) return contractZone;
    final lower = contractZone.toLowerCase();
    for (final key in DepotDatabase.zoneData.keys) {
      if (key.toLowerCase() == lower) return key;
    }
    final codeMatch = RegExp(r'\((\w+)\)$').firstMatch(contractZone);
    if (codeMatch != null) {
      final code = codeMatch.group(1)!.toLowerCase();
      for (final key in DepotDatabase.zoneData.keys) {
        if (key.toLowerCase().contains('($code)')) return key;
      }
    }
    for (final key in DepotDatabase.zoneData.keys) {
      if (key.toLowerCase().contains(contractZone.toLowerCase()) ||
          contractZone.toLowerCase().contains(key.toLowerCase())) return key;
    }
    return contractZone;
  }

  String? _normalizeDivisionFromContract(String? zoneKey, String? contractDivision) {
    if (zoneKey == null || zoneKey.isEmpty || contractDivision == null || contractDivision.isEmpty) {
      return contractDivision;
    }
    final divisionsMap = DepotDatabase.zoneData[zoneKey]?.keys ?? {};
    if (divisionsMap.isEmpty) return contractDivision;
    if (divisionsMap.contains(contractDivision)) return contractDivision;
    final lower = contractDivision.toLowerCase();
    for (final div in divisionsMap) {
      if (div.toLowerCase() == lower) return div;
    }
    return contractDivision;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: kRailwayBlue,
        title: const Text('Create New User', style: TextStyle(color: Colors.white)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'User Details',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: kRailwayBlue,
                ),
              ),
              const SizedBox(height: 16),


              DropdownButtonFormField<String>(
                value: _userTypeOptions.contains(_selectedUserType) ? _selectedUserType : _userTypeOptions.first,
                decoration: const InputDecoration(
                  labelText: 'User Type *',
                  border: OutlineInputBorder(),
                ),
                items: _userTypeOptions
                    .map((u) => DropdownMenuItem(value: u, child: Text(u == 'railway' ? 'Railway' : 'Contractor')))
                    .toList(),
                onChanged: (v) => setState(() {
                  _selectedUserType = v!;
                  _selectedRole = null;
                  _zone = null;
                  _division = null;
                  _depot = null;
                  _entityStations = [];
                  _isEntityAutoAssigned = false;
                  zones = DepotDatabase.zoneData.keys.toList();
                }),
              ),
              const SizedBox(height: 12),


              if (_getRolesForUserType(_selectedUserType).isEmpty) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.amber.shade400),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.amber),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Railway Supervisors monitor and score work. They do not create users.',
                          style: TextStyle(color: Colors.black87),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ] else ...[
                DropdownButtonFormField<String>(
                  value: (_selectedRole != null && _getRolesForUserType(_selectedUserType).contains(_selectedRole)) ? _selectedRole : null,
                  decoration: const InputDecoration(
                    labelText: 'Role *',
                    border: OutlineInputBorder(),
                  ),
                  items: _getRolesForUserType(_selectedUserType)
                      .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                      .toList(),
                  validator: (v) => v == null ? 'Select role' : null,
                  onChanged: (v) {
                    setState(() {
                      _selectedRole = v;
                      if (v == 'Janitor') {
                        _workerType = 'Janitor';
                      } else if (v == 'Attendant') {
                        _workerType = 'Attendant';
                      } else if (v != 'Contractor Worker') {
                        _workerType = null;
                      }
                      _selectedCompany = null;
                      _selectedContractId = null;
                      _selectedContractData = null;
                      _selectedContractStationIds = [];
                      _selectedStationId = null;
                      _isContractAutoAssigned = false;
                      _isEntityAutoAssigned = false;
                      final currentUser = Provider.of<AuthProvider>(context, listen: false).currentUser;


                    if (currentUser?.role == 'Railway Admin') {
                      _zone = currentUser?.zone;
                      _division = currentUser?.division;
                      if (_zone != null) {
                        divisions = DepotDatabase.zoneData[_zone]?.keys.toList() ?? [];
                        if (_division != null) {
                          depots = DepotDatabase.zoneData[_zone]?[_division] ?? [];
                        }
                      }
                      _depot = null;
                    }

                    else if (currentUser?.role == 'Railway Master') {
                      _zone = currentUser?.zone;
                      if (_zone != null) {
                        divisions = DepotDatabase.zoneData[_zone]?.keys.toList() ?? [];
                      }
                      _division = null;
                      _depot = null;
                      depots = [];
                    }

                    else if (currentUser?.role == 'Contractor Admin') {
                      _zone = currentUser?.zone;
                      _division = currentUser?.division;
                      if (_zone != null) {
                        divisions = DepotDatabase.zoneData[_zone]?.keys.toList() ?? [];
                        if (_division != null) {
                          depots = DepotDatabase.zoneData[_zone]?[_division] ?? [];
                        }
                      }
                      _depot = null;
                    }

                    else if (currentUser?.role == 'Contractor Master') {
                      _zone = currentUser?.zone;
                      if (_zone != null) {
                        divisions = DepotDatabase.zoneData[_zone]?.keys.toList() ?? [];
                      }
                      _division = null;
                      _depot = null;
                      depots = [];
                    }

                    else {
                      _zone = null;
                      _division = null;
                      _depot = null;
                      divisions = [];
                      depots = [];
                    }
                  });
                  _autoAssignFromCurrentUser();
                },
              ),
              const SizedBox(height: 12),
              ],


              if (_selectedUserType == 'contractor') ...[
                if (_isContractAutoAssigned && _selectedContractData != null) ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Entity', style: TextStyle(fontWeight: FontWeight.w500)),
                        const SizedBox(height: 4),
                        Chip(avatar: const Icon(Icons.business, size: 18), label: Text(_entityLabel())),
                        const SizedBox(height: 8),
                        const Text('Contract', style: TextStyle(fontWeight: FontWeight.w500)),
                        const SizedBox(height: 4),
                        Chip(
                          avatar: const Icon(Icons.assignment, size: 18),
                          label: Text('${_selectedContractData!['contractNumber'] ?? ''} - ${_selectedContractData!['contractName'] ?? ''}'),
                        ),
                      ],
                    ),
                  ),
                  _buildContractStationDropdown(),
                ] else if (_isEntityAutoAssigned && _selectedCompany != null) ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Entity', style: TextStyle(fontWeight: FontWeight.w500)),
                        const SizedBox(height: 4),
                        Chip(avatar: const Icon(Icons.business, size: 18), label: Text(_entityLabel())),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  ContractDropdown(
                    entityId: _selectedCompany,
                    onSelected: (contractId, contractData) {
                      _stationNameController.clear();
                      final rawZone = contractData['zone'] as String?;
                      final rawDivision = contractData['division'] as String?;
                      final normZone = _normalizeZoneFromContract(rawZone);
                      final normDivision = _normalizeDivisionFromContract(normZone, rawDivision);
                      final zoneDivisions = normZone.isNotEmpty
                          ? (DepotDatabase.zoneData[normZone]?.keys.toList() ?? <String>[])
                          : <String>[];
                      setState(() {
                        _selectedContractId = contractId;
                        _selectedContractData = contractData;
                        _selectedCompanyName = (contractData['entityName'] as String?)?.isNotEmpty == true ? contractData['entityName'] as String? : _selectedCompanyName;
                        _selectedContractStationIds = [];
                        _selectedStationId = null;
                        _zone = normZone;
                        _division = normDivision;
                        divisions = zoneDivisions;
                        if (normZone.isNotEmpty && !zones.contains(normZone)) {
                          zones = [...zones, normZone];
                        }
                      });
                    },
                  ),
                  if (_selectedContractData != null) ...[
                    const SizedBox(height: 12),
                    _buildContractStationDropdown(),
                  ],
                ] else if (_selectedCompany != null && !_isContractAutoAssigned && _selectedRole != null && _selectedRole!.contains('Supervisor')) ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Entity', style: TextStyle(fontWeight: FontWeight.w500)),
                        const SizedBox(height: 4),
                        Chip(avatar: const Icon(Icons.business, size: 18), label: Text(_entityLabel())),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  ContractDropdown(
                    entityId: _selectedCompany,
                    onSelected: (contractId, contractData) {
                      _stationNameController.clear();
                      final rawZone = contractData['zone'] as String?;
                      final rawDivision = contractData['division'] as String?;
                      final normZone = _normalizeZoneFromContract(rawZone);
                      final normDivision = _normalizeDivisionFromContract(normZone, rawDivision);
                      final zoneDivisions = normZone.isNotEmpty
                          ? (DepotDatabase.zoneData[normZone]?.keys.toList() ?? <String>[])
                          : <String>[];
                      setState(() {
                        _selectedContractId = contractId;
                        _selectedContractData = contractData;
                        _selectedCompanyName = (contractData['entityName'] as String?)?.isNotEmpty == true ? contractData['entityName'] as String? : _selectedCompanyName;
                        _selectedContractStationIds = [];
                        _selectedStationId = null;
                        _zone = normZone;
                        _division = normDivision;
                        divisions = zoneDivisions;
                        if (normZone.isNotEmpty && !zones.contains(normZone)) {
                          zones = [...zones, normZone];
                        }
                      });
                    },
                  ),
                  if (_selectedContractData != null) ...[
                    const SizedBox(height: 12),
                    _buildContractStationDropdown(),
                  ],
                ] else ...[
                  ApprovedEntityDropdown(
                    onSelected: (name) {
setState(() {
        _selectedCompany = name;
        _selectedContractId = null;
        _selectedContractData = null;
        _selectedContractStationIds = [];
        _selectedStationId = null;
        _zone = null;
        _division = null;
      });
      _loadEntityStations(name);
    },
    onNameChanged: (entityName) {
      setState(() {
        _selectedCompanyName = (entityName ?? '').isNotEmpty ? entityName : null;
      });
    },
  ),
                  const SizedBox(height: 12),
                  if (_selectedCompany != null && !_isContractorMaster())
                    ContractDropdown(
                      entityId: _selectedCompany,
                      onSelected: (contractId, contractData) {
                        _stationNameController.clear();
                        final rawZone = contractData['zone'] as String?;
                        final rawDivision = contractData['division'] as String?;
                        final normZone = _normalizeZoneFromContract(rawZone);
                        final normDivision = _normalizeDivisionFromContract(normZone, rawDivision);
                        final zoneDivisions = normZone.isNotEmpty
                            ? (DepotDatabase.zoneData[normZone]?.keys.toList() ?? <String>[])
                            : <String>[];
                        setState(() {
                          _selectedContractId = contractId;
                          _selectedContractData = contractData;
                          _selectedContractStationIds = [];
                          _selectedStationId = null;
                          _zone = normZone;
                          _division = normDivision;
                          divisions = zoneDivisions;
                          if (normZone.isNotEmpty && !zones.contains(normZone)) {
                            zones = [...zones, normZone];
                          }
                        });
                      },
                    ),
                  if (_selectedContractData != null && !_isContractorMaster()) ...[
                    const SizedBox(height: 12),
                    _buildContractStationDropdown(),
                  ],
                ],
              ],



              if (_shouldShowStationSelection() && !_isContractorAdminOrSupervisor())
                _buildStationDropdown(),



              const SizedBox(height: 12),


              TextFormField(
                controller: _fullName,
                decoration: const InputDecoration(
                  labelText: 'Full Name *',
                  border: OutlineInputBorder(),
                  hintText: 'Enter full name (letters only)',
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
              const SizedBox(height: 12),


              TextFormField(
                controller: _designation,
                decoration: const InputDecoration(
                  labelText: 'Designation *',
                  border: OutlineInputBorder(),
                  hintText: 'e.g., Senior Engineer, Manager',
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9\s\.\-\,]')),
                ],
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return 'Designation is required';
                  }
                  if (v.trim().length < 2) {
                    return 'Designation must be at least 2 characters';
                  }
                  if (v.trim().length > 50) {
                    return 'Designation must not exceed 50 characters';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),


              TextFormField(
                controller: _email,
                decoration: const InputDecoration(
                  labelText: 'Official Email *',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.emailAddress,
                validator: AppValidators.email,
              ),
              const SizedBox(height: 12),


              TextFormField(
                controller: _mobile,
                decoration: const InputDecoration(
                  labelText: 'Mobile Number *',
                  border: OutlineInputBorder(),
                  hintText: '10 digit number',
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(10),
                ],
                validator: AppValidators.mobile,
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _aadhaar,
                decoration: const InputDecoration(
                  labelText: 'Aadhaar Number *',
                  border: OutlineInputBorder(),
                  hintText: '12 digit number',
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(12),
                ],
                validator: AppValidators.aadhaar,
              ),
              const SizedBox(height: 12),

              TextFormField(
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Password is required';
                  }
                  if (value.length < 6) {
                    return 'Password must be at least 6 characters';
                  }
                  return null;
                },
                controller: _password,
                obscureText: _obscurePassword,
                decoration: InputDecoration(
                  labelText: 'Generated Password',
                  border: const OutlineInputBorder(),
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: Icon(
                          _obscurePassword ? Icons.visibility : Icons.visibility_off,
                        ),
                        onPressed: () {
                          setState(() => _obscurePassword = !_obscurePassword);
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.refresh),
                        onPressed: () {
                          _generatePassword();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Password regenerated'),
                              duration: Duration(seconds: 1),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              const Text(
                'Location Details',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: kRailwayBlue,
                ),
              ),
              const SizedBox(height: 16),

              if (_shouldShowZone())
                Column(
                  children: [
                    DropdownButtonFormField<String>(
                      value: (_zone != null && zones.contains(_zone)) ? _zone : null,
                      decoration: InputDecoration(
                        labelText: 'Zone *',
                        border: const OutlineInputBorder(),
                        helperText: _selectedRole?.contains('Master') == true
                            ? 'Master has access to entire zone'
                            : null,
                      ),
                      items: zones
                          .map((z) => DropdownMenuItem(value: z, child: Text(z)))
                          .toList(),
                      validator: (v) => v == null ? 'Required' : null,
                      onChanged: (_isZoneReadOnly() || _isContractAreaLocked()) ? null : (v) {
                        setState(() {
                          _zone = v;
                          if (_selectedRole?.contains('Master') == true) {
                            _division = null;
                            _depot = null;
                            divisions = [];
                            depots = [];
                          } else if (v != null) {
                            _loadDivisions(v);
                          }
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                  ],
                ),

              if (_shouldShowDivision())
                Column(
                  children: [
                    DropdownButtonFormField<String>(
                      value: (_division != null && divisions.contains(_division)) ? _division : null,
                      decoration: InputDecoration(
                        labelText: 'Division *',
                        border: const OutlineInputBorder(),
                        helperText: _selectedRole!.contains('Admin')
                            ? 'Admin has access to entire division'
                            : null,
                      ),
                      items: divisions
                          .map((d) => DropdownMenuItem(value: d, child: Text(d)))
                          .toList(),
                      validator: (v) => v == null ? 'Required' : null,
                      onChanged: (_isDivisionReadOnly() || _isContractAreaLocked()) ? null : (v) {
                        setState(() {
                          _division = v;
                          _selectedStationId = null;
                          if (v != null && _zone != null) {
                            _loadDepots(_zone!, v);
                            if (_selectedUserType == 'contractor') {
                              _loadDivisionStations(v);
                            }
                          }
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                  ],
                ),

              if (_shouldShowDepot())
                Column(
                  children: [
                    DropdownButtonFormField<String>(
                      value: (_depot != null && depots.contains(_depot)) ? _depot : null,
                      decoration: const InputDecoration(
                        labelText: 'Depot',
                        border: OutlineInputBorder(),
                        helperText: 'Supervisor manages this depot',
                      ),
                      items: depots
                          .map((d) => DropdownMenuItem(value: d, child: Text(d)))
                          .toList(),
                      onChanged: (v) => setState(() => _depot = v),
                    ),
                    const SizedBox(height: 12),
                  ],
                ),

              if (_shouldShowWorkerType())
                Column(
                  children: [
                    DropdownButtonFormField<String>(
                      value: (_workerType != null && ['Janitor', 'Attendant'].contains(_workerType)) ? _workerType : null,
                      decoration: const InputDecoration(
                        labelText: 'Worker Type *',
                        border: OutlineInputBorder(),
                        helperText: 'Janitor (OBHS) or Attendant (Linen)',
                      ),
                      items: ['Janitor', 'Attendant']
                          .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                          .toList(),
                      validator: (v) => v == null ? 'Required' : null,
                      onChanged: (v) => setState(() => _workerType = v),
                    ),
                    const SizedBox(height: 12),
                  ],
                ),

              if (_shouldShowTrainSelection())
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!_isMultiTrainExport())
                      DropdownButtonFormField<String>(
                        value: (_trainId != null && allTrains.any((t) => t.uid == _trainId)) ? _trainId : null,
                        decoration: const InputDecoration(
                          labelText: 'Assigned Train *',
                          border: OutlineInputBorder(),
                          helperText: 'Contractor Supervisor mapped to one train',
                        ),
                        items: allTrains
                            .map((t) => DropdownMenuItem(
                                  value: t.uid,
                                  child: Text('${t.trainNo} - ${t.trainName}'),
                                ))
                            .toList(),
                        validator: (v) => v == null ? 'Required' : null,
                        onChanged: (v) => setState(() {
                          _trainId = v;
                          _selectedTrainIds = v != null ? [v] : [];
                        }),
                      )
                    else
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Assigned Trains (Multiple allowed) *',
                              style: TextStyle(fontWeight: FontWeight.w500)),
                          const SizedBox(height: 8),
                          Container(
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Column(
                              children: allTrains.map((t) {
                                final isSelected =
                                    _selectedTrainIds.contains(t.uid);
                                return CheckboxListTile(
                                  title: Text('${t.trainNo} - ${t.trainName}'),
                                  value: isSelected,
                                  onChanged: (val) {
                                    setState(() {
                                      if (val == true) {
                                        _selectedTrainIds.add(t.uid!);
                                      } else {
                                        _selectedTrainIds.remove(t.uid);
                                      }
                                      _trainId = _selectedTrainIds.isNotEmpty
                                          ? _selectedTrainIds[0]
                                          : null;
                                    });
                                  },
                                );
                              }).toList(),
                            ),
                          ),
                          if (_selectedTrainIds.isEmpty)
                            const Padding(
                              padding: EdgeInsets.only(top: 8.0, left: 12),
                              child: Text('At least one train required',
                                  style: TextStyle(
                                      color: Colors.red, fontSize: 12)),
                            ),
                        ],
                      ),
                    const SizedBox(height: 12),
                  ],
                ),

              const SizedBox(height: 24),

              const Text(
                'Document Uploads',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: kRailwayBlue,
                ),
              ),
              const SizedBox(height: 12),

              ..._buildDocumentUploadField('Aadhar Card'),
              ..._buildDocumentUploadField('PAN Card'),
              ..._buildDocumentUploadField('ID Proof'),
              ..._buildDocumentUploadField('Photo'),

              const SizedBox(height: 24),

              const Text(
                'Signature',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: kRailwayBlue,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Signature(
                  controller: _signatureController,
                  height: 150,
                  backgroundColor: Colors.grey[200]!,
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => _signatureController.clear(),
                  icon: const Icon(Icons.clear, size: 16),
                  label: const Text('Clear Signature'),
                ),
              ),
              const SizedBox(height: 24),

              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        side: BorderSide(color: kRailwayBlue, width: 2),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      icon: Icon(Icons.save_outlined, color: kRailwayBlue),
                      label: Text(
                        'Save as Draft',
                        style: TextStyle(color: kRailwayBlue, fontSize: 12),
                      ),
                      onPressed: _saveDraft,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kRailwayBlue,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      icon: const Icon(Icons.send, color: Colors.white),
                      label: const Text(
                        'Submit for Approval',
                        style: TextStyle(color: Colors.white, fontSize: 12),
                      ),
                      onPressed: _submitForm,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildDocumentUploadField(String docName) {
    final fileName = pickedDocs[docName];
    return [
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(
                fileName != null ? Icons.check_circle : Icons.upload_file,
                color: fileName != null ? Colors.green : Colors.grey,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                docName,
                style: TextStyle(
                  fontWeight: FontWeight.w500,
                  color: fileName != null ? Colors.black87 : Colors.black54,
                ),
              ),
            ],
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: fileName != null ? Colors.green.shade50 : Colors.blue.shade50,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
            icon: Icon(
              fileName != null ? Icons.check : Icons.upload,
              color: fileName != null ? Colors.green : Colors.blue,
              size: 18,
            ),
            label: Text(
              fileName != null ? 'Uploaded' : 'Upload',
              style: TextStyle(
                color: fileName != null ? Colors.green : Colors.blue,
                fontWeight: FontWeight.w500,
              ),
            ),
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

                  setState(() {
                    pickedDocs[docName] = fileName;
                  });

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('$docName selected: $fileName'),
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
      if (fileName != null)
        Padding(
          padding: const EdgeInsets.only(left: 28, top: 4, bottom: 8),
          child: Row(
            children: [
              const Icon(Icons.insert_drive_file, size: 16, color: Colors.grey),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  fileName,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 18, color: Colors.red),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () {
                  setState(() {
                    pickedDocs.remove(docName);
                  });
                },
              ),
            ],
          ),
        ),
      const SizedBox(height: 12),
    ];
  }



  List<String> _getRolesForUserType(String userType) {
    final currentUser = Provider.of<AuthProvider>(context, listen: false).currentUser;
    final creatorRole = currentUser?.role ?? '';

    if (userType == 'railway') {
      if (creatorRole == 'Railway Admin') {
        return ['Railway Supervisor'];
      }
      else if (creatorRole == 'Railway Master') {
        return [
          'Railway Admin',
          'Railway Supervisor',
        ];
      }
      else if (creatorRole == 'Railway Supervisor') {
        return [];
      }
      else {
        return ['Railway Master', 'Railway Admin', 'Railway Supervisor'];
      }
    } else {
      if (creatorRole == 'Contractor Admin') {
        return ['Contractor Supervisor', 'Contractor Worker', 'Janitor', 'Attendant'];
      }
      else if (creatorRole == 'Contractor Master') {
        return ['Contractor Admin', 'Contractor Supervisor', 'Contractor Worker', 'Janitor', 'Attendant'];
      }
      else if (creatorRole == 'Contractor Supervisor' || creatorRole == 'CTS') {
        return ['Contractor Worker', 'Janitor', 'Attendant'];
      }
      else if (creatorRole == 'Railway Admin') {
        return ['Contractor Supervisor', 'Contractor Worker', 'Janitor', 'Attendant'];
      }
      else if (creatorRole == 'Railway Master') {
        return ['Contractor Master', 'Contractor Admin', 'Contractor Supervisor', 'Contractor Worker', 'Janitor', 'Attendant'];
      }
      else if (creatorRole == 'Railway Supervisor') {
        return [];
      }
      else {
        return ['Contractor Master', 'Contractor Admin', 'Contractor Supervisor', 'Contractor Worker', 'Janitor', 'Attendant'];
      }
    }
  }

  Future<void> _saveDraft() async {
    final currentUser = Provider.of<AuthProvider>(context, listen: false).currentUser;

    if (currentUser?.uid == null) {
      _showError('User not logged in');
      return;
    }


    final draftData = {
      'fullName': _fullName.text.trim(),
      'designation': _designation.text.trim(),
      'email': _email.text.trim(),
      'mobile': _mobile.text.trim(),
      'aadhaarNumber': _aadhaar.text.trim(),
      'password': _password.text.trim(),
      'userType': _selectedUserType,
      'role': _selectedRole,
      'entityId': _selectedCompany,
      'contractId': _selectedContractId,
      'stations': _selectedContractStationIds,
      'zone': _zone,
      'division': _division,
      'depot': _depot,
      'documents': pickedDocs,
    };

    setState(() => _isLoading = true);

    final success = await DraftStorageService.saveUserDraft(
      currentUserId: currentUser!.uid!,
      draftData: draftData,
      draftId: widget.draftId,
    );

    setState(() => _isLoading = false);

    if (success) {
      _showSuccess('Draft saved successfully');
      await Future.delayed(const Duration(seconds: 1));
      Navigator.pop(context, true);
    } else {
      _showError('Failed to save draft');
    }
  }

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedUserType == 'contractor' && _isContractorAdminOrSupervisor() && _selectedContractId == null) {
      _showError('Please select a contract for Contractor Admin/Supervisor.');
      return;
    }

    if (_selectedRole != null && _selectedRole!.toLowerCase().contains('inspector') && _selectedStationId == null) {
      _showError('Please select a station for the Railway Inspector.');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final currentUser = Provider.of<AuthProvider>(context, listen: false).currentUser;
      
      String? base64Signature;
      if (_signatureController.isNotEmpty) {
        final signatureBytes = await _signatureController.toPngBytes();
        if (signatureBytes != null) {
          base64Signature = base64Encode(signatureBytes);
        }
      }

      final result = await ApiService.createUser(
        userType: _selectedUserType,
        role: _selectedRole!,
        fullName: _fullName.text.trim(),
        designation: _designation.text.trim(),
        email: _email.text.trim(),
        password: _password.text.trim(),
        mobile: _mobile.text.trim(),
        aadhaarNumber: _aadhaar.text.trim(),
        zone: _zone?.trim().isEmpty ?? true ? null : _zone?.trim(),
        division: _division?.trim().isEmpty ?? true ? null : _division?.trim(),
        depot: _depot?.trim().isEmpty ?? true ? null : _depot?.trim(),
        entityId: (_selectedCompany?.trim().isEmpty ?? true) ? null : _selectedCompany?.trim(),
        contractId: _selectedUserType == 'contractor' ? _selectedContractId : null,
        stations: _selectedUserType == 'contractor' ? _selectedContractStationIds : null,
        createdById: currentUser?.uid,
        worker_type: _workerType,
        trainId: _trainId,
        trainIds: _selectedTrainIds,
        stationId: _selectedStationId,
        areaId: _selectedAreaId,
        platformId: _selectedPlatformId,
        signatureBase64: base64Signature,
      );

      setState(() => _isLoading = false);

      if (widget.draftId != null) {
        await DraftStorageService.deleteUserDraft(
          currentUserId: currentUser!.uid!,
          draftId: widget.draftId!,
        );
      }

      final message = result['message'] ?? 'User created successfully';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 3),
        ),

      );
      Navigator.pop(context,true);
    } catch (e) {
      setState(() => _isLoading = false);
      _showError('Failed to create user: ${e.toString()}');
    }
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.green),
    );
  }


  @override
  void dispose() {
    _fullName.dispose();
    _designation.dispose();
    _email.dispose();
    _mobile.dispose();
    _aadhaar.dispose();
    _password.dispose();
    _signatureController.dispose();
    _stationNameController.dispose();
    super.dispose();
  }
}

