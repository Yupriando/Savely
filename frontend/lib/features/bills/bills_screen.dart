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
import '../../widgets/stagger.dart';

void openBills(BuildContext context) {
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const BillsScreen()));
}

/// Pemasukan yang belum diterima bukan tunggakan, jadi tidak merah.
Color billStatusColor(BuildContext context, Bill b) => switch (b.status) {
  BillStatus.overdue => b.type.isIncome ? AppColors.gold : AppColors.expense,
  BillStatus.dueSoon => AppColors.gold,
  BillStatus.upcoming => context.colors.primary,
  BillStatus.paid => AppColors.income,
  BillStatus.inactive => context.colors.onSurfaceVariant,
};

/// "Jatuh tempo 3 hari lagi", "Hari ini", "Lewat 2 hari", "Dibayar 5 Okt".
String billDueLabel(Bill b) {
  final income = b.type.isIncome;
  if (b.isPaid) {
    return '${income ? 'Diterima' : 'Dibayar'} ${b.paidDate != null ? shortDate(b.paidDate!) : ''}'.trim();
  }
  if (!b.isActive) return 'Nonaktif';
  final verb = income ? 'Biasanya diterima' : 'Jatuh tempo';
  if (b.daysUntilDue == 0) return '$verb hari ini';
  if (b.daysUntilDue == 1) return '$verb besok';
  if (b.daysUntilDue < 0) return income ? 'Belum diterima' : 'Lewat ${-b.daysUntilDue} hari';
  return '$verb ${b.daysUntilDue} hari lagi';
}

class BillsScreen extends ConsumerStatefulWidget {
  const BillsScreen({super.key});

  @override
  ConsumerState<BillsScreen> createState() => _BillsScreenState();
}

class _BillsScreenState extends ConsumerState<BillsScreen> {
  DateTime _month = monthOnly(DateTime.now());

