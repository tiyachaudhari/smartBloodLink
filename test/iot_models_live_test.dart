import 'package:flutter_test/flutter_test.dart';
import 'package:smart_blood_link/models/iot_models.dart';

/// Parsing checks against the exact shapes the deployed server returns.
///
/// PostgreSQL numeric columns (`threshold_min`, history `temp`, ...) come back
/// as JSON strings, while `real` columns come back as JSON numbers. Both must
/// parse, otherwise the live chart loses every history point.
void main() {
  group('Live IoT model parsing', () {
    test('device thresholds accept numeric strings', () {
      final device = IotDevice.fromJson({
        'id': 'VL-ESP32-001',
        'hospital_id': '1e284613-f15a-4777-8427-559e75fb330f',
        'name': 'Blood Fridge 1',
        'storage_unit': 'Ward A',
        'fw': 'soak-1.0',
        'wifi_rssi': -55,
        'ip': '192.168.1.50',
        'last_seen_at': '2026-10-20T07:17:21.352Z',
        'threshold_min': '2.0',
        'threshold_max': '6.0',
        'upload_interval_s': 3,
        'latest': {
          'temperatureC': 4.2,
          'tempSensorOk': true,
          'bagCount': 1,
          'bagRevision': 'A1B2C3D4',
          'groups': {'O+': 1},
          'security': {'enabled': false, 'state': 'OFF', 'graceLeftS': 0},
          'rfid': {'readerOk': true, 'lastUid': 'A1 B2 C3 D4'},
        },
      });

      expect(device.thresholdMin, 2.0);
      expect(device.thresholdMax, 6.0);
      expect(device.uploadIntervalS, 3);
      expect(device.temperatureC, 4.2);
      expect(device.isSafeBand(device.thresholdMin, device.thresholdMax), true);
      expect(device.groups['O+'], 1);
      expect(device.rfidUid, 'A1 B2 C3 D4');
    });

    test('history parses string and null payloads', () {
      final point = TelemetryPoint.fromHistoryJson({
        't': '2026-10-20T06:32:00.000Z',
        'temp': '4.30',
        'tmin': '4.30',
        'tmax': '4.30',
        'weight_g': null,
      });
      expect(point.temperatureC, 4.30);
      expect(point.tempMinC, 4.30);
      expect(point.weightG, isNull);

      final weighed = TelemetryPoint.fromHistoryJson({
        't': '2026-10-20T06:33:00.000Z',
        'temp': '4.20',
        'weight_g': 132,
      });
      expect(weighed.temperatureC, 4.20);
      expect(weighed.weightG, 132.0);
    });

    test('bag snapshot and alerts parse', () {
      final bag = DeviceBag.fromJson({
        'uid': 'A1 B2 C3 D4',
        'group': 'O+',
        'expiry': '2026-11-18T00:00:00.000Z',
        'updated_at': '2026-10-20T07:09:46.937Z',
      });
      expect(bag.group, 'O+');
      expect(bag.expiry?.year, 2026);
      expect(bag.expiry?.month, 11);
      expect(bag.expiry?.day, 18);

      final alert = IotAlert.fromJson({
        'id': '55',
        'device_id': 'VL-ESP32-001',
        'type': 'DEVICE_OFFLINE',
        'severity': 'critical',
        'message': 'device offline',
        'status': 'RESOLVED',
        'opened_at': '2026-10-20T06:00:00.000Z',
        'resolved_at': '2026-10-20T06:10:00.000Z',
      });
      expect(alert.id, '55');
      expect(alert.isCritical, true);
      expect(alert.isOpen, false);
      expect(alert.resolvedAt, isNotNull);
    });
  });
}
