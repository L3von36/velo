import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app.dart';
import '../../api/api.dart';
import '../../models/models.dart';
import '../../providers/session.dart';
import '../../providers/shop.dart';
import '../../widgets/common.dart';
import 'item_form_sheet.dart';

/// C1 — catalog list (label adapts: Products / Services / Catalog).
/// Master-detail on wide screens via item form sheets.
class CatalogScreen extends ConsumerStatefulWidget {
  const CatalogScreen({
    super.key,
    required this.catalogLabel,
    this.standalone = false,
    this.lowStockOnly = false,
  });
  final String catalogLabel;
  final bool standalone;
  final bool lowStockOnly;

  @override
  ConsumerState<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends ConsumerState<CatalogScreen> {
  final _search = TextEditingController();

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
    final tenant = session?.tenant;
    final canEdit = session?.canEditPrices ?? true;
    final width = MediaQuery.of(context).size.width;
    final theme = Theme.of(context);

    var items = catalog.value?.filtered ?? [];
    if (widget.lowStockOnly) {
      items = items.where((i) => !i.isService && i.requiresStock && i.stockQty <= i.lowStockThreshold).toList();
    }

    final body = Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: widget.standalone,
        title: Text(widget.lowStockOnly ? t(context).lowStockList : widget.catalogLabel),
        actions: [
          if (canEdit && !widget.lowStockOnly)
            IconButton(
              tooltip: t(context).categories,
              icon: const Icon(Icons.category_rounded),
              onPressed: () => _openCategories(context),
            ),
        ],
      ),
      floatingActionButton: canEdit && !widget.lowStockOnly
          ? FloatingActionButton.extended(
              heroTag: 'catalogFab',
              onPressed: () => _openForm(context),
              icon: const Icon(Icons.add_rounded),
              label: Text(
                  (tenant?.sellsServices ?? false) && !(tenant?.sellsProducts ?? true)
                      ? t(context).addService
                      : t(context).addItem),
            )
          : null,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
            child: TextField(
              controller: _search,
              decoration: InputDecoration(
                hintText: t(context).searchItemsPlain,
                prefixIcon: const Icon(Icons.search_rounded),
              ),
              onChanged: (v) => ref.read(catalogProvider.notifier).setSearch(v),
            ),
          ),
          Expanded(
            child: catalog.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => ErrorRetry(
                  message: '$e', onRetry: () => ref.read(catalogProvider.notifier).reload()),
              data: (_) {
                if (items.isEmpty) {
                  return EmptyState(
                    icon: Icons.inventory_2_rounded,
                    title: widget.lowStockOnly
                        ? t(context).allStockedUp
                        : (catalog.value?.search.isEmpty ?? true)
                            ? t(context).emptyCatalog
                            : 'No matches',
                    subtitle: widget.lowStockOnly
                        ? null
                        : (catalog.value?.search.isEmpty ?? true)
                            ? t(context).emptyCatalogHint
                            : null,
                    actionLabel:
                        (canEdit && !widget.lowStockOnly) ? t(context).addItem : null,
                    onAction: () => _openForm(context),
                  );
                }
                // Grid on wide screens, list on phones (PRD C1).
                if (width >= 700) {
                  return GridView.builder(
                    padding: const EdgeInsets.all(14),
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 240,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 2.3,
                    ),
                    itemCount: items.length,
                    itemBuilder: (ctx, i) => _WideItemCard(
                      item: items[i],
                      canEdit: canEdit,
                      onTap: () => _openForm(ctx, item: items[i]),
                    ),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 96),
                  itemCount: items.length,
                  itemBuilder: (ctx, i) {
                    final item = items[i];
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      child: ListTile(
                        onTap: canEdit ? () => _openForm(context, item: item) : null,
                        leading: CircleAvatar(
                          backgroundColor:
                              item.isService ? const Color(0xFFE8A200).withValues(alpha: 0.14) : theme.colorScheme.primaryContainer,
                          child: Icon(
                            item.isService ? Icons.spa_rounded : Icons.inventory_2_rounded,
                            color: item.isService ? const Color(0xFFE8A200) : theme.colorScheme.primary,
                            size: 20,
                          ),
                        ),
                        title: Text(item.name,
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Row(
                          children: [
                            if (item.categoryName != null) ...[
                              Flexible(
                                child: Text(item.categoryName!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.labelSmall),
                              ),
                              const SizedBox(width: 6),
                            ],
                            if (!item.isService)
                              Text(
                                item.stockQty <= 0
                                    ? t(context).outOfStock
                                    : '${_fq(item.stockQty.toDouble())} ${item.unit == 'pc' ? '' : item.unit}',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: item.stockQty <= item.lowStockThreshold
                                      ? (item.stockQty <= 0 ? theme.colorScheme.error : const Color(0xFFE8A200))
                                      : theme.colorScheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            if (item.isService && item.durationMinutes != null)
                              Text('${item.durationMinutes} min',
                                  style: theme.textTheme.labelSmall),
                          ],
                        ),
                        trailing: MoneyText(item.price, bold: true),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
    return body;
  }

  String _fq(double q) => q == q.roundToDouble() ? '${q.toInt()}' : '$q';

  Future<void> _openForm(BuildContext context, {CatalogItem? item}) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => ItemFormSheet(item: item),
    );
    ref.read(catalogProvider.notifier).reload();
  }

  Future<void> _openCategories(BuildContext context) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _CategoriesSheet(),
    );
    ref.read(catalogProvider.notifier).reload();
  }
}

