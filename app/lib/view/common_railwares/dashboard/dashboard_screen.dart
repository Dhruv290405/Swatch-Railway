import 'package:flutter/material.dart';

class CommonDashboard extends StatefulWidget {
  const CommonDashboard({super.key});

  @override
  State<CommonDashboard> createState() => _CommonDashboardState();
}

class _CommonDashboardState extends State<CommonDashboard> {
  int _currentPage = 1;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dashboard')),
      body: const Center(child: Text('Dashboard')),
    );
  }
}
