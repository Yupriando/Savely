import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

/// Penyimpanan sesi login.
///
/// Token disimpan terenkripsi (Keystore Android, Keychain iOS/macOS,
/// Credential Manager Windows, WebCrypto di web). Isinya dimuat ke memori
/// sekali saat app dibuka, jadi pembacaan berikutnya instan.
class TokenStore {
  TokenStore._(this._prefs, this._secure, this._access, this._refresh, this._secureOk);

  final SharedPreferences _prefs;
  final FlutterSecureStorage _secure;
  String? _access;
  String? _refresh;

  /// false = penyimpanan aman tidak tersedia di perangkat ini, pakai shared_preferences.
  bool _secureOk;

  static const _accessKey = 'access_token';
  static const _refreshKey = 'refresh_token';
  static const _userKey = 'cached_user';

  static Future<TokenStore> load(
    SharedPreferences prefs, {
    FlutterSecureStorage secure = const FlutterSecureStorage(),
  }) async {
    String? access;
    String? refresh;
    var secureOk = true;
    try {
      access = await secure.read(key: _accessKey);
      refresh = await secure.read(key: _refreshKey);
    } catch (e) {
      debugPrint('Secure storage tidak tersedia, pakai shared_preferences: $e');
      secureOk = false;
    }

    final store = TokenStore._(prefs, secure, access, refresh, secureOk);

    // Versi lama menyimpan token di shared_preferences -> pindahkan (tanpa logout)
    final oldRefresh = prefs.getString(_refreshKey);
    if (refresh == null && oldRefresh != null) {
      store._access = prefs.getString(_accessKey);
      store._refresh = oldRefresh;
      await store._persist();
    } else if (!secureOk) {
      store._access = prefs.getString(_accessKey);
      store._refresh = oldRefresh;
    }
    return store;
  }

  String? get accessToken => _access;
  String? get refreshToken => _refresh;
  bool get hasSession => _refresh != null;

  /// Data user terakhir, supaya app tetap bisa dibuka walau server sedang tidak bisa dihubungi.
  AppUser? get cachedUser {
    final raw = _prefs.getString(_userKey);
    if (raw == null) return null;
    try {
      return AppUser.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> save(Map<String, dynamic> session) async {
    _access = session['access_token'] as String;
    _refresh = session['refresh_token'] as String;
    await _persist();
  }

  Future<void> saveUser(Map<String, dynamic> json) => _prefs.setString(_userKey, jsonEncode(json));

  Future<void> clear() async {
    _access = null;
    _refresh = null;
    await _persist();
    await _prefs.remove(_userKey);
  }

  Future<void> _persist() async {
    if (_secureOk) {
      try {
        await _write(_secure, _accessKey, _access);
        await _write(_secure, _refreshKey, _refresh);
        // Bersihkan sisa token lama yang tidak terenkripsi
        await _prefs.remove(_accessKey);
        await _prefs.remove(_refreshKey);
        return;
      } catch (e) {
        debugPrint('Gagal menulis secure storage, pakai shared_preferences: $e');
        _secureOk = false;
      }
    }
    await _writePrefs(_accessKey, _access);
    await _writePrefs(_refreshKey, _refresh);
  }

  static Future<void> _write(FlutterSecureStorage s, String key, String? value) =>
      value == null ? s.delete(key: key) : s.write(key: key, value: value);

  Future<void> _writePrefs(String key, String? value) =>
      value == null ? _prefs.remove(key) : _prefs.setString(key, value);
}
