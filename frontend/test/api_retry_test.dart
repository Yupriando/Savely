import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/data/api_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Server palsu: gagal [failures] kali dulu (seperti server yang sedang bangun), lalu sukses.
class _FlakyServer implements HttpClientAdapter {
  _FlakyServer({required this.failures, this.failWith = 'connection'});

  final int failures;
  final String failWith;
  final calls = <String>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls.add('${options.method} ${options.path}');
    if (calls.length <= failures) {
      if (failWith == '503') {
        return ResponseBody.fromString(
          jsonEncode({
            'error': {'message': 'Service Unavailable'},
          }),
          503,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      }
      throw DioException.connectionError(requestOptions: options, reason: 'server tidur');
    }
    return ResponseBody.fromString(
      '[]',
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Future<ApiClient> _client(_FlakyServer server) async {
  SharedPreferences.setMockInitialValues({});
  FlutterSecureStorage.setMockInitialValues({});
  final tokens = await TokenStore.load(await SharedPreferences.getInstance());
  return ApiClient(tokens, onSessionExpired: () {}, adapter: server);
}

void main() {
  test('GET dicoba ulang saat server sedang bangun, lalu berhasil', () async {
    final server = _FlakyServer(failures: 2);
    final api = await _client(server);

    final result = await api.categories();

    expect(result, isEmpty);
    expect(server.calls, ['GET /categories', 'GET /categories', 'GET /categories']);
  });

  test('GET dicoba ulang juga saat server membalas 503 (sedang deploy)', () async {
    final server = _FlakyServer(failures: 1, failWith: '503');
    final api = await _client(server);

    await api.categories();
    expect(server.calls.length, 2);
  });

  test('menyerah setelah 2x coba ulang dan memberi pesan yang jelas', () async {
    final server = _FlakyServer(failures: 99);
    final api = await _client(server);

    await expectLater(
      api.categories(),
      throwsA(isA<ApiException>().having((e) => e.message, 'message', contains('Tidak bisa terhubung'))),
    );
    expect(server.calls.length, 3); // 1 percobaan + 2 ulang
  });

  test('POST TIDAK diulang (supaya transaksi tidak tercatat dobel)', () async {
    final server = _FlakyServer(failures: 1);
    final api = await _client(server);

    await expectLater(api.createBudget('kategori-1', 100000), throwsA(isA<ApiException>()));
    expect(server.calls, ['POST /budgets']);
  });
}
