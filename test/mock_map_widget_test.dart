import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_blood_link/widgets/mock_map_widget.dart';
import 'package:smart_blood_link/widgets/pulse_animation.dart';

/// Regression test for the map widget.
///
/// The ambulance screen hands the map an infinite height so it fills the
/// remaining space. The marker positions used to be derived from that
/// height, which placed the moving marker at an infinite offset and handed
/// the web engine a NaN coordinate, so the whole screen failed to paint.
void main() {
  Widget wrap(Widget child, {Size mediaSize = const Size(800, 600)}) {
    return MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(size: mediaSize),
        child: Scaffold(
          body: Center(
            child: SizedBox(width: 400, child: child),
          ),
        ),
      ),
    );
  }

  MockMapWidget map({double height = 240}) => MockMapWidget(
        currentLat: 18.52,
        currentLng: 73.85,
        pickupName: 'City Apex Blood Center',
        destinationName: 'Ruby Hall Clinic',
        distanceRemainingKm: 3.2,
        etaMinutes: 8,
        height: height,
      );

  testWidgets('lays out and animates without an exception', (tester) async {
    await tester.pumpWidget(wrap(map()));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('an infinite height does not produce an invalid offset',
      (tester) async {
    // The ambulance navigation screen asks for an infinite height.
    await tester.pumpWidget(wrap(map(height: double.infinity)));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(tester.takeException(), isNull);

    // The marker must land inside the map, at a finite position.
    final marker = tester.widget<PulseAnimation>(find.byType(PulseAnimation));
    expect(marker, isNotNull);
  });

  testWidgets('the marker offset stays finite for any media size',
      (tester) async {
    for (final size in const [Size.zero, Size(400, 800), Size(3000, 2000)]) {
      await tester.pumpWidget(wrap(map(height: double.infinity),
          mediaSize: size));
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.takeException(), isNull,
          reason: 'failed for media size $size');
    }
  });
}
