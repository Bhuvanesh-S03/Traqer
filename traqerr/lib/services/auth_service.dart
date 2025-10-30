// --- lib/services/auth_service.dart ---

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart'; // Import for debugPrint

// Enum definition must be consistent across all files
enum UserRole { admin, driver, parent, unknown }

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // CRITICAL: Use the exact domain defined in app.js
  static const String SYNTH_DOMAIN = "traqerr.com";

  /// -------------------------------
  ///  LOGIN FUNCTION: Uses phone ID to construct the Firebase email.
  /// -------------------------------
  Future<UserRole> signIn(String id, String password) async {
    try {
      // 1. Convert Phone ID to the required Firebase Email format: [id]@traqerr.com
      final String email = '$id@$SYNTH_DOMAIN';
      debugPrint('Attempting login for email: $email'); // Diagnostic logging

      // 2. Use the standard Firebase email/password method as dictated by app.js
      UserCredential userCredential = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password.trim(),
      );

      User? user = userCredential.user;
      if (user == null) return UserRole.unknown;

      // 3. Check role based on Auth UID
      return await getRoleFromUID(user.uid);
    } on FirebaseAuthException catch (e) {
      debugPrint('Firebase Auth Error: ${e.code} / ${e.message}');
      return UserRole.unknown;
    } catch (e) {
      debugPrint('Login Error: $e');
      return UserRole.unknown;
    }
  }

  /// -------------------------------
  ///  CORE ROLE VERIFICATION LOGIC (Efficient Direct Lookup)
  /// -------------------------------
  Future<UserRole> getRoleFromUID(String uid) async {
    try {
      // Check the primary collections using UID as the Document ID (most efficient)
      DocumentSnapshot doc =
          await _firestore.collection('parents').doc(uid).get();

      if (!doc.exists) {
        doc = await _firestore.collection('drivers').doc(uid).get();
      }

      // Check admin last (based on assumed collection name)
      if (!doc.exists) {
        // Assuming admin documents also use the UID as the document ID
        doc = await _firestore.collection('admins').doc(uid).get();
      }

      if (!doc.exists) return UserRole.unknown;

      // Retrieve the 'role' field, which app.js sets as 'parent', 'driver', etc.
      String role = doc.get('role');

      if (role == 'parent') return UserRole.parent;
      if (role == 'driver') return UserRole.driver;
      if (role == 'admin') return UserRole.admin;

      return UserRole.unknown;
    } catch (e) {
      debugPrint('Error fetching role: $e');
      return UserRole.unknown;
    }
  }

  /// -------------------------------
  ///  FETCH ROLE FROM CURRENT AUTH
  /// -------------------------------
  Future<UserRole> getRoleFromAuth() async {
    User? user = _auth.currentUser;
    if (user == null) return UserRole.unknown;
    return await getRoleFromUID(user.uid);
  }

  /// -------------------------------
  ///  SIGN OUT FUNCTION
  /// -------------------------------
  Future<void> signOutUser() async {
    await _auth.signOut();
  }

  // Note: The redirectUser function should live in the UI layer (like LoginScreen/main.dart)
}
