import 'package:crm_train/utills/app_colors.dart';
import 'package:crm_train/controller/contractor_nav_controller.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:get/get.dart';
import '../../../model/status_model.dart';
import '../../../providers/auth_provider.dart';
import '../../../services/api_services.dart';
import '../../../services/dashboard_counts_service.dart';
import '../../../services/draft_storage_service.dart';
import '../../onboarding_screens/login_screen.dart';
import '../alert/common_alert_screen.dart';
import '../entities/common_entity_managment_screen.dart';
import '../entities/entity_register_form.dart';
import '../profile/common_profile_screen.dart';
import '../trains/common_train_screen.dart';
import '../trains/train_from_screen.dart';
import '../users/common_user_management_screen.dart';
import '../contracts/common_contracts_screen.dart';
import '../divisions/division_management_screen.dart';
import '../business_activities/business_activities_screen.dart';
import '../audit/audit_log_screen.dart';
import '../billing/billing_dashboard_screen.dart';
import '../billing/contract_billing_config_screen.dart';
import '../cleaning_forms/cleaning_form_dashboard.dart';
import '../../station_cleaning_screens/station_cleaning_runs_list_screen.dart';
import '../../station_cleaning_complete/station_cleaning_main_screen.dart';
import '../station_management/station_dashboard_screen.dart';
import '../../common_workers/worker_pest_control_screen.dart';
import '../../common_workers/worker_machine_screen.dart';
import '../../common_workers/worker_garbage_screen.dart';
import '../report/common_report_screen.dart';
import '../ratings/admin_ratings_screen.dart';
import '../widgets/DonutChart.dart';
import '../widgets/QuickActionCard.dart';
import '../widgets/filter_section.dart';
import '../widgets/indicator_color.dart';
import '../widgets/status_tile.dart';
import '../station_management/area_list_screen.dart';
import '../station_management/task_generation_screen.dart';
import '../../station_cleaning/shift_summary_approval_screen.dart';
import '../../station_cleaning/attendance/station_supervisor_attendance_screen.dart';
import '../../station_cleaning/reporting/report_list_screen.dart';
import '../station_management/area_performance_dashboard.dart';
import '../station_management/supervisor_shift_assignment_screen.dart';
import 'package:crm_train/view/common_contractor/form_screen/forms/new_coach_form.dart';
import 'package:crm_train/view/common_contractor/form_screen/forms/new_premises_form.dart';
import 'package:crm_train/view/common_contractor/form_screen/forms/cts_form_screen_v2.dart';
import 'package:crm_train/view/common_railways/forms/common_form_screen.dart';
import 'package:crm_train/view/obhs_screens/obhs_runs_list_screen.dart';
import 'package:crm_train/view/obhs_screens/obhs_create_run_screen.dart';
import 'package:crm_train/view/obhs_screens/obhs_attendance_list_screen.dart';
import 'package:crm_train/view/obhs_screens/obhs_water_checks_screen.dart';
import 'package:crm_train/view/obhs_screens/obhs_safety_checks_screen.dart';
import 'package:crm_train/view/obhs_screens/obhs_petty_repairs_screen.dart';
import 'package:crm_train/view/obhs_screens/obhs_ratings_screen.dart';
import 'package:crm_train/view/obhs_screens/obhs_analytics_screen.dart';

class CommonDashboard extends StatefulWidget {
  CommonDashboard({
    super.key,
  });

  @override
  State<CommonDashboard> createState() => _CommonDashboardState();
}

class _CommonDashboardState extends State<CommonDashboard> {
  bool isStatsLoading = true;

  String? selectedZone;
  String? selectedDivision;
  String? selectedDepot;

  Map<String, dynamic> dashboardData = {};

  int railwayEmployees = 0;
  int contractorEmployees = 0;
  int activeContracts = 0;
  int totalFormsProcessed = 0;
  int numberOfZones = 0;
  int numberOfDivisions = 0;
  int numberOfDepots = 0;

  int totalEntities = 0;
  int approvedEntities = 0;
  int pendingEntities = 0;
  int draftEntities = 0;

  int totalUsers = 0;
  int approvedUsers = 0;
  int pendingUsers = 0;
  int draftUsers = 0;
  int rejectedUsers = 0;
  int railwayStaff = 0;
  int contractorStaff = 0;

  int totalTrains = 0;
  int activeTrains = 0;
  int inactiveTrains = 0;
  int draftTrains = 0;

  int totalForms = 0;
  int pendingForms = 0;
  int manpowerApprovedForms = 0;
  int rejectedForms = 0;
  int scoringProgressForms = 0;
  int autoApprovedForms = 0;
  int lockedForms = 0;

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

  int scTotalStations = 0;
  int scTotalAreas = 0;
  int scTasksToday = 0;
  int scTasksPending = 0;
  int scTasksCompleted = 0;
  int scTasksInProgress = 0;
  int scPendingShiftSummaries = 0;

