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

void openWallets(BuildContext context) {
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const WalletsScreen()));
}

class WalletsScreen extends ConsumerStatefulWidget {
  const WalletsScreen({super.key});

  @override
  ConsumerState<WalletsScreen> createState() => _WalletsScreenState();
}

class _WalletsScreenState extends ConsumerState<WalletsScreen> {
  bool _showArchived = false;

  @override
  Widget build(BuildContext context) {
    final wallets = ref.watch(allWalletsProvider);
    final month = monthOnly(DateTime.now());
    final transfers = ref.watch(transfersProvider(month));

    return Scaffold(
      appBar: AppBar(title: const Text('Dompet')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab-wallet',
        onPressed: () => showWalletForm(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Dompet baru'),
      ),
      body: RefreshIndicator(
        onRefresh: () => refreshProviders(ref, [allWalletsProvider, walletsProvider, transfersProvider]),
        child: AsyncView(
          value: wallets,
          onRetry: () => ref.invalidate(allWalletsProvider),
          builder: (data) {
            final active = data.active;
            final archived = data.wallets.where((w) => w.archived).toList();
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 100),
              children: [
                _TotalCard(total: data.totalBalance, count: active.length),
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  onPressed: active.length < 2 ? null : () => showTransferForm(context),
                  icon: const Icon(Icons.swap_horiz_rounded),
                  label: Text(
                    active.length < 2 ? 'Transfer (butuh minimal 2 dompet)' : 'Transfer antar dompet',
                  ),
                ),
                const SizedBox(height: 20),
                for (final w in active)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _WalletCard(
                      wallet: w,
                      onTap: () => showWalletForm(context, existing: w),
                    ),
                  ),
                if (archived.isNotEmpty) ...[
                  TextButton.icon(
                    onPressed: () => setState(() => _showArchived = !_showArchived),
                    icon: Icon(_showArchived ? Icons.expand_less_rounded : Icons.expand_more_rounded),
                    label: Text('Diarsipkan (${archived.length})'),
                  ),
                  if (_showArchived)
                    for (final w in archived)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Opacity(
                          opacity: 0.6,
                          child: _WalletCard(
                            wallet: w,
                            onTap: () => showWalletForm(context, existing: w),
                          ),
                        ),
                      ),
                ],
                const SizedBox(height: 16),
                SectionTitle('Transfer ${monthLabel(month)}'),
                const SizedBox(height: 8),
                transfers.when(
                  loading: () => const SkeletonList(count: 2),
                  error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(transfersProvider)),
                  data: (list) => list.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                            'Belum ada transfer bulan ini. Contoh: tarik tunai dari ATM, top up e-wallet.',
                            style: context.text.bodyMedium?.copyWith(color: context.colors.onSurfaceVariant),
                          ),
                        )
                      : Card(
                          clipBehavior: Clip.antiAlias,
                          child: Column(children: [for (final t in list) _TransferTile(transfer: t)]),
                        ),
                ),
              ].staggered(interval: 50.ms).fadeIn(duration: 350.ms).moveY(begin: 14, end: 0),
            );
          },
        ),
      ),
    );
  }
}

class _TotalCard extends StatelessWidget {
  const _TotalCard({required this.total, required this.count});

