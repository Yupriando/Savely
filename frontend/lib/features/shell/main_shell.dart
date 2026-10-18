import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/sound.dart';
import '../../data/providers.dart';
import '../../widgets/sync_banner.dart';
import '../home/home_screen.dart';
import '../reports/reports_screen.dart';
import '../transactions/transactions_screen.dart';
import '../wishlist/wishlist_screen.dart';

class MainShell extends ConsumerWidget {
  const MainShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final index = ref.watch(shellTabProvider);

    return Scaffold(
      body: _FadeIndexedStack(
        index: index,
        children: const [HomeScreen(), TransactionsScreen(), WishlistScreen(), ReportsScreen()],
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SyncBanner(),
          NavigationBar(
            selectedIndex: index,
            onDestinationSelected: (i) {
              if (i != index) SoundFx.play(Sfx.tap);
              ref.read(shellTabProvider.notifier).state = i;
            },
            animationDuration: const Duration(milliseconds: 500),
            destinations: [
              for (final (icon, selected, label) in const [
                (Icons.home_outlined, Icons.home_rounded, 'Beranda'),
                (Icons.receipt_long_outlined, Icons.receipt_long_rounded, 'Transaksi'),
                (Icons.favorite_outline_rounded, Icons.favorite_rounded, 'Wishlist'),
                (Icons.pie_chart_outline_rounded, Icons.pie_chart_rounded, 'Laporan'),
              ])
                NavigationDestination(
                  icon: Icon(icon),
                  // Ikon tab yang dipilih memantul & sedikit berputar
                  selectedIcon: Icon(selected)
                      .animate()
                      .scaleXY(begin: 0.6, end: 1, duration: 550.ms, curve: Curves.elasticOut)
                      .rotate(begin: -0.08, end: 0, duration: 400.ms, curve: Curves.easeOutBack),
                  label: label,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// IndexedStack (state tiap tab tetap tersimpan) + animasi fade & geser saat ganti tab.
class _FadeIndexedStack extends StatefulWidget {
  const _FadeIndexedStack({required this.index, required this.children});

  final int index;
  final List<Widget> children;

  @override
  State<_FadeIndexedStack> createState() => _FadeIndexedStackState();
}

class _FadeIndexedStackState extends State<_FadeIndexedStack> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 350),
    value: 1,
  );

  @override
  void didUpdateWidget(_FadeIndexedStack old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index) _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween(begin: const Offset(0, 0.02), end: Offset.zero).animate(curved),
        child: IndexedStack(index: widget.index, children: widget.children),
      ),
    );
  }
}
