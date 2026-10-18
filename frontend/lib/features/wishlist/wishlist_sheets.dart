import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../widgets/celebration.dart';
import '../../widgets/common.dart';

// =============================================================
// Form tambah / ubah wishlist
// =============================================================

Future<void> showWishlistForm(BuildContext context, {Wishlist? existing}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _WishlistForm(existing: existing),
  );
}

class _WishlistForm extends ConsumerStatefulWidget {
  const _WishlistForm({this.existing});

  final Wishlist? existing;

  @override
  ConsumerState<_WishlistForm> createState() => _WishlistFormState();
}

class _WishlistFormState extends ConsumerState<_WishlistForm> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _amount = TextEditingController(
    text: widget.existing != null ? formatThousands(widget.existing!.targetAmount) : '',
  );
  late final _note = TextEditingController(text: widget.existing?.note ?? '');
  late DateTime _targetDate =
      widget.existing?.targetDate ?? dateOnly(DateTime.now()).add(const Duration(days: 90));
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    // Update preview rencana tabungan saat nominal diketik
    _amount.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final today = dateOnly(DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: _targetDate.isBefore(today) ? today : _targetDate,
      firstDate: today,
      lastDate: DateTime(today.year + 20),
      helpText: 'Kapan target tercapai?',
    );
    if (picked != null) setState(() => _targetDate = picked);
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final amount = parseAmount(_amount.text);
    if (name.isEmpty) return showSnack(context, 'Nama barang wajib diisi', error: true);
    if (amount <= 0) return showSnack(context, 'Masukkan harga target', error: true);

    setState(() => _saving = true);
    final api = ref.read(apiProvider);
    try {
      if (_isEdit) {
        await api.updateWishlist(
          widget.existing!.id,
          name: name,
          targetAmount: amount,
          targetDate: _targetDate,
          note: _note.text,
        );
      } else {
        await api.createWishlist(name: name, targetAmount: amount, targetDate: _targetDate, note: _note.text);
      }
      refreshWishlists(ref);
      if (!mounted) return;
      Navigator.pop(context);
      showSuccess(context, _isEdit ? 'Wishlist diperbarui' : 'Impian "$name"\nditambahkan ✨');
    } catch (e) {
      if (mounted) showSnack(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final amount = parseAmount(_amount.text);
    final saved = widget.existing?.savedAmount ?? 0;
    final remaining = (amount - saved).clamp(0, amount);
    final days = _targetDate.difference(dateOnly(DateTime.now())).inDays;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _isEdit ? 'Ubah impian' : 'Impian baru',
              style: context.text.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              'Tentukan barang yang ingin kamu beli dan kapan targetnya.',
              style: context.text.bodyMedium?.copyWith(color: context.colors.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _name,
              autofocus: !_isEdit,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'Nama barang, misal: HP baru',
                prefixIcon: Icon(Icons.card_giftcard_rounded),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _amount,
              keyboardType: TextInputType.number,
              inputFormatters: [ThousandsInputFormatter()],
              decoration: const InputDecoration(
                hintText: 'Harga target',
                prefixIcon: Padding(
                  padding: EdgeInsets.only(left: 16, right: 8),
                  child: Text('Rp', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                ),
                prefixIconConstraints: BoxConstraints(minWidth: 0, minHeight: 0),
              ),
            ),
            const SizedBox(height: 12),
            Pressable(
              onTap: _pickDate,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: context.colors.surfaceContainer,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    Icon(Icons.event_rounded, color: context.colors.onSurfaceVariant),
                    const SizedBox(width: 12),
                    Expanded(child: Text('Target: ${shortDate(_targetDate)}')),
                    Text(
                      days <= 0 ? 'hari ini' : '$days hari lagi',
                      style: context.text.labelMedium?.copyWith(color: context.colors.primary),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'Catatan (opsional)',
                prefixIcon: Icon(Icons.edit_note_rounded),
              ),
            ),
            const SizedBox(height: 16),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: remaining > 0
                  ? _PlanPreview(
                      key: const ValueKey('plan'),
                      perDay: (remaining / (days <= 0 ? 1 : days)).ceil(),
                      perMonth: (remaining / ((days <= 0 ? 1 : days) / 30).ceil()).ceil(),
                    )
                  : const SizedBox.shrink(key: ValueKey('none')),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                    )
                  : Text(_isEdit ? 'Simpan perubahan' : 'Tambah impian'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlanPreview extends StatelessWidget {
  const _PlanPreview({super.key, required this.perDay, required this.perMonth});

  final int perDay;
  final int perMonth;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.gold.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.lightbulb_rounded,
            color: AppColors.gold,
          ).animate(onPlay: (c) => c.repeat(reverse: true)).scaleXY(begin: 0.9, end: 1.1, duration: 900.ms),
          const SizedBox(width: 12),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  const TextSpan(text: 'Kamu perlu nabung sekitar '),
                  TextSpan(
                    text: '${rupiah(perDay)}/hari',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const TextSpan(text: ' atau '),
                  TextSpan(
                    text: '${rupiah(perMonth)}/bulan',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
              style: context.text.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================
// Setor / tarik tabungan
// =============================================================

/// Tambah setoran/penarikan, atau ubah/hapus catatan lama kalau [existing] diisi.
Future<void> showSavingSheet(
  BuildContext context,
  Wishlist wishlist, {
  bool deposit = true,
  WishlistSaving? existing,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) =>
        _SavingSheet(wishlist: wishlist, deposit: existing?.isDeposit ?? deposit, existing: existing),
  );
}

class _SavingSheet extends ConsumerStatefulWidget {
  const _SavingSheet({required this.wishlist, required this.deposit, this.existing});

  final Wishlist wishlist;
  final bool deposit;
  final WishlistSaving? existing;

  @override
  ConsumerState<_SavingSheet> createState() => _SavingSheetState();
}

class _SavingSheetState extends ConsumerState<_SavingSheet> {
  late bool _deposit = widget.deposit;
  late DateTime _date = widget.existing?.date ?? dateOnly(DateTime.now());
  late final _amount = TextEditingController(
    text: widget.existing != null ? formatThousands(widget.existing!.amount.abs()) : '',
  );
  late final _note = TextEditingController(text: widget.existing?.note ?? '');
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  /// Saldo tabungan tanpa catatan yang sedang diubah (batas maksimal tarik).
  int get _available => widget.wishlist.savedAmount - (widget.existing?.amount ?? 0);

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save() async {
    final w = widget.wishlist;
    final amount = parseAmount(_amount.text);
    if (amount <= 0) return showSnack(context, 'Masukkan nominal dulu', error: true);
    if (!_deposit && amount > _available) {
      return showSnack(context, 'Maksimal tarik ${rupiah(_available)}', error: true);
    }

    final signed = _deposit ? amount : -amount;
    setState(() => _saving = true);
    try {
      final api = ref.read(apiProvider);
      if (_isEdit) {
        await api.updateSaving(w.id, widget.existing!.id, amount: signed, date: _date, note: _note.text);
      } else {
        await api.addSaving(w.id, amount: signed, date: _date, note: _note.text);
      }
      refreshWishlists(ref);
      if (!mounted) return;
      Navigator.pop(context);

      final reached = w.savedAmount < w.targetAmount && _available + signed >= w.targetAmount;
      showSuccess(
        context,
        reached
            ? 'Selamat! Target "${w.name}" tercapai 🎉'
            : _isEdit
            ? 'Catatan tabungan diperbarui'
            : _deposit
            ? 'Berhasil menabung ${rupiah(amount)}'
            : 'Berhasil menarik ${rupiah(amount)}',
        confetti: reached,
      );
    } catch (e) {
      if (mounted) showSnack(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final s = widget.existing!;
    final ok = await confirmDialog(
      context,
      title: 'Hapus catatan tabungan?',
      message: '${s.isDeposit ? 'Setoran' : 'Penarikan'} ${rupiah(s.amount.abs())} akan dihapus.',
    );
    if (!ok || !mounted) return;
    try {
      await ref.read(apiProvider).deleteSaving(widget.wishlist.id, s.id);
      refreshWishlists(ref);
      if (!mounted) return;
      Navigator.pop(context);
      showSnack(context, 'Catatan tabungan dihapus');
    } catch (e) {
      if (mounted) showSnack(context, e.toString(), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.wishlist;
    final color = _deposit ? AppColors.income : AppColors.expense;
    final today = dateOnly(DateTime.now());
    final yesterday = today.subtract(const Duration(days: 1));
    final isCustomDate = _date != today && _date != yesterday;

    // Saran nominal: sesuai rencana tabungan, atau sisa kekurangan / semua saldo
    final suggestions = _isEdit
        ? const <String, int>{}
        : _deposit
        ? <String, int>{
            if (w.plan.perDay > 0) 'Per hari': w.plan.perDay,
            if (w.plan.perWeek > 0) 'Per minggu': w.plan.perWeek,
            if (w.plan.perMonth > 0) 'Per bulan': w.plan.perMonth,
            if (w.remainingAmount > 0) 'Lunasi': w.remainingAmount,
          }
        : <String, int>{if (_available > 0) 'Semua': _available};

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
                    _isEdit ? 'Ubah catatan tabungan' : (_deposit ? 'Setor tabungan' : 'Tarik tabungan'),
                    style: context.text.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                if (_isEdit)
                  IconButton(
                    tooltip: 'Hapus',
                    onPressed: _delete,
                    icon: const Icon(Icons.delete_outline_rounded, color: AppColors.expense),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              _deposit
                  ? 'Untuk "${w.name}" · kurang ${rupiah(w.remainingAmount)}'
                  : 'Dari "${w.name}" · bisa ditarik ${rupiah(_available)}',
              style: context.text.bodyMedium?.copyWith(color: context.colors.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            PillTabs(
              labels: const ['Setor', 'Tarik'],
              index: _deposit ? 0 : 1,
              colors: const [AppColors.income, AppColors.expense],
              onChanged: (i) => setState(() => _deposit = i == 0),
            ),
            const SizedBox(height: 16),
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: color.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Text(
                    'Rp',
                    style: context.text.headlineSmall?.copyWith(color: color, fontWeight: FontWeight.w800),
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
            if (suggestions.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final e in suggestions.entries)
                    ActionChip(
                      label: Text('${e.key} · ${rupiahCompact(e.value)}'),
                      onPressed: () => _amount.text = formatThousands(e.value),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 16),
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
            const SizedBox(height: 16),
            TextField(
              controller: _note,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'Catatan (opsional)',
                prefixIcon: Icon(Icons.edit_note_rounded),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: color),
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                    )
                  : Text(_isEdit ? 'Simpan perubahan' : (_deposit ? 'Setor' : 'Tarik')),
            ),
          ],
        ),
      ),
    );
  }
}
