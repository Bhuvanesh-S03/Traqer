// --- lib/screens/driver/driver_home.dart ---

import 'package:flutter/material.dart';

class DriverHomeTab extends StatelessWidget {
  const DriverHomeTab({super.key});

  @override
  Widget build(BuildContext context) {
    final Color primaryColor = Theme.of(context).primaryColor;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.directions_bus_filled,
              size: 70,
              color: primaryColor.withOpacity(0.8),
            ),
            const SizedBox(height: 20),
            const Text(
              'Welcome, Driver!',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            Text(
              'Navigate to the "Start Route" tab to begin sending live location updates to parents.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
            ),
            const SizedBox(height: 40),
            // Placeholder for quick route info fetching
            ElevatedButton.icon(
              onPressed:
                  () => ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Route details feature coming soon!'),
                    ),
                  ),
              icon: const Icon(Icons.route),
              label: const Text('View Assigned Route'),
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor.withOpacity(0.9),
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
