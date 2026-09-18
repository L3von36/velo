import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app.dart';
import '../../api/api.dart';
import '../../models/models.dart';
import '../../providers/shop.dart';
import '../../utils/format.dart';
import '../../widgets/common.dart';

/// F1–F4 — customer list, quick add, detail with append-only debt ledger.
class CustomersScreen extends ConsumerStatefulWidget {
  const CustomersScreen({super.key});

  @override
  ConsumerState<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends ConsumerState<CustomersScreen> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(customersProvider.notifier).reload();
    });
  }

  @override
  Widget build(BuildContext context) {
    final customers = ref.watch(customersProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(t(context).customers)),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'custFab',
        onPressed: () => _showForm(context),
        icon: const Icon(Icons.person_add_alt_rounded),
        label: Text(t(context).addCustomer),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
            child: TextField(
              controller: _search,
              decoration: InputDecoration(
                hintText: '${t(context).search} — ${t(context).name.toLowerCase()} / ${t(context).phoneNumber.toLowerCase()}',
                prefixIcon: const Icon(Icons.search_rounded),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Expanded(
            child: customers.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => ErrorRetry(
                  message: '$e', onRetry: () => ref.read(customersProvider.notifier).reload()),
              data: (list) {
                final filtered = list
                    .where((c) =>
                        _query.isEmpty ||
                        c.name.toLowerCase().contains(_query.toLowerCase()) ||
                        c.phone.contains(_query))
                    .toList()
                  ..sort((a, b) => b.balance.compareTo(a.balance));
                if (filtered.isEmpty) {
                  return EmptyState(
                    icon: Icons.people_alt_rounded,
                    title: t(context).emptyCustomers,
                    subtitle: t(context).emptyCustomersHint,
                    actionLabel: t(context).addCustomer,
                    onAction: () => _showForm(context),
                  );
                }
                return RefreshIndicator(
                  onRefresh: () => ref.read(customersProvider.notifier).reload(),
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(14, 8, 14, 96),
                    itemCount: filtered.length,
                    itemBuilder: (ctx, i) {
                      final c = filtered[i];
                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        child: ListTile(
                          onTap: () => _openDetail(context, c),
                          leading: CircleAvatar(
                            backgroundColor: c.owes
                                ? const Color(0xFFB3261E).withValues(alpha: 0.14)
                                : theme.colorScheme.primaryContainer,
                            child: Text(
                              c.name.isEmpty ? '?' : c.name[0].toUpperCase(),
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: c.owes ? const Color(0xFFB3261E) : theme.colorScheme.primary,
                              ),
                            ),
                          ),
                          title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: c.phone.isEmpty ? null : Text(EthPhone.pretty(c.phone)),
                          trailing: c.owes
                              ? Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(t(context).balance,
                                        style: theme.textTheme.labelSmall),
                                    Text(Money.etb(c.balance),
                                        style: theme.textTheme.titleSmall?.copyWith(
                                            fontWeight: FontWeight.w800,
                                            color: const Color(0xFFB3261E))),
                                  ],
                                )
                              : const Icon(Icons.chevron_right_rounded),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showForm(BuildContext context, {Customer? existing}) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _CustomerForm(existing: existing),
    );
    ref.read(customersProvider.notifier).reload();
  }

  Future<void> _openDetail(BuildContext context, Customer c) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _CustomerDetailSheet(customer: c),
    );
    ref.read(customersProvider.notifier).reload();
  }
}

// ---------------------------------------------------------------- form
class _CustomerForm extends ConsumerStatefulWidget {
  const _CustomerForm({this.existing});
  final Customer? existing;

  @override
  ConsumerState<_CustomerForm> createState() => _CustomerFormState();
}

class _CustomerFormState extends ConsumerState<_CustomerForm> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _phone = TextEditingController(text: widget.existing?.phone ?? '');
  late final _notes = TextEditingController(text: widget.existing?.notes ?? '');
  bool _saving = false;
  String? _error;

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) return;
    setState(() => _saving = true);
    try {
      final norm = EthPhone.normalize(_phone.text);
      await Api().createCustomer({
        'name': _name.text.trim(),
        'phone': norm ?? '',
        'notes': _notes.text.trim(),
      });
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('ApiException: ', ''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(
          left: 18, right: 18, top: 18,
          bottom: MediaQuery.of(context).viewInsets.bottom + 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.existing == null ? t(context).addCustomer : t(context).edit,
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 14),
          TextField(controller: _name, decoration: InputDecoration(labelText: t(context).customerName)),
          const SizedBox(height: 12),
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(
                labelText: t(context).phoneNumber, hintText: t(context).phoneHint),
          ),
          const SizedBox(height: 12),
          TextField(controller: _notes, decoration: InputDecoration(labelText: t(context).note)),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: TextStyle(color: theme.colorScheme.error, fontSize: 13)),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(width: 22, height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.4))
                : Text(t(context).save),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- detail
class _CustomerDetailSheet extends ConsumerStatefulWidget {
  const _CustomerDetailSheet({required this.customer});
  final Customer customer;

  @override
  ConsumerState<_CustomerDetailSheet> createState() => _CustomerDetailSheetState();
}

