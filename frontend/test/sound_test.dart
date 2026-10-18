import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/sound.dart';

void main() {
  for (final sfx in Sfx.values) {
    test('assets/sounds/${sfx.name}.wav valid & tidak senyap', () {
      final file = File('assets/sounds/${sfx.name}.wav');
      expect(file.existsSync(), isTrue, reason: 'jalankan: node tool/generate_sounds.mjs');

      final bytes = file.readAsBytesSync();
      final data = ByteData.sublistView(bytes);
      expect(String.fromCharCodes(bytes.sublist(0, 4)), 'RIFF');
      expect(String.fromCharCodes(bytes.sublist(8, 12)), 'WAVE');
      expect(data.getUint16(22, Endian.little), 1, reason: 'mono');
      expect(data.getUint32(24, Endian.little), 44100, reason: 'sample rate');
      expect(data.getUint16(34, Endian.little), 16, reason: '16-bit');

      final samples = data.getUint32(40, Endian.little) ~/ 2;
      final seconds = samples / 44100;
      expect(seconds, inInclusiveRange(0.03, 1.5), reason: 'efek suara harus pendek');

      var peak = 0;
      for (var i = 0; i < samples; i++) {
        final v = data.getInt16(44 + i * 2, Endian.little).abs();
        if (v > peak) peak = v;
      }
      // Ada bunyinya, tapi tidak memekakkan (puncak < 60% skala penuh)
      expect(peak, greaterThan(3000));
      expect(peak, lessThan((32767 * 0.6).round()));
    });
  }

  test('SoundFx.play tidak melakukan apa-apa saat efek suara mati', () {
    SoundFx.enabled = false;
    expect(() => SoundFx.play(Sfx.success), returnsNormally);
  });
}
