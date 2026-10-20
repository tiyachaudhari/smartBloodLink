import 'dart:async';
import 'dart:math';
import '../models/iot_sensor_model.dart';
import '../utils/constants.dart';
import 'mock_data_service.dart';

/// IoT Cold-Chain Storage Monitoring Service with ESP32 stream simulation
class IotMonitoringService {
  static final IotMonitoringService _instance =
      IotMonitoringService._internal();
  factory IotMonitoringService() => _instance;
  IotMonitoringService._internal() {
    _startTelemetryLoop();
  }

  final _telemetryController = StreamController<SensorReading>.broadcast();
  Stream<SensorReading> get telemetryStream => _telemetryController.stream;

  final _alertController = StreamController<String?>.broadcast();
  Stream<String?> get alertStream => _alertController.stream;

  double _currentTemp = 4.0;
  bool _isManualSimulation = false;
  bool _paused = false;
  int _consecutiveViolations = 0;
  Timer? _telemetryTimer;

  double get currentTemperature => _currentTemp;
  bool get isInSafeRange =>
      _currentTemp >= BloodConstants.safeStorageTempMin &&
      _currentTemp <= BloodConstants.safeStorageTempMax;

  List<SensorReading> get recentReadings =>
      MockDataService.initialSensorReadings;

  /// Stops the simulation.
  ///
  /// The app calls this while it shows real server data, so the simulated
  /// cold chain does not drift in the background.
  void pause() => _paused = true;

  /// Restarts the simulation.
  void resume() => _paused = false;

  void _startTelemetryLoop() {
    _telemetryTimer?.cancel();
    _telemetryTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (_paused) return;
      if (!_isManualSimulation) {
        // Natural subtle cold-chain temperature oscillation between 3.6°C and 4.4°C
        final randomOffset = (Random().nextDouble() * 0.4) - 0.2;
        _currentTemp = double.parse((_currentTemp + randomOffset).clamp(3.4, 4.8).toStringAsFixed(1));
      }

      final reading = SensorReading(
        readingId: 'READ-${DateTime.now().millisecondsSinceEpoch}',
        deviceId: 'ESP32-FRIDGE-01',
        storageUnitName: 'Cold Unit A (RBC Bank)',
        hospitalId: 'user_hospital_1',
        temperature: _currentTemp,
        timestamp: DateTime.now(),
      );

      MockDataService.initialSensorReadings.add(reading);
      if (MockDataService.initialSensorReadings.length > 20) {
        MockDataService.initialSensorReadings.removeAt(0);
      }

      _telemetryController.add(reading);

      // Check safety thresholds
      if (!reading.isSafe) {
        _consecutiveViolations++;
        // 2 consecutive violations of 4s = ~8-10s for interactive responsiveness in UI demo
        if (_consecutiveViolations >= 2) {
          _alertController.add(
            '🚨 CRITICAL TEMPERATURE BREACH: Cold Storage at ${_currentTemp}°C! Safe range is 2.0°C - 6.0°C.',
          );
        }
      } else {
        _consecutiveViolations = 0;
        _alertController.add(null);
      }
    });
  }

  /// Interactive Simulation: Inject high temperature breach for demo testing
  void simulateTemperatureBreach(double breachTemp) {
    _isManualSimulation = true;
    _currentTemp = breachTemp;
    _consecutiveViolations = 2; // Trigger alert immediately
    final reading = SensorReading(
      readingId: 'READ-ALERT-${DateTime.now().millisecondsSinceEpoch}',
      deviceId: 'ESP32-FRIDGE-01',
      storageUnitName: 'Cold Unit A (RBC Bank)',
      hospitalId: 'user_hospital_1',
      temperature: _currentTemp,
      timestamp: DateTime.now(),
    );
    MockDataService.initialSensorReadings.add(reading);
    _telemetryController.add(reading);
    _alertController.add(
      '🚨 CRITICAL TEMPERATURE BREACH: Cold Storage at ${_currentTemp}°C! Immediate intervention required to prevent blood spoilage.',
    );
  }

  /// Reset temperature back to safe calibrated baseline
  void resetToSafeNormal() {
    _isManualSimulation = false;
    _currentTemp = 4.0;
    _consecutiveViolations = 0;
    _alertController.add(null);
  }

  void dispose() {
    _telemetryTimer?.cancel();
    _telemetryController.close();
    _alertController.close();
  }
}
