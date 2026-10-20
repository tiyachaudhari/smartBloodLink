import 'dart:async';

import 'package:flutter/material.dart';

import '../models/inventory_item_model.dart';
import '../models/iot_models.dart';
import '../models/iot_sensor_model.dart';
import '../repositories/inventory_repository.dart';
import '../repositories/iot_repository.dart';
import '../services/real_inventory_mapper.dart';
import '../services/rfid_service.dart';
import '../services/vitalink_api.dart';
import '../services/vitalink_session.dart';
import '../services/vitalink_socket.dart';
import '../utils/constants.dart';
import 'app_mode_provider.dart';

enum IotDataSource { demo, connecting, live, error }

/// Hospital Staff ViewModel.
///
/// The app-wide [AppMode] decides where the data comes from. In demo mode
/// the inventory and the cold-chain telemetry stay on the bundled simulation.
/// In real mode the telemetry, the bag list and the alerts come from the
/// VitaLink server, and only the modules the server does not cover keep
/// their simulated data.
class HospitalProvider with ChangeNotifier {
  final InventoryRepository _inventoryRepository;
  final IotRepository _iotRepository;
  final RfidService _rfidService;
  final VitalinkApi _api;

  /// Builds the realtime socket. Tests inject a fake so they never open a
  /// real connection.
  final VitalinkSocket Function({
    required void Function(Map<String, dynamic>) onEvent,
    required void Function(String?) onClosed,
  })? _socketFactory;

  List<BloodBagModel> _bags = [];
  Map<String, int> _stockCounts = {};
  List<String> _lowStockGroups = [];
  BloodBagModel? _lastScannedBag;
  bool _isScanning = false;
  String? _scanError;

  // ---- mode ----------------------------------------------------------
  AppMode _mode = AppMode.demo;

  /// Server-backed inventory, built from the device bag list.
  List<BloodBagModel> _realBags = const [];
  Map<String, int> _realStockCounts = const {};
  List<String> _realLowStock = const [];

  // ---- demo mode -----------------------------------------------------
  double _currentTemp = 4.0;
  bool _isTempSafe = true;
  bool _hasTemperature = true;
  String? _tempAlertMessage;
  bool _demoSubscribed = false;

  // ---- live VitaLink state ------------------------------------------
  VitalinkSocket? _socket;
  IotDataSource _source = IotDataSource.demo;
  String? _liveError;
  DateTime? _lastSync;
  bool _socketConnected = false;
  bool _starting = false;
  bool _disposed = false;
  String? _selectedDeviceId;
  List<IotDevice> _devices = [];
  List<SensorReading> _readings = [];
  String? _lastSampleId;
  List<IotAlert> _alerts = [];
  List<DeviceBag> _deviceBags = [];
  Map<String, int> _liveGroups = {};
  double? _weightG;
  int _bagCount = 0;
  bool _securityEnabled = false;
  String _securityState = 'OFF';
  bool _rfidReaderOk = false;
  String? _rfidUid;
  int? _wifiRssi;
  String? _ipAddress;
  double _thresholdMin = 2.0;
  double _thresholdMax = 6.0;

  Timer? _pollTimer;
  Timer? _alertsTimer;
  Timer? _reconnectTimer;

  HospitalProvider({
    InventoryRepository? inventoryRepository,
    IotRepository? iotRepository,
    RfidService? rfidService,
    VitalinkApi? api,
    VitalinkSocket Function({
      required void Function(Map<String, dynamic>) onEvent,
      required void Function(String?) onClosed,
    })? socketFactory,
  })  : _inventoryRepository = inventoryRepository ?? InventoryRepository(),
        _iotRepository = iotRepository ?? IotRepository(),
        _rfidService = rfidService ?? RfidService(),
        _api = api ?? VitalinkApi(),
        _socketFactory = socketFactory {
    _mode = AppModeProvider.instance.mode;
    if (_mode == AppMode.real) {
      // The simulation must not drift in the background while the app shows
      // real server data.
      _iotRepository.pause();
    }
    _loadHospitalData();
    VitalinkSession.instance.addListener(_onSessionChanged);
    _startSource();
  }

