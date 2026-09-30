import 'package:crm_train/utills/app_colors.dart';
import 'package:crm_train/view/common_contractor/form_screen/forms/cts_form_screen_v2.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import 'package:get/get.dart';
import '../../../controller/contractor_nav_controller.dart';
import '../../../model/contracts_model.dart';
import '../../../model/user_registeration_model.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/station_cleaning_provider.dart';
import '../../../services/api_services.dart';
import '../../../services/dashboard_counts_service.dart';
import '../../common_railways/widgets/DonutChart.dart';
import '../../common_railways/widgets/indicator_color.dart';
import '../../common_railways/widgets/status_tile.dart';
import 'station_selector_scaffold.dart';
import '../../onboarding_screens/login_screen.dart';
import '../alert/contractor_master_alert_screen.dart';
import '../profile/contractor_master_profile_screen.dart';
import '../form_screen/forms/new_coach_form.dart';
import '../form_screen/forms/new_premises_form.dart';
import '../form_screen/contractor_master_forms_screen.dart';
import '../my_company/contractor_master_my_contracts_screen.dart';

import '../../common_railways/entities/common_entity_managment_screen.dart';
import '../../common_railways/trains/common_train_screen.dart';
import '../../common_railways/users/common_user_management_screen.dart';
import '../../common_railways/contracts/common_contracts_screen.dart';
import '../../common_railways/divisions/division_management_screen.dart';
import '../../common_railways/audit/audit_log_screen.dart';
import '../../common_railways/billing/billing_dashboard_screen.dart';
import '../../common_railways/cleaning_forms/cleaning_form_dashboard.dart';
import '../../station_cleaning_screens/station_cleaning_runs_list_screen.dart';
import '../../common_railways/station_management/station_dashboard_screen.dart';
import '../../common_railways/report/common_report_screen.dart';
import '../../common_railways/ratings/admin_ratings_screen.dart';
import '../../common_railways/station_management/area_list_screen.dart';
import '../../common_railways/station_management/task_generation_screen.dart';
import '../../common_railways/station_management/area_performance_dashboard.dart';
import '../../common_railways/station_management/supervisor_shift_assignment_screen.dart';
import '../../station_cleaning/supervisor_task_screen.dart';
import '../../station_cleaning/workers/worker_management_screen.dart';
import '../../station_cleaning/shift_summary_screen.dart';
import '../../station_cleaning/evidence/evidence_upload_screen.dart';
import '../../station_cleaning/reporting/report_list_screen.dart';
import '../../station_cleaning/dashboard/supervisor_dashboard_screen.dart';
import '../../station_cleaning/attendance/station_supervisor_attendance_screen.dart';
import '../../station_cleaning/feedback/passenger_feedback_form_screen.dart';
import '../../station_cleaning/feedback/passenger_feedback_list_screen.dart';
import '../../station_cleaning/feedback/feedback_qr_screen.dart';
import '../../obhs_screens/obhs_runs_list_screen.dart';
import '../../obhs_screens/obhs_create_run_screen.dart';
import '../../obhs_screens/obhs_attendance_list_screen.dart';
import '../../obhs_screens/obhs_water_checks_screen.dart';
import '../../obhs_screens/obhs_safety_checks_screen.dart';
import '../../obhs_screens/obhs_petty_repairs_screen.dart';
import '../../obhs_screens/obhs_ratings_screen.dart';
import '../../obhs_screens/obhs_analytics_screen.dart';

class ContractorMasterDashboard extends StatefulWidget {
  final String? contractType;
  const ContractorMasterDashboard({super.key, this.contractType});

  @override
  _ContractorMasterDashboardState createState() => _ContractorMasterDashboardState();
}

class _ContractorMasterDashboardState extends State<ContractorMasterDashboard> {

  int coachTotal = 0;
  int coachPending = 0;
  int coachManpowerApproved = 0;
  int coachRejected = 0;
  int coachScoringProgress = 0;
  int coachAutoApproved = 0;
  int coachLocked = 0;

  int premisesTotal = 0;
  int premisesPending = 0;
  int premisesManpowerApproved = 0;
  int premisesRejected = 0;
  int premisesScoringProgress = 0;
  int premisesAutoApproved = 0;
  int premisesLocked = 0;

  int ctsTotal = 0;
  int ctsPending = 0;
  int ctsManpowerApproved = 0;
  int ctsRejected = 0;
  int ctsScoringProgress = 0;
  int ctsAutoApproved = 0;
  int ctsLocked = 0;


  Map<String, dynamic> coachCleaningStats = {};
  Map<String, dynamic> premisesCleaningStats = {};
  Map<String, dynamic> ctsStats = {};
  bool isChartLoading = true;
  bool isStatsLoading = true;

  Map<String, dynamic>? scDashboard;
  Map<String, dynamic>? scDailyReport;
  bool isScLoading = true;

  String dateRange = 'Last 30 days';

  List<Map<String, dynamic>> get coachKpi => [
    {'title': 'Pending', 'value': coachPending.toString()},
    {'title': 'Approved', 'value': coachManpowerApproved.toString()},
    {'title': 'Rejected', 'value': coachRejected.toString()},
    {'title': 'Scoring Progress', 'value': coachScoringProgress.toString()},
    {'title': 'Auto-Approved', 'value': coachAutoApproved.toString()},
    {'title': 'Locked', 'value': coachLocked.toString()},
  ];

  List<Map<String, dynamic>> get premisesKpi => [
    {'title': 'Pending', 'value': premisesPending.toString()},
    {'title': 'Approved', 'value': premisesManpowerApproved.toString()},
    {'title': 'Rejected', 'value': premisesRejected.toString()},
    {'title': 'Scoring Progress', 'value': premisesScoringProgress.toString()},
    {'title': 'Auto-Approved', 'value': premisesAutoApproved.toString()},
    {'title': 'Locked', 'value': premisesLocked.toString()},
  ];

  List<Map<String, dynamic>> get ctsKpi => [
    {'title': 'Pending', 'value': ctsPending.toString()},
    {'title': 'Approved', 'value': ctsAutoApproved.toString()},
    {'title': 'Rejected', 'value': ctsRejected.toString()},
    {'title': 'Scoring Progress', 'value': ctsScoringProgress.toString()},
    {'title': 'Auto-Approved', 'value': ctsAutoApproved.toString()},
    {'title': 'Locked', 'value': ctsLocked.toString()},
  ];

  @override
  void initState() {
    super.initState();
    _subscribeToDashboardRefresh();
    _loadAllData();
  }

  // The dashboard tab stays alive inside the persistent bottom nav bar, so
  // switching tabs never re-runs initState. Listen to the nav controller and
  // reload whenever the user returns to the Dashboard tab (e.g. after adding
  // a contractor supervisor on the Users tab) so the UI stays fresh.
  void _subscribeToDashboardRefresh() {
    try {
      final nav = Get.find<ContractorNavController>();
      _navSub = nav.dashboardRefreshTick.listen((_) {
        if (mounted) _loadAllData();
      });
    } catch (_) {
      // Controller not registered (dashboard used outside the nav bar): refresh
      // is only available via the existing pull-to-refresh.
    }
  }

  @override
  void dispose() {
    _navSub?.cancel();
    super.dispose();
  }

  StreamSubscription<int>? _navSub;

  List<ContractModel> ownerContracts = [];
  List<UserRegistrationModel> ownerTeam = [];
  List<UserRegistrationModel> ownerPending = [];
  bool isOwnerLoading = true;
  bool isOwnerError = false;

  int _getDaysFromRange() {
    switch (dateRange) {
      case 'Last 7 days':
        return 7;
      case 'Last 30 days':
        return 30;
      case 'Last 90 days':
        return 90;
      case 'This month':
        final now = DateTime.now();
        return now.day;
      default:
        return 30;
    }
  }

