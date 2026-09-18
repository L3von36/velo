import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app.dart';
import '../providers/session.dart';

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
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.language_rounded,
                      size: 44, color: theme.colorScheme.primary),
                  const SizedBox(height: 12),
                  Text(
                    t(context).languageSelectTitle,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 28),
                  _LanguageCard(
                    title: 'አማርኛ',
                    subtitle: 'ዋና ቋንቋ',
                    flagEmoji: '🇪🇹',
                    selected: _selected == 'am',
                    onTap: () => setState(() => _selected = 'am'),
                  ),
                  const SizedBox(height: 14),
                  _LanguageCard(
                    title: 'English',
                    subtitle: 'International',
                    flagEmoji: '🌍',
                    selected: _selected == 'en',
                    onTap: () => setState(() => _selected = 'en'),
                  ),
                  const SizedBox(height: 28),
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
          ? theme.colorScheme.primaryContainer
          : theme.colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outlineVariant,
              width: selected ? 2 : 1,
            ),
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
              if (selected)
                Icon(Icons.check_circle_rounded, color: theme.colorScheme.primary),
            ],
          ),
        ),
      ),
    );
  }
}
