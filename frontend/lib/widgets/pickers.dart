import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../data/providers.dart';
import 'category_icon.dart';
import 'common.dart';

/// Ikon yang bisa dipilih untuk kategori.
const categoryIconChoices = [
  'restaurant', 'local_cafe', 'local_grocery_store', 'shopping_bag', 'checkroom', //
  'bolt', 'water_drop', 'apartment', 'home', 'wifi', 'phone_android', 'subscriptions',
  'directions_car', 'local_gas_station', 'local_parking', 'flight',
  'local_hospital', 'spa', 'fitness_center', 'school', 'child_care', 'pets',
  'movie', 'sports_esports', 'sports_soccer', 'celebration', 'card_giftcard',
  'volunteer_activism', 'build', 'local_laundry_service', 'receipt_long',
  'payments', 'work', 'storefront', 'redeem', 'family_restroom', 'trending_up',
  'attach_money', 'savings', 'more_horiz',
];

/// Ikon yang bisa dipilih untuk dompet.
const walletIconChoices = [
  'payments',
  'account_balance',
  'account_balance_wallet',
  'phone_iphone',
  'credit_card',
  'savings',
];

/// Palet warna yang enak dilihat di mode terang & gelap.
const colorChoices = [
  '#10B981',
  '#059669',
  '#0EA5E9',
  '#2563EB',
  '#5C6BC0',
  '#7E57C2',
  '#AB47BC',
  '#EC407A',
  '#F06292',
  '#EF5350',
  '#FF7043',
  '#FFA726',
  '#FFCA28',
  '#8D6E63',
  '#78909C',
  '#9E9E9E',
];

Color hexColor(String hex) => Color(int.parse(hex.substring(1), radix: 16) | 0xFF000000);

String colorHex(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

class IconPickerGrid extends StatelessWidget {
  const IconPickerGrid({
    super.key,
    required this.icons,
    required this.selected,
    required this.color,
    required this.onChanged,
  });

  final List<String> icons;
  final String selected;
  final Color color;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final name in icons)
          Pressable(
            onTap: () => onChanged(name),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: name == selected ? color.withValues(alpha: 0.18) : context.colors.surfaceContainer,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: name == selected ? color : Colors.transparent, width: 1.8),
              ),
              child: Icon(
                iconFor(name),
                size: 22,
                color: name == selected ? color : context.colors.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}

class ColorPickerRow extends StatelessWidget {
  const ColorPickerRow({super.key, required this.selected, required this.onChanged});

  final String selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final hex in colorChoices)
          Pressable(
            onTap: () => onChanged(hex),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: hexColor(hex),
                shape: BoxShape.circle,
                border: Border.all(
                  color: hex.toUpperCase() == selected.toUpperCase()
                      ? context.colors.onSurface
                      : Colors.transparent,
                  width: 3,
                ),
              ),
              child: hex.toUpperCase() == selected.toUpperCase()
                  ? const Icon(Icons.check_rounded, color: Colors.white, size: 18)
                  : null,
            ),
          ),
      ],
    );
  }
}

/// Pilih dompet (chip horizontal + saldo). [selectedId] null = pakai dompet utama.
class WalletPicker extends ConsumerWidget {
  const WalletPicker({
    super.key,
    required this.selectedId,
    required this.onChanged,
    this.excludeId,
    this.label = 'Dompet',
  });

  final String? selectedId;
  final ValueChanged<String> onChanged;
  final String? excludeId;
  final String label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wallets = ref.watch(walletsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        wallets.when(
          loading: () => const SkeletonBox(height: 56),
          error: (e, _) => Text(e.toString(), style: const TextStyle(color: AppColors.expense)),
          data: (data) {
            final list = data.active.where((w) => w.id != excludeId).toList();
            final effective = selectedId ?? data.defaultWallet?.id;
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              child: Row(
                children: [
                  for (final w in list)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _WalletChip(
                        wallet: w,
                        selected: w.id == effective,
                        onTap: () => onChanged(w.id),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

class _WalletChip extends StatelessWidget {
  const _WalletChip({required this.wallet, required this.selected, required this.onTap});

  final Wallet wallet;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = wallet.color;
    return Pressable(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.fromLTRB(8, 8, 14, 8),
        decoration: BoxDecoration(
          color: selected ? c.withValues(alpha: 0.16) : context.colors.surfaceContainer,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: selected ? c : Colors.transparent, width: 1.6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CategoryIcon(icon: wallet.icon, color: c, size: 30),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  wallet.name,
                  style: context.text.labelLarge?.copyWith(
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
                Text(
                  rupiah(wallet.balance),
                  style: context.text.labelSmall?.copyWith(color: context.colors.onSurfaceVariant),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Pilihan tanggal cepat: Hari ini / Kemarin / pilih sendiri.
class DateChips extends StatelessWidget {
  const DateChips({super.key, required this.date, required this.onChanged, this.allowFuture = false});

  final DateTime date;
  final ValueChanged<DateTime> onChanged;
  final bool allowFuture;

  @override
  Widget build(BuildContext context) {
    final today = dateOnly(DateTime.now());
    final yesterday = today.subtract(const Duration(days: 1));
    final d = dateOnly(date);
    final isCustom = d != today && d != yesterday;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        ChoiceChip(label: const Text('Hari ini'), selected: d == today, onSelected: (_) => onChanged(today)),
        ChoiceChip(
          label: const Text('Kemarin'),
          selected: d == yesterday,
          onSelected: (_) => onChanged(yesterday),
        ),
        ChoiceChip(
          avatar: const Icon(Icons.calendar_month_rounded, size: 18),
          label: Text(isCustom ? shortDate(d) : 'Pilih tanggal'),
          selected: isCustom,
          onSelected: (_) async {
            final picked = await showDatePicker(
              context: context,
              initialDate: d,
              firstDate: DateTime(2020),
              lastDate: allowFuture ? DateTime(today.year + 2) : DateTime.now(),
            );
            if (picked != null) onChanged(picked);
          },
        ),
      ],
    );
  }
}

/// Input nominal besar: "Rp 25.000" dengan warna sesuai jenis.
class AmountField extends StatelessWidget {
  const AmountField({super.key, required this.controller, required this.color, this.autofocus = false});

  final TextEditingController controller;
  final Color color;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
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
              controller: controller,
              autofocus: autofocus,
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
    );
  }
}

/// Header sheet: judul + tombol hapus opsional.
class SheetHeader extends StatelessWidget {
  const SheetHeader({super.key, required this.title, this.subtitle, this.onDelete});

  final String title;
  final String? subtitle;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(title, style: context.text.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            ),
            if (onDelete != null)
              IconButton(
                tooltip: 'Hapus',
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline_rounded, color: AppColors.expense),
              ),
          ],
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(subtitle!, style: context.text.bodyMedium?.copyWith(color: context.colors.onSurfaceVariant)),
        ],
      ],
    );
  }
}

/// Tombol simpan dengan spinner.
class SaveButton extends StatelessWidget {
  const SaveButton({
    super.key,
    required this.label,
    required this.saving,
    required this.onPressed,
    this.color,
  });

  final String label;
  final bool saving;
  final VoidCallback onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      style: color == null ? null : FilledButton.styleFrom(backgroundColor: color),
      onPressed: saving ? null : onPressed,
      child: saving
          ? const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
            )
          : Text(label),
    );
  }
}

/// Buka bottom sheet yang bisa di-scroll & naik saat keyboard muncul.
Future<T?> showFormSheet<T>(BuildContext context, Widget child) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
      child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(20, 0, 20, 24), child: child),
    ),
  );
}