  // ---- inventory / RFID -----------------------------------------------
  /// The blood bags the app shows.
  ///
  /// Demo mode returns the bundled simulation. Real mode returns the bags
  /// the cold-chain device reported to the server.
  List<BloodBagModel> get bags => _mode == AppMode.real ? _realBags : _bags;

  /// Units per blood group.
  Map<String, int> get stockCounts =>
      _mode == AppMode.real ? _realStockCounts : _stockCounts;

  /// Blood groups that are stocked but running low.
  List<String> get lowStockGroups =>
      _mode == AppMode.real ? _realLowStock : _lowStockGroups;

  int get totalUnits => _mode == AppMode.real
      ? _realBags.fold<int>(0, (sum, b) => sum + b.units)
      : _inventoryRepository.getTotalAvailableUnits('user_hospital_1');
  BloodBagModel? get lastScannedBag => _lastScannedBag;
  bool get isScanning => _isScanning;
  String? get scanError => _scanError;
  List<SensorReading> get recentReadings =>
      _source == IotDataSource.live || _source == IotDataSource.connecting
          ? _readings
          : _iotRepository.recentReadings;

  // ---- mode -----------------------------------------------------------
  AppMode get mode => _mode;
  bool get isRealMode => _mode == AppMode.real;
  bool get isDemoMode => _mode == AppMode.demo;

  /// Switches the data source.
  ///
  /// The work is deferred to a microtask because this is also called from
  /// the provider's build phase, where notifying listeners is not allowed.
  void setMode(AppMode mode) {
    if (_mode == mode) return;
    _mode = mode;
    Future.microtask(_applyMode);
  }

  Future<void> _applyMode() async {
    if (_disposed) return;
    if (_mode == AppMode.real) {
      // The simulation must not drift in the background while the app shows
      // real server data.
      _iotRepository.pause();
      await _connectLive();
    } else {
      _iotRepository.resume();
      _stopLive();
      _enableDemo();
      _loadHospitalData();
    }
    _notify();
  }

  // ---- source / device ----------------------------------------------
  IotDataSource get dataSource => _source;
  bool get isLive => _source == IotDataSource.live;
  bool get isDemo => _source == IotDataSource.demo;
  String? get liveError => _liveError;
  DateTime? get lastSync => _lastSync;
  List<IotDevice> get devices => _devices;
  String? get selectedDeviceId => _selectedDeviceId;
  IotDevice? get selectedDevice {
    final id = _selectedDeviceId;
    if (id == null) return null;
    for (final d in _devices) {
      if (d.id == id) return d;
    }
    return _devices.isEmpty ? null : _devices.first;
  }

  /// The device display name.
  ///
  /// Real mode never invents a name: without a device it shows a dash.
  String get deviceName {
    final d = selectedDevice;
    if (d != null) return d.name;
    return _mode == AppMode.real ? '—' : 'ESP32 Fridge A';
  }

  String get storageUnit {
    final d = selectedDevice;
    if (d != null) return d.storageUnit;
    return _mode == AppMode.real ? '—' : 'Cold Unit A';
  }

  String get firmware => selectedDevice?.firmware ?? '—';

  /// Upload cadence in seconds. Zero means the server did not report one.
  int get uploadIntervalS =>
      _mode == AppMode.real ? (selectedDevice?.uploadIntervalS ?? 0) : 3;

  int? get wifiRssi => selectedDevice?.wifiRssi ?? _wifiRssi;
  String? get ipAddress => selectedDevice?.ip ?? _ipAddress;
  double get thresholdMin => selectedDevice?.thresholdMin ?? _thresholdMin;
  double get thresholdMax => selectedDevice?.thresholdMax ?? _thresholdMax;

  // ---- temperature ---------------------------------------------------
  /// The latest temperature, or null when the device has not reported one.
  ///
  /// Real mode returns null rather than a placeholder, so the UI can show
  /// `--` instead of an invented reading.
  double? get currentTemperature => _hasTemperature ? _currentTemp : null;

