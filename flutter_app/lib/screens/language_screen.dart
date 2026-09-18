import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app.dart';
import '../providers/session.dart';
import '../theme/app_theme.dart' show AppTheme;
import '../widgets/common.dart';

/// A2 — language select. Stored locally, no account needed (PRD rule).
class LanguageScreen extends ConsumerStatefulWidget {
  const LanguageScreen({super.key});

  @override
  ConsumerState<LanguageScreen> createState() => _LanguageScreenState();
}

class _LanguageScreenState extends ConsumerState<LanguageScreen> {
  String? _selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFF2FBF5), Color(0xFFF7FAF6)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Center(child: BrandMark(size: 64, radius: 18)),
                    const SizedBox(height: 20),
                    Text(
                      'Velo',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w800, letterSpacing: -0.8),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      t(context).languageSelectTitle,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 24),
                    _LanguageCard(
                      title: 'አማርኛ',
                      subtitle: 'ዋና ቋንቋ',
                      flagEmoji: '🇪🇹',
                      selected: _selected == 'am',
                      onTap: () => setState(() => _selected = 'am'),
                    ),
                    const SizedBox(height: 12),
                    _LanguageCard(
                      title: 'English',
                      subtitle: 'International',
                      flagEmoji: '🌍',
                      selected: _selected == 'en',
                      onTap: () => setState(() => _selected = 'en'),
                    ),
                    const SizedBox(height: 26),
                    FilledButton(
                      onPressed: _selected == null
                          ? null
                          : () async {
                              await ref
                                  .read(sessionProvider.notifier)
                                  .setLanguage(_selected!);
                              if (context.mounted) {
                                ref.invalidate(sessionProvider);
                              }
                            },
                      child: Text(t(context).continueLabel),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LanguageCard extends StatelessWidget {
  const _LanguageCard({
    required this.title,
    required this.subtitle,
    required this.flagEmoji,
    required this.selected,
    required this.onTap,
  });

  final String title, subtitle, flagEmoji;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: selected
          ? theme.colorScheme.primaryContainer.withValues(alpha: 0.55)
          : theme.colorScheme.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(AppTheme.rMd),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.rMd),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.rMd),
            border: Border.all(
              color: selected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outlineVariant,
              width: selected ? 1.8 : 1,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                        color: theme.colorScheme.primary.withValues(alpha: 0.12),
                        blurRadius: 14,
                        offset: const Offset(0, 4))
                  ]
                : null,
          ),
          child: Row(
            children: [
              Text(flagEmoji, style: const TextStyle(fontSize: 30)),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: theme.textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    Text(subtitle, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected
                      ? theme.colorScheme.primary
                      : Colors.transparent,
                  border: selected
                      ? null
                      : Border.all(
                          color: theme.colorScheme.outlineVariant, width: 1.6),
                ),
                child: selected
                    ? Icon(Icons.check_rounded,
                        size: 17, color: theme.colorScheme.onPrimary)
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
