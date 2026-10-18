import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../widgets/category_icon.dart';
import '../../widgets/common.dart';
import '../../widgets/transaction_tile.dart';
import '../transactions/transaction_form_sheet.dart';
import 'report_calendar.dart';

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  int _mode = 0; // 0 bulanan, 1 harian
  DateTime _month = monthOnly(DateTime.now());
  DateTime _day = dateOnly(DateTime.now());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Laporan')),
      body: RefreshIndicator(
        onRefresh: () => refreshProviders(ref, [monthlyReportProvider, dailyReportProvider, trendProvider]),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
          children: [
            PillTabs(
              labels: const ['Bulanan', 'Harian'],
              index: _mode,
              onChanged: (i) => setState(() => _mode = i),
            ),
            const SizedBox(height: 14),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 350),
              switchInCurve: Curves.easeOutCubic,
              transitionBuilder: (child, anim) => FadeTransition(
                opacity: anim,
                child: SlideTransition(
                  position: Tween(begin: const Offset(0.04, 0), end: Offset.zero).animate(anim),
                  child: child,
                ),
              ),
              child: _mode == 0
                  ? _MonthlyView(
                      key: const ValueKey('monthly'),
                      month: _month,
                      onMonthChanged: (m) => setState(() => _month = m),
                    )
                  : _DailyView(
                      key: const ValueKey('daily'),
                      day: _day,
                      onDayChanged: (d) => setState(() => _day = dateOnly(d)),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================
// Bulanan
// =============================================================

class _MonthlyView extends ConsumerWidget {
  const _MonthlyView({super.key, required this.month, required this.onMonthChanged});

  final DateTime month;
  final ValueChanged<DateTime> onMonthChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final report = ref.watch(monthlyReportProvider(month));
    final trend = ref.watch(trendProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MonthSwitcher(month: month, onChanged: onMonthChanged),
        const SizedBox(height: 16),
        AsyncView(
          value: report,
          onRetry: () => ref.invalidate(monthlyReportProvider),
          loading: const _ReportSkeleton(),
          builder: (r) => Column(
            key: ValueKey(month),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SummaryGrid(summary: r.summary),
              const SizedBox(height: 16),
              _ChartCard(
                title: 'Arus kas harian',
                child: _DailyBarChart(days: r.dailyTotals),
              ),
              const SizedBox(height: 16),
              _CategoryBreakdown(title: 'Pengeluaran per kategori', items: r.expenseByCategory),
              const SizedBox(height: 16),
              _CategoryBreakdown(title: 'Pemasukan per kategori', items: r.incomeByCategory),
            ]
                .animate(interval: 80.ms)
                .fadeIn(duration: 400.ms)
                .moveY(begin: 16, end: 0, curve: Curves.easeOutCubic),
          ),
        ),
        const SizedBox(height: 16),
        _ChartCard(
          title: 'Tren 6 bulan terakhir',
          child: trend.when(
            data: (t) => _TrendChart(months: t),
            loading: () => const SkeletonBox(height: 200),
            error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(trendProvider)),
          ),
        ).animate().fadeIn(delay: 350.ms, duration: 400.ms),
      ],
    );
  }
}

// =============================================================
// Harian
// =============================================================

class _DailyView extends ConsumerWidget {
  const _DailyView({super.key, required this.day, required this.onDayChanged});

  final DateTime day;
  final ValueChanged<DateTime> onDayChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final report = ref.watch(dailyReportProvider(day));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ReportCalendar(selected: day, onSelected: onDayChanged),
        const SizedBox(height: 20),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: Row(
            key: ValueKey(day),
            children: [
              Icon(Icons.event_note_rounded, size: 20, color: context.colors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  fullDate(day),
                  style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        AsyncView(
          value: report,
          onRetry: () => ref.invalidate(dailyReportProvider),
          loading: const _ReportSkeleton(),
          builder: (r) => Column(
            key: ValueKey(day),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SummaryGrid(summary: r.summary),
              const SizedBox(height: 16),
              _CategoryBreakdown(title: 'Pengeluaran per kategori', items: r.expenseByCategory),
              const SizedBox(height: 16),
              _ChartCard(
                title: 'Daftar transaksi',
                child: r.transactions.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Text(
                          'Tidak ada transaksi di hari ini',
                          textAlign: TextAlign.center,
                          style: context.text.bodyMedium?.copyWith(color: context.colors.onSurfaceVariant),
                        ),
                      )
                    : Column(
                        children: [
                          for (final t in r.transactions)
                            TransactionTile(
                              transaction: t,
                              onTap: () => showTransactionForm(context, existing: t),
                            ),
                        ],
                      ),
              ),
            ]
                .animate(interval: 80.ms)
                .fadeIn(duration: 400.ms)
                .moveY(begin: 16, end: 0, curve: Curves.easeOutCubic),
          ),
        ),
      ],
    );
  }
}

