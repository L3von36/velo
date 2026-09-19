import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../../app.dart';
import '../../api/api.dart';
import '../../models/models.dart';
import '../../providers/session.dart';
import '../../providers/shop.dart';
import '../../theme/app_theme.dart' show AppTheme;
import '../../utils/format.dart';
import '../../widgets/common.dart';
import 'checkout_sheet.dart';

/// D1 — POS main screen. Split view on wide screens (grid left ~65%,
/// live cart right ~35%); cart-as-bottom-sheet on mobile. Zero-lag taps:
/// cart is pure client state; server is only touched at checkout.
class PosScreen extends ConsumerStatefulWidget {
  const PosScreen({super.key, this.standalone = false});
  final bool standalone;

  @override
  ConsumerState<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends ConsumerState<PosScreen> {
  final _search = TextEditingController();
  String _searchText = '';
  int? _categoryFilter;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(catalogProvider.notifier).reload();
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(catalogProvider);
    final session = ref.watch(sessionProvider).value;
    final cart = ref.watch(cartProvider);
    final width = MediaQuery.of(context).size.width;
    final wide = width >= 900; // PRD: tablet/desktop split view
    final theme = Theme.of(context);

    final items = catalog.value?.filtered ?? [];
    final categories = catalog.value?.categories ?? [];

    final grid = Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
          child: TextField(
            controller: _search,
            autofocus: false,
            decoration: InputDecoration(
              hintText: t(context).searchItems,
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _searchText.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () {
                        _search.clear();
                        setState(() => _searchText = '');
                        ref.read(catalogProvider.notifier).setSearch('');
                      },
                    )
                  : const Icon(Icons.qr_code_scanner_rounded),
            ),
            onChanged: (v) {
              setState(() => _searchText = v);
              ref.read(catalogProvider.notifier).setSearch(v);
            },
          ),
        ),
        // Category quick-filter chips (D1).
        SizedBox(
          height: 52,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  label: Text(t(context).all),
                  selected: _categoryFilter == null,
                  onSelected: (_) {
                    setState(() => _categoryFilter = null);
                    ref.read(catalogProvider.notifier).setCategory(null);
                  },
                ),
              ),
              ...categories.map((c) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(c.name),
                      selected: _categoryFilter == c.id,
                      onSelected: (_) {
                        setState(() => _categoryFilter = c.id);
                        ref.read(catalogProvider.notifier).setCategory(c.id);
                      },
                    ),
                  )),
            ],
          ),
        ),
        Expanded(
          child: catalog.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => ErrorRetry(
                message: '$e', onRetry: () => ref.read(catalogProvider.notifier).reload()),
            data: (s) {
              if (items.isEmpty) {
                return EmptyState(
                  icon: Icons.inventory_2_rounded,
                  title: s.search.isEmpty ? t(context).emptyCatalog : 'No matches',
                  subtitle:
                      s.search.isEmpty ? t(context).emptyCatalogHint : 'Try a different search.',
                );
              }
              return GridView.builder(
                padding: const EdgeInsets.fromLTRB(14, 4, 14, 16),
                gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: wide ? 190 : 150,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 1.05,
                ),
                itemCount: items.length,
                itemBuilder: (context, i) => _ItemTile(
                  item: items[i],
                  onTap: () => _addToCart(items[i]),
                ),
              );
            },
          ),
        ),
      ],
    );

    final cartPanel = _CartPanel(
      cart: cart,
      session: session,
      wide: wide,
      onCheckout: _openCheckout,
      onHold: _holdSale,
      onResume: _resumeSale,
    );

    if (wide) {
      // The single most important layout decision (PRD D1):
      // grid 65% left, permanently visible cart 35% right.
      return Scaffold(
        appBar: _posBar(),
        body: Row(
          children: [
            Expanded(flex: 65, child: grid),
            VerticalDivider(width: 1, thickness: 1, color: theme.colorScheme.outlineVariant),
            SizedBox(width: 360, child: cartPanel),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: _posBar(),
      body: grid,
      bottomSheet: cart.lines.isEmpty
          ? null
          : _MobileCartBar(
              cart: cart,
              onTap: _openCheckout,
            ),
    );
  }

  PreferredSizeWidget _posBar() {
    return AppBar(
      leading: widget.standalone
          ? IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: () => Navigator.of(context).maybePop(),
            )
          : null,
      title: Text(t(context).sell),
      actions: [
        IconButton(
          tooltip: t(context).heldSales,
          icon: const Icon(Icons.pause_circle_outline_rounded),
          onPressed: _showHeld,
        ),
      ],
    );
  }

  void _addToCart(CatalogItem item) {
    try {
      if (item.variants.length > 1) {
        _pickVariant(item);
      } else {
        ref.read(cartProvider.notifier).add(item);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
    }
  }

  void _pickVariant(CatalogItem item) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(16),
          children: [
            Text(item.name, style: Theme.of(ctx).textTheme.titleMedium),
            const SizedBox(height: 10),
            ...item.variants.map((v) => ListTile(
                  enabled: v.stockQty > 0,
                  title: Text(v.label.isEmpty ? 'Default' : v.label),
                  subtitle: v.stockQty > 0 ? Text('Stock: ${v.stockQty}') : const Text('Out of stock'),
                  trailing: MoneyText(v.priceOverride ?? item.price, bold: true),
                  onTap: () {
                    Navigator.pop(ctx);
                    try {
                      ref.read(cartProvider.notifier).add(item, variant: v);
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text(e.toString().replaceFirst('Exception: ', ''))));
                    }
                  },
                )),
          ],
        ),
      ),
    );
  }

  Future<void> _openCheckout() async {
    final cart = ref.read(cartProvider);
    if (cart.lines.isEmpty) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const CheckoutSheet(),
    );
  }

  Future<void> _holdSale() async {
    final cart = ref.read(cartProvider);
    if (cart.lines.isEmpty) return;
    final label = await _askLabel();
    if (label == null) return;
    try {
      await Api().holdSale({
        'label': label,
        ...ref.read(cartProvider.notifier).snapshot(),
      });
      ref.read(cartProvider.notifier).clear();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('${t(context).holdSale}: $label')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e.toString().replaceFirst('ApiException: ', ''))));
      }
    }
  }

  Future<String?> _askLabel() {
    final ctrl = TextEditingController(
        text: ref.read(cartProvider).customerName ?? '');
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t(context).holdSale),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'e.g. Almaz — will pay soon'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t(context).cancel)),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: Text(t(context).confirm),
          ),
        ],
      ),
    );
  }

  Future<void> _resumeSale() async {
    try {
      final held = await Api().heldSales();
      if (!mounted) return;
      if (held.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(t(context).emptyHeld)));
        return;
      }
      showModalBottomSheet(
        context: context,
        builder: (ctx) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(8),
            children: held
                .map((h) => ListTile(
                      leading: const Icon(Icons.pause_circle_outline_rounded),
                      title: Text(h.label.isEmpty ? 'Held sale' : h.label),
                      subtitle: Text(
                          '${(h.payload['lines'] ?? []).length} ${t(context).items} · ${_time(h.createdAt)}'),
                      trailing: TextButton(
                        onPressed: () {
                          Navigator.pop(ctx);
                          ref.read(cartProvider.notifier).loadHeld(h);
                          Api().deleteHeldSale(h.id);
                        },
                        child: Text(t(context).resumeSale),
                      ),
                    ))
                .toList(),
          ),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  String _time(String iso) {
    final d = DateTime.tryParse(iso);
    return d == null ? '' : '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _showHeld() => _resumeSale();
}