  bool get hasTemperature => _hasTemperature;
  bool get isTempSafe => _isTempSafe;
  String? get tempAlertMessage => _tempAlertMessage;

  /// True when the reading is outside the configured 2-6 C band.
  ///
  /// This is informational only. Whether an out-of-range reading is an
  /// *alarm* is decided by the server, so the app follows the server's
  /// alerts instead of raising its own.
  bool get isTempOutOfRange =>
      _hasTemperature &&
      (_currentTemp < _thresholdMin || _currentTemp > _thresholdMax);

  /// True when the server has an open temperature alert for this device.
  ///
  /// The server owns alarm policy (it can have temperature monitoring
  /// disabled), so a live session must not invent its own breach state.
  bool get tempAlarmActive {
    if (_source != IotDataSource.live) return !_isTempSafe;
    return _alerts.any((a) => a.isOpen && a.type == 'TEMP_BREACH');
  }

  /// Whether the server will raise a temperature breach alert at all.
  bool get tempAlarmEnabled =>
      selectedDevice?.tempAlarmEnabled ?? true;

  // ---- fridge details ------------------------------------------------
  double? get weightG => _mode == AppMode.real ? _weightG : null;
  int get bagCount =>
      _mode == AppMode.real ? _bagCount : _deviceBags.length;

  /// Units per blood group.
  Map<String, int> get groups =>
      _mode == AppMode.real ? _liveGroups : _stockCounts;

  /// The bags the device reported to the server.
  List<DeviceBag> get deviceBags =>
      _mode == AppMode.real ? _deviceBags : const [];
  bool get securityEnabled => _securityEnabled;
  String get securityState => _securityState;
  bool get rfidReaderOk => _rfidReaderOk;
  String? get rfidUid => _rfidUid;
  bool get gatewayOnline => selectedDevice?.online ?? false;
  DateTime? get lastSeen => selectedDevice?.lastSeenAt;
  List<IotAlert> get activeAlerts => _alerts.where((a) => a.isOpen).toList();

  // ---- live actions --------------------------------------------------
  Future<void> refresh() async {
    if (_mode != AppMode.real) {
      // Demo mode is driven by the local simulator, there is nothing to pull.
      _enableDemo();
      return;
    }
    if (!VitalinkSession.instance.canUseIot) {
      _source = IotDataSource.error;
      _liveError =
          'The VitaLink session has expired. Connect again to use real data.';
      _notify();
      return;
    }
    if (_source != IotDataSource.live) {
      await _connectLive();
      return;
    }
    await _refreshDevice();
    await _refreshAlerts();
  }

  Future<void> selectDevice(String id) async {
    if (_selectedDeviceId == id) return;
    _selectedDeviceId = id;
    final d = selectedDevice;
    if (d != null) _applyDevice(d);
    _notify();
    if (_mode == AppMode.real && VitalinkSession.instance.canUseIot) {
      await _refreshDetails();
    }
  }

  Future<bool> ackAlert(String id) async {
    if (!await VitalinkSession.instance.ensureValid()) return false;
    try {
      await _api.ackAlert(VitalinkSession.instance.accessToken!, id);
      await _refreshAlerts();
      return true;
    } catch (e) {
      _liveError = e.toString();
      _notify();
      return false;
    }
  }

  Future<bool> sendCommand(
    String type, [
    Map<String, dynamic> payload = const {},
  ]) async {
    final device = selectedDevice;
    if (device == null) return false;
    if (!await VitalinkSession.instance.ensureValid()) return false;
    try {
      await _api.sendCommand(
          VitalinkSession.instance.accessToken!, device.id, type, payload);
      return true;
    } catch (e) {
      _liveError = e.toString();
      _notify();
      return false;
    }
  }

