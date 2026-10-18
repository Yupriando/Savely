import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/export.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../widgets/common.dart';
import '../../widgets/transaction_tile.dart';
import 'transaction_form_sheet.dart';

class TransactionsScreen extends ConsumerStatefulWidget {
  const TransactionsScreen({super.key});

  @override
  ConsumerState<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends ConsumerState<TransactionsScreen> {
  int _filter = 0; // 0 semua, 1 masuk, 2 keluar
  final _searchCtrl = TextEditingController();
  final _scroll = ScrollController();
  String _search = '';
  Timer? _debounce;

  /// Id yang sudah di-swipe hapus, disembunyikan sampai data baru datang.
  final _removed = <String>{};

  TxType? get _type => switch (_filter) {
    1 => TxType.income,
    2 => TxType.expense,
    _ => null,
  };

  TxQuery get _query => (month: ref.read(selectedMonthProvider), type: _type, search: _search);

  @override
  void initState() {
    super.initState();
    // Hampir sampai bawah -> muat halaman berikutnya
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 400) {
        ref.read(pagedTransactionsProvider(_query).notifier).loadMore();
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (mounted) setState(() => _search = value.trim());
    });
  }

  Future<bool> _confirmDelete(Transaction t) async {
    final ok = await confirmDialog(
      context,
      title: 'Hapus transaksi?',
      message: '${t.category.name} ${rupiah(t.amount)} akan dihapus permanen.',
    );
    if (!ok) return false;
    try {
      await ref.read(apiProvider).deleteTransaction(t.id);
      return true;
    } catch (e) {
      if (mounted) showSnack(context, e.toString(), error: true);
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final month = ref.watch(selectedMonthProvider);
    final query = (month: month, type: _type, search: _search);
    final txs = ref.watch(pagedTransactionsProvider(query));
    final report = ref.watch(monthlyReportProvider(month)).valueOrNull;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Transaksi'),
        actions: [
          IconButton(
            tooltip: 'Ekspor ke CSV / Excel',
            onPressed: () => showExportDialog(context, ref, month: month),
            icon: const Icon(Icons.file_download_outlined),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'fab-tx',
        onPressed: () => showTransactionForm(context),
        child: const Icon(Icons.add_rounded),
      ),
      body: RefreshIndicator(
        onRefresh: () => refreshProviders(ref, [pagedTransactionsProvider, monthlyReportProvider]),
        child: ListView(
          controller: _scroll,
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 100),
          children: [
            MonthSwitcher(month: month, onChanged: (m) => ref.read(selectedMonthProvider.notifier).state = m),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _SummaryChip(
                    label: 'Masuk',
                    value: report?.summary.income,
                    color: AppColors.income,
                    icon: Icons.south_west_rounded,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _SummaryChip(
                    label: 'Keluar',
                    value: report?.summary.expense,
                    color: AppColors.expense,
                    icon: Icons.north_east_rounded,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _searchCtrl,
              onChanged: _onSearchChanged,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Cari catatan atau kategori…',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _searchCtrl.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Hapus pencarian',
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () {
                          _searchCtrl.clear();
                          _debounce?.cancel();
                          setState(() => _search = '');
                        },
                      ),
              ),
            ),
            const SizedBox(height: 12),
            PillTabs(
              labels: const ['Semua', 'Masuk', 'Keluar'],
              index: _filter,
              onChanged: (i) => setState(() => _filter = i),
            ),
            const SizedBox(height: 18),
            AsyncView(
              value: txs,
              onRetry: () => ref.invalidate(pagedTransactionsProvider),
              builder: (state) {
                final list = state.items.where((t) => !_removed.contains(t.id)).toList();
                if (list.isEmpty) {
                  return EmptyState(
                    icon: _search.isEmpty ? Icons.inbox_rounded : Icons.search_off_rounded,
                    title: _search.isEmpty ? 'Belum ada transaksi' : 'Tidak ditemukan',
                    subtitle: _search.isEmpty
                        ? 'Transaksi di ${monthLabel(month)} akan muncul di sini.'
                        : 'Tidak ada transaksi "$_search" di ${monthLabel(month)}.',
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(left: 4, bottom: 10),
                      child: Row(
                        children: [
                          Icon(Icons.touch_app_rounded, size: 14, color: context.colors.onSurfaceVariant),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              '${state.total} transaksi · ketuk untuk ubah, geser ke kiri untuk hapus',
                              style: context.text.labelSmall?.copyWith(
                                color: context.colors.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    KeyedSubtree(
                      key: ValueKey('${isoMonth(month)}-$_filter-$_search'),
                      child: _GroupedList(
                        transactions: list,
                        onTap: (t) => showTransactionForm(context, existing: t),
                        confirmDelete: _confirmDelete,
                        onDeleted: (t) {
                          setState(() => _removed.add(t.id));
                          refreshFinance(ref);
                          showSnack(context, 'Transaksi dihapus');
                        },
                      ),
                    ),
                    if (state.hasMore)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Center(
                          child: state.loadingMore
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(strokeWidth: 2.5),
                                )
                              : TextButton(
                                  onPressed: () =>
                                      ref.read(pagedTransactionsProvider(query).notifier).loadMore(),
                                  child: Text('Muat lagi (${state.total - state.items.length} lagi)'),
                                ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _GroupedList extends StatelessWidget {
  const _GroupedList({
    required this.transactions,
    required this.onTap,
    required this.confirmDelete,
    required this.onDeleted,
  });

  final List<Transaction> transactions;
  final void Function(Transaction) onTap;
  final Future<bool> Function(Transaction) confirmDelete;
  final void Function(Transaction) onDeleted;

  @override
  Widget build(BuildContext context) {
    // Kelompokkan per tanggal (data sudah terurut terbaru dulu)
    final groups = <DateTime, List<Transaction>>{};
    for (final t in transactions) {
      groups.putIfAbsent(dateOnly(t.date), () => []).add(t);
    }

    return Column(
      children:
          [
                for (final entry in groups.entries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _DayHeader(date: entry.key, items: entry.value),
                        const SizedBox(height: 8),
                        Card(
                          clipBehavior: Clip.antiAlias,
                          child: Column(
                            children: [
                              for (final t in entry.value)
                                Dismissible(
                                  key: ValueKey(t.id),
                                  direction: DismissDirection.endToStart,
                                  confirmDismiss: (_) => confirmDelete(t),
                                  onDismissed: (_) => onDeleted(t),
                                  background: Container(
                                    color: AppColors.expense,
                                    alignment: Alignment.centerRight,
                                    padding: const EdgeInsets.only(right: 24),
                                    child: const Icon(Icons.delete_rounded, color: Colors.white),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                                    child: TransactionTile(transaction: t, onTap: () => onTap(t)),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              ]
              .animate(interval: 60.ms)
              .fadeIn(duration: 350.ms)
              .moveY(begin: 16, end: 0, curve: Curves.easeOutCubic),
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.date, required this.items});

  final DateTime date;
  final List<Transaction> items;

  @override
  Widget build(BuildContext context) {
    final net = items.fold<int>(0, (sum, t) => sum + (t.type.isIncome ? t.amount : -t.amount));
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              relativeDay(date),
              style: context.text.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: context.colors.onSurfaceVariant,
              ),
            ),
          ),
          Text(
            signedRupiah(net, isIncome: net >= 0),
            style: context.text.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: net >= 0 ? AppColors.income : AppColors.expense,
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  const _SummaryChip({required this.label, required this.value, required this.color, required this.icon});

  final String label;
  final int? value;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(18)),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: context.text.labelSmall?.copyWith(color: color)),
                value == null
                    ? const SkeletonBox(height: 14, width: 60)
                    : AnimatedRupiah(
                        value!,
                        compact: value! >= 10000000,
                        style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800, color: color),
                      ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
