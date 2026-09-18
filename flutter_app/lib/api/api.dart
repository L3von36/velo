import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/models.dart';
import 'api_client.dart';

/// Thin typed wrappers over the Supabase backend.
///
/// Every table is protected by Row Level Security keyed on the signed-in
/// user's shop (current_shop_id()), which mirrors the Django tenancy model.
/// Multi-step business logic (checkout, refunds, stock, credit ledger) runs
/// in Postgres functions (RPC) so it stays atomic on flaky connections.
class Api {
  static final Api _instance = Api._();
  factory Api() => _instance;
  Api._();

  SupabaseClient get _sb => Supabase.instance.client;

  // Ethiopian phone -> synthetic login email (0911000001 -> 0911000001@velo.app)
  static String emailForPhone(String phone) {
    var digits = phone.replaceAll(RegExp(r'[^\d]'), '');
    if (digits.startsWith('251')) digits = '0${digits.substring(3)}';
    if (!digits.startsWith('0')) digits = '0$digits';
    return '$digits@velo.app';
  }

  /// Role capability matrix (PRD G3) — identical to the Django backend.
  static const Map<String, Map<String, bool>> _roleMatrix = {
    'owner': {
      'manage_settings': true, 'manage_staff': true, 'view_reports': true,
      'void_sales': true, 'apply_discount': true, 'edit_prices': true,
      'manage_customers': true, 'record_payment': true, 'manage_expenses': true,
      'view_profit': true, 'view_cost': true,
    },
    'manager': {
      'manage_settings': false, 'manage_staff': true, 'view_reports': true,
      'void_sales': true, 'apply_discount': true, 'edit_prices': true,
      'manage_customers': true, 'record_payment': true, 'manage_expenses': true,
      'view_profit': true, 'view_cost': true,
    },
    'cashier': {
      'manage_settings': false, 'manage_staff': false, 'view_reports': false,
      'void_sales': false, 'apply_discount': false, 'edit_prices': false,
      'manage_customers': true, 'record_payment': true, 'manage_expenses': false,
      'view_profit': false, 'view_cost': false,
    },
    'staff': {
      'manage_settings': false, 'manage_staff': false, 'view_reports': false,
      'void_sales': false, 'apply_discount': false, 'edit_prices': false,
      'manage_customers': true, 'record_payment': true, 'manage_expenses': false,
      'view_profit': false, 'view_cost': false,
    },
  };

  // ---------------------------------------------------------------- auth
  Future<Map<String, dynamic>> login(String phone, String password) async {
    try {
      await _sb.auth.signInWithPassword(
          email: emailForPhone(phone), password: password);
    } catch (e) {
      throw mapSupabaseError(e);
    }
    return {'access': 'supabase', 'refresh': 'supabase', 'user': _userJson};
  }

  Future<Map<String, dynamic>> signup(Map<String, dynamic> payload) async {
    final phone = '${payload['phone'] ?? ''}';
    try {
      final res = await _sb.auth.signUp(
        email: emailForPhone(phone),
        password: '${payload['password'] ?? ''}',
        data: {'name': payload['name'], 'phone': phone},
      );
      if (res.session == null) {
        throw ApiException('Account created — please verify and log in.');
      }
      // create the shop + owner staff row + default categories
      await _sb.rpc('app_create_shop', params: {
        'p_shop_name': payload['shop_name'] ?? 'My Shop',
        'p_business_type': payload['business_type'] ?? 'general',
        'p_phone': phone,
      });
    } catch (e) {
      throw mapSupabaseError(e);
    }
    return {'access': 'supabase', 'refresh': 'supabase', 'user': _userJson};
  }

  Map<String, dynamic> get _userJson {
    final u = _sb.auth.currentUser;
    return {
      'id': 0,
      'name': u?.userMetadata?['name'] ?? '',
      'phone': u?.userMetadata?['phone'] ?? '',
      'role': 'owner',
      'capabilities': _roleMatrix['owner'],
    };
  }

  Future<Map<String, dynamic>> _myStaff() async {
    final rows = await _sb
        .from('staff')
        .select('*, shop:shops(*)')
        .eq('user_id', _sb.auth.currentUser!.id)
        .eq('active', true)
        .limit(1);
    if ((rows as List).isEmpty) {
      throw ApiException('No shop found for this account.');
    }
    return (rows.first as Map).cast<String, dynamic>();
  }

