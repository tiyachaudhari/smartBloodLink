/// Live VitaLink server models.
///
/// These mirror the JSON returned by `/v1/*`. They deliberately keep the
/// raw `latest` map so new firmware fields are available without an app
/// release.
library;

// PostgreSQL numeric/bigint columns arrive as JSON strings ("4.30"), while
// real columns arrive as JSON numbers, so accept both.
double? _d(dynamic v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}

int? _i(dynamic v) {
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? double.tryParse(v)?.toInt();
  return null;
}

DateTime? _t(dynamic v) =>
    v is String ? DateTime.tryParse(v)?.toLocal() : null;

/// Expiry is a calendar date, not an instant. The server serialises midnight
/// UTC, so converting to local time can display the previous day in negative
/// UTC offsets. Keep the date components exactly as sent.
DateTime? _date(dynamic v) {
  if (v is! String) return null;
  final d = DateTime.tryParse(v);
  if (d == null) return null;
  return DateTime(d.year, d.month, d.day);
}

class IotDevice {
  final String id;
  final String hospitalId;
  final String name;
  final String storageUnit;
  final String firmware;
  final int uploadIntervalS;
  final double thresholdMin;
  final double thresholdMax;

  /// Whether the server raises a breach alert for an out-of-range reading.
  ///
  /// The server owns alarm policy, so the app must not invent its own
  /// breach state. When this is off the reading is still shown and charted,
  /// it just does not raise an alarm.
  final bool tempAlarmEnabled;
  final int? wifiRssi;
  final String? ip;
  final DateTime? lastSeenAt;
  final DateTime? latestAt;
  final Map<String, dynamic> latest;

  IotDevice({
    required this.id,
    required this.hospitalId,
    required this.name,
    required this.storageUnit,
    required this.firmware,
    required this.uploadIntervalS,
    required this.thresholdMin,
    required this.thresholdMax,
    this.tempAlarmEnabled = true,
    this.wifiRssi,
    this.ip,
    this.lastSeenAt,
    this.latestAt,
    this.latest = const {},
  });

  factory IotDevice.fromJson(Map<String, dynamic> json) {
    final latest = (json['latest'] as Map?)?.cast<String, dynamic>() ?? {};
    return IotDevice(
      id: json['id']?.toString() ?? '',
      hospitalId: json['hospital_id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Blood fridge',
      storageUnit: json['storage_unit']?.toString() ?? '',
      firmware: (latest['fw'] ?? json['fw'] ?? '').toString(),
      uploadIntervalS: _i(json['upload_interval_s']) ?? 3,
      thresholdMin: _d(json['threshold_min']) ?? 2.0,
      thresholdMax: _d(json['threshold_max']) ?? 6.0,
      tempAlarmEnabled: json['temp_alarm_enabled'] != false,
      wifiRssi: _i(json['wifi_rssi']) ?? _i(latest['wifiRssi']),
      ip: json['ip']?.toString() ?? latest['ip']?.toString(),
      lastSeenAt: _t(json['last_seen_at']),
      latestAt: _t(json['latest_at']) ?? _t(latest['recordedAt']),
      latest: latest,
    );
  }

  bool get online {
    final seen = lastSeenAt;
    if (seen == null) return false;
    return DateTime.now().difference(seen).inSeconds <= 15;
  }

  bool get tempSensorOk => latest['tempSensorOk'] == true;
  double? get temperatureC => _d(latest['temperatureC']);
  double? get tempMinC => _d(latest['tempMinC']);
  double? get tempMaxC => _d(latest['tempMaxC']);
  double? get weightG => _d(latest['weightG']);
  int get bagCount => _i(latest['bagCount']) ?? 0;
  String get bagRevision => latest['bagRevision']?.toString() ?? '';
  bool get scaleFault => latest['scaleFault'] == true;
  bool get scaleCalibrated => latest['scaleCalibrated'] == true;

  Map<String, dynamic> get security =>
      (latest['security'] as Map?)?.cast<String, dynamic>() ?? const {};
  bool get securityEnabled => security['enabled'] == true;
  String get securityState => security['state']?.toString() ?? 'OFF';
  num? get graceLeftS => security['graceLeftS'] as num?;

  Map<String, dynamic> get rfid =>
      (latest['rfid'] as Map?)?.cast<String, dynamic>() ?? const {};
  bool get rfidReaderOk => rfid['readerOk'] == true;
  String? get rfidUid => rfid['lastUid']?.toString();

  Map<String, int> get groups {
    final raw = (latest['groups'] as Map?)?.cast<String, dynamic>() ?? {};
    return raw.map((k, v) => MapEntry(k, _i(v) ?? 0));
  }

  bool isSafeBand(double min, double max) {
    final t = temperatureC;
    return tempSensorOk && t != null && t >= min && t <= max;
  }

  IotDevice copyWithLatest(Map<String, dynamic> patch) {
    return IotDevice(
      id: id,
      hospitalId: hospitalId,
      name: name,
      storageUnit: storageUnit,
      firmware: firmware,
      uploadIntervalS: uploadIntervalS,
      thresholdMin: thresholdMin,
      thresholdMax: thresholdMax,
      tempAlarmEnabled: tempAlarmEnabled,
      wifiRssi: wifiRssi,
      ip: ip,
      lastSeenAt: lastSeenAt,
      latestAt: latestAt,
      latest: {...latest, ...patch},
    );
  }
}

class DeviceBag {
  final String uid;
  final String group;
  final DateTime? expiry;
  final DateTime? updatedAt;

