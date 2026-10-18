import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../widgets/common.dart';

/// Kalender bulanan: tiap tanggal menampilkan total keluar/masuk,
/// warna makin merah = pengeluaran makin besar. Ketuk tanggal untuk memilih.
class ReportCalendar extends ConsumerStatefulWidget {
  const ReportCalendar({super.key, required this.selected, required this.onSelected});

  final DateTime selected;
  final ValueChanged<DateTime> onSelected;

  @override
  ConsumerState<ReportCalendar> createState() => _ReportCalendarState();
}

class _ReportCalendarState extends ConsumerState<ReportCalendar> {
  static const _weekdays = ['Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min'];

  /// 1 = geser ke bulan berikutnya, -1 = ke bulan sebelumnya (arah animasi).
  int _direction = 1;

  DateTime get _month => monthOnly(widget.selected);

  void _changeMonth(int delta) => _goToMonth(DateTime(_month.year, _month.month + delta));

  void _goToMonth(DateTime target) {
    final now = DateTime.now();
    if (target.isAfter(monthOnly(now)) || target == _month) return;

    setState(() => _direction = target.isBefore(_month) ? -1 : 1);
    final isCurrent = target.year == now.year && target.month == now.month;
    widget.onSelected(isCurrent ? dateOnly(now) : target);
  }

  @override
  Widget build(BuildContext context) {
    final report = ref.watch(monthlyReportProvider(_month));
    final totals = {
      for (final d in report.valueOrNull?.dailyTotals ?? const <DailyTotal>[]) dateOnly(d.day): d,
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 14),
        child: Column(
          children: [
            MonthSwitcher(month: _month, onChanged: _goToMonth),
            const SizedBox(height: 12),
            Row(
              children: [
                for (final w in _weekdays)
                  Expanded(
                    child: Text(
                      w,
                      textAlign: TextAlign.center,
                      style: context.text.labelSmall?.copyWith(
                        color: w == 'Min' ? AppColors.expense : context.colors.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            // Geser kiri/kanan untuk ganti bulan
            GestureDetector(
              onHorizontalDragEnd: (d) {
                final v = d.primaryVelocity ?? 0;
                if (v < -200) _changeMonth(1);
                if (v > 200) _changeMonth(-1);
              },
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                switchInCurve: Curves.easeOutCubic,
                transitionBuilder: (child, anim) {
                  final incoming = child.key == ValueKey(_month);
                  final dx = (incoming ? 0.15 : -0.15) * _direction;
                  return FadeTransition(
                    opacity: anim,
                    child: SlideTransition(
                      position: Tween(begin: Offset(dx, 0), end: Offset.zero).animate(anim),
                      child: child,
                    ),
                  );
                },
                child: report.hasValue
                    ? _Grid(
                        key: ValueKey(_month),
                        month: _month,
                        selected: dateOnly(widget.selected),
                        totals: totals,
                        onTap: widget.onSelected,
                      )
                    : const SkeletonBox(key: ValueKey('loading'), height: 300, radius: 16),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _LegendDot(color: AppColors.expense, label: 'Keluar'),
                const SizedBox(width: 16),
                _LegendDot(color: AppColors.income, label: 'Masuk'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Grid extends StatelessWidget {
  const _Grid({
    super.key,
    required this.month,
    required this.selected,
    required this.totals,
    required this.onTap,
  });

  final DateTime month;
  final DateTime selected;
  final Map<DateTime, DailyTotal> totals;
  final ValueChanged<DateTime> onTap;

  @override
  Widget build(BuildContext context) {
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final leading = DateTime(month.year, month.month).weekday - 1; // minggu mulai Senin
    final cellCount = ((leading + daysInMonth) / 7).ceil() * 7;
    final maxExpense = totals.values.fold<int>(0, (m, d) => d.expense > m ? d.expense : m);
    final today = dateOnly(DateTime.now());

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      itemCount: cellCount,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
        childAspectRatio: 0.78,
      ),
      itemBuilder: (context, i) {
        final dayNum = i - leading + 1;
        if (dayNum < 1 || dayNum > daysInMonth) return const SizedBox.shrink();
        final date = DateTime(month.year, month.month, dayNum);
        return _DayCell(
          date: date,
          total: totals[date],
          maxExpense: maxExpense,
          isSelected: date == selected,
          isToday: date == today,
          isFuture: date.isAfter(today),
          onTap: () => onTap(date),
        );
      },
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.date,
    required this.total,
    required this.maxExpense,
    required this.isSelected,
    required this.isToday,
    required this.isFuture,
    required this.onTap,
  });

  final DateTime date;
  final DailyTotal? total;
  final int maxExpense;
  final bool isSelected;
  final bool isToday;
  final bool isFuture;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final expense = total?.expense ?? 0;
    final income = total?.income ?? 0;

    // Intensitas merah sesuai besar pengeluaran dibanding hari paling boros
    final heat = maxExpense == 0 ? 0.0 : expense / maxExpense;
    final background = isSelected
        ? context.colors.primary
        : expense > 0
        ? AppColors.expense.withValues(alpha: 0.06 + heat * 0.22)
        : income > 0
        ? AppColors.income.withValues(alpha: 0.08)
        : context.colors.surfaceContainer.withValues(alpha: isFuture ? 0.4 : 1);

    final dayColor = isSelected
        ? Colors.white
        : isFuture
        ? context.colors.onSurfaceVariant.withValues(alpha: 0.4)
        : date.weekday == DateTime.sunday
        ? AppColors.expense
        : context.colors.onSurface;

    final amountStyle = context.text.labelSmall?.copyWith(
      fontSize: 9,
      fontWeight: FontWeight.w700,
      height: 1.15,
    );

    return Pressable(
      onTap: isFuture ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(12),
          border: isToday && !isSelected ? Border.all(color: context.colors.primary, width: 1.6) : null,
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: context.colors.primary.withValues(alpha: 0.4),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 2),
        child: Column(
          children: [
            Text(
              '${date.day}',
              style: context.text.labelLarge?.copyWith(fontWeight: FontWeight.w800, color: dayColor),
            ),
            const Spacer(),
            if (expense > 0)
              FittedBox(
                child: Text(
                  '-${shortAmount(expense)}',
                  style: amountStyle?.copyWith(color: isSelected ? Colors.white : AppColors.expense),
                ),
              ),
            if (income > 0)
              FittedBox(
                child: Text(
                  '+${shortAmount(income)}',
                  style: amountStyle?.copyWith(color: isSelected ? Colors.white : AppColors.income),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: context.text.labelSmall?.copyWith(color: context.colors.onSurfaceVariant)),
      ],
    );
  }
}
