import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../providers/hospital_provider.dart';
import '../../utils/app_colors.dart';
import '../../widgets/animated_card.dart';
import '../../widgets/custom_button.dart';
import '../../widgets/mode_switch.dart';
import '../../widgets/temperature_chart_widget.dart';

/// IoT cold-chain monitor. Shows live VitaLink server telemetry for
/// hospital/admin sessions and the local simulation otherwise.
class IotTemperatureScreen extends StatelessWidget {
  const IotTemperatureScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<HospitalProvider>();
    final readings = provider.recentReadings;
    final currentTemp = provider.currentTemperature;
    final isSafe = provider.isTempSafe;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('IoT Cold Storage Monitor'),
        actions: [
          const ModeSwitch(),
          IconButton(
            tooltip: 'Refresh',
            onPressed: () => provider.refresh(),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: provider.refresh,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (provider.liveError != null) ...[
              _errorBanner(provider.liveError!),
              const SizedBox(height: 12),
            ],
            if (provider.dataSource == IotDataSource.connecting) ...[
              _connectingBanner(),
              const SizedBox(height: 12),
            ],
            // Connection state, moved out of the app bar so the top-right
            // corner can show the app-wide Demo / Real switch.
            _statusLine(provider),
            const SizedBox(height: 12),
            if (provider.isRealMode) ...[
              _alarmPolicyCard(context, provider),
              const SizedBox(height: 12),
            ],
            if (provider.devices.length > 1) ...[
              _devicePicker(context, provider),
              const SizedBox(height: 12),
            ],
            AnimatedCard(
              padding: const EdgeInsets.all(18),
              child: TemperatureChartWidget(
                readings: readings
                    .where((r) => r.timestamp.isAfter(
                        DateTime.now().subtract(const Duration(hours: 2))))
                    .toList(),
                currentTemp: currentTemp,
                isSafe: isSafe,
                // The server owns the alarm policy, so the chart only says
                // "breach" when the server raised the alert.
                alarmActive: provider.tempAlarmActive,
                alarmsEnabled: provider.tempAlarmEnabled,
                thresholdMin: provider.thresholdMin,
                thresholdMax: provider.thresholdMax,
              ),
            ),
            const SizedBox(height: 16),
            _temperatureCard(context, provider),
            const SizedBox(height: 16),
            if (provider.activeAlerts.isNotEmpty) ...[
              _alertsCard(context, provider),
              const SizedBox(height: 16),
            ],
            _gatewayCard(context, provider, isDark),
            const SizedBox(height: 16),
            if (provider.isRealMode) ...[
              _commandCard(context, provider),
              const SizedBox(height: 16),
              if (provider.deviceBags.isNotEmpty) ...[
                _bagsCard(provider),
                const SizedBox(height: 16),
              ],
            ] else ...[
              _demoControls(context, provider),
              const SizedBox(height: 16),
            ],
            const Text(
              'Recent Telemetry Readings',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            AnimatedCard(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: readings.reversed.take(8).map((reading) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: reading.isSafe
                                    ? AppColors.success
                                    : AppColors.error,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              DateFormat('HH:mm:ss').format(reading.timestamp),
                              style: const TextStyle(
                                  fontSize: 13, color: Colors.grey),
                            ),
                          ],
                        ),
                        Text(
                          '${reading.temperature.toStringAsFixed(1)}°C',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: reading.isSafe
                                ? AppColors.success
                                : AppColors.error,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _errorBanner(String message) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.warningLight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.warning),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_off_rounded, color: AppColors.warning),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(fontSize: 13, color: Colors.black87),
            ),
          ),
        ],
      ),
    );
  }

  /// Small status line showing where the telemetry comes from.
  Widget _statusLine(HospitalProvider provider) {
    return Row(
      children: [
        _SourceChip(
          live: provider.isLive,
          connecting: provider.dataSource == IotDataSource.connecting,
          error: provider.dataSource == IotDataSource.error,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            provider.isRealMode
                ? 'Telemetry reported by the VitaLink server'
                : 'Telemetry from the on-device simulator',
            style: const TextStyle(fontSize: 11, color: Colors.grey),
          ),
        ),
      ],
    );
  }

  /// Shown while the app is still talking to the VitaLink server.
  Widget _connectingBanner() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.infoLight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.info),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Connecting to the VitaLink server…',
              style: TextStyle(fontSize: 13, color: Colors.black87),
            ),
          ),
        ],
      ),
    );
  }

  Widget _devicePicker(BuildContext context, HospitalProvider provider) {
    return AnimatedCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: DropdownButton<String>(
        isExpanded: true,
        value: provider.selectedDeviceId,
        underline: const SizedBox.shrink(),
        items: provider.devices
            .map((d) => DropdownMenuItem(
                  value: d.id,
                  child: Text('${d.name}  ·  ${d.id}'),
                ))
            .toList(),
        onChanged: (id) {
          if (id != null) provider.selectDevice(id);
        },
      ),
    );
  }

  /// Temperature alarm policy for the selected device.
  ///
  /// The setting lives on the server, so the switch changes the device
  /// record there. While it is off the reading is still shown and charted,
  /// it just does not raise a breach alert.
  Widget _alarmPolicyCard(BuildContext context, HospitalProvider provider) {
    final enabled = provider.tempAlarmEnabled;
    return AnimatedCard(
      padding: const EdgeInsets.fromLTRB(16, 8, 10, 8),
      child: Row(
        children: [
          Icon(
            enabled ? Icons.notifications_active_rounded : Icons.notifications_off_rounded,
            color: enabled ? AppColors.success : AppColors.warning,
            size: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Temperature alarm',
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 2),
                Text(
                  enabled
                      ? 'A reading outside the band raises a breach alert.'
                      : 'Alerts are off. Readings are still stored and charted.',
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
            ),
          ),
          Switch(
            value: enabled,
            onChanged: (v) async {
              final ok = await provider.setTempAlarmEnabled(v);
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(ok
                    ? 'Temperature alarm ${v ? 'enabled' : 'disabled'}'
                    : 'Could not change the alarm setting'),
              ));
            },
          ),
        ],
      ),
    );
  }

  Widget _temperatureCard(BuildContext context, HospitalProvider provider) {
    final tempText = provider.currentTemperature == null
        ? '--'
        : '${provider.currentTemperature!.toStringAsFixed(1)}°C';
    // The server owns alarm policy. An out-of-range reading is reported as
    // information; only a server-raised alert is shown as an alarm.
    final alarming = provider.tempAlarmActive;
    final outOfRange = provider.isTempOutOfRange;
    final band = '${provider.thresholdMin.toStringAsFixed(1)}–'
        '${provider.thresholdMax.toStringAsFixed(1)}°C';
    final String status;
    if (alarming) {
      status = 'BREACH ALERT';
    } else if (outOfRange) {
      status = provider.tempAlarmEnabled
          ? 'Outside $band'
          : 'Outside $band (alarms off)';
    } else if (!provider.hasTemperature) {
      // No reading at all: the device has not reported a temperature, so
      // the card must not claim the fridge is optimal.
      status = 'NO READING';
    } else {
      status = 'Optimal ($band)';
    }
    final color = alarming
        ? AppColors.error
        : (outOfRange
            ? AppColors.warning
            : (provider.hasTemperature ? AppColors.success : Colors.grey));

    return AnimatedCard(
      padding: const EdgeInsets.all(16),
      border: Border.all(color: color.withOpacity(0.45)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.thermostat_rounded, color: color),
              const SizedBox(width: 8),
              Text(
                'Fridge environment',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              Text(status, style: TextStyle(color: color, fontSize: 12)),
            ],
          ),
          const Divider(),
          Row(
            children: [
              Expanded(
                child: _metric('Temperature', tempText, color),
              ),
              Expanded(
                child: _metric(
                  'Weight',
                  provider.weightG == null
                      ? '—'
                      : '${provider.weightG!.toStringAsFixed(1)} g',
                  null,
                ),
              ),
              Expanded(
                child: _metric('Bags', '${provider.bagCount}', null),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _metric(
                  'Sensor',
                  provider.hasTemperature ? 'OK' : 'NO READING',
                  provider.hasTemperature ? AppColors.success : AppColors.error,
                ),
              ),
              Expanded(
                child: _metric(
                  'Security',
                  provider.securityEnabled ? provider.securityState : 'OFF',
                  provider.securityState == 'ALARM'
                      ? AppColors.error
                      : (provider.securityEnabled
                          ? AppColors.success
                          : null),
                ),
              ),
              Expanded(
                child: _metric(
                  'RFID',
                  provider.rfidReaderOk ? 'READY' : 'OFFLINE',
                  provider.rfidReaderOk ? AppColors.success : AppColors.error,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _metric(String label, String value, Color? color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(fontSize: 11, color: Colors.grey)),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _alertsCard(BuildContext context, HospitalProvider provider) {
    return AnimatedCard(
      padding: const EdgeInsets.all(14),
      color: AppColors.errorLight,
      border: Border.all(color: AppColors.error),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.warning_rounded, color: AppColors.error),
              SizedBox(width: 8),
              Text('Active server alerts',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, color: AppColors.error)),
            ],
          ),
          const SizedBox(height: 8),
          ...provider.activeAlerts.map((alert) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${alert.type}: ${alert.message}',
                        style: const TextStyle(
                            fontSize: 12, color: Colors.black87),
                      ),
                    ),
                    TextButton(
                      onPressed: () async {
                        final ok = await provider.ackAlert(alert.id);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text(ok
                                ? 'Alert acknowledged'
                                : 'Could not acknowledge alert'),
                          ));
                        }
                      },
                      child: const Text('ACK'),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  Widget _gatewayCard(
      BuildContext context, HospitalProvider provider, bool isDark) {
    final online = provider.gatewayOnline;
    return AnimatedCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                provider.deviceName,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: online
                      ? AppColors.successLight
                      : (isDark ? const Color(0xFF3A1F1F) : AppColors.errorLight),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  online ? 'ONLINE' : 'OFFLINE',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: online ? AppColors.success : AppColors.error,
                  ),
                ),
              ),
            ],
          ),
          const Divider(),
          _SpecRow('Device ID', provider.selectedDevice?.id ?? '—'),
          _SpecRow('Storage unit', provider.storageUnit),
          _SpecRow('Firmware', provider.firmware),
          // Zero means the server did not report an upload cadence.
          _SpecRow(
            'Upload interval',
            provider.uploadIntervalS == 0
                ? '—'
                : '${provider.uploadIntervalS} s',
          ),
          _SpecRow('Wi-Fi RSSI',
              provider.wifiRssi == null ? '—' : '${provider.wifiRssi} dBm'),
          _SpecRow('IP address', provider.ipAddress ?? '—'),
          _SpecRow('Last seen', _time(provider.lastSeen)),
          _SpecRow('Last sync', _time(provider.lastSync)),
        ],
      ),
    );
  }

  Widget _commandCard(BuildContext context, HospitalProvider provider) {
    Future<void> run(String type,
        [Map<String, dynamic> payload = const {}]) async {
      final ok = await provider.sendCommand(type, payload);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(ok
              ? 'Command queued: $type'
              : 'Command failed. Check the connection.'),
        ));
      }
    }

    return AnimatedCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Remote commands',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          const Text(
            'Delivered to the fridge on its next upload (up to one interval).',
            style: TextStyle(fontSize: 11, color: Colors.grey),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _cmd(context, 'Buzzer test', Icons.volume_up_rounded,
                  () => run('BUZZER_TEST')),
              _cmd(context, 'RFID scan', Icons.qr_code_scanner_rounded,
                  () => run('START_RFID_SCAN')),
              _cmd(context, 'Tare scale', Icons.scale_rounded,
                  () => run('TARE')),
              _cmd(
                context,
                provider.securityEnabled ? 'Secure off' : 'Secure on',
                Icons.shield_rounded,
                () => run('SET_SECURE', {'on': !provider.securityEnabled}),
              ),
              _cmd(context, 'Silence alarm', Icons.notifications_off_rounded,
                  () => run('ACK_ALARM')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _cmd(BuildContext context, String label, IconData icon,
      VoidCallback onTap) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16),
      label: Text(label, style: const TextStyle(fontSize: 12)),
    );
  }

  Widget _bagsCard(HospitalProvider provider) {
    return AnimatedCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Bags in ${provider.deviceName}',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          const Divider(),
          ...provider.deviceBags.map((bag) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        bag.group,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(bag.uid,
                          style: const TextStyle(fontSize: 12)),
                    ),
                    Text(
                      bag.expiry == null
                          ? '—'
                          : DateFormat('d MMM yyyy').format(bag.expiry!),
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  Widget _demoControls(BuildContext context, HospitalProvider provider) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Demo hardware simulator',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        const Text(
          'Log in with a VitaLink hospital account to see the real fridge.',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: CustomButton(
                text: 'Breach 8.4°C',
                icon: Icons.local_fire_department_rounded,
                variant: ButtonVariant.emergency,
                onPressed: provider.simulateHighTemperatureBreach,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: CustomButton(
                text: 'Reset 4.0°C',
                icon: Icons.ac_unit_rounded,
                variant: ButtonVariant.outline,
                onPressed: provider.resetTemperatureNormal,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _SpecRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  String _time(DateTime? t) {
    if (t == null) return '—';
    final diff = DateTime.now().difference(t);
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    return DateFormat('d MMM HH:mm').format(t);
  }
}

class _SourceChip extends StatelessWidget {
  final bool live;
  final bool connecting;

  /// True when the server connection failed. Without it the chip would
  /// claim "DEMO" while the app is really in real mode.
  final bool error;

  const _SourceChip({
    required this.live,
    required this.connecting,
    this.error = false,
  });

  @override
  Widget build(BuildContext context) {
    final label = live
        ? 'LIVE'
        : (connecting ? 'LINKING' : (error ? 'ERROR' : 'DEMO'));
    final color = live
        ? AppColors.success
        : (connecting
            ? AppColors.warning
            : (error ? AppColors.error : Colors.grey));
    return Center(
      child: Container(
        margin: const EdgeInsets.only(right: 4),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
              fontSize: 10, fontWeight: FontWeight.bold, color: color),
        ),
      ),
    );
  }
}
