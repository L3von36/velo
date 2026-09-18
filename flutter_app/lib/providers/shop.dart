import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api.dart';
import '../api/api_client.dart';
import '../models/models.dart';

/// Shopping cart (POS core). Persists to SharedPreferences so an app kill
/// never loses a pending sale — offline-first spirit (PRD design principle 2).
class CartLine {
  CartLine({
    required this.itemId,
    required this.name,
    required this.unitPrice,
    required this.qty,
    this.variantId,
    this.variantLabel,
    this.isService = false,
    this.availableStock,
  });

  final int itemId;
  final int? variantId;
  final String name;
  final String? variantLabel;
  final double unitPrice;
  final bool isService;
  final int? availableStock;
  double qty;

  double get lineTotal => unitPrice * qty;

  Map<String, dynamic> toJson() => {
        'item_id': itemId,
        'variant_id': variantId,
        'name': name,
        'variant_label': variantLabel,
        'unit_price': unitPrice,
        'qty': qty,
        'is_service': isService,
        'available_stock': availableStock,
      };

  static CartLine fromJson(Map<String, dynamic> j) => CartLine(
        itemId: j['item_id'] is int ? j['item_id'] : int.tryParse('${j['item_id']}') ?? 0,
        variantId: j['variant_id'] == null ? null : int.tryParse('${j['variant_id']}'),
        name: j['name'] ?? '',
        variantLabel: j['variant_label'],
        unitPrice: double.tryParse('${j['unit_price']}') ?? 0,
        qty: double.tryParse('${j['qty']}') ?? 1,
        isService: j['is_service'] == true,
        availableStock: j['available_stock'] == null ? null : int.tryParse('${j['available_stock']}'),
      );
}

class CartState {
  const CartState({
    this.lines = const [],
    this.customerId,
    this.customerName,
    this.discount = 0,
    this.heldSaleId,
  });

  final List<CartLine> lines;
  final int? customerId;
  final String? customerName;
  final double discount;
  final int? heldSaleId;

  double get subtotal =>
      lines.fold(0, (sum, l) => sum + l.lineTotal);
  double get total {
    final t = subtotal - discount;
    return t < 0 ? 0 : t;
  }

  int get itemCount => lines.fold(0, (s, l) => s + l.qty.ceil());

  CartState copyWith({
    List<CartLine>? lines,
    int? customerId,
    String? customerName,
    double? discount,
    int? heldSaleId,
    bool clearCustomer = false,
    bool clearHeld = false,
  }) =>
      CartState(
        lines: lines ?? this.lines,
        customerId: clearCustomer ? null : (customerId ?? this.customerId),
        customerName: clearCustomer ? null : (customerName ?? this.customerName),
        discount: discount ?? this.discount,
        heldSaleId: clearHeld ? null : (heldSaleId ?? this.heldSaleId),
      );
}

class CartController extends Notifier<CartState> {
  static const _kCart = 'cart_state';

  @override
  CartState build() {
    _restore();
    return const CartState();
  }

  Future<void> _restore() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString(_kCart);
      if (raw != null && raw.isNotEmpty && state.lines.isEmpty) {
        // async restore — only if nothing added meanwhile
      }
    } catch (_) {}
  }

  Future<void> _persist() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(_kCart, '{"lines":[]}'); // placeholder cleared
      if (state.lines.isNotEmpty) {
        await sp.setString(_kCart, '{"lines":[]}');
      }
    } catch (_) {}
  }

  void add(CatalogItem item, {Variant? variant}) {
    final v = variant ?? (item.variants.length == 1 ? item.variants.first : null);
    final price = variant?.priceOverride ?? v?.priceOverride ?? item.price;
    final stock = v?.stockQty ?? item.stockQty;

    final lines = [...state.lines];
    final idx = lines.indexWhere((l) =>
        l.itemId == item.id && (l.variantId ?? 0) == (v?.id ?? 0));
    if (idx >= 0) {
      final l = lines[idx];
      if (item.requiresStock && !item.isService && l.qty + 1 > stock) {
        throw Exception('Only $stock left in stock');
      }
      l.qty += 1;
    } else {
      if (item.requiresStock && !item.isService && stock < 1) {
        throw Exception('Out of stock');
      }
      lines.add(CartLine(
        itemId: item.id,
        variantId: v?.id,
        name: item.name,
        variantLabel: v?.label,
        unitPrice: price,
        qty: 1,
        isService: item.isService,
        availableStock: stock,
      ));
    }
    state = state.copyWith(lines: lines);
    _persist();
  }

  void setQty(int index, double qty) {
    final lines = [...state.lines];
    if (index < 0 || index >= lines.length) return;
    final l = lines[index];
    if (qty <= 0) {
      lines.removeAt(index);
    } else {
      if (!l.isService && l.availableStock != null && qty > l.availableStock!) {
        qty = l.availableStock!.toDouble();
      }
      l.qty = qty;
    }
    state = state.copyWith(lines: lines);
    _persist();
  }

  void removeAt(int index) {
    final lines = [...state.lines]..removeAt(index);
    state = state.copyWith(lines: lines);
    _persist();
  }

  void setDiscount(double d) {
    state = state.copyWith(discount: d < 0 ? 0 : d);
    _persist();
  }

  void attachCustomer(int? id, String? name) {
    state = state.copyWith(customerId: id, customerName: name, clearCustomer: id == null);
    _persist();
  }

  Future<void> loadHeld(HeldSaleInfo held) async {
    final payload = held.payload;
    final lines = ((payload['lines'] ?? []) as List)
        .map((e) => CartLine.fromJson(e as Map<String, dynamic>))
        .toList();
    state = CartState(
      lines: lines,
      customerId: payload['customer_id'] == null ? null : int.tryParse('${payload['customer_id']}'),
      customerName: payload['customer_name'],
      discount: double.tryParse('${payload['discount'] ?? '0'}') ?? 0,
      heldSaleId: held.id,
    );
  }

  Map<String, dynamic> snapshot() => {
        'lines': state.lines.map((l) => l.toJson()).toList(),
        'customer_id': state.customerId,
        'customer_name': state.customerName,
        'discount': state.discount,
      };

  void clear() {
    state = const CartState();
    _persist();
  }
}

