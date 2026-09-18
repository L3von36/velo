import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'config/supabase_config.dart';
import 'l10n/app_localizations.dart';
import 'providers/session.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: SupabaseConfig.url,
    publishableKey: SupabaseConfig.anonKey,
  );
  runApp(const ProviderScope(child: VeloApp()));
}

class VeloApp extends ConsumerWidget {
  const VeloApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(localeProvider);
    final dark = ref.watch(darkModeProvider);

    // restore theme once
    ref.read(darkModeProvider.notifier).restore();

    return MaterialApp(
      title: 'Velo',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      locale: Locale(lang),
      supportedLocales: const [Locale('en'), Locale('am')],
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: const RootRouter(),
    );
  }
}
