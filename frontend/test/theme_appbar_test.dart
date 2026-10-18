import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/theme.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('judul AppBar memakai gaya tema (besar & tebal)', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(appBar: AppBar(title: const Text('Transaksi'))),
      ),
    );
    final style = tester
        .widget<RichText>(find.descendant(of: find.byType(AppBar), matching: find.byType(RichText)))
        .text
        .style;
    expect(style?.fontSize, greaterThanOrEqualTo(20));
    expect(style?.fontWeight, FontWeight.w800);
  });
}
