import 'package:flutter/material.dart';
import '../../model/user_model.dart';
import 'common_nav_bar.dart';

class MainNavScreen extends StatelessWidget {
  final UserModel user;
  const MainNavScreen({super.key, required this.user});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CommonNavBar(
        userLevel: user.zone ?? user.division ?? user.depot ?? 'All Zones',
        userRole: user.userType,
        userDisplayRole: user.role,
        contractType: user.effectiveContractType,
      ),
    );
  }
}