// ---------------------------------------------------------------- tiles
class _WideItemCard extends StatelessWidget {
  const _WideItemCard({required this.item, required this.canEdit, required this.onTap});
  final CatalogItem item;
  final bool canEdit;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: InkWell(
        onTap: canEdit ? onTap : null,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(item.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700)),
                  ),
                  MoneyText(item.price, bold: true, color: theme.colorScheme.primary),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  if (item.categoryName != null) ...[
                    Icon(Icons.label_outline_rounded, size: 13, color: theme.colorScheme.outline),
                    const SizedBox(width: 4),
                    Text(item.categoryName!, style: theme.textTheme.labelSmall),
                    const SizedBox(width: 10),
                  ],
                  if (!item.isService)
                    Text(
                      item.stockQty <= 0
                          ? t(context).outOfStock
                          : '${item.stockQty} ${item.unit == 'pc' ? '' : item.unit}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: item.stockQty <= 0
                            ? theme.colorScheme.error
                            : item.stockQty <= item.lowStockThreshold
                                ? const Color(0xFFE8A200)
                                : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  if (item.isService && item.durationMinutes != null)
                    Text('${item.durationMinutes} min', style: theme.textTheme.labelSmall),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- categories
class _CategoriesSheet extends ConsumerStatefulWidget {
  const _CategoriesSheet();

  @override
  ConsumerState<_CategoriesSheet> createState() => _CategoriesSheetState();
}

class _CategoriesSheetState extends ConsumerState<_CategoriesSheet> {
  final _name = TextEditingController();
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final cats = ref.watch(catalogProvider).value?.categories ?? [];
    final theme = Theme.of(context);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.65,
      builder: (ctx, scroll) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Text(t(context).categories,
                      style: theme.textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w700)),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _name,
                    decoration: InputDecoration(hintText: t(context).name),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _saving
                      ? null
                      : () async {
                          if (_name.text.trim().isEmpty) return;
                          setState(() => _saving = true);
                          try {
                            await Api().createCategory(_name.text.trim());
                            _name.clear();
                            await ref.read(catalogProvider.notifier).reload();
                          } catch (e) {
                            if (ctx.mounted) {
                              ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                                  content: Text(e.toString().replaceFirst('ApiException: ', ''))));
                            }
                          } finally {
                            if (mounted) setState(() => _saving = false);
                          }
                        },
                  child: const Icon(Icons.add_rounded),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              controller: scroll,
              padding: const EdgeInsets.all(8),
              children: cats
                  .map((c) => ListTile(
                        leading: const Icon(Icons.label_outline_rounded),
                        title: Text(c.name),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('${c.itemCount} ${t(context).items}',
                                style: theme.textTheme.labelSmall),
                            IconButton(
                              icon: const Icon(Icons.delete_outline_rounded, size: 20),
                              onPressed: () async {
                                try {
                                  await Api().deleteCategory(c.id);
                                  await ref.read(catalogProvider.notifier).reload();
                                } catch (e) {
                                  if (ctx.mounted) {
                                    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                                        content: Text(
                                            e.toString().replaceFirst('ApiException: ', ''))));
                                  }
                                }
                              },
                            ),
                          ],
                        ),
                      ))
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }
}

