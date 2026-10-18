import 'package:flutter/foundation.dart';

class AppConfig {
  AppConfig._();

  /// Bisa di-override: flutter run --dart-define=API_URL=http://192.168.1.10:3000/api
  static const _apiUrlFromEnv = String.fromEnvironment('API_URL');

  static String get apiUrl {
    if (_apiUrlFromEnv.isNotEmpty) return _apiUrlFromEnv;
    // Emulator Android tidak bisa akses "localhost" laptop, harus lewat 10.0.2.2
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:3000/api';
    }
    return 'http://localhost:3000/api';
  }
}
