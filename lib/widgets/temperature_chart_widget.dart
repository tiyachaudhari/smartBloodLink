import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../models/iot_sensor_model.dart';
import '../utils/app_colors.dart';
import '../utils/constants.dart';

/// Real-time IoT temperature telemetry chart with safety threshold boundaries
class TemperatureChartWidget extends StatelessWidget {
  final List<SensorReading> readings;

  /// The latest reading. Null when the device has not reported one, in which
  /// case the chart shows a dash rather than an invented value.
  final double? currentTemp;

  /// True when the reading is inside the configured band.
  final bool isSafe;

  /// True when the server raised a breach alert for this device. The server
  /// owns the alarm policy, so the chart only says "breach" when the server
  /// said so.
  final bool alarmActive;

  /// True when the server would raise a breach alert for an out-of-band
  /// reading. When it is off the reading is still charted, just not alarmed.
  final bool alarmsEnabled;

  final double thresholdMin;
  final double thresholdMax;

  const TemperatureChartWidget({
    super.key,
    required this.readings,
    required this.currentTemp,
    required this.isSafe,
    this.alarmActive = false,
    this.alarmsEnabled = true,
    this.thresholdMin = BloodConstants.safeStorageTempMin,
    this.thresholdMax = BloodConstants.safeStorageTempMax,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (readings.isEmpty) {
      // Never draw a synthetic line. An empty chart is honest: the device
      // has simply not reported anything yet.
      return _emptyState(context);
    }

    // The x axis is the real time of each reading, so a gap in the data
    // (a device that was offline) shows up as a gap instead of being
    // squashed away.
    final DateTime first = readings.first.timestamp;
    final double spanSeconds = readings.last.timestamp
            .difference(first)
            .inMilliseconds
            .toDouble() /
        1000.0;

    final spots = <FlSpot>[];
    double dataMin = readings.first.temperature;
    double dataMax = readings.first.temperature;
    for (final reading in readings) {
      final double x = reading.timestamp
              .difference(first)
              .inMilliseconds
              .toDouble() /
          1000.0;
      spots.add(FlSpot(x, reading.temperature));
      dataMin = math.min(dataMin, reading.temperature);
      dataMax = math.max(dataMax, reading.temperature);
    }

    // The scale has to follow the data. A fixed 0-10 C axis hides every
    // reading above 10 C, which is exactly what happens when the fridge
    // door is open or the unit is on the bench.
    final double maxY = math.max(10.0, dataMax * 1.15);
    final double yInterval = _niceStep(maxY / 5);
    final double xInterval = _niceStep(math.max(spanSeconds / 5, 1));

    final Color statusColor = _statusColor;
    final String statusLabel = _statusLabel;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'COLD STORAGE TELEMETRY (ESP32)',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      currentTemp == null
                          ? '--'
                          : '${currentTemp!.toStringAsFixed(1)}°C',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: currentTemp == null
                            ? Colors.grey
                            : statusColor,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        statusLabel,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: statusColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.thermostat_rounded,
                size: 26,
                color: statusColor,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 180,
          child: LineChart(
            LineChartData(
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: yInterval,
                getDrawingHorizontalLine: (val) {
                  return FlLine(
                    color: isDark ? Colors.white12 : Colors.black12,
                    strokeWidth: 1,
                  );
                },
              ),
              titlesData: FlTitlesData(
                show: true,
                topTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 22,
                    interval: xInterval,
                    getTitlesWidget: (value, meta) {
                      final DateTime t = first.add(
                        Duration(milliseconds: (value * 1000).round()),
                      );
                      return Text(
                        '${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}',
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 10,
                        ),
                      );
                    },
                  ),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 34,
                    interval: yInterval,
                    getTitlesWidget: (value, meta) {
                      return Text(
                        '${value.toStringAsFixed(value % 1 == 0 ? 0 : 1)}°C',
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 10,
                        ),
                      );
                    },
                  ),
                ),
              ),
              borderData: FlBorderData(show: false),
              minX: 0,
              maxX: spanSeconds > 0 ? spanSeconds : 1,
              minY: 0,
              maxY: maxY,
              // Draw Safe Threshold Range
              extraLinesData: ExtraLinesData(
                horizontalLines: [
                  if (thresholdMax <= maxY)
                    HorizontalLine(
                      y: thresholdMax,
                      color: AppColors.warning.withOpacity(0.7),
                      strokeWidth: 1.5,
                      dashArray: [5, 5],
                      label: HorizontalLineLabel(
                        show: true,
                        alignment: Alignment.topRight,
                        padding: const EdgeInsets.only(right: 5, bottom: 2),
                        style: const TextStyle(
                          fontSize: 9,
                          color: AppColors.warning,
                          fontWeight: FontWeight.bold,
                        ),
                        labelResolver: (line) =>
                            'Max (${thresholdMax.toStringAsFixed(0)}°C)',
                      ),
                    ),
                  if (thresholdMin <= maxY)
                    HorizontalLine(
                      y: thresholdMin,
                      color: AppColors.info.withOpacity(0.7),
                      strokeWidth: 1.5,
                      dashArray: [5, 5],
                      label: HorizontalLineLabel(
                        show: true,
                        alignment: Alignment.bottomRight,
                        padding: const EdgeInsets.only(right: 5, top: 2),
                        style: const TextStyle(
                          fontSize: 9,
                          color: AppColors.info,
                          fontWeight: FontWeight.bold,
                        ),
                        labelResolver: (line) =>
                            'Min (${thresholdMin.toStringAsFixed(0)}°C)',
                      ),
                    ),
                ],
              ),
              lineBarsData: [
                LineChartBarData(
                  spots: spots,
                  isCurved: false,
                  color: statusColor,
                  barWidth: 2.5,
                  isStrokeCapRound: true,
                  dotData: const FlDotData(show: false),
                  belowBarData: BarAreaData(
                    show: true,
                    color: statusColor.withOpacity(0.12),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// The status line above the chart.
  ///
  /// The server owns the alarm policy: an out-of-band reading is reported
  /// as information, and only a server-raised alert is shown as a breach.
  String get _statusLabel {
    if (currentTemp == null) return 'NO READING';
    if (alarmActive) return 'BREACH ALERT';
    if (!isSafe) {
      return alarmsEnabled ? 'OUTSIDE BAND' : 'OUTSIDE BAND (alarms off)';
    }
    return 'OPTIMAL SAFE';
  }

  Color get _statusColor {
    if (currentTemp == null) return Colors.grey;
    if (alarmActive) return AppColors.error;
    if (!isSafe) return AppColors.warning;
    return AppColors.success;
  }

  /// A round axis step (1, 2, 5, 10, 20, ...) for the given rough step.
  static double _niceStep(double rough) {
    if (rough <= 0 || !rough.isFinite) return 1;
    final double magnitude =
        math.pow(10, (math.log(rough) / math.ln10).floor()).toDouble();
    final double normalised = rough / magnitude;
    if (normalised <= 1) return magnitude;
    if (normalised <= 2) return 2 * magnitude;
    if (normalised <= 5) return 5 * magnitude;
    return 10 * magnitude;
  }

  static String _two(int value) => value.toString().padLeft(2, '0');

  /// Shown when the device has not reported any reading yet.
  Widget _emptyState(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'COLD STORAGE TELEMETRY (ESP32)',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
            color: Colors.grey,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          currentTemp == null ? '--' : '${currentTemp!.toStringAsFixed(1)}°C',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            color: Colors.grey,
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 180,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.timeline_rounded,
                  size: 34,
                  color: isDark ? Colors.white24 : Colors.black26,
                ),
                const SizedBox(height: 8),
                Text(
                  'No telemetry received yet',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white38 : Colors.black45,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'The chart starts as soon as the cold-chain device reports.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Colors.white24 : Colors.black38,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
