import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../widgets/category_icon.dart';
import '../../widgets/celebration.dart';
import '../../widgets/common.dart';
import '../../widgets/pickers.dart';

void openBudgets(BuildContext context) {
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const BudgetsScreen()));
}

Color budgetColor(BudgetStatus s) => switch (s) {
  BudgetStatus.safe => AppColors.income,
  BudgetStatus.warning => AppColors.gold,
  BudgetStatus.over => AppColors.expense,
};

class BudgetsScreen extends ConsumerStatefulWidget {
  const BudgetsScreen({super.key});

  @override
  ConsumerState<BudgetsScreen> createState() => _BudgetsScreenState();
}

class _BudgetsScreenState extends ConsumerState<BudgetsScreen> {
  DateTime _month = monthOnly(DateTime.now());

  @override
  Widget build(BuildContext context) {
    final report = ref.watch(budgetsProvider(_month));

    return Scaffold(
      appBar: AppBar(title: const Text('Anggaran')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab-budget',
        onPressed: () => showBudgetForm(context, used: report.valueOrNull?.items ?? const []),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Anggaran baru'),
      ),
      body: RefreshIndicator(
        onRefresh: () => refreshProviders(ref, [budgetsProvider]),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 100),
          children: [
            MonthSwitcher(month: _month, onChanged: (m) => setState(() => _month = m)),
            const SizedBox(height: 16),
            AsyncView(
              value: report,
              onRetry: () => ref.invalidate(budgetsProvider),
              builder: (r) {
                if (r.items.isEmpty) {
                  return const EmptyState(
                    icon: Icons.track_changes_rounded,
                    title: 'Belum ada anggaran',
                    subtitle:
                        'Tentukan batas pengeluaran per kategori, misalnya Makanan Rp1,5 jt per bulan. Savely akan mengingatkan kalau hampir habis.',
                  );
                }
                return Column(
                  key: ValueKey(_month),
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _TotalBudgetCard(report: r),
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.only(left: 4, bottom: 8),
                      child: Text(
                        'Ketuk untuk ubah batas atau hapus',
                        style: context.text.labelSmall?.copyWith(color: context.colors.onSurfaceVariant),
                      ),
                    ),
                    for (final b in r.items)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: BudgetTile(
                          budget: b,
                          onTap: () => showBudgetForm(context, existing: b),
                        ),
                      ),
                  ].animate(interval: 60.ms).fadeIn(duration: 350.ms).moveY(begin: 14, end: 0),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _TotalBudgetCard extends StatelessWidget {
  const _TotalBudgetCard({required this.report});

  final BudgetReport report;

  @override
  Widget build(BuildContext context) {
    final r = report;
    final percent = r.totalBudget == 0 ? 0.0 : r.totalSpent / r.totalBudget;
    final status = percent >= 1
        ? BudgetStatus.over
        : percent >= 0.8
        ? BudgetStatus.warning
        : BudgetStatus.safe;
    final color = budgetColor(status);
    final remaining = r.totalBudget - r.totalSpent;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Total anggaran',
              style: context.text.bodyMedium?.copyWith(color: context.colors.onSurfaceVariant),
            ),
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                AnimatedRupiah(
                  r.totalSpent,
                  style: context.text.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 3, left: 6),
                  child: Text(
                    '/ ${rupiah(r.totalBudget)}',
                    style: context.text.bodyMedium?.copyWith(color: context.colors.onSurfaceVariant),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            AnimatedProgressBar(value: percent, color: color, height: 12),
            const SizedBox(height: 8),
            Text(
              remaining >= 0 ? 'Sisa ${rupiah(remaining)}' : 'Lebih ${rupiah(-remaining)} dari anggaran',
              style: context.text.labelLarge?.copyWith(color: color, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

/// Satu baris anggaran: ikon kategori, terpakai/batas, progress berwarna.
class BudgetTile extends StatelessWidget {
  const BudgetTile({super.key, required this.budget, this.onTap, this.compact = false});

  final Budget budget;
  final VoidCallback? onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final b = budget;
    final color = budgetColor(b.status);
    final content = Row(
      children: [
        CategoryIcon(icon: b.category.icon, color: b.category.color, size: compact ? 36 : 42),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      b.category.name,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  Text(
                    '${b.percent.toStringAsFixed(0)}%',
                    style: context.text.labelLarge?.copyWith(color: color, fontWeight: FontWeight.w800),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              AnimatedProgressBar(value: b.percent / 100, color: color, height: 8),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${rupiah(b.spent)} / ${rupiah(b.amount)}',
                      style: context.text.labelSmall?.copyWith(color: context.colors.onSurfaceVariant),
                    ),
                  ),
                  Text(
                    b.remaining >= 0
                        ? 'sisa ${rupiahCompact(b.remaining)}'
                        : 'lebih ${rupiahCompact(-b.remaining)}',
                    style: context.text.labelSmall?.copyWith(color: color, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );

    if (compact) return Pressable(onTap: onTap, child: content);
    return Pressable(
      onTap: onTap,
      child: Card(
        child: Padding(padding: const EdgeInsets.all(16), child: content),
      ),
    );
  }
}

// =============================================================
// Form anggaran
// =============================================================

Future<void> showBudgetForm(BuildContext context, {Budget? existing, List<Budget> used = const []}) =>
    showFormSheet<void>(context, _BudgetForm(existing: existing, used: used));

class _BudgetForm extends ConsumerStatefulWidget {
  const _BudgetForm({this.existing, this.used = const []});

  final Budget? existing;
  final List<Budget> used;

  @override
  ConsumerState<_BudgetForm> createState() => _BudgetFormState();
}

class _BudgetFormState extends ConsumerState<_BudgetForm> {
  late final _amount = TextEditingController(
    text: widget.existing != null ? formatThousands(widget.existing!.amount) : '',
  );
  String? _categoryId;
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amount = parseAmount(_amount.text);
    if (!_isEdit && _categoryId == null) return showSnack(context, 'Pilih kategori dulu', error: true);
    if (amount <= 0) return showSnack(context, 'Masukkan batas anggaran', error: true);

    setState(() => _saving = true);
    try {
      final api = ref.read(apiProvider);
      _isEdit
          ? await api.updateBudget(widget.existing!.id, amount)
          : await api.createBudget(_categoryId!, amount);
      refreshFinance(ref);
      if (!mounted) return;
      Navigator.pop(context);
      showSuccess(context, _isEdit ? 'Anggaran diperbarui' : 'Anggaran dibuat');
    } catch (e) {
      if (mounted) showSnack(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final b = widget.existing!;
    final ok = await confirmDialog(
      context,
      title: 'Hapus anggaran?',
      message: 'Anggaran ${b.category.name} akan dihapus. Transaksi tidak terpengaruh.',
    );
    if (!ok || !mounted) return;
    try {
      await ref.read(apiProvider).deleteBudget(b.id);
      refreshFinance(ref);
      if (!mounted) return;
      Navigator.pop(context);
      showSnack(context, 'Anggaran dihapus');
    } catch (e) {
      if (mounted) showSnack(context, e.toString(), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(categoriesProvider);
    final usedIds = widget.used.map((b) => b.categoryId).toSet();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SheetHeader(
          title: _isEdit ? 'Anggaran ${widget.existing!.category.name}' : 'Anggaran baru',
          subtitle: 'Batas pengeluaran per bulan. Berlaku setiap bulan.',
          onDelete: _isEdit ? _delete : null,
        ),
        const SizedBox(height: 18),
        if (!_isEdit) ...[
          Text('Kategori pengeluaran', style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          categories.when(
            loading: () => const SkeletonBox(height: 90),
            error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(categoriesProvider)),
            data: (all) {
              final list = all.where((c) => c.type == TxType.expense && !usedIds.contains(c.id)).toList();
              if (list.isEmpty) {
                return Text(
                  'Semua kategori pengeluaran sudah punya anggaran.',
                  style: context.text.bodyMedium?.copyWith(color: context.colors.onSurfaceVariant),
                );
              }
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final c in list)
                    ChoiceChip(
                      avatar: Icon(iconFor(c.icon), size: 18, color: c.color),
                      label: Text(c.name),
                      selected: _categoryId == c.id,
                      onSelected: (_) => setState(() => _categoryId = c.id),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 18),
        ],
        Text('Batas per bulan', style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        AmountField(controller: _amount, color: context.colors.primary, autofocus: _isEdit),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          children: [
            for (final v in const [500000, 1000000, 1500000, 2000000, 3000000])
              ActionChip(label: Text(rupiahCompact(v)), onPressed: () => _amount.text = formatThousands(v)),
          ],
        ),
        const SizedBox(height: 20),
        SaveButton(label: _isEdit ? 'Simpan perubahan' : 'Buat anggaran', saving: _saving, onPressed: _save),
      ],
    );
  }
}