// ---------------------------------------------------------------- item tile
class _ItemTile extends StatelessWidget {
  const _ItemTile({required this.item, required this.onTap});
  final CatalogItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final out = item.requiresStock && !item.isService && item.stockQty <= 0;
    final lowStock = item.requiresStock &&
        !item.isService &&
        !out &&
        item.stockQty <= item.lowStockThreshold;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: out ? null : onTap,
        child: out
            ? Stack(
                fit: StackFit.expand,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(10),
                    child: _tileContent(theme, lowStock),
                  ),
                  Positioned.fill(
                    child: ColoredBox(
                      color: theme.colorScheme.surface.withValues(alpha: 0.72),
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.error
                                .withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(t(context).outOfStock,
                              style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.error,
                                  fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ),
                  ),
                ],
              )
            : Padding(
                padding: const EdgeInsets.all(10),
                child: _tileContent(theme, lowStock)),
      ),
    );
  }

  Widget _tileContent(ThemeData theme, bool lowStock) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: (item.isService
                        ? theme.colorScheme.tertiary
                        : theme.colorScheme.primary)
                    .withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                item.isService ? Icons.spa_rounded : Icons.inventory_2_rounded,
                size: 15,
                color: item.isService
                    ? theme.colorScheme.tertiary
                    : theme.colorScheme.primary,
              ),
            ),
            const Spacer(),
            if (item.requiresStock && !item.isService)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: lowStock
                      ? AppTheme.warning.withValues(alpha: 0.12)
                      : theme.colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${item.stockQty}${item.unit == 'pc' ? '' : ' ${item.unit}'}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: lowStock
                        ? AppTheme.warning
                        : theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
          ],
        ),
        const Spacer(),
        Text(item.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall
                ?.copyWith(fontWeight: FontWeight.w600, height: 1.25)),
        const SizedBox(height: 5),
        Text(
          Money.etb(item.price),
          style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.2),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- cart panel