  Future<Map<String, dynamic>> me() async {
    final me = await _myStaff();
    final shop = (me['shop'] as Map).cast<String, dynamic>();
    final role = '${me['role']}';
    return {
      'user': {
        'id': me['id'],
        'name': me['name'],
        'phone': me['phone'],
        'role': role,
        'capabilities': _roleMatrix[role] ?? _roleMatrix['staff'],
      },
      'tenant': _tenantJson(shop, await _btConfig(shop['business_type'] ?? 'general')),
      'branches': const [
        {'id': 1, 'name': 'Main branch', 'is_default': true},
      ],
    };
  }

  Map<String, dynamic> _tenantJson(Map<String, dynamic> shop, Map<String, dynamic> config) => {
        'id': shop['id'],
        'name': shop['name'],
        'business_type': shop['business_type'],
        'language': shop['language'] ?? 'en',
        'plan': shop['plan'] ?? 'free',
        'telebirr_number': shop['telebirr_number'] ?? '',
        'cbe_number': shop['cbe_number'] ?? '',
        'accept_telebirr': shop['accept_telebirr'] != false,
        'accept_cbe': shop['accept_cbe'] != false,
        'accept_credit': shop['accept_credit'] != false,
        'receipt_footer': shop['receipt_footer'] ?? '',
        'sells_products': true,
        'sells_services': false,
        'config': config,
      };

  Map<String, dynamic> _btJson(String key, Map<String, dynamic> c) => {
        'key': c['key'] ?? key,
        'label_en': c['label_en'] ?? key,
        'label_am': c['label_am'] ?? key,
        'catalog_label': c['catalog_label'] ?? 'Catalog',
        'sells_products': c['sells_products'] == true,
        'sells_services': c['sells_services'] == true,
        'variants': c['variants'] == true,
        'inventory': c['inventory'] == true,
        'appointments': c['appointments'] == true,
        'barcode': c['barcode'] ?? 'optional',
        'staff_commission': c['staff_commission'] == true,
        'default_categories': c['default_categories'] ?? const [],
        'icon': c['icon'] ?? 'category',
      };

  Future<Map<String, dynamic>> _btConfig(String key) async {
    final rows = await _sb
        .from('business_types')
        .select('key, config')
        .eq('key', key)
        .limit(1);
    if ((rows as List).isEmpty) return _btJson(key, {'key': key});
    return _btJson(key, (rows.first['config'] as Map).cast<String, dynamic>());
  }

  Future<List<BusinessTypeConfig>> businessTypes() async {
    final rows = await _sb.from('business_types').select('key, config').order('sort');
    return (rows as List)
        .map((e) => BusinessTypeConfig.fromJson(
            _btJson('${e['key']}', (e['config'] as Map).cast<String, dynamic>())))
        .toList();
  }

  Future<List<Map<String, dynamic>>> demoAccounts() async => const [
        {'tenant': 'Sheger Supermarket', 'phone': '0911000001', 'password': 'demo1234'},
        {'tenant': 'Merkato Fashion House', 'phone': '0911000002', 'password': 'demo1234'},
        {'tenant': 'Addis Fade Barbershop', 'phone': '0911000003', 'password': 'demo1234'},
      ];

  // ---------------------------------------------------------------- catalog
  Future<List<Category>> categories() async {
    final rows = await _sb.from('categories').select('id, name, items(count)').order('name');
    return (rows as List).map((e) {
      final counts = (e['items'] as List?) ?? const [];
      final n = counts.isEmpty ? 0 : (counts.first['count'] ?? 0);
      return Category.fromJson({
        'id': e['id'],
        'name': e['name'],
        'item_count': n is int ? n : int.tryParse('$n') ?? 0,
      });
    }).toList();
  }

