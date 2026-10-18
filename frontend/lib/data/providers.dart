import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/format.dart';
import '../core/sound.dart';
import 'api_client.dart';
import 'response_cache.dart';
import 'models.dart';

/// Di-override di main() setelah SharedPreferences siap.
final sharedPrefsProvider = Provider<SharedPreferences>((_) => throw UnimplementedError());

/// false kalau HP tidak terhubung ke jaringan saat app dibuka (di-override di main()).
/// Dengan begitu app langsung memakai data terakhir tanpa menunggu percobaan ulang.
final initialOnlineProvider = Provider<bool>((_) => true);

/// Di-override di main() setelah sesi login dimuat dari penyimpanan aman.
final tokenStoreProvider = Provider<TokenStore>((_) => throw UnimplementedError());

// ---------------- Tema ----------------

final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);

class ThemeModeNotifier extends Notifier<ThemeMode> {
  static const _key = 'theme_mode';

  @override
  ThemeMode build() {
    final saved = ref.read(sharedPrefsProvider).getString(_key);
    return ThemeMode.values.firstWhere((m) => m.name == saved, orElse: () => ThemeMode.system);
  }

  void set(ThemeMode mode) {
    state = mode;
    ref.read(sharedPrefsProvider).setString(_key, mode.name);
  }
}

// ---------------- Efek suara ----------------

final soundEnabledProvider = NotifierProvider<SoundEnabledNotifier, bool>(SoundEnabledNotifier.new);

class SoundEnabledNotifier extends Notifier<bool> {
  static const key = 'sound_enabled';

  @override
  bool build() => ref.read(sharedPrefsProvider).getBool(key) ?? true;

  void set(bool enabled) {
    state = enabled;
    SoundFx.enabled = enabled;
    ref.read(sharedPrefsProvider).setBool(key, enabled);
    if (enabled) SoundFx.play(Sfx.success); // contoh bunyinya
  }
}

// ---------------- API & Auth ----------------

final apiProvider = Provider<ApiClient>((ref) {
  return ApiClient(
    ref.read(tokenStoreProvider),
    onSessionExpired: () => ref.read(authProvider.notifier).sessionExpired(),
    cache: ResponseCache(ref.read(sharedPrefsProvider)),
    initiallyOnline: ref.read(initialOnlineProvider),
  );
});

final authProvider = AsyncNotifierProvider<AuthNotifier, AppUser?>(AuthNotifier.new);

class AuthNotifier extends AsyncNotifier<AppUser?> {
  ApiClient get _api => ref.read(apiProvider);

  @override
  Future<AppUser?> build() async {
    // Pernah login di perangkat ini -> langsung masuk tanpa login ulang
    if (!_api.tokens.hasSession) return null;
    try {
      return await _api.me();
    } on ApiException catch (e) {
      // Sesi benar-benar tidak berlaku lagi (mis. logout dari tempat lain)
      if (e.statusCode == 401) {
        await _api.logout();
        return null;
      }
      // Server/jaringan bermasalah: tetap masuk pakai data user tersimpan,
      // data keuangan akan dimuat ulang saat koneksi kembali.
      final cached = _api.tokens.cachedUser;
      if (cached != null) return cached;
      rethrow;
    }
  }

  Future<void> login(String email, String password) async {
    state = AsyncData(await _api.login(email, password));
  }

  Future<void> register(String name, String email, String password) async {
    state = AsyncData(await _api.register(name, email, password));
  }

  Future<void> logout() async {
    await _api.logout();
    state = const AsyncData(null);
  }

  void sessionExpired() => state = const AsyncData(null);

  Future<AppUser> updateProfile({String? fullName, String? email}) async {
    final user = await _api.updateProfile(fullName: fullName, email: email);
    state = AsyncData(user);
    return user;
  }

  Future<void> uploadAvatar(List<int> bytes, {required String filename, required String mimeType}) async {
    state = AsyncData(await _api.uploadAvatar(bytes, filename: filename, mimeType: mimeType));
  }

  Future<void> removeAvatar() async {
    state = AsyncData(await _api.removeAvatar());
  }
}

// ---------------- Jam ----------------

/// Jam sistem, diperbarui tiap 20 detik (untuk sapaan & pergantian hari).
final clockProvider = StreamProvider<DateTime>((ref) async* {
  yield DateTime.now();
  yield* Stream.periodic(const Duration(seconds: 20), (_) => DateTime.now());
});

/// Tanggal hari ini; hanya berubah saat lewat tengah malam.
final todayProvider = Provider<DateTime>(
  (ref) => dateOnly(ref.watch(clockProvider).valueOrNull ?? DateTime.now()),
);

// ---------------- Navigasi shell ----------------

final shellTabProvider = StateProvider<int>((_) => 0);

// ---------------- Data keuangan ----------------

final categoriesProvider = FutureProvider.autoDispose<List<Category>>(
  (ref) => ref.watch(apiProvider).categories(),
);

/// Bulan yang sedang dilihat di tab Transaksi.
final selectedMonthProvider = StateProvider<DateTime>((_) => monthOnly(DateTime.now()));