  DeviceBag({required this.uid, required this.group, this.expiry, this.updatedAt});

  factory DeviceBag.fromJson(Map<String, dynamic> json) => DeviceBag(
        uid: json['uid']?.toString() ?? '',
        group: json['group']?.toString() ?? '?',
        expiry: _date(json['expiry']),
        updatedAt: _t(json['updated_at']),
      );
}

class IotAlert {
  final String id;
  final String deviceId;
  final String type;
  final String severity;
  final String message;
  final String status;
  final DateTime? openedAt;
  final DateTime? resolvedAt;
  final DateTime? ackedAt;

  IotAlert({
    required this.id,
    required this.deviceId,
    required this.type,
    required this.severity,
    required this.message,
    required this.status,
    this.openedAt,
    this.resolvedAt,
    this.ackedAt,
  });

  factory IotAlert.fromJson(Map<String, dynamic> json) => IotAlert(
        id: json['id']?.toString() ?? '',
        deviceId: json['device_id']?.toString() ?? '',
        type: json['type']?.toString() ?? '',
        severity: json['severity']?.toString() ?? 'warning',
        message: json['message']?.toString() ?? '',
        status: json['status']?.toString() ?? 'OPEN',
        openedAt: _t(json['opened_at']),
        resolvedAt: _t(json['resolved_at']),
        ackedAt: _t(json['acked_at']),
      );

  bool get isCritical => severity == 'critical';
  bool get isOpen => status == 'OPEN';
}

class TelemetryPoint {
  final DateTime t;
  final double? temperatureC;
  final double? tempMinC;
  final double? tempMaxC;
  final double? weightG;

  TelemetryPoint({
    required this.t,
    this.temperatureC,
    this.tempMinC,
    this.tempMaxC,
    this.weightG,
  });

  factory TelemetryPoint.fromHistoryJson(Map<String, dynamic> json) =>
      TelemetryPoint(
        t: DateTime.tryParse(json['t']?.toString() ?? '')?.toLocal() ??
            DateTime.now(),
        temperatureC: _d(json['temp']),
        tempMinC: _d(json['tmin']),
        tempMaxC: _d(json['tmax']),
        weightG: _d(json['weight_g']),
      );
}
