import 'package:flutter/material.dart';
import 'package:crm_train/model/user_model.dart';

import '../view/common_railways/main_nav_screen.dart';
import '../view/common_workers/worker_mobile_nav_bar.dart';
import '../view/obhs_screens/mcc/obhs_mcc_router.dart';
import '../view/mcc/mcc_router.dart';

void navigateUser(BuildContext context, UserModel user) {
  final role = user.role.toUpperCase().replaceAll(' ', '_');

  const obhsRoles = {'CTS', 'WORKER'};

  const railwayWorkerRoles = {'RAILWAY_WORKER', 'RAILWAYSTAFF', 'JANITOR', 'ATTENDANT'};
  final stationWorkerType = (user.workerType ?? '').toUpperCase();
  final isStationCleaningWorker =
      user.contractType == 'station_cleaning' &&
      (role == 'JANITOR' ||
          role == 'ATTENDANT' ||
          (role == 'WORKER' &&
              (stationWorkerType == 'JANITOR' ||
                  stationWorkerType == 'ATTENDANT')));

  if (isStationCleaningWorker) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => WorkerMobileNavBar(user: user)),
    );
  } else if (user.contractType == 'mcc') {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => MccRouter(user: user)),
    );
  } else if (railwayWorkerRoles.contains(role)) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => WorkerMobileNavBar(user: user)),
    );
  } else if (obhsRoles.contains(role)) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => ObhsMccRouter(user: user)),
    );
  } else {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => MainNavScreen(user: user)),
    );
  }
}
