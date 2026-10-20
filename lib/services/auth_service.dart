import 'dart:async';
import '../models/user_model.dart';
import '../utils/constants.dart';
import 'mock_data_service.dart';
import 'vitalink_api.dart';
import 'vitalink_session.dart';

/// Authentication Service managing authentication state, role verification, and demo modes
class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  UserModel? _currentUser = MockDataService.initialUsers[0]; // Default to Patient
  final StreamController<UserModel?> _userStreamController =
      StreamController<UserModel?>.broadcast();

  Stream<UserModel?> get authStateChanges => _userStreamController.stream;
  UserModel? get currentUser => _currentUser;

  /// Restore a hospital/admin session from the last run. Called once from
  /// `main()` before the widget tree is built.
  Future<void> bootstrap() async {
    final ok = await VitalinkSession.instance.restore();
    if (!ok) return;
    final session = VitalinkSession.instance;
    if (!session.isHospitalOrAdmin) return;
    _currentUser = _userFromSession(session);
    _userStreamController.add(_currentUser);
  }

  UserModel _userFromSession(VitalinkSession session) {
    final isAdmin = session.role == 'admin';
    return UserModel(
      uid: session.userId ?? 'server_user',
      email: session.user?['email']?.toString() ?? '',
      name: session.userName ?? (isAdmin ? 'Administrator' : 'Hospital Staff'),
      phone: '',
      bloodGroup: 'O+',
      role: isAdmin ? UserRole.admin : UserRole.hospital,
      organizationOrVehicle: isAdmin ? 'VitaLink Admin' : 'VitaLink Hospital',
      verified: true,
      status: 'approved',
      createdAt: DateTime.now(),
    );
  }

  /// Quick login for testing any of the 5 roles instantly
  Future<UserModel> loginAsDemoRole(UserRole role) async {
    await VitalinkSession.instance.logout();
    await Future.delayed(const Duration(milliseconds: 400));
    final demoUser = MockDataService.initialUsers.firstWhere(
      (u) => u.role == role,
      orElse: () => MockDataService.initialUsers[0],
    );
    _currentUser = demoUser;
    _userStreamController.add(_currentUser);
    return demoUser;
  }

  /// Standard Email & Password Login.
  ///
  /// Demo/mock emails keep working offline. Any other email is tried against
  /// the VitaLink server, which is what enables the live hospital IoT data.
  Future<UserModel> login({
    required String email,
    required String password,
  }) async {
    final clean = email.trim();
    final isMock = MockDataService.initialUsers
        .any((u) => u.email.toLowerCase() == clean.toLowerCase());

    if (!isMock) {
      try {
        final res = await VitalinkApi().login(clean, password);
        final role = res['user'] is Map
            ? (res['user'] as Map)['role']?.toString()
            : null;
        if (role != 'hospital' && role != 'admin') {
          throw Exception('This account is not allowed in the hospital app.');
        }
        await VitalinkSession.instance.setLoginResponse(res);
        final user = _userFromSession(VitalinkSession.instance);
        _currentUser = user;
        _userStreamController.add(_currentUser);
        return user;
      } on VitalinkApiException catch (e) {
        final msg = e.status == 401
            ? 'Incorrect email or password for the VitaLink server.'
            : e.message;
        throw Exception(msg);
      }
    }

    await Future.delayed(const Duration(milliseconds: 400));
    // A demo account must never inherit a previous server session, otherwise
    // it would show another hospital's live data in real mode.
    await VitalinkSession.instance.logout();
    final user = MockDataService.initialUsers.firstWhere(
      (u) => u.email.toLowerCase() == clean.toLowerCase(),
      orElse: () => throw Exception('User account not found with this email.'),
    );

    if (user.status == 'suspended') {
      throw Exception('This account has been suspended by system administrators.');
    }

    _currentUser = user;
    _userStreamController.add(_currentUser);
    return user;
  }

  /// Register new user with 6-digit OTP requirement
  Future<UserModel> register({
    required String email,
    required String password,
    required String name,
    required String phone,
    required String bloodGroup,
    required UserRole role,
    String? organizationOrVehicle,
  }) async {
    await Future.delayed(const Duration(milliseconds: 700));

    final newUser = UserModel(
      uid: 'user_${DateTime.now().millisecondsSinceEpoch}',
      email: email.trim(),
      name: name.trim(),
      phone: phone.trim(),
      bloodGroup: bloodGroup,
      role: role,
      verified: role == UserRole.patient, // Donors & hospitals require admin approval
      status: (role == UserRole.hospital || role == UserRole.donor)
          ? 'pending'
          : 'approved',
      organizationOrVehicle: organizationOrVehicle,
      createdAt: DateTime.now(),
    );

    MockDataService.initialUsers.add(newUser);
    _currentUser = newUser;
    _userStreamController.add(_currentUser);
    return newUser;
  }

  /// Verify 6-digit OTP code
  Future<bool> verifyOtp({
    required String phone,
    required String otp,
  }) async {
    await Future.delayed(const Duration(milliseconds: 500));
    // Standard mock accepted OTPs: '123456' or any valid 6-digit number
    if (otp.length == 6) {
      if (_currentUser != null) {
        _currentUser = _currentUser!.copyWith(verified: true);
        _userStreamController.add(_currentUser);
      }
      return true;
    }
    return false;
  }

  /// Send password reset email
  Future<bool> resetPassword(String email) async {
    await Future.delayed(const Duration(milliseconds: 500));
    return true;
  }

  /// Update current user profile
  Future<void> updateProfile({
    String? name,
    String? phone,
    String? bloodGroup,
    String? organizationOrVehicle,
  }) async {
    if (_currentUser == null) return;
    _currentUser = _currentUser!.copyWith(
      name: name,
      phone: phone,
      bloodGroup: bloodGroup,
      organizationOrVehicle: organizationOrVehicle,
    );
    _userStreamController.add(_currentUser);
  }

  /// Sign out
  Future<void> signOut() async {
    await Future.delayed(const Duration(milliseconds: 200));
    await VitalinkSession.instance.logout();
    _currentUser = null;
    _userStreamController.add(null);
  }
}
