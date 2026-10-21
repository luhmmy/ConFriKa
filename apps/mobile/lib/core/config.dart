/// App-wide configuration.
///
/// The backend base URL defaults to the Android-emulator loopback alias
/// (10.0.2.2 maps to the host machine's localhost). Override at build time:
///   flutter run --dart-define=API_BASE_URL=https://api.confrika.com
class AppConfig {
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000',
  );

  /// WebSocket base derived from the API base URL (http->ws, https->wss).
  static String get wsBaseUrl {
    if (apiBaseUrl.startsWith('https')) {
      return apiBaseUrl.replaceFirst('https', 'wss');
    }
    return apiBaseUrl.replaceFirst('http', 'ws');
  }
}
