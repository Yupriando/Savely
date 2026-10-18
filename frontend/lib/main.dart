import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/sound.dart';
import 'data/providers.dart';
import 'data/token_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('id_ID');
  final prefs = await SharedPreferences.getInstance();
  final tokens = await TokenStore.load(prefs);
  await SoundFx.init(enabled: prefs.getBool(SoundEnabledNotifier.key) ?? true);
  final online = await _hasNetwork();

  runApp(
    ProviderScope(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        tokenStoreProvider.overrideWithValue(tokens),
        initialOnlineProvider.overrideWithValue(online),
      ],
      child: const SavelyApp(),
    ),
  );
}

/// Cek cepat apakah HP terhubung ke jaringan (Wi-Fi/data). Kalau tidak bisa dicek, anggap online.
Future<bool> _hasNetwork() async {
  try {
    final results = await Connectivity().checkConnectivity().timeout(const Duration(seconds: 2));
    return results.any((r) => r != ConnectivityResult.none);
  } catch (_) {
    return true;
  }
}
