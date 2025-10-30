// --- lib/models/user_model.dart ---

import 'package:cloud_firestore/cloud_firestore.dart';

enum UserRole { parent, driver, unregistered, error }

class UserModel {
  final String uid;
  final String name;
  final String phone;
  final UserRole role;

  // CRITICAL FIX: Changed assignedBusNum to assignedBus to match app.js schema.
  final String? assignedBus;
  final String? assignedStopId; // Only relevant for parents

  UserModel({
    required this.uid,
    required this.name,
    required this.phone,
    required this.role,
    this.assignedBus,
    this.assignedStopId,
  });

  // Factory constructor to create UserModel from a Firestore Document
  factory UserModel.fromFirestore(DocumentSnapshot doc, UserRole role) {
    final data = doc.data() as Map<String, dynamic>;

    String busId = '';
    String stopId = '';

    // Data field is 'assignedBus' for both roles
    busId = data['assignedBus'] ?? '';
    if (role == UserRole.parent) {
      stopId = data['assignedStopId'] ?? '';
    }

    return UserModel(
      uid: doc.id,
      name: data['name'] ?? 'N/A',
      phone: data['phone'] ?? '',
      role: role,
      assignedBus: busId,
      assignedStopId: stopId,
    );
  }
}
