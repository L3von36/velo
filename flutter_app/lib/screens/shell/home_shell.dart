import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app.dart';
import '../../providers/session.dart';
import '../../providers/shop.dart';
import '../../theme/app_theme.dart' show AppTheme;
import '../../widgets/common.dart';
import '../dashboard_screen.dart';
import '../pos/pos_screen.dart';
import '../catalog/catalog_screen.dart';
import '../customers/customers_screen.dart';
import '../reports/reports_hub.dart';
import '../staff/staff_screen.dart';
import '../expenses/expenses_screen.dart';
import '../settings/settings_screen.dart';

/// Adaptive navigation shell (PRD UI/UX):
///  - < 600dp: NavigationBar bottom, 4 direct destinations + "More" sheet
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

  /// Instagram-style "More" sheet: the destinations that don't fit in the
  /// bottom bar (Reports, Expenses, Staff, Settings) live here. Each entry
  /// carries its absolute destination index, resolved at open time so late
  /// rebuilds can never desync the lookup.
  void _openMoreSheet(List<MapEntry<int, _Dest>> overflow) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetCtx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 14, top: 2, bottom: 10),
                child: Text(t(context).more,
                    style: theme.textTheme.titleLarge),
              ),
              for (final entry in overflow)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Material(
                    color: Colors.transparent,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () {
                        Navigator.of(sheetCtx).pop();
                        setState(() => _index = entry.key);
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                        child: Row(
                          children: [
                            Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                color: entry.key == _index
                                    ? scheme.primaryContainer
                                    : scheme.surfaceContainerHigh,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(entry.value.icon,
                                  size: 21,
                                  color: entry.key == _index
                                      ? scheme.onPrimaryContainer
                                      : scheme.onSurfaceVariant),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Text(entry.value.label,
                                  style: theme.textTheme.titleMedium),
                            ),
                            if (entry.key == _index)
                              Icon(Icons.check_circle_rounded,
                                  size: 18, color: scheme.primary)
                            else
                              Icon(Icons.chevron_right_rounded,
                                  size: 20, color: scheme.onSurfaceVariant),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
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
            color: AppTheme.warning,
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
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          )
        : const SizedBox.shrink();

    if (width < 600) {
      // Mobile bottom nav: 4 direct destinations + "More" overflow menu
      // (Instagram pattern) so every screen stays reachable on small phones.
      const directCount = 4;
      final direct = destinations.take(directCount).toList();
      final overflow = <MapEntry<int, _Dest>>[
        for (var i = directCount; i < destinations.length; i++)
          MapEntry(i, destinations[i]),
      ];
      final hasMore = overflow.isNotEmpty;
      return Scaffold(
        body: Column(
          children: [
            offlineBanner,
            Expanded(child: body),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index < directCount ? _index : directCount,
          onDestinationSelected: (i) {
            if (i < directCount) {
              setState(() => _index = i);
            } else if (hasMore) {
              _openMoreSheet(overflow);
            }
          },
          destinations: [
            ...direct.map((d) => NavigationDestination(
                  icon: Icon(d.icon),
                  selectedIcon: Icon(d.icon, fill: 1),
                  label: d.label,
                )),
            if (hasMore)
              NavigationDestination(
                icon: const Icon(Icons.apps_rounded),
                selectedIcon: const Icon(Icons.apps_rounded, fill: 1),
                label: t(context).more,
              ),
          ],
        ),
      );
    }

    // Tablet & desktop: rail / sidebar with branded extended header.
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
                    padding: const EdgeInsets.only(top: 16, bottom: 14),
                    child: extended
                        ? Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Row(
                              children: [
                                const BrandMark(size: 40, radius: 12),
                                const SizedBox(width: 10),
                                Text('Velo',
                                    style: theme.textTheme.titleLarge?.copyWith(
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: -0.4)),
                              ],
                            ),
                          )
                        : const Center(child: BrandMark(size: 40, radius: 12)),
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
