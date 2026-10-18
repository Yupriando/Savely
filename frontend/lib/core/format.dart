import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

final _rupiah = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp', decimalDigits: 0);
final _rupiahCompact = NumberFormat.compactCurrency(locale: 'id_ID', symbol: 'Rp', decimalDigits: 0);
final _thousands = NumberFormat.decimalPattern('id_ID');

/// 25000 -> "Rp25.000"
String rupiah(num value) => _rupiah.format(value);

/// 2500000 -> "Rp3 jt"
String rupiahCompact(num value) => _rupiahCompact.format(value);

/// Dengan tanda + / - untuk pemasukan / pengeluaran.
String signedRupiah(num value, {required bool isIncome}) =>
    '${isIncome ? '+' : '-'}${rupiah(value.abs())}';

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
DateTime monthOnly(DateTime d) => DateTime(d.year, d.month);

/// Format yang dipakai API.
String isoDate(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
String isoMonth(DateTime d) => DateFormat('yyyy-MM').format(d);

String monthLabel(DateTime d) => DateFormat('MMMM yyyy', 'id_ID').format(d);
String shortMonth(DateTime d) => DateFormat('MMM', 'id_ID').format(d);
String fullDate(DateTime d) => DateFormat('EEEE, d MMMM yyyy', 'id_ID').format(d);
String shortDate(DateTime d) => DateFormat('d MMM yyyy', 'id_ID').format(d);

/// "Hari ini", "Kemarin", atau "Senin, 12 Okt".
String relativeDay(DateTime d) {
  final today = dateOnly(DateTime.now());
  final diff = today.difference(dateOnly(d)).inDays;
  if (diff == 0) return 'Hari ini';
  if (diff == 1) return 'Kemarin';
  if (diff == -1) return 'Besok';
  final sameYear = d.year == today.year;
  return DateFormat(sameYear ? 'EEEE, d MMM' : 'EEEE, d MMM yyyy', 'id_ID').format(d);
}

/// Sapaan sesuai jam sistem: pagi 04–10, siang 11–14, sore 15–17, malam 18–03.
({String text, String emoji}) greetingFor(DateTime time) {
  final h = time.hour;
  if (h >= 4 && h < 11) return (text: 'Selamat pagi', emoji: '🌤️');
  if (h >= 11 && h < 15) return (text: 'Selamat siang', emoji: '☀️');
  if (h >= 15 && h < 18) return (text: 'Selamat sore', emoji: '🌇');
  return (text: 'Selamat malam', emoji: '🌙');
}

int parseAmount(String text) => int.tryParse(text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;

/// Ketik "25000" -> tampil "25.000".
class ThousandsInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    var digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return const TextEditingValue();
    if (digits.length > 13) digits = digits.substring(0, 13);
    final text = _thousands.format(int.parse(digits));
    return TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
  }
}

String formatThousands(int value) => _thousands.format(value);

/// Nominal super singkat untuk sel kalender: 50000 -> "50rb", 1500000 -> "1,5jt".
String shortAmount(int value) {
  String trim(double v) {
    final s = v >= 100 ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
    return s.endsWith('.0') ? s.substring(0, s.length - 2) : s.replaceAll('.', ',');
  }

  final v = value.abs();
  if (v >= 1000000000) return '${trim(v / 1000000000)}M';
  if (v >= 1000000) return '${trim(v / 1000000)}jt';
  if (v >= 1000) return '${trim(v / 1000)}rb';
  return '$v';
}