class _CustomerDetailSheetState extends ConsumerState<_CustomerDetailSheet> {
  Map<String, dynamic>? _data;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await Api().customerDetail(widget.customer.id);
      if (mounted) setState(() => _data = d);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final customer = Customer.fromJson((_data?['customer'] ?? widget.customer.toJsonSafe()) as Map<String, dynamic>);
    final sales = ((_data?['sales'] ?? []) as List).map((e) => Sale.fromJson(e as Map<String, dynamic>)).toList();
    final ledger = ((_data?['ledger'] ?? []) as List).map((e) => LedgerEntry.fromJson(e as Map<String, dynamic>)).toList();

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.9,
      builder: (ctx, scroll) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(customer.name,
                              style: theme.textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w800)),
                          if (customer.phone.isNotEmpty)
                            Text(EthPhone.pretty(customer.phone),
                                style: theme.textTheme.bodyMedium
                                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                        ],
                      ),
                    ),
                    if (customer.owes)
                      Chip(
                        label: Text(Money.etb(customer.balance)),
                        backgroundColor: const Color(0xFFB3261E).withValues(alpha: 0.12),
                        labelStyle: const TextStyle(color: Color(0xFFB3261E), fontWeight: FontWeight.w700),
                      ),
                    IconButton(
                        icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(ctx)),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _ledgerEntry(context, 'charge'),
                        icon: const Icon(Icons.add_card_rounded, size: 18),
                        label: Text(t(context).recordCharge, overflow: TextOverflow.ellipsis),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: customer.owes ? () => _ledgerEntry(context, 'payment') : null,
                        icon: const Icon(Icons.payments_rounded, size: 18),
                        label: Text(t(context).recordPayment, overflow: TextOverflow.ellipsis),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (_error != null)
            Padding(padding: const EdgeInsets.all(16), child: Text(_error!)),
          Expanded(
            child: DefaultTabController(
              length: 2,
              child: Column(
                children: [
                  TabBar(
                    tabs: [
                      Tab(text: t(context).purchaseHistory),
                      Tab(text: t(context).ledger),
                    ],
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _SalesTab(sales: sales, scroll: scroll),
                        _LedgerTab(ledger: ledger, scroll: scroll),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _ledgerEntry(BuildContext context, String type) async {
    final amount = TextEditingController();
    final note = TextEditingController();
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
            left: 18, right: 18, top: 18,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(type == 'charge' ? t(context).recordCharge : t(context).recordPayment,
                style: Theme.of(ctx).textTheme.titleMedium),
            const SizedBox(height: 12),
            TextField(
              controller: amount,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [DecimalInputFormatter()],
              decoration: InputDecoration(labelText: t(context).amount, suffixText: 'ETB'),
            ),
            const SizedBox(height: 10),
            TextField(controller: note, decoration: InputDecoration(labelText: t(context).note)),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(t(context).confirm),
            ),
          ],
        ),
      ),
    );
    if (confirmed == true && amount.text.isNotEmpty) {
      try {
        await Api().addLedger(widget.customer.id, {
          'type': type,
          'amount': double.tryParse(amount.text) ?? 0,
          'note': note.text.trim(),
        });
        await _load();
      } catch (e) {
        messenger.showSnackBar(
            SnackBar(content: Text(e.toString().replaceFirst('ApiException: ', ''))));
      }
    }
  }
}

class _SalesTab extends StatelessWidget {
  const _SalesTab({required this.sales, required this.scroll});
  final List<Sale> sales;
  final ScrollController scroll;

  @override
  Widget build(BuildContext context) {
    if (sales.isEmpty) {
      return ListView(controller: scroll, children: [
        Padding(
          padding: const EdgeInsets.all(32),
          child: Center(child: Text(t(context).emptySales)),
        ),
      ]);
    }
    return ListView(
      controller: scroll,
      padding: const EdgeInsets.all(8),
      children: sales
          .map((s) => ListTile(
                leading: const Icon(Icons.receipt_rounded),
                title: Text('#${s.receiptNumber}'),
                subtitle: Text(_d(s.createdAt)),
                trailing: MoneyText(s.total, bold: true),
              ))
          .toList(),
    );
  }

  String _d(String iso) {
    final dt = DateTime.tryParse(iso);
    return dt == null ? '' : '${dt.day}/${dt.month}/${dt.year}';
  }
}

class _LedgerTab extends StatelessWidget {
  const _LedgerTab({required this.ledger, required this.scroll});
  final List<LedgerEntry> ledger;
  final ScrollController scroll;

  @override
  Widget build(BuildContext context) {
    if (ledger.isEmpty) {
      return ListView(controller: scroll, children: [
        Padding(
          padding: const EdgeInsets.all(32),
          child: Center(child: Text(t(context).noOutstandingDebt)),
        ),
      ]);
    }
    return ListView(
      controller: scroll,
      padding: const EdgeInsets.all(8),
      children: ledger
          .map((e) {
            final charge = e.type == 'charge';
            return ListTile(
              leading: Icon(
                charge ? Icons.add_card_rounded : Icons.payments_rounded,
                color: charge ? const Color(0xFFB3261E) : const Color(0xFF0E7A3D),
              ),
              title: Text(
                '${charge ? '+' : '-'}${Money.etb(e.amount)}',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: charge ? const Color(0xFFB3261E) : const Color(0xFF0E7A3D),
                ),
              ),
              subtitle: Text(
                  '${e.note.isEmpty ? e.type : e.note}\n${_d(e.createdAt)}${e.staffName != null ? ' · ${e.staffName}' : ''}',
                  style: const TextStyle(fontSize: 12)),
              isThreeLine: true,
              trailing: Text('bal ${Money.etb(e.balanceAfter, withSymbol: false)}',
                  style: const TextStyle(fontSize: 12)),
            );
          })
          .toList(),
    );
  }

  String _d(String iso) {
    final dt = DateTime.tryParse(iso);
    return dt == null ? '' : '${dt.day}/${dt.month}/${dt.year} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

extension on Customer {
  Map<String, dynamic> toJsonSafe() => {
        'id': id, 'name': name, 'phone': phone, 'notes': notes, 'balance': balance,
      };
}