// =============================================================
// Komponen
// =============================================================

class _ReportSkeleton extends StatelessWidget {
  const _ReportSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        Row(
          children: [
            Expanded(child: SkeletonBox(height: 80, radius: 18)),
            SizedBox(width: 12),
            Expanded(child: SkeletonBox(height: 80, radius: 18)),
          ],
        ),
        SizedBox(height: 12),
        SkeletonBox(height: 70, radius: 18),
        SizedBox(height: 16),
        SkeletonBox(height: 240, radius: 20),
      ],
    );
  }
}

class _SummaryGrid extends StatelessWidget {
  const _SummaryGrid({required this.summary});

  final ReportSummary summary;

  @override
  Widget build(BuildContext context) {
    final positive = summary.balance >= 0;
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _StatCard(
                label: 'Pemasukan',
                value: summary.income,
                color: AppColors.income,
                icon: Icons.south_west_rounded,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatCard(
                label: 'Pengeluaran',
                value: summary.expense,
                color: AppColors.expense,
                icon: Icons.north_east_rounded,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: positive ? AppColors.heroGradient : null,
            color: positive ? null : AppColors.expense,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              Icon(
                positive ? Icons.trending_up_rounded : Icons.trending_down_rounded,
                color: Colors.white,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  positive ? 'Selisih (hemat)' : 'Selisih (boros)',
                  style: context.text.titleSmall?.copyWith(color: Colors.white),
                ),
              ),
              AnimatedRupiah(
                summary.balance,
                style: context.text.titleMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.value, required this.color, required this.icon});

  final String label;
  final int value;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.14), shape: BoxShape.circle),
                  child: Icon(icon, size: 16, color: color),
                ),
                const SizedBox(width: 8),
                Text(label, style: context.text.labelMedium?.copyWith(color: context.colors.onSurfaceVariant)),
              ],
            ),
            const SizedBox(height: 10),
            AnimatedRupiah(
              value,
              compact: value >= 100000000,
              style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChartCard extends StatelessWidget {
  const _ChartCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}

Widget _axisLabel(BuildContext context, String text) => Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(text, style: context.text.labelSmall?.copyWith(color: context.colors.onSurfaceVariant)),
    );

