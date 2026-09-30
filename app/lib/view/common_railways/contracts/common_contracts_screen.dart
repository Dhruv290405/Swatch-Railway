import 'package:crm_train/services/api_services.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../model/contracts_model.dart';
import '../../../providers/auth_provider.dart';
import '../../../utills/app_colors.dart';
import '../widgets/rolevise_dropdowns.dart';
import 'contracts_form_screen.dart';

class CommonContractsScreen extends StatefulWidget {
  final String userRole;
  const CommonContractsScreen({super.key, required this.userRole});

  @override
  State<CommonContractsScreen> createState() => _CommonContractsScreenState();
}

class _CommonContractsScreenState extends State<CommonContractsScreen>
    with SingleTickerProviderStateMixin {
  List<ContractModel> contracts = [];
  String search = "";
  late TabController _tabController;
  bool _isFilterExpanded = false;
  bool _isLoading = false;

  String? selectedZone;
  String? selectedDivision;
  String? selectedDepot;
  String? _selectedFilterDivision;
  String? _selectedFilterDepot;
  String? _selectedContractType;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    // Defer reading AuthProvider until after build context is available
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final user = Provider.of<AuthProvider>(context, listen: false).currentUser;
      if (user?.contractType != null) {
        setState(() => _selectedContractType = user!.contractType);
      }
      _loadContracts();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadContracts({String? contractType}) async {
    final user = Provider.of<AuthProvider>(context, listen: false).currentUser;
    setState(() => _isLoading = true);

    final effectiveContractType = contractType ?? _selectedContractType;

    try {
      final activeContractsResponse = await ApiService.getActiveContracts(contractType: effectiveContractType);
      final inactiveContractsResponse = await ApiService.getInActiveContracts(contractType: effectiveContractType);

      List<ContractModel> allContracts = [
        ...activeContractsResponse,
        ...inactiveContractsResponse,
      ];

      if (widget.userRole == "Railway Supervisor") {
        contracts = allContracts
            .where((c) =>
        c.zone == user?.zone &&
            c.division == user?.division &&
            c.depot == user?.depot)
            .toList();
      } else if (widget.userRole == "Railway Admin") {
        contracts = allContracts
            .where((c) => c.zone == user?.zone && c.division == user?.division)
            .toList();
      } else {
        contracts = allContracts;
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Failed to load contracts: ${e.toString()}"),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = Provider.of<AuthProvider>(context, listen: false).currentUser;
    List<ContractModel> activeContracts =
    contracts.where((c) => c.isActive ?? false).toList();
    List<ContractModel> inactiveContracts =
    contracts.where((c) => !(c.isActive ?? false)).toList();

    bool canAddEdit = widget.userRole == "Company Master" || widget.userRole == "Contractor Admin" || widget.userRole == "Super Admin";

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Contract Management",
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 20,
              ),
            ),
            Text(
              _getUserScopeText(),
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.normal,
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF1565C0),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadContracts,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
        children: [
          if (!canAddEdit)
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                decoration: InputDecoration(
                  contentPadding: const EdgeInsets.only(top: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  prefixIcon: const Icon(Icons.search),
                  hintText: "Search by Contract No. / Name",
                ),
                onChanged: (v) => setState(() => search = v),
              ),
            ),
          if (widget.userRole == "Railway Master")
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: _buildFilterSection(user!),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                _buildTypeChip('All', null),
                const SizedBox(width: 8),
                _buildTypeChip('Station Cleaning', 'station_cleaning'),
                const SizedBox(width: 8),
                _buildTypeChip('OBHS', 'obhs'),
                const SizedBox(width: 8),
                _buildTypeChip('MCC', 'mcc'),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: Column(
              children: [
                TabBar(
                  controller: _tabController,
                  labelColor: const Color(0xFF1565C0),
                  unselectedLabelColor: Colors.black54,
                  labelStyle: const TextStyle(fontWeight: FontWeight.w600),
                  tabs: [
                    Tab(text: "Active (${activeContracts.length})"),
                    Tab(text: "Inactive (${inactiveContracts.length})"),
                  ],
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _contractListView(activeContracts, canAddEdit),
                      _contractListView(inactiveContracts, canAddEdit),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: canAddEdit
          ? FloatingActionButton.extended(
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const ContractFormScreen(),
            ),
          );
          if (result == true) {
            _loadContracts();
          }
        },
        backgroundColor: const Color(0xFF1565C0),
        icon: const Icon(Icons.description, color: Colors.white),
        label: const Text(
          "Add Contract",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
        ),
      )
          : null,
    );
  }

  Widget _buildTypeChip(String label, String? value) {
    final selected = _selectedContractType == value;
    return GestureDetector(
      onTap: () {
        setState(() => _selectedContractType = value);
        _loadContracts(contractType: value);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF1565C0) : Colors.grey[200],
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : Colors.black87,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _buildFilterSection(dynamic user) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.shade300,
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () {
              setState(() {
                _isFilterExpanded = !_isFilterExpanded;
              });
            },
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.filter_list,
                      color: Color(0xFF1565C0), size: 20),
                  const SizedBox(width: 8),
                  const Text(
                    'Filter',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                  const Spacer(),
                  AnimatedRotation(
                    turns: _isFilterExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 300),
                    child: const Icon(
                      Icons.keyboard_arrow_down,
                      color: Color(0xFF1565C0),
                    ),
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
              padding: const EdgeInsets.only(
                  left: 16, right: 16, bottom: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(height: 1),
                  const SizedBox(height: 16),
                  ZoneDivisionDepotDropdowns(
                    user: user,
                    onChanged: (division, depot) {
                      setState(() {
                        _selectedFilterDivision = division;
                        _selectedFilterDepot = depot;
                      });
                    },
                  ),
                  const SizedBox(height: 14),
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        selectedZone = null;
                        selectedDivision = null;
                        selectedDepot = null;
                      });
                    },
                    child: const Text(
                      'Clear All Filters',
                      style: TextStyle(
                        color: Color(0xFF1565C0),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            )
                : const SizedBox.shrink(),
          )
        ],
      ),
    );
  }

  String _getUserScopeText() {
    final user = Provider.of<AuthProvider>(context, listen: false).currentUser;
    final division = user?.division;
    final depot = user?.depot;

    if (widget.userRole == "Railway Supervisor") {
      String text = "";
      if (division != null && division.isNotEmpty) {
        text += "Division: $division";
      }
      if (depot != null && depot.isNotEmpty) {
        if (text.isNotEmpty) text += " | ";
        text += "Depot: $depot";
      }
      return text.isEmpty ? "" : text;
    } else if (widget.userRole == "Railway Admin") {
      return division != null && division.isNotEmpty
          ? "Division: $division"
          : "";
    } else {
      return "All Zones & Divisions";
    }
  }

  Widget _contractListView(List<ContractModel> list, bool canAddEdit) {
    List<ContractModel> filteredContracts = list
        .where((c) =>
    search.isEmpty ||
        (c.contractNumber?.toLowerCase().contains(search.toLowerCase()) ??
            false) ||
        (c.contractName?.toLowerCase().contains(search.toLowerCase()) ??
            false))
        .toList();

    if (widget.userRole == "Railway Master") {
      if (selectedZone != null) {
        filteredContracts = filteredContracts
            .where((c) => c.zone == selectedZone)
            .toList();
      }
      if (selectedDivision != null) {
        filteredContracts = filteredContracts
            .where((c) => c.division == selectedDivision)
            .toList();
      }
    }

    if (filteredContracts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox_outlined, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              "No contracts found",
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadContracts,
      child: ListView.builder(
        padding: const EdgeInsets.only(left: 10, right: 10, top: 10, bottom: 130),
        itemCount: filteredContracts.length,
        itemBuilder: (_, index) {
          ContractModel c = filteredContracts[index];
          return _buildContractCard(c, canAddEdit);
        },
      ),
    );
  }

  Widget _buildContractCard(ContractModel c, bool canAddEdit) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 6,
            offset: Offset(0, 3),
          )
        ],
      ),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "${c.contractNumber ?? 'N/A'} · ${c.contractName ?? 'Unnamed'}",
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        c.entityName ?? '',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _statusPill(c),
                    if (c.contractType != null) ...[
                      const SizedBox(height: 4),
                      _typeBadge(c.contractType!),
                    ],
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            _infoRow(Icons.train, "Zone", c.zone ?? 'N/A'),
            _infoRow(Icons.location_city, "Division", c.division ?? 'N/A'),
            if (c.depot != null) _infoRow(Icons.place, "Depot", c.depot!),
            _infoRow(
              Icons.work,
              "Categories",
              c.workCategories ?? 'N/A',
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _viewContract(c),
                  icon: const Icon(Icons.remove_red_eye, size: 18),
                  label: const Text("View"),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF1565C0),
                  ),
                ),
                if (canAddEdit) ...[
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: () => _editContract(c),
                    icon: const Icon(Icons.edit, size: 18),
                    label: const Text("Edit"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1565C0),
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _viewContract(ContractModel c) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _ContractDetailsSheet(contract: c),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(icon, size: 16, color: const Color(0xFF1565C0)),
          const SizedBox(width: 8),
          Text(
            "$label: ",
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 13, color: Colors.black87),
            ),
          ),
        ],
      ),
    );
  }

  Widget _typeBadge(String type) {
    final display = type == 'station_cleaning'
        ? 'Station Cleaning'
        : (type == 'obhs' ? 'OBHS' : 'MCC');
    final color = type == 'station_cleaning'
        ? Colors.teal
        : (type == 'obhs' ? Colors.indigo : Colors.deepPurple);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        display,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _statusPill(ContractModel c) {
    String label = c.status ?? 'Unknown';
    Color color;
    switch (label.toLowerCase()) {
      case "active":
        color = Colors.green;
        break;
      case "expired":
        color = Colors.red;
        break;
      case "suspended":
        color = Colors.orange;
        break;
      case "inactive":
        color = Colors.grey;
        break;
      default:
        color = Colors.grey;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  void _editContract(ContractModel c) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ContractFormScreen(contract: c),
      ),
    );

    if (result == true) {
      _loadContracts();
    }
  }
}

