import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_blood_link/providers/app_mode_provider.dart';
import 'package:smart_blood_link/providers/hospital_provider.dart';
import 'package:smart_blood_link/services/vitalink_api.dart';
import 'package:smart_blood_link/services/vitalink_session.dart';
import 'package:smart_blood_link/services/vitalink_socket.dart';

/// Tests for the Demo/Real switch inside the hospital provider.
///
/// No real network is touched: the API client is a [MockClient] that answers
/// with the exact payloads the VitaLink server returns, and the realtime
/// socket is replaced by a fake so nothing tries to open a websocket.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeVitalinkServer server;
  HospitalProvider? provider;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await VitalinkSession.instance.clear();
    await AppModeProvider.instance.setMode(AppMode.demo);
    server = FakeVitalinkServer();
  });

  tearDown(() async {
    provider?.dispose();
    provider = null;
    await VitalinkSession.instance.clear();
    await AppModeProvider.instance.setMode(AppMode.demo);
  });

  HospitalProvider buildProvider() => HospitalProvider(
        api: VitalinkApi(client: server.client),
        socketFactory: fakeSocketFactory,
      );

  group('HospitalProvider demo mode', () {
    test('demo mode serves the bundled inventory and never calls the server',
        () async {
      provider = buildProvider();
      final p = provider!;

      expect(p.mode, AppMode.demo);
      expect(p.isDemoMode, isTrue);
      expect(p.isRealMode, isFalse);
      expect(p.dataSource, IotDataSource.demo);
      expect(p.bags.length, 6,
          reason: 'demo mode shows the bundled mock inventory');
      expect(p.stockCounts, isNotEmpty);
      expect(p.totalUnits, greaterThan(0));
      expect(server.requestCount, 0,
          reason: 'demo mode must not talk to the server');

      // Asking for the mode that is already active changes nothing.
      p.setMode(AppMode.demo);
      await Future.delayed(const Duration(milliseconds: 200));

      expect(p.dataSource, IotDataSource.demo);
      expect(p.bags.length, 6);
      expect(p.stockCounts, isNotEmpty);
      expect(server.requestCount, 0);
    });
  });

  group('HospitalProvider real mode', () {
    test('real mode without a session reports an error', () async {
      await AppModeProvider.instance.setMode(AppMode.real);
      provider = buildProvider();
      final p = provider!;

      await _waitFor(() => p.dataSource == IotDataSource.error);

      expect(p.mode, AppMode.real);
      expect(p.dataSource, IotDataSource.error);
      expect(p.liveError, isNotNull,
          reason: 'the user has to be told why there is no live data');
    });

    test('real mode serves the server inventory', () async {
      await _login();
      await AppModeProvider.instance.setMode(AppMode.real);
      provider = buildProvider();
      final p = provider!;

      await _waitFor(() => p.dataSource == IotDataSource.live);

      expect(p.dataSource, IotDataSource.live,
          reason: 'the provider should switch to live. error=${p.liveError}');
      expect(p.isRealMode, isTrue);

      // ---- devices -----------------------------------------------------
      expect(p.devices.length, 1);
      expect(p.selectedDevice, isNotNull);
      expect(p.selectedDevice!.firmware, '2.2.0');
      expect(p.selectedDeviceId, 'VL-ESP32-001');

      // ---- telemetry ---------------------------------------------------
      expect(p.hasTemperature, isTrue);
      expect(p.currentTemperature, 4.5);

      // ---- inventory ---------------------------------------------------
      expect(p.bags.length, 2,
          reason: 'real mode shows the bags the server reported, not the '
              'bundled mock inventory');
      expect(p.bags.every((b) => b.serverBacked), isTrue);

      final withExpiry = p.bags.firstWhere((b) => b.bloodGroup == 'O+');
      final withoutExpiry = p.bags.firstWhere((b) => b.bloodGroup == 'A+');
      expect(withExpiry.expiryKnown, isTrue);
      expect(withExpiry.collectionDateKnown, isTrue);
      expect(withoutExpiry.expiryKnown, isFalse,
          reason: 'the server sent no expiry, so the app must not invent one');
      expect(withoutExpiry.collectionDateKnown, isFalse);

      expect(p.stockCounts['O+'], 1);
      expect(p.stockCounts['A+'], 1);
      for (final group in ['A-', 'B+', 'B-', 'AB+', 'AB-', 'O-']) {
        expect(p.stockCounts[group], 0,
            reason: '$group was not reported by the server');
      }
      expect(p.totalUnits, 2);

      expect(server.requestCount, greaterThan(0),
          reason: 'real mode must use the server');
    });

    test('switching back to demo restores the bundled inventory', () async {
      await _login();
      await AppModeProvider.instance.setMode(AppMode.real);
      provider = buildProvider();
      final p = provider!;

      await _waitFor(() => p.dataSource == IotDataSource.live);
      expect(p.bags.length, 2);

      p.setMode(AppMode.demo);
      await _waitFor(() => p.dataSource == IotDataSource.demo);

      expect(p.mode, AppMode.demo);
      expect(p.dataSource, IotDataSource.demo);
      expect(p.bags.length, 6,
          reason: 'the mock inventory is back after leaving real mode');
      expect(p.devices, isEmpty,
          reason: 'the live devices must not leak into demo mode');
      expect(p.selectedDevice, isNull);
    });
  });
}

