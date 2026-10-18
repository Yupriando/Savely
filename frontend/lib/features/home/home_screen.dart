import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../widgets/common.dart';
import '../../widgets/transaction_tile.dart';
import '../../widgets/user_avatar.dart';
import '../settings/settings_screen.dart';
import '../transactions/transaction_form_sheet.dart';
import '../wishlist/wishlist_detail_screen.dart';

final _hideBalanceProvider = StateProvider<bool>((_) => false);

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = ref.watch(todayProvider);
    final month = monthOnly(today);

    final report = ref.watch(monthlyReportProvider(month));
    final todayReport = ref.watch(dailyReportProvider(today));
    final recent = ref.watch(transactionsProvider((month: month, type: null)));
    final wishlists = ref.watch(wishlistsProvider);

    void goToTab(int i) => ref.read(shellTabProvider.notifier).state = i;

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab-home',
        onPressed: () => showTransactionForm(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Catat'),
      ).animate().scale(delay: 500.ms, duration: 400.ms, curve: Curves.easeOutBack),
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () => refreshProviders(ref, [
            monthlyReportProvider,
            dailyReportProvider,
            transactionsProvider,
            wishlistsProvider,
          ]),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
            children: [
              const _Header(),
              const SizedBox(height: 20),
              report.when(
                skipLoadingOnRefresh: true,
                // Kilau melintas tiap ~5 detik
                data: (r) => _BalanceCard(month: month, summary: r.summary)
                    .animate(onPlay: (c) => c.repeat())
                    .shimmer(delay: 3500.ms, duration: 1500.ms, color: Colors.white.withValues(alpha: 0.18)),
                loading: () => const SkeletonBox(height: 200, radius: 28),
                error: (e, _) => ErrorView(
                  error: e,
                  onRetry: () => ref.invalidate(monthlyReportProvider),
                ),
              ),
              const SizedBox(height: 14),
              _TodayRow(summary: todayReport.valueOrNull?.summary),
              const SizedBox(height: 24),
              const SectionTitle('Arus kas bulan ini'),
              const SizedBox(height: 10),
              _CashflowCard(daily: report.valueOrNull?.dailyTotals),
              ...wishlists.maybeWhen(
                data: (list) {
                  final active = list.where((w) => w.status == WishlistStatus.active).toList();
                  if (active.isEmpty) return const <Widget>[];
                  return [
                    const SizedBox(height: 20),
                    SectionTitle('Impianmu', action: 'Lihat semua', onAction: () => goToTab(2)),
                    const SizedBox(height: 4),
                    _WishlistStrip(items: active),
                  ];
                },
                orElse: () => const <Widget>[],
              ),
              const SizedBox(height: 20),
              SectionTitle('Transaksi terakhir', action: 'Lihat semua', onAction: () => goToTab(1)),
              const SizedBox(height: 4),
              AsyncView(
                value: recent,
                onRetry: () => ref.invalidate(transactionsProvider),
                loading: const SkeletonList(count: 4),
                builder: (list) {
                  if (list.isEmpty) {
                    return const EmptyState(
                      icon: Icons.receipt_long_rounded,
                      title: 'Belum ada transaksi bulan ini',
                      subtitle: 'Tekan tombol "Catat" untuk mencatat pemasukan atau pengeluaran pertamamu.',
                    );
                  }
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Column(
                        children: [
                          for (final t in list.take(5))
                            TransactionTile(
                              transaction: t,
                              showDate: true,
                              onTap: () => showTransactionForm(context, existing: t),
                            ),
                        ]
                            .animate(interval: 60.ms)
                            .fadeIn(duration: 300.ms)
                            .moveX(begin: 16, end: 0, curve: Curves.easeOutCubic),
                      ),
                    ),
                  );
                },
              ),
            ]
                .animate(interval: 70.ms)
                .fadeIn(duration: 450.ms)
                .moveY(begin: 18, end: 0, curve: Curves.easeOutCubic),
          ),
        ),
      ),
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).valueOrNull;
    final now = ref.watch(clockProvider).valueOrNull ?? DateTime.now();
    final greet = greetingFor(now);

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Sapaan berganti otomatis mengikuti jam sistem
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 500),
                transitionBuilder: (child, anim) => FadeTransition(
                  opacity: anim,
                  child: SlideTransition(
                    position: Tween(begin: const Offset(0, 0.5), end: Offset.zero).animate(anim),
                    child: child,
                  ),
                ),
                child: Row(
                  key: ValueKey(greet.text),
                  children: [
                    Text(
                      greet.text,
                      style: context.text.bodyMedium?.copyWith(color: context.colors.onSurfaceVariant),
                    ),
                    const SizedBox(width: 6),
                    Text(greet.emoji, style: const TextStyle(fontSize: 16))
                        .animate(onPlay: (c) => c.repeat(reverse: true))
                        .moveY(begin: -1.5, end: 1.5, duration: 1200.ms, curve: Curves.easeInOut)
                        .rotate(begin: -0.04, end: 0.04, duration: 1200.ms),
                  ],
                ),
              ),
              const SizedBox(height: 2),
              Text(
                user?.displayName ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.text.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ),
        Pressable(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
          ),
          child: Hero(tag: 'avatar', child: UserAvatar(user: user, size: 48)),
        ),
      ],
    );
  }
}

