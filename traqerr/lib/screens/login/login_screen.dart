// --- lib/screens/login/login_screen.dart ---

import 'package:flutter/material.dart';
// FIX: Import AuthService with alias to access UserRole and sign-in logic
import '../../services/auth_service.dart' as auth;
// Removed: import '../../models/user_model.dart' show UserRole;
// The enum is now defined in auth_service.dart

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _idController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  // FIX: Use the aliased AuthService when instantiating the service
  final auth.AuthService _authService = auth.AuthService();
  bool _isLoading = false;

  final Color primaryColor = const Color(0xFF00C896);

  void _login() async {
    if (_idController.text.trim().isEmpty ||
        _passwordController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter ID (Phone Number) and Password.'),
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    final String id = _idController.text.trim();
    final String password = _passwordController.text.trim();

    // The AuthService handles converting ID to the full email format
    auth.UserRole role = await _authService.signIn(
      id,
      password,
    ); // Corrected reference

    if (mounted) {
      setState(() {
        _isLoading = false;
      });

      if (role == auth.UserRole.parent) {
        // FIX: Use auth.UserRole
        Navigator.of(context).pushReplacementNamed('/parent');
      } else if (role == auth.UserRole.driver) {
        // FIX: Use auth.UserRole
        Navigator.of(context).pushReplacementNamed('/driver');
      } else if (role == auth.UserRole.admin) {
        // Check for admin role
        // In a real app, this would navigate to the mobile admin interface
        Navigator.of(context).pushReplacementNamed('/adminHome');
      } else {
        // Handle UserRole.unknown (which includes error) and unregistered
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Login Failed. Invalid ID/Password or role not assigned.',
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Traqer Login'),
        backgroundColor: primaryColor,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // App Icon/Branding
              Icon(Icons.directions_bus_filled, size: 80, color: primaryColor),
              const SizedBox(height: 10),
              Text(
                'Traqer Mobile',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: primaryColor,
                ),
              ),
              const SizedBox(height: 40),

              // ID Field (Phone Number)
              TextField(
                controller: _idController,
                decoration: InputDecoration(
                  labelText: 'ID (Phone Number)',
                  hintText: 'e.g., 9000000001',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  prefixIcon: const Icon(Icons.phone),
                ),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 16),

              // Password Field
              TextField(
                controller: _passwordController,
                decoration: InputDecoration(
                  labelText: 'Password',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  prefixIcon: const Icon(Icons.lock),
                ),
                obscureText: true,
              ),
              const SizedBox(height: 30),

              // Login Button
              _isLoading
                  ? Center(
                    child: CircularProgressIndicator(color: primaryColor),
                  )
                  : ElevatedButton(
                    onPressed: _login,
                    child: const Text(
                      'SIGN IN',
                      style: TextStyle(fontSize: 16),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryColor,
                      foregroundColor: Colors.white,
                      elevation: 6,
                      shadowColor: primaryColor.withOpacity(0.4),
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}
