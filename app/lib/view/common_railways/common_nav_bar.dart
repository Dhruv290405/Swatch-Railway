import 'package:crm_train/controller/contractor_nav_controller.dart';
import 'package:crm_train/view/common_contractor/alert/contractor_master_alert_screen.dart';
import 'package:crm_train/view/common_contractor/dashboard/contractor_master_dashboard.dart';
import 'package:crm_train/view/common_contractor/form_screen/contractor_master_forms_screen.dart';
import 'package:crm_train/view/common_contractor/my_company/contractor_master_my_contracts_screen.dart';
import 'package:crm_train/view/common_contractor/report/contractor_master_report_screen.dart';
import 'package:crm_train/view/common_railways/report/common_report_screen.dart';
import 'package:crm_train/view/common_railways/trains/common_train_screen.dart';
import 'package:crm_train/view/common_railways/users/common_user_management_screen.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:persistent_bottom_nav_bar/persistent_bottom_nav_bar.dart';

import 'dashboard/dashboard_screen.dart';
import 'entities/common_entity_managment_screen.dart';
import 'forms/common_form_screen.dart';

class CommonNavBar extends StatelessWidget {
  final String userRole;
  final String userLevel;
  final String? userDisplayRole;
  final String? contractType;

  const CommonNavBar({
    super.key,
    required this.userRole,
    required this.userLevel,
    this.userDisplayRole,
    this.contractType,
  });

  bool get _isStationCleaning => contractType == 'station_cleaning';
  bool get _isContractorSupervisor =>
      userDisplayRole != null && userDisplayRole == 'Contractor Supervisor';
  bool get _isContractorMaster => userDisplayRole == 'Contractor Master';
  bool get _isContractorEmployee =>
      userDisplayRole == 'Contractor Admin' ||
          userDisplayRole == 'Contractor Supervisor';

  List<Widget> _contractorScreens() {
    final screens = <Widget>[
      ContractorMasterDashboard(contractType: contractType),
      if (!_isContractorSupervisor && !(_isStationCleaning && (_isContractorEmployee || _isContractorMaster)))
        ContractorMasterFormsScreen(contractType: contractType),
      if (!_isContractorSupervisor && !(_isStationCleaning && _isContractorEmployee))
        ContractorMasterMyContractsScreen(),
      if (!(_isStationCleaning && (_isContractorEmployee || _isContractorMaster)))
        ContractorReportScreen(contractType: contractType),
      if (!_isContractorSupervisor) CommonUserManagementScreen(),
    ];
    if (!_isStationCleaning) {
      screens.add(CommonTrainScreen());
    }
    return screens;
  }

  List<PersistentBottomNavBarItem> _contractorNavItems() {
    final items = <PersistentBottomNavBarItem>[
      PersistentBottomNavBarItem(
        icon: const Icon(Icons.dashboard_rounded),
        title: "Dashboard",
        activeColorPrimary: Colors.blue,
        inactiveColorPrimary: Colors.grey,
      ),
      if (!_isContractorSupervisor && !(_isStationCleaning && (_isContractorEmployee || _isContractorMaster)))
        PersistentBottomNavBarItem(
          icon: const Icon(Icons.description_rounded),
          title: "Forms",
          activeColorPrimary: Colors.blue,
          inactiveColorPrimary: Colors.grey,
        ),
      if (!_isContractorSupervisor && !(_isStationCleaning && _isContractorEmployee))
        PersistentBottomNavBarItem(
          icon: const Icon(Icons.file_copy_rounded),
          title: "My Contracts",
          activeColorPrimary: Colors.blue,
          inactiveColorPrimary: Colors.grey,
        ),
      if (!(_isStationCleaning && (_isContractorEmployee || _isContractorMaster)))
        PersistentBottomNavBarItem(
          icon: const Icon(Icons.bar_chart),
          title: "Report",
          activeColorPrimary: Colors.blue,
          inactiveColorPrimary: Colors.grey,
        ),
      if (!_isContractorSupervisor)
        PersistentBottomNavBarItem(
          icon: const Icon(Icons.people),
          title: "Users",
          activeColorPrimary: Colors.blue,
          inactiveColorPrimary: Colors.grey,
        ),
    ];
    if (!_isStationCleaning) {
      items.add(
        PersistentBottomNavBarItem(
          icon: const Icon(Icons.train),
          title: "Train",
          activeColorPrimary: Colors.blue,
          inactiveColorPrimary: Colors.grey,
        ),
      );
    }
    return items;
  }


  bool get _isSuperAdmin => userDisplayRole == 'Super Admin';

  List<Widget> _commonScreens() {
    final screens = <Widget>[
      CommonDashboard(),
      CommonFormScreen(role: userRole, userLevel: userLevel),
      CommonUserManagementScreen(),
      if (_isSuperAdmin) CommonEntityManagmentScreen(),
      CommonReportScreen(),
      CommonTrainScreen(),
    ];
    return screens;
  }

  List<PersistentBottomNavBarItem> _commonNavItems() {
    final items = <PersistentBottomNavBarItem>[
      PersistentBottomNavBarItem(
        icon: const Icon(Icons.dashboard_rounded),
        title: "Dashboard",
        activeColorPrimary: Colors.blue,
        inactiveColorPrimary: Colors.grey,
      ),
      PersistentBottomNavBarItem(
        icon: const Icon(Icons.description_rounded),
        title: "Forms",
        activeColorPrimary: Colors.blue,
        inactiveColorPrimary: Colors.grey,
      ),
      PersistentBottomNavBarItem(
        icon: const Icon(Icons.person_add_alt_1_rounded),
        title: "Approvals",
        activeColorPrimary: Colors.blue,
        inactiveColorPrimary: Colors.grey,
      ),
      if (_isSuperAdmin)
        PersistentBottomNavBarItem(
          icon: const Icon(Icons.location_city_outlined),
          title: "Entity",
          activeColorPrimary: Colors.blue,
          inactiveColorPrimary: Colors.grey,
        ),
      PersistentBottomNavBarItem(
        icon: const Icon(Icons.bar_chart),
        title: "Reports",
        activeColorPrimary: Colors.blue,
        inactiveColorPrimary: Colors.grey,
      ),
      PersistentBottomNavBarItem(
        icon: const Icon(Icons.train),
        title: "Train",
        activeColorPrimary: Colors.blue,
        inactiveColorPrimary: Colors.grey,
      ),
    ];
    return items;
  }

  @override
  Widget build(BuildContext context) {
    final navController = Get.put(ContractorNavController());


    final isContractor = userRole.toLowerCase() == "contractor" ||
        (userDisplayRole != null && (userDisplayRole!.contains("Contractor") || userDisplayRole == "Company Master"));

    final screens = isContractor ? _contractorScreens() : _commonScreens();
    final items = isContractor ? _contractorNavItems() : _commonNavItems();

    if (items.length < 2 || screens.length < 2) {
      return Scaffold(body: screens.isNotEmpty ? screens.first : const SizedBox.shrink());
    }

    return GetBuilder<ContractorNavController>(
      builder: (controller) {
        return PersistentTabView(
          context,
          controller: controller.tabController,
          screens: screens,
          items: items,
          onItemSelected: controller.onTabSelected,
          confineToSafeArea: true,
          backgroundColor: Colors.white,
          handleAndroidBackButtonPress: true,
          resizeToAvoidBottomInset: true,
          stateManagement: true,
          decoration: NavBarDecoration(
            borderRadius: BorderRadius.circular(15.0),
            colorBehindNavBar: Colors.white,
          ),
          navBarStyle: NavBarStyle.style12,
        );
      },
    );
  }
}
