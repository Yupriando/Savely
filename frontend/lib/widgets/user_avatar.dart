import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../data/models.dart';

/// Foto profil bulat. Tanpa foto -> inisial nama di atas gradien hijau.
/// Saat foto berganti, transisinya memudar dan membesar halus.
class UserAvatar extends StatelessWidget {
  const UserAvatar({super.key, required this.user, this.size = 48});

  final AppUser? user;
  final double size;

  @override
  Widget build(BuildContext context) {
    final url = user?.avatarUrl;
    final initial = Center(
      key: ValueKey('initial-${user?.initial}'),
      child: Text(
        user?.initial ?? '?',
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: size * 0.4),
      ),
    );

    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(gradient: AppColors.heroGradient, shape: BoxShape.circle),
      clipBehavior: Clip.antiAlias,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 450),
        transitionBuilder: (child, anim) => FadeTransition(
          opacity: anim,
          child: ScaleTransition(scale: Tween(begin: 1.15, end: 1.0).animate(anim), child: child),
        ),
        child: url == null
            ? initial
            : Image.network(
                url,
                key: ValueKey(url),
                width: size,
                height: size,
                fit: BoxFit.cover,
                // Foto muncul memudar setelah selesai diunduh
                frameBuilder: (context, child, frame, wasSync) => wasSync
                    ? child
                    : AnimatedOpacity(
                        opacity: frame == null ? 0 : 1,
                        duration: const Duration(milliseconds: 400),
                        child: child,
                      ),
                errorBuilder: (_, _, _) => initial,
              ),
      ),
    );
  }
}
