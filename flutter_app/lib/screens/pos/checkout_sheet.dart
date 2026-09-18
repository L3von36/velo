import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app.dart';
import '../../api/api.dart';
import '../../models/models.dart';
import '../../providers/session.dart';
import '../dashboard_screen.dart';
import '../../providers/shop.dart';
import '../../utils/format.dart';
import '../../widgets/common.dart';

/// D3–D10 — payment flow: method select → per-method input → receipt.
class CheckoutSheet extends ConsumerStatefulWidget {
  const CheckoutSheet({super.key});

  @override
  ConsumerState<CheckoutSheet> createState() => _CheckoutSheetState();
}

enum _Stage { method, cash, mobileMoney, processing, done }

class _CheckoutSheetState extends ConsumerState<CheckoutSheet> {
  _Stage _stage = _Stage.method;
  String _method = 'cash';
  String _tenderedText = '';
  final _ref = TextEditingController();
  Sale? _sale;
  String? _error;

  double get _total => ref.read(cartProvider).total;
  double get _tendered => double.tryParse(_tenderedText.isEmpty ? '0' : _tenderedText) ?? 0;
  double get _change => _tendered - _total;
  bool get _cashEnough => _tendered >= _total - 0.001;

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    final session = ref.watch(sessionProvider).value;
    final tenant = session?.tenant;

