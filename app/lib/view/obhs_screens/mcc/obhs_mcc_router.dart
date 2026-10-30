import 'package:flutter/material.dart';
import 'package:crm_train/model/user_model.dart';

import '../../common_workers/worker_mobile_nav_bar.dart';
import 'cm_dashboard_screen.dart';
import 'ca_dashboard_screen.dart';
import 'cts_train_view_screen.dart';
import 'cs_field_execution_screen.dart';

class ObhsMccRouter extends StatelessWidget {
  final UserModel user;

  const ObhsMccRouter({super.key, required this.user});

  @override
  Widget build(BuildContext context) {
    final role = user.role.toUpperCase().replaceAll(' ', '_');
    switch (role) {
      case 'CM':
      case 'COMPANY_MASTER':
      case 'CONTRACTOR_MASTER':
        return CmDashboardScreen(user: user);
      case 'CA':
      case 'CONTRACTOR_ADMIN':
        return CaDashboardScreen(user: user);
      case 'CTS':
        return CtsTrainViewScreen(user: user);
      case 'CS':
      case 'CONTRACTOR_SUPERVISOR':
        return CsFieldExecutionScreen(user: user);
      case 'JANITOR':
      case 'WORKER':
      case 'ATTENDANT':
        return WorkerMobileNavBar(user: user);
      default:
        return const Scaffold(
          body: Center(
            child: Text('Role not recognized in MCC workflow.'),
          ),
        );
    }
  }
}
