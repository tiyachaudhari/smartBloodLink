import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Which data source the whole app shows.
///
/// [demo] keeps every module on the bundled simulation, so the app works
/// with no server and no hardware. [real] routes everything the VitaLink
/// server knows about through the server, and leaves the remaining modules
/// on their simulated data.
enum AppMode {
  demo,
  real,
}

/// Holds the app-wide Demo/Real choice and persists it between launches.
///
/// The choice is restored in `main()` before the widget tree is built, so
/// the first screen already renders in the right mode.
class AppModeProvider extends ChangeNotifier {
  AppModeProvider();

  /// Shared instance. The app provides it with `ChangeNotifierProvider.value`
  /// and the role providers read it to decide where their data comes from.
  static final AppModeProvider instance = AppModeProvider();

  static const String _kMode = 'app_mode';

  AppMode _mode = AppMode.demo;

  AppMode get mode => _mode;
  bool get isReal => _mode == AppMode.real;
  bool get isDemo => _mode == AppMode.demo;

  /// Restores the saved choice. Anything unexpected falls back to demo.
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kMode);
      _mode = raw == 'real' ? AppMode.real : AppMode.demo;
    } catch (_) {
      _mode = AppMode.demo;
    }
  }

  /// Switches mode and remembers the choice for the next launch.
  Future<void> setMode(AppMode mode) async {
    if (_mode == mode) return;
    _mode = mode;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kMode, mode == AppMode.real ? 'real' : 'demo');
    } catch (_) {}
  }
}
