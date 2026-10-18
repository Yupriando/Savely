import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../core/config.dart';
import 'models.dart';
import 'token_store.dart';

export 'token_store.dart';

class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

/// Semua komunikasi ke backend Savely.
class ApiClient {
  // Server gratis (mis. Render) "tidur" saat lama tidak dipakai dan butuh ~30–60 detik untuk bangun.
  // Request ditahan selama server bangun, jadi batas tunggu jawabannya dibuat longgar.
  static const _connectTimeout = Duration(seconds: 20);
  static const _receiveTimeout = Duration(seconds: 75);
  static const _maxTransientRetries = 2;

  /// [adapter] hanya untuk test (server palsu).
  ApiClient(this.tokens, {required this.onSessionExpired, HttpClientAdapter? adapter})
    : _dio = Dio(
        BaseOptions(
          baseUrl: AppConfig.apiUrl,
          connectTimeout: _connectTimeout,
          receiveTimeout: _receiveTimeout,
          contentType: Headers.jsonContentType,
        ),
      ) {
    if (adapter != null) {
      _dio.httpClientAdapter = adapter;
      _plainDio.httpClientAdapter = adapter;
    }
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
    BaseOptions(baseUrl: AppConfig.apiUrl, connectTimeout: _connectTimeout, receiveTimeout: _receiveTimeout),
  );

  /// Gangguan sementara: jaringan putus, server sedang bangun / deploy ulang.
  static bool _isTransient(DioException e) {
    final status = e.response?.statusCode;
    return e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        status == 502 ||
        status == 503 ||
        status == 504;
  }

  /// Penanganan error:
  /// 1. Gangguan sementara pada request GET -> coba lagi (maks. 2x, jeda 2 lalu 4 detik).
  ///    POST/PATCH/DELETE tidak diulang supaya data tidak tercatat dobel.
  /// 2. Access token kedaluwarsa (401) -> perbarui pakai refresh token, lalu ulangi request.
  ///    Hanya logout kalau refresh token benar-benar ditolak server, bukan karena gangguan jaringan.
  Future<void> _refreshOnUnauthorized(DioException err, ErrorInterceptorHandler handler) async {
    final options = err.requestOptions;

    final attempt = (options.extra['transientRetry'] as int?) ?? 0;
    if (options.method == 'GET' && _isTransient(err) && attempt < _maxTransientRetries) {
      await Future<void>.delayed(Duration(seconds: 2 * (attempt + 1)));
      options.extra['transientRetry'] = attempt + 1;
      try {
        return handler.resolve(await _plainDio.fetch(options));
      } on DioException catch (e) {
        // Masih gagal: coba lagi lewat handler ini (tanpa antre ulang)
        return _refreshOnUnauthorized(e, handler);
      }
    }

    final refreshToken = tokens.refreshToken;
    final canRefresh =
        err.response?.statusCode == 401 &&
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
        return const ApiException(
          'Tidak bisa terhubung ke server. Cek internet kamu, atau coba lagi sebentar lagi.',
        );
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
        return const ApiException('Server sedang bangun atau sibuk. Tunggu sebentar lalu coba lagi.');
      default:
        return ApiException(
          'Terjadi kesalahan (${e.response?.statusCode ?? 'jaringan'})',
          statusCode: e.response?.statusCode,
        );
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
    await _send(
      () => _dio.post('/auth/register', data: {'email': email, 'password': password, 'full_name': name}),
    ),
  );

  Future<AppUser> me() async => _user(await _send(() => _dio.get('/auth/me')));

  Future<void> logout() => tokens.clear();

  Future<AppUser> updateProfile({String? fullName, String? email}) async =>
      _user(await _send(() => _dio.patch('/auth/me', data: {'full_name': ?fullName, 'email': ?email})));

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

  Future<void> createCategory({
    required String name,
    required TxType type,
    required String icon,
    required String color,
  }) => _send(
    () => _dio.post('/categories', data: {'name': name, 'type': type.name, 'icon': icon, 'color': color}),
  );

  Future<void> updateCategory(
    String id, {
    required String name,
    required String icon,
    required String color,
  }) => _send(() => _dio.patch('/categories/$id', data: {'name': name, 'icon': icon, 'color': color}));

