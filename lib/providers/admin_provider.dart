import 'dart:async';

import 'package:flutter/material.dart';

import '../models/audit_log_model.dart';
import '../models/inventory_item_model.dart';
import '../models/iot_models.dart';
import '../models/user_model.dart';
import '../repositories/admin_repository.dart';
import '../services/real_inventory_mapper.dart';
import '../services/vitalink_api.dart';
import '../services/vitalink_session.dart';
import 'app_mode_provider.dart';

/// Administrator ViewModel managing platform oversight, user verification,
/// and audit logs.
///
/// Demo mode stays on the bundled simulation. Real mode reads the device
/// list, the cold-chain alerts, the audit trail and the bag stock from the
/// VitaLink server. Metrics the server does not publish (donor and request
/// counts) keep their simulated value and are flagged as simulated so the
/// screens can say so.
class AdminProvider with ChangeNotifier {
  final AdminRepository _adminRepository;
  final VitalinkApi _api;

  List<UserModel> _users = [];
  List<AuditLogModel> _auditLogs = [];
  Map<String, int> _metrics = {};
  bool _isLoading = false;

  // ---- real mode ------------------------------------------------------
  AppMode _mode = AppMode.demo;
  List<IotDevice> _devices = const [];
  List<IotAlert> _alerts = const [];
  List<BloodBagModel> _bags = const [];
  Map<String, int> _stockCounts = const {};
  Map<String, int> _realMetrics = const {};
  Set<String> _simulatedMetrics = {};
  String? _realError;
  String? _actionError;
  DateTime? _lastSync;

  Timer? _timer;
  bool _disposed = false;

  AdminProvider({
    AdminRepository? adminRepository,
    VitalinkApi? api,
  })  : _adminRepository = adminRepository ?? AdminRepository(),
        _api = api ?? VitalinkApi() {
    _mode = AppModeProvider.instance.mode;
    loadAdminData();
    if (_mode == AppMode.real) {
      Future.microtask(_loadReal);
    }
  }

  // ---- demo data ------------------------------------------------------
  List<UserModel> get users => _users;
  List<AuditLogModel> get auditLogs => _auditLogs;
  Map<String, int> get metrics => _metrics;
  bool get isLoading => _isLoading;

  // ---- mode -----------------------------------------------------------
  AppMode get mode => _mode;
  bool get isRealMode => _mode == AppMode.real;
  bool get isDemoMode => _mode == AppMode.demo;

  /// Switches the data source.
  ///
  /// Deferred to a microtask because this also runs from the provider's
  /// build phase, where notifying listeners is not allowed.
  void setMode(AppMode mode) {
    if (_mode == mode) return;
    _mode = mode;
    Future.microtask(_applyMode);
  }

  Future<void> _applyMode() async {
    if (_disposed) return;
    if (_mode == AppMode.real) {
      await _loadReal();
    } else {
      _stopReal();
      loadAdminData();
    }
    _notify();
  }

  /// True when the metric is not published by the server and therefore comes
  /// from the simulation.
  bool isSimulatedMetric(String key) => _simulatedMetrics.contains(key);

  // ---- real data ------------------------------------------------------
  /// Every cold-chain device the server knows about.
  List<IotDevice> get devices => _devices;

  /// The open alerts the server raised.
  List<IotAlert> get alerts => _alerts;

  /// The bags reported by the devices.
  List<BloodBagModel> get bags => _bags;

  /// Units per blood group across every device.
  Map<String, int> get stockCounts => _stockCounts;

  /// Devices that reported within the last minute.
  int get onlineDeviceCount => _devices.where((d) => d.online).length;

  String? get realError => _realError;
  String? get actionError => _actionError;
  DateTime? get lastSync => _lastSync;

  /// The server has no endpoint to moderate accounts, so this is only
  /// available in demo mode.
  bool get canModerateUsers => _mode == AppMode.demo;

  void loadAdminData() {
    _users = _adminRepository.allUsers;
    if (_mode == AppMode.real) {
      // The audit trail comes from the server in real mode.
      _simulatedMetrics = {'totalDonors', 'totalRequests', 'averageResponseSec'};
      _metrics = {..._mockMetrics(), ..._realMetrics};
    } else {
      _simulatedMetrics = {
        'totalUsers',
        'totalDonors',
        'totalHospitals',
        'totalUnitsInStock',
        'totalRequests',
        'averageResponseSec',
      };
      _metrics = _mockMetrics();
      _auditLogs = _adminRepository.auditLogs;
    }
    notifyListeners();
  }

