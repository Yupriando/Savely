import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../widgets/celebration.dart';
import '../../widgets/common.dart';
import 'wishlist_sheets.dart';
import '../../widgets/stagger.dart';

void openWishlistDetail(BuildContext context, Wishlist wishlist) {
  Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => WishlistDetailScreen(initial: wishlist)));
}

/// Ikon hadiah dengan latar emas.
class WishIcon extends StatelessWidget {
  const WishIcon({super.key, this.size = 44, this.achieved = false});

  final double size;
  final bool achieved;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: AppColors.goldGradient,
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      child: Icon(
        achieved ? Icons.emoji_events_rounded : Icons.card_giftcard_rounded,
        color: Colors.white,
        size: size * 0.52,
      ),
    );
  }
}

class WishlistDetailScreen extends ConsumerWidget {
  const WishlistDetailScreen({super.key, required this.initial});

  /// Data dari daftar, ditampilkan langsung sambil menunggu detail lengkap.
  final Wishlist initial;

  Future<void> _delete(BuildContext context, WidgetRef ref, Wishlist w) async {
    final ok = await confirmDialog(
      context,
      title: 'Hapus impian?',
      message: '"${w.name}" beserta riwayat tabungannya akan dihapus.',
    );
    if (!ok || !context.mounted) return;
    try {
      await ref.read(apiProvider).deleteWishlist(w.id);
      refreshWishlists(ref);
      if (!context.mounted) return;
      Navigator.pop(context);
      showSnack(context, 'Impian dihapus');
    } catch (e) {
      if (context.mounted) showSnack(context, e.toString(), error: true);
    }
  }

