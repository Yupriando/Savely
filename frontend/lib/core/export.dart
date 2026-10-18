import 'package:file_saver/file_saver.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/providers.dart';
import '../widgets/celebration.dart';
import '../widgets/common.dart';
import 'format.dart';

/// Unduh transaksi [start]..[end] sebagai CSV (bisa dibuka di Excel / Google Sheets).
Future<void> exportTransactionsCsv(BuildContext context, WidgetRef ref, DateTime start, DateTime end) async {
  try {
    final bytes = await ref.read(apiProvider).exportTransactions(start, end);
    final name = 'savely_${isoDate(start)}_${isoDate(end)}';
    // Web: langsung terunduh. HP/desktop: muncul dialog "Simpan sebagai".
    final saved = kIsWeb
        ? await FileSaver.instance.saveFile(
            name: name,
            bytes: bytes,
            fileExtension: 'csv',
            mimeType: MimeType.csv,
          )
        : await FileSaver.instance.saveAs(
            name: name,
            bytes: bytes,
            fileExtension: 'csv',
            mimeType: MimeType.csv,
          );
    if (!context.mounted || saved == null) return;
    showSuccess(context, 'File CSV tersimpan');
  } catch (e) {
    if (context.mounted) showSnack(context, 'Gagal mengekspor: $e', error: true);
  }
}

/// Pilih rentang lalu ekspor.
Future<void> showExportDialog(BuildContext context, WidgetRef ref, {DateTime? month}) async {
  final m = month ?? monthOnly(DateTime.now());
  final range = await showDateRangePicker(
    context: context,
    firstDate: DateTime(2020),
    lastDate: DateTime.now(),
    initialDateRange: DateTimeRange(
      start: DateTime(m.year, m.month),
      end: _minDate(DateTime(m.year, m.month + 1, 0), dateOnly(DateTime.now())),
    ),
    helpText: 'Pilih rentang transaksi yang diekspor',
    saveText: 'Ekspor',
  );
  if (range == null || !context.mounted) return;
  await exportTransactionsCsv(context, ref, range.start, range.end);
}

DateTime _minDate(DateTime a, DateTime b) => a.isBefore(b) ? a : b;
