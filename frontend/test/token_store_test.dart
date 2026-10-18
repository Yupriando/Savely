import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/data/api_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('sesi & data user tersimpan di perangkat, hilang saat logout', () async {
    SharedPreferences.setMockInitialValues({});
    final store = TokenStore(await SharedPreferences.getInstance());
    expect(store.hasSession, isFalse);
    expect(store.cachedUser, isNull);

    await store.save({'access_token': 'akses', 'refresh_token': 'refresh'});
    await store.saveUser({
      'id': 'u1',
      'email': 'yupri@mail.com',
      'full_name': 'Yupriando',
      'avatar_url': null,
    });

    // Buka app lagi (instance baru dari storage yang sama)
    final reopened = TokenStore(await SharedPreferences.getInstance());
    expect(reopened.hasSession, isTrue);
    expect(reopened.cachedUser?.displayName, 'Yupriando');

    await reopened.clear();
    expect(reopened.hasSession, isFalse);
    expect(reopened.cachedUser, isNull);
  });

  test('access token kedaluwarsa tetap dianggap login selama refresh token ada', () async {
    SharedPreferences.setMockInitialValues({'refresh_token': 'refresh'});
    final store = TokenStore(await SharedPreferences.getInstance());
    expect(store.hasSession, isTrue);
  });
}