  Future<bool> _deleteSaving(BuildContext context, WidgetRef ref, Wishlist w, WishlistSaving s) async {
    final ok = await confirmDialog(
      context,
      title: 'Hapus catatan tabungan?',
      message: '${s.isDeposit ? 'Setoran' : 'Penarikan'} ${rupiah(s.amount.abs())} akan dihapus.',
    );
    if (!ok) return false;
    try {
      await ref.read(apiProvider).deleteSaving(w.id, s.id);
      refreshWishlists(ref);
      return true;
    } catch (e) {
      if (context.mounted) showSnack(context, e.toString(), error: true);
      return false;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(wishlistDetailProvider(initial.id));
    final w = detail.valueOrNull ?? initial;
    final loadingSavings = detail.isLoading && !detail.hasValue;

    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            tooltip: 'Ubah',
            onPressed: () => showWishlistForm(context, existing: w),
            icon: const Icon(Icons.edit_rounded),
          ),
          IconButton(
            tooltip: 'Hapus',
            onPressed: () => _delete(context, ref, w),
            icon: const Icon(Icons.delete_outline_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
        children:
            [
                  Center(
                    child: Stack(
                      clipBehavior: Clip.none,
                      alignment: Alignment.center,
                      children: [
                        _ProgressRing(wishlist: w),
                        // Target tercapai -> confetti meledak saat halaman dibuka
                        if (w.isAchieved)
                          const Positioned(
                            left: -120,
                            right: -120,
                            top: -40,
                            bottom: -260,
                            child: ConfettiOnce(delay: Duration(milliseconds: 400)),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Hero(
                        tag: 'wish-icon-${w.id}',
                        child: WishIcon(size: 32, achieved: w.isAchieved),
                      ),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          w.name,
                          textAlign: TextAlign.center,
                          style: context.text.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Center(
                    child: Text(
                      'Target ${fullDate(w.targetDate)}',
                      style: context.text.bodyMedium?.copyWith(color: context.colors.onSurfaceVariant),
                    ),
                  ),
                  if (w.note != null && w.note!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Center(
                      child: Text(
                        '"${w.note}"',
                        textAlign: TextAlign.center,
                        style: context.text.bodyMedium?.copyWith(fontStyle: FontStyle.italic),
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: _Stat(label: 'Terkumpul', value: rupiah(w.savedAmount)),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _Stat(label: 'Kurang', value: rupiah(w.remainingAmount)),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _Stat(
                          label: 'Sisa waktu',
                          value: w.plan.daysLeft < 0 ? 'Lewat' : '${w.plan.daysLeft} hari',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (w.isAchieved)
                    const _AchievedBanner()
                  else if (w.remainingAmount > 0)
                    _PlanCard(wishlist: w),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () => showSavingSheet(context, w, deposit: true),
                          icon: const Icon(Icons.add_rounded),
                          label: const Text('Setor'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: w.savedAmount > 0
                              ? () => showSavingSheet(context, w, deposit: false)
                              : null,
                          icon: const Icon(Icons.remove_rounded),
                          label: const Text('Tarik'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 28),
                  const SectionTitle('Riwayat tabungan'),
                  if (w.savings.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Icon(Icons.touch_app_rounded, size: 14, color: context.colors.onSurfaceVariant),
                          const SizedBox(width: 4),
                          Text(
                            'Ketuk untuk ubah, geser ke kiri untuk hapus',
                            style: context.text.labelSmall?.copyWith(color: context.colors.onSurfaceVariant),
                          ),
                        ],
                      ),
                    )
                  else
                    const SizedBox(height: 8),
                  if (loadingSavings)
                    const SkeletonList(count: 3)
                  else if (w.savings.isEmpty)
                    const EmptyState(
                      icon: Icons.savings_rounded,
                      title: 'Belum ada tabungan',
                      subtitle: 'Tekan "Setor" untuk mulai menabung.',
                    )
                  else
                    _SavingsList(
                      savings: w.savings,
                      confirmDelete: (saving) => _deleteSaving(context, ref, w, saving),
                      onTap: (saving) => showSavingSheet(context, w, existing: saving),
                    ),
                ]
                .staggered(interval: 50.ms)
                .fadeIn(duration: 400.ms)
                .moveY(begin: 14, end: 0, curve: Curves.easeOutCubic),
      ),
    );
  }
}

class _ProgressRing extends StatelessWidget {
  const _ProgressRing({required this.wishlist});

  final Wishlist wishlist;

  @override
  Widget build(BuildContext context) {
    final w = wishlist;
    final color = w.isAchieved ? AppColors.gold : context.colors.primary;

    return SizedBox(
      width: 210,
      height: 210,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (w.isAchieved)
            // Bintang berkelip mengelilingi cincin
            for (var i = 0; i < 8; i++)
              Transform.translate(
                offset: Offset(98 * math.cos(i * math.pi / 4), 98 * math.sin(i * math.pi / 4)),
                child: const Icon(Icons.star_rounded, color: AppColors.gold, size: 18)
                    .animate(delay: (i * 120).ms, onPlay: (c) => c.repeat(reverse: true))
                    .scaleXY(begin: 0.4, end: 1.2, duration: 700.ms)
                    .fade(begin: 0.3, end: 1),
              ),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: w.progress),
            duration: const Duration(milliseconds: 1400),
            curve: Curves.easeOutCubic,
            builder: (context, v, _) => Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 170,
                  height: 170,
                  child: CircularProgressIndicator(
                    value: v,
                    strokeWidth: 14,
                    strokeCap: StrokeCap.round,
                    color: color,
                    backgroundColor: color.withValues(alpha: 0.14),
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${(v * 100).toStringAsFixed(0)}%',
                      style: context.text.displaySmall?.copyWith(fontWeight: FontWeight.w800, color: color),
                    ),
                    Text(
                      w.isAchieved ? 'tercapai!' : 'terkumpul',
                      style: context.text.bodyMedium?.copyWith(color: context.colors.onSurfaceVariant),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    ).animate().scaleXY(begin: 0.8, duration: 600.ms, curve: Curves.easeOutBack);
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.colors.outlineVariant),
      ),
      child: Column(
        children: [
          Text(label, style: context.text.labelSmall?.copyWith(color: context.colors.onSurfaceVariant)),
          const SizedBox(height: 4),
          FittedBox(
            child: Text(value, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.wishlist});

  final Wishlist wishlist;

  @override
  Widget build(BuildContext context) {
    final p = wishlist.plan;

    if (p.isOverdue) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.expense.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: AppColors.expense),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Target tanggal sudah lewat. Ubah tanggal target supaya rencana tabungan dihitung ulang.',
                style: context.text.bodyMedium?.copyWith(color: AppColors.expense),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(gradient: AppColors.heroGradient, borderRadius: BorderRadius.circular(22)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_graph_rounded, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Text(
                'Rencana menabung',
                style: context.text.titleSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Supaya tercapai tepat waktu, sisihkan:',
            style: context.text.bodySmall?.copyWith(color: Colors.white.withValues(alpha: 0.85)),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _PlanItem(label: 'per hari', value: p.perDay),
              _PlanItem(label: 'per minggu', value: p.perWeek),
              _PlanItem(label: 'per bulan', value: p.perMonth),
            ],
          ),
        ],
      ),
    );
  }
}

class _PlanItem extends StatelessWidget {
  const _PlanItem({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FittedBox(
            child: AnimatedRupiah(
              value,
              style: context.text.titleMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
            ),
          ),
          Text(label, style: context.text.labelSmall?.copyWith(color: Colors.white.withValues(alpha: 0.8))),
        ],
      ),
    );
  }
}

class _AchievedBanner extends StatelessWidget {
  const _AchievedBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(gradient: AppColors.goldGradient, borderRadius: BorderRadius.circular(22)),
      child: Row(
        children: [
          const Text('🎉', style: TextStyle(fontSize: 32))
              .animate(onPlay: (c) => c.repeat(reverse: true))
              .rotate(begin: -0.06, end: 0.06, duration: 500.ms)
              .scaleXY(begin: 0.95, end: 1.1, duration: 500.ms),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              'Selamat! Target ini sudah tercapai. Saatnya beli barang impianmu!',
              style: context.text.bodyMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    ).animate().shimmer(delay: 400.ms, duration: 1500.ms, color: Colors.white.withValues(alpha: 0.5));
  }
}

class _SavingsList extends StatefulWidget {
  const _SavingsList({required this.savings, required this.confirmDelete, required this.onTap});

  final List<WishlistSaving> savings;
  final Future<bool> Function(WishlistSaving) confirmDelete;
  final void Function(WishlistSaving) onTap;

  @override
  State<_SavingsList> createState() => _SavingsListState();
}

class _SavingsListState extends State<_SavingsList> {
  /// Id yang sudah di-swipe hapus, disembunyikan sampai data baru datang.
  final _removed = <String>{};

  @override
  Widget build(BuildContext context) {
    final items = widget.savings.where((s) => !_removed.contains(s.id)).toList();
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (final s in items)
            Dismissible(
              key: ValueKey(s.id),
              direction: DismissDirection.endToStart,
              confirmDismiss: (_) => widget.confirmDelete(s),
              onDismissed: (_) => setState(() => _removed.add(s.id)),
              background: Container(
                color: AppColors.expense,
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 24),
                child: const Icon(Icons.delete_rounded, color: Colors.white),
              ),
              child: _SavingTile(saving: s, onTap: () => widget.onTap(s)),
            ),
        ].staggered(interval: 50.ms).fadeIn(duration: 300.ms).moveX(begin: 16, end: 0),
      ),
    );
  }
}

class _SavingTile extends StatelessWidget {
  const _SavingTile({required this.saving, required this.onTap});

  final WishlistSaving saving;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = saving;
    final color = s.isDeposit ? AppColors.income : AppColors.expense;
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(color: color.withValues(alpha: 0.14), shape: BoxShape.circle),
        child: Icon(s.isDeposit ? Icons.south_rounded : Icons.north_rounded, color: color, size: 20),
      ),
      title: Text(
        s.isDeposit ? 'Setor' : 'Tarik',
        style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        [
          relativeDay(s.date),
          if (s.wallet != null) s.wallet!.name,
          if (s.note != null && s.note!.isNotEmpty) s.note!,
        ].join(' • '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Text(
        signedRupiah(s.amount, isIncome: s.isDeposit),
        style: context.text.titleSmall?.copyWith(color: color, fontWeight: FontWeight.w800),
      ),
    );
  }
}
