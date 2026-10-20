import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_blood_link/providers/app_mode_provider.dart';

/// Tests for the global Demo/Real switch.
///
/// The provider is a plain [ChangeNotifier] around one persisted preference,
/// so the tests only need the SharedPreferences mock.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const modeKey = 'app_mode';

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('AppModeProvider', () {
    test('a fresh provider starts in demo mode', () {
      final provider = AppModeProvider();

      expect(provider.mode, AppMode.demo);
      expect(provider.isDemo, isTrue);
      expect(provider.isReal, isFalse);
    });

    test('load restores the saved real mode', () async {
      SharedPreferences.setMockInitialValues({modeKey: 'real'});
      final provider = AppModeProvider();

      await provider.load();

      expect(provider.mode, AppMode.real);
      expect(provider.isReal, isTrue);
      expect(provider.isDemo, isFalse);
    });

    test('load falls back to demo for an unknown saved value', () async {
      SharedPreferences.setMockInitialValues({modeKey: 'not-a-mode'});
      final provider = AppModeProvider();

      await provider.load();

      expect(provider.mode, AppMode.demo,
          reason: 'an unreadable value must never put the app in real mode');
      expect(provider.isDemo, isTrue);
    });

    test('load falls back to demo when nothing was saved', () async {
      SharedPreferences.setMockInitialValues({});
      final provider = AppModeProvider();

      await provider.load();

      expect(provider.mode, AppMode.demo);
    });

    test('setMode persists the choice and notifies listeners', () async {
      SharedPreferences.setMockInitialValues({});
      final provider = AppModeProvider();
      var notifications = 0;
      provider.addListener(() => notifications++);

      await provider.setMode(AppMode.real);

      expect(provider.mode, AppMode.real);
      expect(notifications, 1);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(modeKey), 'real');
    });

    test('setMode with the same value does not notify again', () async {
      SharedPreferences.setMockInitialValues({});
      final provider = AppModeProvider();
      var notifications = 0;
      provider.addListener(() => notifications++);

      await provider.setMode(AppMode.real);
      expect(notifications, 1);

      await provider.setMode(AppMode.real);

      expect(provider.mode, AppMode.real);
      expect(notifications, 1,
          reason: 'an unchanged mode must not rebuild the widget tree');
    });

    test('switching back to demo persists the demo mode', () async {
      SharedPreferences.setMockInitialValues({});
      final provider = AppModeProvider();

      await provider.setMode(AppMode.real);
      await provider.setMode(AppMode.demo);

      expect(provider.mode, AppMode.demo);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(modeKey), 'demo');
    });
  });
}
