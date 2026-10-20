/// VitaLink server endpoints.
///
/// The app talks to the same server the ESP32 uses. Only `hospital` and
/// `admin` roles are allowed on these endpoints; the server enforces it.
class ApiConfig {
  ApiConfig._();

  static const String baseUrl = 'https://vitalapi.fenric.uk';
  static const String wsUrl = 'wss://vitalapi.fenric.uk/ws';
  static const Duration timeout = Duration(seconds: 12);
}
