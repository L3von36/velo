import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app.dart';
import '../api/api.dart';
import '../models/models.dart';
import '../providers/session.dart';
import '../utils/format.dart';
import '../widgets/common.dart';
import 'catalog/catalog_screen.dart';
import 'pos/pos_screen.dart';
import 'reports/reports_hub.dart';

/// B1 owner/manager dashboard + B2 cashier variant (role decides content).
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
        title: Column(
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
        actions: [
          IconButton(
            tooltip: t(context).newSale,
            onPressed: () => _goToPos(),
            icon: const Icon(Icons.point_of_sale_rounded),
          ),
        ],
      ),
      body: isStaffRole ? _CashierHome(session: session) : _OwnerDashboard(session: session),
    );
  }

  void _goToPos() {
    // Shell nav is index-1 (Sell) — flip index via a simple route trick:
    // The shell owns the index; simplest robust approach: open POS full-screen.
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
          final cards = <Widget>[
            StatCard(
              label: t(context).todaySales,
              value: Money.etb(d.todayTotal),
              icon: Icons.today_rounded,
              trendPct: d.trendPct,
              money: true,
            ),
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
                color: const Color(0xFFB3261E),
              ),
          ];

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Quick actions (B1).
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => const PosScreen(standalone: true))),
                      icon: const Icon(Icons.bolt_rounded),
                      label: Text(t(context).newSale),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
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
              const SizedBox(height: 18),
              Text(t(context).todaySales, style: theme.textTheme.titleMedium),
              const SizedBox(height: 10),
              // Stat grid responsive: 2 cols mobile, 4 cols wide.
              GridView.count(
                crossAxisCount: width > 1000 ? 4 : 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: width > 1000 ? 2.4 : 1.7,
                children: cards,
              ),
              const SizedBox(height: 20),
              SectionHeader(t(context).topItemsToday),
              if (d.topItems.isEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(22),
                    child: Column(
                      children: [
                        Text(t(context).noSalesYet,
                            style: theme.textTheme.bodyLarge),
                        const SizedBox(height: 6),
                        Text(t(context).startSelling,
                            style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
                )
              else
                ...d.topItems.map((item) => Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor:
                              theme.colorScheme.primaryContainer,
                          child: Text(
                            '${d.topItems.indexOf(item) + 1}',
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: theme.colorScheme.primary),
                          ),
                        ),
                        title: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text('${_fmtQty(item.qty)} sold'),
                        trailing: MoneyText(item.revenue, bold: true),
                      ),
                    )),
              const SizedBox(height: 20),
              SectionHeader(t(context).lowStock),
              Card(
                child: ListTile(
                  enabled: d.lowStockCount > 0,
                  leading: Icon(
                    d.lowStockCount > 0
                        ? Icons.warning_amber_rounded
                        : Icons.check_circle_rounded,
                    color: d.lowStockCount > 0
                        ? const Color(0xFFB3261E)
                        : theme.colorScheme.primary,
                  ),
                  title: Text(d.lowStockCount > 0
                      ? '${d.lowStockCount} ${t(context).items.toLowerCase()} ${t(context).lowStock.toLowerCase()}'
                      : t(context).allStockedUp),
                  trailing: d.lowStockCount > 0
                      ? const Icon(Icons.chevron_right_rounded)
                      : null,
                  onTap: d.lowStockCount > 0
                      ? () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => CatalogScreen(
                                catalogLabel: t(context).lowStockList,
                                standalone: true,
                                lowStockOnly: true,
                              )))
                      : null,
                ),
              ),
              const SizedBox(height: 32),
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
                style: theme.textTheme.titleMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 20),
            // B2: the New Sale button front and center — the cashier's world.
            Material(
              color: theme.colorScheme.primary,
              borderRadius: BorderRadius.circular(24),
              child: InkWell(
                borderRadius: BorderRadius.circular(24),
                onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const PosScreen(standalone: true))),
                child: Container(
                  width: 220,
                  height: 220,
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.point_of_sale_rounded,
                          size: 64, color: Colors.white),
                      const SizedBox(height: 14),
                      Text(t(context).newSale,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleLarge?.copyWith(
                              color: Colors.white, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
