import 'package:flutter/material.dart';
import '../models/user_model.dart';
import '../repositories/auth_repository.dart';
import '../services/vitalink_session.dart';
import '../utils/constants.dart';
import 'app_mode_provider.dart';

/// Authentication ViewModel managing user sessions, roles, and verification
class AuthProvider with ChangeNotifier {
  final AuthRepository _authRepository;

  UserModel? _currentUser;
  bool _isLoading = false;
  String? _errorMessage;

  AuthProvider({AuthRepository? authRepository})
      : _authRepository = authRepository ?? AuthRepository() {
    _currentUser = _authRepository.currentUser;
    _authRepository.authState.listen((user) {
      _currentUser = user;
      notifyListeners();
    });
  }

  UserModel? get currentUser => _currentUser;
  bool get isAuthenticated => _currentUser != null;
  UserRole get currentRole => _currentUser?.role ?? UserRole.patient;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  Future<bool> login(String email, String password) async {
    _setLoading(true);
    try {
      _currentUser = await _authRepository.login(
        email: email,
        password: password,
      );
      _errorMessage = null;
      _setLoading(false);
      await _alignModeWithSession();
      return true;
    } catch (e) {
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      _setLoading(false);
      return false;
    }
  }

  Future<void> loginAsDemoRole(UserRole role) async {
    _setLoading(true);
    _currentUser = await _authRepository.loginAsDemoRole(role);
    _errorMessage = null;
    _setLoading(false);
    await _alignModeWithSession();
  }

  Future<bool> register({
    required String email,
    required String password,
    required String name,
    required String phone,
    required String bloodGroup,
    required UserRole role,
    String? organizationOrVehicle,
  }) async {
    _setLoading(true);
    try {
      _currentUser = await _authRepository.register(
        email: email,
        password: password,
        name: name,
        phone: phone,
        bloodGroup: bloodGroup,
        role: role,
        organizationOrVehicle: organizationOrVehicle,
      );
      _errorMessage = null;
      _setLoading(false);
      return true;
    } catch (e) {
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      _setLoading(false);
      return false;
    }
  }

  Future<bool> verifyOtp(String phone, String otp) async {
    _setLoading(true);
    final success = await _authRepository.verifyOtp(phone: phone, otp: otp);
    _setLoading(false);
    return success;
  }

  Future<bool> resetPassword(String email) async {
    _setLoading(true);
    final success = await _authRepository.resetPassword(email);
    _setLoading(false);
    return success;
  }

  Future<void> updateProfile({
    String? name,
    String? phone,
    String? bloodGroup,
    String? organizationOrVehicle,
  }) async {
    _setLoading(true);
    await _authRepository.updateProfile(
      name: name,
      phone: phone,
      bloodGroup: bloodGroup,
      organizationOrVehicle: organizationOrVehicle,
    );
    _currentUser = _authRepository.currentUser;
    _setLoading(false);
  }

  Future<void> signOut() async {
    await _authRepository.signOut();
    _currentUser = null;
    notifyListeners();
    // Without a session there is no real data to show.
    await AppModeProvider.instance.setMode(AppMode.demo);
  }

  /// Real mode needs a VitaLink hospital or admin session.
  ///
  /// A demo account (or a sign-out) leaves the app without one, so the app
  /// falls back to demo mode instead of showing an error.
  Future<void> _alignModeWithSession() async {
    if (!AppModeProvider.instance.isReal) return;
    if (VitalinkSession.instance.canUseIot) return;
    await AppModeProvider.instance.setMode(AppMode.demo);
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }
}
