import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_blood_link/providers/admin_provider.dart';
import 'package:smart_blood_link/providers/app_mode_provider.dart';
import 'package:smart_blood_link/services/vitalink_api.dart';
import 'package:smart_blood_link/services/vitalink_session.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Live check of the admin real-mode path against the deployed VitaLink
/// server.
///
/// It drives the same provider the Flutter app uses, so it verifies the
/// actual app code path rather than a re-implementation of it.
const _email = 'demo.admin@bloodlink.org';
const _password = 'DemoAdmin@2026';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late VitalinkApi api;
  AdminProvider? provider;

  setUp(() async {
    // The test binding replaces HttpClient with one that always returns
    // 400. This suite talks to the real server, so put the real client back.
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({});
    api = VitalinkApi();
    await AppModeProvider.instance.setMode(AppMode.real);
  });

  tearDown(() async {
    provider?.dispose();
    provider = null;
    await VitalinkSession.instance.clear();
    await AppModeProvider.instance.setMode(AppMode.demo);
  });

  test('admin real mode reads devices, alerts and audit from the server',
      () async {
    final login = await api.login(_email, _password);
    await VitalinkSession.instance.setLoginResponse(login);

    provider = AdminProvider(api: api);
    final p = provider!;

    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (DateTime.now().isBefore(deadline) &&
        p.metrics['totalDevices'] == null) {
      await Future.delayed(const Duration(milliseconds: 250));
    }

    print('mode        : ${p.mode}');
    print('devices     : ${p.devices.length}');
    print('online      : ${p.onlineDeviceCount}');
    print('alerts      : ${p.alerts.length}');
    print('audit rows  : ${p.auditLogs.length}');
    print('bags        : ${p.bags.length}');
    print('stock       : ${p.stockCounts}');
    print('metrics     : ${p.metrics}');
    print('lastSync    : ${p.lastSync}');
    print('realError   : ${p.realError}');

    expect(p.isRealMode, isTrue);
    expect(p.realError, isNull);
    expect(p.devices, isNotEmpty,
        reason: 'the admin must see the cold-chain devices');
    expect(p.metrics['totalDevices'], p.devices.length);
    expect(p.auditLogs, isNotEmpty,
        reason: 'the server publishes an audit trail');
    expect(p.auditLogs.first.action, isNotEmpty);
    expect(p.lastSync, isNotNull);

    // The server does not publish account moderation, so the app must not
    // pretend it can moderate accounts in real mode.
    expect(p.canModerateUsers, isFalse);
  }, timeout: const Timeout(Duration(seconds: 90)));
}
