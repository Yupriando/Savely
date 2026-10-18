import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/data/token_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('sesi tersimpan terenkripsi, bertahan saat app dibuka ulang, hilang saat logout', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = await TokenStore.load(prefs);
    expect(store.hasSession, isFalse);

    await store.save({'access_token': 'akses', 'refresh_token': 'refresh'});
    await store.saveUser({'id': 'u1', 'email': 'yupri@mail.com', 'full_name': 'Yupriando'});

    // Token TIDAK disimpan polos di shared_preferences
    expect(prefs.getString('access_token'), isNull);
    expect(prefs.getString('refresh_token'), isNull);

    // Buka app lagi
    final reopened = await TokenStore.load(prefs);
    expect(reopened.hasSession, isTrue);
    expect(reopened.accessToken, 'akses');
    expect(reopened.cachedUser?.displayName, 'Yupriando');

    await reopened.clear();
    final afterLogout = await TokenStore.load(prefs);
    expect(afterLogout.hasSession, isFalse);
    expect(afterLogout.cachedUser, isNull);
  });

  test('token dari versi lama (shared_preferences) dipindah tanpa logout', () async {
    SharedPreferences.setMockInitialValues({'access_token': 'lama-akses', 'refresh_token': 'lama-refresh'});
    final prefs = await SharedPreferences.getInstance();

    final store = await TokenStore.load(prefs);
    expect(store.hasSession, isTrue);
    expect(store.refreshToken, 'lama-refresh');
    // Sisa token polos dibersihkan setelah dipindah
    expect(prefs.getString('refresh_token'), isNull);

    final reopened = await TokenStore.load(prefs);
    expect(reopened.refreshToken, 'lama-refresh');
  });
}
