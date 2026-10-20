import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/iot_models.dart';

class VitalinkApiException implements Exception {
  final String message;
  final int? status;

  VitalinkApiException(this.message, {this.status});

  bool get isUnauthorized => status == 401 || status == 403;

  @override
  String toString() => message;
}

class BagSnapshot {
  final int count;
  final Map<String, int> groups;
  final List<DeviceBag> bags;

  BagSnapshot({required this.count, required this.groups, required this.bags});
}

class VitalinkApi {
  final http.Client _client;
  VitalinkApi({http.Client? client}) : _client = client ?? http.Client();

  Uri _uri(String path) => Uri.parse('${ApiConfig.baseUrl}$path');

  Map<String, String> _headers([String? token]) => {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  Future<dynamic> _send(
    String method,
    String path, {
    String? token,
    Map<String, dynamic>? body,
  }) async {
    late http.Response res;
    try {
      final uri = _uri(path);
      switch (method) {
        case 'GET':
          res = await _client
              .get(uri, headers: _headers(token))
              .timeout(ApiConfig.timeout);
          break;
        case 'POST':
          res = await _client
              .post(uri,
                  headers: _headers(token), body: body == null ? null : jsonEncode(body))
              .timeout(ApiConfig.timeout);
          break;
        default:
          throw VitalinkApiException('Unsupported method $method');
      }
    } on VitalinkApiException {
      rethrow;
    } catch (_) {
      throw VitalinkApiException(
          'Cannot reach the VitaLink server. Check the connection.');
    }

    if (res.statusCode == 401 || res.statusCode == 403) {
      throw VitalinkApiException('Server session expired or not allowed.',
          status: res.statusCode);
    }
    if (res.statusCode == 429) {
      throw VitalinkApiException('Server busy, please try again shortly.',
          status: 429);
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      String msg = 'Server error (${res.statusCode})';
      try {
        final decoded = jsonDecode(res.body);
        if (decoded is Map && decoded['error'] != null) {
          msg = decoded['error'].toString();
        }
      } catch (_) {}
      throw VitalinkApiException(msg, status: res.statusCode);
    }
    if (res.body.isEmpty) return null;
    try {
      return jsonDecode(res.body);
    } catch (_) {
      throw VitalinkApiException('Malformed server response.');
    }
  }

  Future<Map<String, dynamic>> login(String email, String password) async {
    final data = await _send('POST', '/auth/login',
        body: {'email': email.trim(), 'password': password});
    if (data is! Map) throw VitalinkApiException('Malformed login response.');
    return data.cast<String, dynamic>();
  }

  Future<Map<String, dynamic>> refresh(String refreshToken) async {
    final data = await _send('POST', '/auth/refresh',
        body: {'refreshToken': refreshToken});
    if (data is! Map) throw VitalinkApiException('Malformed refresh response.');
    return data.cast<String, dynamic>();
  }

  Future<List<IotDevice>> devices(String token) async {
    final data = await _send('GET', '/v1/devices', token: token);
    if (data is! List) throw VitalinkApiException('Malformed device list.');
    return data
        .whereType<Map>()
        .map((e) => IotDevice.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  Future<IotDevice> device(String token, String id) async {
    final data = await _send('GET', '/v1/devices/$id', token: token);
    if (data is! Map) throw VitalinkApiException('Malformed device response.');
    return IotDevice.fromJson(data.cast<String, dynamic>());
  }

  Future<List<TelemetryPoint>> history(
    String token,
    String id, {
    String range = '1h',
  }) async {
    final data =
        await _send('GET', '/v1/devices/$id/history?range=$range', token: token);
    if (data is! List) return const [];
    return data
        .whereType<Map>()
        .map((e) => TelemetryPoint.fromHistoryJson(e.cast<String, dynamic>()))
        .toList();
  }

  Future<BagSnapshot> bags(String token, String id) async {
    final data = await _send('GET', '/v1/devices/$id/bags', token: token);
    if (data is! Map) return BagSnapshot(count: 0, groups: {}, bags: []);
    final rawGroups = (data['groups'] as Map?) ?? const {};
    final groups = rawGroups.map(
        (k, v) => MapEntry(k.toString(), v is num ? v.toInt() : 0));
    final list = (data['bags'] as List?) ?? const [];
    return BagSnapshot(
      count: (data['count'] as num?)?.toInt() ?? list.length,
      groups: groups,
      bags: list
          .whereType<Map>()
          .map((e) => DeviceBag.fromJson(e.cast<String, dynamic>()))
          .toList(),
    );
  }

  Future<List<IotAlert>> alerts(String token, {String status = 'OPEN'}) async {
    final data = await _send('GET', '/v1/alerts?status=$status', token: token);
    if (data is! List) return const [];
    return data
        .whereType<Map>()
        .map((e) => IotAlert.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  Future<void> ackAlert(String token, String id) async {
    await _send('POST', '/v1/alerts/$id/ack', token: token);
  }

  Future<Map<String, dynamic>> sendCommand(
    String token,
    String deviceId,
    String type, [
    Map<String, dynamic> payload = const {},
  ]) async {
    final data = await _send('POST', '/v1/devices/$deviceId/commands',
        token: token, body: {'type': type, 'payload': payload});
    if (data is! Map) return {};
    return data.cast<String, dynamic>();
  }

  /// Turns the server-side temperature breach alarm on or off for a device.
  ///
  /// Telemetry keeps being stored either way; only the alert is affected.
  Future<bool> setTempAlarmEnabled(
    String token,
    String deviceId,
    bool enabled,
  ) async {
    final data = await _send('POST', '/v1/devices/$deviceId/temp-alarm',
        token: token, body: {'enabled': enabled});
    return data is Map && data['temp_alarm_enabled'] == enabled;
  }

  /// The server audit trail. Admin only.
  Future<List<Map<String, dynamic>>> adminAudit(String token) async {
    final data = await _send('GET', '/v1/admin/audit', token: token);
    if (data is! List) return const [];
    return data
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList();
  }
}
