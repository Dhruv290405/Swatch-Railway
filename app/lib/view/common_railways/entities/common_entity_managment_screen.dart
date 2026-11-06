import 'package:crm_train/model/user_entity_model.dart';
import 'package:flutter/material.dart';
import 'package:crm_train/utills/app_colors.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../providers/auth_provider.dart';
import '../../../services/api_services.dart';
import '../../../services/draft_storage_service.dart';
import '../contracts/common_contracts_screen.dart';
import 'entity_register_form.dart';

class CommonEntityManagmentScreen extends StatefulWidget {
  const CommonEntityManagmentScreen({super.key,});

  @override
  State<CommonEntityManagmentScreen> createState() =>
      _CommonEntityManagmentScreenState();
}

class _CommonEntityManagmentScreenState
    extends State<CommonEntityManagmentScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isFilterExpanded = false;
  bool _isLoading = false;

  List<EntityModel> pendingEntity = [];
  List<EntityModel> approvedEntity = [];
  List<EntityModel> rejectedEntity = [];
  List<EntityModel> suspendedEntity = [];
  List<Map<String, dynamic>> entityDrafts = [];

  String? _selectedFilterDivision;
  String? _selectedFilterDepot;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    loadAllEntity();
    _loadDrafts();
  }

  Future<void> loadAllEntity() async {
    setState(() => _isLoading = true);
    try {
      final pending = await ApiService.getPendingEntity();
      final approved = await ApiService.getApprovedEntity();
      final rejected = await ApiService.getRejectedEntity();
      final suspended = await ApiService.getSuspendedEntity();

      setState(() {
        pendingEntity = pending;
        approvedEntity = approved;
        rejectedEntity = rejected;
        suspendedEntity = suspended;
        _isLoading = false;
        // Entities are created by admins and are approved on creation; the Pending tab only
        // appears for older entities that are still waiting.
        final wanted = pendingEntity.isNotEmpty ? 5 : 4;
        if (_tabController.length != wanted) {
          _tabController.dispose();
          _tabController = TabController(length: wanted, vsync: this);
        }
      });
    } catch (e) {
      setState(() => _isLoading = false);
      _showError('Failed to load users: $e');
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

  Future<void> _approveEntity(String id) async {
    if (id.isEmpty) {
      _showError('Invalid user ID');
      return;
    }

    try {
      setState(() => _isLoading = true);
      final result = await ApiService.approveEntity(id);
      final message = result['message'] ?? 'Entity approved successfully';
      _showSuccess(message);
      await loadAllEntity();
    } catch (e) {
      _showError('Failed to approve user: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }


  Future<void> _rejectEntity(String id) async {
    if (id.isEmpty) {
      _showError('Invalid user ID');
      return;
    }

    try {
      setState(() => _isLoading = true);
      final result = await ApiService.rejectEntity(id);
      final message = result['message'] ?? 'Entity rejected successfully';
      _showSuccess(message);
      await loadAllEntity();
    } catch (e) {
      _showError('Failed to reject user: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadDrafts() async {
    final currentUser = Provider.of<AuthProvider>(context, listen: false).currentUser;
    if (currentUser?.uid == null) {
      print('User UID is null in entity management');
      return;
    }

    try {
      print('Loading entity drafts for user: ${currentUser!.uid}');
      final drafts = await DraftStorageService.getEntityDrafts(currentUser.uid!);
      print('Loaded ${drafts.length} entity drafts');
      setState(() {
        entityDrafts = drafts;
      });
      print('Entity drafts state updated: ${entityDrafts.length}');
    } catch (e) {
      print('Error loading drafts: $e');
    }
  }

  Future<void> _deleteDraft(String draftId) async {
    final currentUser = Provider.of<AuthProvider>(context, listen: false).currentUser;
    if (currentUser?.uid == null) return;

    final success = await DraftStorageService.deleteEntityDraft(
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
        builder: (_) => EntityRegisterForm(
          draftData: draft,
          draftId: draft['draftId'],
        ),
      ),
    );

    if (result == true) {
      await _loadDrafts();
      await loadAllEntity();
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = Provider.of<AuthProvider>(context).currentUser;

    final bool isMaster = user != null &&
        (user.role == 'SUPER_ADMIN' || user.role == 'Super Admin' || user.role == 'Company Master');


    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      appBar: AppBar(
        backgroundColor: kRailwayBlue,
        elevation: 0,
        title: Text(
          isMaster ? "Entity Management" : "Active Entities",
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.w600, fontSize: 20),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
            GestureDetector(
              onTap: () {
                Navigator.push(context,
                    MaterialPageRoute(builder: (context) => CommonContractsScreen(userRole: user!.role)));
              },
              child: Container(
                padding: EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8)),
                child: Row(
                  children: [
                    Icon(Icons.file_copy_rounded, color: Colors.black, size: 20),
                    const SizedBox(width: 5),
                    Text(
                      isMaster ? 'Manage Contracts' : 'Contracts',
                      style: TextStyle(
                          color: Colors.black,
                          fontSize: 12,
                          fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(width: 10),
        ],
      ),


      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
        padding: const EdgeInsets.all(16),
        child: isMaster
            ? _buildFullEntityBody()
            : _buildActiveEntityList(),
      ),


      floatingActionButton: isMaster
          ? FloatingActionButton.extended(
        onPressed: () async{
          final result = await Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => const EntityRegisterForm()),
          );
          if (result == true) {
            loadAllEntity();
            _loadDrafts();
          }
        },
        backgroundColor: kRailwayBlue,
        icon: const Icon(Icons.person_add_alt_1, color: Colors.white),
        label: const Text(
          "Add Entity",
          style:
          TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
        ),
      )
          : null,
    );
  }


  Widget _buildFullEntityBody() {
    final user = Provider.of<AuthProvider>(context).currentUser;
    return Column(
      children: [

        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            if (pendingEntity.isNotEmpty)
              _buildStatusCard("Pending", pendingEntity.length, Colors.orange),
            _buildStatusCard("Approved", approvedEntity.length, Colors.green),
            _buildStatusCard("Rejected", rejectedEntity.length, Colors.red),
            _buildStatusCard("Suspended", suspendedEntity.length, Colors.grey),
          ],
        ),
        const SizedBox(height: 16),


        Container(
          decoration: BoxDecoration(
              color: Colors.white, borderRadius: BorderRadius.circular(10)),
          child: TabBar(
            controller: _tabController,
            labelColor: Colors.blue,
            unselectedLabelColor: Colors.black54,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelPadding: const EdgeInsets.symmetric(horizontal: 12),
            labelStyle: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w600),
            tabs: [
              if (pendingEntity.isNotEmpty) Tab(text: "Pending (${pendingEntity.length})"),
              Tab(text: "Approved (${approvedEntity.length})"),
              Tab(text: "Rejected (${rejectedEntity.length})"),
              Tab(text: "Suspended (${suspendedEntity.length})"),
              Tab(text: "Drafts (${entityDrafts.length})"),
            ],
          ),
        ),
        const SizedBox(height: 12),


        Expanded(
          child: TabBarView(
            physics: NeverScrollableScrollPhysics(),
            controller: _tabController,
            children: [
              if (pendingEntity.isNotEmpty) _buildPendingTab(),
              _buildApprovedTab(approvedEntity),
              _buildApprovedTab(rejectedEntity, isRejected: true),
              _buildApprovedTab(suspendedEntity, isSuspended: true),
              _buildDraftsTab(),
            ],
          ),
        ),
      ],
    );
  }


  Widget _buildActiveEntityList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Active Entities",
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: ListView.builder(
            itemCount: approvedEntity.length,
            itemBuilder: (context, index) {
              final entity = approvedEntity[index];
              return Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black12,
                      blurRadius: 6,
                      offset: const Offset(0, 3),
                    )
                  ],
                ),
                margin: const EdgeInsets.symmetric(vertical: 6),
                child: ListTile(
                  contentPadding: const EdgeInsets.all(12),
                  leading: CircleAvatar(
                    backgroundColor: Colors.orange.shade100,
                    child: const Icon(Icons.person, color: Colors.orange),
                  ),
                  title: Text(entity.contractorName ?? '',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(entity.registrationType ?? ''),
                  trailing: IconButton(
                    onPressed: () => _showDetailsBottomSheet(entity),
                    icon: const Icon(Icons.remove_red_eye_outlined,
                        color: Colors.grey),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }


  Widget _buildStatusCard(String label, int count, Color color) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4)],
        ),
        child: Column(
          children: [
            Text("$count",
                style: TextStyle(
                    color: color, fontSize: 20, fontWeight: FontWeight.bold)),
            Text(label, style: const TextStyle(color: Colors.black54)),
          ],
        ),
      ),
    );
  }

  Widget _buildPendingTab() {
    if (pendingEntity.isEmpty) {
      return const Center(child: Text("No pending users"));
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 50),
      child: ListView.builder(
        itemCount: pendingEntity.length,
        itemBuilder: (context, index) {
          final entity = pendingEntity[index];
          return Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 6,
                  offset: const Offset(0, 3),
                )
              ],
            ),
            margin: const EdgeInsets.symmetric(vertical: 6),
            child: ListTile(
              leading: Container(
                padding: EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.blue.shade100,
                  borderRadius: BorderRadiusGeometry.circular(10)
                ),
                child: const Icon(Icons.location_city_outlined, color: kRailwayBlue),
              ),
              title: Text(entity.contractorName ?? '',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(entity.registrationType ?? ''),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                      onPressed: () => _showDetailsBottomSheet(entity),
                      icon: const Icon(Icons.remove_red_eye_outlined,
                          color: Colors.grey)),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.red),
                    onPressed: () => _rejectEntity(entity.uid),
                  ),
                  IconButton(
                    icon: const Icon(Icons.check, color: Colors.green),
                    onPressed: () {
                      _approveEntity(entity.uid);
                    },
                  ),

                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildApprovedTab(List<EntityModel> entity, {bool isRejected = false, bool isSuspended = false}) {
    if (entity.isEmpty) {
      return const Center(child: Text("No users found"));
    }
    return ListView.builder(
      itemCount: entity.length,
      itemBuilder: (context, index) {
        final e = entity[index];
        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black12,
                blurRadius: 6,
                offset: const Offset(0, 3),
              )
            ],
          ),
          margin: const EdgeInsets.symmetric(vertical: 6),
          child: ListTile(
            leading: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color: isSuspended
                      ? Colors.grey.shade100
                      : isRejected
                          ? Colors.red.shade100
                          : Colors.blue.shade100,
                  borderRadius: BorderRadius.circular(10)
              ),
              child: Icon(
                Icons.location_city_outlined,
                color: isSuspended
                    ? Colors.grey
                    : isRejected
                        ? Colors.red
                        : kRailwayBlue,
              ),
            ),
            title: Text(e.contractorName ?? '',
                style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(e.registrationType ?? ''),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(icon: const Icon(Icons.remove_red_eye), onPressed: () => _showDetailsBottomSheet(e)),
                  isRejected ? const SizedBox() :
                  IconButton(
                    icon: const Icon(Icons.edit, color: kRailwayBlue),
                    onPressed: () async {
                      final result = await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => EntityRegisterForm(entity: e),
                        ),
                      );
                      if (result == true) {
                        loadAllEntity();
                      }
                    },
                  )
              ],
            ),
          ),
        );
      },
    );
  }

  void _showDetailsBottomSheet(EntityModel entity) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.75,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          builder: (_, controller) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: SingleChildScrollView(
                controller: controller,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        height: 5,
                        width: 50,
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(
                            color: Colors.grey[300],
                            borderRadius: BorderRadius.circular(5)),
                      ),
                    ),
                    Text(entity.contractorName ?? '',
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    Text(entity.registrationType ?? "",
                        style: const TextStyle(color: Colors.black54)),
                    Text(entity.registeredAddress ?? "",
                        style: const TextStyle(color: Colors.black54)),
                    const Divider(),
                    _infoTile("Email", entity.email ?? ''),
                    _infoTile("Contact", entity.contactNumber ?? ''),
                    _infoTile("Alternate Contact", entity.alternateContact ?? ''),
                    _infoTile("PAN Number", entity.panNumber ?? ''),
                    _infoTile("GST Number", entity.gstinNumber ?? ''),
                    _infoTile("Gem ID", entity.gemId ?? ''),

                    const SizedBox(height: 20),
                    const Text(
                      'Audit Logs',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: kRailwayBlue),
                    ),
                    const SizedBox(height: 12),

                    _auditRow(
                      title: 'Created',
                      byName: entity.createdByName,
                      at: entity.createdAt,
                    ),

                    _auditRow(
                      title: 'Approved',
                      byName: entity.approvedByName,
                      at: entity.approvedAt,
                    ),

                    _auditRow(
                      title: 'Suspended',
                      byName: entity.suspendedByName,
                      at: entity.suspendedAt,
                    ),

                    _auditRow(
                      title: 'Rejected',
                      byName: entity.rejectedByName,
                      at: entity.rejectedAt,
                    ),

                    _auditRow(
                      title: 'Updated',
                      byName: entity.updatedByName,
                      at: entity.updatedAt,
                    ),




                    if (
                    entity.createdAt == null &&
                        entity.updatedAt == null &&
                        entity.approvedAt == null &&
                        entity.rejectedAt == null &&
                        entity.suspendedAt == null
                    )
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          'No audit history available',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                        ),
                      ),






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


  Widget _infoTile(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text("$label: ",
              style: const TextStyle(
                  color: Colors.black54, fontWeight: FontWeight.w500)),
          Expanded(
              child: Text(value,
                  style: const TextStyle(fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }

  Widget _buildDraftsTab() {
    if (entityDrafts.isEmpty) {
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
              'Save a draft when creating a new entity to see it here',
              style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 80),
      itemCount: entityDrafts.length,
      itemBuilder: (context, idx) {
        final draft = entityDrafts[idx];

        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 3))],
          ),
          margin: const EdgeInsets.symmetric(vertical: 8),
          child: ListTile(
            title: Text(draft['companyName']?.isNotEmpty == true ? draft['companyName'] : 'Unnamed Draft'),
            subtitle: Text('${draft['zone'] ?? 'No zone'}${draft['division'] != null ? ' / ${draft['division']}' : ''}'),
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
        );
      },
    );
  }
}
