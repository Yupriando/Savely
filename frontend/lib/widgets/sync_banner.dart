import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../data/offline_queue.dart';
import '../data/providers.dart';

/// Status koneksi & antrean offline, tampil di atas navigasi bawah hanya bila perlu.
class SyncBanner extends ConsumerWidget {
  const SyncBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final api = ref.watch(apiProvider);
    final sync = ref.watch(syncProvider);

    return ValueListenableBuilder<bool>(
      valueListenable: api.online,
      builder: (context, online, _) {
        final pending = sync.pending.length;
        final failed = sync.failedCount;
        final show = !online || pending > 0;

        final (Color color, IconData icon, String text, Widget action) = !online
            ? (
                AppColors.gold,
                Icons.cloud_off_rounded,
                pending > 0
                    ? 'Offline · $pending transaksi disimpan di HP'
                    : 'Offline · menampilkan data terakhir',
                TextButton(
                  onPressed: () {
                    invalidateFinance(ref.invalidate);
                    ref.read(syncProvider.notifier).syncNow();
                  },
                  child: const Text('Coba lagi'),
                ),
              )
            : sync.syncing
            ? (
                context.colors.primary,
                Icons.cloud_upload_rounded,
                'Mengirim $pending transaksi…',
                const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2)),
              )
            : failed > 0
            ? (
                AppColors.expense,
                Icons.error_outline_rounded,
                '$failed transaksi gagal dikirim · ketuk untuk perbaiki',
                TextButton(
                  onPressed: () => ref.read(syncProvider.notifier).syncNow(retryFailed: true),
                  child: const Text('Coba lagi'),
                ),
              )
            : (
                AppColors.gold,
                Icons.cloud_upload_rounded,
                '$pending transaksi menunggu dikirim',
                TextButton(
                  onPressed: () => ref.read(syncProvider.notifier).syncNow(),
                  child: const Text('Kirim sekarang'),
                ),
              );

        return AnimatedSize(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          child: !show
              ? const SizedBox(width: double.infinity)
              : Material(
                  color: color.withValues(alpha: context.isDark ? 0.22 : 0.14),
                  child: InkWell(
                    // Ketuk -> buka tab Transaksi untuk melihat yang belum terkirim
                    onTap: pending > 0 ? () => ref.read(shellTabProvider.notifier).state = 1 : null,
                    child: SafeArea(
                      top: false,
                      bottom: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
                        child: Row(
                          children: [
                            Icon(icon, size: 18, color: color)
                                .animate(onPlay: (c) => c.repeat(reverse: true))
                                .fade(begin: 0.55, end: 1, duration: 900.ms),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                text,
                                maxLines: 2,
                                style: context.text.labelMedium?.copyWith(
                                  color: context.colors.onSurface,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            action,
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
        );
      },
    );
  }
}