    return PopScope(
      canPop: _stage != _Stage.processing,
      child: Padding(
        padding: EdgeInsets.only(
            left: 16, right: 16, top: 14,
            bottom: MediaQuery.of(context).viewInsets.bottom + 16),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 560,
            maxHeight: MediaQuery.of(context).size.height * 0.88,
          ),
          child: switch (_stage) {
            _Stage.method => _buildMethodSelect(context, cart, tenant),
            _Stage.cash => _buildCash(context),
            _Stage.mobileMoney => _buildMobileMoney(context, tenant),
            _Stage.processing => _buildProcessing(context),
            _Stage.done => _buildReceipt(context, cart),
          },
        ),
      ),
    );
  }

  // ------------------------------------------------------- D3 method select
  Widget _buildMethodSelect(BuildContext context, CartState cart, TenantInfo? tenant) {
    final theme = Theme.of(context);
    final canCredit = (tenant?.acceptCredit ?? true) && cart.customerId != null;

    final methods = [
      _MethodRow('cash', t(context).cash, Icons.payments_rounded, const Color(0xFF0E7A3D), true),
      if (tenant?.acceptTelebirr ?? true)
        _MethodRow('telebirr', t(context).telebirr, Icons.phone_android_rounded, const Color(0xFFB3261E), true),
      if (tenant?.acceptCbe ?? true)
        _MethodRow('cbe', t(context).cbe, Icons.account_balance_rounded, const Color(0xFF6A4BA1), true),
      _MethodRow(
          'credit', t(context).credit, Icons.receipt_rounded, const Color(0xFFE8A200), canCredit,
          disabledNote: canCredit ? null : t(context).creditRequiresCustomer),
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sheetTitle(theme, t(context).paymentMethod),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          ),
        ...methods.map((m) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Material(
                color: m.enabled
                    ? theme.colorScheme.surfaceContainerLow
                    : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  onTap: m.enabled ? () => _pick(m.key) : null,
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: theme.colorScheme.outlineVariant),
                    ),
                    child: Row(
                      children: [
                        Icon(m.icon, color: m.color, size: 26),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(m.label,
                                  style: theme.textTheme.titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w700)),
                              if (m.disabledNote != null)
                                Text(m.disabledNote!,
                                    style: theme.textTheme.labelSmall
                                        ?.copyWith(color: theme.colorScheme.error)),
                            ],
                          ),
                        ),
                        Text(Money.etb(_total),
                            style: theme.textTheme.bodyMedium?.copyWith(color: m.color)),
                      ],
                    ),
                  ),
                ),
              ),
            )),
      ],
    );
  }

  void _pick(String method) {
    setState(() {
      _method = method;
      _error = null;
      if (method == 'cash') {
        _stage = _Stage.cash;
        _tenderedText = _total == _total.roundToDouble()
            ? _total.toStringAsFixed(0)
            : _total.toStringAsFixed(2); // default exact — fastest path
      } else if (method == 'credit') {
        _complete(); // full amount on the customer's account
      } else {
        _stage = _Stage.mobileMoney;
      }
    });
  }

  // ------------------------------------------------------- D4 cash keypad
  Widget _buildCash(BuildContext context) {
    final theme = Theme.of(context);
    final quick = [_total, 50.0, 100.0, 200.0, 500.0]
        .map((v) => double.parse(v.toStringAsFixed(2)))
        .toSet()
        .toList();

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sheetTitle(theme, t(context).cash),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            children: [
              _kv(theme, t(context).amountDue, Money.etb(_total)),
              const SizedBox(height: 8),
              _kv(theme, t(context).amountTendered, Money.etb(_tendered)),
              const Divider(height: 20),
              _kv(
                theme,
                _cashEnough ? t(context).change : 'Short',
                Money.etb(_change.abs()),
                highlight: true,
                valueColor: _cashEnough ? theme.colorScheme.primary : theme.colorScheme.error,
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: quick
              .map((v) => OutlinedButton(
                    onPressed: () => setState(() => _tenderedText =
                        v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2)),
                    child: Text(Money.etb(v, withSymbol: false)),
                  ))
              .toList(),
        ),
        const SizedBox(height: 10),
        _Numpad(
          onKey: (k) {
            HapticFeedback.selectionClick();
            setState(() {
              if (k == 'C') {
                _tenderedText = '';
              } else if (k == '.') {
                if (!_tenderedText.contains('.')) _tenderedText = '$_tenderedText.';
              } else if (_tenderedText.length < 10) {
                _tenderedText = '$_tenderedText$k';
              }
            });
          },
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            TextButton(
              onPressed: () => setState(() => _stage = _Stage.method),
              child: Text(t(context).cancel),
            ),
            const Spacer(),
            FilledButton.icon(
              onPressed: _cashEnough ? _complete : null,
              icon: const Icon(Icons.check_rounded),
              label: Text('${t(context).completeSale} · ${Money.etb(_total)}'),
            ),
          ],
        ),
      ],
    );
  }

  // ------------------------------------------------------- D5 telebirr/CBE
  Widget _buildMobileMoney(BuildContext context, TenantInfo? tenant) {
    final theme = Theme.of(context);
    final isTelebirr = _method == 'telebirr';
    final payTo = isTelebirr ? (tenant?.telebirrNumber ?? '') : (tenant?.cbeNumber ?? '');
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sheetTitle(theme, isTelebirr ? t(context).telebirr : t(context).cbe),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Ask the customer to pay to:', style: theme.textTheme.labelMedium),
                const SizedBox(height: 4),
                Text(
                  payTo.isEmpty ? '(set your number in Settings)' : payTo,
                  style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _ref,
          decoration: InputDecoration(
            labelText: t(context).referenceNumber,
            hintText: 'e.g. TB8H2K91LM',
            prefixIcon: const Icon(Icons.tag_rounded),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'A reference number marks the payment as ${t(context).pendingVerification.toLowerCase()} — '
          'you can leave it empty and mark as paid manually.',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 14),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          ),
        Row(
          children: [
            TextButton(
              onPressed: () => setState(() => _stage = _Stage.method),
              child: Text(t(context).cancel),
            ),
            const Spacer(),
            OutlinedButton(
              onPressed: _complete,
              child: Text(t(context).markPaidManually),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: () {
                if (_ref.text.trim().isEmpty) {
                  setState(() => _error = 'Enter the reference number, or mark as paid manually.');
                  return;
                }
                _complete();
              },
              icon: const Icon(Icons.check_rounded),
              label: Text('${t(context).completeSale} · ${Money.etb(_total)}'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildProcessing(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 30),
        const CircularProgressIndicator(),
        const SizedBox(height: 20),
        Text(t(context).loading, style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 30),
      ],
    );
  }

  // ------------------------------------------------------- D8/D10 receipt
  Widget _buildReceipt(BuildContext context, CartState cart) {
    final theme = Theme.of(context);
    final sale = _sale!;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        CircleAvatar(
          radius: 28,
          backgroundColor: theme.colorScheme.primaryContainer,
          child: Icon(Icons.check_rounded, size: 34, color: theme.colorScheme.primary),
        ),
        const SizedBox(height: 10),
        Center(
          child: Text(t(context).saleComplete,
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
        ),
        const SizedBox(height: 14),
        // Receipt preview (D8).
        Card(
          color: Colors.white,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(cart.customerName ?? t(context).walkInCustomer,
                    style: theme.textTheme.labelMedium),
                const SizedBox(height: 2),
                Text('Receipt #${sale.receiptNumber}',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800,
                        color: Colors.black)),
                const Divider(height: 18),
                ...sale.items.map((it) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          Expanded(
                              child: Text('${_fq(it.qty)} × ${it.name}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: Colors.black87))),
                          Text(Money.etb(it.qty * it.unitPrice - it.discount),
                              style: const TextStyle(color: Colors.black87)),
                        ],
                      ),
                    )),
                const Divider(height: 18),
                _kvDark(theme, t(context).total, Money.etb(sale.total)),
                ...sale.payments.map((p) => Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Row(
                        children: [
                          Icon(paymentIcon(p.method), size: 14, color: paymentColor(p.method)),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '${_methodName(p.method)}'
                              '${p.referenceNumber.isNotEmpty ? ' · ${p.referenceNumber}' : ''}'
                              '${p.status == 'pending_verification' ? ' · ${t(context).pendingVerification}' : ''}',
                              style: const TextStyle(color: Colors.black87, fontSize: 12),
                            ),
                          ),
                          Text(Money.etb(p.amount),
                              style: const TextStyle(color: Colors.black87, fontSize: 12)),
                        ],
                      ),
                    )),
                if (sale.discountTotal > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text('${t(context).discount}: -${Money.etb(sale.discountTotal)}',
                        style: const TextStyle(color: Colors.black54, fontSize: 12)),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        // D9 — print/share actions. Web build: copy + done (thermal printing
        // comes with the native mobile/desktop builds per PRD K7).
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: _receiptText(sale)));
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Receipt copied to clipboard')));
                },
                icon: const Icon(Icons.copy_rounded, size: 18),
                label: const Text('Copy'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: FilledButton(
                onPressed: () {
                  ref.read(cartProvider.notifier).clear();
                  Navigator.of(context).pop();
                },
                child: Text(t(context).newSaleBtn),
              ),
            ),
          ],
        ),
      ],
    );
  }

  String _methodName(String m) => switch (m) {
        'cash' => t(context).cash,
        'telebirr' => t(context).telebirr,
        'cbe' => t(context).cbe,
        'credit' => t(context).credit,
        _ => m,
      };

  String _fq(double q) => q == q.roundToDouble() ? '${q.toInt()}' : '$q';

  String _receiptText(Sale sale) {
    final b = StringBuffer();
    b.writeln('Receipt #${sale.receiptNumber}');
    b.writeln(sale.createdAt);
    b.writeln('---');
    for (final it in sale.items) {
      b.writeln('${_fq(it.qty)} x ${it.name} — ${Money.etb(it.qty * it.unitPrice - it.discount)}');
    }
    b.writeln('---');
    b.writeln('Total: ${Money.etb(sale.total)}');
    for (final p in sale.payments) {
      b.writeln('${p.method}: ${Money.etb(p.amount)}${p.status == 'pending_verification' ? ' (pending)' : ''}');
    }
    b.writeln('Thank you!');
    return b.toString();
  }

  // ------------------------------------------------------- actions
  Future<void> _complete() async {
    final cart = ref.read(cartProvider);
    setState(() {
      _stage = _Stage.processing;
      _error = null;
    });
    final pays = <Map<String, dynamic>>[];
    switch (_method) {
      case 'cash':
        pays.add({'method': 'cash', 'amount': cart.total});
      case 'credit':
        pays.add({'method': 'credit', 'amount': cart.total});
      default:
        pays.add({
          'method': _method,
          'amount': cart.total,
          if (_ref.text.trim().isNotEmpty) 'reference_number': _ref.text.trim(),
        });
    }
    try {
      final sale = await Api().checkout({
        'items': cart.lines
            .map((l) => {
                  'item_id': l.itemId,
                  'variant_id': l.variantId,
                  'qty': l.qty,
                })
            .toList(),
        'payments': pays,
        if (cart.customerId != null) 'customer_id': cart.customerId,
        if (cart.discount > 0) 'discount': cart.discount,
        if (cart.heldSaleId != null) 'held_sale_id': cart.heldSaleId,
      });
      setState(() {
        _sale = sale;
        _stage = _Stage.done;
      });
      // Refresh catalog stock in background.
      ref.read(catalogProvider.notifier).reload();
      ref.invalidate(dashboardDataProvider);
    } catch (e) {
      setState(() {
        _stage = _Stage.method;
        _error = e.toString().replaceFirst('ApiException: ', '');
      });
    }
  }

  Widget _sheetTitle(ThemeData theme, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          children: [
            Expanded(
              child: Text(text,
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
            ),
            Text(Money.etb(_total),
                style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800, color: theme.colorScheme.primary)),
          ],
        ),
      );

  Widget _kv(ThemeData theme, String k, String v,
      {bool highlight = false, Color? valueColor}) {
    return Row(
      children: [
        Expanded(child: Text(k, style: theme.textTheme.bodyMedium)),
        Text(v,
            style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: highlight ? FontWeight.w800 : FontWeight.w600,
                color: valueColor)),
      ],
    );
  }

  Widget _kvDark(ThemeData theme, String k, String v) => Row(
        children: [
          Expanded(
              child: Text(k,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, color: Colors.black))),
          Text(v,
              style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.black)),
        ],
      );
}

class _MethodRow {
  const _MethodRow(this.key, this.label, this.icon, this.color, this.enabled,
      {this.disabledNote});
  final String key, label;
  final IconData icon;
  final Color color;
  final bool enabled;
  final String? disabledNote;
}

class _Numpad extends StatelessWidget {
  const _Numpad({required this.onKey});
  final ValueChanged<String> onKey;

  static const _keys = [
    '1', '2', '3',
    '4', '5', '6',
    '7', '8', '9',
    '00', '0', '.',
  ];
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 232,
      child: GridView.count(
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: 3,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 2.4,
        children: [
          for (final k in _keys)
            _pad(context, k, () => onKey(k)),
          _pad(context, 'C', () => onKey('C'), color: Theme.of(context).colorScheme.errorContainer),
        ],
      ),
    );
  }

  Widget _pad(BuildContext context, String label, VoidCallback onTap, {Color? color}) {
    final theme = Theme.of(context);
    return Material(
      color: color ?? theme.colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Center(
          child: Text(
            label == 'C' ? 'C' : label,
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
      ),
    );
  }
}