  List<StatusModel> get statusList {
    return [
      StatusModel(pendingForms, 'Pending'),
      StatusModel(manpowerApprovedForms, 'Approved'),
      StatusModel(rejectedForms, 'Rejected'),
      StatusModel(scoringProgressForms, 'Scoring in progress'),
      StatusModel(autoApprovedForms, 'Auto-Approved'),
      StatusModel(lockedForms, 'Locked'),
    ];
  }

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
    {'title': 'Approved', 'value': ctsManpowerApproved.toString()},
    {'title': 'Rejected', 'value': ctsRejected.toString()},
    {'title': 'Scoring Progress', 'value': ctsScoringProgress.toString()},
    {'title': 'Auto-Approved', 'value': ctsAutoApproved.toString()},
    {'title': 'Locked', 'value': ctsLocked.toString()},
  ];


@override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final user = Provider.of<AuthProvider>(context, listen: false).currentUser;
      setState(() {
        selectedZone = user?.zone;
        selectedDivision = user?.division;
        selectedDepot = user?.depot;
      });
      _loadDashboardStats();
    });
  }

  Future<void> _loadDashboardStats() async {
    try {
      final user = Provider.of<AuthProvider>(context, listen: false).currentUser;
      if (user == null) return;

      setState(() => isStatsLoading = true);

      final results = await Future.wait([
        FirebaseCountService.getUniqueZoneCount(),
        FirebaseCountService.getUniqueDivisionCount(zone: selectedZone),
        FirebaseCountService.getUniqueDepotCount(
          zone: selectedZone,
          division: selectedDivision,
        ),
        FirebaseCountService.getRailwayUserCount(
          zone: selectedZone,
          division: selectedDivision,
          depot: selectedDepot,
        ),
        FirebaseCountService.getContractorUserCount(
          zone: selectedZone,
          division: selectedDivision,
          depot: selectedDepot,
        ),
        FirebaseCountService.getTotalActiveContracts(
          zone: selectedZone,
          division: selectedDivision,
          depot: selectedDepot,
        ),
        FirebaseCountService.getTotalFormsProcessed(
          zone: selectedZone,
          division: selectedDivision,
        ),
        FirebaseCountService.getTotalEntityRegistered(),
      ]);

      numberOfZones = results[0];
      numberOfDivisions = results[1];
      numberOfDepots = results[2];
      railwayEmployees = results[3];
      contractorEmployees = results[4];
      activeContracts = results[5];
      totalFormsProcessed = results[6];
      totalEntities = results[7];

      final stats = await ApiService.getDashboardStats(
        zone: selectedZone,
        division: selectedDivision,
      );

      final coachStats = await FirebaseCountService.getFormStatusCounts(
        formType: 'coach',
        zone: selectedZone,
        division: selectedDivision,
      );

      final premisesStats = await FirebaseCountService.getFormStatusCounts(
        formType: 'premises',
        zone: selectedZone,
        division: selectedDivision,
      );

      final ctsStats = await FirebaseCountService.getFormStatusCounts(
        formType: 'cts',
        zone: selectedZone,
        division: selectedDivision,
      );

      final userStats = await ApiService.getUserStats(
        zone: selectedZone,
        division: selectedDivision,
        depot: selectedDepot,
      );

      final trainStats = await ApiService.getTrainStats(
        zone: selectedZone,
        division: selectedDivision,
        depot: selectedDepot,
      );

      setState(() {
        dashboardData = stats;

        final systemOverview = stats['systemOverview'] ?? {};
        if (railwayEmployees == 0) railwayEmployees = systemOverview['railwayEmployees'] ?? 0;
        if (contractorEmployees == 0) contractorEmployees = systemOverview['contractorEmployees'] ?? 0;
        if (totalEntities == 0) totalEntities = systemOverview['totalRegisteredEntities'] ?? 0;
        if (activeContracts == 0) activeContracts = systemOverview['activeContracts'] ?? 0;
        if (totalFormsProcessed == 0) totalFormsProcessed = systemOverview['totalFormsProcessed'] ?? 0;

        final entityOverview = stats['entityOverview'] ?? {};
        approvedEntities = entityOverview['approved'] ?? 0;
        pendingEntities = entityOverview['pending'] ?? 0;

        final userStatsData = userStats['data'] ?? {};
        totalUsers = userStatsData['totalRegistered'] ?? 0;
        approvedUsers = userStatsData['approvedUsers'] ?? 0;
        pendingUsers = userStatsData['pendingApproval'] ?? 0;
        rejectedUsers = userStatsData['rejectedUsers'] ?? 0;
        railwayStaff = userStatsData['railwayStaff'] ?? 0;
        contractorStaff = userStatsData['contractorStaff'] ?? 0;

        final trainStatsData = trainStats['data'] ?? {};
        totalTrains = trainStatsData['totalTrains'] ?? 0;
        activeTrains = trainStatsData['activeTrains'] ?? 0;
        inactiveTrains = trainStatsData['inactiveTrains'] ?? 0;

        final formsOverview = stats['formsOverview'] ?? {};
        totalForms = formsOverview['total'] ?? 0;
        pendingForms = formsOverview['pending'] ?? 0;
        manpowerApprovedForms = formsOverview['manpowerApproved'] ?? 0;
        rejectedForms = formsOverview['rejected'] ?? 0;
        scoringProgressForms = formsOverview['scoringProgress'] ?? 0;
        autoApprovedForms = formsOverview['autoApproved'] ?? 0;
        lockedForms = formsOverview['locked'] ?? 0;

        coachTotal = coachStats['total'] ?? 0;
        coachPending = coachStats['pending'] ?? 0;
        coachManpowerApproved = coachStats['manpowerApproved'] ?? 0;
        coachRejected = coachStats['rejected'] ?? 0;
        coachScoringProgress = coachStats['scoringProgress'] ?? 0;
        coachAutoApproved = coachStats['autoApproved'] ?? 0;
        coachLocked = coachStats['locked'] ?? 0;

        premisesTotal = premisesStats['total'] ?? 0;
        premisesPending = premisesStats['pending'] ?? 0;
        premisesManpowerApproved = premisesStats['manpowerApproved'] ?? 0;
        premisesRejected = premisesStats['rejected'] ?? 0;
        premisesScoringProgress = premisesStats['scoringProgress'] ?? 0;
        premisesAutoApproved = premisesStats['autoApproved'] ?? 0;
        premisesLocked = premisesStats['locked'] ?? 0;

        ctsTotal = ctsStats['total'] ?? 0;
        ctsPending = ctsStats['pending'] ?? 0;
        ctsManpowerApproved = ctsStats['manpowerApproved'] ?? 0;
        ctsRejected = ctsStats['rejected'] ?? 0;
        ctsScoringProgress = ctsStats['scoringProgress'] ?? 0;
        ctsAutoApproved = ctsStats['autoApproved'] ?? 0;
        ctsLocked = ctsStats['locked'] ?? 0;

        final scOverview = stats['stationCleaning'] ?? {};
        scTotalStations = scOverview['totalStations'] ?? 0;
        scTotalAreas = scOverview['totalAreas'] ?? 0;
        scTasksToday = scOverview['tasksToday'] ?? 0;
        scTasksPending = scOverview['tasksPending'] ?? 0;
        scTasksCompleted = scOverview['tasksCompleted'] ?? 0;
        scTasksInProgress = scOverview['tasksInProgress'] ?? 0;
        scPendingShiftSummaries = scOverview['pendingShiftSummaries'] ?? 0;

        isStatsLoading = false;
      });

      await _loadLocalDraftCounts();
    } catch (e) {
      print('Error loading dashboard stats: $e');
      setState(() => isStatsLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load dashboard: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _loadLocalDraftCounts() async {
    try {
      final user = Provider.of<AuthProvider>(context, listen: false).currentUser;
      if (user?.uid == null) {
        return;
      }

      final userDrafts = await DraftStorageService.getUserDrafts(user!.uid!);
      final trainDrafts = await DraftStorageService.getTrainDrafts(user.uid!);
      final entityDrafts = await DraftStorageService.getEntityDrafts(user.uid!);

      print('Loaded drafts - Users: ${userDrafts.length}, Trains: ${trainDrafts.length}, Entities: ${entityDrafts.length}');

      setState(() {
        draftUsers = userDrafts.length;
        draftTrains = trainDrafts.length;
        draftEntities = entityDrafts.length;
      });

      print('Draft counts updated - Users: $draftUsers, Trains: $draftTrains, Entities: $draftEntities');
    } catch (e) {
      print('Error loading local draft counts: $e');
    }
  }



  List<Map<String, dynamic>> get kpiData => [
    {'title': 'No. of Zones', 'value': numberOfZones.toString()},
    {'title': 'No. of Divisions', 'value': numberOfDivisions.toString()},
    {'title': 'No. of Depot', 'value': numberOfDepots.toString()},
    {'title': 'Railway Employee', 'value': railwayEmployees.toString()},
    {'title': 'Contractor Employees', 'value': contractorEmployees.toString()},
    {'title': 'Total Registered Entities', 'value': totalEntities.toString()},
    {'title': 'Active Contracts (Contract IDs)', 'value': activeContracts.toString()},
    {'title': 'Total Forms Processed', 'value': totalFormsProcessed.toString()},
  ];

  List<Map<String, dynamic>> get trainKpi => [
    {'title': 'Total Registered Trains', 'value': totalTrains.toString()},
    {'title': 'Active Trains', 'value': activeTrains.toString()},
    {'title': 'Inactive Trains', 'value': inactiveTrains.toString()},
    {'title': 'Draft Trains', 'value': draftTrains.toString()},
  ];

  List<Map<String, dynamic>> get userKpi => [
    {'title': 'Total Registered Users', 'value': totalUsers.toString()},
    {'title': 'Approved Users', 'value': approvedUsers.toString()},
    {'title': 'Pending Approval', 'value': pendingUsers.toString()},
    {'title': 'Draft Users', 'value': draftUsers.toString()},
  ];

  List<Map<String, dynamic>> get entityKpi => [
    {'title': 'Total Registered Entity', 'value': totalEntities.toString()},
    {'title': 'Approved Entity', 'value': approvedEntities.toString()},
    {'title': 'Pending Approval', 'value': pendingEntities.toString()},
    {'title': 'Draft Entity', 'value': draftEntities.toString()},
  ];




  List<Map<String, dynamic>> _getQuickActions(String? userRole) {
    final defaultActions = [
      {
        "icon": Icons.note_add_sharp,
        "title": "Review Forms",
        "subtitle": "$pendingForms pending",
        "color": Colors.blue,
        "roles": ["Company Master", "Contractor Admin", "Railway Master", "Railway Admin", "Railway Supervisor"]
      },
      {
        "icon": Icons.event_note_sharp,
        "title": "Pending Scorecards",
        "subtitle": "$scoringProgressForms forms ready",
        "color": Colors.purple,
        "roles": ["Company Master", "Contractor Admin", "Railway Supervisor"]
      },
      {
        "icon": Icons.train,
        "title": "Add New Train",
        "subtitle": "Register Train",
        "color": Colors.green,
        "roles": ["Company Master", "Contractor Admin", "Railway Master"]
      },
      {
        "icon": Icons.location_city_outlined,
        "title": "Add New Entity",
        "subtitle": "Entity Registration",
        "color": Colors.red,
        "roles": ["Super Admin", "Company Master", "Railway Master"]
      },
    ];




    return defaultActions
        .where((action) => (action['roles'] as List<String>).contains(userRole))
        .toList();
  }

  List<Map<String, dynamic>> _getSidebarMenuItems(String? userRole, String? contractType) {
    List<Map<String, dynamic>> items = [
      {
        "icon": Icons.dashboard_rounded,
        "title": "Dashboard",
        "route": null,
        "roles": ["Super Admin", "Company Master", "Contractor Admin", "Railway Master", "Railway Admin", "Railway Supervisor"]
      },
      {
        "icon": Icons.admin_panel_settings,
        "title": "Masters",
        "roles": ["Super Admin", "Company Master", "Contractor Admin", "Railway Master", "Railway Admin"],
        "children": [
          {"title": "User Management", "route": "users"},
          {"title": "Entity Management", "route": "entities", "roles": ["Super Admin", "Company Master", "Railway Master", "Railway Admin"]},
          {"title": "Contract Management", "route": "contracts", "roles": ["Super Admin", "Company Master", "Railway Master", "Railway Admin"]},
          {"title": "Station Management", "route": "station_management_master"},
          {"title": "Train Management", "route": "trains"},
          {"title": "Division Management", "route": "divisions", "roles": ["Super Admin", "Company Master", "Railway Master", "Railway Admin"]},
          {"title": "Billing Rules", "route": "billing_rules"},
        ]
      },
      {
        "icon": Icons.cleaning_services,
        "title": "Operations",
        "roles": ["Super Admin", "Company Master", "Contractor Admin", "Railway Master", "Railway Admin", "Railway Supervisor"],
        "children": [
          {"title": "Coach Cleaning", "route": "coach_cleaning", "contractTypes": ["coach"]},
          {"title": "Premise Cleaning", "route": "premise_cleaning", "contractTypes": ["premises"]},
          {"title": "CTS Forms", "route": "cts_cleaning", "contractTypes": ["cts"]},
        ]
      },
      {
        "icon": Icons.cleaning_services_rounded,
        "title": "Station Cleaning",
        "contractTypes": ["station_cleaning"],
        "roles": ["Super Admin", "Company Master", "Contractor Admin", "Railway Master", "Railway Admin", "Railway Supervisor", "Railway Inspector"],
        "children": [
          {"title": "Module Hub", "route": "sc_main", "roles": ["Super Admin", "Company Master", "Contractor Admin", "Railway Master", "Railway Admin", "Railway Supervisor", "Railway Inspector"]},
          {"title": "Area Management", "route": "sc_areas", "roles": ["Super Admin", "Company Master", "Contractor Admin", "Railway Master", "Railway Admin"]},
          {"title": "Generate Tasks", "route": "sc_generate_tasks", "roles": ["Super Admin", "Company Master", "Contractor Admin", "Railway Master", "Railway Admin", "Railway Supervisor"]},
          {"title": "Shift Summary Approval", "route": "sc_shift_summary_approval", "roles": ["Super Admin", "Admin", "Railway Master", "Railway Admin", "Railway Supervisor", "Railway Inspector"]},
          {"title": "Supervisor Attendance", "route": "sc_supervisor_attendance", "roles": ["Super Admin", "Company Master", "Contractor Admin", "Railway Master", "Railway Admin", "Railway Supervisor"]},
          {"title": "Supervisor Shifts", "route": "sc_supervisor_shifts", "roles": ["Super Admin", "Company Master", "Contractor Admin", "Railway Master", "Railway Admin"]},
        ]
      },
      {
        "icon": Icons.train,
        "title": "OBHS Operations",
        "roles": ["Super Admin", "Company Master", "Contractor Admin", "Railway Master", "Railway Admin", "Railway Supervisor"],
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
        "icon": Icons.analytics,
        "title": "Reports",
        "roles": ["Super Admin", "Company Master", "Contractor Admin", "Railway Master", "Railway Admin", "Railway Supervisor"],
        "children": [
          {"title": "Coach Reports", "route": "coach_reports", "contractTypes": ["coach"]},
          {"title": "Premise Reports", "route": "premise_reports", "contractTypes": ["premises"]},
          {"title": "CTS Reports", "route": "cts_reports", "contractTypes": ["cts"]},
          {"title": "Station Reports", "route": "station_reports", "contractTypes": ["station_cleaning"]},
        ]
      },
      {
        "icon": Icons.star_outline,
        "title": "Ratings",
        "route": "ratings",
        "roles": ["Super Admin", "Company Master", "Contractor Admin", "Railway Master", "Railway Admin", "Railway Supervisor"]
      },
      {
        "icon": Icons.security,
        "title": "Audit & Compliance",
        "roles": ["Super Admin", "Company Master", "Contractor Admin", "Railway Master", "Railway Admin"],
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

  void _handleSidebarNavigation(String? route, BuildContext context, String? userRole) {
    if (route == null) {
      Navigator.pop(context); // Close drawer
      return;
    }

    Navigator.pop(context); // Always close drawer on selection

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
        Navigator.push(context, MaterialPageRoute(builder: (context) {
          return NewCoachFormScreen();
        }));
        break;
      case "premise_cleaning":
        Navigator.push(context, MaterialPageRoute(builder: (context) {
          return PremisesCleaningForm();
        }));
        break;
      case "cts_cleaning":
        Navigator.push(context, MaterialPageRoute(builder: (context) {
          return NewCTSFormScreen();
        }));
        break;
      case "station_cleaning":
        Navigator.push(context, MaterialPageRoute(builder: (context) => const StationDashboardScreen()));
        break;
      case "station_cleaning_runs":
        Navigator.push(context, MaterialPageRoute(builder: (context) => const StationCleaningRunsListScreen()));
        break;
      case "pest_control":
        Navigator.push(context, MaterialPageRoute(builder: (context) => const WorkerPestControlScreen()));
        break;
      case "machines":
        Navigator.push(context, MaterialPageRoute(builder: (context) => const WorkerMachineScreen()));
        break;
      case "garbage":
        Navigator.push(context, MaterialPageRoute(builder: (context) => const WorkerGarbageScreen()));
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
case "station_reports": {
          final authProvider = Provider.of<AuthProvider>(context, listen: false);
          final user = authProvider.currentUser;
          final stationId = (user?.stationId != null && user!.stationId!.isNotEmpty)
              ? user.stationId
              : (user?.stations.isNotEmpty == true ? user!.stations.first : null);
          if (stationId == null || stationId.isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('No station assigned. Please contact admin or select a station.'),
                backgroundColor: Colors.orange,
              ),
            );
            break;
          }
          Navigator.push(context, MaterialPageRoute(builder: (context) => ReportListScreen(
            stationId: stationId,
            stationName: '',
            role: user?.role ?? '',
          )));
          break;
        }
      case "divisions":
        Navigator.push(context, MaterialPageRoute(builder: (context) => const DivisionManagementScreen()));
        break;
      case "billing_rules":
      case "billing":
        Navigator.push(context, MaterialPageRoute(builder: (context) => const BillingDashboardScreen()));
        break;
      case "ratings":
        Navigator.push(context, MaterialPageRoute(builder: (context) => const AdminRatingsScreen()));
        break;
      case "audit_logs":
        Navigator.push(context, MaterialPageRoute(builder: (context) => const AuditLogScreen()));
        break;
      case "activity_logs":
        Navigator.push(context, MaterialPageRoute(builder: (context) => const BusinessActivitiesScreen()));
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
      case "sc_main":
        Navigator.push(context, MaterialPageRoute(builder: (context) => const StationCleaningMainScreen()));
        break;
      case "sc_areas":
        Navigator.push(context, MaterialPageRoute(builder: (context) => const AreaListScreen()));
        break;
      case "sc_generate_tasks":
        Navigator.push(context, MaterialPageRoute(builder: (context) => const TaskGenerationScreen()));
        break;
      case "sc_shift_summary_approval": {
        final authProvider = Provider.of<AuthProvider>(context, listen: false);
        final user = authProvider.currentUser;
        final stationId = (user?.stationId != null && user!.stationId!.isNotEmpty)
            ? user.stationId
            : (user?.stations.isNotEmpty == true ? user!.stations.first : null);
        Navigator.push(context, MaterialPageRoute(builder: (context) => ShiftSummaryApprovalScreen(stationId: stationId)));
        break;
      }
      case "sc_supervisor_attendance": {
        final authProvider = Provider.of<AuthProvider>(context, listen: false);
        final user = authProvider.currentUser;
        final stationId = (user?.stationId != null && user!.stationId!.isNotEmpty)
            ? user.stationId
            : (user?.stations.isNotEmpty == true ? user!.stations.first : null);
        Navigator.push(context, MaterialPageRoute(builder: (context) => StationSupervisorAttendanceScreen(
          stationId: stationId ?? '',
          stationName: '',
        )));
        break;
      }
      case "sc_supervisor_shifts": {
        final authProvider = Provider.of<AuthProvider>(context, listen: false);
        final user = authProvider.currentUser;
        final stationId = (user?.stationId != null && user!.stationId!.isNotEmpty)
            ? user.stationId
            : (user?.stations.isNotEmpty == true ? user!.stations.first : null);
        Navigator.push(context, MaterialPageRoute(builder: (context) => SupervisorShiftAssignmentScreen(
          stationId: stationId ?? '',
          stationName: '',
        )));
        break;
      }
      case "sc_performance":
        Navigator.push(context, MaterialPageRoute(builder: (context) => const AreaPerformanceDashboard()));
        break;
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = Provider.of<AuthProvider>(context).currentUser;
    final quickActions = _getQuickActions(user?.role);
    final sidebarMenuItems = _getSidebarMenuItems(user?.role, user?.contractType ?? user?.domain);

    final parts = [
      if (user?.zone != null && user!.zone!.isNotEmpty) user.zone!,
      if (user?.division != null && user!.division!.isNotEmpty) user.division!,
      if (user?.depot != null && user!.depot!.isNotEmpty) user.depot!,
    ];
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
          IconButton(
              onPressed: () {
                Navigator.push(context,
                    MaterialPageRoute(builder: (context) => CommonProfileScreen()));
              },
              icon: CircleAvatar(
                  backgroundColor: Colors.white,
                  radius: 16,
                  child: Icon(Icons.person, color: kRailwayBlue))),
          IconButton(
              onPressed: () {
                Navigator.push(context,
                    MaterialPageRoute(builder: (context) => CommonAlertScreen()));
              },
              icon: Icon(Icons.notifications, color: Colors.white)),
          IconButton(
              onPressed: () async{
                final authProvider = Provider.of<AuthProvider>(context, listen: false);
                await authProvider.logout();
                Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (context) => const LoginScreen()),
                      (route) => false,
                );
              },
              icon: Icon(Icons.logout, color: Colors.white)),
        ],
      ),
      backgroundColor: Colors.grey[50],
      drawer: Drawer(
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
      ),
      body: SafeArea(
          child: RefreshIndicator(
            onRefresh: _loadDashboardStats,
            color: kRailwayBlue,
            child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
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
                      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(Icons.home_work_outlined),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Welcome, ${user?.fullName ?? 'User'}",
                            style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: Colors.black),
                          ),
                        if (parts.isNotEmpty)
            Text(parts.join(" | "))
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              if (user?.role != 'Railway Supervisor')
                FilterSection(
                  userRole: user?.role,
                  fixedZone: user?.role == 'Super Admin' ? null : user?.zone,
                  fixedDivision: user?.role == 'Super Admin' ? null : user?.division,
                  fixedDepot: user?.role == 'Super Admin' ? null : user?.depot,
                  onChanged: (zone, division, depot) {
                    final isSuperAdmin = user?.role == 'Super Admin';
                    setState(() {
                      selectedZone = (isSuperAdmin ? zone : (zone ?? user?.zone));
                      selectedDivision = (isSuperAdmin ? division : (division ?? user?.division));
                      selectedDepot = (isSuperAdmin ? depot : (depot ?? user?.depot));
                    });
                    _loadDashboardStats();
                  },
                  onClear: () {
                    final isSuperAdmin = user?.role == 'Super Admin';
                    setState(() {
                      selectedZone = isSuperAdmin ? null : user?.zone;
                      selectedDivision = isSuperAdmin ? null : user?.division;
                      selectedDepot = isSuperAdmin ? null : user?.depot;
                    });
                    _loadDashboardStats();
                  },
                ),

        Visibility(
          visible: user?.role != 'Railway Supervisor',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),

              Text(
                "System Overview",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),

              const SizedBox(height: 10),

              _buildGrid(() {
                List<Map<String, dynamic>> filtered = List.from(kpiData);

                if (user?.role == "Company Master") {
                  return filtered;
                }

                if (user?.role == "Railway Master") {
                  filtered.removeWhere((item) => item["title"] == "No. of Zones");
                } else if (user?.role == "Railway Admin") {
                  filtered.removeWhere((item) =>
                  item["title"] == "No. of Zones" ||
                      item["title"] == "No. of Divisions");
                } else if (user?.role == "Railway Supervisor") {
                  filtered.removeWhere((item) =>
                  item["title"] == "No. of Zones" ||
                      item["title"] == "No. of Divisions" ||
                      item["title"] == "No. of Depot");
                }

                return filtered;
              }())
            ],
          ),
        ),


        const SizedBox(height: 20),


              Text("Forms Overview",
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87)),
              const SizedBox(height: 10),

              _buildFormsCardList(),

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


              const SizedBox(height: 20),

              Text("Station Cleaning",
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
                    children: [
                      StatusTile(number: scTotalStations, label: 'Stations'),
                      const SizedBox(width: 12),
                      StatusTile(number: scTotalAreas, label: 'Areas'),
                      const SizedBox(width: 12),
                      StatusTile(number: scTasksToday, label: 'Tasks Today'),
                      const SizedBox(width: 12),
                      StatusTile(number: scTasksPending, label: 'Pending Tasks'),
                      const SizedBox(width: 12),
                      StatusTile(number: scTasksCompleted, label: 'Completed'),
                      const SizedBox(width: 12),
                      StatusTile(number: scTasksInProgress, label: 'In Progress'),
                      const SizedBox(width: 12),
                      StatusTile(number: scPendingShiftSummaries, label: 'Shift Summary Pending'),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),



              if (user?.role != 'Railway Supervisor')
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "User Overview",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),

                    const SizedBox(height: 10),

                    _buildGrid(userKpi),

                    const SizedBox(height: 10),

                    _buildActionButton("Manage Users", Icons.person, Colors.blue, () {
                      Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (context) => CommonUserManagementScreen()));
                    }),
                    const SizedBox(height: 20),
                  ],
                ),





              Text("Train Overview",
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87)),
              const SizedBox(height: 10),
              _buildGrid(trainKpi),

              const SizedBox(height: 10),
              _buildActionButton("Manage Trains", Icons.train, Colors.blue, () {
                Navigator.push(context,
                    MaterialPageRoute(builder: (context) => CommonTrainScreen()));
              }),

              const SizedBox(height: 20),

              if (user?.role != 'Railway Supervisor' && user?.role != 'Contractor Admin')
              Column(
                crossAxisAlignment:CrossAxisAlignment.start,
                children: [
                  Text("Entity Overview",
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87)),

              const SizedBox(height: 10),
              _buildGrid(entityKpi),

              const SizedBox(height: 10),

              if (user?.role != "Railway Supervisor" && user?.role != "Contractor Admin")
                _buildActionButton("Manage Entity",
                    Icons.location_city_outlined, Colors.blue, () {
                      Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (context) => CommonEntityManagmentScreen()));
                    }),

              const SizedBox(height: 20),

                ],
              ),
              _buildQuickActions(quickActions, context),

              const SizedBox(height: 20),

            ],
          ),
        ),
      ),
        )
    );
  }


  Widget _buildGrid(List<Map<String, dynamic>> list) {
    if (isStatsLoading) {
      return SizedBox(
        height: 200,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              CircularProgressIndicator(strokeWidth: 2),
              SizedBox(height: 12),
              Text(
                'Loading data...',
                style: TextStyle(color: Colors.grey, fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }

    return _buildGridContent(list);
  }


  Widget _buildGridContent(List<Map<String, dynamic>> list) {
    return LayoutBuilder(
      builder: (context, constraints) {
        double aspectRatio;
        double titleFontSize;
        double valueFontSize;
        double padding;
        double spacing;

        if (constraints.maxWidth < 320) {
          aspectRatio = 1.5;
          titleFontSize = 11;
          valueFontSize = 18;
          padding = 8;
          spacing = 8;
        } else if (constraints.maxWidth < 360) {
          aspectRatio = 1.6;
          titleFontSize = 12;
          valueFontSize = 20;
          padding = 9;
          spacing = 10;
        } else {
          aspectRatio = 1.8;
          titleFontSize = 14;
          valueFontSize = 22;
          padding = 10;
          spacing = 12;
        }

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: list.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: spacing,
            mainAxisSpacing: spacing,
            childAspectRatio: aspectRatio,
          ),
          itemBuilder: (context, index) {
            final item = list[index];

            return Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 6,
                    offset: const Offset(2, 3),
                  ),
                ],
              ),
              padding: EdgeInsets.all(padding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    item['title'] ?? '',
                    style: TextStyle(
                      fontSize: titleFontSize,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    item['value']?.toString() ?? '0',
                    style: TextStyle(
                      fontSize: valueFontSize,
                      fontWeight: FontWeight.bold,
                      color: Colors.blueAccent,
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }


  Widget _buildFormsCardList() {
    return SizedBox(
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
          const SizedBox(width: 16),
          _buildStationCleaningCard(),
        ],
      ),
    );
  }

  Widget _buildStationCleaningCard() {
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
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Color(0xFF1565C0).withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.train, color: Color(0xFF1565C0), size: 32),
            ),
            const SizedBox(height: 12),
            const Text(
              'Station Cleaning',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _scTile('Stations', scTotalStations, Icons.location_city),
                _scTile('Areas', scTotalAreas, Icons.grid_on),
                _scTile('Tasks Today', scTasksToday, Icons.assignment),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _scTile('Completed', scTasksCompleted, Icons.check_circle),
                _scTile('Pending', scTasksPending, Icons.hourglass_empty),
                _scTile('Shift Summary\nPending', scPendingShiftSummaries, Icons.toc),
              ],
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const StationDashboardScreen()));
              },
              style: ElevatedButton.styleFrom(backgroundColor: kRailwayBlue),
              child: const Text("Open Station Dashboard"),
            ),
          ],
        ),
      ),
    );
  }

  Widget _scTile(String label, int value, IconData icon) {
    return Container(
      width: 92,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF1565C0).withOpacity(0.06),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Icon(icon, color: const Color(0xFF1565C0), size: 18),
          const SizedBox(height: 4),
          Text(
            '$value',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1565C0)),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 9, color: Colors.grey.shade600),
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
              child: isStatsLoading
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
            ElevatedButton(
              onPressed: () {
                final navController = Get.find<ContractorNavController>();
                navController.changeTab(1);
              },
              style: ElevatedButton.styleFrom(backgroundColor: kRailwayBlue),
              child: const Text("Open Pending Forms"),
            ),
          ],
        ),
      ),
    );
  }



  Widget _buildActionButton(
      String title, IconData icon, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
          padding: EdgeInsets.all(20),
          decoration: BoxDecoration(
              gradient: LinearGradient(colors: [kRailwayBlue, Colors.lightBlue]),
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                    color: Colors.black12,
                    blurRadius: 6,
                    offset: Offset(0, 3))
              ]),
          child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: Colors.white),
                const SizedBox(width: 10),
                Text(title,
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold))
              ])),
    );
  }


  Widget _buildQuickActions(
      List<Map<String, dynamic>> actions, BuildContext context) {
    if (actions.isEmpty) return SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(vertical: 20, horizontal: 20),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Quick Actions",
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87)),
            const SizedBox(height: 10),

            if (actions.length == 1)
              Center(
                child: SizedBox(
                  width: 180,
                  child: QuickActionCard(
                    icon: actions[0]["icon"] as IconData,
                    title: actions[0]["title"] as String,
                    subtitle: actions[0]["subtitle"] as String,
                    color: actions[0]["color"] as Color,
                    onTap: () {
                      _handleQuickAction(actions[0]["title"] as String, context);
                    },
                  ),
                ),
              )

            else
              LayoutBuilder(
                builder: (context, constraints) {
                  double aspectRatio;
                  if (constraints.maxWidth < 350) {
                    aspectRatio = 1.6;
                  } else if (constraints.maxWidth < 400) {
                    aspectRatio = 1.6;
                  } else {
                    aspectRatio = 1.8;
                  }

                  return GridView.builder(
                    shrinkWrap: true,
                    physics: NeverScrollableScrollPhysics(),
                    itemCount: actions.length,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                        childAspectRatio: aspectRatio),
                    itemBuilder: (context, index) {
                      final action = actions[index];
                      return QuickActionCard(
                        icon: action["icon"] as IconData,
                        title: action["title"] as String,
                        subtitle: action["subtitle"] as String,
                        color: action["color"] as Color,
                        onTap: () {
                          _handleQuickAction(action["title"] as String, context);
                        },
                      );
                    },
                  );
                },
              ),
          ]),
    );
  }


  void _handleQuickAction(String actionTitle, BuildContext context) {
    final navController = Get.find<ContractorNavController>();

    switch (actionTitle) {
      case "Review Forms":
        debugPrint("Review Forms tapped");
        navController.changeTab(1);
        break;
      case "Pending Scorecards":
        debugPrint("Pending Scorecards tapped");
        navController.changeTab(1);
        break;
      case "Add New Train":
        Navigator.push(context,
            MaterialPageRoute(builder: (context) => TrainFormScreen()));
        break;
      case "Add New Entity":
        Navigator.push(
            context,
            MaterialPageRoute(
                builder: (context) => EntityRegisterForm()));
        break;
      default:
        break;
    }
  }

}
