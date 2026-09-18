import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app.dart';
import '../../api/api.dart';
import '../../models/models.dart';
import '../../utils/format.dart';
import '../../widgets/common.dart';

/// I1–I2 — expense list + quick add (feeds P&L).
class ExpensesScreen extends ConsumerStatefulWidget {
  const ExpensesScreen({super.key});

  @override
  ConsumerState<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends ConsumerState<ExpensesScreen> {
  List<Expense>? _expenses;
  List<ExpenseCategory>? _categories;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final futures = await Future.wait([
        Api().expenses(),
        Api().expenseCategories(),
      ]);
      if (mounted) {
        setState(() {
          _expenses = futures[0] as List<Expense>;
          _categories = futures[1] as List<ExpenseCategory>;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final expenses = _expenses;

    // Group by month.
    final months = <String, List<Expense>>{};
    double total = 0;
    if (expenses != null) {
      for (final e in expenses) {
        final key = e.date.length >= 7 ? e.date.substring(0, 7) : '—';
        months.putIfAbsent(key, () => []).add(e);
        total += e.amount;
      }
    }

    return Scaffold(
      appBar: AppBar(title: Text(t(context).expenses)),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'expFab',
        onPressed: () => _showForm(context),
        icon: const Icon(Icons.add_rounded),
        label: Text(t(context).addExpense),
      ),
      body: _error != null
          ? ErrorRetry(message: _error!, onRetry: _load)
          : expenses == null
              ? const Center(child: CircularProgressIndicator())
              : expenses.isEmpty
                  ? EmptyState(
                      icon: Icons.receipt_long_rounded,
                      title: t(context).emptyExpenses,
                      subtitle: 'Rent, salaries, supplies — track them to see real profit.',
                      actionLabel: t(context).addExpense,
                      onAction: () => _showForm(context),
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 96),
                      children: [
                        Card(
                          color: theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                const Icon(Icons.account_balance_wallet_rounded),
                                const SizedBox(width: 12),
                                Expanded(child: Text(t(context).expenseTotal)),
                                MoneyText(total, bold: true,
                                    style: theme.textTheme.titleLarge),
                              ],
                            ),
                          ),
                        ),
                        for (final month in months.keys)
                          ...[
                            Padding(
                              padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
                              child: Text(month,
                                  style: theme.textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: theme.colorScheme.onSurfaceVariant)),
                            ),
                            ...months[month]!.map((e) => Card(
                                  margin: const EdgeInsets.symmetric(vertical: 4),
                                  child: ListTile(
                                    leading: const Icon(Icons.receipt_long_rounded),
                                    title: Text(e.note.isEmpty
                                        ? (e.categoryName ?? 'Expense')
                                        : e.note),
                                    subtitle: Text(
                                        '${e.categoryName ?? 'Other'} · ${e.date}',
                                        style: theme.textTheme.labelSmall),
                                    trailing: MoneyText(e.amount, bold: true),
                                  ),
                                )),
                          ],
                      ],
                    ),
    );
  }

  Future<void> _showForm(BuildContext context) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ExpenseForm(categories: _categories ?? []),
    );
    _load();
  }
}

class _ExpenseForm extends ConsumerStatefulWidget {
  const _ExpenseForm({required this.categories});
  final List<ExpenseCategory> categories;

  @override
  ConsumerState<_ExpenseForm> createState() => _ExpenseFormState();
}

class _ExpenseFormState extends ConsumerState<_ExpenseForm> {
  final _amount = TextEditingController();
  final _note = TextEditingController();
  int? _categoryId;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _categoryId = widget.categories.isEmpty ? null : widget.categories.first.id;
  }

  Future<void> _save() async {
    final amt = double.tryParse(_amount.text.trim());
    if (amt == null || amt <= 0) {
      setState(() => _error = 'Enter a valid amount.');
      return;
    }
    setState(() => _saving = true);
    try {
      await Api().createExpense({
        'amount': amt,
        'note': _note.text.trim(),
        if (_categoryId != null) 'category': _categoryId,
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
          Text(t(context).addExpense,
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 14),
          DropdownButtonFormField<int>(
            value: _categoryId,
            decoration: InputDecoration(labelText: t(context).category),
            items: widget.categories
                .map((c) => DropdownMenuItem(value: c.id, child: Text(c.name)))
                .toList(),
            onChanged: (v) => setState(() => _categoryId = v),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _amount,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [DecimalInputFormatter()],
            decoration: InputDecoration(labelText: t(context).amount, suffixText: 'ETB'),
          ),
          const SizedBox(height: 12),
          TextField(controller: _note, decoration: InputDecoration(labelText: t(context).note)),
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
