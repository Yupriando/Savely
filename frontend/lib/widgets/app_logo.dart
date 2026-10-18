import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Logo Savely: celengan dengan gradien emerald di dalam kotak putih membulat.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 96});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(size * 0.3),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: size * 0.3,
            offset: Offset(0, size * 0.1),
          ),
        ],
      ),
      child: ShaderMask(
        shaderCallback: (bounds) => AppColors.heroGradient.createShader(bounds),
        child: Icon(Icons.savings_rounded, size: size * 0.58, color: Colors.white),
      ),
    );
  }
}

/// Koin emas kecil (dipakai di animasi splash).
class GoldCoin extends StatelessWidget {
  const GoldCoin({super.key, this.size = 30});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: AppColors.goldGradient,
        border: Border.all(color: const Color(0xFFFDE68A), width: 2),
        boxShadow: [BoxShadow(color: AppColors.gold.withValues(alpha: 0.6), blurRadius: 12)],
      ),
      alignment: Alignment.center,
      child: Text(
        'Rp',
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: size * 0.34),
      ),
    );
  }
}
