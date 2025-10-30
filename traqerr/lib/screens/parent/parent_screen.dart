// --- lib/screens/parent/parent_main_screen.dart ---

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../services/auth_service.dart';
import 'parent_home.dart';
import 'parent_achievement_tab.dart';
import 'parent_map.dart';

class ParentMainScreen extends StatefulWidget {
  const ParentMainScreen({super.key});

  @override
  State<ParentMainScreen> createState() => _ParentMainScreenState();
}

class _ParentMainScreenState extends State<ParentMainScreen> {
  int _currentIndex = 0;
  String? _assignedBusId;

  // Initialize tabs with a null assignedBusId placeholder first
  List<Widget> _tabs = [
    const ParentHomeTab(),
    const ParentAchievementsTab(),
    const ParentMap(assignedBusId: null), // Placeholder
  ];

  @override
  void initState() {
    super.initState();
    _fetchAssignedBusId();
  }

  Future<void> _fetchAssignedBusId() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    try {
      final doc =
          await FirebaseFirestore.instance.collection('parents').doc(uid).get();
      if (doc.exists) {
        final busId = doc.data()?['assignedBus'] as String?;
        setState(() {
          _assignedBusId = busId;
          _updateTabs();
        });
      }
    } catch (e) {
      debugPrint('Error fetching assigned bus ID: $e');
    }
  }

  void _updateTabs() {
    _tabs = [
      const ParentHomeTab(),
      const ParentAchievementsTab(),
      ParentMap(assignedBusId: _assignedBusId),
    ];
  }

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
        title: const Text('Parent Dashboard'),
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
            icon: Icon(Icons.military_tech),
            label: 'Announcements',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.map), label: 'Live Map'),
        ],
      ),
    );
  }
}
