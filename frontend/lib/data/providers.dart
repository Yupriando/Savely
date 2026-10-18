import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/format.dart';
import 'api_client.dart';
import 'models.dart';

/// Di-override di main() setelah SharedPreferences siap.
final sharedPrefsProvider = Provider<SharedPreferences>((_) => throw UnimplementedError());

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

// ---------------- API & Auth ----------------

final apiProvider = Provider<ApiClient>((ref) {
  return ApiClient(
    TokenStore(ref.read(sharedPrefsProvider)),
    onSessionExpired: () => ref.read(authProvider.notifier).sessionExpired(),
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

typedef TxQuery = ({DateTime month, TxType? type});

final transactionsProvider = FutureProvider.autoDispose.family<List<Transaction>, TxQuery>((ref, q) {
  final start = DateTime(q.month.year, q.month.month);
  final end = DateTime(q.month.year, q.month.month + 1, 0);
  return ref.watch(apiProvider).transactions(start: start, end: end, type: q.type);
});

final monthlyReportProvider = FutureProvider.autoDispose.family<MonthlyReport, DateTime>(
  (ref, month) => ref.watch(apiProvider).monthlyReport(month),
);

final dailyReportProvider = FutureProvider.autoDispose.family<DailyReport, DateTime>(
  (ref, date) => ref.watch(apiProvider).dailyReport(date),
);

final trendProvider = FutureProvider.autoDispose<List<MonthlyTotal>>(
  (ref) => ref.watch(apiProvider).trend(months: 6),
);

final wishlistsProvider = FutureProvider.autoDispose<List<Wishlist>>(
  (ref) => ref.watch(apiProvider).wishlists(),
);

final wishlistDetailProvider = FutureProvider.autoDispose.family<Wishlist, String>(
  (ref, id) => ref.watch(apiProvider).wishlist(id),
);

/// Panggil setelah menambah/mengubah/menghapus data supaya semua layar ikut ter-update.
void refreshFinance(WidgetRef ref) {
  ref.invalidate(transactionsProvider);
  ref.invalidate(monthlyReportProvider);
  ref.invalidate(dailyReportProvider);
  ref.invalidate(trendProvider);
}

void refreshWishlists(WidgetRef ref) {
  ref.invalidate(wishlistsProvider);
  ref.invalidate(wishlistDetailProvider);
}