/// 5 transaksi terbaru (semua bulan) untuk Beranda.
final recentTransactionsProvider = FutureProvider.autoDispose<List<Transaction>>(
  (ref) async => (await ref.watch(apiProvider).transactions(limit: 5)).items,
);

typedef TxQuery = ({DateTime month, TxType? type, String search});

class TxListState {
  const TxListState({required this.items, required this.total, this.loadingMore = false});

  final List<Transaction> items;
  final int total;
  final bool loadingMore;

  bool get hasMore => items.length < total;

  TxListState copyWith({List<Transaction>? items, int? total, bool? loadingMore}) => TxListState(
    items: items ?? this.items,
    total: total ?? this.total,
    loadingMore: loadingMore ?? this.loadingMore,
  );
}

/// Daftar transaksi per bulan, dimuat bertahap (30 per halaman) saat di-scroll.
final pagedTransactionsProvider = AsyncNotifierProvider.autoDispose
    .family<PagedTransactions, TxListState, TxQuery>(PagedTransactions.new);

class PagedTransactions extends AutoDisposeFamilyAsyncNotifier<TxListState, TxQuery> {
  static const _pageSize = 30;
  int _page = 1;

  Future<TxPage> _fetch(int page) {
    final q = arg;
    return ref
        .read(apiProvider)
        .transactions(
          start: DateTime(q.month.year, q.month.month),
          end: DateTime(q.month.year, q.month.month + 1, 0),
          type: q.type,
          search: q.search,
          page: page,
          limit: _pageSize,
        );
  }

  @override
  Future<TxListState> build(TxQuery arg) async {
    _page = 1;
    final page = await _fetch(1);
    return TxListState(items: page.items, total: page.total);
  }

  Future<void> loadMore() async {
    final current = state.valueOrNull;
    if (current == null || !current.hasMore || current.loadingMore) return;
    state = AsyncData(current.copyWith(loadingMore: true));
    try {
      final next = await _fetch(_page + 1);
      _page++;
      state = AsyncData(current.copyWith(items: [...current.items, ...next.items], total: next.total));
    } catch (_) {
      state = AsyncData(current.copyWith(loadingMore: false));
    }
  }
}

final monthlyReportProvider = FutureProvider.autoDispose.family<MonthlyReport, DateTime>(
  (ref, month) => ref.watch(apiProvider).monthlyReport(month),
);

final dailyReportProvider = FutureProvider.autoDispose.family<DailyReport, DateTime>(
  (ref, date) => ref.watch(apiProvider).dailyReport(date),
);

final trendProvider = FutureProvider.autoDispose<List<MonthlyTotal>>(
  (ref) => ref.watch(apiProvider).trend(months: 6),
);

final insightsProvider = FutureProvider.autoDispose.family<List<Insight>, DateTime>(
  (ref, month) => ref.watch(apiProvider).insights(month),
);

final walletsProvider = FutureProvider.autoDispose<WalletsData>((ref) => ref.watch(apiProvider).wallets());

final allWalletsProvider = FutureProvider.autoDispose<WalletsData>(
  (ref) => ref.watch(apiProvider).wallets(includeArchived: true),
);

final transfersProvider = FutureProvider.autoDispose.family<List<Transfer>, DateTime>((ref, month) {
  return ref
      .watch(apiProvider)
      .transfers(start: DateTime(month.year, month.month), end: DateTime(month.year, month.month + 1, 0));
});

final budgetsProvider = FutureProvider.autoDispose.family<BudgetReport, DateTime>(
  (ref, month) => ref.watch(apiProvider).budgets(month),
);

final billsProvider = FutureProvider.autoDispose.family<BillsReport, DateTime>(
  (ref, month) => ref.watch(apiProvider).bills(month),
);

final wishlistsProvider = FutureProvider.autoDispose<List<Wishlist>>(
  (ref) => ref.watch(apiProvider).wishlists(),
);

final wishlistDetailProvider = FutureProvider.autoDispose.family<Wishlist, String>(
  (ref, id) => ref.watch(apiProvider).wishlist(id),
);

/// Panggil setelah menambah/mengubah/menghapus data supaya semua layar ikut ter-update.
void refreshFinance(WidgetRef ref) => invalidateFinance(ref.invalidate);

/// Versi umum [refreshFinance]: bisa dipanggil dari widget maupun dari Notifier (mis. antrean offline).
void invalidateFinance(void Function(ProviderOrFamily) invalidate) {
  for (final p in <ProviderOrFamily>[
    recentTransactionsProvider,
    pagedTransactionsProvider,
    monthlyReportProvider,
    dailyReportProvider,
    trendProvider,
    insightsProvider,
    walletsProvider,
    allWalletsProvider,
    transfersProvider,
    budgetsProvider,
    billsProvider,
  ]) {
    invalidate(p);
  }
}

/// Tabungan wishlist juga mengubah saldo dompet & ringkasan "ditabung".
void refreshWishlists(WidgetRef ref) {
  ref.invalidate(wishlistsProvider);
  ref.invalidate(wishlistDetailProvider);
  refreshFinance(ref);
}

void refreshCategories(WidgetRef ref) {
  ref.invalidate(categoriesProvider);
  refreshFinance(ref);
}