  /// Turns the server-side temperature breach alarm on or off.
  ///
  /// The alarm policy lives on the server, so this changes the device
  /// record and then re-reads it. A live session only shows a breach alarm
  /// when the server has one open.
  Future<bool> setTempAlarmEnabled(bool enabled) async {
    final device = selectedDevice;
    if (device == null) return false;
    if (!await VitalinkSession.instance.ensureValid()) return false;
    try {
      final ok = await _api.setTempAlarmEnabled(
          VitalinkSession.instance.accessToken!, device.id, enabled);
      if (!ok) return false;
      await _refreshDevice();
      await _refreshAlerts();
      return true;
    } catch (e) {
      _liveError = e.toString();
      _notify();
      return false;
    }
  }

  // ---- lifecycle -----------------------------------------------------
  void _onSessionChanged() {
    if (_disposed) return;
    // Demo mode never talks to the server, so a session change is only
    // interesting while real data is switched on.
    if (_mode != AppMode.real) return;
    if (VitalinkSession.instance.canUseIot) {
      if (_source != IotDataSource.live &&
          _source != IotDataSource.connecting) {
        _connectLive();
      }
    } else {
      _stopLive();
      _source = IotDataSource.error;
      _liveError =
          'The VitaLink session has expired. Connect again to use real data.';
      _notify();
    }
  }

  void _startSource() {
    if (_mode == AppMode.real) {
      _connectLive();
    } else {
      _enableDemo();
    }
  }

  void _enableDemo() {
    if (_source == IotDataSource.demo && _demoSubscribed) return;
    _source = IotDataSource.demo;
    _liveError = null;
    _hasTemperature = true;
    _currentTemp = _iotRepository.currentTemp;
    _isTempSafe = _iotRepository.isInSafeRange;
    _realBags = const [];
    _realStockCounts = const {};
    _realLowStock = const [];
    if (!_demoSubscribed) {
      _demoSubscribed = true;
      _subscribeToIot();
    }
    _notify();
  }

  Future<void> _connectLive() async {
    if (_starting || _disposed) return;
    _starting = true;
    _source = IotDataSource.connecting;
    _liveError = null;
    _notify();

    try {
      if (!await VitalinkSession.instance.ensureValid()) {
        throw VitalinkApiException('VitaLink session expired. Log in again.');
      }
      final token = VitalinkSession.instance.accessToken!;
      final devices = await _api.devices(token);
      if (_disposed) return;
      _devices = devices;
      if (devices.isEmpty) {
        _source = IotDataSource.error;
        _liveError = 'No IoT devices are assigned to this hospital yet.';
        _notify();
        return;
      }
      final wanted = _selectedDeviceId;
      _selectedDeviceId = devices.any((d) => d.id == wanted)
          ? wanted
          : devices.first.id;
      _applyDevice(selectedDevice!);
      await _refreshDetails();
      _startTimers();
      await _connectSocket();
      if (_disposed) return;
      _source = IotDataSource.live;
      _lastSync = DateTime.now();
    } catch (e) {
      if (_disposed) return;
      _source = IotDataSource.error;
      _liveError = e.toString().replaceAll('Exception: ', '');
      _scheduleReconnect();
    } finally {
      _starting = false;
      _notify();
    }
  }

  void _stopLive() {
    _pollTimer?.cancel();
    _alertsTimer?.cancel();
    _reconnectTimer?.cancel();
    _pollTimer = null;
    _alertsTimer = null;
    _reconnectTimer = null;
    _socketConnected = false;
    final socket = _socket;
    _socket = null;
    socket?.dispose();
    // Do not leak one hospital's live data into the demo/other account.
    _devices = const [];
    _selectedDeviceId = null;
    _deviceBags = const [];
    _liveGroups = const {};
    _alerts = const [];
    _realBags = const [];
    _realStockCounts = const {};
    _realLowStock = const [];
    _tempAlertMessage = null;
    _liveError = null;
  }

