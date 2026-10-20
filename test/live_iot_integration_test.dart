import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_blood_link/providers/app_mode_provider.dart';
import 'package:smart_blood_link/providers/hospital_provider.dart';
import 'package:smart_blood_link/services/vitalink_api.dart';
import 'package:smart_blood_link/services/vitalink_session.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Live end-to-end check against the deployed VitaLink server and the real
/// ESP32 on the network.
///
/// This drives the same provider the Flutter app uses, so it verifies the
/// actual app code path rather than a re-implementation of it.
const _email = 'test.hospital@example.com';
const _password = 'test@123';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late VitalinkApi api;
  HospitalProvider? provider;

  setUp(() async {
    // The test binding replaces HttpClient with one that always returns
    // 400. This suite talks to the real server, so put the real client back.
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({});
    // The provider only reaches for the server in real mode, and it reads
    // the mode when it is built, so the switch has to be on beforehand.
    await AppModeProvider.instance.setMode(AppMode.real);
    api = VitalinkApi();
  });

  tearDown(() async {
    provider?.dispose();
    provider = null;
    await VitalinkSession.instance.clear();
    await AppModeProvider.instance.setMode(AppMode.demo);
  });

  test('real ESP32 shows up in the app provider', () async {
    final login = await api.login(_email, _password);
    await VitalinkSession.instance.setLoginResponse(login);

    provider = HospitalProvider(api: api);
    final p = provider!;

    // Wait for the provider to finish its live connect.
    final deadline = DateTime.now().add(const Duration(seconds: 25));
    while (DateTime.now().isBefore(deadline) &&
        p.dataSource != IotDataSource.live &&
        p.dataSource != IotDataSource.error) {
      await Future.delayed(const Duration(milliseconds: 250));
    }

    expect(p.dataSource, IotDataSource.live,
        reason: 'provider should switch to live. error=${p.liveError}');
    expect(p.devices, isNotEmpty,
        reason: 'the ESP32 should be listed for this hospital');

    final device = p.selectedDevice!;
    print('device      : ${device.id} "${device.name}"');
    print('firmware    : ${device.firmware}');
    print('online      : ${device.online}');
    print('interval    : ${device.uploadIntervalS}s');
    print('thresholds  : ${device.thresholdMin}-${device.thresholdMax} C');
    print('temperature : ${device.temperatureC} C');
    print('weight      : ${device.weightG} g');
    print('bags        : ${device.bagCount}');
    print('security    : ${device.securityEnabled} ${device.securityState}');
    print('rssi        : ${device.wifiRssi}');
    print('ip          : ${device.ip}');

    expect(device.id, 'VL-ESP32-001');
    expect(device.firmware, '2.2.0');
    expect(device.temperatureC, isNotNull,
        reason: 'the server keeps the last reading it received');
    expect(device.tempSensorOk, isTrue);

    if (device.online) {
      expect(p.gatewayOnline, isTrue);
      expect(p.hasTemperature, isTrue);
    } else {
      // The bench device can be powered down between runs. The app must
      // then show the device as offline instead of inventing a reading.
      print('NOTE: the bench device is offline, the live assertions are '
          'skipped');
      print('alerts      : ${p.activeAlerts.map((a) => a.type).toList()}');
    }

    // The device is on the bench at room temperature, so the reading is
    // outside the 2-6 C band. The server has temperature alarms disabled,
    // so the app must NOT show a breach alarm for it.
    print('outOfRange  : ${p.isTempOutOfRange}');
    print('alarmActive : ${p.tempAlarmActive}');
    print('alarmEnabled: ${p.tempAlarmEnabled}');
    expect(p.isTempOutOfRange, isTrue,
        reason: 'room temperature is outside the 2-6 C band');
    expect(p.tempAlarmActive, isFalse,
        reason: 'the server raises no TEMP_BREACH, so the app must not either');
    if (device.online) {
      expect(p.activeAlerts, isEmpty,
          reason: 'no server alerts should be open for the healthy device');
    }
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('temperature alarm policy is readable and togglable from the app',
      () async {
    final login = await api.login(_email, _password);
    await VitalinkSession.instance.setLoginResponse(login);

    provider = HospitalProvider(api: api);
    final p = provider!;

    final deadline = DateTime.now().add(const Duration(seconds: 25));
    while (DateTime.now().isBefore(deadline) &&
        p.dataSource != IotDataSource.live) {
      await Future.delayed(const Duration(milliseconds: 250));
    }
    expect(p.dataSource, IotDataSource.live);

    // The server exposes the per-device policy, and the app can read it.
    expect(p.selectedDevice!.tempAlarmEnabled, isFalse,
        reason: 'alarms are disabled for the bench device');
    expect(p.tempAlarmEnabled, isFalse);

    // Turn it on and back off again through the provider.
    expect(await p.setTempAlarmEnabled(true), isTrue);
    expect(p.tempAlarmEnabled, isTrue,
        reason: 'the provider should reflect the new policy');
    expect(await p.setTempAlarmEnabled(false), isTrue);
    expect(p.tempAlarmEnabled, isFalse);
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('live WebSocket pushes telemetry into the provider', () async {
    final login = await api.login(_email, _password);
    await VitalinkSession.instance.setLoginResponse(login);

    provider = HospitalProvider(api: api);
    final p = provider!;

    final deadline = DateTime.now().add(const Duration(seconds: 25));
    while (DateTime.now().isBefore(deadline) &&
        p.dataSource != IotDataSource.live) {
      await Future.delayed(const Duration(milliseconds: 250));
    }
    expect(p.dataSource, IotDataSource.live);

    final before = p.currentTemperature;
    final beforeReadings = p.recentReadings.length;

    if (!(p.selectedDevice?.online ?? false)) {
      print('NOTE: the bench device is offline, no telemetry can arrive. '
          'The realtime path is skipped.');
      return;
    }

    // The ESP32 uploads every 3 s, so telemetry should arrive on its own.
    final changed = Completer<void>();
    final poll = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (p.recentReadings.length > beforeReadings ||
          p.currentTemperature != before) {
        if (!changed.isCompleted) changed.complete();
      }
    });

    await changed.future.timeout(const Duration(seconds: 30),
        onTimeout: () => fail('no live telemetry arrived within 30s'));
    poll.cancel();

    print('telemetry pushed: temp $before -> ${p.currentTemperature}');
    print('readings        : $beforeReadings -> ${p.recentReadings.length}');
    expect(p.recentReadings.length, greaterThan(beforeReadings));
  }, timeout: const Timeout(Duration(seconds: 90)));
}
