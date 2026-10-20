import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:smart_blood_link/models/iot_sensor_model.dart';
import 'package:smart_blood_link/widgets/temperature_chart_widget.dart';

/// Regression tests for the cold-chain chart.
///
/// The Y axis used to be fixed at 0-10 C, so every reading above 10 C was
/// drawn outside the visible area and the chart looked empty.
void main() {
  List<SensorReading> readingsAt(double temp, {int count = 12}) {
    final start = DateTime(2026, 10, 20, 14, 24);
    return List<SensorReading>.generate(
      count,
      (i) => SensorReading(
        readingId: 'r$i',
        deviceId: 'VL-ESP32-001',
        storageUnitName: 'Cold Unit A',
        hospitalId: 'h',
        temperature: temp,
        timestamp: start.add(Duration(minutes: i)),
      ),
    );
  }

  Widget wrap(Widget child) => MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: child)),
      );

  LineChartData chartData(WidgetTester tester) {
    final chart = tester.widget<LineChart>(find.byType(LineChart));
    return chart.data;
  }

  testWidgets('a reading above 10 C is still inside the visible range',
      (tester) async {
    await tester.pumpWidget(wrap(TemperatureChartWidget(
      readings: readingsAt(31.4),
      currentTemp: 31.4,
      isSafe: false,
      alarmsEnabled: false,
    )));
    await tester.pump();

    final data = chartData(tester);
    expect(data.maxY, greaterThan(31.4),
        reason: 'the scale must cover the reading or the line is invisible');
    expect(data.minY, lessThan(31.4));

    // The line itself must sit inside the chart area.
    final spots = data.lineBarsData.first.spots;
    expect(spots, isNotEmpty);
    for (final spot in spots) {
      expect(spot.y, lessThanOrEqualTo(data.maxY));
      expect(spot.y, greaterThanOrEqualTo(data.minY));
    }
  });

  testWidgets('a normal fridge reading keeps the 0-10 C scale', (tester) async {
    await tester.pumpWidget(wrap(TemperatureChartWidget(
      readings: readingsAt(4.0),
      currentTemp: 4.0,
      isSafe: true,
    )));
    await tester.pump();

    final data = chartData(tester);
    expect(data.maxY, 10.0);
    expect(data.lineBarsData.first.spots.first.y, 4.0);
  });

  testWidgets('the x axis uses the real time of the readings', (tester) async {
    await tester.pumpWidget(wrap(TemperatureChartWidget(
      readings: readingsAt(4.0, count: 6),
      currentTemp: 4.0,
      isSafe: true,
    )));
    await tester.pump();

    final data = chartData(tester);
    final spots = data.lineBarsData.first.spots;
    // Six readings one minute apart span five minutes.
    expect(spots.first.x, 0);
    expect(spots.last.x, 300);
  });

  testWidgets('no readings shows the empty state, not a fake line',
      (tester) async {
    await tester.pumpWidget(wrap(const TemperatureChartWidget(
      readings: [],
      currentTemp: null,
      isSafe: false,
    )));
    await tester.pump();

    expect(find.byType(LineChart), findsNothing);
    expect(find.text('No telemetry received yet'), findsOneWidget);
    expect(find.text('--'), findsOneWidget);
  });

  testWidgets('an out-of-band reading with alarms off is not called a breach',
      (tester) async {
    await tester.pumpWidget(wrap(TemperatureChartWidget(
      readings: readingsAt(31.4),
      currentTemp: 31.4,
      isSafe: false,
      alarmActive: false,
      alarmsEnabled: false,
    )));
    await tester.pump();

    expect(find.text('OUTSIDE BAND (alarms off)'), findsOneWidget);
    expect(find.text('BREACH ALERT'), findsNothing);
  });

  testWidgets('a server-raised alert is called a breach', (tester) async {
    await tester.pumpWidget(wrap(TemperatureChartWidget(
      readings: readingsAt(31.4),
      currentTemp: 31.4,
      isSafe: false,
      alarmActive: true,
      alarmsEnabled: true,
    )));
    await tester.pump();

    expect(find.text('BREACH ALERT'), findsOneWidget);
  });
}