  Future<void> deleteCategory(String id) => _send(() => _dio.delete('/categories/$id'));

  // ---------------- Transactions ----------------

  Future<TxPage> transactions({
    DateTime? start,
    DateTime? end,
    TxType? type,
    String? walletId,
    String? search,
    int page = 1,
    int limit = 30,
  }) async {
    final data = await _send(
      () => _dio.get(
        '/transactions',
        queryParameters: {
          if (start != null) 'start_date': _iso(start),
          if (end != null) 'end_date': _iso(end),
          if (type != null) 'type': type.name,
          'wallet_id': ?walletId,
          if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
          'page': page,
          'limit': limit,
        },
      ),
    );
    return TxPage(
      items: (data['data'] as List<dynamic>)
          .map((e) => Transaction.fromJson(e as Map<String, dynamic>))
          .toList(),
      total: (data['pagination']['total'] as num).toInt(),
    );
  }

  Map<String, dynamic> _txBody(
    TxType type,
    String categoryId,
    int amount,
    DateTime date,
    String? note,
    String? walletId,
  ) => {
    'type': type.name,
    'category_id': categoryId,
    'amount': amount,
    'transaction_date': _iso(date),
    'note': _nullIfEmpty(note),
    'wallet_id': ?walletId,
  };

  Future<void> createTransaction({
    required TxType type,
    required String categoryId,
    required int amount,
    required DateTime date,
    String? note,
    String? walletId,
  }) =>
      _send(() => _dio.post('/transactions', data: _txBody(type, categoryId, amount, date, note, walletId)));

  Future<void> updateTransaction(
    String id, {
    required TxType type,
    required String categoryId,
    required int amount,
    required DateTime date,
    String? note,
    String? walletId,
  }) => _send(
    () => _dio.patch('/transactions/$id', data: _txBody(type, categoryId, amount, date, note, walletId)),
  );

  Future<void> deleteTransaction(String id) => _send(() => _dio.delete('/transactions/$id'));

  /// File CSV (bytes) transaksi dalam rentang tanggal.
  Future<Uint8List> exportTransactions(DateTime start, DateTime end) async {
    try {
      final res = await _dio.get<List<int>>(
        '/transactions/export',
        queryParameters: {'start_date': _iso(start), 'end_date': _iso(end)},
        options: Options(responseType: ResponseType.bytes),
      );
      return Uint8List.fromList(res.data ?? const []);
    } on DioException catch (e) {
      throw _toApiException(e);
    }
  }

  // ---------------- Wallets ----------------

  Future<WalletsData> wallets({bool includeArchived = false}) async => WalletsData.fromJson(
    await _send(
      () => _dio.get('/wallets', queryParameters: {if (includeArchived) 'include_archived': 'true'}),
    ),
  );

  Future<void> createWallet(Map<String, dynamic> body) => _send(() => _dio.post('/wallets', data: body));

  Future<void> updateWallet(String id, Map<String, dynamic> body) =>
      _send(() => _dio.patch('/wallets/$id', data: body));

  Future<void> deleteWallet(String id) => _send(() => _dio.delete('/wallets/$id'));

