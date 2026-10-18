import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme.dart';
import 'data/providers.dart';
import 'features/auth/auth_screen.dart';
import 'features/shell/main_shell.dart';
import 'features/splash/splash_screen.dart';
import 'widgets/common.dart';

class SavelyApp extends ConsumerWidget {
  const SavelyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'Savely',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ref.watch(themeModeProvider),
      themeAnimationDuration: const Duration(milliseconds: 400),
      locale: const Locale('id', 'ID'),
      supportedLocales: const [Locale('id', 'ID'), Locale('en', 'US')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const SplashScreen(),
    );
  }
}

/// Menampilkan halaman login atau aplikasi utama sesuai status login.
class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);

    // Logout / sesi habis: tutup semua halaman di atas (pengaturan, detail, sheet)
    ref.listen(authProvider, (prev, next) {
      if (prev?.valueOrNull != null && next.valueOrNull == null) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    });

    final Widget child = auth.when(
      skipLoadingOnReload: true,
      data: (user) => user == null
          ? const AuthScreen(key: ValueKey('auth'))
          : const MainShell(key: ValueKey('shell')),
      loading: () => const Scaffold(
        key: ValueKey('loading'),
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        key: const ValueKey('error'),
        body: Center(
          child: ErrorView(error: e, onRetry: () => ref.invalidate(authProvider)),
        ),
      ),
    );

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 500),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: ScaleTransition(
          scale: Tween(begin: 0.96, end: 1.0).animate(anim),
          child: child,
        ),
      ),
      child: child,
    );
  }
}