  void _startTimers() {
    _pollTimer?.cancel();
    _alertsTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _refreshDevice();
    });
    // Bags and history can change on the device portal without a socket
    // event, so refresh the full detail set as well as the alerts.
    _alertsTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _refreshDetails();
    });
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 5), () async {
      if (_disposed) return;
      if (!VitalinkSession.instance.canUseIot) return;
      if (_source == IotDataSource.live && _socketConnected) return;
      if (await VitalinkSession.instance.ensureValid()) {
        if (_source == IotDataSource.error) {
          await _connectLive();
        } else {
          await _connectSocket();
          await _refreshDevice();
        }
      }
    });
  }

  // ---- device helpers ------------------------------------------------
  void _applyDevice(IotDevice d) {
    _thresholdMin = d.thresholdMin;
    _thresholdMax = d.thresholdMax;
    final t = d.temperatureC;
    _hasTemperature = d.tempSensorOk && t != null;
    if (t != null) _currentTemp = t;
    _isTempSafe = d.isSafeBand(d.thresholdMin, d.thresholdMax);
    _weightG = d.weightG;
    _bagCount = d.bagCount;
    _liveGroups = d.groups.isEmpty ? _liveGroups : d.groups;
    _securityEnabled = d.securityEnabled;
    _securityState = d.securityState;
    _rfidReaderOk = d.rfidReaderOk;
    _rfidUid = d.rfidUid;
    _wifiRssi = d.wifiRssi;
    _ipAddress = d.ip;
    _tempAlertMessage = _deriveAlertMessage();
  }

  String? _deriveAlertMessage() {
    final open = _alerts.where((a) => a.isOpen).toList();
    open.sort((a, b) =>
        (b.isCritical ? 1 : 0).compareTo(a.isCritical ? 1 : 0));
    if (open.isNotEmpty) return open.first.message;
    if (_securityState == 'ALARM') {
      return 'Secure monitor alarm: unauthorised bag removal.';
    }
    // In demo mode there is no server to raise the alert, so the local range
    // check still produces one. A live session only shows what the server
    // reported.
    if (_source != IotDataSource.live &&
        _hasTemperature &&
        (_currentTemp < _thresholdMin || _currentTemp > _thresholdMax)) {
      return 'Temperature ${_currentTemp.toStringAsFixed(1)}°C outside '
          '${_thresholdMin.toStringAsFixed(1)}–${_thresholdMax.toStringAsFixed(1)}°C.';
    }
    return null;
  }

  Future<void> _refreshDetails() async {
    final device = selectedDevice;
    if (device == null) return;
    if (!await VitalinkSession.instance.ensureValid()) return;
    final token = VitalinkSession.instance.accessToken!;
    try {
      final history = await _api.history(token, device.id, range: '1h');
      _setHistory(history, device);
    } catch (_) {}
    try {
      final snapshot = await _api.bags(token, device.id);
      _deviceBags = snapshot.bags;
      if (snapshot.groups.isNotEmpty) _liveGroups = snapshot.groups;
      if (_mode == AppMode.real) {
        _realBags = RealInventoryMapper.bags(
          deviceBags: snapshot.bags,
          device: device,
        );
        _realStockCounts = RealInventoryMapper.groupCounts(_realBags);
        _realLowStock = RealInventoryMapper.lowStockGroups(_realStockCounts);
      }
    } catch (_) {}
    await _refreshAlerts();
    if (!_disposed) _notify();
  }

  Future<void> _refreshAlerts() async {
    if (!await VitalinkSession.instance.ensureValid()) return;
    try {
      final alerts = await _api.alerts(VitalinkSession.instance.accessToken!);
      if (_disposed) return;
      _alerts = alerts;
      _tempAlertMessage = _deriveAlertMessage();
      _notify();
    } catch (_) {}
  }

  Future<void> _refreshDevice() async {
    final id = _selectedDeviceId;
    if (id == null) return;
    if (!await VitalinkSession.instance.ensureValid()) return;
    try {
      final fresh = await _api.device(VitalinkSession.instance.accessToken!, id);
      if (_disposed) return;
      final idx = _devices.indexWhere((d) => d.id == id);
      if (idx >= 0) {
        _devices[idx] = fresh;
      } else {
        _devices.add(fresh);
      }
      _applyDevice(fresh);
      _lastSync = DateTime.now();
      if (!_socketConnected) _appendLatest(fresh);
      _notify();
    } catch (_) {}
  }

  void _setHistory(List<TelemetryPoint> points, IotDevice device) {
    final mapped = <SensorReading>[];
    for (final p in points) {
      final t = p.temperatureC;
      if (t == null) continue;
      mapped.add(SensorReading(
        readingId: 'h${p.t.millisecondsSinceEpoch}',
        deviceId: device.id,
        storageUnitName: device.storageUnit,
        hospitalId: device.hospitalId,
        temperature: t,
        timestamp: p.t,
        isSafe: t >= device.thresholdMin && t <= device.thresholdMax,
      ));
    }
    if (mapped.isEmpty) return;
    _readings = mapped.length > 600
        ? mapped.sublist(mapped.length - 600)
        : mapped;
  }

  void _appendLatest(IotDevice device) {
    final sampleId = device.latest['sampleId']?.toString();
    if (sampleId != null && sampleId == _lastSampleId) return;
    final t = device.temperatureC;
    if (t == null) return;
    _lastSampleId = sampleId;
    _readings.add(SensorReading(
      readingId: sampleId ?? 'l${DateTime.now().millisecondsSinceEpoch}',
      deviceId: device.id,
      storageUnitName: device.storageUnit,
      hospitalId: device.hospitalId,
      temperature: t,
      timestamp: device.latestAt ?? DateTime.now(),
      isSafe: device.isSafeBand(device.thresholdMin, device.thresholdMax),
    ));
    if (_readings.length > 600) _readings.removeAt(0);
  }

  // ---- socket ---------------------------------------------------------
  Future<void> _connectSocket() async {
    if (_disposed) return;
    final token = VitalinkSession.instance.accessToken;
    if (token == null) return;
    final old = _socket;
    _socket = null;
    await old?.dispose();
    void onClosed(String? error) {
      _socketConnected = false;
      _scheduleReconnect();
    }

    final socket = _socketFactory != null
        ? _socketFactory!(onEvent: _onSocketEvent, onClosed: onClosed)
        : VitalinkSocket(onEvent: _onSocketEvent, onClosed: onClosed);
    _socket = socket;
    final ok = await socket.connect(token);
    _socketConnected = ok;
    if (!ok) _scheduleReconnect();
  }

  void _onSocketEvent(Map<String, dynamic> msg) {
    if (_disposed) return;
    final type = msg['type']?.toString();
    if (type == 'telemetry') {
      final deviceId = msg['deviceId']?.toString();
      final idx = _devices.indexWhere((d) => d.id == deviceId);
      if (idx < 0) return;
      final patch = <String, dynamic>{
        'recordedAt': msg['recordedAt'],
        'temperatureC': msg['temperatureC'],
        // The socket payload does not always carry tempSensorOk, so treat a
        // missing reading as a sensor problem instead of showing stale data.
        'tempSensorOk':
            msg['tempSensorOk'] ?? (msg['temperatureC'] != null),
        'weightG': msg['weightG'],
        'bagCount': msg['bagCount'],
        'security': msg['security'],
        'wifiRssi': msg['wifiRssi'],
      };
      final updated = _devices[idx].copyWithLatest(patch);
      _devices[idx] = IotDevice(
        id: updated.id,
        hospitalId: updated.hospitalId,
        name: updated.name,
        storageUnit: updated.storageUnit,
        firmware: updated.firmware,
        uploadIntervalS: updated.uploadIntervalS,
        thresholdMin: updated.thresholdMin,
        thresholdMax: updated.thresholdMax,
        tempAlarmEnabled: updated.tempAlarmEnabled,
        wifiRssi: msg['wifiRssi'] is num
            ? (msg['wifiRssi'] as num).toInt()
            : updated.wifiRssi,
        ip: updated.ip,
        lastSeenAt: DateTime.now(),
        latestAt: msg['recordedAt'] != null
            ? DateTime.tryParse(msg['recordedAt'].toString())?.toLocal()
            : updated.latestAt,
        latest: updated.latest,
      );
      if (deviceId == _selectedDeviceId) {
        _applyDevice(_devices[idx]);
        _appendLatest(_devices[idx]);
        _lastSync = DateTime.now();
      }
      _notify();
    } else if (type == 'alert_opened' || type == 'alert_resolved') {
      _refreshAlerts();
    }
  }

  // ---- demo stream ----------------------------------------------------
  void _subscribeToIot() {
    _iotRepository.telemetryStream.listen((reading) {
      if (_source != IotDataSource.demo) return;
      _currentTemp = reading.temperature;
      _isTempSafe = reading.isSafe;
      _hasTemperature = true;
      _notify();
    });

    _iotRepository.alertStream.listen((alert) {
      if (_source != IotDataSource.demo) return;
      _tempAlertMessage = alert;
      _notify();
    });
  }

  // ---- inventory actions ---------------------------------------------
  void _loadHospitalData() {
    _bags = _inventoryRepository.getBagsForHospital('user_hospital_1');
    _stockCounts =
        _inventoryRepository.getStockCountByBloodGroup('user_hospital_1');
    _lowStockGroups =
        _inventoryRepository.getLowStockGroups('user_hospital_1');
    _notify();
  }

  Future<bool> scanRfidTag(String rfidTag) async {
    _isScanning = true;
    _scanError = null;
    _notify();

    if (_mode == AppMode.real) {
      // The server owns the bag list in real mode, so refresh it first and
      // look the tag up there instead of in the bundled simulation.
      await _refreshDetails();
      final matches = _realBags
          .where((b) => b.rfidTag == rfidTag || b.bagId == rfidTag)
          .toList();
      _isScanning = false;
      if (matches.isNotEmpty) {
        _lastScannedBag = matches.first;
        _notify();
        return true;
      }
      _scanError =
          'No bag with RFID $rfidTag is registered on the device yet.';
      _notify();
      return false;
    }

    final bag = await _rfidService.scanTag(rfidTag);
    _isScanning = false;

    if (bag != null) {
      _lastScannedBag = bag;
      _notify();
      return true;
    } else {
      _scanError = 'No blood bag found for RFID: $rfidTag';
      _notify();
      return false;
    }
  }

  Future<void> updateBagStatus(String bagId, BagStatus newStatus) async {
    if (_mode == AppMode.real) {
      throw Exception(
          'Bag state is managed on the cold-chain device, so it cannot be '
          'changed here.');
    }
    final updated = await _rfidService.updateBagStatus(
      bagId: bagId,
      newStatus: newStatus,
    );
    _lastScannedBag = updated;
    _loadHospitalData();
  }

  Future<void> addNewBloodUnit({
    required String bloodGroup,
    required int units,
    required String rfidTag,
    required DateTime collectionDate,
    required DateTime expiryDate,
    String? storageUnitName,
  }) async {
    if (_mode == AppMode.real) {
      throw Exception(
          'In real mode a bag is added on the cold-chain device: tap the new '
          'bag\'s RFID tag on the reader and it appears here.');
    }
    await _rfidService.registerNewBag(
      hospitalId: 'user_hospital_1',
      hospitalName: 'City Apex Blood Center',
      bloodGroup: bloodGroup,
      units: units,
      rfidTag: rfidTag,
      collectionDate: collectionDate,
      expiryDate: expiryDate,
      storageUnitName: storageUnitName,
    );
    _loadHospitalData();
  }

  /// Demo-only breach injection; ignored while real server data is active.
  void simulateHighTemperatureBreach() {
    if (_mode == AppMode.real) return;
    _iotRepository.triggerSimulatedBreach(8.4);
  }

  /// Demo-only reset; ignored while real server data is active.
  void resetTemperatureNormal() {
    if (_mode == AppMode.real) return;
    _iotRepository.resetSafeNormal();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    VitalinkSession.instance.removeListener(_onSessionChanged);
    _pollTimer?.cancel();
    _alertsTimer?.cancel();
    _reconnectTimer?.cancel();
    _socket?.dispose();
    super.dispose();
  }
}
