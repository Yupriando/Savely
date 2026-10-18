import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Ref;

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/offline_queue.dart';
import '../../data/providers.dart';
import '../../widgets/category_icon.dart';
import '../../widgets/celebration.dart';
import '../../widgets/common.dart';
import '../../widgets/pickers.dart';
import '../../core/sound.dart';

/// Buka form tambah transaksi, atau ubah kalau [existing] diisi.
Future<void> showTransactionForm(BuildContext context, {Transaction? existing}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => TransactionFormSheet(existing: existing),
  );
}

class TransactionFormSheet extends ConsumerStatefulWidget {
  const TransactionFormSheet({super.key, this.existing});

  final Transaction? existing;

  @override
  ConsumerState<TransactionFormSheet> createState() => _TransactionFormSheetState();
}

class _TransactionFormSheetState extends ConsumerState<TransactionFormSheet> {
  late TxType _type = widget.existing?.type ?? TxType.expense;
  late String? _categoryId = widget.existing?.category.id;
  late DateTime _date = widget.existing?.date ?? dateOnly(DateTime.now());
  late String? _walletId = widget.existing?.walletId;
  late final _amount = TextEditingController(
    text: widget.existing != null ? formatThousands(widget.existing!.amount) : '',
  );
  late final _note = TextEditingController(text: widget.existing?.note ?? '');

  bool _saving = false;
  bool get _isEdit => widget.existing != null;

