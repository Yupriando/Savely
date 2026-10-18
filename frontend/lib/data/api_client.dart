import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/config.dart';
import 'models.dart';

class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class TokenStore {
  TokenStore(this._prefs);

  final SharedPreferences _prefs;
  static const _accessKey = 'access_token';
  static const _refreshKey = 'refresh_token';
  static const _userKey = 'cached_user';

  String? get accessToken => _prefs.getString(_accessKey);
  String? get refreshToken => _prefs.getString(_refreshKey);
  bool get hasSession => refreshToken != null;

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
    await _prefs.setString(_accessKey, session['access_token'] as String);
    await _prefs.setString(_refreshKey, session['refresh_token'] as String);
  }

  Future<void> saveUser(Map<String, dynamic> json) => _prefs.setString(_userKey, jsonEncode(json));

  Future<void> clear() async {
    await _prefs.remove(_accessKey);
    await _prefs.remove(_refreshKey);
    await _prefs.remove(_userKey);
  }
}

/// Semua komunikasi ke backend Savely.
class ApiClient {
  ApiClient(this.tokens, {required this.onSessionExpired})
      : _dio = Dio(
          BaseOptions(
            baseUrl: AppConfig.apiUrl,
            connectTimeout: const Duration(seconds: 10),
            receiveTimeout: const Duration(seconds: 20),
            contentType: Headers.jsonContentType,
          ),
        ) {
    _dio.interceptors.add(
      QueuedInterceptorsWrapper(onRequest: _attachToken, onError: _refreshOnUnauthorized),
    );
  }

  final Dio _dio;
  final TokenStore tokens;
  final void Function() onSessionExpired;

  static const _publicPaths = {'/auth/login', '/auth/register', '/auth/refresh'};

  void _attachToken(RequestOptions options, RequestInterceptorHandler handler) {
    final token = tokens.accessToken;
    if (token != null && !_publicPaths.contains(options.path)) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  /// Dio polos (tanpa interceptor) untuk refresh token & mengulang request,
  /// supaya tidak macet menunggu antrean interceptor yang sedang berjalan.
  late final _plainDio = Dio(
    BaseOptions(
      baseUrl: AppConfig.apiUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 20),
    ),
  );

  /// Access token kedaluwarsa (401) -> perbarui pakai refresh token, lalu ulangi request.
  /// Hanya logout kalau refresh token benar-benar ditolak server, bukan karena gangguan jaringan.
  Future<void> _refreshOnUnauthorized(DioException err, ErrorInterceptorHandler handler) async {
    final options = err.requestOptions;
    final refreshToken = tokens.refreshToken;
    final canRefresh = err.response?.statusCode == 401 &&
        !_publicPaths.contains(options.path) &&
        options.extra['retried'] != true &&
        refreshToken != null;

    if (!canRefresh) return handler.next(err);

    // Request lain di antrean sudah memperbarui token: cukup ulangi dengan token baru.
    final usedToken = (options.headers['Authorization'] as String?)?.replaceFirst('Bearer ', '');
    final currentToken = tokens.accessToken;
    if (currentToken != null && usedToken != currentToken) {
      return _retry(options, handler);
    }

    try {
      final res = await _plainDio.post('/auth/refresh', data: {'refresh_token': refreshToken});
      await tokens.save(res.data['session'] as Map<String, dynamic>);
    } on DioException catch (e) {
      final rejected = e.response?.statusCode == 401 || e.response?.statusCode == 400;
      if (rejected) {
        await tokens.clear();
        onSessionExpired();
      }
      return handler.next(err);
    }
    await _retry(options, handler);
  }

  Future<void> _retry(RequestOptions options, ErrorInterceptorHandler handler) async {
    options.extra['retried'] = true;
    options.headers['Authorization'] = 'Bearer ${tokens.accessToken}';
    try {
      handler.resolve(await _plainDio.fetch(options));
    } on DioException catch (e) {
      handler.next(e);
    }
  }

  Future<dynamic> _send(Future<Response<dynamic>> Function() request) async {
    try {
      return (await request()).data;
    } on DioException catch (e) {
      throw _toApiException(e);
    }
  }

  ApiException _toApiException(DioException e) {
    final data = e.response?.data;
    if (data is Map && data['error'] is Map && data['error']['message'] != null) {
      return ApiException(data['error']['message'] as String, statusCode: e.response?.statusCode);
    }
    switch (e.type) {
      case DioExceptionType.connectionError:
      case DioExceptionType.connectionTimeout:
        return const ApiException('Tidak bisa terhubung ke server. Pastikan backend sudah jalan.');
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
        return const ApiException('Server terlalu lama merespons. Coba lagi.');
      default:
        return ApiException('Terjadi kesalahan (${e.response?.statusCode ?? 'jaringan'})',
            statusCode: e.response?.statusCode);
    }
  }

  // ---------------- Auth ----------------

  /// Parse data user dari server sekaligus simpan salinannya di perangkat.
  Future<AppUser> _user(dynamic json) async {
    final map = json as Map<String, dynamic>;
    await tokens.saveUser(map);
    return AppUser.fromJson(map);
  }

  Future<AppUser> _handleAuth(dynamic data) async {
    final session = data['session'];
    if (session == null) {
      throw const ApiException('Akun dibuat. Cek email kamu untuk konfirmasi, lalu login.');
    }
    await tokens.save(session as Map<String, dynamic>);
    return _user(data['user']);
  }

  Future<AppUser> login(String email, String password) async =>
      _handleAuth(await _send(() => _dio.post('/auth/login', data: {'email': email, 'password': password})));

