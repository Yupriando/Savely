import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config.dart';
import '../../core/export.dart';
import '../../core/theme.dart';
import '../../data/providers.dart';
import '../../widgets/common.dart';
import '../../widgets/user_avatar.dart';
import '../bills/bills_screen.dart';
import '../budgets/budgets_screen.dart';
import '../categories/categories_screen.dart';
import '../wallets/wallets_screen.dart';
import 'edit_profile_screen.dart';
import '../../widgets/stagger.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  Future<void> _logout(BuildContext context, WidgetRef ref) async {
    final ok = await confirmDialog(
      context,
      title: 'Keluar dari akun?',
      message: 'Kamu perlu login lagi untuk melihat datamu.',
      confirmLabel: 'Keluar',
    );
    if (!ok || !context.mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
    await ref.read(authProvider.notifier).logout();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).valueOrNull;
    final mode = ref.watch(themeModeProvider);
    final soundOn = ref.watch(soundEnabledProvider);
    final name = user?.displayName ?? '';

    return Scaffold(
      appBar: AppBar(title: const Text('Pengaturan')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children:
            [
                  // Profil (ketuk untuk edit)
                  Pressable(
                    onTap: () => Navigator.of(
                      context,
                    ).push(MaterialPageRoute<void>(builder: (_) => const EditProfileScreen())),
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Row(
                          children: [
                            Hero(
                              tag: 'avatar',
                              child: UserAvatar(user: user, size: 60),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    name,
                                    style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                                  ),
                                  Text(
                                    user?.email ?? '',
                                    style: context.text.bodyMedium?.copyWith(
                                      color: context.colors.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(Icons.edit_rounded, size: 20, color: context.colors.onSurfaceVariant),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const SectionTitle('Keuangan'),
                  const SizedBox(height: 10),
                  Card(
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        _MenuTile(
                          icon: Icons.account_balance_wallet_rounded,
                          color: AppColors.emerald,
                          title: 'Dompet',
                          subtitle: 'Tunai, bank, e-wallet & transfer',
                          onTap: () => openWallets(context),
                        ),
                        _MenuTile(
                          icon: Icons.track_changes_rounded,
                          color: AppColors.gold,
                          title: 'Anggaran',
                          subtitle: 'Batas pengeluaran per kategori',
                          onTap: () => openBudgets(context),
                        ),
                        _MenuTile(
                          icon: Icons.event_repeat_rounded,
                          color: const Color(0xFFEC407A),
                          title: 'Tagihan rutin',
                          subtitle: 'IPL, listrik, kiriman orang tua…',
                          onTap: () => openBills(context),
                        ),
                        _MenuTile(
                          icon: Icons.category_rounded,
                          color: const Color(0xFF7E57C2),
                          title: 'Kelola kategori',
                          subtitle: 'Tambah, ubah nama, ikon & warna',
                          onTap: () => openCategories(context),
                        ),
                        _MenuTile(
                          icon: Icons.file_download_rounded,
                          color: const Color(0xFF0EA5E9),
                          title: 'Ekspor ke CSV / Excel',
                          subtitle: 'Unduh transaksi dalam rentang tanggal',
                          onTap: () => showExportDialog(context, ref),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  const SectionTitle('Tampilan'),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      for (final (m, icon, label) in const [
                        (ThemeMode.system, Icons.brightness_auto_rounded, 'Sistem'),
                        (ThemeMode.light, Icons.light_mode_rounded, 'Terang'),
                        (ThemeMode.dark, Icons.dark_mode_rounded, 'Gelap'),
                      ])
                        Expanded(
                          child: Padding(
                            padding: EdgeInsets.only(right: m == ThemeMode.dark ? 0 : 10),
                            child: _ThemeOption(
                              icon: icon,
                              label: label,
                              selected: mode == m,
                              onTap: () => ref.read(themeModeProvider.notifier).set(m),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Card(
                    clipBehavior: Clip.antiAlias,
                    child: SwitchListTile(
                      secondary: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 250),
                        transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
                        child: Icon(
                          soundOn ? Icons.volume_up_rounded : Icons.volume_off_rounded,
                          key: ValueKey(soundOn),
                          color: soundOn ? context.colors.primary : context.colors.onSurfaceVariant,
                        ),
                      ),
                      title: const Text('Efek suara', style: TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: const Text('Bunyi saat menyimpan, uang masuk, dan menghapus'),
                      value: soundOn,
                      onChanged: (v) => ref.read(soundEnabledProvider.notifier).set(v),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const SectionTitle('Tentang'),
                  const SizedBox(height: 10),
                  Card(
                    child: Column(
                      children: [
                        const ListTile(
                          leading: Icon(Icons.savings_rounded),
                          title: Text('Savely'),
                          subtitle: Text('Versi 1.0.0'),
                        ),
                        const Divider(indent: 16, endIndent: 16),
                        ListTile(
                          leading: const Icon(Icons.dns_rounded),
                          title: const Text('Server'),
                          subtitle: Text(AppConfig.apiUrl),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.expense,
                      side: BorderSide(color: AppColors.expense.withValues(alpha: 0.5)),
                    ),
                    onPressed: () => _logout(context, ref),
                    icon: const Icon(Icons.logout_rounded),
                    label: const Text('Keluar'),
                  ),
                ]
                .staggered(interval: 60.ms)
                .fadeIn(duration: 350.ms)
                .moveY(begin: 14, end: 0, curve: Curves.easeOutCubic),
      ),
    );
  }
}

class _ThemeOption extends StatelessWidget {
  const _ThemeOption({required this.icon, required this.label, required this.selected, required this.onTap});

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final primary = context.colors.primary;
    return Pressable(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: selected ? primary.withValues(alpha: 0.12) : context.colors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: selected ? primary : context.colors.outlineVariant, width: 1.6),
        ),
        child: Column(
          children: [
            AnimatedRotation(
              turns: selected ? 0.5 : 0,
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeOutBack,
              child: Icon(icon, color: selected ? primary : context.colors.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: context.text.labelLarge?.copyWith(
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? primary : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: color, size: 22),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right_rounded),
    );
  }
}