  DateTime? _getStartDate() {
    final now = DateTime.now();
    switch (dateRange) {
      case 'Last 7 days':
        return now.subtract(const Duration(days: 7));
      case 'Last 30 days':
        return now.subtract(const Duration(days: 30));
      case 'Last 90 days':
        return now.subtract(const Duration(days: 90));
      case 'This month':
        return DateTime(now.year, now.month, 1);
      default:
        return now.subtract(const Duration(days: 30));
    }
  }

  DateTime? _getEndDate() {
    final now = DateTime.now();
    if (dateRange == 'This month') {
      return DateTime(now.year, now.month + 1, 0, 23, 59, 59);
    }
    return now;
  }

  Future<void> _loadAllData() async {
    if (_isStationCleaning && _isContractorMaster) {
      await Future.wait([_loadOwnerData()]);
      return;
    }
    await Future.wait([
      _loadFormStatusCounts(),
      _loadCleaningStats(),
      _loadScDashboard(),
    ]);
  }

  Future<void> _loadOwnerData() async {
    setState(() {
      isOwnerLoading = true;
      isOwnerError = false;
    });
    try {
      final user = Provider.of<AuthProvider>(context, listen: false).currentUser;
      if (user == null || user.entityId == null || user.entityId!.isEmpty) {
        if (mounted) setState(() { isOwnerLoading = false; isOwnerError = true; });
        return;
      }
      final results = await Future.wait([
        // Only this entity's team is rendered here, so ask the server for it
        // instead of downloading every user in scope (that payload is what made
        // the screen stall right after login on slow connections).
        ApiService.getContractsContractor(user.entityId!, contractType: 'station_cleaning'),
        ApiService.getApprovedUsers(entityId: user.entityId, limit: 100),
        ApiService.getPendingUsers(entityId: user.entityId, limit: 100),
      ]);
      final contracts = (results[0] as List).cast<ContractModel>();
      final approved = (results[1] as List).cast<UserRegistrationModel>();
      final pending = (results[2] as List).cast<UserRegistrationModel>();
      final team = approved
          .where((u) => u.entityId == user.entityId && u.role != 'Contractor Master')
          .toList();
      if (mounted) {
        setState(() {
          ownerContracts = contracts;
          ownerTeam = team;
          ownerPending = pending;
          isOwnerLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() { isOwnerLoading = false; isOwnerError = true; });
      }
    }
  }

  Future<void> _loadScDashboard() async {
    if (!_isStationCleaning) return;
    setState(() => isScLoading = true);
    try {
      final user = Provider.of<AuthProvider>(context, listen: false).currentUser;
      if (user == null) { setState(() => isScLoading = false); return; }
      final provider = StationCleaningProvider();
      String stationId = user.stationId ?? '';
      if (stationId.isEmpty && (user.stations is List) && (user.stations as List).isNotEmpty) {
        stationId = (user.stations as List).first.toString();
      }
      final isAdmin = user.role == 'Contractor Admin' || user.role == 'Contractor Master' || user.role == 'Company Master';
      final results = await Future.wait([
        isAdmin
            ? provider.fetchAdminDashboard(stationId)
            : provider.fetchSupervisorDashboard(user.uid),
        if (stationId.isNotEmpty) provider.fetchDailyReport(stationId),
      ]);
      if (mounted) setState(() {
        scDashboard = results[0];
        scDailyReport = stationId.isNotEmpty ? results.elementAt(1) : null;
        isScLoading = false;
      });
    } catch (e) {
      if (mounted) setState(() { scDashboard = null; scDailyReport = null; isScLoading = false; });
    }
  }

  String? get _effectiveContractType => widget.contractType;
  bool get _isStationCleaning => _effectiveContractType == 'station_cleaning';
  bool get _isOBHS => _effectiveContractType == 'obhs';
  bool get _isContractorMaster {
    final user = Provider.of<AuthProvider>(context, listen: false).currentUser;
    return user?.role == 'Contractor Master';
  }

  Future<void> _loadFormStatusCounts() async {
    final user = Provider.of<AuthProvider>(context, listen: false).currentUser;
    if (user == null) {
      return;
    }

    setState(() => isChartLoading = true);

    try {
      final days = _getDaysFromRange();

      // Station cleaning users don't need form status counts from OBHS forms
      if (!_isStationCleaning) {
        final coachStats = await FirebaseCountService.getFormStatusCounts(
          formType: 'coach',
          days: days,
          entityId: user.entityId,
          contractId: user.contractId,
        );

        print("Coach Forms Stats: $coachStats");

        setState(() {
          coachTotal = coachStats['total'] ?? 0;
          coachPending = coachStats['pending'] ?? 0;
          coachManpowerApproved = coachStats['manpowerApproved'] ?? 0;
          coachRejected = coachStats['rejected'] ?? 0;
          coachScoringProgress = coachStats['scoringProgress'] ?? 0;
          coachAutoApproved = coachStats['autoApproved'] ?? 0;
          coachLocked = coachStats['locked'] ?? 0;
        });
      }

      final premisesStatsData = await FirebaseCountService.getFormStatusCounts(
        formType: 'premises',
        days: days,
        entityId: user.entityId,
        contractId: user.contractId,
      );

      print("Premises Forms Stats: $premisesStatsData");

      setState(() {
        premisesTotal = premisesStatsData['total'] ?? 0;
        premisesPending = premisesStatsData['pending'] ?? 0;
        premisesManpowerApproved = premisesStatsData['manpowerApproved'] ?? 0;
        premisesRejected = premisesStatsData['rejected'] ?? 0;
        premisesScoringProgress = premisesStatsData['scoringProgress'] ?? 0;
        premisesAutoApproved = premisesStatsData['autoApproved'] ?? 0;
        premisesLocked = premisesStatsData['locked'] ?? 0;
      });

      final ctsStatsData = await FirebaseCountService.getFormStatusCounts(
        formType: 'cts',
        days: days,
        entityId: user.entityId,
        contractId: user.contractId,
      );

      print("CTS Forms Stats: $ctsStatsData");

      setState(() {
        ctsTotal = ctsStatsData['total'] ?? 0;
        ctsPending = ctsStatsData['pending'] ?? 0;
        ctsManpowerApproved = ctsStatsData['manpowerApproved'] ?? 0;
        ctsRejected = ctsStatsData['rejected'] ?? 0;
        ctsScoringProgress = ctsStatsData['scoringProgress'] ?? 0;
        ctsAutoApproved = ctsStatsData['autoApproved'] ?? 0;
        ctsLocked = ctsStatsData['locked'] ?? 0;

        isChartLoading = false;
      });
    } catch (e) {
      print("Error loading form status counts: $e");
      setState(() => isChartLoading = false);
    }
  }

  Future<void> _loadCleaningStats() async {
    final user = Provider.of<AuthProvider>(context, listen: false).currentUser;
    if (user == null) return;

    // Station cleaning users don't need OBHS cleaning stats
    if (_isStationCleaning) {
      setState(() => isStatsLoading = false);
      return;
    }

    setState(() => isStatsLoading = true);

    try {
      final startDate = _getStartDate();
      final endDate = _getEndDate();

      print("Loading Cleaning Stats...");

      final coachStatsData = await FirebaseCountService.getCoachCleaningStats(
        userRole: user.role,
        uid: user.uid,
        zone: user.zone,
        division: user.division,
        depot: user.depot,
        entityId: user.entityId,
        contractId: user.contractId,
        startDate: startDate,
        endDate: endDate,
      );


      final premisesStatsData = await FirebaseCountService.getPremisesCleaningStats(
        userRole: user.role,
        uid: user.uid,
        zone: user.zone,
        division: user.division,
        depot: user.depot,
        entityId: user.entityId,
        contractId: user.contractId,
        startDate: startDate,
        endDate: endDate,
      );


      setState(() {
        coachCleaningStats = coachStatsData;
        premisesCleaningStats = premisesStatsData;
        isStatsLoading = false;
      });
    } catch (e) {
      print("Error loading cleaning stats: $e");
      setState(() => isStatsLoading = false);
    }
  }

  final List<String> dateRanges = [
    'Last 7 days',
    'Last 30 days',
    'Last 90 days',
    'This month'
  ];

  @override

  List<Map<String, dynamic>> _getSidebarMenuItems(String? userRole, String? contractType) {
    List<Map<String, dynamic>> items = [
      {
        "icon": Icons.dashboard_rounded,
        "title": "Dashboard",
        "route": null,
        "roles": ["Contractor Master", "Company Master", "Contractor Admin", "Railway Master", "Railway Admin", "Railway Supervisor", "Contractor Supervisor"]
      },
      {
        "icon": Icons.admin_panel_settings,
        "title": "Masters",
        "roles": ["Contractor Master", "Company Master", "Contractor Admin", "Railway Master", "Railway Admin"],
        "children": [
          {"title": "User Management", "route": "users"},
          {"title": "Entity Management", "route": "entities", "roles": ["Contractor Master", "Company Master", "Railway Master", "Railway Admin"]},
          {"title": "Contract Management", "route": "contracts", "roles": ["Contractor Master", "Company Master", "Railway Master", "Railway Admin"]},
          {"title": "Station Management", "route": "station_management_master", "contractTypes": ["station_cleaning"]},
          {"title": "Train Management", "route": "trains", "contractTypes": ["obhs"]},
          {"title": "Division Management", "route": "divisions", "roles": ["Contractor Master", "Company Master", "Railway Master", "Railway Admin"]},
          {"title": "Billing Rules", "route": "billing_rules"},
        ]
      },
      {
        "icon": Icons.cleaning_services,
        "title": "Operations",
        "roles": ["Contractor Master", "Company Master", "Contractor Admin", "Railway Master", "Railway Admin", "Railway Supervisor"],
        "children": [
          {"title": "Coach Cleaning", "route": "coach_cleaning", "contractTypes": ["obhs"]},
          {"title": "Premise Cleaning", "route": "premise_cleaning", "contractTypes": ["obhs"]},
          {"title": "CTS Forms", "route": "cts_cleaning", "contractTypes": ["obhs"]},
        ]
      },
      {
        "icon": Icons.train,
        "title": "OBHS Operations",
        "roles": ["Contractor Master", "Company Master", "Contractor Admin", "Railway Master", "Railway Admin", "Railway Supervisor", "Contractor Supervisor"],
        "contractTypes": ["obhs"],
        "children": [
          {"title": "OBHS Runs", "route": "obhs_runs"},
          {"title": "Create OBHS Run", "route": "obhs_create_run"},
          {"title": "OBHS Attendance", "route": "obhs_attendance"},
          {"title": "Water Checks", "route": "obhs_water"},
          {"title": "Safety Checks", "route": "obhs_safety"},
          {"title": "Petty Repairs", "route": "obhs_repairs"},
          {"title": "Ratings", "route": "obhs_ratings"},
          {"title": "Analytics", "route": "obhs_analytics"},
        ]
      },
      {
        "icon": Icons.cleaning_services_rounded,
        "title": "Station Cleaning",
        "roles": ["Contractor Master", "Company Master", "Contractor Admin", "Railway Master", "Railway Admin"],
        "contractTypes": ["station_cleaning"],
        "children": [
          {"title": "Area Management", "route": "sc_areas"},
          {"title": "Generate Tasks", "route": "sc_generate_tasks"},
          {"title": "Passenger Feedback", "route": "sc_passenger_feedback"},
          {"title": "Supervisor Attendance", "route": "sc_supervisor_attendance"},
          {"title": "Supervisor Shifts", "route": "sc_supervisor_shifts"},
        ]
      },
      {
        "icon": Icons.assignment,
        "title": "My Tasks",
        "roles": ["Contractor Supervisor"],
        "contractTypes": ["station_cleaning"],
        "children": [
          {"title": "Dashboard", "route": "sc_supervisor_dashboard"},
          {"title": "My Tasks", "route": "sc_supervisor_tasks"},
          {"title": "Workers", "route": "sc_supervisor_workers"},
          {"title": "Shift Summary", "route": "sc_supervisor_shift_summary"},
          {"title": "Passenger Feedback", "route": "sc_supervisor_passenger_feedback"},
        ]
      },
      {
        "icon": Icons.analytics,
        "title": "Reports",
        "roles": ["Contractor Master", "Company Master", "Contractor Admin", "Railway Master", "Railway Admin", "Railway Supervisor", "Contractor Supervisor"],
        "children": [
          {"title": "Coach Reports", "route": "coach_reports", "contractTypes": ["obhs"]},
          {"title": "Premise Reports", "route": "premise_reports", "contractTypes": ["obhs"]},
          {"title": "CTS Reports", "route": "cts_reports", "contractTypes": ["obhs"]},
          {"title": "Station Reports", "route": "station_reports", "contractTypes": ["station_cleaning"]},
        ]
      },
      {
        "icon": Icons.receipt_long,
        "title": "Billing",
        "route": "billing",
        "roles": ["Contractor Master", "Company Master", "Contractor Admin", "Railway Master", "Railway Admin", "Railway Supervisor"]
      },
      {
        "icon": Icons.star_outline,
        "title": "Ratings",
        "route": "ratings",
        "contractTypes": ["obhs"],
        "roles": ["Contractor Master", "Company Master", "Contractor Admin", "Railway Master", "Railway Admin", "Railway Supervisor"]
      },
      {
        "icon": Icons.security,
        "title": "Audit & Compliance",
        "roles": ["Contractor Master", "Company Master", "Contractor Admin", "Railway Master", "Railway Admin"],
        "children": [
          {"title": "Compliance & Security Tracking", "route": "audit_logs"},
          {"title": "Business Activities", "route": "activity_logs"},
        ]
      },
    ];

    return items.where((item) {
      if (!(item['roles'] as List<String>).contains(userRole)) return false;
      if (item.containsKey('contractTypes') && contractType != null) {
        final allowedTypes = item['contractTypes'] as List<String>;
        if (!allowedTypes.contains(contractType)) return false;
      }
      return true;
    }).map((item) {
      if (item.containsKey('children')) {
        final children = (item['children'] as List<Map<String, dynamic>>).where((child) {
          if (child.containsKey('roles')) {
            final allowedRoles = child['roles'] as List<String>;
            if (!allowedRoles.contains(userRole)) return false;
          }
          if (child.containsKey('contractTypes') && contractType != null) {
            final allowedTypes = child['contractTypes'] as List<String>;
            if (!allowedTypes.contains(contractType)) return false;
          }
          return true;
        }).toList();
        item['children'] = children;
      }
      return item;
    }).where((item) => !item.containsKey('children') || (item['children'] as List).isNotEmpty).toList();
  }

  void _navigateWithStationSelector(
    BuildContext context,
    String title,
    IconData icon,
    Widget Function(BuildContext context, String stationId, String stationName) screenBuilder,
    dynamic user,
  ) {
    final navigator = Navigator.of(context);
    List<String> allowed = [];
    if (user?.stations is List) {
      allowed = (user.stations as List).whereType<String>().toList();
    }
    navigator.push(MaterialPageRoute(
      builder: (_) => StationSelectorScaffold(
        title: title,
        icon: icon,
        allowedStationIds: allowed,
        initialStationId: user?.stationId?.toString(),
        builder: screenBuilder,
      ),
    ));
  }

  void _navigateWithStation(BuildContext context, Widget Function(String stationId, String stationName) screenBuilder, dynamic user) async {
    final navigator = Navigator.of(context);
    String stationId = user?.stationId ?? '';
    if (stationId.isEmpty && (user?.stations is List) && (user.stations as List).isNotEmpty) {
      stationId = (user.stations as List).first.toString();
    }
    String stationName = '';
    if (stationId.isNotEmpty && stationName.isEmpty) {
      try {
        final stations = await ApiService.getStations(active: true);
        final match = stations.where((s) => s.uid == stationId).firstOrNull;
        if (match != null) stationName = match.stationName;
      } catch (_) {}
    }
    if (mounted) {
      navigator.push(MaterialPageRoute(builder: (context) => screenBuilder(stationId, stationName)));
    }
  }

  void _handleSidebarNavigation(String? route, BuildContext context, String? userRole) {
    if (route == null) {
      Navigator.pop(context); // Close drawer
      return;
    }

    Navigator.pop(context); // Always close drawer on selection

    final user = Provider.of<AuthProvider>(context, listen: false).currentUser;

    switch (route) {
      case "users":
        Navigator.push(context, MaterialPageRoute(builder: (context) => CommonUserManagementScreen()));
        break;
      case "entities":
        Navigator.push(context, MaterialPageRoute(builder: (context) => CommonEntityManagmentScreen()));
        break;
      case "contracts":
        Navigator.push(context, MaterialPageRoute(builder: (context) => CommonContractsScreen(userRole: userRole ?? '')));
        break;
      case "station_management_master":
        Navigator.push(context, MaterialPageRoute(builder: (context) => const StationDashboardScreen()));
        break;
      case "trains":
        Navigator.push(context, MaterialPageRoute(builder: (context) => const CommonTrainScreen()));
        break;
      case "coach_cleaning":
        Navigator.push(context, MaterialPageRoute(builder: (context) => ContractorMasterFormsScreen(initialTabIndex: 0)));
        break;
      case "premise_cleaning":
        Navigator.push(context, MaterialPageRoute(builder: (context) => ContractorMasterFormsScreen(initialTabIndex: 1)));
        break;
      case "cts_cleaning":
        Navigator.push(context, MaterialPageRoute(builder: (context) => ContractorMasterFormsScreen(initialTabIndex: 2)));
        break;
      case "obhs_runs":
        Navigator.push(context, MaterialPageRoute(builder: (context) => const OBHSRunsListScreen()));
        break;
      case "obhs_create_run":
        Navigator.push(context, MaterialPageRoute(builder: (context) => const OBHSCreateInstanceScreen()));
        break;
      case "obhs_attendance":
        Navigator.push(context, MaterialPageRoute(builder: (context) => const OBHSAttendanceListScreen()));
        break;
      case "obhs_water":
        Navigator.push(context, MaterialPageRoute(builder: (context) => const ObhsWaterChecksScreen()));
        break;
      case "obhs_safety":
        Navigator.push(context, MaterialPageRoute(builder: (context) => const ObhsSafetyChecksScreen()));
        break;
      case "obhs_repairs":
        Navigator.push(context, MaterialPageRoute(builder: (context) => const ObhsPettyRepairsScreen()));
        break;
      case "obhs_ratings":
        Navigator.push(context, MaterialPageRoute(builder: (context) => const ObhsRatingsScreen()));
        break;
      case "obhs_analytics":
        Navigator.push(context, MaterialPageRoute(builder: (context) => const ObhsAnalyticsScreen()));
        break;
      case "station_cleaning":
        Navigator.push(context, MaterialPageRoute(builder: (context) => const StationDashboardScreen()));
        break;
      case "station_cleaning_runs":
        Navigator.push(context, MaterialPageRoute(builder: (context) => const StationCleaningRunsListScreen()));
        break;
      case "sc_areas":
        Navigator.push(context, MaterialPageRoute(builder: (context) => const AreaListScreen()));
        break;
      case "sc_generate_tasks":
        Navigator.push(context, MaterialPageRoute(builder: (context) => const TaskGenerationScreen()));
        break;
      case "sc_performance":
        Navigator.push(context, MaterialPageRoute(builder: (context) => const AreaPerformanceDashboard()));
        break;
      case "coach_reports":
        Navigator.push(context, MaterialPageRoute(builder: (context) => const CommonReportScreen(initialIndex: 1)));
        break;
      case "premise_reports":
        Navigator.push(context, MaterialPageRoute(builder: (context) => const CommonReportScreen(initialIndex: 0)));
        break;
      case "cts_reports":
        Navigator.push(context, MaterialPageRoute(builder: (context) => const CommonReportScreen(initialIndex: 2)));
        break;
      case "station_reports":
        _navigateWithStation(context, (stationId, stationName) => ReportListScreen(
          stationId: stationId,
          stationName: stationName,
          role: user?.role ?? '',
        ), user);
        break;
      case "divisions":
        Navigator.push(context, MaterialPageRoute(builder: (context) => const DivisionManagementScreen()));
        break;
      case "billing_rules":
      case "billing":
        _navigateWithStationSelector(context, 'Billing', Icons.receipt_long, (ctx, stationId, stationName) =>
            BillingDashboardScreen(stationId: stationId, stationName: stationName), user);
        break;
      case "ratings":
        Navigator.push(context, MaterialPageRoute(builder: (context) => const AdminRatingsScreen()));
        break;
      case "audit_logs":
      case "activity_logs":
        Navigator.push(context, MaterialPageRoute(builder: (context) => const AuditLogScreen()));
        break;
      case "sc_supervisor_dashboard":
        _navigateWithStation(context, (stationId, stationName) => SupervisorDashboardScreen(
          stationId: stationId,
          stationName: stationName,
        ), user);
        break;
      case "sc_supervisor_tasks":
        _navigateWithStation(context, (stationId, stationName) => SupervisorTaskScreen(
          stationId: stationId,
          stationName: stationName,
          supervisorId: user?.uid ?? '',
          supervisorName: user?.fullName ?? '',
        ), user);
        break;
      case "sc_supervisor_workers":
        _navigateWithStation(context, (stationId, stationName) => WorkerManagementScreen(
          stationId: stationId,
          stationName: stationName,
        ), user);
        break;
      case "sc_supervisor_shift_summary":
        _navigateWithStation(context, (stationId, stationName) => ShiftSummaryScreen(
          stationId: stationId,
          stationName: stationName,
          supervisorId: user?.uid ?? '',
          supervisorName: user?.fullName ?? '',
          shift: 'Morning',
          date: DateTime.now().toIso8601String().split('T')[0],
          areas: const [],
        ), user);
        break;
      case "sc_supervisor_passenger_feedback":
        _navigateWithStation(context, (stationId, stationName) => _PassengerFeedbackChooser(
          stationId: stationId,
          stationName: stationName,
        ), user);
        break;
      case "sc_passenger_feedback":
        _navigateWithStationSelector(context, 'Passenger Feedback', Icons.feedback, (ctx, stationId, stationName) =>
            _PassengerFeedbackChooser(stationId: stationId, stationName: stationName), user);
        break;
      case "sc_supervisor_attendance":
        _navigateWithStationSelector(context, 'Supervisor Attendance', Icons.verified_user, (ctx, stationId, stationName) =>
            StationSupervisorAttendanceScreen(stationId: stationId, stationName: stationName), user);
        break;
      case "sc_supervisor_shifts":
        _navigateWithStationSelector(context, 'Supervisor Shifts', Icons.nights_stay, (ctx, stationId, stationName) =>
            SupervisorShiftAssignmentScreen(stationId: stationId, stationName: stationName), user);
        break;
      default:
        break;
    }
  }

  Widget _buildDrawer(var user, List<Map<String, dynamic>> sidebarMenuItems) {
    return Drawer(
      child: Column(
        children: [
          // Drawer Header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [kRailwayBlue, Colors.lightBlue],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  backgroundColor: Colors.white,
                  radius: 35,
                  child: Icon(Icons.person, size: 40, color: kRailwayBlue),
                ),
                const SizedBox(height: 12),
                Text(
                  user?.fullName ?? 'User',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  user?.role ?? '',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          // Menu Items
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: sidebarMenuItems.length,
              itemBuilder: (context, index) {
                final item = sidebarMenuItems[index];
                final isCurrentScreen = item['route'] == null && !item.containsKey('children');

                if (item.containsKey('children')) {
                  final children = item['children'] as List<Map<String, dynamic>>;
                  return ExpansionTile(
                    leading: Icon(
                      item['icon'] as IconData,
                      color: Colors.grey[700],
                    ),
                    title: Text(
                      item['title'] as String,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[800],
                      ),
                    ),
                    children: children.map((child) {
                      return ListTile(
                        contentPadding: const EdgeInsets.only(left: 72, right: 16),
                        title: Text(
                          child['title'] as String,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[700],
                          ),
                        ),
                        onTap: () => _handleSidebarNavigation(
                          child['route'] as String?,
                          context,
                          user?.role,
                        ),
                      );
                    }).toList(),
                  );
                }

                return ListTile(
                  leading: Icon(
                    item['icon'] as IconData,
                    color: isCurrentScreen ? kRailwayBlue : Colors.grey[700],
                  ),
                  title: Text(
                    item['title'] as String,
                    style: TextStyle(
                      fontWeight: isCurrentScreen ? FontWeight.bold : FontWeight.w500,
                      color: isCurrentScreen ? kRailwayBlue : Colors.grey[800],
                    ),
                  ),
                  selected: isCurrentScreen,
                  selectedTileColor: kRailwayBlue.withOpacity(0.1),
                  onTap: () => _handleSidebarNavigation(
                    item['route'] as String?,
                    context,
                    user?.role,
                  ),
                );
              },
            ),
          ),
          // Logout Button
          Container(
            padding: const EdgeInsets.all(16),
            child: ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text(
                'Logout',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Colors.red,
                ),
              ),
              onTap: () async {
                final authProvider = Provider.of<AuthProvider>(context, listen: false);
                await authProvider.logout();
                Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (context) => const LoginScreen()),
                  (route) => false,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final user = authProvider.currentUser;
    final entityDetails = authProvider.entityDetails;
    const cardBg = Colors.white;
    const accentGreen = Color(0xFF12C27D);
    const softBorder = Color(0xFFE8E8F0);

    final sidebarMenuItems = _getSidebarMenuItems(user?.role, user?.contractType ?? user?.domain);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Dashboard',
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.w600, fontSize: 20),
        ),
        backgroundColor: kRailwayBlue,
        elevation: 0.5,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(onPressed: (){

            Navigator.push(context, MaterialPageRoute(builder: (context) => ContractorMasterProfileScreen()));

          }, icon: CircleAvatar(
              backgroundColor: Colors.white,
              radius: 16,
              child: Icon(Icons.person,color: kRailwayBlue))),
          IconButton(onPressed: (){

            Navigator.push(context, MaterialPageRoute(builder: (context) => ContractorMasterAlertScreen()));

          }, icon: Icon(Icons.notifications,color: Colors.white,)),
          IconButton(onPressed: (){
            Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
              MaterialPageRoute(builder: (context) => const LoginScreen()),
                  (route) => false,
            );
          },
              icon: Icon(Icons.logout,color: Colors.white,)),

        ],

      ),
      drawer: _buildDrawer(user, sidebarMenuItems),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadAllData,
          color: kRailwayBlue,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black12,
                          blurRadius: 6,
                          offset: Offset(0, 3))
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: EdgeInsets.all(10),
                        decoration: BoxDecoration(
                            color: kRailwayBlue.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(10)
                        ),
                        child:  Icon(Icons.location_city_outlined, color: kRailwayBlue),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children:  [
                            Text(user?.fullName ?? "NA",
                                style:
                                TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                            SizedBox(height: 4),
                            Text( entityDetails?['companyName'] ?? 'N/A',
                                style: TextStyle(fontSize: 13, color: Colors.black54)),
                            SizedBox(height: 2),
                            Text('${_formatContractType(user?.contractType ?? '')} | ${user?.division ?? "N/A"}',
                                style: TextStyle(fontSize: 12, color: Colors.black45)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                if (!(_isStationCleaning && _isContractorMaster))
                  Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x0A000000),
                        blurRadius: 6,
                        offset: Offset(0, 3),
                      )
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Date Range',
                        style:
                        TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                      const SizedBox(height: 8),
                      _buildDropdown(
                          current: dateRange,
                          items: dateRanges,
                          onChanged: (v) {
                            setState(() => dateRange = v!);
                            _loadAllData();
                          }),
                    ],
                  ),
                ),

                const SizedBox(height: 18),

                if (_isStationCleaning) ...[
                  if (_isContractorMaster)
                    _buildMasterOwnerDashboard()
                  else
                    _buildStationCleaningDashboard(),
                ] else ...[

                // OBHS and railway users see the full forms dashboard
                // OBHS and railway users see the full forms dashboard
                if (!_isStationCleaning) ...[
                  Text("Forms Overview",
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87)),
                  const SizedBox(height: 10),

                  SizedBox(
                    height: 370,
                    child: ListView(
                      shrinkWrap: true,
                      scrollDirection: Axis.horizontal,
                      children: [
                        _buildFormsCard(
                          'Coach\nCleaning',
                          pending: coachPending,
                          approved: coachManpowerApproved,
                          rejected: coachRejected,
                          progress: coachScoringProgress,
                          autoApproved: coachAutoApproved,
                          locked: coachLocked,
                        ),
                        const SizedBox(width: 16),
                        _buildFormsCard(
                          'Premises\nCleaning',
                          pending: premisesPending,
                          approved: premisesManpowerApproved,
                          rejected: premisesRejected,
                          progress: premisesScoringProgress,
                          autoApproved: premisesAutoApproved,
                          locked: premisesLocked,
                        ),
                        const SizedBox(width: 16),
                        _buildFormsCard(
                          'CTS\nForm',
                          pending: ctsPending,
                          approved: ctsManpowerApproved,
                          rejected: ctsRejected,
                          progress: ctsScoringProgress,
                          autoApproved: ctsAutoApproved,
                          locked: ctsLocked,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  Text("Coach Cleaning Forms",
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87)),
                  const SizedBox(height: 10),

                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(
                        children: List.generate(coachKpi.length, (index) {
                          final item = coachKpi[index];
                          return Padding(
                            padding: const EdgeInsets.only(right: 12),
                            child: StatusTile(
                              number: int.parse(item['value']),
                              label: item['title'],
                            ),
                          );
                        }),
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  Text("Premises Cleaning Forms",
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87)),
                  const SizedBox(height: 10),

                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(
                        children: List.generate(premisesKpi.length, (index) {
                          final item = premisesKpi[index];
                          return Padding(
                            padding: const EdgeInsets.only(right: 12),
                            child: StatusTile(
                              number: int.parse(item['value']),
                              label: item['title'],
                            ),
                          );
                        }),
                      ),
                    ),
                  ),


                  const SizedBox(height: 20),

                  Text("CTS Forms",
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87)),
                  const SizedBox(height: 10),

                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(
                        children: List.generate(ctsKpi.length, (index) {
                          final item = ctsKpi[index];
                          return Padding(
                            padding: const EdgeInsets.only(right: 12),
                            child: StatusTile(
                              number: int.parse(item['value']),
                              label: item['title'],
                            ),
                          );
                        }),
                      ),
                    ),
                  ),

                  const SizedBox(height: 18),

                  Column(
                    children: [
                      _scoreCardCoach(
                        title: 'Overall Score — Coach Cleaning',
                        accent: accentGreen,
                        softBorder: softBorder,
                        cardBg: cardBg,
                        subtitle: 'Based on selected filters',
                        iconInner: Icons.cleaning_services,
                      ),

                      const SizedBox(height: 12),
                      _scoreCardPremises(
                        title: 'Overall Score — Premises Cleaning',
                        accent: accentGreen,
                      softBorder: softBorder,
                      cardBg: cardBg,
                      subtitle: 'Based on selected filters',
                      iconInner: Icons.cleaning_services,
                    ),
                  ],
                ),
                ],

                const SizedBox(height: 18),



                if(!_isStationCleaning && user?.role == 'Contractor Supervisor')
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: const [
                          BoxShadow(
                              color: Color(0x0A000000), blurRadius: 6, offset: Offset(0,3))
                        ]),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Quick Actions',
                            style: TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 16)),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: GestureDetector(
                                onTap: () {
                                  Navigator.of(context).push(MaterialPageRoute(
                                      builder: (_) => const NewCoachFormScreen()));
                                },
                                child: Container(
                                  height: 96,
                                  margin: const EdgeInsets.only(right: 8),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFE8FBF0),
                                    borderRadius: BorderRadius.circular(12),
                                    border:
                                    Border.all(color: const Color(0xFFCFF3E2)),
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: const [
                                      Icon(Icons.note_add, size: 28, color: Colors.green),
                                      SizedBox(height: 8),
                                      Text('New Coach Form',
                                          style: TextStyle(fontWeight: FontWeight.w600))
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            Expanded(
                              child: GestureDetector(
                                onTap: () {
                                  Navigator.of(context).push(MaterialPageRoute(
                                      builder: (_) =>  PremisesCleaningForm()));
                                },
                                child: Container(
                                  height: 96,
                                  margin: const EdgeInsets.only(left: 8),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF6EDFF),
                                    borderRadius: BorderRadius.circular(12),
                                    border:
                                    Border.all(color: const Color(0xFFEBDEF9)),
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: const [
                                      Icon(Icons.library_add, size: 28, color: Colors.purple),
                                      SizedBox(height: 8),
                                      Text('New Premises Form',
                                          style: TextStyle(fontWeight: FontWeight.w600))
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12,),
                        Row(
                          children: [
                            Expanded(
                              child: GestureDetector(
                                onTap: () {
                                  Navigator.of(context).push(MaterialPageRoute(
                                      builder: (_) => const NewCTSFormScreen()));
                                },
                                child: Container(
                                  height: 96,
                                  margin: const EdgeInsets.only(right: 8),
                                  decoration: BoxDecoration(
                                    color:   Colors.orange.shade50,
                                    borderRadius: BorderRadius.circular(12),
                                    border:
                                    Border.all(color:  Colors.orange.shade100),
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: const [
                                      Icon(Icons.note_add, size: 28, color: Colors.orange),
                                      SizedBox(height: 8),
                                      Text('New CTS Form',
                                          style: TextStyle(fontWeight: FontWeight.w600))
                                    ],
                                  ),
                                ),
                              ),
                            ),

                          ],
                        )
                      ],
                    ),
                  ),


                const SizedBox(height: 28)
              ],
            ],
            ),
          ),
        ),
      ),
    );
  }


  Widget _buildMasterOwnerDashboard() {
    if (isOwnerLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 60),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (isOwnerError) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              const Icon(Icons.error_outline, size: 44, color: kErrorRed),
              const SizedBox(height: 10),
              const Text('Could not load entity overview',
                  textAlign: TextAlign.center),
              const SizedBox(height: 12),
              ElevatedButton(
                  onPressed: _loadOwnerData, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final user = authProvider.currentUser;
    final entityDetails = authProvider.entityDetails;
    final companyName =
        entityDetails?['companyName']?.toString() ?? user?.fullName ?? 'My Entity';

    final activeContracts = ownerContracts
        .where((c) => c.status == 'Active' || c.isActive == true)
        .toList();
    final stationSet = <String>{};
    for (final c in ownerContracts) {
      stationSet.addAll(c.stationNames);
    }
    final stationNames = stationSet.where((s) => s.isNotEmpty).toList();

    final todayLabel = DateFormat('EEE, dd MMM yyyy').format(DateTime.now());
    final zone = user?.zone ?? 'N/A';
    final division = user?.division ?? 'N/A';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: const LinearGradient(colors: [kRailwayBlue, Colors.lightBlue],
                begin: Alignment.topLeft, end: Alignment.bottomRight),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(todayLabel,
                            style: const TextStyle(color: Colors.white70, fontSize: 13)),
                        const SizedBox(height: 6),
                        const Text('Entity Overview',
                            style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Text('$companyName  •  $zone / $division',
                            style: const TextStyle(color: Colors.white70, fontSize: 13)),
                      ],
                    ),
                  ),
                  Container(
                    width: 54,
                    height: 54,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
                    ),
                    child: const Icon(Icons.apartment, color: Colors.white, size: 28),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: const LinearProgressIndicator(
                  value: 0.0,
                  minHeight: 10,
                  backgroundColor: Colors.white24,
                  valueColor: AlwaysStoppedAnimation(Colors.white),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        Row(children: [
          _ownerStatCard(Icons.assignment_outlined, 'Contracts', activeContracts.length.toString(), kRailwayBlue),
          const SizedBox(width: 8),
          _ownerStatCard(Icons.apartment, 'Stations', stationNames.length.toString(), kSuccessGreen),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          _ownerStatCard(Icons.people_outline, 'Team', ownerTeam.length.toString(), Colors.teal),
          const SizedBox(width: 8),
          _ownerStatCard(Icons.hourglass_top, 'Pending Approvals', ownerPending.length.toString(),
              ownerPending.isEmpty ? Colors.grey : kWarningOrange),
        ]),
        const SizedBox(height: 18),

        _ownerSectionHeader(Icons.pending_actions, 'Approvals',
            onSeeAll: _openUserManagement),
        const SizedBox(height: 8),
        if (ownerPending.isEmpty)
          _ownerEmptyCard('No pending approvals', Icons.task_alt)
        else
          ...ownerPending.take(4).map((u) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _pendingApprovalTile(u),
              )),
        const SizedBox(height: 14),

        _ownerSectionHeader(Icons.assignment_outlined, 'Your Contracts (Station Cleaning)',
            onSeeAll: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const ContractorMasterMyContractsScreen()),
              );
            }),
        const SizedBox(height: 8),
        if (ownerContracts.isEmpty)
          _ownerEmptyCard('No station cleaning contracts found', Icons.assignment_late)
        else
          ...ownerContracts.take(4).map((c) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _contractTile(c),
              )),
        const SizedBox(height: 14),

        _ownerSectionHeader(Icons.train_outlined, 'Stations at a glance',
            onSeeAll: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const StationCleaningRunsListScreen()),
              );
            }),
        const SizedBox(height: 8),
        if (stationNames.isEmpty)
          _ownerEmptyCard('No stations linked to your contracts', Icons.apartment)
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: stationNames.take(12)
                .map((s) => Chip(
                      avatar: const Icon(Icons.place, size: 16, color: kRailwayBlue),
                      label: Text(s),
                      labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      backgroundColor: Colors.white,
                      side: BorderSide(color: Colors.black12),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                    ))
                .toList(),
          ),
      ],
    );
  }

  void _openUserManagement() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CommonUserManagementScreen()),
    );
  }

  Widget _ownerStatCard(IconData icon, String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 6, offset: Offset(0, 3))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: color),
                const Spacer(),
                Text(value,
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color)),
              ],
            ),
            const SizedBox(height: 6),
            Text(label,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black54)),
          ],
        ),
      ),
    );
  }

  Widget _ownerSectionHeader(IconData icon, String title, {VoidCallback? onSeeAll}) {
    return Row(
      children: [
        Icon(icon, size: 20, color: kRailwayBlue),
        const SizedBox(width: 8),
        Expanded(
          child: Text(title,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        ),
        if (onSeeAll != null)
          TextButton(onPressed: onSeeAll,
              child: const Text('See all', style: TextStyle(fontSize: 13))),
      ],
    );
  }

  Widget _ownerEmptyCard(String message, IconData icon) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 6, offset: Offset(0, 3))],
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.grey[400]),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message,
                style: const TextStyle(color: Colors.black45, fontSize: 13)),
          ),
        ],
      ),
    );
  }

  Widget _contractTile(ContractModel c) {
    final status = c.status ?? (c.isActive == true ? 'Active' : 'Inactive');
    final statusColor = status.toLowerCase() == 'active' ? kSuccessGreen : kWarningOrange;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 6, offset: Offset(0, 3))],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: kRailwayBlue.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.description_outlined, color: kRailwayBlue),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(c.contractName ?? c.contractNumber ?? 'Contract',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                const SizedBox(height: 3),
                Text([
                      c.contractNumber ?? '',
                      c.zone ?? '',
                      c.division ?? '',
                    ].where((s) => s.isNotEmpty).join('  •  '),
                    style: const TextStyle(fontSize: 12, color: Colors.black54)),
                if (c.stationNames.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text('${c.stationNames.length} station(s)',
                      style: const TextStyle(fontSize: 12, color: Colors.black45)),
                ],
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(status,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: statusColor)),
          ),
        ],
      ),
    );
  }

  Widget _pendingApprovalTile(UserRegistrationModel u) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 6, offset: Offset(0, 3))],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: kWarningOrange.withValues(alpha: 0.15),
            child: const Icon(Icons.person_outline, color: kWarningOrange),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(u.fullName ?? 'Pending user',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                const SizedBox(height: 3),
                Text(u.role ?? '',
                    style: const TextStyle(fontSize: 12, color: Colors.black54)),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: Colors.black38),
        ],
      ),
    );
  }

  Widget _buildStationCleaningDashboard() {
    if (isScLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 60),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final d = scDashboard;
    if (d == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              const Icon(Icons.error_outline, size: 44, color: kErrorRed),
              const SizedBox(height: 10),
              const Text('Could not load station cleaning dashboard',
                  textAlign: TextAlign.center),
              const SizedBox(height: 12),
              ElevatedButton(onPressed: _loadScDashboard, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    final isAdminDashboard = d.containsKey('supervisors');

    final total = (d['totalTasks'] ?? 0) as int;
    final completed = (d['completedTasks'] ?? 0) as int;
    final inProgress = (d['inProgressTasks'] ?? 0) as int;
    final pending = (d['pendingTasks'] ?? 0) as int;
    final approved = (d['approvedTasks'] ?? 0) as int;
    final rejected = (d['rejectedTasks'] ?? 0) as int;
    final overdue = (d['overdueTasks'] ?? 0) as int;
    final awaiting = (completed - approved).clamp(0, total);
    final fraction = total > 0 ? completed / total : 0.0;
    final rate = (fraction * 100).round();
    final todayLabel = DateFormat('EEE, dd MMM yyyy').format(DateTime.now());
    final rep = scDailyReport;
    final grade = (!isAdminDashboard
            ? d['grade']?.toString()
            : rep?['grade']?.toString() ?? d['grade']?.toString()) ??
        'N/A';
    final avgScoreRaw = (!isAdminDashboard
            ? d['averageScore']
            : rep?['averageScore'] ?? d['averageScore']) ??
        0;
    final avgScore = avgScoreRaw.toInt();
    Color gradeColor = grade == 'A'
        ? Colors.greenAccent
        : grade == 'B'
        ? Colors.lightGreenAccent
        : grade == 'C'
        ? kWarningOrange
        : Colors.redAccent;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: const LinearGradient(colors: [kRailwayBlue, Colors.lightBlue],
                begin: Alignment.topLeft, end: Alignment.bottomRight),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(todayLabel,
                            style: const TextStyle(color: Colors.white70, fontSize: 13)),
                        const SizedBox(height: 6),
                        Text(isAdminDashboard ? 'Station Overview' : 'Station Cleaning',
                            style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Text('$total tasks scheduled today',
                            style: const TextStyle(color: Colors.white70, fontSize: 13)),
                      ],
                    ),
                  ),
                  Column(
                    children: [
                      Container(
                        width: 54,
                        height: 54,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
                        ),
                        child: Text(grade,
                            style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: gradeColor)),
                      ),
                      const SizedBox(height: 6),
                      Text('Grade',
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 11)),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: fraction,
                  minHeight: 10,
                  backgroundColor: Colors.white24,
                  valueColor: AlwaysStoppedAnimation(rate >= 80 ? Colors.greenAccent : kWarningOrange),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text('Shift Progress',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 12, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  Text('$completed/$total  •  $rate%  |  Score $avgScore%',
                      style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        Row(
          children: [
            _scStatCard('Pending', pending, kWarningOrange, Icons.schedule),
            const SizedBox(width: 8),
            _scStatCard('In Progress', inProgress, kRailwayBlue, Icons.cleaning_services),
            const SizedBox(width: 8),
            _scStatCard('Completed', completed, kSuccessGreen, Icons.check_circle),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _scStatCard('Overdue', overdue, kErrorRed, Icons.cancel),
            const SizedBox(width: 8),
            _scStatCard('Rejected', rejected, Colors.purple, Icons.block),
            const SizedBox(width: 8),
            if (isAdminDashboard)
              _scStatCard('Supervisors', (d['supervisorCount'] ?? 0) as int, Colors.teal, Icons.supervisor_account),
            if (!isAdminDashboard)
              _scStatCard('Workers', (d['workerPerformance'] as List? ?? []).length, Colors.teal, Icons.people),
          ],
        ),
        const SizedBox(height: 14),

        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 6, offset: Offset(0, 3))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Approval Status',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              const SizedBox(height: 6),
              const Text('Tasks awaiting railway approval',
                  style: TextStyle(color: Colors.black54, fontSize: 12)),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: _approvalPill(Icons.check_circle, 'Approved', approved, kSuccessGreen)),
                  const SizedBox(width: 8),
                  Expanded(child: _approvalPill(Icons.hourglass_top, 'Pending Approval', awaiting, kWarningOrange)),
                  const SizedBox(width: 8),
                  Expanded(child: _approvalPill(Icons.cancel, 'Rejected', rejected, kErrorRed)),
                ],
              ),
            ],
          ),
        ),

        if (isAdminDashboard) ...[
          const SizedBox(height: 14),
          _buildAdminSupervisorsSection(d),
        ],
      ],
    );
  }

  Widget _buildAdminSupervisorsSection(Map<String, dynamic> d) {
    final supervisors = (d['supervisors'] as List? ?? []).cast<Map<String, dynamic>>();

    String _shiftLabel(String? s) {
      switch (s) {
        case 'evening': return 'Evening';
        case 'night':    return 'Night';
        default:         return 'Morning';
      }
    }

    Color _shiftColor(String? s) {
      switch (s) {
        case 'evening': return kWarningOrange;
        case 'night':    return kErrorRed;
        default:         return kSuccessGreen;
      }
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 6, offset: Offset(0, 3))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('Supervisors',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              ),
              TextButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => SupervisorShiftAssignmentScreen(
                        stationId: d['stationId'] ?? '',
                        stationName: d['stationName'] ?? '',
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.manage_accounts, size: 18),
                label: const Text('Manage', style: TextStyle(fontSize: 13)),
              ),
            ],
          ),
          if (supervisors.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.supervisor_account, size: 44, color: Colors.grey[350]),
                    const SizedBox(height: 10),
                    const Text('No supervisors assigned to this station yet',
                        style: TextStyle(color: Colors.black45)),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => SupervisorShiftAssignmentScreen(
                              stationId: d['stationId'] ?? '',
                              stationName: d['stationName'] ?? '',
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.person_add),
                      label: const Text('Assign Supervisor'),
                    ),
                  ],
                ),
              ),
            )
          else
            ...supervisors.map((s) {
              final completed = (s['completedTasks'] ?? 0) as int;
              final total = (s['totalTasks'] ?? 0) as int;
              final pending = (s['pendingTasks'] ?? 0) as int;
              final fraction = total > 0 ? completed / total : 0.0;
              final shift = (s['shift'] as String?) ?? 'morning';
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => SupervisorShiftAssignmentScreen(
                            stationId: d['stationId'] ?? '',
                            stationName: d['stationName'] ?? '',
                          ),
                        ),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 20,
                            backgroundColor: _shiftColor(shift).withValues(alpha: 0.12),
                            child: Text(
                              (s['fullName'] ?? 'S').toString().substring(0, 1).toUpperCase(),
                              style: TextStyle(color: _shiftColor(shift), fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  (s['fullName'] as String?)?.trim().isNotEmpty == true ? s['fullName'] : 'Unnamed Supervisor',
                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if ((s['mobile'] as String?)?.isNotEmpty == true)
                                  Text(s['mobile'], style: const TextStyle(fontSize: 12, color: Colors.black45)),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: _shiftColor(shift).withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Text(_shiftLabel(shift),
                                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _shiftColor(shift))),
                                    ),
                                    const SizedBox(width: 8),
                                    Text('$completed/$total done',
                                        style: const TextStyle(fontSize: 12, color: Colors.black54)),
                                    const SizedBox(width: 8),
                                    if (pending > 0)
                                      Text('$pending pending',
                                          style: TextStyle(fontSize: 12, color: kWarningOrange)),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 4),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(3),
                            child: SizedBox(
                              width: 44,
                              child: LinearProgressIndicator(
                                value: fraction,
                                minHeight: 4,
                                backgroundColor: Colors.grey[200],
                                valueColor: AlwaysStoppedAnimation(
                                  fraction >= 0.8 ? kSuccessGreen : fraction >= 0.4 ? kWarningOrange : kErrorRed,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(Icons.chevron_right, color: Colors.grey[400], size: 20),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _scStatCard(String label, int count, Color color, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 6, offset: Offset(0, 3))],
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 6),
            Text('$count', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
            Text(label, style: TextStyle(fontSize: 10, color: Colors.grey[600])),
          ],
        ),
      ),
    );
  }

  Widget _approvalPill(IconData icon, String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 4),
          Text('$count', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
          Text(label, style: TextStyle(fontSize: 9, color: Colors.grey[700])),
        ],
      ),
    );
  }


  Widget _scoreCardPremises({
    required String title,
    required Color accent,
    required String subtitle,
    required Color cardBg,
    required Color softBorder,
    required IconData iconInner,
  }) {
    final List<Map<String, String>> grades = [
      {'grade': '>90', 'pct': '${premisesCleaningStats['gradeAbove90Pct'] ?? '0.0'}%'},
      {'grade': '81-90', 'pct': '${premisesCleaningStats['grade81to90Pct'] ?? '0.0'}%'},
      {'grade': '71-80', 'pct': '${premisesCleaningStats['grade71to80Pct'] ?? '0.0'}%'},
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: softBorder),
      ),
      child: isStatsLoading
          ? Center(child: CircularProgressIndicator())
          : Row(
        children: [
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 15)),
                  const SizedBox(height: 6),
                  Text(subtitle,
                      style: const TextStyle(color: Colors.black54, fontSize: 13))
                ]),
          ),

          Row(
            children: grades
                .map((g) => Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Container(
                width: 50,
                height: 60,
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: accent.withOpacity(0.4)),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      g['grade']!,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: accent),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      g['pct']!,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87),
                    ),
                  ],
                ),
              ),
            ))
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _scoreCardCoach({
    required String title,
    required Color accent,
    required String subtitle,
    required Color cardBg,
    required Color softBorder,
    required IconData iconInner,
  }) {
    final List<Map<String, String>> grades = [
      {'grade': 'A', 'pct': '${coachCleaningStats['gradeAPercent'] ?? '0.0'}%'},
      {'grade': 'B', 'pct': '${coachCleaningStats['gradeBPercent'] ?? '0.0'}%'},
      {'grade': 'C', 'pct': '${coachCleaningStats['gradeCPercent'] ?? '0.0'}%'},
      {'grade': 'D', 'pct': '${coachCleaningStats['gradeDPercent'] ?? '0.0'}%'},
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: softBorder),
      ),
      child: isStatsLoading
          ? Center(child: CircularProgressIndicator())
          : Row(
        children: [
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 15)),
                  const SizedBox(height: 6),
                  Text(subtitle,
                      style: const TextStyle(color: Colors.black54, fontSize: 13))
                ]),
          ),
          Row(
            children: grades
                .map((g) => Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Container(
                width: 50,
                height: 60,
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: accent.withOpacity(0.4)),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      g['grade']!,
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: accent),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      g['pct']!,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87),
                    ),
                  ],
                ),
              ),
            ))
                .toList(),
          ),
        ],
      ),
    );
  }




  Widget _buildFormsCard(
      String title, {
        required int pending,
        required int approved,
        required int rejected,
        required int progress,
        required int autoApproved,
        required int locked,
      }) {
    return Padding(
      padding: const EdgeInsets.all(5.0),
      child: Container(
        width: 350,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 3))
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 10),
            SizedBox(
              height: 200,
              child: isChartLoading
                  ? Center(child: CircularProgressIndicator())
                  : DonutChart(
                midText: title,
                pending: pending,
                approved: approved,
                rejected: rejected,
                progress: progress,
                autoApproved: autoApproved,
                locked: locked,
              ),
            ),
            const SizedBox(height: 20),
            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                LegendItem(color: Colors.green, label: "Pending"),
                SizedBox(width: 16),
                LegendItem(color: Colors.orange, label: "Approved"),
                SizedBox(width: 16),
                LegendItem(color: Colors.purple, label: "Rejected"),
              ],
            ),
            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                LegendItem(color: Colors.blue, label: "Progress"),
                SizedBox(width: 16),
                LegendItem(color: Colors.grey, label: "Auto-Approved"),
                SizedBox(width: 16),
                LegendItem(color: Colors.red, label: "Locked"),
              ],
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  Widget _buildDropdown({
    required String current,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12,vertical: 10),
      decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFE6E6F0)),
          color: Colors.white),
      child: DropdownButtonFormField<String>(
        decoration: const InputDecoration(
            isDense: true, border: InputBorder.none, contentPadding: EdgeInsets.zero),
        value: items.contains(current) ? current : null,
        onChanged: onChanged,
        items: items
            .map((e) => DropdownMenuItem<String>(
          value: e,
          child: Text(e, style: const TextStyle(fontSize: 13)),
        ))
            .toList(),
      ),
    );
  }

  String _formatContractType(String type) {
    switch (type) {
      case 'station_cleaning':
        return 'Station Cleaning';
      case 'coach_cleaning':
        return 'Coach Cleaning';
      case 'premises_cleaning':
        return 'Premises Cleaning';
      case 'cts':
        return 'CTS';
      case 'obhs':
        return 'OBHS';
      default:
        return type;
    }
  }
}

