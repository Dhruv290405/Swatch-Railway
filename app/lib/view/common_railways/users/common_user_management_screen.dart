import 'package:crm_train/model/user_registeration_model.dart';
import 'package:crm_train/providers/auth_provider.dart';
import 'package:crm_train/services/draft_storage_service.dart';
import 'package:crm_train/view/common_railways/users/user_edit_screen.dart';
import 'package:crm_train/view/common_railways/users/user_registration_screen.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../data/zone_database.dart';
import '../../../model/user_model.dart';
import '../../../services/api_services.dart';
import '../../../utills/app_colors.dart';


class CommonUserManagementScreen extends StatefulWidget {
  const CommonUserManagementScreen({super.key});

  @override
  State<CommonUserManagementScreen> createState() => _CommonUserManagementScreenState();
}

class _CommonUserManagementScreenState extends State<CommonUserManagementScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isFilterExpanded = false;
  bool _isLoading = false;

  List<UserRegistrationModel> pendingUsers = [];
  List<UserRegistrationModel> approvedUsers = [];
  List<UserRegistrationModel> rejectedUsers = [];
  List<Map<String, dynamic>> userDrafts = [];


  String selectedRoleFilter = 'All Roles';
  String selectedOrgFilter = 'All';
  String? selectedZoneFilter;
  String? selectedDivisionFilter;
  String? selectedDepotFilter;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final currentUser = Provider.of<AuthProvider>(context, listen: false).currentUser;
      if (currentUser?.role == 'Railway Master' ||
          currentUser?.role == 'Railway Admin' ||
          currentUser?.role == 'Railway Supervisor') {
        setState(() {
          selectedZoneFilter = currentUser?.zone;
          if (currentUser?.role == 'Railway Admin' || currentUser?.role == 'Railway Supervisor') {
            selectedDivisionFilter = currentUser?.division;
          }
        });
      }
    });

    loadAllUsers();
    _loadDrafts();
  }


  Future<void> loadAllUsers({bool silent = false}) async {
    if (!silent) setState(() => _isLoading = true);
    try {
      final pending = await ApiService.getAllUsersByStatus('PENDING');
      final approved = await ApiService.getAllUsersByStatus('APPROVED');
      final rejected = await ApiService.getAllUsersByStatus('REJECTED');

      setState(() {
        pendingUsers = pending;
        approvedUsers = approved;
        rejectedUsers = rejected;
        if (!silent) _isLoading = false;
      });
    } catch (e) {
      if (!silent) setState(() => _isLoading = false);
      _showError('Failed to load users: $e');
      print(e);
    }
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

  List<String> _getAvailableRoleFilters(UserModel? currentUser) {
    if (currentUser?.role == 'Railway Admin' || currentUser?.role == 'Contractor Admin') {
      return [
        'All Roles',
        'Railway Admin',
        'Railway Supervisor',
        'Contractor Admin',
        'Contractor Supervisor',
      ];
    }
    if (currentUser?.role == 'Railway Supervisor' || currentUser?.role == 'Contractor Supervisor') {
      return [
        'All Roles',
        'Railway Supervisor',
        'Contractor Supervisor',
      ];
    }
    return [
      'All Roles',
      'Super Admin',
      'Company Master',
      'Railway Master',
      'Railway Admin',
      'Railway Supervisor',
      'Contractor Master',
      'Contractor Admin',
      'Contractor Supervisor',
    ];
  }

  List<UserRegistrationModel> _applyFilters(List<UserRegistrationModel> users) {
    final currentUser = Provider.of<AuthProvider>(context, listen: false).currentUser;

    return users.where((user) {
      if (currentUser?.role == 'Railway Supervisor') {
        if (!user.role!.contains('Supervisor')) {
          return false;
        }
        if (currentUser?.division != null && user.division != currentUser?.division) {
          return false;
        }
      }
      else if (currentUser?.role == 'Railway Admin') {
        if (user.role == 'SUPER_ADMIN' || user.role == 'Super Admin' || user.role == 'Railway Master' || user.role == 'Contractor Master' || user.role == 'Company Master') {
          return false;
        }
        if (currentUser?.division != null && user.division != currentUser?.division) {
          return false;
        }
      }
      else if (currentUser?.role == 'Railway Master') {
        if (currentUser?.zone != null && user.zone != currentUser?.zone) {
          return false;
        }
      }
      else if (currentUser?.role == 'Contractor Supervisor') {
        if (!user.role!.contains('Supervisor')) {
          return false;
        }
        if (currentUser?.division != null && user.division != currentUser?.division) {
          return false;
        }
      }
      // Contractor Admin - can see Admins and Supervisors in their division
      else if (currentUser?.role == 'Contractor Admin') {
        if (user.role == 'SUPER_ADMIN' || user.role == 'Super Admin' || user.role == 'Railway Master' || user.role == 'Contractor Master' || user.role == 'Company Master') {
          return false;
        }
        if (currentUser?.division != null && user.division != currentUser?.division) {
          return false;
        }
      }
      else if (currentUser?.role == 'Contractor Master') {
        if (currentUser?.zone != null && user.zone != currentUser?.zone) {
          return false;
        }
      }

      final normalizedUserRole = user.role?.replaceAll('_', ' ').toLowerCase() ?? '';
      final filterRoleLower = selectedRoleFilter.toLowerCase();
      
      if (selectedRoleFilter != 'All Roles' && normalizedUserRole != filterRoleLower) {
        return false;
      }

      if (selectedOrgFilter != 'All') {
        if (selectedOrgFilter == 'Railway' && user.userType?.toLowerCase() != 'railway') {
          return false;
        }
        if (selectedOrgFilter == 'Contractor' && user.userType?.toLowerCase() != 'contractor') {
          return false;
        }
      }

      if (selectedZoneFilter != null && user.zone != selectedZoneFilter) {
        return false;
      }

      if (selectedDivisionFilter != null && user.division != selectedDivisionFilter) {
        return false;
      }

      if (selectedDepotFilter != null && user.depot != selectedDepotFilter) {
        return false;
      }

      return true;
    }).toList();
  }

  Future<void> _approveUser(String uid) async {
    if (uid.isEmpty) {
      _showError('Invalid user ID');
      return;
    }

    try {
      final currentUser = Provider.of<AuthProvider>(context, listen: false).currentUser;
      final result = await ApiService.approveUser(uid, approvedById: currentUser?.uid);
      final message = result['message'] ?? 'User approved successfully';
      _showSuccess(message);
      await loadAllUsers(silent: true);
    } catch (e) {
      _showError('Failed to approve user: $e');
    }
  }

  Future<void> _rejectUser(String uid) async {
    if (uid.isEmpty) {
      _showError('Invalid user ID');
      return;
    }

    try {
      final result = await ApiService.rejectUser(uid);
      final message = result['message'] ?? 'User rejected successfully';
      _showSuccess(message);
      await loadAllUsers(silent: true);
    } catch (e) {
      _showError('Failed to reject user: $e');
    }
  }

  Future<void> _loadDrafts() async {
    final currentUser = Provider.of<AuthProvider>(context, listen: false).currentUser;
    if (currentUser?.uid == null) return;

    try {
      final drafts = await DraftStorageService.getUserDrafts(currentUser!.uid!);
      setState(() {
        userDrafts = drafts;
      });
    } catch (e) {
      print('Error loading drafts: $e');
    }
  }

  Future<void> _deleteDraft(String draftId) async {
    final currentUser = Provider.of<AuthProvider>(context, listen: false).currentUser;
    if (currentUser?.uid == null) return;

    final success = await DraftStorageService.deleteUserDraft(
      currentUserId: currentUser!.uid!,
      draftId: draftId,
    );

    if (success) {
      _showSuccess('Draft deleted successfully');
      await _loadDrafts();
    } else {
      _showError('Failed to delete draft');
    }
  }

  Future<void> _openDraft(Map<String, dynamic> draft) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => UserRegistrationScreen(
          draftData: draft,
          draftId: draft['draftId'],
        ),
      ),
    );

    if (result == true) {
      await _loadDrafts();
      await loadAllUsers();
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = Provider.of<AuthProvider>(context).currentUser;
    final filteredPending = _applyFilters(pendingUsers);
    final filteredApproved = _applyFilters(approvedUsers);
    final filteredRejected = _applyFilters(rejectedUsers);

    final bool canAddUsers = user != null &&
        (user.role == 'SUPER_ADMIN' ||
         user.role == 'Super Admin' ||
         user.role == 'Company Master' ||
         user.role == 'Railway Master' ||
         user.role == 'Railway Admin' ||
         user.role == 'Contractor Master' ||
         user.role == 'Contractor Admin');


    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        iconTheme: const IconThemeData(color: Colors.white),
        backgroundColor: kRailwayBlue,
        title: const Text(
          'User Management',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: loadAllUsers,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [

            Row(
              children: [
                _statusCard('Pending', pendingUsers.length, Colors.orange),
                _statusCard('Approved', approvedUsers.length, Colors.green),
                _statusCard('Rejected', rejectedUsers.length, Colors.red),
              ],
            ),
            const SizedBox(height: 12),


            _buildFilterSection(),
            const SizedBox(height: 12),


            TabBar(
              controller: _tabController,
              labelColor: Colors.blue,
              unselectedLabelColor: Colors.black54,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              labelPadding: const EdgeInsets.symmetric(horizontal: 12),
              tabs: [
                Tab(text: 'Pending (${filteredPending.length})'),
                Tab(text: 'Approved (${filteredApproved.length})'),
                Tab(text: 'Rejected (${filteredRejected.length})'),
                Tab(text: 'Drafts (${userDrafts.length})'),
              ],
            ),
            const SizedBox(height: 8),


            Expanded(
              child: TabBarView(
                physics: const NeverScrollableScrollPhysics(),
                controller: _tabController,
                children: [
                  _buildPendingList(filteredPending),
                  _buildUserList(filteredApproved, showActions: true),
                  _buildUserList(filteredRejected, showActions: false),
                  _buildDraftsTab(),
                ],
              ),
            ),
          ],
        ),
      ),

      floatingActionButton: canAddUsers ? FloatingActionButton.extended(
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const UserRegistrationScreen()),
          );
          if (result == true) {
            loadAllUsers();
            _loadDrafts();
          }
        },
        backgroundColor: kRailwayBlue,
        icon: const Icon(Icons.person_add_alt_1, color: Colors.white),
        label: const Text(
          "Add User",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
        ),
      ) : null,
    );
  }

  Widget _buildFilterSection() {
    final user = Provider.of<AuthProvider>(context).currentUser;
    final zones = DepotDatabase.zoneData.keys.toSet().toList();
    final divisions = selectedZoneFilter != null
        ? (DepotDatabase.zoneData[selectedZoneFilter]?.keys.toSet().toList() ?? [])
        : [];
    final depots = (selectedZoneFilter != null && selectedDivisionFilter != null)
        ? (DepotDatabase.zoneData[selectedZoneFilter]?[selectedDivisionFilter]?.toSet().toList() ?? [])
        : [];

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.shade200,
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _isFilterExpanded = !_isFilterExpanded),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              ),
              child: Row(
                children: [
                  Icon(Icons.filter_list, color: kRailwayBlue, size: 22),
                  const SizedBox(width: 10),
                  const Text(
                    'Filters',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                      color: kRailwayBlue,
                    ),
                  ),
                  const Spacer(),
                  AnimatedRotation(
                    turns: _isFilterExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 300),
                    child: Icon(Icons.keyboard_arrow_down, color: kRailwayBlue),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            child: _isFilterExpanded
                ? Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [

                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: (_getAvailableRoleFilters(user).contains(selectedRoleFilter)) ? selectedRoleFilter : 'All Roles',
                          decoration: InputDecoration(
                            labelText: 'Role',
                            labelStyle: const TextStyle(fontSize: 14),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            filled: true,
                            fillColor: Colors.grey.shade50,
                          ),
                          isExpanded: true,
                          items: _getAvailableRoleFilters(user).map(
                                (r) => DropdownMenuItem(
                              value: r,
                              child: Text(
                                r,
                                style: const TextStyle(fontSize: 14),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ),
                          ).toList(),
                          onChanged: (v) => setState(() => selectedRoleFilter = v ?? 'All Roles'),
                        )
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: selectedOrgFilter,
                          decoration: InputDecoration(
                            labelText: 'Organization',
                            labelStyle: const TextStyle(fontSize: 14),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            filled: true,
                            fillColor: Colors.grey.shade50,
                          ),
                          items: const [
                            DropdownMenuItem(value: 'All', child: Text('All', style: TextStyle(fontSize: 14))),
                            DropdownMenuItem(value: 'Railway', child: Text('Railway', style: TextStyle(fontSize: 14))),
                            DropdownMenuItem(value: 'Contractor', child: Text('Contractor', style: TextStyle(fontSize: 14))),
                          ],
                          onChanged: (v) => setState(() => selectedOrgFilter = v ?? 'All'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),


                  const Text(
                    'Location',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 10),


                  DropdownButtonFormField<String>(
                    value: (selectedZoneFilter != null && zones.contains(selectedZoneFilter)) ? selectedZoneFilter : null,
                    decoration: InputDecoration(
                      labelText: 'Zone',
                      labelStyle: const TextStyle(fontSize: 14),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                    ),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('All Zones', style: TextStyle(fontSize: 14))),
                      ...zones.map((z) => DropdownMenuItem(value: z, child: Text(z, style: const TextStyle(fontSize: 14)))),
                    ],
                    onChanged: (user?.role == 'Railway Master' || user?.role == 'Railway Admin' || user?.role == 'Railway Supervisor' ||
                               user?.role == 'Contractor Master' || user?.role == 'Contractor Admin' || user?.role == 'Contractor Supervisor')
                        ? null
                        : (v) {
                      setState(() {
                        selectedZoneFilter = v;
                        selectedDivisionFilter = null;
                        selectedDepotFilter = null;
                      });
                    },
                  ),
                  const SizedBox(height: 12),


                  DropdownButtonFormField<String>(
                    value: (selectedDivisionFilter != null && divisions.contains(selectedDivisionFilter)) ? selectedDivisionFilter : null,
                    decoration: InputDecoration(
                      labelText: 'Division',
                      labelStyle: const TextStyle(fontSize: 14),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                    ),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('All Divisions', style: TextStyle(fontSize: 14))),
                      ...divisions.map((d) => DropdownMenuItem(value: d, child: Text(d, style: const TextStyle(fontSize: 14)))),
                    ],
                    onChanged: (user?.role == 'Railway Admin' || user?.role == 'Railway Supervisor' ||
                               user?.role == 'Contractor Admin' || user?.role == 'Contractor Supervisor')
                        ? null
                        : (v) {
                      setState(() {
                        selectedDivisionFilter = v;
                        selectedDepotFilter = null;
                      });
                    },
                  ),
                  const SizedBox(height: 12),


                  DropdownButtonFormField<String>(
                    value: (selectedDepotFilter != null && depots.contains(selectedDepotFilter)) ? selectedDepotFilter : null,
                    decoration: InputDecoration(
                      labelText: 'Depot',
                      labelStyle: const TextStyle(fontSize: 14),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                    ),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('All Depots', style: TextStyle(fontSize: 14))),
                      ...depots.map((d) => DropdownMenuItem(value: d, child: Text(d, style: const TextStyle(fontSize: 14)))),
                    ],
                    onChanged: (v) {
                      setState(() {
                        selectedDepotFilter = v;
                      });
                    },
                  ),

                  const SizedBox(height: 16),


                  Center(
                    child: TextButton.icon(
                      onPressed: () {
                        setState(() {
                          selectedRoleFilter = 'All Roles';
                          selectedOrgFilter = 'All';
                          if (user?.role != 'Railway Master' &&
                              user?.role != 'Railway Admin' &&
                              user?.role != 'Railway Supervisor' &&
                              user?.role != 'Contractor Master' &&
                              user?.role != 'Contractor Admin' &&
                              user?.role != 'Contractor Supervisor') {
                            selectedZoneFilter = null;
                            selectedDivisionFilter = null;
                          }
                          selectedDepotFilter = null;
                        });
                      },
                      icon: const Icon(Icons.clear_all, size: 18),
                      label: const Text('Clear All Filters'),
                      style: TextButton.styleFrom(
                        foregroundColor: kRailwayBlue,
                        textStyle: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ),
            )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _statusCard(String label, int count, Color color) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
        ),
        child: Column(
          children: [
            Text(
              count.toString(),
              style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 18),
            ),
            const SizedBox(height: 6),
            Text(label, style: const TextStyle(color: Colors.black54))
          ],
        ),
      ),
    );
  }

  Widget _buildPendingList(List<UserRegistrationModel> users) {
    final currentUser = Provider.of<AuthProvider>(context).currentUser;

    final canPerformActions = currentUser?.role == 'SUPER_ADMIN' ||
        currentUser?.role == 'Super Admin' ||
        currentUser?.role == 'Company Master' ||
        currentUser?.role == 'Railway Master' ||
        currentUser?.role == 'Railway Admin' ||
        currentUser?.role == 'Contractor Master' ||
        currentUser?.role == 'Contractor Admin';

    if (users.isEmpty) {
      return const Center(child: Text('No pending users'));
    }

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 80),
      itemCount: users.length,
      itemBuilder: (context, idx) {
        final u = users[idx];

        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 3))],
          ),
          margin: const EdgeInsets.symmetric(vertical: 8),
          child: Material(
            color: Colors.transparent,
            child: ListTile(
              title: Text(u.fullName ?? 'Unknown'),
              subtitle: Text('${u.role ?? ''} • ${u.zone ?? ''}${u.division != null ? ' / ${u.division}' : ''}'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.remove_red_eye),
                    onPressed: () => _showUserDetail(u),
                  ),
                  if (canPerformActions) ...[
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.red),
                      onPressed: () => _rejectUser(u.uid ?? ''),
                    ),
                    IconButton(
                      icon: const Icon(Icons.check, color: Colors.green),
                      onPressed: () => _approveUser(u.uid ?? ''),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }


  Widget _buildUserList(List<UserRegistrationModel> users, {bool showActions = true}) {
    final currentUser = Provider.of<AuthProvider>(context).currentUser;

    final canEdit = currentUser?.role == 'SUPER_ADMIN' ||
                    currentUser?.role == 'Super Admin' ||
                    currentUser?.role == 'Company Master' ||
                    currentUser?.role == 'Railway Master' ||
                    currentUser?.role == 'Railway Admin' ||
                    currentUser?.role == 'Contractor Master' ||
                    currentUser?.role == 'Contractor Admin';

    if (users.isEmpty) {
      return const Center(child: Text('No users found'));
    }

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 80),
      itemCount: users.length,
      itemBuilder: (context, idx) {
        final u = users[idx];
        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 3))],
          ),
          margin: const EdgeInsets.symmetric(vertical: 6),
          child: Material(
            color: Colors.transparent,
            child: ListTile(
              title: Text(u.fullName ?? 'Unknown'),
              subtitle: Text('${u.role ?? ''} • ${u.zone ?? ''}${u.division != null ? ' / ${u.division}' : ''}'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(icon: const Icon(Icons.remove_red_eye), onPressed: () => _showUserDetail(u)),
                  if (canEdit && currentUser?.uid != u.uid)
                    IconButton(
                      icon: const Icon(Icons.edit),
                      onPressed: () async {
                        final result = await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => UserEditScreen(user: u),
                          ),
                        );
                        if (result == true) {
                          loadAllUsers();
                        }
                      },
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }


  void _showUserDetail(UserRegistrationModel user) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) {
            return Padding(
              padding: const EdgeInsets.all(20.0),
              child: SingleChildScrollView(
                controller: scrollController,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [

                Row(
                  children: [
                    Expanded(
                      child: Text(
                        user.fullName ?? 'Unknown',
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: user.status?.toUpperCase() == 'APPROVED'
                            ? Colors.green.shade50
                            : user.status?.toUpperCase() == 'REJECTED'
                                ? Colors.red.shade50
                                : Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        user.status?.toUpperCase() ?? 'PENDING',
                        style: TextStyle(
                          color: user.status?.toUpperCase() == 'APPROVED'
                              ? Colors.green.shade700
                              : user.status?.toUpperCase() == 'REJECTED'
                                  ? Colors.red.shade700
                                  : Colors.orange.shade700,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),


                const Text(
                  'User Details',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: kRailwayBlue),
                ),
                const SizedBox(height: 12),
                _detailRow(Icons.email_outlined, user.email ?? 'N/A'),
                _detailRow(Icons.phone, user.mobile ?? 'N/A'),
                _detailRow(Icons.work, user.role ?? 'N/A'),
                _detailRow(Icons.badge, user.designation ?? 'N/A'),
                if(user.zone != null)
                _detailRow(Icons.location_on,
                    '${user.zone ?? ''}${user.division != null ? ' / ${user.division}' : ''}${user.depot != null ? ' / ${user.depot}' : ''}'),
                if (user.entityDetails?.contractorName != null) _detailRow(Icons.business, user.entityDetails?.contractorName ?? ''),

                const SizedBox(height: 20),
                const Divider(),
                const SizedBox(height: 20),


                    const Text(
                      'Audit Logs',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: kRailwayBlue),
                    ),
                    const SizedBox(height: 12),

                    _auditRow(
                      title: 'Created',
                      byName: user.createdByName,
                      at: user.createdAt,
                    ),

                    _auditRow(
                      title: 'Approved',
                      byName: user.approvedByName,
                      at: user.approvedAt,
                    ),

                    _auditRow(
                      title: 'Rejected',
                      byName: user.rejectedByName,
                      at: user.rejectedAt,
                    ),

                    _auditRow(
                      title: 'Updated',
                      byName: user.updatedByName,
                      at: user.updatedAt,
                    ),


                    if (
                    user.createdAt == null &&
                        user.updatedAt == null &&
                        user.approvedAt == null &&
                        user.rejectedAt == null
                    )
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          'No audit history available',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                        ),
                      ),


                    const SizedBox(height: 20),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _auditRow({
    required String title,
    String? byName,
    DateTime? at,
  }) {
    if (byName == null && at == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '•',
            style: TextStyle(fontSize: 14, height: 1.4),
          ),
          const SizedBox(width: 8),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (byName != null || at != null)
                  Text(
                    [
                      if (byName != null) byName,
                      if (at != null)
                        DateFormat('dd MMM yyyy, hh:mm a').format(at),
                    ].join(' • '),
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }



  Widget _detailRow(IconData icon,String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.grey[600]),
          const SizedBox(width: 12),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }

  Widget _buildDraftsTab() {
    if (userDrafts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.drafts_outlined, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              'No saved drafts',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Save a draft when creating a new user to see it here',
              style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 80),
      itemCount: userDrafts.length,
      itemBuilder: (context, idx) {
        final draft = userDrafts[idx];

        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 3))],
          ),
          margin: const EdgeInsets.symmetric(vertical: 8),
          child: Material(
            color: Colors.transparent,
            child: ListTile(
              title: Text(draft['fullName']?.isNotEmpty == true ? draft['fullName'] : 'Unnamed Draft'),
              subtitle: Text('${draft['role'] ?? 'No role'} • ${draft['zone'] ?? 'No zone'}${draft['division'] != null ? ' / ${draft['division']}' : ''}'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit),
                    onPressed: () => _openDraft(draft),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Delete Draft'),
                          content: const Text('Are you sure you want to delete this draft?'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: const Text('Cancel'),
                            ),
                            TextButton(
                              onPressed: () {
                                Navigator.pop(ctx);
                                _deleteDraft(draft['draftId']);
                              },
                              child: const Text('Delete', style: TextStyle(color: Colors.red)),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }
}