/// Logs a test user in so the provider may talk to the server.
Future<void> _login() {
  return VitalinkSession.instance.setLoginResponse({
    'accessToken': 'tok',
    'refreshToken': 'ref',
    'expiresInS': 3600,
    'user': {'id': 'u', 'role': 'hospital', 'hospitalId': 'h'},
  });
}

/// Waits until [condition] holds or the timeout expires.
Future<void> _waitFor(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition() && DateTime.now().isBefore(deadline)) {
    await Future.delayed(const Duration(milliseconds: 50));
  }
}

/// A socket that never opens a real connection.
class FakeSocket extends VitalinkSocket {
  FakeSocket({
    required void Function(Map<String, dynamic>) onEvent,
    void Function(String?)? onClosed,
  }) : super(onEvent: onEvent, onClosed: onClosed);

  @override
  Future<bool> connect(String token) async => true;

  @override
  Future<void> dispose() async {}
}

/// Builds the fake socket the provider uses instead of a real websocket.
VitalinkSocket fakeSocketFactory({
  required void Function(Map<String, dynamic>) onEvent,
  required void Function(String?) onClosed,
}) =>
    FakeSocket(onEvent: onEvent, onClosed: onClosed);

/// A stand-in for the VitaLink server.
///
/// Every request is counted, so a test can prove that demo mode never
/// reaches out to the network.
class FakeVitalinkServer {
  final List<String> requestedPaths = [];

  int get requestCount => requestedPaths.length;

  http.Client get client => MockClient((request) async {
        requestedPaths.add(request.url.path);
        switch (request.url.path) {
          case '/v1/devices':
            return http.Response(jsonEncode([_deviceJson()]), 200);
          case '/v1/devices/VL-ESP32-001':
            return http.Response(jsonEncode(_deviceJson()), 200);
          case '/v1/devices/VL-ESP32-001/bags':
            return http.Response(jsonEncode(_bagsJson()), 200);
          case '/v1/devices/VL-ESP32-001/history':
            return http.Response('[]', 200);
          case '/v1/alerts':
            return http.Response('[]', 200);
          default:
            return http.Response('{}', 200);
        }
      });

  static Map<String, dynamic> _deviceJson() => {
        'id': 'VL-ESP32-001',
        'hospital_id': 'h',
        'name': 'Test Fridge',
        'storage_unit': 'Cold Unit A',
        'fw': '2.2.0',
        'last_seen_at': DateTime.now().toUtc().toIso8601String(),
        'wifi_rssi': -60,
        'ip': '10.0.0.5',
        'threshold_min': 2.0,
        'threshold_max': 6.0,
        'upload_interval_s': 3,
        'temp_alarm_enabled': false,
        'latest': {
          'temperatureC': 4.5,
          'tempSensorOk': true,
          'weightG': 120.0,
          'bagCount': 2,
          'groups': {'O+': 1, 'A+': 1},
        },
        'latest_at': DateTime.now().toUtc().toIso8601String(),
      };

  /// The second bag has no expiry on purpose: the app must show a dash
  /// instead of an invented date.
  static Map<String, dynamic> _bagsJson() => {
        'count': 2,
        'groups': {'O+': 1, 'A+': 1},
        'bags': [
          {'uid': 'RFID-1', 'group': 'O+', 'expiry': '2030-01-01'},
          {'uid': 'RFID-2', 'group': 'A+'},
        ],
      };
}
