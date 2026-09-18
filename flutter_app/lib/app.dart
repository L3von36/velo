import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'l10n/app_localizations.dart';
import 'providers/session.dart';
import 'screens/language_screen.dart';
import 'screens/login_screen.dart';
import 'screens/onboarding/onboarding_wizard.dart';
import 'screens/shell/home_shell.dart';
import 'widgets/common.dart';

/// Routes by session phase (A1 splash behavior: instant, no network wait).
class RootRouter extends ConsumerWidget {
  const RootRouter({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);

    return session.when(
      loading: () => const _Splash(),
      error: (e, _) => const _Splash(),
      data: (s) {
        switch (s.phase) {
          case AppPhase.language:
            return const LanguageScreen();
          case AppPhase.loggedOut:
            return const LoginScreen();
          case AppPhase.onboarding:
            return const OnboardingWizard();
          case AppPhase.ready:
            return const HomeShell();
          case AppPhase.boot:
            return const _Splash();
        }
      },
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFF2FBF5), Color(0xFFE8F5EC)],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF0E7A3D).withValues(alpha: 0.18),
                      blurRadius: 30,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: const BrandMark(size: 84, radius: 24),
              ),
              const SizedBox(height: 18),
              Text('Velo',
                  style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800, letterSpacing: -0.8)),
              const SizedBox(height: 4),
              Text(t(context).tagline,
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant)),
              const SizedBox(height: 28),
              SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(
                    strokeWidth: 2.5, color: theme.colorScheme.primary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small helper — localized strings shortcut.
AppLocalizations t(BuildContext context) => AppLocalizations.of(context);