// Contract Details Bottom Sheet
class _ContractDetailsSheet extends StatelessWidget {
  final ContractModel contract;

  const _ContractDetailsSheet({required this.contract});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.9,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1565C0).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.description,
                    color: Color(0xFF1565C0),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    "Contract Details",
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.grey[100],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildStatusCard(contract),
                  const SizedBox(height: 20),
                  _buildDetailsSection(
                    "Basic Information",
                    Icons.info_outline,
                    [
                      _buildDetailRow("Contract Number", contract.contractNumber ?? "N/A"),
                      _buildDetailRow("Contract Name", contract.contractName ?? "N/A"),
                      _buildDetailRow("Entity", contract.entityName ?? "N/A"),
                      _buildDetailRow("Status", contract.status ?? "N/A"),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _buildDetailsSection(
                    "Location",
                    Icons.location_on,
                    [
                      _buildDetailRow("Zone", contract.zone ?? "N/A"),
                      _buildDetailRow("Division", contract.division ?? "N/A"),
                      if (contract.depot != null)
                        _buildDetailRow("Depot", contract.depot!),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _buildDetailsSection(
                    "Contract Period",
                    Icons.calendar_today,
                    [
                      _buildDetailRow("Start Date", _formatDate(contract.startDate)),
                      _buildDetailRow("End Date", _formatDate(contract.endDate)),
                      _buildDetailRow("Work Categories", contract.workCategories ?? "N/A"),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _buildDetailsSection(
                    "Authorized Representative",
                    Icons.person,
                    [
                      _buildDetailRow("Name", contract.repName ?? "N/A"),
                      _buildDetailRow("Designation", contract.repDesignation ?? "N/A"),
                      _buildDetailRow("Mobile", contract.repMobile ?? "N/A"),
                      _buildDetailRow("Email", contract.repEmail ?? "N/A"),
                      _buildDetailRow("ID Type", contract.repIdProofType ?? "N/A"),
                      _buildDetailRow("ID Number", contract.repIdProofNumber ?? "N/A"),
                    ],
                  ),
                  if (contract.remarks != null && contract.remarks!.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    _buildDetailsSection(
                      "Remarks",
                      Icons.note,
                      [
                        _buildDetailRow("", contract.remarks!),
                      ],
                    ),
                  ],
                  const SizedBox(height: 20),
                  _buildAuditSection(contract),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusCard(ContractModel contract) {
    String status = contract.status ?? "Unknown";
    Color statusColor = _getStatusColor(status);
    IconData statusIcon = _getStatusIcon(status);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [statusColor, statusColor.withOpacity(0.7)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: statusColor.withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.3),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(statusIcon, color: Colors.white, size: 32),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  contract.contractNumber ?? "N/A",
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  contract.contractName ?? "Unnamed",
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              status,
              style: TextStyle(
                color: statusColor,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case "active":
        return Colors.green;
      case "expired":
        return Colors.red;
      case "suspended":
        return Colors.orange;
      case "inactive":
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status.toLowerCase()) {
      case "active":
        return Icons.check_circle;
      case "expired":
        return Icons.error;
      case "suspended":
        return Icons.pause_circle;
      default:
        return Icons.info;
    }
  }

  Widget _buildDetailsSection(String title, IconData icon, List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(icon, color: const Color(0xFF1565C0), size: 20),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1565C0),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (label.isNotEmpty) ...[
            Expanded(
              flex: 2,
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[700],
                ),
              ),
            ),
            Expanded(
              flex: 3,
              child: Text(
                value,
                style: const TextStyle(
                  fontSize: 14,
                  color: Colors.black87,
                ),
              ),
            ),
          ] else
            Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                color: Colors.black87,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAuditSection(ContractModel contract) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue[50],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.history, color: kRailwayBlue, size: 18),
              const SizedBox(width: 8),
              const Text(
                'Audit Trail',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: kRailwayBlue,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (contract.createdAt != null) ...[
            _buildAuditRow(
              'Created',
              contract.createdByName,
              contract.createdAt,
            ),
          ],
          if (contract.updatedAt != null) ...[
            const SizedBox(height: 8),
            _buildAuditRow(
              'Updated',
              contract.updatedByName,
              contract.updatedAt,
            ),
          ],
          if (contract.createdAt == null && contract.updatedAt == null)
            Text(
              'No audit data available',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
        ],
      ),
    );
  }

  Widget _buildAuditRow(String title, String? byName, DateTime? at) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('•', style: TextStyle(fontSize: 14)),
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
                    if (at != null) DateFormat('dd MMM yyyy, hh:mm a').format(at.toLocal()),
                  ].join(' • '),
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  String _formatDate(String? dateString) {
    if (dateString == null || dateString.isEmpty) return "N/A";
    try {
      final date = DateTime.parse(dateString);
      return DateFormat('dd MMM yyyy').format(date);
    } catch (e) {
      return dateString;
    }
  }
}