BarTouchData _barTouch(BuildContext context, String Function(int group) title) => BarTouchData(
      touchTooltipData: BarTouchTooltipData(
        getTooltipColor: (_) => context.colors.inverseSurface,
        getTooltipItem: (group, _, rod, rodIndex) => BarTooltipItem(
          rodIndex == 0 ? '${title(group.x)}\n' : '',
          TextStyle(color: context.colors.onInverseSurface, fontWeight: FontWeight.w600, fontSize: 12),
          children: [
            TextSpan(
              text: rupiah(rod.toY.round()),
              style: TextStyle(color: rod.color, fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );

class _DailyBarChart extends StatelessWidget {
  const _DailyBarChart({required this.days});

  final List<DailyTotal> days;

  @override
  Widget build(BuildContext context) {
    final hasData = days.any((d) => d.income > 0 || d.expense > 0);
    if (!hasData) {
      return SizedBox(
        height: 120,
        child: Center(
          child: Text(
            'Belum ada transaksi bulan ini',
            style: context.text.bodyMedium?.copyWith(color: context.colors.onSurfaceVariant),
          ),
        ),
      );
    }

    return SizedBox(
      height: 200,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 900),
        curve: Curves.easeOutCubic,
        builder: (context, t, _) => BarChart(
          BarChartData(
            alignment: BarChartAlignment.spaceAround,
            gridData: FlGridData(
              drawVerticalLine: false,
              getDrawingHorizontalLine: (_) => FlLine(color: context.colors.outlineVariant, strokeWidth: 1),
            ),
            borderData: FlBorderData(show: false),
            barTouchData: _barTouch(context, (x) => 'Tanggal ${x + 1}'),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(),
              rightTitles: const AxisTitles(),
              leftTitles: const AxisTitles(),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  getTitlesWidget: (v, _) {
                    final day = v.toInt() + 1;
                    return (day == 1 || day % 5 == 0) ? _axisLabel(context, '$day') : const SizedBox.shrink();
                  },
                ),
              ),
            ),
            barGroups: [
              for (var i = 0; i < days.length; i++)
                BarChartGroupData(
                  x: i,
                  barsSpace: 1,
                  barRods: [
                    BarChartRodData(
                      toY: days[i].income * t,
                      color: AppColors.income,
                      width: 3.5,
                      borderRadius: BorderRadius.circular(2),
                    ),
                    BarChartRodData(
                      toY: days[i].expense * t,
                      color: AppColors.expense,
                      width: 3.5,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TrendChart extends StatelessWidget {
  const _TrendChart({required this.months});

  final List<MonthlyTotal> months;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 200,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 1000),
        curve: Curves.easeOutCubic,
        builder: (context, t, _) => BarChart(
          BarChartData(
            alignment: BarChartAlignment.spaceAround,
            gridData: FlGridData(
              drawVerticalLine: false,
              getDrawingHorizontalLine: (_) => FlLine(color: context.colors.outlineVariant, strokeWidth: 1),
            ),
            borderData: FlBorderData(show: false),
            barTouchData: _barTouch(context, (x) => monthLabel(months[x].month)),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(),
              rightTitles: const AxisTitles(),
              leftTitles: const AxisTitles(),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  getTitlesWidget: (v, _) => _axisLabel(context, shortMonth(months[v.toInt()].month)),
                ),
              ),
            ),
            barGroups: [
              for (var i = 0; i < months.length; i++)
                BarChartGroupData(
                  x: i,
                  barsSpace: 4,
                  barRods: [
                    BarChartRodData(
                      toY: months[i].income * t,
                      color: AppColors.income,
                      width: 12,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    BarChartRodData(
                      toY: months[i].expense * t,
                      color: AppColors.expense,
                      width: 12,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Donut chart + daftar kategori dengan persentase.
class _CategoryBreakdown extends StatefulWidget {
  const _CategoryBreakdown({required this.title, required this.items});

  final String title;
  final List<CategoryTotal> items;

  @override
  State<_CategoryBreakdown> createState() => _CategoryBreakdownState();
}

class _CategoryBreakdownState extends State<_CategoryBreakdown> {
  int _touched = -1;

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    final total = items.fold<int>(0, (s, c) => s + c.total);

    return _ChartCard(
      title: widget.title,
      child: items.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                'Belum ada data',
                textAlign: TextAlign.center,
                style: context.text.bodyMedium?.copyWith(color: context.colors.onSurfaceVariant),
              ),
            )
          : Column(
              children: [
                SizedBox(
                  height: 200,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      PieChart(
                        PieChartData(
                          sectionsSpace: 3,
                          centerSpaceRadius: 62,
                          startDegreeOffset: -90,
                          pieTouchData: PieTouchData(
                            touchCallback: (event, response) {
                              if (!event.isInterestedForInteractions || response?.touchedSection == null) {
                                if (_touched != -1) setState(() => _touched = -1);
                                return;
                              }
                              setState(() => _touched = response!.touchedSection!.touchedSectionIndex);
                            },
                          ),
                          sections: [
                            for (var i = 0; i < items.length; i++)
                              PieChartSectionData(
                                value: items[i].total.toDouble(),
                                color: items[i].color,
                                radius: i == _touched ? 30 : 22,
                                showTitle: false,
                              ),
                          ],
                        ),
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOut,
                      )
                          .animate()
                          .rotate(begin: -0.25, end: 0, duration: 800.ms, curve: Curves.easeOutCubic)
                          .scaleXY(begin: 0.6, end: 1, duration: 800.ms, curve: Curves.easeOutBack),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        child: Column(
                          key: ValueKey(_touched),
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _touched >= 0 && _touched < items.length ? items[_touched].name : 'Total',
                              style: context.text.labelMedium?.copyWith(color: context.colors.onSurfaceVariant),
                            ),
                            Text(
                              rupiahCompact(
                                  _touched >= 0 && _touched < items.length ? items[_touched].total : total),
                              style: context.text.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                for (var i = 0; i < items.length; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        CategoryIcon(icon: items[i].icon, color: items[i].color, size: 36),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      items[i].name,
                                      style: context.text.labelLarge?.copyWith(fontWeight: FontWeight.w700),
                                    ),
                                  ),
                                  Text(
                                    rupiah(items[i].total),
                                    style: context.text.labelLarge?.copyWith(fontWeight: FontWeight.w700),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Expanded(
                                    child: AnimatedProgressBar(
                                      value: items[i].percentage / 100,
                                      color: items[i].color,
                                      height: 6,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  SizedBox(
                                    width: 44,
                                    child: Text(
                                      '${items[i].percentage.toStringAsFixed(1)}%',
                                      textAlign: TextAlign.end,
                                      style: context.text.labelSmall?.copyWith(
                                        color: context.colors.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
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