  Map<String, int> _mockMetrics() => _adminRepository.getGlobalSystemMetrics();

  /// Reloads the server-backed data.
  Future<void> _loadReal() async {
    if (_disposed) return;
    if (!VitalinkSession.instance.canUseIot) {
      _realError =
          'The VitaLink session has expired. Connect again to use real data.';
      _notify();
      return;
    }
    _isLoading = true;
    _realError = null;
    _notify();
    try {
      final token = VitalinkSession.instance.accessToken!;
      final devices = await _api.devices(token);

      final alerts = <IotAlert>[];
      final bags = <BloodBagModel>[];
      for (final device in devices) {
        try {
          final snapshot = await _api.bags(token, device.id);
          bags.addAll(RealInventoryMapper.bags(
            deviceBags: snapshot.bags,
            device: device,
          ));
        } catch (_) {
          // A device that does not answer must not break the whole view.
        }
      }
      try {
        alerts.addAll(await _api.alerts(token));
      } catch (_) {}

      var auditLogs = <AuditLogModel>[];
      try {
        final rows = await _api.adminAudit(token);
        auditLogs = rows.map(_auditFromServer).toList();
      } catch (_) {
        auditLogs = <AuditLogModel>[];
      }

      if (_disposed) return;
      _devices = devices;
      _alerts = alerts;
      _bags = bags;
      _stockCounts = RealInventoryMapper.groupCounts(bags);
      _auditLogs = auditLogs;
      _realMetrics = {
        'totalDevices': devices.length,
        'onlineDevices': onlineDeviceCount,
        'totalHospitals': devices.map((d) => d.hospitalId).toSet().length,
        'totalUnitsInStock':
            bags.fold<int>(0, (sum, b) => sum + b.units),
        'totalBags': bags.length,
        'openAlerts': alerts.where((a) => a.isOpen).length,
      };
      _lastSync = DateTime.now();
      loadAdminData();
      _startTimer();
    } catch (e) {
      if (_disposed) return;
      _realError = e.toString().replaceAll('Exception: ', '');
    } finally {
      _isLoading = false;
      if (!_disposed) notifyListeners();
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_disposed) return;
      if (_mode != AppMode.real) return;
      _loadReal();
    });
  }

  void _stopReal() {
    _timer?.cancel();
    _timer = null;
    _devices = const [];
    _alerts = const [];
    _bags = const [];
    _stockCounts = const {};
    _realMetrics = const {};
    _realError = null;
    _lastSync = null;
  }

  AuditLogModel _auditFromServer(Map<String, dynamic> row) {
    final details = row['details'];
    final detailText = details is Map
        ? details.entries.map((e) => '${e.key}=${e.value}').join(', ')
        : (details?.toString() ?? '');
    final action = row['action']?.toString() ?? '';
    return AuditLogModel(
      logId: row['id']?.toString() ?? '',
      actorId: row['actor']?.toString() ?? '',
      actorName: row['actor']?.toString() ?? 'system',
      actorRole: 'System',
      action: action,
      entityType: row['entity']?.toString() ?? '',
      entityId: row['entity']?.toString() ?? '',
      details: detailText,
      severity: action.contains('fail') || action.contains('rotate')
          ? 'Warning'
          : 'Info',
      timestamp:
          DateTime.tryParse(row['created_at']?.toString() ?? '') ?? DateTime.now(),
    );
  }

  /// Reloads the server data on demand.
  Future<void> refresh() async {
    if (_mode == AppMode.real) {
      await _loadReal();
    } else {
      loadAdminData();
    }
  }

  Future<void> updateUserStatus(String uid, String status, {String? reason}) async {
    if (_mode == AppMode.real) {
      _actionError =
          'The VitaLink server has no endpoint to moderate accounts, so this '
          'action is only available in demo mode.';
      _notify();
      return;
    }
    _isLoading = true;
    _actionError = null;
    notifyListeners();

    await _adminRepository.setUserStatus(uid: uid, status: status, reason: reason);
    loadAdminData();

    _isLoading = false;
    notifyListeners();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}