  Color get _typeColor => _type.isIncome ? AppColors.income : AppColors.expense;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  void _addQuick(int value) {
    final next = parseAmount(_amount.text) + value;
    _amount.text = formatThousands(next);
    HapticFeedback.selectionClick();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save() async {
    final amount = parseAmount(_amount.text);
    if (amount <= 0) return showSnack(context, 'Masukkan nominal dulu', error: true);
    if (_categoryId == null) return showSnack(context, 'Pilih kategori dulu', error: true);

    // Transaksi baru & transaksi yang masih di antrean: simpan di HP dulu (langsung, tanpa
    // menunggu internet), lalu dikirim ke server di belakang layar.
    if (!_isEdit || widget.existing!.isPending) return _saveOffline(amount);

    setState(() => _saving = true);
    try {
      await ref
          .read(apiProvider)
          .updateTransaction(
            widget.existing!.id,
            type: _type,
            categoryId: _categoryId!,
            amount: amount,
            date: _date,
            note: _note.text,
            walletId: _walletId,
          );
      refreshFinance(ref);
      if (!mounted) return;
      Navigator.pop(context);
      showSuccess(context, 'Transaksi diperbarui');
    } catch (e) {
      if (mounted) showSnack(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveOffline(int amount) async {
    final category = ref.read(categoriesProvider).valueOrNull?.where((c) => c.id == _categoryId).firstOrNull;
    if (category == null) return showSnack(context, 'Kategori belum dimuat, coba lagi', error: true);

    final wallets = ref.read(walletsProvider).valueOrNull;
    final wallet = wallets?.active.where((w) => w.id == _walletId).firstOrNull ?? wallets?.defaultWallet;

    final tx = PendingTx(
      clientId: widget.existing?.pendingClientId ?? newClientId(),
      type: _type,
      amount: amount,
      date: _date,
      category: category,
      wallet: wallet == null
          ? null
          : Ref(id: wallet.id, name: wallet.name, icon: wallet.icon, color: wallet.color),
      note: _note.text.trim().isEmpty ? null : _note.text.trim(),
    );

    final sync = ref.read(syncProvider.notifier);
    if (_isEdit) {
      await sync.replace(tx);
    } else {
      await sync.add(tx);
    }
    if (!mounted) return;

    // Sheet langsung ditutup. Widget ini ikut hilang, jadi pakai navigator utama & container.
    final overlay = Navigator.of(context, rootNavigator: true).overlay!;
    final container = ProviderScope.containerOf(context);
    final label = '${_type.label} ${rupiah(amount)}';
    final isEdit = _isEdit;
    final sound = !isEdit && _type.isIncome ? Sfx.coin : null; // uang masuk -> bunyi koin
    Navigator.pop(context);

    // Coba kirim sebentar (maks 2,5 detik) supaya pesannya jujur: terkirim, atau disimpan di HP dulu.
    // Saat benar-benar offline gagalnya seketika, jadi pesan langsung muncul.
    final sending = sync.syncNow(retryFailed: true);
    await Future.any([sending, Future<void>.delayed(const Duration(milliseconds: 2500))]);
    final sent = !container.read(syncProvider).pending.any((p) => p.clientId == tx.clientId);
    showSuccessOn(
      overlay,
      isEdit
          ? 'Transaksi diperbarui'
          : sent
          ? '$label\ndicatat'
          : '$label\ndisimpan di HP, dikirim saat online',
      sound: sound,
    );
  }

  Future<void> _delete() async {
    final ok = await confirmDialog(
      context,
      title: 'Hapus transaksi?',
      message: 'Transaksi ini akan dihapus permanen.',
    );
    if (!ok || !mounted) return;
    // Belum terkirim: cukup dibuang dari antrean
    if (widget.existing!.isPending) {
      await ref.read(syncProvider.notifier).remove(widget.existing!.pendingClientId!);
      if (!mounted) return;
      Navigator.pop(context);
      showSnack(context, 'Transaksi dihapus', sound: Sfx.delete);
      return;
    }
    try {
      await ref.read(apiProvider).deleteTransaction(widget.existing!.id);
      refreshFinance(ref);
      if (!mounted) return;
      Navigator.pop(context);
      showSnack(context, 'Transaksi dihapus', sound: Sfx.delete);
    } catch (e) {
      if (mounted) showSnack(context, e.toString(), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(categoriesProvider);
    final today = dateOnly(DateTime.now());
    final yesterday = today.subtract(const Duration(days: 1));
    final isCustomDate = _date != today && _date != yesterday;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _isEdit ? 'Ubah transaksi' : 'Catat transaksi',
                    style: context.text.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                if (_isEdit)
                  IconButton(
                    onPressed: _delete,
                    icon: const Icon(Icons.delete_outline_rounded, color: AppColors.expense),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            PillTabs(
              labels: const ['Pengeluaran', 'Pemasukan'],
              index: _type.isIncome ? 1 : 0,
              colors: const [AppColors.expense, AppColors.income],
              onChanged: (i) {
                final type = i == 1 ? TxType.income : TxType.expense;
                if (type == _type) return;
                setState(() {
                  _type = type;
                  _categoryId = null;
                });
              },
            ),
            const SizedBox(height: 20),

            // Nominal
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
              decoration: BoxDecoration(
                color: _typeColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _typeColor.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Text(
                    'Rp',
                    style: context.text.headlineSmall?.copyWith(
                      color: _typeColor,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _amount,
                      autofocus: !_isEdit,
                      keyboardType: TextInputType.number,
                      inputFormatters: [ThousandsInputFormatter()],
                      style: context.text.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
                      decoration: const InputDecoration(
                        hintText: '0',
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final v in const [10000, 20000, 50000, 100000, 500000])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ActionChip(
                        label: Text('+${rupiahCompact(v).replaceFirst('Rp', '')}'),
                        onPressed: () => _addQuick(v),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Kategori
            Text('Kategori', style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            categories.when(
              loading: () => const SkeletonBox(height: 90),
              error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(categoriesProvider)),
              data: (all) {
                final list = all.where((c) => c.type == _type).toList();
                return AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: Wrap(
                    key: ValueKey(_type),
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (var i = 0; i < list.length; i++)
                        _CategoryChip(
                          category: list[i],
                          selected: list[i].id == _categoryId,
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setState(() => _categoryId = list[i].id);
                          },
                        ).animate(delay: (i * 25).ms).fadeIn(duration: 200.ms).scaleXY(begin: 0.85),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 20),

            WalletPicker(
              label: _type.isIncome ? 'Masuk ke dompet' : 'Bayar dari dompet',
              selectedId: _walletId,
              onChanged: (id) => setState(() => _walletId = id),
            ),
            const SizedBox(height: 20),

            // Tanggal
            Text('Tanggal', style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('Hari ini'),
                  selected: _date == today,
                  onSelected: (_) => setState(() => _date = today),
                ),
                ChoiceChip(
                  label: const Text('Kemarin'),
                  selected: _date == yesterday,
                  onSelected: (_) => setState(() => _date = yesterday),
                ),
                ChoiceChip(
                  avatar: const Icon(Icons.calendar_month_rounded, size: 18),
                  label: Text(isCustomDate ? shortDate(_date) : 'Pilih tanggal'),
                  selected: isCustomDate,
                  onSelected: (_) => _pickDate(),
                ),
              ],
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _note,
              maxLength: 255,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'Catatan (opsional)',
                prefixIcon: Icon(Icons.edit_note_rounded),
                counterText: '',
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: _typeColor),
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                    )
                  : Text(_isEdit ? 'Simpan perubahan' : 'Simpan ${_type.label.toLowerCase()}'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({required this.category, required this.selected, required this.onTap});

  final Category category;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = category.color;
    return Pressable(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        padding: const EdgeInsets.fromLTRB(8, 8, 14, 8),
        decoration: BoxDecoration(
          color: selected ? c.withValues(alpha: 0.18) : context.colors.surfaceContainer,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: selected ? c : Colors.transparent, width: 1.6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CategoryIcon(icon: category.icon, color: c, size: 28),
            const SizedBox(width: 8),
            Text(
              category.name,
              style: context.text.labelLarge?.copyWith(
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