  final int total;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: AppColors.heroGradient,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColors.emeraldDeep.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Total saldo $count dompet',
            style: context.text.bodyMedium?.copyWith(color: Colors.white.withValues(alpha: 0.85)),
          ),
          const SizedBox(height: 6),
          AnimatedRupiah(
            total,
            style: context.text.headlineMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _WalletCard extends StatelessWidget {
  const _WalletCard({required this.wallet, required this.onTap});

  final Wallet wallet;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final w = wallet;
    return Pressable(
      onTap: onTap,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CategoryIcon(icon: w.icon, color: w.color, size: 48),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            w.name,
                            overflow: TextOverflow.ellipsis,
                            style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                        if (w.isDefault) ...[
                          const SizedBox(width: 8),
                          _Badge(label: 'Utama', color: context.colors.primary),
                        ],
                        if (w.archived) ...[
                          const SizedBox(width: 8),
                          _Badge(label: 'Arsip', color: context.colors.onSurfaceVariant),
                        ],
                      ],
                    ),
                    Text(
                      w.type.label,
                      style: context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              AnimatedRupiah(
                w.balance,
                style: context.text.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: w.balance < 0 ? AppColors.expense : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(8)),
      child: Text(
        label,
        style: context.text.labelSmall?.copyWith(color: color, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _TransferTile extends ConsumerWidget {
  const _TransferTile({required this.transfer});

  final Transfer transfer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = transfer;
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(color: context.colors.primaryContainer, shape: BoxShape.circle),
        child: Icon(Icons.swap_horiz_rounded, color: context.colors.primary),
      ),
      title: Text('${t.from.name} → ${t.to.name}', style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text([relativeDay(t.date), if (t.note != null && t.note!.isNotEmpty) t.note!].join(' • ')),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(rupiah(t.amount), style: const TextStyle(fontWeight: FontWeight.w800)),
          IconButton(
            tooltip: 'Hapus transfer',
            icon: const Icon(Icons.delete_outline_rounded, size: 20),
            onPressed: () async {
              final ok = await confirmDialog(
                context,
                title: 'Hapus transfer?',
                message: '${rupiah(t.amount)} dari ${t.from.name} ke ${t.to.name} akan dibatalkan.',
              );
              if (!ok) return;
              try {
                await ref.read(apiProvider).deleteTransfer(t.id);
                refreshFinance(ref);
                if (context.mounted) showSnack(context, 'Transfer dihapus');
              } catch (e) {
                if (context.mounted) showSnack(context, e.toString(), error: true);
              }
            },
          ),
        ],
      ),
    );
  }
}

// =============================================================
// Form dompet
// =============================================================

Future<void> showWalletForm(BuildContext context, {Wallet? existing}) =>
    showFormSheet<void>(context, _WalletForm(existing: existing));

class _WalletForm extends ConsumerStatefulWidget {
  const _WalletForm({this.existing});

  final Wallet? existing;

  @override
  ConsumerState<_WalletForm> createState() => _WalletFormState();
}

