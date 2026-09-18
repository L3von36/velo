import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app.dart';
import '../../models/models.dart';
import '../../providers/session.dart';
import '../../providers/shop.dart';
import '../../utils/format.dart';

/// C4/C5 — add/edit product or service. Fields adapt to item type:
/// services get duration; products get stock, unit, barcode, threshold.
class ItemFormSheet extends ConsumerStatefulWidget {
  const ItemFormSheet({super.key, this.item});
  final CatalogItem? item;

  @override
  ConsumerState<ItemFormSheet> createState() => _ItemFormSheetState();
}

class _ItemFormSheetState extends ConsumerState<ItemFormSheet> {
  late bool _isService;
  late final _name = TextEditingController(text: widget.item?.name ?? '');
  late final _price = TextEditingController(
      text: widget.item == null ? '' : _trim(widget.item!.price));
  late final _cost = TextEditingController(
      text: widget.item?.cost == null ? '' : _trim(widget.item!.cost!));
  late final _stock = TextEditingController(
      text: widget.item == null ? '' : '${widget.item!.stockQty}');
  late final _barcode = TextEditingController(text: widget.item?.barcode ?? '');
  late final _threshold =
      TextEditingController(text: widget.item == null ? '5' : '${widget.item!.lowStockThreshold}');
  int? _categoryId;
  int? _duration;
  String _unit = 'pc';
  bool _saving = false;
  String? _error;

  static String _trim(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  @override
  void initState() {
    super.initState();
    final session = ref.read(sessionProvider).value;
    _isService = widget.item?.isService ??
        ((session?.tenant?.sellsServices ?? false) &&
            !(session?.tenant?.sellsProducts ?? true));
    _categoryId = widget.item?.category;
    _duration = widget.item?.durationMinutes ?? 30;
    _unit = widget.item?.unit ?? 'pc';
  }

  bool get _valid =>
      _name.text.trim().isNotEmpty &&
      (double.tryParse(_price.text.trim()) ?? -1) >= 0;

  Future<void> _save() async {
    if (!_valid) {
      setState(() => _error = 'Name and a valid price are required.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final payload = <String, dynamic>{
      'type': _isService ? 'service' : 'product',
      'name': _name.text.trim(),
      'price': double.tryParse(_price.text.trim()) ?? 0,
      'category': _categoryId,
      'description': '',
    };
    if (_isService) {
      payload['duration_minutes'] = _duration ?? 30;
      payload['requires_stock'] = false;
    } else {
      payload['cost'] = double.tryParse(_cost.text.trim());
      payload['barcode'] = _barcode.text.trim();
      payload['unit'] = _unit;
      payload['low_stock_threshold'] = int.tryParse(_threshold.text.trim()) ?? 5;
      payload['requires_stock'] = true;
    }

    try {
      final editing = widget.item != null;
      await ref.read(catalogProvider.notifier).upsertItem(payload, editingId: editing ? widget.item!.id : null);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('ApiException: ', ''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t(context).delete),
        content: Text('Remove "${widget.item!.name}" from your catalog?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t(context).cancel)),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(t(context).delete),
          ),
        ],
      ),
    );
    if (ok == true) {
      try {
        await ref.read(catalogProvider.notifier).removeItem(widget.item!.id);
        if (mounted) Navigator.pop(context);
      } catch (e) {
        setState(() => _error = e.toString().replaceFirst('ApiException: ', ''));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cats = ref.watch(catalogProvider).value?.categories ?? [];

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.92,
      maxChildSize: 0.95,
      builder: (ctx, scroll) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.item == null
                        ? (_isService ? t(context).addService : t(context).addProduct)
                        : t(context).editItem,
                    style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                if (widget.item != null)
                  IconButton(icon: const Icon(Icons.delete_outline_rounded), onPressed: _delete),
                IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(ctx)),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              controller: scroll,
              padding: const EdgeInsets.all(18),
              children: [
                // Product / Service segmented choice.
                SegmentedButton<bool>(
                  segments: [
                    ButtonSegment(value: false, label: Text(t(context).products), icon: const Icon(Icons.inventory_2_rounded)),
                    ButtonSegment(value: true, label: Text(t(context).services), icon: const Icon(Icons.spa_rounded)),
                  ],
                  selected: {_isService},
                  onSelectionChanged: widget.item == null
                      ? (s) => setState(() => _isService = s.first)
                      : null,
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _name,
                  decoration: InputDecoration(labelText: '${t(context).name} *'),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _price,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [DecimalInputFormatter()],
                        decoration: InputDecoration(labelText: '${t(context).price} *', suffixText: 'ETB'),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 10),
                    if (!_isService)
                      Expanded(
                        child: TextField(
                          controller: _cost,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: [DecimalInputFormatter()],
                          decoration: InputDecoration(
                              labelText: t(context).cost,
                              helperText: t(context).costHint,
                              helperMaxLines: 2,
                              suffixText: 'ETB'),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  value: _categoryId,
                  decoration: InputDecoration(labelText: t(context).category),
                  items: [
                    DropdownMenuItem(value: null, child: Text(t(context).uncategorized)),
                    ...cats.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))),
                  ],
                  onChanged: (v) => setState(() => _categoryId = v),
                ),
                if (!_isService) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _stock,
                          keyboardType: TextInputType.number,
                          inputFormatters: [IntInputFormatter()],
                          enabled: widget.item == null, // later via stock-adjust (E1 audit)
                          decoration: InputDecoration(labelText: t(context).stockQty),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _unit,
                          decoration: InputDecoration(labelText: t(context).unit),
                          items: const [
                            DropdownMenuItem(value: 'pc', child: Text('Piece')),
                            DropdownMenuItem(value: 'kg', child: Text('Kilogram')),
                            DropdownMenuItem(value: 'litre', child: Text('Litre')),
                          ],
                          onChanged: (v) => setState(() => _unit = v ?? 'pc'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _barcode,
                          decoration: InputDecoration(
                              labelText: t(context).barcode,
                              prefixIcon: const Icon(Icons.qr_code_rounded)),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _threshold,
                          keyboardType: TextInputType.number,
                          inputFormatters: [IntInputFormatter()],
                          decoration:
                              InputDecoration(labelText: t(context).lowStockThreshold),
                        ),
                      ),
                    ],
                  ),
                ] else ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    value: _duration,
                    decoration: InputDecoration(labelText: t(context).duration),
                    items: [15, 20, 30, 45, 60, 90, 120]
                        .map((m) => DropdownMenuItem(value: m, child: Text('$m min')))
                        .toList(),
                    onChanged: (v) => setState(() => _duration = v),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                ],
                const SizedBox(height: 22),
                FilledButton(
                  onPressed: (_valid && !_saving) ? _save : null,
                  child: _saving
                      ? const SizedBox(
                          width: 22, height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.4))
                      : Text(t(context).save),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
