import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../widgets/common.dart';
import 'wishlist_detail_screen.dart';
import 'wishlist_sheets.dart';
import '../../widgets/stagger.dart';

class WishlistScreen extends ConsumerStatefulWidget {
  const WishlistScreen({super.key});

  @override
  ConsumerState<WishlistScreen> createState() => _WishlistScreenState();
}

class _WishlistScreenState extends ConsumerState<WishlistScreen> {
  int _tab = 0; // 0 aktif, 1 tercapai

  @override
  Widget build(BuildContext context) {
    final wishlists = ref.watch(wishlistsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Wishlist')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab-wish',
        onPressed: () => showWishlistForm(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Impian baru'),
      ),
      body: RefreshIndicator(
        onRefresh: () => refreshProviders(ref, [wishlistsProvider]),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 100),
          children: [
            AsyncView(
              value: wishlists,
              onRetry: () => ref.invalidate(wishlistsProvider),
              loading: const Column(
                children: [
                  SkeletonBox(height: 130, radius: 24),
                  SizedBox(height: 16),
                  SkeletonList(count: 3),
                ],
              ),
              builder: (all) {
                final active = all.where((w) => w.status == WishlistStatus.active).toList();
                final achieved = all.where((w) => w.status == WishlistStatus.achieved).toList();
                final shown = _tab == 0 ? active : achieved;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _SummaryCard(active: active, achievedCount: achieved.length),
                    const SizedBox(height: 16),
                    PillTabs(
                      labels: ['Aktif (${active.length})', 'Tercapai (${achieved.length})'],
                      index: _tab,
                      colors: const [AppColors.emeraldDeep, AppColors.gold],
                      onChanged: (i) => setState(() => _tab = i),
                    ),
                    const SizedBox(height: 16),
                    if (shown.isEmpty)
                      EmptyState(
                        icon: _tab == 0 ? Icons.auto_awesome_rounded : Icons.emoji_events_rounded,
                        title: _tab == 0 ? 'Belum ada impian' : 'Belum ada yang tercapai',
                        subtitle: _tab == 0
                            ? 'Tambahkan barang yang ingin kamu beli, Savely bantu hitung berapa yang perlu ditabung.'
                            : 'Terus menabung, impianmu pasti tercapai!',
                      )
                    else
                      KeyedSubtree(
                        key: ValueKey(_tab),
                        child: Column(
                          children:
                              [
                                    for (final w in shown)
                                      Padding(
                                        padding: const EdgeInsets.only(bottom: 14),
                                        child: WishlistCard(wishlist: w),
                                      ),
                                  ]
                                  .staggered(interval: 70.ms)
                                  .fadeIn(duration: 350.ms)
                                  .moveY(begin: 20, end: 0, curve: Curves.easeOutCubic),
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

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.active, required this.achievedCount});

  final List<Wishlist> active;
  final int achievedCount;

  @override
  Widget build(BuildContext context) {
    final saved = active.fold<int>(0, (s, w) => s + w.savedAmount);
    final target = active.fold<int>(0, (s, w) => s + w.targetAmount);
    final progress = target == 0 ? 0.0 : saved / target;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: AppColors.goldGradient,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColors.gold.withValues(alpha: 0.35),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Total tabungan impian',
                  style: context.text.bodyMedium?.copyWith(color: Colors.white.withValues(alpha: 0.9)),
                ),
              ),
              const Icon(Icons.emoji_events_rounded, color: Colors.white, size: 18),
              const SizedBox(width: 4),
              Text(
                '$achievedCount tercapai',
                style: context.text.labelMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 6),
          AnimatedRupiah(
            saved,
            style: context.text.headlineSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
          ),
          Text(
            'dari ${rupiah(target)}',
            style: context.text.bodySmall?.copyWith(color: Colors.white.withValues(alpha: 0.85)),
          ),
          const SizedBox(height: 14),
          AnimatedProgressBar(
            value: progress,
            color: Colors.white,
            background: Colors.white.withValues(alpha: 0.25),
          ),
        ],
      ),
    );
  }
}

class WishlistCard extends StatelessWidget {
  const WishlistCard({super.key, required this.wishlist});

  final Wishlist wishlist;

  @override
  Widget build(BuildContext context) {
    final w = wishlist;
    final barColor = w.isAchieved ? AppColors.gold : context.colors.primary;

    return Pressable(
      onTap: () => openWishlistDetail(context, w),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Hero(
                    tag: 'wish-icon-${w.id}',
                    child: WishIcon(achieved: w.isAchieved),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          w.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        Text(
                          'Target ${shortDate(w.targetDate)}',
                          style: context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  DaysBadge(wishlist: w),
                ],
              ),
              const SizedBox(height: 16),
              AnimatedProgressBar(value: w.progress, color: barColor),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: rupiah(w.savedAmount),
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          TextSpan(
                            text: ' / ${rupiah(w.targetAmount)}',
                            style: TextStyle(color: context.colors.onSurfaceVariant),
                          ),
                        ],
                      ),
                      style: context.text.bodyMedium,
                    ),
                  ),
                  Text(
                    '${w.progressPercent.toStringAsFixed(0)}%',
                    style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800, color: barColor),
                  ),
                ],
              ),
              if (!w.isAchieved && w.remainingAmount > 0) ...[
                const SizedBox(height: 12),
                _PlanHint(wishlist: w),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PlanHint extends StatelessWidget {
  const _PlanHint({required this.wishlist});

  final Wishlist wishlist;

  @override
  Widget build(BuildContext context) {
    final p = wishlist.plan;
    final overdue = p.isOverdue;
    final color = overdue ? AppColors.expense : context.colors.primary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Icon(
            overdue ? Icons.warning_amber_rounded : Icons.tips_and_updates_rounded,
            size: 18,
            color: color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              overdue
                  ? 'Target sudah lewat, kurang ${rupiah(wishlist.remainingAmount)}'
                  : 'Nabung ${rupiah(p.perDay)}/hari biar tepat waktu',
              style: context.text.labelMedium?.copyWith(color: color, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class DaysBadge extends StatelessWidget {
  const DaysBadge({super.key, required this.wishlist});

  final Wishlist wishlist;

  @override
  Widget build(BuildContext context) {
    final w = wishlist;
    final (label, color) = w.isAchieved
        ? ('Tercapai 🎉', AppColors.gold)
        : w.plan.isOverdue
        ? ('Lewat', AppColors.expense)
        : w.plan.daysLeft == 0
        ? ('Hari ini', AppColors.gold)
        : ('${w.plan.daysLeft} hari', context.colors.primary);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: context.text.labelSmall?.copyWith(color: color, fontWeight: FontWeight.w800),
      ),
    );
  }
}
