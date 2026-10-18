import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/widgets.dart' show AppLifecycleListener, Color;
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Ref;

import 'api_client.dart';
import 'models.dart';
import 'providers.dart';

/// UUID v4 acak untuk menandai transaksi offline (anti-dobel di server).
String newClientId() {
  final r = Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}

String _hex(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

/// Transaksi yang dicatat di HP dan menunggu dikirim ke server.
class PendingTx {
  const PendingTx({
    required this.clientId,
    required this.type,
    required this.amount,
    required this.date,
    required this.category,
    this.wallet,
    this.note,
    this.error,
  });

  final String clientId;
  final TxType type;
  final int amount;
  final DateTime date;
  final Category category;
  final Ref? wallet;
  final String? note;

  /// Diisi kalau server menolak (mis. kategori sudah dihapus). Tidak dicoba ulang otomatis.
  final String? error;

  PendingTx copyWith({String? error, bool clearError = false}) => PendingTx(
    clientId: clientId,
    type: type,
    amount: amount,
    date: date,
    category: category,
    wallet: wallet,
    note: note,
    error: clearError ? null : (error ?? this.error),
  );

  Transaction toTransaction() => Transaction(
    id: 'local:$clientId',
    type: type,
    amount: amount,
    date: date,
    category: category,
    note: note,
    walletId: wallet?.id,
    wallet: wallet,
    pendingClientId: clientId,
    syncError: error,
  );

  Map<String, dynamic> toJson() => {
    'client_id': clientId,
    'type': type.name,
    'amount': amount,
    'date': date.toIso8601String(),
    'note': note,
    'error': error,
    'category': {
      'id': category.id,
      'name': category.name,
      'icon': category.icon,
      'color': _hex(category.color),
    },
    'wallet': wallet == null
        ? null
        : {'id': wallet!.id, 'name': wallet!.name, 'icon': wallet!.icon, 'color': _hex(wallet!.color)},
  };

  factory PendingTx.fromJson(Map<String, dynamic> j) {
    final type = TxType.parse(j['type'] as String);
    return PendingTx(
      clientId: j['client_id'] as String,
      type: type,
      amount: (j['amount'] as num).toInt(),
      date: DateTime.parse(j['date'] as String),
      category: Category.fromJson(j['category'] as Map<String, dynamic>, type: type),
      wallet: Ref.maybe(j['wallet']),
      note: j['note'] as String?,
      error: j['error'] as String?,
    );
  }
}

class SyncState {
  const SyncState({this.pending = const [], this.syncing = false});

  final List<PendingTx> pending;
  final bool syncing;

  int get failedCount => pending.where((p) => p.error != null).length;

  /// Transaksi antrean yang cocok dengan filter daftar transaksi.
  List<Transaction> matching({required DateTime month, TxType? type, String search = ''}) {
    final q = search.trim().toLowerCase();
    return pending
        .where((p) => p.date.year == month.year && p.date.month == month.month)
        .where((p) => type == null || p.type == type)
        .where(
          (p) =>
              q.isEmpty ||
              p.category.name.toLowerCase().contains(q) ||
              (p.note ?? '').toLowerCase().contains(q),
        )
        .map((p) => p.toTransaction())
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
  }

  SyncState copyWith({List<PendingTx>? pending, bool? syncing}) =>
      SyncState(pending: pending ?? this.pending, syncing: syncing ?? this.syncing);
}

final syncProvider = NotifierProvider<SyncController, SyncState>(SyncController.new);

/// Antrean transaksi offline + pengiriman otomatis saat internet tersedia.
class SyncController extends Notifier<SyncState> {
  static const storageKey = 'pending_transactions';
  static const _retryEvery = Duration(seconds: 15);

  Timer? _timer;
  StreamSubscription<List<ConnectivityResult>>? _connectivity;
  AppLifecycleListener? _lifecycle;

  @override
  SyncState build() {
    ref.onDispose(() {
      _timer?.cancel();
      _connectivity?.cancel();
      _lifecycle?.dispose();
    });
    _listenForConnection();

    // Server kembali bisa dihubungi -> kirim antrean & muat ulang data yang tadinya dari cache
    final api = ref.read(apiProvider);
    var wasOnline = api.online.value;
    void onOnlineChanged() {
      final online = api.online.value;
      if (online && !wasOnline) {
        syncNow();
        invalidateFinance(ref.invalidate);
      }
      wasOnline = online;
    }

    api.online.addListener(onOnlineChanged);
    ref.onDispose(() => api.online.removeListener(onOnlineChanged));

    // Setiap 15 detik: kirim antrean yang tersisa, dan selama offline cek apakah server
    // sudah bisa dihubungi lagi (cukup muat ulang data dompet yang kecil).
    _timer = Timer.periodic(_retryEvery, (_) {
      if (!api.online.value) ref.invalidate(walletsProvider);
      if (state.pending.any((p) => p.error == null)) syncNow();
    });

    final loaded = SyncState(pending: _load());
    if (loaded.pending.isNotEmpty) Future.microtask(syncNow);
    return loaded;
  }

  List<PendingTx> _load() {
    final raw = ref.read(sharedPrefsProvider).getString(storageKey);
    if (raw == null) return const [];
    try {
      return (jsonDecode(raw) as List<dynamic>)
          .map((e) => PendingTx.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('Antrean offline rusak, diabaikan: $e');
      return const [];
    }
  }

  Future<void> _save(List<PendingTx> list) async {
    state = state.copyWith(pending: list);
    await ref
        .read(sharedPrefsProvider)
        .setString(storageKey, jsonEncode(list.map((p) => p.toJson()).toList()));
  }

  /// Internet kembali / app dibuka lagi -> kirim antrean.
  void _listenForConnection() {
    try {
      _connectivity = Connectivity().onConnectivityChanged.listen((results) {
        if (results.any((r) => r != ConnectivityResult.none)) {
          Future<void>.delayed(const Duration(seconds: 1), () {
            syncNow();
            // Sebelumnya offline: muat ulang data supaya layar tidak lagi memakai data lama
            if (!ref.read(apiProvider).online.value) invalidateFinance(ref.invalidate);
          });
        }
      }, onError: (Object e) => debugPrint('Connectivity tidak tersedia: $e'));
    } catch (e) {
      debugPrint('Connectivity tidak tersedia: $e');
    }
    try {
      _lifecycle = AppLifecycleListener(onResume: syncNow);
    } catch (_) {}
  }

  Future<void> add(PendingTx tx) => _save([...state.pending, tx]);

  Future<void> replace(PendingTx tx) =>
      _save([for (final p in state.pending) p.clientId == tx.clientId ? tx : p]);

  Future<void> remove(String clientId) => _save(state.pending.where((p) => p.clientId != clientId).toList());

  /// Kirim semua antrean ke server, satu per satu sesuai urutan dicatat.
  /// Berhenti di gangguan jaringan pertama (dicoba lagi nanti). Kalau server menolak
  /// (mis. kategori dihapus), transaksi ditandai gagal supaya user bisa memperbaikinya.
  Future<void> syncNow({bool retryFailed = false}) async {
    if (state.syncing || state.pending.isEmpty) return;
    state = state.copyWith(syncing: true);
    final api = ref.read(apiProvider);
    var sent = 0;
    try {
      for (final p in [...state.pending]) {
        if (p.error != null && !retryFailed) continue;
        try {
          await api.createTransaction(
            type: p.type,
            categoryId: p.category.id,
            amount: p.amount,
            date: p.date,
            note: p.note,
            walletId: p.wallet?.id,
            clientId: p.clientId,
          );
          sent++;
          await _save(state.pending.where((x) => x.clientId != p.clientId).toList());
        } on ApiException catch (e) {
          if (e.isNetwork || e.statusCode == 401) break;
          await replace(p.copyWith(error: e.message));
        }
      }
    } finally {
      state = state.copyWith(syncing: false);
      if (sent > 0) invalidateFinance(ref.invalidate);
    }
  }

  /// Dipanggil saat logout: antrean milik akun ini dibuang.
  Future<void> clear() => _save(const []);
}
