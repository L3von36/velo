import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'l10n/app_localizations.dart';
import 'providers/session.dart';
import 'screens/language_screen.dart';
import 'screens/login_screen.dart';
import 'screens/onboarding/onboarding_wizard.dart';
import 'screens/shell/home_shell.dart';
import 'theme/app_theme.dart';

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
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppTheme.seed,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(Icons.storefront_rounded, color: Colors.white, size: 40),
            ),
            const SizedBox(height: 16),
            Text(
              'Velo',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 24),
            const SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
          ],
        ),
      ),
    );
  }
}

/// Small helper — localized strings shortcut.
AppLocalizations t(BuildContext context) => AppLocalizations.of(context);
