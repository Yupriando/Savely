import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/format.dart';
import 'package:frontend/data/models.dart';
import 'package:frontend/data/providers.dart';
import 'package:frontend/features/reports/report_calendar.dart';
import 'package:intl/date_symbol_data_local.dart';

MonthlyReport _fakeReport(DateTime month) {
  final days = DateTime(month.year, month.month + 1, 0).day;
  return MonthlyReport(
    summary: const ReportSummary(income: 0, expense: 0, balance: 0, count: 0),
    dailyTotals: [
      for (var d = 1; d <= days; d++)
        DailyTotal(
          day: DateTime(month.year, month.month, d),
          // Variasi: kosong, kecil, besar sekali, ada pemasukan juta-an
          expense: d % 3 == 0 ? 0 : d * 37500,
          income: d % 5 == 0 ? 12500000 : 0,
        ),
    ],
    expenseByCategory: const [],
    incomeByCategory: const [],
  );
}

void main() {
  setUpAll(() => initializeDateFormatting('id_ID'));

  test('shortAmount meringkas nominal', () {
    expect(shortAmount(500), '500');
    expect(shortAmount(50000), '50rb');
    expect(shortAmount(1500000), '1,5jt');
    expect(shortAmount(12500000), '12,5jt');
    expect(shortAmount(250000000), '250jt');
  });

  testWidgets('kalender tampil tanpa overflow di layar sempit & bisa pilih tanggal', (tester) async {
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final month = monthOnly(DateTime.now());
    final firstDay = DateTime(month.year, month.month);
    DateTime? picked;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          monthlyReportProvider.overrideWith((ref, m) async => _fakeReport(m)),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: StatefulBuilder(
                builder: (context, setState) => ReportCalendar(
                  selected: picked ?? firstDay,
                  onSelected: (d) => setState(() => picked = d),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(seconds: 1));

    // Tidak ada error layout (overflow dsb.)
    expect(tester.takeException(), isNull);
    // Nama bulan & tanggal 1 tampil
    expect(find.text(monthLabel(month)), findsOneWidget);
    expect(find.text('1'), findsOneWidget);

    // Ketuk tanggal 1 -> terpilih
    await tester.tap(find.text('1'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(seconds: 1));
    expect(picked, firstDay);
  });
}
