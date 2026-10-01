import 'package:flutter/material.dart';
import 'package:crm_train/model/user_model.dart';

import '../view/common_railways/main_nav_screen.dart';
import '../view/common_workers/worker_mobile_nav_bar.dart';
import '../view/obhs_screens/mcc/obhs_mcc_router.dart';
import '../view/mcc/mcc_router.dart';

void navigateUser(BuildContext context, UserModel user) {
  // Normalize the role the same way ObhsMccRouter does, so casing and spacing
  // in the stored role ("Janitor", "contractor master", ...) never matter.
  final role = user.role.toUpperCase().replaceAll(' ', '_');

  // OBHS roles historically served by ObhsMccRouter (CTS, Janitor, Attendant,
  // Worker). They keep that screen even when no contractType is set.
  const obhsRoles = {'CTS', 'JANITOR', 'ATTENDANT', 'WORKER'};

  // Roles used by the OBHS conditional-cleaning module (contractType 'obhs'):
  // contractor masters/admins/supervisors included.
  const mccRoles = {
    'CTS',
    'CM', 'COMPANY_MASTER', 'CONTRACTOR_MASTER',
    'CA', 'CONTRACTOR_ADMIN',
    'CS', 'CONTRACTOR_SUPERVISOR',
    'JANITOR', 'ATTENDANT', 'WORKER',
  };

  const railwayWorkerRoles = {'RAILWAY_WORKER', 'RAILWAYSTAFF'};

  if (user.contractType == 'mcc') {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => MccRouter(user: user),
      ),
    );
  } else if (user.contractType == 'obhs' && mccRoles.contains(role)) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => ObhsMccRouter(user: user),
      ),
    );
  } else if (railwayWorkerRoles.contains(role)) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => WorkerMobileNavBar(user: user),
      ),
    );
  } else if (obhsRoles.contains(role)) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => ObhsMccRouter(user: user),
      ),
    );
  } else {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => MainNavScreen(user: user),
      ),
    );
  }
}
