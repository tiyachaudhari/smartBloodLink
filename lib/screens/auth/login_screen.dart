import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../utils/app_colors.dart';
import '../../utils/constants.dart';
import '../../widgets/animated_card.dart';
import '../../widgets/custom_button.dart';
import '../../widgets/custom_text_field.dart';
import '../patient/patient_main_navigation.dart';
import '../donor/donor_main_navigation.dart';
import '../hospital/hospital_main_navigation.dart';
import '../ambulance/ambulance_main_navigation.dart';
import '../admin/admin_main_navigation.dart';
import 'forgot_password_screen.dart';
import 'register_screen.dart';

/// Secure Login Screen with instant 1-tap role switcher for test evaluations
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController(text: 'patient@bloodlink.org');
  final _passwordController = TextEditingController(text: 'demo123');
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _routeToRoleDashboard(UserRole role) {
    Widget target;
    switch (role) {
      case UserRole.patient:
        target = const PatientMainNavigation();
        break;
      case UserRole.donor:
        target = const DonorMainNavigation();
        break;
      case UserRole.hospital:
        target = const HospitalMainNavigation();
        break;
      case UserRole.ambulance:
        target = const AmbulanceMainNavigation();
        break;
      case UserRole.admin:
        target = const AdminMainNavigation();
        break;
    }

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => target),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),
              Center(
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.bloodtype_rounded,
                    size: 38,
                    color: AppColors.primary,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Center(
                child: Text(
                  'Welcome to Smart BloodLink',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Center(
                child: Text(
                  'Emergency Blood Coordination Platform',
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark
                        ? AppColors.darkTextSecondary
                        : AppColors.lightTextSecondary,
                  ),
                ),
              ),
              const SizedBox(height: 32),

              // Form
              Form(
                key: _formKey,
                child: Column(
                  children: [
                    CustomTextField(
                      label: 'Email Address',
                      hint: 'name@bloodlink.org',
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      prefixIcon: Icons.email_outlined,
                      validator: (val) =>
                          val == null || !val.contains('@')
                              ? 'Enter a valid email'
                              : null,
                    ),
                    const SizedBox(height: 16),
                    CustomTextField(
                      label: 'Password',
                      hint: '••••••••',
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      prefixIcon: Icons.lock_outline_rounded,
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          size: 20,
                        ),
                        onPressed: () {
                          setState(() {
                            _obscurePassword = !_obscurePassword;
                          });
                        },
                      ),
                      validator: (val) => val == null || val.length < 6
                          ? 'Password must be at least 6 chars'
                          : null,
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const ForgotPasswordScreen(),
                            ),
                          );
                        },
                        child: const Text('Forgot Password?'),
                      ),
                    ),
                    if (authProvider.errorMessage != null) ...[
                      Container(
                        padding: const EdgeInsets.all(10),
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: AppColors.errorLight,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline,
                                color: AppColors.error, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                authProvider.errorMessage!,
                                style: const TextStyle(
                                    color: AppColors.error, fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    CustomButton(
                      text: 'Sign In',
                      isLoading: authProvider.isLoading,
                      onPressed: () async {
                        if (_formKey.currentState!.validate()) {
                          final success = await authProvider.login(
                            _emailController.text.trim(),
                            _passwordController.text.trim(),
                          );
                          if (success && mounted) {
                            _routeToRoleDashboard(authProvider.currentRole);
                          }
                        }
                      },
                    ),
                    const SizedBox(height: 10),
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.cloud_outlined,
                            size: 14, color: Colors.grey),
                        SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            'A VitaLink hospital or admin account unlocks real '
                            'mode with live cold-chain data from the server',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 11, color: Colors.grey),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // 1-Tap Quick Demo Role Selection
              AnimatedCard(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: const [
                        Icon(Icons.bolt_rounded,
                            size: 18, color: AppColors.primary),
                        SizedBox(width: 6),
                        Text(
                          '1-Tap Demo Logins (Evaluation Shortcuts)',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _demoRoleChip(
                          'Patient',
                          UserRole.patient,
                          Icons.personal_injury_rounded,
                          authProvider,
                        ),
                        _demoRoleChip(
                          'Donor',
                          UserRole.donor,
                          Icons.volunteer_activism_rounded,
                          authProvider,
                        ),
                        _demoRoleChip(
                          'Hospital',
                          UserRole.hospital,
                          Icons.local_hospital_rounded,
                          authProvider,
                        ),
                        _demoRoleChip(
                          'Ambulance',
                          UserRole.ambulance,
                          Icons.emergency_rounded,
                          authProvider,
                        ),
                        _demoRoleChip(
                          'Admin',
                          UserRole.admin,
                          Icons.admin_panel_settings_rounded,
                          authProvider,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Sign Up Link
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text("Don't have an account?"),
                  TextButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const RegisterScreen(),
                        ),
                      );
                    },
                    child: const Text('Register Now'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _demoRoleChip(
    String label,
    UserRole role,
    IconData icon,
    AuthProvider authProvider,
  ) {
    return ActionChip(
      avatar: Icon(icon, size: 16, color: AppColors.primary),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      onPressed: () async {
        await authProvider.loginAsDemoRole(role);
        if (mounted) {
          _routeToRoleDashboard(role);
        }
      },
    );
  }
}