  Future<Category> createCategory(String name) async {
    try {
      final row = await _sb.from('categories').insert({'name': name}).select().single();
      return Category.fromJson({'id': row['id'], 'name': row['name'], 'item_count': 0});
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<void> deleteCategory(int id) async {
    await _sb.from('categories').delete().eq('id', id);
  }

  Future<List<CatalogItem>> items({
    String? type,
    String? search,
    int? category,
    bool lowStock = false,
  }) async {
    var q = _sb.from('items').select('*, category:categories(name), variants:item_variants(*)');
    if (type != null) q = q.eq('type', type);
    if (category != null) q = q.eq('category_id', category);
    if (lowStock) {
      q = q.eq('is_active', true).eq('type', 'product')
           .filter('stock_qty', 'lte', 'low_stock_threshold');
    }
    if (search != null && search.isNotEmpty) {
      q = q.or('name.ilike.%$search%,barcode.eq.$search');
    }
    final rows = await q.order('name').limit(500);
    return (rows as List)
        .map((e) => CatalogItem.fromJson(_itemJson(e as Map)))
        .toList();
  }

  Map<String, dynamic> _itemJson(Map e) {
    final cat = e['category'];
    final vars = ((e['variants'] ?? const []) as List)
        .whereType<Map>()
        .map((v) => {
              'id': v['id'],
              'attributes': v['attributes'] ?? const {},
              'stock_qty': v['stock_qty'] ?? 0,
              'price_override': v['price_override'],
              'sku': v['sku'] ?? '',
              'barcode': v['barcode'] ?? '',
            })
        .toList();
    return {
      'id': e['id'],
      'type': e['type'] ?? 'product',
      'name': e['name'],
      'description': e['description'] ?? '',
      'price': e['price'],
      'cost': e['cost'],
      'category': e['category_id'],
      'category_name': cat is Map ? cat['name'] : null,
      'stock_qty': e['stock_qty'] ?? 0,
      'low_stock_threshold': e['low_stock_threshold'] ?? 5,
      'barcode': e['barcode'] ?? '',
      'unit': e['unit'] ?? 'pc',
      'duration_minutes': e['duration_minutes'],
      'requires_stock': e['requires_stock'] != false,
      'is_active': e['is_active'] != false,
      'is_low_stock':
          (e['type'] ?? 'product') == 'product' &&
              ((e['stock_qty'] ?? 0) as num) <= ((e['low_stock_threshold'] ?? 5) as num),
      'variants': vars,
    };
  }

  Map<String, dynamic> _itemPayload(Map<String, dynamic> payload) => {
        'type': payload['type'] ?? 'product',
        'name': payload['name'],
        if (payload['description'] != null) 'description': payload['description'],
        'price': payload['price'] ?? 0,
        if (payload['cost'] != null) 'cost': payload['cost'],
        if (payload['category'] != null) 'category_id': payload['category'],
        if (payload['stock_qty'] != null) 'stock_qty': payload['stock_qty'],
        if (payload['low_stock_threshold'] != null)
          'low_stock_threshold': payload['low_stock_threshold'],
        if (payload['barcode'] != null) 'barcode': payload['barcode'],
        if (payload['unit'] != null) 'unit': payload['unit'],
        if (payload['duration_minutes'] != null)
          'duration_minutes': payload['duration_minutes'],
        if (payload['requires_stock'] != null)
          'requires_stock': payload['requires_stock'],
        if (payload['is_active'] != null) 'is_active': payload['is_active'],
      };

  Future<CatalogItem> createItem(Map<String, dynamic> payload) async {
    try {
      final row = await _sb
          .from('items')
          .insert(_itemPayload(payload))
          .select('*, category:categories(name), variants:item_variants(*)')
          .single();
      return CatalogItem.fromJson(_itemJson(row));
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<CatalogItem> updateItem(int id, Map<String, dynamic> payload) async {
    try {
      final row = await _sb
          .from('items')
          .update(_itemPayload(payload))
          .eq('id', id)
          .select('*, category:categories(name), variants:item_variants(*)')
          .single();
      return CatalogItem.fromJson(_itemJson(row));
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<void> deleteItem(int id) => _sb.from('items').delete().eq('id', id);

  Future<int> stockAdjust(int id, Map<String, dynamic> payload) async {
    final delta = (payload['delta'] ?? payload['qty_change'] ?? 0) is num
        ? (payload['delta'] ?? payload['qty_change'] ?? 0) as num
        : num.tryParse('${payload['delta'] ?? payload['qty_change'] ?? 0}') ?? 0;
    final r = await _sb.rpc('app_stock_adjust', params: {
      'p_item': id,
      'p_delta': delta.toInt(),
      'p_reason': '${payload['reason'] ?? ''}',
    });
    return ((r as Map)['stock_qty'] ?? 0) is int
        ? (r['stock_qty'] as int)
        : int.tryParse('${r['stock_qty']}') ?? 0;
  }

  // ---------------------------------------------------------------- customers
  Future<List<Customer>> customers({String? search, bool debtors = false}) async {
    var q = _sb.from('customers').select();
    if (debtors) q = q.gt('balance', 0.009);
    if (search != null && search.isNotEmpty) {
      q = q.or('name.ilike.%$search%,phone.ilike.%$search%');
    }
    final rows = await q.order('name').limit(500);
    final list = (rows as List)
        .map((e) => Customer.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
    if (debtors) list.sort((a, b) => b.balance.compareTo(a.balance));
    return list;
  }

  Future<Customer> createCustomer(Map<String, dynamic> payload) async {
    try {
      final row = await _sb
          .from('customers')
          .insert({
            'name': payload['name'],
            if (payload['phone'] != null) 'phone': payload['phone'],
            if (payload['notes'] != null) 'notes': payload['notes'],
          })
          .select()
          .single();
      return Customer.fromJson((row as Map).cast<String, dynamic>());
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<void> deleteCustomer(int id) =>
      _sb.from('customers').delete().eq('id', id);

  Future<Map<String, dynamic>> customerDetail(int id) =>
      _sb.rpc('app_customer_detail', params: {'p_customer': id});

  Future<Map<String, dynamic>> addLedger(int id, Map<String, dynamic> payload) =>
      _sb.rpc('app_add_ledger', params: {
        'p_customer': id,
        'p_type': payload['type'] ?? 'payment',
        'p_amount': payload['amount'] ?? 0,
        'p_note': '${payload['note'] ?? ''}',
      });

  // ---------------------------------------------------------------- staff
  Future<List<StaffMember>> staff() async {
    final rows = await _sb.from('staff').select().order('id');
    // today's per-staff sales for the list badges
    final since =
        DateTime.now().toUtc().subtract(const Duration(hours: 24)).toIso8601String();
    final todayRows = await _sb
        .from('sales')
        .select('staff_id, total')
        .gte('created_at', since)
        .neq('status', 'refunded');
    final count = <int, int>{};
    final total = <int, double>{};
    for (final r in (todayRows as List)) {
      final sid = (r as Map)['staff_id'];
      if (sid is int) {
        count[sid] = (count[sid] ?? 0) + 1;
        total[sid] =
            (total[sid] ?? 0) + (double.tryParse('${r['total']}') ?? 0);
      }
    }
    return (rows as List).map((e) {
      final m = (e as Map).cast<String, dynamic>();
      final sid = m['id'] is int ? m['id'] as int : 0;
      return StaffMember.fromJson({
        ...m,
        'sales_today_count': count[sid] ?? 0,
        'sales_today_total': total[sid] ?? 0,
      });
    }).toList();
  }

  Future<StaffMember> createStaff(Map<String, dynamic> payload) async {
    try {
      final row = await _sb
          .from('staff')
          .insert({
            'name': payload['name'],
            if (payload['phone'] != null) 'phone': payload['phone'],
            'role': payload['role'] ?? 'staff',
            'commission_percent': payload['commission_percent'] ?? 0,
          })
          .select()
          .single();
      return StaffMember.fromJson((row as Map).cast<String, dynamic>());
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<StaffMember> updateStaff(int id, Map<String, dynamic> payload) async {
    try {
      final patch = <String, dynamic>{
        if (payload['name'] != null) 'name': payload['name'],
        if (payload['phone'] != null) 'phone': payload['phone'],
        if (payload['role'] != null) 'role': payload['role'],
        if (payload['commission_percent'] != null)
          'commission_percent': payload['commission_percent'],
        if (payload['active'] != null) 'active': payload['active'],
      };
      final row = await _sb
          .from('staff')
          .update(patch)
          .eq('id', id)
          .select()
          .single();
      return StaffMember.fromJson((row as Map).cast<String, dynamic>());
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  // ---------------------------------------------------------------- POS
  Future<Sale> checkout(Map<String, dynamic> payload) async {
    try {
      final r = await _sb.rpc('app_checkout', params: {'p_payload': payload});
      return Sale.fromJson((r as Map).cast<String, dynamic>());
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<List<Sale>> sales({
    String? from,
    String? to,
    int? staffId,
    String? method,
    String? search,
  }) async {
    var q = _sb.from('sales').select();
    if (from != null) q = q.gte('created_at', '${from}T00:00:00');
    if (to != null) q = q.lte('created_at', '${to}T23:59:59');
    if (staffId != null) q = q.eq('staff_id', staffId);
    if (method != null) q = q.eq('method', method);
    if (search != null && search.isNotEmpty) {
      q = q.or('customer_name.ilike.%$search%,reference.ilike.%$search%');
    }
    final rows = await q.order('created_at', ascending: false).limit(100);
    return (rows as List)
        .map((e) => Sale.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  Future<Sale> refundSale(int id, String reason) async {
    try {
      final r = await _sb
          .rpc('app_refund_sale', params: {'p_sale': id, 'p_reason': reason});
      return Sale.fromJson((r as Map).cast<String, dynamic>());
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<List<HeldSaleInfo>> heldSales() async {
    final rows =
        await _sb.from('held_sales').select().order('created_at', ascending: false);
    return (rows as List)
        .map((e) => HeldSaleInfo.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  Future<void> holdSale(Map<String, dynamic> payload) async {
    final p = Map<String, dynamic>.from(payload)..remove('label');
    await _sb.from('held_sales').insert({'label': payload['label'] ?? '', 'payload': p});
  }

  Future<void> deleteHeldSale(int id) =>
      _sb.from('held_sales').delete().eq('id', id);

  // ---------------------------------------------------------------- expenses
  Future<List<Expense>> expenses() async {
    final rows = await _sb
        .from('expenses')
        .select('*, cat:expense_categories(name)')
        .order('spent_date', ascending: false)
        .order('id', ascending: false)
        .limit(400);
    return (rows as List).map((e) {
      final m = (e as Map).cast<String, dynamic>();
      final cat = m['cat'];
      return Expense.fromJson({
        'id': m['id'],
        'amount': m['amount'],
        'note': m['note'] ?? '',
        'date': m['spent_date'],
        'category': m['category_id'],
        'category_name': cat is Map ? cat['name'] : null,
      });
    }).toList();
  }

  Future<Expense> createExpense(Map<String, dynamic> payload) async {
    try {
      final row = await _sb
          .from('expenses')
          .insert({
            'amount': payload['amount'] ?? 0,
            'note': payload['note'] ?? '',
            if (payload['category'] != null) 'category_id': payload['category'],
            'spent_date': DateTime.now().toIso8601String().substring(0, 10),
          })
          .select()
          .single();
      final m = (row as Map).cast<String, dynamic>();
      return Expense.fromJson({
        'id': m['id'],
        'amount': m['amount'],
        'note': m['note'] ?? '',
        'date': m['spent_date'],
        'category': m['category_id'],
        'category_name': null,
      });
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<List<ExpenseCategory>> expenseCategories() async {
    final rows = await _sb.from('expense_categories').select().order('name');
    return (rows as List)
        .map((e) => ExpenseCategory.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  // ---------------------------------------------------------------- reports
  Future<DashboardData> dashboard() async {
    final r = await _sb.rpc('app_dashboard');
    return DashboardData.fromJson((r as Map).cast<String, dynamic>());
  }

  Future<SalesReport> salesReport(String from, String to) async {
    final r = await _sb
        .rpc('app_sales_report', params: {'f': from, 't': to});
    return SalesReport.fromJson((r as Map).cast<String, dynamic>());
  }

  Future<List<TopItem>> bestSellers(String from, String to, {String by = 'qty'}) async {
    final r = await _sb.rpc('app_best_sellers',
        params: {'f': from, 't': to, 'by_mode': by});
    return (((r as Map)['results'] ?? const []) as List)
        .map((e) => TopItem.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  Future<List<StaffSlice>> staffPerformance(String from, String to) async {
    final r = await _sb.rpc('app_staff_performance', params: {'f': from, 't': to});
    return (((r as Map)['results'] ?? const []) as List)
        .map((e) => StaffSlice.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  Future<PnlReport> pnl(String from, String to) async {
    final r = await _sb.rpc('app_pnl', params: {'f': from, 't': to});
    return PnlReport.fromJson((r as Map).cast<String, dynamic>());
  }

  Future<Map<String, dynamic>> debtors() => _sb.rpc('app_debtors');

  // ---------------------------------------------------------------- settings
  Future<TenantInfo> updateSettings(Map<String, dynamic> payload) async {
    try {
      final me = await _myStaff();
      final shopId = me['shop_id'];
      final patch = <String, dynamic>{
        if (payload['name'] != null) 'name': payload['name'],
        if (payload['business_type'] != null)
          'business_type': payload['business_type'],
        if (payload['phone'] != null) 'phone': payload['phone'],
        if (payload['address'] != null) 'address': payload['address'],
        if (payload['telebirr_number'] != null)
          'telebirr_number': payload['telebirr_number'],
        if (payload['cbe_number'] != null) 'cbe_number': payload['cbe_number'],
        if (payload['accept_telebirr'] != null)
          'accept_telebirr': payload['accept_telebirr'],
        if (payload['accept_cbe'] != null) 'accept_cbe': payload['accept_cbe'],
        if (payload['accept_credit'] != null)
          'accept_credit': payload['accept_credit'],
        if (payload['receipt_footer'] != null)
          'receipt_footer': payload['receipt_footer'],
      };
      final row =
          await _sb.from('shops').update(patch).eq('id', shopId).select().single();
      final shopMap = (row as Map).cast<String, dynamic>();
      return TenantInfo.fromJson(
          _tenantJson(shopMap, await _btConfig(shopMap['business_type'] ?? 'general')));
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<void> updateLanguage(String lang) async {
    final me = await _myStaff();
    await _sb.from('staff').update({'language': lang}).eq('id', me['id']);
  }
}
