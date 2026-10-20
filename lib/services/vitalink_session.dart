import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'vitalink_api.dart';

/// Holds the short-lived VitaLink access token and the refresh token.
///
/// The server issues 30-minute access tokens and single-use refresh tokens.
/// Call [ensureValid] before every authenticated call; it refreshes when
/// the token is within 30 seconds of expiring.
class VitalinkSession extends ChangeNotifier {
  VitalinkSession._();
  static final VitalinkSession instance = VitalinkSession._();

  static const _kAccess = 'vl_access_token';
  static const _kRefresh = 'vl_refresh_token';
  static const _kExpiry = 'vl_expires_at_ms';
  static const _kUser = 'vl_user_json';

  final VitalinkApi _api = VitalinkApi();

  String? _accessToken;
  String? _refreshToken;
  DateTime? _expiresAt;
  Map<String, dynamic>? _user;
  bool _restored = false;

  String? get accessToken => _accessToken;
  Map<String, dynamic>? get user => _user;
  String? get userId => _user?['id']?.toString();
  String? get userName => _user?['name']?.toString();
  String? get role => _user?['role']?.toString();
  String? get hospitalId => _user?['hospitalId']?.toString();

  bool get isHospitalOrAdmin => role == 'hospital' || role == 'admin';
  bool get hasToken => _accessToken != null && _accessToken!.isNotEmpty;
  bool get isAuthenticated =>
      hasToken && (_expiresAt?.isAfter(DateTime.now()) ?? true);

  bool get canUseIot => isHospitalOrAdmin && isAuthenticated;

  Future<bool> restore() async {
    if (_restored) return isAuthenticated;
    _restored = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      _accessToken = prefs.getString(_kAccess);
      _refreshToken = prefs.getString(_kRefresh);
      final ms = prefs.getInt(_kExpiry);
      _expiresAt = ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
      final raw = prefs.getString(_kUser);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) _user = decoded.cast<String, dynamic>();
      }
    } catch (_) {
      await clear();
      return false;
    }

    if (!hasToken) return false;
    if (isAuthenticated) {
      notifyListeners();
      return true;
    }
    return ensureValid();
  }

  Future<void> setLoginResponse(Map<String, dynamic> res) async {
    _accessToken = res['accessToken']?.toString();
    final newRefresh = res['refreshToken']?.toString();
    if (newRefresh != null && newRefresh.isNotEmpty) _refreshToken = newRefresh;
    final expiresIn = res['expiresInS'];
    _expiresAt = DateTime.now()
        .add(Duration(seconds: expiresIn is num ? expiresIn.toInt() : 1800));
    final u = res['user'];
    if (u is Map) _user = u.cast<String, dynamic>();
    await _persist();
    notifyListeners();
  }

  /// Refreshes if the access token is missing or about to expire.
  Future<bool> ensureValid() async {
    if (!hasToken) return false;
    final expires = _expiresAt;
    if (expires != null &&
        expires.isAfter(DateTime.now().add(const Duration(seconds: 30)))) {
      return true;
    }
    final rt = _refreshToken;
    if (rt == null || rt.isEmpty) {
      await clear();
      return false;
    }
    try {
      final res = await _api.refresh(rt);
      await setLoginResponse(res);
      return true;
    } catch (_) {
      await clear();
      return false;
    }
  }

  Future<void> clear() async {
    _accessToken = null;
    _refreshToken = null;
    _expiresAt = null;
    _user = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kAccess);
      await prefs.remove(_kRefresh);
      await prefs.remove(_kExpiry);
      await prefs.remove(_kUser);
    } catch (_) {}
    notifyListeners();
  }

  Future<void> logout() => clear();

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_accessToken != null) await prefs.setString(_kAccess, _accessToken!);
      if (_refreshToken != null) {
        await prefs.setString(_kRefresh, _refreshToken!);
      }
      if (_expiresAt != null) {
        await prefs.setInt(_kExpiry, _expiresAt!.millisecondsSinceEpoch);
      }
      if (_user != null) await prefs.setString(_kUser, jsonEncode(_user));
    } catch (_) {}
  }
}