  Future<List<Transfer>> transfers({DateTime? start, DateTime? end}) async {
    final data =
        await _send(
              () => _dio.get(
                '/wallets/transfers',
                queryParameters: {
                  if (start != null) 'start_date': _iso(start),
                  if (end != null) 'end_date': _iso(end),
                },
              ),
            )
            as List<dynamic>;
    return data.map((e) => Transfer.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> createTransfer({
    required String fromWalletId,
    required String toWalletId,
    required int amount,
    required DateTime date,
    String? note,
  }) => _send(
    () => _dio.post(
      '/wallets/transfers',
      data: {
        'from_wallet_id': fromWalletId,
        'to_wallet_id': toWalletId,
        'amount': amount,
        'transfer_date': _iso(date),
        'note': _nullIfEmpty(note),
      },
    ),
  );

  Future<void> deleteTransfer(String id) => _send(() => _dio.delete('/wallets/transfers/$id'));

  // ---------------- Budgets ----------------

  Future<BudgetReport> budgets(DateTime month) async => BudgetReport.fromJson(
    await _send(() => _dio.get('/budgets', queryParameters: {'month': _isoMonth(month)})),
  );

  Future<void> createBudget(String categoryId, int amount) =>
      _send(() => _dio.post('/budgets', data: {'category_id': categoryId, 'amount': amount}));

  Future<void> updateBudget(String id, int amount) =>
      _send(() => _dio.patch('/budgets/$id', data: {'amount': amount}));

  Future<void> deleteBudget(String id) => _send(() => _dio.delete('/budgets/$id'));

  // ---------------- Bills ----------------

  Future<BillsReport> bills(DateTime month) async => BillsReport.fromJson(
    await _send(() => _dio.get('/bills', queryParameters: {'month': _isoMonth(month)})),
  );

  Future<void> createBill(Map<String, dynamic> body) => _send(() => _dio.post('/bills', data: body));

  Future<void> updateBill(String id, Map<String, dynamic> body) =>
      _send(() => _dio.patch('/bills/$id', data: body));

  Future<void> deleteBill(String id) => _send(() => _dio.delete('/bills/$id'));

  Future<void> payBill(String id, {required DateTime month, int? amount, String? walletId, DateTime? date}) =>
      _send(
        () => _dio.post(
          '/bills/$id/pay',
          data: {
            'month': _isoMonth(month),
            'amount': ?amount,
            'wallet_id': ?walletId,
            if (date != null) 'date': _iso(date),
          },
        ),
      );

  Future<void> unpayBill(String id, DateTime month) =>
      _send(() => _dio.delete('/bills/$id/pay', queryParameters: {'month': _isoMonth(month)}));

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
  }) => _send(
    () => _dio.post(
      '/wishlists',
      data: {
        'name': name,
        'target_amount': targetAmount,
        'target_date': _iso(targetDate),
        'note': _nullIfEmpty(note),
      },
    ),
  );

  Future<void> updateWishlist(
    String id, {
    required String name,
    required int targetAmount,
    required DateTime targetDate,
    String? note,
  }) => _send(
    () => _dio.patch(
      '/wishlists/$id',
      data: {
        'name': name,
        'target_amount': targetAmount,
        'target_date': _iso(targetDate),
        'note': _nullIfEmpty(note),
      },
    ),
  );

  Future<void> deleteWishlist(String id) => _send(() => _dio.delete('/wishlists/$id'));

  /// amount positif = setor, negatif = tarik.
  Future<void> addSaving(
    String wishlistId, {
    required int amount,
    required DateTime date,
    String? note,
    String? walletId,
  }) => _send(
    () => _dio.post(
      '/wishlists/$wishlistId/savings',
      data: {'amount': amount, 'saving_date': _iso(date), 'note': _nullIfEmpty(note), 'wallet_id': ?walletId},
    ),
  );

  Future<void> updateSaving(
    String wishlistId,
    String savingId, {
    required int amount,
    required DateTime date,
    String? note,
    String? walletId,
  }) => _send(
    () => _dio.patch(
      '/wishlists/$wishlistId/savings/$savingId',
      data: {'amount': amount, 'saving_date': _iso(date), 'note': _nullIfEmpty(note), 'wallet_id': ?walletId},
    ),
  );

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
    final data =
        await _send(() => _dio.get('/reports/trend', queryParameters: {'months': months})) as List<dynamic>;
    return data.map((e) => MonthlyTotal.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<Insight>> insights(DateTime month) async {
    final data = await _send(
      () => _dio.get('/reports/insights', queryParameters: {'month': _isoMonth(month)}),
    );
    return (data['items'] as List<dynamic>).map((e) => Insight.fromJson(e as Map<String, dynamic>)).toList();
  }

  // ---------------- helpers ----------------

  static String _two(int n) => n.toString().padLeft(2, '0');
  static String _iso(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';
  static String _isoMonth(DateTime d) => '${d.year}-${_two(d.month)}';
  static String? _nullIfEmpty(String? s) => (s == null || s.trim().isEmpty) ? null : s.trim();
}
