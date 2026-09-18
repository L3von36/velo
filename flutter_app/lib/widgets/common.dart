import 'package:flutter/material.dart';

import '../theme/app_theme.dart' show AppTheme, VeloShadows;
import '../utils/format.dart';

/// ─────────────────────────────────────────────────────────────────────────
/// Velo shared widget library — v2 "Emerald Pro".
/// ─────────────────────────────────────────────────────────────────────────

/// Brand logo mark: rounded-square with Velo gradient + storefront bolt.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 48, this.radius});
  final double size;
  final double? radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: AppTheme.heroGradient,
        borderRadius: BorderRadius.circular(radius ?? size * 0.30),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0E7A3D).withValues(alpha: 0.35),
            blurRadius: size * 0.4,
            offset: Offset(0, size * 0.10),
          ),
        ],
      ),
      child: Icon(Icons.storefront_rounded, color: Colors.white, size: size * 0.55),
    );
  }
}

/// Stat card v2 — tonal icon chip, strong value hierarchy, trend pill.
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
    final soft = color?.withValues(alpha: 0.12) ??
        theme.colorScheme.primary.withValues(alpha: 0.10);

    return PressableCard(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                if (icon != null)
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: soft,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Icon(icon, size: 17, color: c),
                  ),
                if (icon != null) const SizedBox(width: 8),
                Expanded(
                  child: Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Text(value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800, letterSpacing: -0.5)),
                ),
                if (trendPct != null) ...[
                  const SizedBox(width: 6),
                  _TrendPill(pct: trendPct!),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Small green/red % trend chip.
class _TrendPill extends StatelessWidget {
  const _TrendPill({required this.pct});
  final double pct;

  @override
  Widget build(BuildContext context) {
    final up = pct >= 0;
    final c = up ? AppTheme.success : AppTheme.danger;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(up ? Icons.trending_up_rounded : Icons.trending_down_rounded,
              size: 12, color: c),
          const SizedBox(width: 3),
          Text('${pct.abs().toStringAsFixed(0)}%',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: c, fontWeight: FontWeight.w700, fontSize: 10.5)),
        ],
      ),
    );
  }
}

/// Gradient hero KPI card — used for "today's sales" headline metric.
class KpiHeroCard extends StatelessWidget {
  const KpiHeroCard({
    super.key,
    required this.title,
    required this.value,
    this.subtitle,
    this.trendPct,
    this.icon = Icons.today_rounded,
    this.onTap,
  });

  final String title;
  final String value;
  final String? subtitle;
  final double? trendPct;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final up = (trendPct ?? 0) >= 0;
    return PressableCard(
      onTap: onTap,
      radius: AppTheme.rLg,
      gradient: AppTheme.heroGradient,
      shadow: const BoxShadow(
        color: Color(0x330E7A3D),
        blurRadius: 18,
        offset: Offset(0, 6),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: 19, color: Colors.white),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(title,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: Colors.white.withValues(alpha: 0.92),
                          fontWeight: FontWeight.w600)),
                ),
                if (trendPct != null)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                            up
                                ? Icons.trending_up_rounded
                                : Icons.trending_down_rounded,
                            size: 13,
                            color: Colors.white),
                        const SizedBox(width: 3),
                        Text('${trendPct!.abs().toStringAsFixed(0)}%',
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800)),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Text(value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context)
                    .textTheme
                    .headlineMedium
                    ?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.8)),
            if (subtitle != null) ...[
              const SizedBox(height: 3),
              Text(subtitle!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.white.withValues(alpha: 0.75))),
            ],
          ],
        ),
      ),
    );
  }
}

/// Pressable card with optional gradient — unifies tap states.
class PressableCard extends StatelessWidget {
  const PressableCard({
    super.key,
    required this.child,
    this.onTap,
    this.radius = AppTheme.rMd,
    this.gradient,
    this.shadow,
  });

  final Widget child;
  final VoidCallback? onTap;
  final double radius;
  final Gradient? gradient;
  final BoxShadow? shadow;

  @override
  Widget build(BuildContext context) {
    final shadows = Theme.of(context).extension<VeloShadows>();
    final shape =
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius));
    return Card(
      elevation: 0,
      color: Colors.transparent,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            gradient: gradient,
            color:
                gradient == null ? Theme.of(context).colorScheme.surfaceContainerLowest : null,
            borderRadius: BorderRadius.circular(radius),
            border: gradient == null
                ? Border.all(
                    color: Theme.of(context)
                        .colorScheme
                        .outlineVariant
                        .withValues(alpha: 0.55))
                : null,
            boxShadow: [shadow ?? shadows?.card ?? const BoxShadow()],
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Empty state v2 — duotone tonal circle, softer copy hierarchy.
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
            Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.07),
                    shape: BoxShape.circle,
                  ),
                ),
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 30, color: theme.colorScheme.primary),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Text(title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(subtitle!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ],
            if (actionLabel != null) ...[
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.add_rounded, size: 20),
                label: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Error + retry state.
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
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: theme.colorScheme.error.withValues(alpha: 0.09),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.cloud_off_rounded, size: 30,
                  color: theme.colorScheme.error),
            ),
            const SizedBox(height: 14),
            Text(message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
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
            child: Text(title,
                style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    letterSpacing: 0.3,
                    fontWeight: FontWeight.w700)),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Rank badge for "top items" lists — gold / silver / bronze.
class RankBadge extends StatelessWidget {
  const RankBadge({super.key, required this.rank});
  final int rank;

  @override
  Widget build(BuildContext context) {
    const colors = [Color(0xFFE8A200), Color(0xFF8E9AA6), Color(0xFFB0713A)];
    final c = rank <= 3 ? colors[rank - 1] : Theme.of(context).colorScheme.outline;
    return CircleAvatar(
      radius: 14,
      backgroundColor: c.withValues(alpha: 0.14),
      child: Text('$rank',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: c, fontWeight: FontWeight.w800, fontSize: 12)),
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
      return const Color(0xFF16803C);
    case 'telebirr':
      return const Color(0xFFB3261E);
    case 'cbe':
      return const Color(0xFF6A4BA1);
    case 'credit':
      return const Color(0xFFE8A200);
  }
  return Colors.grey;
}