class _CartPanel extends ConsumerWidget {
  const _CartPanel({
    required this.cart,
    required this.session,
    required this.wide,
    required this.onCheckout,
    required this.onHold,
    required this.onResume,
  });

  final CartState cart;
  final SessionState? session;
  final bool wide;
  final VoidCallback onCheckout;
  final VoidCallback onHold;
  final VoidCallback onResume;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Column(
      children: [
        // Customer attach row.
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
          child: _CustomerRow(cart: cart),
        ),
        Expanded(
          child: cart.lines.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.shopping_cart_outlined,
                          size: 44, color: theme.colorScheme.outline),
                      const SizedBox(height: 10),
                      Text(t(context).cartEmpty,
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  itemCount: cart.lines.length,
                  itemBuilder: (context, i) {
                    final l = cart.lines[i];
                    return _CartLineTile(index: i, line: l);
                  },
                ),
        ),
        if (cart.lines.isNotEmpty) ...[
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                _Row(label: t(context).subtotal, value: Money.etb(cart.subtotal)),
                if (cart.discount > 0)
                  _Row(label: t(context).discount, value: '-${Money.etb(cart.discount)}'),
                const SizedBox(height: 6),
                _Row(
                  label: t(context).total,
                  value: Money.etb(cart.total),
                  bold: true,
                  valueStyle: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800, color: theme.colorScheme.primary),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: onCheckout,
                    icon: const Icon(Icons.payments_rounded),
                    label: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text('${t(context).charge} · ${Money.etb(cart.total)}',
                          style: const TextStyle(fontSize: 14.5)),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: onHold,
                        icon: const Icon(Icons.pause_rounded, size: 18),
                        label: Text(t(context).holdSale),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          ref.read(cartProvider.notifier).clear();
                        },
                        icon: const Icon(Icons.delete_outline_rounded, size: 18),
                        label: Text(t(context).clearCart),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _CustomerRow extends StatelessWidget {
  const _CustomerRow({required this.cart});
  final CartState cart;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => _pickCustomer(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Row(
          children: [
            Icon(
              cart.customerId == null ? Icons.person_search_rounded : Icons.person_rounded,
              size: 20,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                cart.customerName ?? t(context).walkInCustomer,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium,
              ),
            ),
            Text(
              cart.customerId == null ? t(context).attachCustomer : t(context).edit,
              style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.primary),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickCustomer(BuildContext context) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => const _CustomerPickerSheet(),
    );
  }
}

class _CustomerPickerSheet extends ConsumerStatefulWidget {
  const _CustomerPickerSheet();

  @override
  ConsumerState<_CustomerPickerSheet> createState() => _CustomerPickerSheetState();
}

class _CustomerPickerSheetState extends ConsumerState<_CustomerPickerSheet> {
  final _search = TextEditingController();
  List<Customer>? _results;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    try {
      final r = await Api().customers(search: _search.text);
      if (mounted) setState(() => _results = r);
    } catch (_) {
      if (mounted) setState(() => _results = []);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      builder: (ctx, scroll) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: TextField(
              controller: _search,
              autofocus: true,
              decoration: InputDecoration(
                hintText: t(context).search,
                prefixIcon: const Icon(Icons.search_rounded),
              ),
              onChanged: (_) => _run(),
            ),
          ),
          Expanded(
            child: _results == null
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    controller: scroll,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    children: [
                      ListTile(
                        leading: const Icon(Icons.person_off_rounded),
                        title: Text(t(context).walkInCustomer),
                        onTap: () {
                          ref.read(cartProvider.notifier).attachCustomer(null, null);
                          Navigator.pop(ctx);
                        },
                      ),
                      ..._results!.map((c) => ListTile(
                            leading: CircleAvatar(
                              child: Text(c.name.isEmpty ? '?' : c.name[0].toUpperCase()),
                            ),
                            title: Text(c.name),
                            subtitle: c.phone.isEmpty ? null : Text(EthPhone.pretty(c.phone)),
                            trailing: c.owes
                                ? Chip(
                                    label: Text(Money.etb(c.balance)),
                                    backgroundColor: const Color(0xFFB3261E).withValues(alpha: 0.12),
                                  )
                                : null,
                            onTap: () {
                              ref.read(cartProvider.notifier).attachCustomer(c.id, c.name);
                              Navigator.pop(ctx);
                            },
                          )),
                      const Divider(),
                      ListTile(
                        leading: const Icon(Icons.person_add_alt_rounded),
                        title: Text(t(context).addCustomer),
                        onTap: () => _quickAdd(ctx),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _quickAdd(BuildContext ctx) async {
    final name = TextEditingController();
    final phone = TextEditingController();
    Navigator.pop(ctx);
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx2) => Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx2).viewInsets.bottom, left: 16, right: 16, top: 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(t(context).addCustomer, style: Theme.of(ctx2).textTheme.titleMedium),
            const SizedBox(height: 12),
            TextField(
                controller: name,
                decoration: InputDecoration(labelText: t(context).customerName)),
            const SizedBox(height: 10),
            TextField(
                controller: phone,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(labelText: t(context).phoneNumber)),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: () async {
                final norm = EthPhone.normalize(phone.text);
                try {
                  final c = await Api().createCustomer({
                    'name': name.text.trim(),
                    'phone': norm ?? '',
                  });
                  await ref.read(customersProvider.notifier).reload();
                  ref.read(cartProvider.notifier).attachCustomer(c.id, c.name);
                  if (ctx2.mounted) Navigator.pop(ctx2);
                } catch (e) {
                  if (ctx2.mounted) {
                    ScaffoldMessenger.of(ctx2).showSnackBar(
                        SnackBar(content: Text(e.toString().replaceFirst('ApiException: ', ''))));
                  }
                }
              },
              child: Text(t(context).save),
            ),
            const SizedBox(height: 18),
          ],
        ),
      ),
    );
  }
}

