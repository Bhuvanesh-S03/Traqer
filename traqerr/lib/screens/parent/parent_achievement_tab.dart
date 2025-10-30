// --- lib/screens/parent/parent_achievements_tab.dart ---
// Updated to stream and display data from Firestore.

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart'; // Needed for date formatting

class ParentAchievementsTab extends StatelessWidget {
  const ParentAchievementsTab({super.key});

  final Color primaryColor = const Color(0xFF00C896); // From style.css

  // Widget to stream documents from a collection
  Widget _buildStreamList({
    required String collection,
    required String title,
    required IconData icon,
    required BuildContext context,
  }) {
    return StreamBuilder<QuerySnapshot>(
      stream:
          FirebaseFirestore.instance
              .collection(collection)
              .orderBy('createdAt', descending: true)
              .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator(color: primaryColor));
        }
        if (snapshot.hasError) {
          return Center(
            child: Text(
              'Error: ${snapshot.error}',
              style: const TextStyle(color: Colors.red),
            ),
          );
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(
            child: Text(
              'No $title yet.',
              style: TextStyle(color: Colors.grey.shade600),
            ),
          );
        }

        return ListView(
          physics:
              const NeverScrollableScrollPhysics(), // Managed by parent SingleChildScrollView
          shrinkWrap: true,
          children:
              snapshot.data!.docs.map((doc) {
                final data = doc.data() as Map<String, dynamic>;
                final timestamp = data['createdAt'] as Timestamp?;
                final date =
                    timestamp != null
                        ? DateFormat(
                          'd MMM yyyy, h:mm a',
                        ).format(timestamp.toDate())
                        : 'Unknown Date';

                final isCircular = collection == 'circulars';
                final body = isCircular ? data['body'] : data['description'];

                return Card(
                  margin: const EdgeInsets.symmetric(
                    vertical: 8,
                    horizontal: 16,
                  ),
                  elevation: 4,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: ListTile(
                    leading: Icon(icon, color: primaryColor, size: 30),
                    title: Text(
                      data['title'] ?? 'No Title',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          body ?? 'No Content',
                          style: TextStyle(color: Colors.grey.shade700),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          date,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ),
                    isThreeLine: true,
                  ),
                );
              }).toList(),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              'School Notifications',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: primaryColor,
              ),
            ),
          ),

          // --- Circulars ---
          Padding(
            padding: const EdgeInsets.only(left: 16.0, top: 16, bottom: 8),
            child: Text(
              'Latest Circulars',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Colors.grey.shade800,
              ),
            ),
          ),
          _buildStreamList(
            collection: 'circulars',
            title: 'Circulars',
            icon: Icons.campaign,
            context: context,
          ),

          // --- Achievements ---
          Padding(
            padding: const EdgeInsets.only(left: 16.0, top: 24, bottom: 8),
            child: Text(
              'Student Achievements',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Colors.grey.shade800,
              ),
            ),
          ),
          _buildStreamList(
            collection: 'achievements',
            title: 'Achievements',
            icon: Icons.military_tech,
            context: context,
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}
