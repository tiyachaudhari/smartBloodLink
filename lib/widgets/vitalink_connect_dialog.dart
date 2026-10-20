import 'package:flutter/material.dart';

import '../services/vitalink_api.dart';
import '../services/vitalink_session.dart';
import '../utils/app_colors.dart';
import '../utils/constants.dart';
import 'custom_button.dart';
import 'custom_text_field.dart';

/// Asks for VitaLink server credentials so Real mode can be used.
///
/// Returns true when a session was established, false when the user
/// cancelled or the login failed. The dialog never leaves the app in a
/// half-signed-in state.
class VitalinkConnectDialog extends StatefulWidget {
  /// The app role the server account must have.
  final UserRole expectedRole;

  const VitalinkConnectDialog({super.key, required this.expectedRole});

  /// Shows the dialog and resolves to true when a session was created.
  static Future<bool> show(BuildContext context, UserRole expectedRole) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => VitalinkConnectDialog(expectedRole: expectedRole),
    );
    return ok == true;
  }

  @override
  State<VitalinkConnectDialog> createState() => _VitalinkConnectDialogState();
}

class _VitalinkConnectDialogState extends State<VitalinkConnectDialog> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  String get _expectedServerRole =>
      widget.expectedRole == UserRole.admin ? 'admin' : 'hospital';

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await VitalinkApi().login(
        _emailController.text.trim(),
        _passwordController.text,
      );
      final user = res['user'];
      final role = user is Map ? user['role']?.toString() : null;
      if (role != _expectedServerRole) {
        setState(() {
          _busy = false;
          _error = 'This VitaLink account is a ${role ?? 'unknown'} account. '
              'Real mode needs a $_expectedServerRole account for this role.';
        });
        return;
      }
      await VitalinkSession.instance.setLoginResponse(res);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on VitalinkApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.status == 401
            ? 'Incorrect email or password for the VitaLink server.'
            : e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.toString().replaceAll('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Row(
        children: [
          Icon(Icons.cloud_rounded, color: AppColors.primary),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Connect to VitaLink',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Real mode reads the cold-chain data from the VitaLink server, '
                'so it needs a server account for this role.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              CustomTextField(
                label: 'VitaLink email',
                controller: _emailController,
                prefixIcon: Icons.alternate_email_rounded,
                keyboardType: TextInputType.emailAddress,
                validator: (val) => (val == null || !val.contains('@'))
                    ? 'Enter a valid email'
                    : null,
              ),
              const SizedBox(height: 14),
              CustomTextField(
                label: 'Password',
                controller: _passwordController,
                prefixIcon: Icons.lock_outline_rounded,
                obscureText: true,
                validator: (val) =>
                    (val == null || val.isEmpty) ? 'Enter your password' : null,
              ),
              if (_error != null) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.errorLight,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.error),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline_rounded,
                          color: AppColors.error, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _error!,
                          style: const TextStyle(fontSize: 12, color: Colors.black87),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        SizedBox(
          width: 130,
          child: CustomButton(
            text: 'Connect',
            icon: Icons.login_rounded,
            isLoading: _busy,
            onPressed: _busy ? null : _submit,
          ),
        ),
      ],
    );
  }
}