class _WalletFormState extends ConsumerState<_WalletForm> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _initial = TextEditingController(
    text: widget.existing != null && widget.existing!.initialBalance != 0
        ? formatThousands(widget.existing!.initialBalance)
        : '',
  );
  late WalletType _type = widget.existing?.type ?? WalletType.bank;
  late String _icon = widget.existing?.icon ?? WalletType.bank.defaultIcon;
  late String _color = widget.existing != null ? colorHex(widget.existing!.color) : '#2563EB';
  late bool _isDefault = widget.existing?.isDefault ?? false;
  late bool _archived = widget.existing?.archived ?? false;
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void dispose() {
    _name.dispose();
    _initial.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) return showSnack(context, 'Nama dompet wajib diisi', error: true);

    final body = {
      'name': name,
      'type': _type.name,
      'icon': _icon,
      'color': _color,
      'initial_balance': parseAmount(_initial.text),
      if (_isDefault) 'is_default': true,
      if (_isEdit && !_isDefault) 'archived': _archived,
    };

    setState(() => _saving = true);
    try {
      final api = ref.read(apiProvider);
      _isEdit ? await api.updateWallet(widget.existing!.id, body) : await api.createWallet(body);
      refreshFinance(ref);
      if (!mounted) return;
      Navigator.pop(context);
      showSuccess(context, _isEdit ? 'Dompet diperbarui' : 'Dompet "$name" dibuat');
    } catch (e) {
      if (mounted) showSnack(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final w = widget.existing!;
    final ok = await confirmDialog(
      context,
      title: 'Hapus dompet?',
      message:
          'Dompet yang sudah punya transaksi tidak bisa dihapus. Arsipkan saja supaya riwayatnya tetap ada.',
    );
    if (!ok || !mounted) return;
    try {
      await ref.read(apiProvider).deleteWallet(w.id);
      refreshFinance(ref);
      if (!mounted) return;
      Navigator.pop(context);
      showSnack(context, 'Dompet dihapus');
    } catch (e) {
      if (mounted) showSnack(context, e.toString(), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = hexColor(_color);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SheetHeader(
          title: _isEdit ? 'Ubah dompet' : 'Dompet baru',
          subtitle: 'Contoh: BCA, GoPay, Tunai, Tabungan.',
          onDelete: _isEdit && !widget.existing!.isDefault ? _delete : null,
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: CategoryIcon(key: ValueKey('$_icon$_color'), icon: _icon, color: color, size: 52),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _name,
                autofocus: !_isEdit,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(hintText: 'Nama dompet'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          children: [
            for (final t in WalletType.values)
              ChoiceChip(
                label: Text(t.label),
                selected: _type == t,
                onSelected: (_) => setState(() {
                  // Ikon ikut berubah kalau user belum memilih ikon sendiri
                  if (_icon == _type.defaultIcon) _icon = t.defaultIcon;
                  _type = t;
                }),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Text('Saldo awal', style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(
          'Isi dengan saldo saat ini sebelum mulai dicatat di Savely.',
          style: context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        AmountField(controller: _initial, color: color),
        const SizedBox(height: 16),
        Text('Ikon', style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        IconPickerGrid(
          icons: walletIconChoices,
          selected: _icon,
          color: color,
          onChanged: (v) => setState(() => _icon = v),
        ),
        const SizedBox(height: 16),
        Text('Warna', style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        ColorPickerRow(selected: _color, onChanged: (v) => setState(() => _color = v)),
        const SizedBox(height: 12),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Jadikan dompet utama'),
          subtitle: const Text('Dipakai otomatis saat mencatat transaksi'),
          value: _isDefault,
          onChanged: widget.existing?.isDefault == true ? null : (v) => setState(() => _isDefault = v),
        ),
        if (_isEdit && !_isDefault)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Arsipkan'),
            subtitle: const Text('Disembunyikan dari pilihan, riwayat tetap tersimpan'),
            value: _archived,
            onChanged: (v) => setState(() => _archived = v),
          ),
        const SizedBox(height: 16),
        SaveButton(label: _isEdit ? 'Simpan perubahan' : 'Buat dompet', saving: _saving, onPressed: _save),
      ],
    );
  }
}

// =============================================================
// Form transfer
// =============================================================

Future<void> showTransferForm(BuildContext context) => showFormSheet<void>(context, const _TransferForm());

class _TransferForm extends ConsumerStatefulWidget {
  const _TransferForm();

  @override
  ConsumerState<_TransferForm> createState() => _TransferFormState();
}

class _TransferFormState extends ConsumerState<_TransferForm> {
  final _amount = TextEditingController();
  final _note = TextEditingController();
  String? _from;
  String? _to;
  DateTime _date = dateOnly(DateTime.now());
  bool _saving = false;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final data = ref.read(walletsProvider).valueOrNull;
    final from = _from ?? data?.defaultWallet?.id;
    final amount = parseAmount(_amount.text);
    if (from == null || _to == null) return showSnack(context, 'Pilih dompet asal dan tujuan', error: true);
    if (from == _to) return showSnack(context, 'Dompet asal dan tujuan harus berbeda', error: true);
    if (amount <= 0) return showSnack(context, 'Masukkan nominal dulu', error: true);

    setState(() => _saving = true);
    try {
      await ref
          .read(apiProvider)
          .createTransfer(
            fromWalletId: from,
            toWalletId: _to!,
            amount: amount,
            date: _date,
            note: _note.text,
          );
      refreshFinance(ref);
      if (!mounted) return;
      Navigator.pop(context);
      showSuccess(context, 'Transfer ${rupiah(amount)} berhasil');
    } catch (e) {
      if (mounted) showSnack(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final defaultId = ref.watch(walletsProvider).valueOrNull?.defaultWallet?.id;
    final from = _from ?? defaultId;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SheetHeader(title: 'Transfer antar dompet', subtitle: 'Contoh: tarik tunai, top up e-wallet.'),
        const SizedBox(height: 18),
        AmountField(controller: _amount, color: context.colors.primary, autofocus: true),
        const SizedBox(height: 18),
        WalletPicker(label: 'Dari', selectedId: from, onChanged: (id) => setState(() => _from = id)),
        const SizedBox(height: 8),
        Center(
          child: Icon(
            Icons.arrow_downward_rounded,
            color: context.colors.primary,
          ).animate(onPlay: (c) => c.repeat(reverse: true)).moveY(begin: -3, end: 3, duration: 700.ms),
        ),
        const SizedBox(height: 8),
        WalletPicker(
          label: 'Ke',
          selectedId: _to ?? '',
          excludeId: from,
          onChanged: (id) => setState(() => _to = id),
        ),
        const SizedBox(height: 18),
        DateChips(date: _date, onChanged: (d) => setState(() => _date = d)),
        const SizedBox(height: 14),
        TextField(
          controller: _note,
          decoration: const InputDecoration(
            hintText: 'Catatan (opsional)',
            prefixIcon: Icon(Icons.edit_note_rounded),
          ),
        ),
        const SizedBox(height: 20),
        SaveButton(label: 'Transfer', saving: _saving, onPressed: _save),
      ],
    );
  }
}
