import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Salinan terakhir respons GET dari server, disimpan di perangkat.
/// Dipakai saat offline supaya layar tetap menampilkan data terakhir.
class ResponseCache {
  ResponseCache(this._prefs, {this.maxEntries = 120});

  final SharedPreferences _prefs;
  final int maxEntries;

  static const _prefix = 'http_cache:';
  static const _indexKey = 'http_cache_index';

  /// Urutan kunci dari yang paling lama dipakai -> paling baru (untuk membuang yang lama).
  List<String> get _index => _prefs.getStringList(_indexKey) ?? const [];

  dynamic read(String key) {
    final raw = _prefs.getString('$_prefix$key');
    if (raw == null) return null;
    try {
      return jsonDecode(raw);
    } catch (_) {
      return null;
    }
  }

  Future<void> write(String key, dynamic data) async {
    final encoded = jsonEncode(data);
    // Tidak menulis ulang kalau isinya sama (hemat penulisan ke penyimpanan)
    if (_prefs.getString('$_prefix$key') == encoded) return;
    await _prefs.setString('$_prefix$key', encoded);

    final index = [..._index.where((k) => k != key), key];
    while (index.length > maxEntries) {
      await _prefs.remove('$_prefix${index.removeAt(0)}');
    }
    await _prefs.setStringList(_indexKey, index);
  }

  /// Hapus semua (dipanggil saat logout supaya data tidak terlihat akun lain).
  Future<void> clear() async {
    for (final k in _index) {
      await _prefs.remove('$_prefix$k');
    }
    await _prefs.remove(_indexKey);
  }

  /// Kunci cache: path + query yang diurutkan.
  static String keyFor(String path, Map<String, dynamic> query) {
    if (query.isEmpty) return path;
    final keys = query.keys.toList()..sort();
    return '$path?${keys.map((k) => '$k=${query[k]}').join('&')}';
  }
}