class _CartLineTile extends ConsumerWidget {
  const _CartLineTile({required this.index, required this.line});
  final int index;
  final CartLine line;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isFloat = line.unitPrice != line.unitPrice.roundToDouble();
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(line.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  if (line.variantLabel != null && line.variantLabel!.isNotEmpty)
                    Text(line.variantLabel!, style: theme.textTheme.labelSmall),
                  Text(Money.etb(line.unitPrice), style: theme.textTheme.labelSmall),
                ],
              ),
            ),
            Row(
              children: [
                _QtyBtn(
                  icon: Icons.remove_rounded,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    if (isFloat) {
                      ref.read(cartProvider.notifier).setQty(index, line.qty - 0.5);
                    } else {
                      ref.read(cartProvider.notifier).setQty(index, line.qty - 1);
                    }
                  },
                ),
                SizedBox(
                  width: 34,
                  child: Text(
                    isFloat ? '${line.qty}' : '${line.qty.toInt()}',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                _QtyBtn(
                  icon: Icons.add_rounded,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    ref.read(cartProvider.notifier).setQty(index, line.qty + (isFloat ? 0.5 : 1));
                  },
                ),
                const SizedBox(width: 4),
                SizedBox(
                  width: 88,
                  child: Text(
                    Money.etb(line.lineTotal),
                    textAlign: TextAlign.right,
                    style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close_rounded, size: 18),
                  onPressed: () => ref.read(cartProvider.notifier).removeAt(index),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _QtyBtn extends StatelessWidget {
  const _QtyBtn({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(9),
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: theme.colorScheme.primary.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Icon(icon, size: 18, color: theme.colorScheme.primary),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value, this.bold = false, this.valueStyle});
  final String label, value;
  final bool bold;
  final TextStyle? valueStyle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
          Text(value,
              style: valueStyle ??
                  theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: bold ? FontWeight.w800 : FontWeight.w500)),
        ],
      ),
    );
  }
}

// mobile bottom bar
class _MobileCartBar extends StatelessWidget {
  const _MobileCartBar({required this.cart, required this.onTap});
  final CartState cart;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: Material(
        elevation: 10,
        shadowColor: Colors.black26,
        color: theme.colorScheme.surfaceContainerLowest,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
            child: Row(
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withValues(alpha: 0.09),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.shopping_cart_rounded,
                          size: 22, color: theme.colorScheme.primary),
                    ),
                    Positioned(
                      right: -6,
                      top: -6,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                            color: theme.colorScheme.primary,
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: theme.colorScheme.surfaceContainerLowest,
                                width: 1.5)),
                        child: Text(
                          '${cart.itemCount}',
                          style: TextStyle(
                              color: theme.colorScheme.onPrimary,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(Money.etb(cart.total),
                          style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.3)),
                      if (cart.customerName != null)
                        Text(cart.customerName!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant)),
                    ],
                  ),
                ),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 44),
                  ),
                  onPressed: onTap,
                  icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                  label: Text(t(context).charge),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
