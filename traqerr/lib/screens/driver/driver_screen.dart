// --- lib/screens/driver/driver_main_screen.dart ---

import 'package:flutter/material.dart';
import '../../services/auth_service.dart';
import 'driver_home.dart'; // Actual Home Tab content
import 'driver_map.dart'; // Actual GPS Tracking Tab content

class DriverMainScreen extends StatefulWidget {
  const DriverMainScreen({super.key});

  @override
  State<DriverMainScreen> createState() => _DriverMainScreenState();
}

class _DriverMainScreenState extends State<DriverMainScreen> {
  int _currentIndex = 0;

  // Tabs list now correctly references the implemented files
  final List<Widget> _tabs = [const DriverHomeTab(), const DriverMapTab()];

  void _logout() async {
    await AuthService().signOutUser();
    if (mounted) {
      Navigator.of(
        context,
      ).pushNamedAndRemoveUntil('/login', (Route<dynamic> route) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Driver Dashboard'),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(icon: const Icon(Icons.logout), onPressed: _logout),
        ],
      ),
      body: _tabs[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(
            icon: Icon(Icons.location_on),
            label: 'Start Route/GPS',
          ),
        ],
      ),
    );
  }
}