  @override
  Widget build(BuildContext context) {
    final report = ref.watch(billsProvider(_month));

    return Scaffold(
      appBar: AppBar(title: const Text('Tagihan rutin')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab-bill',
        onPressed: () => showBillForm(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Tagihan baru'),
      ),
      body: RefreshIndicator(
        onRefresh: () => refreshProviders(ref, [billsProvider]),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 100),
          children: [
            MonthSwitcher(month: _month, onChanged: (m) => setState(() => _month = m)),
            const SizedBox(height: 16),
            AsyncView(
              value: report,
              onRetry: () => ref.invalidate(billsProvider),
              builder: (r) {
                if (r.items.isEmpty) {
                  return const EmptyState(
                    icon: Icons.event_repeat_rounded,
                    title: 'Belum ada tagihan rutin',
                    subtitle:
                        'Tambahkan IPL, listrik & air, internet, atau kiriman orang tua. Savely mengingatkan sebelum jatuh tempo dan mencatatnya sekali ketuk.',
                  );
                }
                final unpaid = r.items.where((b) => b.type == TxType.expense && b.needsAttention).length;
                return Column(
                  key: ValueKey(_month),
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Row(
                          children: [
                            Container(
                              width: 46,
                              height: 46,
                              decoration: BoxDecoration(
                                color: AppColors.gold.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: const Icon(Icons.receipt_long_rounded, color: AppColors.gold),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Belum dibayar bulan ini',
                                    style: context.text.bodySmall?.copyWith(
                                      color: context.colors.onSurfaceVariant,
                                    ),
                                  ),
                                  AnimatedRupiah(
                                    r.totalDue,
                                    style: context.text.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                                  ),
                                ],
                              ),
                            ),
                            if (unpaid > 0)
                              Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: AppColors.expense.withValues(alpha: 0.14),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      '$unpaid perlu dibayar',
                                      style: context.text.labelSmall?.copyWith(
                                        color: AppColors.expense,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  )
                                  .animate(onPlay: (c) => c.repeat(reverse: true))
                                  .scaleXY(end: 1.06, duration: 800.ms),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    for (final b in r.items)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: BillCard(bill: b, month: _month),
                      ),
                  ].staggered(interval: 60.ms).fadeIn(duration: 350.ms).moveY(begin: 14, end: 0),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Kartu tagihan dengan status & tombol Bayar.
class BillCard extends ConsumerWidget {
  const BillCard({super.key, required this.bill, required this.month, this.compact = false});

  final Bill bill;
  final DateTime month;
  final bool compact;

  Future<void> _undo(BuildContext context, WidgetRef ref) async {
    final ok = await confirmDialog(
      context,
      title: 'Batalkan pembayaran?',
      message: 'Transaksi pembayaran "${bill.name}" bulan ini akan dihapus.',
      confirmLabel: 'Batalkan',
    );
    if (!ok) return;
    try {
      await ref.read(apiProvider).unpayBill(bill.id, month);
      refreshFinance(ref);
      if (context.mounted) showSnack(context, 'Pembayaran dibatalkan');
    } catch (e) {
      if (context.mounted) showSnack(context, e.toString(), error: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final b = bill;
    final statusColor = billStatusColor(context, b);
    final amountColor = b.type.isIncome ? AppColors.income : null;

    return Pressable(
      onTap: () => showBillForm(context, existing: b),
      child: Card(
        child: Padding(
          padding: EdgeInsets.all(compact ? 12 : 16),
          child: Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  CategoryIcon(icon: b.category.icon, color: b.category.color, size: compact ? 40 : 46),
                  if (b.isPaid)
                    Positioned(
                      right: -4,
                      bottom: -4,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: context.colors.surfaceContainerLow,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.check_circle_rounded, color: AppColors.income, size: 18),
                      ).animate().scale(curve: Curves.elasticOut, duration: 600.ms),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      b.name,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${b.type.isIncome ? '+' : ''}${rupiah(b.isPaid ? (b.paidAmount ?? b.amount) : b.amount)}',
                      style: context.text.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: amountColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(Icons.circle, size: 8, color: statusColor),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            billDueLabel(b),
                            overflow: TextOverflow.ellipsis,
                            style: context.text.labelSmall?.copyWith(
                              color: statusColor,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (b.isPaid)
                TextButton(onPressed: () => _undo(context, ref), child: const Text('Batal'))
              else if (b.isActive)
                FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 40),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    backgroundColor: b.type.isIncome
                        ? AppColors.income
                        : (b.status == BillStatus.overdue ? AppColors.expense : null),
                  ),
                  onPressed: () => showPayBillSheet(context, b, month),
                  child: Text(b.type.isIncome ? 'Terima' : 'Bayar'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================
// Bayar tagihan
// =============================================================

Future<void> showPayBillSheet(BuildContext context, Bill bill, DateTime month) =>
    showFormSheet<void>(context, _PaySheet(bill: bill, month: month));

class _PaySheet extends ConsumerStatefulWidget {
  const _PaySheet({required this.bill, required this.month});

  final Bill bill;
  final DateTime month;

  @override
  ConsumerState<_PaySheet> createState() => _PaySheetState();
}

class _PaySheetState extends ConsumerState<_PaySheet> {
  late final _amount = TextEditingController(text: formatThousands(widget.bill.amount));
  late String? _walletId = widget.bill.walletId;
  DateTime _date = dateOnly(DateTime.now());
  bool _saving = false;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _pay() async {
    final amount = parseAmount(_amount.text);
    if (amount <= 0) return showSnack(context, 'Masukkan nominal dulu', error: true);
    setState(() => _saving = true);
    try {
      await ref
          .read(apiProvider)
          .payBill(widget.bill.id, month: widget.month, amount: amount, walletId: _walletId, date: _date);
      refreshFinance(ref);
      if (!mounted) return;
      Navigator.pop(context);
      showSuccess(context, '${widget.bill.name}\n${widget.bill.type.isIncome ? 'diterima' : 'lunas'} ✔');
    } catch (e) {
      if (mounted) showSnack(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.bill;
    final color = b.type.isIncome ? AppColors.income : AppColors.expense;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SheetHeader(
          title: b.type.isIncome ? 'Terima ${b.name}' : 'Bayar ${b.name}',
          subtitle:
              'Untuk ${monthLabel(widget.month)} · otomatis dicatat sebagai ${b.type.label.toLowerCase()} ${b.category.name}',
        ),
        const SizedBox(height: 18),
        AmountField(controller: _amount, color: color),
        const SizedBox(height: 18),
        WalletPicker(
          label: b.type.isIncome ? 'Masuk ke dompet' : 'Bayar dari dompet',
          selectedId: _walletId,
          onChanged: (id) => setState(() => _walletId = id),
        ),
        const SizedBox(height: 18),
        DateChips(date: _date, onChanged: (d) => setState(() => _date = d)),
        const SizedBox(height: 20),
        SaveButton(
          label: b.type.isIncome ? 'Tandai diterima' : 'Tandai lunas',
          saving: _saving,
          onPressed: _pay,
          color: color,
        ),
      ],
    );
  }
}

// =============================================================
// Form tagihan
// =============================================================

Future<void> showBillForm(BuildContext context, {Bill? existing}) =>
    showFormSheet<void>(context, _BillForm(existing: existing));

class _BillForm extends ConsumerStatefulWidget {
  const _BillForm({this.existing});

  final Bill? existing;

  @override
  ConsumerState<_BillForm> createState() => _BillFormState();
}

class _BillFormState extends ConsumerState<_BillForm> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _amount = TextEditingController(
    text: widget.existing != null ? formatThousands(widget.existing!.amount) : '',
  );
  late TxType _type = widget.existing?.type ?? TxType.expense;
  late String? _categoryId = widget.existing?.categoryId;
  late String? _walletId = widget.existing?.walletId;
  late int _dueDay = widget.existing?.dueDay ?? 10;
  late int _remindDays = widget.existing?.remindDays ?? 3;
  late bool _active = widget.existing?.isActive ?? true;
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final amount = parseAmount(_amount.text);
    if (name.isEmpty) return showSnack(context, 'Nama tagihan wajib diisi', error: true);
    if (amount <= 0) return showSnack(context, 'Masukkan nominal', error: true);
    if (_categoryId == null) return showSnack(context, 'Pilih kategori', error: true);

    final body = {
      'name': name,
      'type': _type.name,
      'category_id': _categoryId,
      'wallet_id': _walletId,
      'amount': amount,
      'due_day': _dueDay,
      'remind_days': _remindDays,
      'is_active': _active,
    };

    setState(() => _saving = true);
    try {
      final api = ref.read(apiProvider);
      _isEdit ? await api.updateBill(widget.existing!.id, body) : await api.createBill(body);
      refreshFinance(ref);
      if (!mounted) return;
      Navigator.pop(context);
      showSuccess(context, _isEdit ? 'Tagihan diperbarui' : 'Tagihan "$name" ditambahkan');
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
      title: 'Hapus tagihan rutin?',
      message: '"${b.name}" tidak akan diingatkan lagi. Transaksi pembayaran lama tetap tersimpan.',
    );
    if (!ok || !mounted) return;
    try {
      await ref.read(apiProvider).deleteBill(b.id);
      refreshFinance(ref);
      if (!mounted) return;
      Navigator.pop(context);
      showSnack(context, 'Tagihan dihapus');
    } catch (e) {
      if (mounted) showSnack(context, e.toString(), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(categoriesProvider);
    final color = _type.isIncome ? AppColors.income : AppColors.expense;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SheetHeader(
          title: _isEdit ? 'Ubah tagihan rutin' : 'Tagihan rutin baru',
          subtitle: 'Berulang setiap bulan di tanggal yang sama.',
          onDelete: _isEdit ? _delete : null,
        ),
        const SizedBox(height: 16),
        PillTabs(
          labels: const ['Tagihan', 'Pemasukan rutin'],
          index: _type.isIncome ? 1 : 0,
          colors: const [AppColors.expense, AppColors.income],
          onChanged: (i) => setState(() {
            final t = i == 1 ? TxType.income : TxType.expense;
            if (t != _type) _categoryId = null;
            _type = t;
          }),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _name,
          autofocus: !_isEdit,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            hintText: _type.isIncome ? 'Nama, misal: Kiriman orang tua' : 'Nama, misal: IPL Apartemen',
            prefixIcon: const Icon(Icons.label_rounded),
          ),
        ),
        const SizedBox(height: 14),
        AmountField(controller: _amount, color: color),
        const SizedBox(height: 18),
        Text('Kategori', style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        categories.when(
          loading: () => const SkeletonBox(height: 90),
          error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(categoriesProvider)),
          data: (all) => Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in all.where((c) => c.type == _type))
                ChoiceChip(
                  avatar: Icon(iconFor(c.icon), size: 18, color: c.color),
                  label: Text(c.name),
                  selected: _categoryId == c.id,
                  onSelected: (_) => setState(() => _categoryId = c.id),
                ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Text(
          _type.isIncome ? 'Biasanya diterima tanggal' : 'Jatuh tempo setiap tanggal',
          style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: Slider(
                value: _dueDay.toDouble(),
                min: 1,
                max: 31,
                divisions: 30,
                label: '$_dueDay',
                onChanged: (v) => setState(() => _dueDay = v.round()),
              ),
            ),
            Container(
              width: 52,
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: context.colors.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: Text('$_dueDay', style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            ),
          ],
        ),
        if (_dueDay > 28)
          Text(
            'Di bulan yang lebih pendek, jatuh tempo di hari terakhir bulan itu.',
            style: context.text.labelSmall?.copyWith(color: context.colors.onSurfaceVariant),
          ),
        const SizedBox(height: 12),
        Text('Ingatkan', style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            for (final d in const [0, 1, 3, 5, 7])
              ChoiceChip(
                label: Text(d == 0 ? 'Di hari H' : '$d hari sebelum'),
                selected: _remindDays == d,
                onSelected: (_) => setState(() => _remindDays = d),
              ),
          ],
        ),
        const SizedBox(height: 18),
        WalletPicker(
          label: _type.isIncome ? 'Biasanya masuk ke' : 'Biasanya dibayar dari',
          selectedId: _walletId,
          onChanged: (id) => setState(() => _walletId = id),
        ),
        if (_isEdit)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Aktif'),
            subtitle: const Text('Matikan kalau sementara tidak perlu diingatkan'),
            value: _active,
            onChanged: (v) => setState(() => _active = v),
          ),
        const SizedBox(height: 20),
        SaveButton(label: _isEdit ? 'Simpan perubahan' : 'Tambah', saving: _saving, onPressed: _save),
      ],
    );
  }
}
