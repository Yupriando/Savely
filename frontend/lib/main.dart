import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'data/providers.dart';
import 'data/token_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('id_ID');
  final prefs = await SharedPreferences.getInstance();
  final tokens = await TokenStore.load(prefs);

  runApp(
    ProviderScope(
      overrides: [sharedPrefsProvider.overrideWithValue(prefs), tokenStoreProvider.overrideWithValue(tokens)],
      child: const SavelyApp(),
    ),
  );
}
