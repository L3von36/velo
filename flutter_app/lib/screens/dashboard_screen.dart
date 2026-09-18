import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app.dart';
import '../api/api.dart';
import '../models/models.dart';
import '../providers/session.dart';
import '../theme/app_theme.dart' show AppTheme;
import '../utils/format.dart';
import '../widgets/common.dart';
import 'catalog/catalog_screen.dart';
import 'pos/pos_screen.dart';
import 'reports/reports_hub.dart';

/// B1 owner/manager dashboard + B2 cashier variant (role decides content).
/// v2: hero KPI gradient card, refined stat grid, ranked best-sellers.
class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.invalidate(dashboardDataProvider);
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider).value;
    final isStaffRole = session?.user?.role == 'cashier' || session?.user?.role == 'staff';

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const BrandMark(size: 40, radius: 12),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(session?.tenant?.name ?? 'Velo',
                    style: Theme.of(context).textTheme.titleMedium),
                Text(
                  '${session?.user?.name ?? ''} · ${session?.user?.role ?? ''}',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: t(context).newSale,
            onPressed: () => _goToPos(),
            icon: const Icon(Icons.point_of_sale_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: isStaffRole ? _CashierHome(session: session) : _OwnerDashboard(session: session),
    );
  }

  void _goToPos() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const PosScreen(standalone: true)),
    );
  }
}

// ---------------------------------------------------------------- data
final dashboardDataProvider =
    FutureProvider.autoDispose<DashboardData>((ref) => Api().dashboard());

// ---------------------------------------------------------------- owner
class _OwnerDashboard extends ConsumerWidget {
  const _OwnerDashboard({required this.session});
  final SessionState? session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionAsync = ref.watch(sessionProvider);
    final data = ref.watch(dashboardDataProvider);
    final width = MediaQuery.of(context).size.width;
    final theme = Theme.of(context);
    final canViewReports = session?.canViewReports ?? false;

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(dashboardDataProvider),
      child: data.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorRetry(message: '$e', onRetry: () => ref.invalidate(dashboardDataProvider)),
        data: (d) {
          final statCards = <Widget>[
            StatCard(
              label: t(context).weekSales,
              value: Money.etb(d.weekTotal),
              icon: Icons.date_range_rounded,
            ),
            if (d.todayCount > 0 || d.todayTotal == 0)
              StatCard(
                label: t(context).transactions,
                value: '${d.todayCount}',
                icon: Icons.receipt_rounded,
              ),
            if (d.lowStockCount > 0)
              StatCard(
                label: t(context).lowStock,
                value: '${d.lowStockCount}',
                icon: Icons.warning_amber_rounded,
                color: AppTheme.danger,
              ),
          ];

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              // ── Hero KPI — today's sales on the brand gradient. ────────
              KpiHeroCard(
                title: t(context).todaySales,
                value: Money.etb(d.todayTotal),
                trendPct: d.trendPct,
                subtitle:
                    '${d.todayCount} ${t(context).transactions.toLowerCase()}',
                icon: Icons.today_rounded,
                onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const ReportsHub(standalone: true))),
              ),
              const SizedBox(height: 14),

              // ── Quick actions (B1). ────────────────────────────────────
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => const PosScreen(standalone: true))),
                      icon: const Icon(Icons.bolt_rounded),
                      label: Text(t(context).newSale),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => CatalogScreen(
                                catalogLabel:
                                    sessionAsync.value?.tenant?.config.catalogLabel ?? 'Catalog',
                                standalone: true,
                              ))),
                      icon: const Icon(Icons.add_business_rounded),
                      label: Text(t(context).addItem),
                    ),
                  ),
                  if (canViewReports && width > 480) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: OutlinedButton.icon(
                        onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const ReportsHub(standalone: true))),
                        icon: const Icon(Icons.insights_rounded),
                        label: Text(t(context).viewReports),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 20),

              // ── Secondary stats — 2 cols mobile, 3 cols wide. ──────────
              GridView.count(
                crossAxisCount: width > 1000 ? 3 : 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: width > 1000 ? 2.6 : 1.75,
                children: statCards,
              ),
              const SizedBox(height: 22),
              SectionHeader(t(context).topItemsToday),
              if (d.topItems.isEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        Icon(Icons.storefront_rounded,
                            size: 34, color: theme.colorScheme.outline),
                        const SizedBox(height: 10),
                        Text(t(context).noSalesYet,
                            style: theme.textTheme.titleSmall),
                        const SizedBox(height: 4),
                        Text(t(context).startSelling,
                            style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
                )
              else
                Card(
                  child: Column(
                    children: [
                      for (var i = 0; i < d.topItems.length; i++) ...[
                        if (i > 0)
                          Divider(
                              height: 1,
                              indent: 66,
                              color: theme.colorScheme.outlineVariant
                                  .withValues(alpha: 0.4)),
                        ListTile(
                          leading: RankBadge(rank: i + 1),
                          title: Text(d.topItems[i].name,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(
                              '${_fmtQty(d.topItems[i].qty)} sold'),
                          trailing: MoneyText(d.topItems[i].revenue, bold: true),
                        ),
                      ],
                    ],
                  ),
                ),
              const SizedBox(height: 22),
              SectionHeader(t(context).lowStock),
              PressableCard(
                onTap: d.lowStockCount > 0
                    ? () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => CatalogScreen(
                              catalogLabel: t(context).lowStockList,
                              standalone: true,
                              lowStockOnly: true,
                            )))
                    : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Builder(builder: (context) {
                    final theme = Theme.of(context);
                    final ok = d.lowStockCount == 0;
                    final c = ok ? AppTheme.success : AppTheme.warning;
                    return Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: c.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            ok ? Icons.check_circle_rounded : Icons.warning_amber_rounded,
                            color: c,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            ok
                                ? t(context).allStockedUp
                                : '${d.lowStockCount} ${t(context).items.toLowerCase()} ${t(context).lowStock.toLowerCase()}',
                            style: theme.textTheme.bodyLarge
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                        if (!ok)
                          Icon(Icons.chevron_right_rounded,
                              color: theme.colorScheme.onSurfaceVariant),
                      ],
                    );
                  }),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  String _fmtQty(double q) => q == q.roundToDouble() ? '${q.toInt()}' : '$q';
}

// ---------------------------------------------------------------- cashier
class _CashierHome extends StatelessWidget {
  const _CashierHome({required this.session});
  final SessionState? session;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(t(context).quickActions,
                style: theme.textTheme.titleSmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 20),
            // B2: the New Sale button front and center — the cashier's world.
            InkWell(
              borderRadius: BorderRadius.circular(28),
              onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const PosScreen(standalone: true))),
              child: Ink(
                width: 230,
                height: 230,
                decoration: const BoxDecoration(
                  gradient: AppTheme.heroGradient,
                  borderRadius: BorderRadius.all(Radius.circular(28)),
                  boxShadow: [
                    BoxShadow(
                        color: Color(0x330E7A3D),
                        blurRadius: 20,
                        offset: Offset(0, 8)),
                  ],
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 74,
                      height: 74,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.16),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.point_of_sale_rounded,
                          size: 40, color: Colors.white),
                    ),
                    const SizedBox(height: 16),
                    Text(t(context).newSale,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleLarge?.copyWith(
                            color: Colors.white, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
