// --- lib/screens/parent/parent_home.dart ---

import 'package:flutter/material.dart';

class ParentHomeTab extends StatelessWidget {
  const ParentHomeTab({super.key});

  @override
  Widget build(BuildContext context) {
    final Color primaryColor = Theme.of(context).primaryColor;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.school, size: 70, color: primaryColor.withOpacity(0.8)),
            const SizedBox(height: 20),
            const Text(
              'Welcome to Traqer!',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            Text(
              'Your secure portal to track your child\'s school transport in real-time.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
            ),
            const SizedBox(height: 40),
            ElevatedButton.icon(
              onPressed: () => Navigator.of(context).pushNamed('/parent'),
              icon: const Icon(Icons.map),
              label: const Text('Go to Live Map'),
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
