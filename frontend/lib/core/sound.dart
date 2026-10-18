import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// Efek suara Savely. File-nya di assets/sounds (dibuat oleh tool/generate_sounds.mjs).
enum Sfx {
  /// Ganti tab / pilihan.
  tap(0.45),

  /// Berhasil menyimpan.
  success(0.8),

  /// Pemasukan / setor tabungan.
  coin(0.8),

  /// Target wishlist tercapai.
  celebrate(0.85),

  /// Data dihapus.
  delete(0.7),

  /// Terjadi kesalahan.
  error(0.7);

  const Sfx(this.volume);

  final double volume;
}

class SoundFx {
  SoundFx._();

  /// Diatur dari Pengaturan > Efek suara. Default mati sampai [init] dipanggil (mis. di test).
  static bool enabled = false;

  static final _players = <Sfx, AudioPlayer>{};

  /// Dipanggil sekali di main().
  static Future<void> init({required bool enabled}) async {
    SoundFx.enabled = enabled;
    try {
      // Jangan menghentikan musik yang sedang diputar user, dan ikuti mode senyap di iPhone.
      await AudioPlayer.global.setAudioContext(
        AudioContextConfig(focus: AudioContextConfigFocus.mixWithOthers, respectSilence: true).build(),
      );
    } catch (e) {
      debugPrint('Audio context tidak bisa diatur: $e');
    }
  }

  /// Putar efek suara. Tidak pernah melempar error (suara bukan hal yang boleh bikin app gagal).
  static void play(Sfx sfx) {
    if (!enabled) return;
    try {
      final player = _players.putIfAbsent(sfx, () {
        final p = AudioPlayer();
        if (!kIsWeb) unawaited(p.setPlayerMode(PlayerMode.lowLatency).catchError((_) {}));
        unawaited(p.setReleaseMode(ReleaseMode.stop).catchError((_) {}));
        return p;
      });
      unawaited(
        player
            .stop()
            .then((_) => player.play(AssetSource('sounds/${sfx.name}.wav'), volume: sfx.volume))
            .catchError((Object e) => debugPrint('Gagal memutar ${sfx.name}: $e')),
      );
    } catch (e) {
      debugPrint('Gagal memutar ${sfx.name}: $e');
    }
  }
}
