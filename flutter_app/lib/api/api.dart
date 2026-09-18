import '../models/models.dart';
import 'api_client.dart';

/// Thin typed wrappers over every backend endpoint.
class Api {
  static final Api _instance = Api._();
  factory Api() => _instance;
  Api._();

  final _c = ApiClient.I;

  // ---------------------------------------------------------------- auth
  Future<Map<String, dynamic>> login(String phone, String password) =>
      _c.post('/auth/login', data: {'phone': phone, 'password': password});

  Future<Map<String, dynamic>> signup(Map<String, dynamic> payload) =>
      _c.post('/auth/signup', data: payload);

  Future<Map<String, dynamic>> me() => _c.get('/me');

  Future<List<BusinessTypeConfig>> businessTypes() async {
    final d = await _c.get('/business-types');
    return ((d['results'] ?? []) as List)
        .map((e) => BusinessTypeConfig.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<Map<String, dynamic>>> demoAccounts() async {
    final d = await _c.get('/demo-accounts');
    return ((d['results'] ?? []) as List).cast<Map<String, dynamic>>();
  }

  // ---------------------------------------------------------------- catalog
  Future<List<Category>> categories() async {
    final d = await _c.get('/categories');
    return ((d['results'] ?? d) is List ? (d['results'] ?? d) as List : const [])
        .map((e) => Category.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Category> createCategory(String name) async {
    final d = await _c.post('/categories', data: {'name': name});
    return Category.fromJson(d);
  }

  Future<void> deleteCategory(int id) => _c.delete('/categories/$id');

  Future<List<CatalogItem>> items({
    String? type,
    String? search,
    int? category,
    bool lowStock = false,
  }) async {
    final q = <String, dynamic>{'page_size': 500};
    if (type != null) q['type'] = type;
    if (search != null && search.isNotEmpty) q['search'] = search;
    if (category != null) q['category'] = category;
    if (lowStock) q['low_stock'] = '1';
    final d = await _c.get('/items', query: q);
    return ((d['results'] ?? []) as List)
        .map((e) => CatalogItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<CatalogItem> createItem(Map<String, dynamic> payload) async {
    final d = await _c.post('/items', data: payload);
    return CatalogItem.fromJson(d);
  }

  Future<CatalogItem> updateItem(int id, Map<String, dynamic> payload) async {
    final d = await _c.patch('/items/$id', data: payload);
    return CatalogItem.fromJson(d);
  }

  Future<void> deleteItem(int id) => _c.delete('/items/$id');

  Future<int> stockAdjust(int id, Map<String, dynamic> payload) async {
    final d = await _c.post('/items/$id/stock_adjust', data: payload);
    return (d['stock_qty'] ?? 0) is num ? (d['stock_qty'] as num).toInt() : 0;
  }

  // ---------------------------------------------------------------- customers
  Future<List<Customer>> customers({String? search, bool debtors = false}) async {
    final q = <String, dynamic>{};
    if (search != null && search.isNotEmpty) q['search'] = search;
    if (debtors) q['debtors'] = '1';
    final d = await _c.get('/customers', query: q);
    return ((d['results'] ?? []) as List)
        .map((e) => Customer.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Customer> createCustomer(Map<String, dynamic> payload) async {
    final d = await _c.post('/customers', data: payload);
    return Customer.fromJson(d);
  }

  Future<void> deleteCustomer(int id) => _c.delete('/customers/$id');

  Future<Map<String, dynamic>> customerDetail(int id) => _c.get('/customers/$id/detail');

  Future<Map<String, dynamic>> addLedger(int id, Map<String, dynamic> payload) =>
      _c.post('/customers/$id/ledger', data: payload);

  // ---------------------------------------------------------------- staff
  Future<List<StaffMember>> staff() async {
    final d = await _c.get('/staff');
    return ((d['results'] ?? []) as List)
        .map((e) => StaffMember.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<StaffMember> createStaff(Map<String, dynamic> payload) async {
    final d = await _c.post('/staff', data: payload);
    return StaffMember.fromJson(d);
  }

  Future<StaffMember> updateStaff(int id, Map<String, dynamic> payload) async {
    final d = await _c.patch('/staff/$id', data: payload);
    return StaffMember.fromJson(d);
  }

  // ---------------------------------------------------------------- POS
  Future<Sale> checkout(Map<String, dynamic> payload) async {
    final d = await _c.post('/checkout', data: payload);
    return Sale.fromJson(d);
  }

  Future<List<Sale>> sales({
    String? from,
    String? to,
    int? staffId,
    String? method,
    String? search,
  }) async {
    final q = <String, dynamic>{'page_size': 100};
    if (from != null) q['date_from'] = from;
    if (to != null) q['date_to'] = to;
    if (staffId != null) q['staff_id'] = staffId;
    if (method != null) q['method'] = method;
    if (search != null && search.isNotEmpty) q['search'] = search;
    final d = await _c.get('/sales', query: q);
    return ((d['results'] ?? []) as List)
        .map((e) => Sale.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Sale> refundSale(int id, String reason) async {
    final d = await _c.post('/sales/$id/refund', data: {'reason': reason});
    return Sale.fromJson(d);
  }

  Future<List<HeldSaleInfo>> heldSales() async {
    final d = await _c.get('/held-sales');
    return ((d['results'] ?? []) as List)
        .map((e) => HeldSaleInfo.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> holdSale(Map<String, dynamic> payload) =>
      _c.post('/held-sales', data: payload);

  Future<void> deleteHeldSale(int id) => _c.delete('/held-sales/$id');

  // ---------------------------------------------------------------- expenses
  Future<List<Expense>> expenses() async {
    final d = await _c.get('/expenses');
    return ((d['results'] ?? []) as List)
        .map((e) => Expense.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Expense> createExpense(Map<String, dynamic> payload) async {
    final d = await _c.post('/expenses', data: payload);
    return Expense.fromJson(d);
  }

  Future<List<ExpenseCategory>> expenseCategories() async {
    final d = await _c.get('/expense-categories');
    return ((d['results'] ?? []) as List)
        .map((e) => ExpenseCategory.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ---------------------------------------------------------------- reports
  Future<DashboardData> dashboard() async =>
      DashboardData.fromJson(await _c.get('/reports/dashboard'));

  Future<SalesReport> salesReport(String from, String to) async =>
      SalesReport.fromJson(await _c.get('/reports/sales', query: {'from': from, 'to': to}));

  Future<List<TopItem>> bestSellers(String from, String to, {String by = 'qty'}) async {
    final d = await _c.get('/reports/best-sellers', query: {'from': from, 'to': to, 'by': by});
    return ((d['results'] ?? []) as List)
        .map((e) => TopItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<StaffSlice>> staffPerformance(String from, String to) async {
    final d = await _c.get('/reports/staff-performance', query: {'from': from, 'to': to});
    return ((d['results'] ?? []) as List)
        .map((e) => StaffSlice.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<PnlReport> pnl(String from, String to) async =>
      PnlReport.fromJson(await _c.get('/reports/pnl', query: {'from': from, 'to': to}));

  Future<Map<String, dynamic>> debtors() => _c.get('/reports/debtors');

  // ---------------------------------------------------------------- settings
  Future<TenantInfo> updateSettings(Map<String, dynamic> payload) async {
    final d = await _c.patch('/settings', data: payload);
    return TenantInfo.fromJson(d);
  }

  Future<void> updateLanguage(String lang) =>
      _c.patch('/me', data: {'language': lang});
}
