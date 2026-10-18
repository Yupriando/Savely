import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/format.dart';
import 'package:frontend/data/models.dart';
import 'package:frontend/widgets/celebration.dart';
import 'package:frontend/widgets/user_avatar.dart';

void main() {
  group('greetingFor mengikuti jam', () {
    String at(int hour, [int minute = 0]) => greetingFor(DateTime(2026, 10, 18, hour, minute)).text;

    test('dini hari & malam = Selamat malam', () {
      expect(at(0), 'Selamat malam');
      expect(at(1, 12), 'Selamat malam'); // kasus bug sebelumnya
      expect(at(3, 59), 'Selamat malam');
      expect(at(18), 'Selamat malam');
      expect(at(23, 59), 'Selamat malam');
    });

    test('pagi, siang, sore', () {
      expect(at(4), 'Selamat pagi');
      expect(at(10, 59), 'Selamat pagi');
      expect(at(11), 'Selamat siang');
      expect(at(14, 59), 'Selamat siang');
      expect(at(15), 'Selamat sore');
      expect(at(17, 59), 'Selamat sore');
    });
  });

  testWidgets('animasi sukses + confetti tampil lalu hilang sendiri', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showSuccess(context, 'Tersimpan', confetti: true),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('go'));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Tersimpan'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Overlay menghapus dirinya setelah animasi selesai
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Tersimpan'), findsNothing);
  });

  testWidgets('avatar tanpa foto menampilkan inisial', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: UserAvatar(user: AppUser(id: '1', email: 'yupri@mail.com', fullName: 'Yupriando')),
        ),
      ),
    );
    expect(find.text('Y'), findsOneWidget);
  });
}
