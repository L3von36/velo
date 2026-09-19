import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app.dart';
import '../../api/api.dart';
import '../../models/models.dart';
import '../../utils/format.dart';
import '../../widgets/common.dart';

/// J1–J5 — reports hub with date-range tabs and inline charts.
class ReportsHub extends ConsumerStatefulWidget {
  const ReportsHub({super.key, this.standalone = false});
  final bool standalone;

  @override
  ConsumerState<ReportsHub> createState() => _ReportsHubState();
}

enum _Range { week, month, custom }

class _ReportsHubState extends ConsumerState<ReportsHub> {
  _Range _range = _Range.month;

  (DateTime, DateTime) get _dates {
    final now = DateTime.now();
    switch (_range) {
      case _Range.week:
        return (now.subtract(const Duration(days: 7)), now);
      case _Range.month:
        return (now.subtract(const Duration(days: 30)), now);
      case _Range.custom:
        return (now.subtract(const Duration(days: 90)), now);
    }
  }

  @override
  Widget build(BuildContext context) {
    final (from, to) = _dates;
    final fromS = _iso(from);
    final toS = _iso(to);

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: widget.standalone,
        title: Text(t(context).reports),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
            child: SegmentedButton<_Range>(
              segments: [
                ButtonSegment(value: _Range.week, label: Text(t(context).week)),
                ButtonSegment(value: _Range.month, label: Text(t(context).month)),
                ButtonSegment(value: _Range.custom, label: '90d'.isEmpty ? Text(t(context).custom) : const Text('90d')),
              ],
              selected: {_range},
              onSelectionChanged: (s) => setState(() => _range = s.first),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async => ref.invalidate(salesReportProvider((fromS, toS))),
              child: ListView(
                padding: const EdgeInsets.all(14),
                children: [
                  _SalesCard(from: fromS, to: toS),
                  const SizedBox(height: 16),
                  _BestSellersCard(from: fromS, to: toS),
                  const SizedBox(height: 16),
                  _StaffCard(from: fromS, to: toS),
                  const SizedBox(height: 16),
                  _PnlCard(from: fromS, to: toS),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _iso(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

final salesReportProvider =
    FutureProvider.autoDispose.family<SalesReport, (String, String)>(
        (ref, range) => Api().salesReport(range.$1, range.$2));

final bestSellersProvider =
    FutureProvider.autoDispose.family<List<TopItem>, (String, String)>(
        (ref, range) => Api().bestSellers(range.$1, range.$2));

final staffPerfProvider =
    FutureProvider.autoDispose.family<List<StaffSlice>, (String, String)>(
        (ref, range) => Api().staffPerformance(range.$1, range.$2));

final pnlProvider =
    FutureProvider.autoDispose.family<PnlReport, (String, String)>(
        (ref, range) => Api().pnl(range.$1, range.$2));

// ---------------------------------------------------------------- sales
class _SalesCard extends ConsumerWidget {
  const _SalesCard({required this.from, required this.to});
  final String from, to;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final report = ref.watch(salesReportProvider((from, to)));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(t(context).salesReport,
                trailing: MoneyText(
                    report.value?.total ?? 0,
                    bold: true,
                    style: theme.textTheme.titleMedium)),
            report.when(
              loading: () => const SizedBox(
                  height: 160,
                  child: Center(child: CircularProgressIndicator())),
              error: (e, _) => Text('$e'),
              data: (r) => Column(
                children: [
                  SizedBox(
                    height: 170,
                    child: r.series.isEmpty
                        ? Center(child: Text(t(context).emptySales,
                            style: theme.textTheme.bodyMedium
                                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)))
                        : _TrendChart(series: r.series),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _MiniStat(t(context).transactions, '${r.count}'),
                      _MiniStat(t(context).averageSale, Money.etb(r.average)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ...r.byMethod.map((m) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          children: [
                            Icon(paymentIcon(m.method),
                                size: 16, color: paymentColor(m.method)),
                            const SizedBox(width: 8),
                            Expanded(
                                child: Text(_methodName(context, m.method),
                                    style: theme.textTheme.bodySmall)),
                            Text('${m.count} · ${Money.etb(m.total)}',
                                style: theme.textTheme.labelMedium
                                    ?.copyWith(fontWeight: FontWeight.w600)),
                          ],
                        ),
                      )),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _methodName(BuildContext context, String m) => switch (m) {
        'cash' => t(context).cash,
        'telebirr' => t(context).telebirr,
        'cbe' => t(context).cbe,
        'credit' => t(context).credit,
        _ => m,
      };
}

class _MiniStat extends StatelessWidget {
  const _MiniStat(this.label, this.value);
  final String label, value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: theme.textTheme.labelSmall, overflow: TextOverflow.ellipsis),
            Text(value, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

class _TrendChart extends StatelessWidget {
  const _TrendChart({required this.series});
  final List<SeriesPoint> series;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final spots = <FlSpot>[
      for (var i = 0; i < series.length; i++)
        FlSpot(i.toDouble(), series[i].total),
    ];
    final maxY = spots.map((s) => s.y).reduce((a, b) => a > b ? a : b);
    return LineChart(
      LineChartData(
        minY: 0,
        maxY: maxY * 1.15 + 10,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (v) => FlLine(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
              strokeWidth: 1),
        ),
        titlesData: FlTitlesData(
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 26,
              interval: (series.length / 5).clamp(1, double.infinity).toDouble(),
              getTitlesWidget: (v, meta) {
                final i = v.toInt();
                if (i < 0 || i >= series.length) return const SizedBox.shrink();
                // Label roughly every nth point only — keeps labels from
                // colliding at the right edge of the chart.
                final nth = (series.length / 5).ceil().clamp(1, 99);
                if (i % nth != 0) return const SizedBox.shrink();
                final p = series[i].date;
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(p.length >= 10 ? p.substring(5) : p,
                      style: TextStyle(
                          fontSize: 10.5, color: theme.colorScheme.onSurfaceVariant)),
                );
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.25,
            preventCurveOverShooting: true,
            barWidth: 2.4,
            color: theme.colorScheme.primary,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: theme.colorScheme.primary.withValues(alpha: 0.12),
            ),
          ),
        ],
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (spots) => spots
                .map((s) => LineTooltipItem(
                    Money.etb(s.y),
                    TextStyle(
                        color: theme.colorScheme.onPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 11.5)))
                .toList(),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- best sellers
class _BestSellersCard extends ConsumerWidget {
  const _BestSellersCard({required this.from, required this.to});
  final String from, to;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final data = ref.watch(bestSellersProvider((from, to)));
    final items = data.value ?? [];
    final maxQty = items.isEmpty ? 1.0 : items.first.qty;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(t(context).bestSellers),
            if (items.isEmpty)
              Padding(
                padding: const EdgeInsets.all(14),
                child: Text(t(context).emptySales,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              )
            else
              ...items.take(7).map((it) {
                final rank = items.indexOf(it);
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 22,
                        child: Text('${rank + 1}',
                            style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: rank < 3 ? theme.colorScheme.primary : theme.colorScheme.outline)),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(it.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyMedium
                                    ?.copyWith(fontWeight: FontWeight.w600)),
                            const SizedBox(height: 3),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: it.qty / maxQty,
                                minHeight: 5,
                                backgroundColor:
                                    theme.colorScheme.surfaceContainerHigh,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 92,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text('${_fq(it.qty)} sold',
                                style: theme.textTheme.labelSmall),
                            MoneyText(it.revenue,
                                style: theme.textTheme.labelMedium),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  String _fq(double q) => q == q.roundToDouble() ? '${q.toInt()}' : '$q';
}

// ---------------------------------------------------------------- staff perf
class _StaffCard extends ConsumerWidget {
  const _StaffCard({required this.from, required this.to});
  final String from, to;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final data = ref.watch(staffPerfProvider((from, to)));
    final rows = data.value ?? [];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(t(context).staffPerformance),
            if (rows.isEmpty)
              Padding(
                padding: const EdgeInsets.all(14),
                child: Text(t(context).emptySales,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              )
            else
              ...rows.map((r) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 15,
                          backgroundColor: theme.colorScheme.primaryContainer,
                          child: Text(r.staff.isEmpty ? '?' : r.staff[0].toUpperCase(),
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: theme.colorScheme.primary)),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(r.staff,
                              style: theme.textTheme.bodyMedium
                                  ?.copyWith(fontWeight: FontWeight.w600)),
                        ),
                        Text('${r.count} txns',
                            style: theme.textTheme.labelSmall
                                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                        const SizedBox(width: 10),
                        MoneyText(r.total, bold: true),
                      ],
                    ),
                  )),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- P&L
class _PnlCard extends ConsumerWidget {
  const _PnlCard({required this.from, required this.to});
  final String from, to;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final data = ref.watch(pnlProvider((from, to)));
    final pnl = data.value;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(t(context).profitLoss),
            if (pnl == null)
              const SizedBox(
                  height: 80, child: Center(child: CircularProgressIndicator()))
            else ...[
              _PnlRow(t(context).revenue, pnl.revenue),
              _PnlRow(t(context).cogs, -pnl.cogs),
              const Divider(),
              _PnlRow(t(context).grossProfit, pnl.grossProfit, bold: true),
              ...pnl.expenses.map((e) => _PnlRow(
                  '${t(context).expenses}: ${e.category}', -e.total)),
              const Divider(),
              _PnlRow(
                t(context).netProfit,
                pnl.netProfit,
                bold: true,
                color: pnl.netProfit >= 0
                    ? theme.colorScheme.primary
                    : theme.colorScheme.error,
              ),
              if (pnl.estimateWarning) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.info_outline_rounded,
                        size: 14, color: const Color(0xFFE8A200)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(t(context).pnlWarning,
                          style: theme.textTheme.labelSmall
                              ?.copyWith(color: const Color(0xFFE8A200))),
                    ),
                  ],
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _PnlRow extends StatelessWidget {
  const _PnlRow(this.label, this.value, {this.bold = false, this.color});
  final String label;
  final double value;
  final bool bold;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: bold ? FontWeight.w700 : FontWeight.w400)),
          ),
          MoneyText(value,
              bold: bold,
              style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
                  color: color ?? (value < 0 ? theme.colorScheme.onSurfaceVariant : null))),
        ],
      ),
    );
  }
}
