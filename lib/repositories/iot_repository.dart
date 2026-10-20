import '../models/iot_sensor_model.dart';
import '../services/iot_monitoring_service.dart';

/// Repository for IoT cold-chain telemetry readings and threshold alerts
class IotRepository {
  final IotMonitoringService _iotService;
  IotRepository({IotMonitoringService? iotService})
      : _iotService = iotService ?? IotMonitoringService();

  Stream<SensorReading> get telemetryStream => _iotService.telemetryStream;
  Stream<String?> get alertStream => _iotService.alertStream;
  double get currentTemp => _iotService.currentTemperature;
  bool get isInSafeRange => _iotService.isInSafeRange;
  List<SensorReading> get recentReadings => _iotService.recentReadings;

  void triggerSimulatedBreach(double breachTemp) =>
      _iotService.simulateTemperatureBreach(breachTemp);

  void resetSafeNormal() => _iotService.resetToSafeNormal();

  /// Stops the simulated cold chain while real server data is shown.
  void pause() => _iotService.pause();

  /// Restarts the simulated cold chain.
  void resume() => _iotService.resume();
}