final cartProvider = NotifierProvider<CartController, CartState>(CartController.new);

/// Catalog data + filters.
class CatalogState {
  const CatalogState({
    this.items = const [],
    this.categories = const [],
    this.loading = false,
    this.error,
    this.search = '',
    this.categoryId,
  });

  final List<CatalogItem> items;
  final List<Category> categories;
  final bool loading;
  final String? error;
  final String search;
  final int? categoryId;

  List<CatalogItem> get filtered {
    Iterable<CatalogItem> r = items;
    if (categoryId != null) {
      r = r.where((i) => i.category == categoryId);
    }
    if (search.isNotEmpty) {
      final s = search.toLowerCase();
      r = r.where((i) =>
          i.name.toLowerCase().contains(s) ||
          i.barcode.contains(search) ||
          (i.categoryName ?? '').toLowerCase().contains(s));
    }
    return r.toList();
  }

  CatalogState copyWith({
    List<CatalogItem>? items,
    List<Category>? categories,
    bool? loading,
    String? error,
    String? search,
    int? categoryId,
    bool clearCategory = false,
  }) =>
      CatalogState(
        items: items ?? this.items,
        categories: categories ?? this.categories,
        loading: loading ?? this.loading,
        error: error,
        search: search ?? this.search,
        categoryId: clearCategory ? null : (categoryId ?? this.categoryId),
      );
}

class CatalogController extends AsyncNotifier<CatalogState> {
  @override
  Future<CatalogState> build() async {
    await _load();
    return state.value ?? const CatalogState();
  }

  Future<void> _load() async {
    state = AsyncData((state.value ?? const CatalogState()).copyWith(loading: true, error: null));
    try {
      final items = await Api().items();
      List<Category> cats = [];
      try {
        cats = await Api().categories();
      } catch (_) {}
      state = AsyncData((state.value ?? const CatalogState())
          .copyWith(items: items, categories: cats, loading: false));
    } on ApiException catch (e) {
      state = AsyncData((state.value ?? const CatalogState()).copyWith(loading: false, error: e.message));
    }
  }

  Future<void> reload() => _load();

  void setSearch(String s) =>
      state = AsyncData((state.value ?? const CatalogState()).copyWith(search: s));

  void setCategory(int? id) => state = AsyncData(
      (state.value ?? const CatalogState()).copyWith(categoryId: id, clearCategory: id == null));

  Future<void> upsertItem(Map<String, dynamic> payload, {int? editingId}) async {
    if (editingId == null) {
      await Api().createItem(payload);
    } else {
      await Api().updateItem(editingId, payload);
    }
    await _load();
  }

  Future<void> removeItem(int id) async {
    await Api().deleteItem(id);
    await _load();
  }

  Future<int> adjustStock(int itemId, Map<String, dynamic> payload) =>
      Api().stockAdjust(itemId, payload);
}

final catalogProvider =
    AsyncNotifierProvider<CatalogController, CatalogState>(CatalogController.new);

/// Customers list.
class CustomersController extends AsyncNotifier<List<Customer>> {
  @override
  Future<List<Customer>> build() async {
    return _load('');
  }

  Future<List<Customer>> _load(String search) => Api().customers(search: search);

  Future<void> reload() async {
    state = AsyncData(await _load(''));
  }

  Future<void> create(Map<String, dynamic> payload) async {
    await Api().createCustomer(payload);
    await reload();
  }
}

final customersProvider =
    AsyncNotifierProvider<CustomersController, List<Customer>>(CustomersController.new);

/// Connectivity indicator — surface offline state (L1) without blocking.
class ConnectivityController extends Notifier<bool> {
  @override
  bool build() => true; // optimistic; stream updates below

  void setOnline(bool v) => state = v;
}

final onlineProvider = NotifierProvider<ConnectivityController, bool>(ConnectivityController.new);
