import 'package:flutter/material.dart';
import 'package:crm_train/model/user_model.dart';

import 'mcc_hub_screen.dart';
import 'mcc_worker_task_board_screen.dart';

class MccRouter extends StatelessWidget {
  final UserModel user;

  const MccRouter({super.key, required this.user});

  @override
  Widget build(BuildContext context) {
    final role = user.role.toUpperCase().replaceAll(' ', '_');
    switch (role) {
      case 'CM':
      case 'COMPANY_MASTER':
      case 'CA':
      case 'CONTRACTOR_MASTER':
      case 'CONTRACTOR_ADMIN':
      case 'CTS':
      case 'CS':
      case 'CONTRACTOR_SUPERVISOR':
        return MccHubScreen(user: user);
      case 'JANITOR':
      case 'WORKER':
      case 'ATTENDANT':
        return MccWorkerTaskBoardScreen(user: user);
      default:
        return const Scaffold(
          body: Center(
            child: Text('Role not recognized in MCC workflow.'),
          ),
        );
    }
  }
}