  Future<AppUser> register(String name, String email, String password) async => _handleAuth(
        await _send(() => _dio.post('/auth/register',
            data: {'email': email, 'password': password, 'full_name': name})),
      );

  Future<AppUser> me() async => _user(await _send(() => _dio.get('/auth/me')));

  Future<void> logout() => tokens.clear();

  Future<AppUser> updateProfile({String? fullName, String? email}) async => _user(
        await _send(() => _dio.patch('/auth/me', data: {
              'full_name': ?fullName,
              'email': ?email,
            })),
      );

  Future<AppUser> uploadAvatar(List<int> bytes, {required String filename, required String mimeType}) async {
    final form = FormData.fromMap({
      'avatar': MultipartFile.fromBytes(bytes, filename: filename, contentType: DioMediaType.parse(mimeType)),
    });
    return _user(await _send(() => _dio.post('/auth/me/avatar', data: form)));
  }

  Future<AppUser> removeAvatar() async => _user(await _send(() => _dio.delete('/auth/me/avatar')));

  // ---------------- Categories ----------------

  Future<List<Category>> categories() async {
    final data = await _send(() => _dio.get('/categories')) as List<dynamic>;
    return data.map((e) => Category.fromJson(e as Map<String, dynamic>)).toList();
  }

  // ---------------- Transactions ----------------

  Future<List<Transaction>> transactions({
    required DateTime start,
    required DateTime end,
    TxType? type,
    int limit = 100,
  }) async {
    final data = await _send(() => _dio.get('/transactions', queryParameters: {
          'start_date': _iso(start),
          'end_date': _iso(end),
          if (type != null) 'type': type.name,
          'limit': limit,
        }));
    return (data['data'] as List<dynamic>)
        .map((e) => Transaction.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> createTransaction({
    required TxType type,
    required String categoryId,
    required int amount,
    required DateTime date,
    String? note,
  }) =>
      _send(() => _dio.post('/transactions', data: {
            'type': type.name,
            'category_id': categoryId,
            'amount': amount,
            'transaction_date': _iso(date),
            'note': _nullIfEmpty(note),
          }));

  Future<void> updateTransaction(
    String id, {
    required TxType type,
    required String categoryId,
    required int amount,
    required DateTime date,
    String? note,
  }) =>
      _send(() => _dio.patch('/transactions/$id', data: {
            'type': type.name,
            'category_id': categoryId,
            'amount': amount,
            'transaction_date': _iso(date),
            'note': _nullIfEmpty(note),
          }));

  Future<void> deleteTransaction(String id) => _send(() => _dio.delete('/transactions/$id'));

  // ---------------- Wishlists ----------------

  Future<List<Wishlist>> wishlists() async {
    final data = await _send(() => _dio.get('/wishlists')) as List<dynamic>;
    return data.map((e) => Wishlist.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Wishlist> wishlist(String id) async =>
      Wishlist.fromJson(await _send(() => _dio.get('/wishlists/$id')) as Map<String, dynamic>);

  Future<void> createWishlist({
    required String name,
    required int targetAmount,
    required DateTime targetDate,
    String? note,
  }) =>
      _send(() => _dio.post('/wishlists', data: {
            'name': name,
            'target_amount': targetAmount,
            'target_date': _iso(targetDate),
            'note': _nullIfEmpty(note),
          }));

  Future<void> updateWishlist(
    String id, {
    required String name,
    required int targetAmount,
    required DateTime targetDate,
    String? note,
  }) =>
      _send(() => _dio.patch('/wishlists/$id', data: {
            'name': name,
            'target_amount': targetAmount,
            'target_date': _iso(targetDate),
            'note': _nullIfEmpty(note),
          }));

  Future<void> deleteWishlist(String id) => _send(() => _dio.delete('/wishlists/$id'));

  /// amount positif = setor, negatif = tarik.
  Future<void> addSaving(String wishlistId, {required int amount, required DateTime date, String? note}) =>
      _send(() => _dio.post('/wishlists/$wishlistId/savings', data: {
            'amount': amount,
            'saving_date': _iso(date),
            'note': _nullIfEmpty(note),
          }));

  Future<void> updateSaving(
    String wishlistId,
    String savingId, {
    required int amount,
    required DateTime date,
    String? note,
  }) =>
      _send(() => _dio.patch('/wishlists/$wishlistId/savings/$savingId', data: {
            'amount': amount,
            'saving_date': _iso(date),
            'note': _nullIfEmpty(note),
          }));

  Future<void> deleteSaving(String wishlistId, String savingId) =>
      _send(() => _dio.delete('/wishlists/$wishlistId/savings/$savingId'));

  // ---------------- Reports ----------------

  Future<MonthlyReport> monthlyReport(DateTime month) async => MonthlyReport.fromJson(
        await _send(() => _dio.get('/reports/monthly', queryParameters: {'month': _isoMonth(month)})),
      );

  Future<DailyReport> dailyReport(DateTime date) async => DailyReport.fromJson(
        await _send(() => _dio.get('/reports/daily', queryParameters: {'date': _iso(date)})),
      );

  Future<List<MonthlyTotal>> trend({int months = 6}) async {
    final data = await _send(() => _dio.get('/reports/trend', queryParameters: {'months': months}))
        as List<dynamic>;
    return data.map((e) => MonthlyTotal.fromJson(e as Map<String, dynamic>)).toList();
  }

  // ---------------- helpers ----------------

  static String _two(int n) => n.toString().padLeft(2, '0');
  static String _iso(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';
  static String _isoMonth(DateTime d) => '${d.year}-${_two(d.month)}';
  static String? _nullIfEmpty(String? s) => (s == null || s.trim().isEmpty) ? null : s.trim();
}
