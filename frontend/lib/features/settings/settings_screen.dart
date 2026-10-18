import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config.dart';
import '../../core/theme.dart';
import '../../data/providers.dart';
import '../../widgets/common.dart';
import '../../widgets/user_avatar.dart';
import 'edit_profile_screen.dart';

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
                .animate(interval: 60.ms)
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