/// Gradien yang bergeser pelan bolak-balik, bikin kartu terasa "hidup".
class _LivingGradient extends StatefulWidget {
  const _LivingGradient({required this.child, required this.borderRadius, this.boxShadow});

  final Widget child;
  final BorderRadius borderRadius;
  final List<BoxShadow>? boxShadow;

  @override
  State<_LivingGradient> createState() => _LivingGradientState();
}

class _LivingGradientState extends State<_LivingGradient> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(seconds: 7))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) {
        final t = Curves.easeInOut.transform(_c.value);
        return Container(
          decoration: BoxDecoration(
            borderRadius: widget.borderRadius,
            boxShadow: widget.boxShadow,
            gradient: LinearGradient(
              begin: Alignment.lerp(Alignment.topLeft, Alignment.topRight, t)!,
              end: Alignment.lerp(Alignment.bottomRight, Alignment.bottomLeft, t)!,
              colors: AppColors.heroGradient.colors,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: child,
        );
      },
    );
  }
}

class _BalanceCard extends ConsumerWidget {
  const _BalanceCard({required this.month, required this.summary});

  final DateTime month;
  final ReportSummary summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hidden = ref.watch(_hideBalanceProvider);
    const white = Colors.white;

    return _LivingGradient(
      borderRadius: BorderRadius.circular(28),
      boxShadow: [
        BoxShadow(
          color: AppColors.emeraldDeep.withValues(alpha: 0.35),
          blurRadius: 24,
          offset: const Offset(0, 12),
        ),
      ],
      child: Stack(
        children: [
          Positioned(
            right: -40,
            top: -50,
            child: _Bubble(size: 180),
          ),
          Positioned(
            right: 60,
            bottom: -70,
            child: _Bubble(size: 140),
          ),
          Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Saldo ${monthLabel(month)}',
                      style: context.text.bodyMedium?.copyWith(color: white.withValues(alpha: 0.85)),
                    ),
                    const Spacer(),
                    InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () => ref.read(_hideBalanceProvider.notifier).state = !hidden,
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          hidden ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                          color: white.withValues(alpha: 0.85),
                          size: 20,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: hidden
                      ? Text(
                          'Rp • • • • • •',
                          key: const ValueKey('hidden'),
                          style: context.text.headlineMedium?.copyWith(
                            color: white,
                            fontWeight: FontWeight.w800,
                          ),
                        )
                      : AnimatedRupiah(
                          summary.balance,
                          key: const ValueKey('shown'),
                          style: context.text.headlineMedium?.copyWith(
                            color: white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: _FlowPill(
                        label: 'Pemasukan',
                        amount: summary.income,
                        icon: Icons.south_west_rounded,
                        hidden: hidden,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _FlowPill(
                        label: 'Pengeluaran',
                        amount: summary.expense,
                        icon: Icons.north_east_rounded,
                        hidden: hidden,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: 0.08),
      ),
    )
        .animate(onPlay: (c) => c.repeat(reverse: true))
        .scaleXY(begin: 0.9, end: 1.08, duration: 3.seconds, curve: Curves.easeInOut);
  }
}

class _FlowPill extends StatelessWidget {
  const _FlowPill({
    required this.label,
    required this.amount,
    required this.icon,
    required this.hidden,
  });

  final String label;
  final int amount;
  final IconData icon;
  final bool hidden;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: context.text.labelSmall?.copyWith(color: Colors.white.withValues(alpha: 0.85)),
                ),
                hidden
                    ? Text('• • • •', style: context.text.titleSmall?.copyWith(color: Colors.white))
                    : AnimatedRupiah(
                        amount,
                        compact: amount >= 10000000,
                        style: context.text.titleSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TodayRow extends StatelessWidget {
  const _TodayRow({required this.summary});

  final ReportSummary? summary;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _MiniStat(
            label: 'Keluar hari ini',
            value: summary?.expense,
            color: AppColors.expense,
            icon: Icons.shopping_cart_rounded,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _MiniStat(
            label: 'Masuk hari ini',
            value: summary?.income,
            color: AppColors.income,
            icon: Icons.account_balance_wallet_rounded,
          ),
        ),
      ],
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value, required this.color, required this.icon});

