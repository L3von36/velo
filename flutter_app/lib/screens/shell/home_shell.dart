import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app.dart';
import '../../providers/session.dart';
import '../../providers/shop.dart';
import '../dashboard_screen.dart';
import '../pos/pos_screen.dart';
import '../catalog/catalog_screen.dart';
import '../customers/customers_screen.dart';
import '../reports/reports_hub.dart';
import '../staff/staff_screen.dart';
import '../expenses/expenses_screen.dart';
import '../settings/settings_screen.dart';

/// Adaptive navigation shell (PRD UI/UX):
///  - < 600dp: NavigationBar bottom, 5 top-level destinations
///  - 600–1024dp: NavigationRail
///  - > 1024dp: persistent sidebar rail with extended labels
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _index = 0;
  bool _listening = false;

  @override
  void initState() {
    super.initState();
    _initConnectivity();
  }

  Future<void> _initConnectivity() async {
    if (_listening) return;
    _listening = true;
    try {
      Connectivity().onConnectivityChanged.listen((results) {
        final offline =
            results.isEmpty || results.every((r) => r == ConnectivityResult.none);
        ref.read(onlineProvider.notifier).setOnline(!offline);
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider).value;
    final tenant = session?.tenant;
    final online = ref.watch(onlineProvider);
    final width = MediaQuery.of(context).size.width;

    final catalogLabel = tenant?.config.catalogLabel ?? t(context).catalog;

    final destinations = <_Dest>[
      _Dest(Icons.dashboard_rounded, t(context).home,
          const DashboardScreen(), session?.isOwnerOrManager == true),
      _Dest(Icons.point_of_sale_rounded, t(context).sell,
          const PosScreen(), true),
      _Dest(Icons.inventory_2_rounded, catalogLabel,
          CatalogScreen(catalogLabel: catalogLabel), true),
      _Dest(Icons.people_alt_rounded, t(context).customers,
          const CustomersScreen(), true),
      _Dest(Icons.insights_rounded, t(context).reports,
          const ReportsHub(), session?.canViewReports ?? false),
      _Dest(Icons.receipt_long_rounded, t(context).expenses,
          const ExpensesScreen(), session?.canManageExpenses ?? false),
      _Dest(Icons.badge_rounded, t(context).staff,
          const StaffScreen(), session?.canManageStaff ?? false),
      _Dest(Icons.settings_rounded, t(context).settings,
          const SettingsScreen(), true),
    ].where((d) => d.visible).toList();

    if (_index >= destinations.length) _index = destinations.length - 1;
    final body = destinations[_index].screen;

    final offlineBanner = !online
        ? Material(
            color: const Color(0xFF8A4B00),
            child: SafeArea(
              bottom: false,
              child: SizedBox(
                width: double.infinity,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.cloud_off_rounded, size: 14, color: Colors.white),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(t(context).offlineBanner,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white, fontSize: 12)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          )
        : const SizedBox.shrink();

    if (width < 600) {
      return Scaffold(
        body: Column(
          children: [
            offlineBanner,
            Expanded(child: body),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          destinations: destinations
              .take(5)
              .map((d) => NavigationDestination(
                    icon: Icon(d.icon),
                    selectedIcon: Icon(d.icon, fill: 1),
                    label: d.label,
                  ))
              .toList(),
        ),
      );
    }

    // Tablet & desktop: rail / sidebar.
    final extended = width > 1024;
    final theme = Theme.of(context);
    return Scaffold(
      body: Column(
        children: [
          offlineBanner,
          Expanded(
            child: Row(
              children: [
                NavigationRail(
                  extended: extended,
                  minExtendedWidth: 210,
                  selectedIndex: _index,
                  onDestinationSelected: (i) => setState(() => _index = i),
                  leading: Padding(
                    padding: const EdgeInsets.only(top: 14, bottom: 10),
                    child: Container(
                      width: 44,
                      height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary,
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: const Icon(Icons.storefront_rounded, color: Colors.white, size: 24),
                    ),
                  ),
                  destinations: destinations
                      .map((d) => NavigationRailDestination(
                            icon: Icon(d.icon),
                            selectedIcon: Icon(d.icon, fill: 1),
                            label: Text(d.label),
                          ))
                      .toList(),
                ),
                VerticalDivider(
                    width: 1, thickness: 1, color: theme.colorScheme.outlineVariant),
                Expanded(child: body),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Dest {
  const _Dest(this.icon, this.label, this.screen, this.visible);
  final IconData icon;
  final String label;
  final Widget screen;
  final bool visible;
}
