import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart' show Color;
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Ref;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/data/api_client.dart';
import 'package:frontend/data/models.dart';
import 'package:frontend/data/offline_queue.dart';
import 'package:frontend/data/providers.dart';
import 'package:frontend/data/response_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Server palsu yang bisa "dimatikan": [handler] menentukan jawaban tiap request.
class _Server implements HttpClientAdapter {
  _Server(this.handler);

  ResponseBody Function(RequestOptions o, Map<String, dynamic>? body) handler;
  final requests = <String>[];
  final bodies = <Map<String, dynamic>>[];

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? stream, Future<void>? cancel) async {
    requests.add('${o.method} ${o.path}');
    Map<String, dynamic>? body;
    if (o.data is Map) body = Map<String, dynamic>.from(o.data as Map);
    if (body != null) bodies.add(body);
    return handler(o, body);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(Object data, [int status = 200]) => ResponseBody.fromString(
  jsonEncode(data),
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

ResponseBody _offline(RequestOptions o, Map<String, dynamic>? _) =>
    throw DioException.connectionError(requestOptions: o, reason: 'tidak ada internet');

Future<(ApiClient, SharedPreferences)> _api(_Server server, {bool initiallyOnline = true}) async {
  SharedPreferences.setMockInitialValues({});
  FlutterSecureStorage.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final tokens = await TokenStore.load(prefs);
  final api = ApiClient(
    tokens,
    onSessionExpired: () {},
    adapter: server,
    cache: ResponseCache(prefs),
    initiallyOnline: initiallyOnline,
  );
  return (api, prefs);
}

PendingTx _pending(String id, {int amount = 25000}) => PendingTx(
  clientId: id,
  type: TxType.expense,
  amount: amount,
  date: DateTime(2026, 10, 18),
  category: const Category(
    id: 'cat-1',
    name: 'Makanan & Minuman',
    icon: 'restaurant',
    color: Color(0xFFFF7043),
  ),
  wallet: const Ref(id: 'w-1', name: 'Tunai', icon: 'payments', color: Color(0xFF10B981)),
  note: 'Makan siang',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Cache data untuk offline', () {
    test('data terakhir dipakai saat offline, status jadi offline', () async {
      final server = _Server(
        (o, _) => _json([
          {'id': 'c1', 'name': 'Gaji', 'type': 'income', 'icon': 'payments', 'color': '#66BB6A'},
        ]),
      );
      final (api, _) = await _api(server);

      expect((await api.categories()).single.name, 'Gaji');
      expect(api.online.value, isTrue);

      server.handler = _offline;
      final offlineResult = await api.categories(); // 1x + 2x coba ulang, lalu cache
      expect(offlineResult.single.name, 'Gaji');
      expect(api.online.value, isFalse);
    });

    test('sudah diketahui offline -> langsung dari cache tanpa menunggu', () async {
      final server = _Server((o, _) => _json([]));
      final (api, prefs) = await _api(server);
      await api.categories(); // isi cache

      server.handler = _offline;
      api.online.value = false;
      final watch = Stopwatch()..start();
      await api.categories();
      expect(watch.elapsed, lessThan(const Duration(seconds: 1)));
      expect(server.requests.where((r) => r == 'GET /categories').length, 2, reason: 'tanpa coba ulang');
      expect(prefs.getStringList('http_cache_index'), contains('/categories'));
    });

    test('belum pernah dimuat & offline -> error jaringan yang jelas', () async {
      final (api, _) = await _api(_Server(_offline), initiallyOnline: false);
      await expectLater(
        api.categories(),
        throwsA(isA<ApiException>().having((e) => e.isNetwork, 'isNetwork', isTrue)),
      );
    });

    test('logout menghapus cache', () async {
      final (api, prefs) = await _api(_Server((o, _) => _json([])));
      await api.categories();
      await api.logout();
      expect(prefs.getStringList('http_cache_index'), isNull);
    });
  });

  group('Antrean transaksi offline', () {
    late _Server server;
    late ProviderContainer container;

    Future<void> setUpContainer() async {
      final (api, prefs) = await _api(server);
      container = ProviderContainer(
        overrides: [
          sharedPrefsProvider.overrideWithValue(prefs),
          tokenStoreProvider.overrideWithValue(api.tokens),
          apiProvider.overrideWithValue(api),
        ],
      );
      addTearDown(container.dispose);
    }

    SyncController sync() => container.read(syncProvider.notifier);
    List<PendingTx> pending() => container.read(syncProvider).pending;

    test('tersimpan saat offline, terkirim saat online, tidak dobel', () async {
      server = _Server(_offline);
      await setUpContainer();

      await sync().add(_pending('11111111-1111-4111-8111-111111111111'));
      await sync().add(_pending('22222222-2222-4222-8222-222222222222', amount: 50000));
      await sync().syncNow();
      expect(pending().length, 2, reason: 'offline: tetap di antrean');

      // Internet kembali
      server.handler = (o, body) => _json({'id': 'srv-${body!['client_id']}'}, 201);
      await sync().syncNow();
      expect(pending(), isEmpty);
      final posts = server.bodies.where((b) => b.containsKey('client_id')).toList();
      expect(posts.map((b) => b['client_id']).toSet().length, 2);
      expect(posts.last['amount'], 50000);
      expect(posts.last['wallet_id'], 'w-1');
    });

    test('server menjawab "sudah ada" (kirim ulang) dianggap berhasil', () async {
      server = _Server((o, body) => _json({'id': 'srv-lama'}, 200));
      await setUpContainer();
      await sync().add(_pending('33333333-3333-4333-8333-333333333333'));
      await sync().syncNow();
      expect(pending(), isEmpty);
    });

    test('ditolak server -> ditandai gagal, yang lain tetap terkirim', () async {
      server = _Server((o, body) {
        if (body?['client_id'] == '44444444-4444-4444-8444-444444444444') {
          return _json({
            'error': {'message': 'Referensi tidak valid (cek kategori dan tipe transaksi)'},
          }, 400);
        }
        return _json({'id': 'ok'}, 201);
      });
      await setUpContainer();
      await sync().add(_pending('44444444-4444-4444-8444-444444444444'));
      await sync().add(_pending('55555555-5555-4555-8555-555555555555'));
      await sync().syncNow();

      expect(pending().length, 1);
      expect(pending().single.error, contains('Referensi tidak valid'));
      expect(pending().single.toTransaction().syncError, isNotNull);

      // Tidak dicoba ulang otomatis (supaya tidak spam server)
      final before = server.requests.length;
      await sync().syncNow();
      expect(server.requests.length, before);
    });

    test('antrean bertahan setelah app ditutup & dibuka lagi', () async {
      server = _Server(_offline);
      await setUpContainer();
      await sync().add(_pending('66666666-6666-4666-8666-666666666666'));

      final prefs = container.read(sharedPrefsProvider);
      final reopened = ProviderContainer(
        overrides: [
          sharedPrefsProvider.overrideWithValue(prefs),
          tokenStoreProvider.overrideWithValue(container.read(tokenStoreProvider)),
          apiProvider.overrideWithValue(container.read(apiProvider)),
        ],
      );
      addTearDown(reopened.dispose);
      final restored = reopened.read(syncProvider).pending;
      expect(restored.single.clientId, '66666666-6666-4666-8666-666666666666');
      expect(restored.single.category.name, 'Makanan & Minuman');
      expect(restored.single.wallet?.name, 'Tunai');
    });

    test('daftar transaksi menampilkan antrean sesuai filter', () async {
      server = _Server(_offline);
      await setUpContainer();
      await sync().add(_pending('77777777-7777-4777-8777-777777777777'));
      final state = container.read(syncProvider);
      expect(state.matching(month: DateTime(2026, 10)).single.isPending, isTrue);
      expect(state.matching(month: DateTime(2026, 9)), isEmpty);
      expect(state.matching(month: DateTime(2026, 10), type: TxType.income), isEmpty);
      expect(state.matching(month: DateTime(2026, 10), search: 'makan'), hasLength(1));
      expect(state.matching(month: DateTime(2026, 10), search: 'bensin'), isEmpty);
    });
  });

  test('newClientId menghasilkan UUID v4 yang valid & unik', () {
    final ids = List.generate(200, (_) => newClientId());
    expect(ids.toSet().length, 200);
    expect(
      ids.every(
        (id) => RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$').hasMatch(id),
      ),
      isTrue,
    );
  });
}