  final String label;
  final int? value;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: context.text.labelSmall?.copyWith(color: context.colors.onSurfaceVariant),
                  ),
                  const SizedBox(height: 2),
                  value == null
                      ? const SkeletonBox(height: 14, width: 70)
                      : AnimatedRupiah(
                          value!,
                          compact: value! >= 10000000,
                          style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                        ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Grafik garis pemasukan vs pengeluaran per hari, sampai hari ini.
class _CashflowCard extends StatelessWidget {
  const _CashflowCard({required this.daily});

  final List<DailyTotal>? daily;

  @override
  Widget build(BuildContext context) {
    if (daily == null) return const SkeletonBox(height: 220, radius: 20);

    final today = dateOnly(DateTime.now());
    final days = daily!.where((d) => !d.day.isAfter(today)).toList();
    final hasData = days.any((d) => d.income > 0 || d.expense > 0);

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 18, 18, 10),
        child: Column(
          children: [
            Row(
              children: const [
                SizedBox(width: 8),
                _Legend(color: AppColors.income, label: 'Pemasukan'),
                SizedBox(width: 16),
                _Legend(color: AppColors.expense, label: 'Pengeluaran'),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 170,
              child: !hasData
                  ? Center(
                      child: Text(
                        'Grafik muncul setelah ada transaksi',
                        style: context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant),
                      ),
                    )
                  : TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: 1),
                      duration: const Duration(milliseconds: 1000),
                      curve: Curves.easeOutCubic,
                      builder: (context, t, _) => LineChart(_chartData(context, days, t)),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  LineChartData _chartData(BuildContext context, List<DailyTotal> days, double t) {
    LineChartBarData line(Color color, double Function(DailyTotal) pick) => LineChartBarData(
          spots: [
            for (var i = 0; i < days.length; i++) FlSpot(i.toDouble(), pick(days[i]) * t),
          ],
          isCurved: true,
          preventCurveOverShooting: true,
          color: color,
          barWidth: 3,
          isStrokeCapRound: true,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(
            show: true,
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [color.withValues(alpha: 0.3), color.withValues(alpha: 0)],
            ),
          ),
        );

    return LineChartData(
      minY: 0,
      gridData: FlGridData(
        drawVerticalLine: false,
        getDrawingHorizontalLine: (_) => FlLine(color: context.colors.outlineVariant, strokeWidth: 1),
      ),
      borderData: FlBorderData(show: false),
      titlesData: FlTitlesData(
        topTitles: const AxisTitles(),
        rightTitles: const AxisTitles(),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 44,
            getTitlesWidget: (v, meta) => v == meta.max
                ? const SizedBox.shrink()
                : Text(rupiahCompact(v).replaceFirst('Rp', ''),
                    style: context.text.labelSmall?.copyWith(color: context.colors.onSurfaceVariant)),
          ),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            interval: 5,
            getTitlesWidget: (v, _) {
              final i = v.toInt();
              if (i < 0 || i >= days.length) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('${days[i].day.day}',
                    style: context.text.labelSmall?.copyWith(color: context.colors.onSurfaceVariant)),
              );
            },
          ),
        ),
      ),
      lineTouchData: LineTouchData(
        touchTooltipData: LineTouchTooltipData(
          getTooltipColor: (_) => context.colors.inverseSurface,
          getTooltipItems: (spots) => [
            for (final s in spots)
              LineTooltipItem(
                rupiah(s.y.round()),
                TextStyle(color: s.bar.color, fontWeight: FontWeight.w700),
              ),
          ],
        ),
      ),
      lineBarsData: [
        line(AppColors.income, (d) => d.income.toDouble()),
        line(AppColors.expense, (d) => d.expense.toDouble()),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label, style: context.text.labelMedium),
      ],
    );
  }
}

class _WishlistStrip extends StatelessWidget {
  const _WishlistStrip({required this.items});

  final List<Wishlist> items;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 132,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          final w = items[i];
          return Pressable(
            onTap: () => openWishlistDetail(context, w),
            child: Container(
              width: 220,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: context.colors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: context.colors.outlineVariant),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const WishIcon(size: 32),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          w.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Text(
                    '${rupiah(w.savedAmount)} / ${rupiahCompact(w.targetAmount)}',
                    style: context.text.labelMedium?.copyWith(color: context.colors.onSurfaceVariant),
                  ),
                  const SizedBox(height: 8),
                  AnimatedProgressBar(value: w.progress, color: AppColors.gold, height: 8),
                ],
              ),
            ),
          ).animate(delay: (i * 80).ms).fadeIn().moveX(begin: 30, end: 0, curve: Curves.easeOutCubic);
        },
      ),
    );
  }
}
