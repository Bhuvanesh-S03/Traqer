// --- lib/main.dart ---

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:traqerr/config/constants.dart';
import 'screens/login/login_screen.dart';
import 'screens/parent/parent_screen.dart';
import 'screens/driver/driver_screen.dart';
// FIX 1: Import AuthService with an alias (as auth) to properly access UserRole
import 'services/auth_service.dart' as auth;
 // ⬅️ Your TraqerApp widget (or put all below if you prefer single file)

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ✅ Absolute safe Firebase init
  try {
    // Try to initialize only if it doesn’t exist
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(options: kFirebaseOptions);
    } else {
      // Reuse existing app on hot restart
      Firebase.app();
    }
  } catch (e) {
    // ✅ Prevent crash on hot reload if Firebase already initialized
    debugPrint('⚠️ Firebase already initialized: $e');
  }

  runApp(const TraqerApp());
}

class TraqerApp extends StatelessWidget {
  const TraqerApp({super.key});

  // Primary color from app.js style.css: #00C896 (Teal/Green)
  final Color primaryColor = const Color(0xFF00C896);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Traqer Mobile',
      // Apply a smooth, modern UI theme (Apple-like aesthetics)
      theme: ThemeData(
        primaryColor: primaryColor,
        colorScheme: ColorScheme.light(
          primary: primaryColor,
          secondary: primaryColor.withOpacity(0.8),
          onPrimary: Colors.white,
          surface: Colors.white,
        ),
        fontFamily: 'Inter',
        appBarTheme: AppBarTheme(
          color: primaryColor,
          titleTextStyle: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
          iconTheme: const IconThemeData(color: Colors.white),
          elevation: 1,
        ),
        scaffoldBackgroundColor: const Color(
          0xFFF5F7FA,
        ), // From style.css background
        useMaterial3: true,
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: primaryColor,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            textStyle: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      ),
      initialRoute: '/login',
      // Defined routes (assuming you have a route for /admin)
      routes: {
        '/login': (context) => const LoginScreen(),
        '/parent': (context) => const ParentMainScreen(),
        '/driver': (context) => const DriverMainScreen(),
        // '/adminHome': (context) => const AdminMainScreen(), // Placeholder for Admin route
      },
      // Check auth state and redirect immediately
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Scaffold(
              body: Center(
                child: CircularProgressIndicator(color: primaryColor),
              ),
            );
          }
          if (snapshot.hasData) {
            return const RoleRedirector();
          }
          return const LoginScreen();
        },
      ),
    );
  }
}

// Helper widget to fetch the role and navigate
class RoleRedirector extends StatelessWidget {
  const RoleRedirector({super.key});

  @override
  Widget build(BuildContext context) {
    final Color primaryColor = Theme.of(context).primaryColor;
    return FutureBuilder<auth.UserRole>(
      // FIX 3: Use auth.UserRole
      future:
          auth.AuthService().getRoleFromAuth(), // FIX 4: Use auth.AuthService
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            body: Center(child: CircularProgressIndicator(color: primaryColor)),
          );
        }

        // Use AuthService's signIn logic for redirection (this handles the unknown/error case)
        final auth.UserRole role =
            snapshot.data ?? auth.UserRole.unknown; // FIX 5: Use auth.UserRole

        if (role == auth.UserRole.parent) {
          // FIX 6: Use auth.UserRole
          return const ParentMainScreen();
        } else if (role == auth.UserRole.driver) {
          // FIX 7: Use auth.UserRole
          return const DriverMainScreen();
        } else if (role == auth.UserRole.admin) {
          // FIX 8: Use auth.UserRole
          // Placeholder for the Admin route
          return const Text('Admin Redirect Placeholder');
        }

        // Default to login if role is unknown or error
        return const LoginScreen();
      },
    );
  }
}
