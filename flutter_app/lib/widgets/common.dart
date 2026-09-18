import 'package:flutter/material.dart';

import '../utils/format.dart';

/// Stat card used across dashboard & reports (B1/J1).
class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.label,
    required this.value,
    this.icon,
    this.trendPct,
    this.color,
    this.money = false,
    this.onTap,
  });

  final String label;
  final String value;
  final IconData? icon;
  final double? trendPct;
  final Color? color;
  final bool money;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = color ?? theme.colorScheme.primary;
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 18, color: c),
                    const SizedBox(width: 6),
                  ],
                  Expanded(
                    child: Text(label,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelMedium
                            ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w800)),
              if (trendPct != null) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      trendPct! >= 0
                          ? Icons.trending_up_rounded
                          : Icons.trending_down_rounded,
                      size: 14,
                      color: trendPct! >= 0 ? const Color(0xFF0E7A3D) : const Color(0xFFB3261E),
                    ),
                    const SizedBox(width: 4),
                    Text('${trendPct!.abs().toStringAsFixed(0)}%',
                        style: theme.textTheme.labelSmall),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// L3 — generic empty state: icon + message + primary action.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHigh,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 40, color: theme.colorScheme.outline),
            ),
            const SizedBox(height: 18),
            Text(title,
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(subtitle!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ],
            if (actionLabel != null) ...[
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.add_rounded),
                label: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// L4 — error + retry state.
class ErrorRetry extends StatelessWidget {
  const ErrorRetry({super.key, required this.message, this.onRetry});
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, size: 44, color: theme.colorScheme.error),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Money text with muted symbol styling.
class MoneyText extends StatelessWidget {
  const MoneyText(this.amount,
      {super.key, this.style, this.bold = false, this.color});
  final double amount;
  final TextStyle? style;
  final bool bold;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      Money.etb(amount),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: (style ?? theme.textTheme.bodyMedium)?.copyWith(
        fontWeight: bold ? FontWeight.w700 : null,
        color: color,
      ),
    );
  }
}

/// Section header for grouped lists.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.trailing});
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(title.toUpperCase(),
                style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    letterSpacing: 0.8,
                    fontWeight: FontWeight.w600)),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Payment method icon mapping — recognizable local methods (PRD §2 UX).
IconData paymentIcon(String method) {
  switch (method) {
    case 'cash':
      return Icons.payments_rounded;
    case 'telebirr':
      return Icons.phone_android_rounded;
    case 'cbe':
      return Icons.account_balance_rounded;
    case 'credit':
      return Icons.receipt_rounded;
  }
  return Icons.payment_rounded;
}

Color paymentColor(String method) {
  switch (method) {
    case 'cash':
      return const Color(0xFF0E7A3D);
    case 'telebirr':
      return const Color(0xFFB3261E);
    case 'cbe':
      return const Color(0xFF6A4BA1);
    case 'credit':
      return const Color(0xFFE8A200);
  }
  return Colors.grey;
}