class _PassengerFeedbackChooser extends StatelessWidget {
  final String stationId;
  final String stationName;
  const _PassengerFeedbackChooser({required this.stationId, required this.stationName});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Passenger Feedback - $stationName', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: kRailwayBlue,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: ListView(
        children: [
          const SizedBox(height: 8),
          ListTile(
            leading: const CircleAvatar(backgroundColor: Colors.green, child: Icon(Icons.edit_note, color: Colors.white)),
            title: const Text('Submit Passenger Feedback'),
            subtitle: const Text('Ask a passenger, record PNR + ratings (min 3 categories)'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PassengerFeedbackFormScreen(
              stationId: stationId,
              stationName: stationName,
            ))),
          ),
          const Divider(),
          ListTile(
            leading: const CircleAvatar(backgroundColor: Colors.teal, child: Icon(Icons.list_alt, color: Colors.white)),
            title: const Text('View Feedback'),
            subtitle: const Text('Browse feedback recorded against PNRs'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PassengerFeedbackListScreen(
              stationId: stationId,
              stationName: stationName,
            ))),
          ),
          const Divider(),
          ListTile(
            leading: const CircleAvatar(backgroundColor: Colors.indigo, child: Icon(Icons.qr_code_2, color: Colors.white)),
            title: const Text('Feedback QR Code'),
            subtitle: const Text('Display the passenger feedback QR for scanning'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => FeedbackQrScreen(
              stationId: stationId,
              stationName: stationName,
            ))),
          ),
          const Divider(),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}