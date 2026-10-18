import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app.dart';
import '../../core/theme.dart';
import '../../data/providers.dart';
import '../../widgets/app_logo.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  static const _name = 'Savely';

  @override
  void initState() {
    super.initState();
    _start();
  }

  /// Tunggu animasi selesai DAN cek login selesai, baru pindah halaman.
  Future<void> _start() async {
    await Future.wait([
      Future<void>.delayed(const Duration(milliseconds: 2800)),
      ref.read(authProvider.future).then((_) {}, onError: (_) {}),
    ]);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 700),
        pageBuilder: (_, _, _) => const AuthGate(),
        transitionsBuilder: (_, anim, _, child) {
          final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
          return FadeTransition(
            opacity: curved,
            child: ScaleTransition(scale: Tween(begin: 1.08, end: 1.0).animate(curved), child: child),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF022C22), AppColors.forest, AppColors.emeraldDeep],
            ),
          ),
          child: Stack(
            children: [
              // Cahaya lembut di sudut, berdenyut pelan
              Positioned(
                top: -120,
                right: -100,
                child: _Glow(size: 320, color: AppColors.emerald.withValues(alpha: 0.45)),
              ),
              Positioned(
                bottom: -140,
                left: -120,
                child: _Glow(size: 360, color: AppColors.gold.withValues(alpha: 0.22)),
              ),
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(width: 240, height: 240, child: _AnimatedLogo()),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (var i = 0; i < _name.length; i++)
                          Text(
                                _name[i],
                                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1,
                                ),
                              )
                              .animate(delay: (1300 + i * 70).ms)
                              .fadeIn(duration: 300.ms)
                              .moveY(begin: 24, end: 0, curve: Curves.easeOutBack, duration: 500.ms),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                          'Atur uangmu, wujudkan impianmu',
                          style: Theme.of(
                            context,
                          ).textTheme.bodyLarge?.copyWith(color: Colors.white.withValues(alpha: 0.8)),
                        )
                        .animate(delay: 1900.ms)
                        .fadeIn(duration: 500.ms)
                        .moveY(begin: 10, end: 0, curve: Curves.easeOut),
                  ],
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 56,
                child: const _LoadingDots().animate(delay: 2100.ms).fadeIn(duration: 400.ms),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AnimatedLogo extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        // Gelombang cincin yang memancar keluar
        for (var i = 0; i < 3; i++)
          Container(
                width: 200,
                height: 200,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white.withValues(alpha: 0.25), width: 2),
                ),
              )
              .animate(delay: (600 + i * 500).ms, onPlay: (c) => c.repeat())
              .scaleXY(begin: 0.45, end: 1.25, duration: 1800.ms, curve: Curves.easeOut)
              .fadeOut(begin: 1, duration: 1800.ms),

        // Logo muncul memantul, lalu "menelan" koin dan berkilau
        const AppLogo(size: 110)
            .animate()
            .fadeIn(duration: 300.ms)
            .scaleXY(begin: 0.2, end: 1, duration: 900.ms, curve: Curves.elasticOut)
            .then(delay: 350.ms)
            .scaleXY(begin: 1, end: 1.12, duration: 140.ms, curve: Curves.easeOut)
            .then()
            .scaleXY(begin: 1, end: 1 / 1.12, duration: 260.ms, curve: Curves.easeOutBack)
            .then()
            .shimmer(duration: 1100.ms, color: AppColors.mint.withValues(alpha: 0.7)),

        // Koin jatuh dari atas ke dalam celengan
        Positioned(
          top: 72,
          left: 0,
          right: 0,
          child: Center(
            child: const GoldCoin(size: 34)
                .animate(delay: 700.ms)
                .fadeIn(duration: 150.ms)
                .moveY(begin: -110, end: 0, duration: 550.ms, curve: Curves.easeInCubic)
                .then()
                .scaleXY(begin: 1, end: 0.3, duration: 150.ms)
                .fadeOut(duration: 150.ms),
          ),
        ),
      ],
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
          ),
        )
        .animate(onPlay: (c) => c.repeat(reverse: true))
        .scaleXY(begin: 0.85, end: 1.1, duration: 2400.ms, curve: Curves.easeInOut);
  }
}

class _LoadingDots extends StatelessWidget {
  const _LoadingDots();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < 3; i++)
          Container(
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.85),
                  shape: BoxShape.circle,
                ),
              )
              .animate(delay: (i * 160).ms, onPlay: (c) => c.repeat(reverse: true))
              .moveY(begin: 0, end: -8, duration: 420.ms, curve: Curves.easeInOut)
              .fade(begin: 0.4, end: 1, duration: 420.ms),
      ],
    );
  }
}
