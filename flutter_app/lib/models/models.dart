/// Typed models mirroring the backend API shapes (snake_case kept via fromJson).
library;

/// int fields arrive as JSON numbers, but PostgREST may serialize some
/// numerics as strings — parse both defensively.
int _asInt(Object? v, [int def = 0]) =>
    v is int ? v : int.tryParse('$v') ?? def;

class BusinessTypeConfig {
  BusinessTypeConfig({
    required this.key,
    required this.labelEn,
    required this.labelAm,
    required this.catalogLabel,
    required this.sellsProducts,
    required this.sellsServices,
    required this.variants,
    required this.inventory,
    required this.appointments,
    required this.barcode,
    required this.staffCommission,
    required this.defaultCategories,
    required this.icon,
  });

  final String key, labelEn, labelAm, catalogLabel, barcode, icon;
  final bool sellsProducts, sellsServices, variants, inventory, appointments, staffCommission;
  final List<String> defaultCategories;

  static BusinessTypeConfig fromJson(Map<String, dynamic> j) => BusinessTypeConfig(
        key: j['key'],
        labelEn: j['label_en'] ?? j['key'],
        labelAm: j['label_am'] ?? j['key'],
        catalogLabel: j['catalog_label'] ?? 'Catalog',
        sellsProducts: j['sells_products'] == true,
        sellsServices: j['sells_services'] == true,
        variants: j['variants'] == true,
        inventory: j['inventory'] == true,
        appointments: j['appointments'] == true,
        barcode: (j['barcode'] ?? 'optional').toString(),
        staffCommission: j['staff_commission'] == true,
        defaultCategories: (j['default_categories'] as List?)?.cast<String>() ?? const [],
        icon: (j['icon'] ?? 'category').toString(),
      );

  String label(String lang) => lang == 'am' ? labelAm : labelEn;
}

class UserAccount {
  UserAccount({
    required this.id,
    required this.name,
    required this.phone,
    required this.role,
    this.branchId,
    this.capabilities = const {},
  });

  final int id;
  final String name, phone, role;
  final int? branchId;
  final Map<String, bool> capabilities;

  bool can(String cap) => capabilities[cap] == true;

  static UserAccount fromJson(Map<String, dynamic> j) => UserAccount(
        id: j['id'] is int ? j['id'] : int.tryParse('${j['id']}') ?? 0,
        name: j['name'] ?? '',
        phone: j['phone'] ?? '',
        role: j['role'] ?? 'cashier',
        branchId: j['branch_id'] is int ? j['branch_id'] : int.tryParse('${j['branch_id']}'),
        capabilities: ((j['capabilities'] ?? {}) as Map).map((k, v) => MapEntry('$k', v == true)),
      );
}

class BranchInfo {
  BranchInfo({required this.id, required this.name, this.isDefault = false});
  final int id;
  final String name;
  final bool isDefault;
  static BranchInfo fromJson(Map<String, dynamic> j) => BranchInfo(
        id: j['id'] is int ? j['id'] : int.tryParse('${j['id']}') ?? 0,
        name: j['name'] ?? '',
        isDefault: j['is_default'] == true,
      );
}

class TenantInfo {
  TenantInfo({
    required this.id,
    required this.name,
    required this.businessType,
    required this.config,
    required this.language,
    required this.plan,
    this.telebirrNumber = '',
    this.cbeNumber = '',
    this.acceptTelebirr = true,
    this.acceptCbe = true,
    this.acceptCredit = true,
    this.receiptFooter = '',
    this.sellsProducts = true,
    this.sellsServices = false,
  });

  final int id;
  final String name, businessType, language, plan, receiptFooter;
  final String telebirrNumber, cbeNumber;
  final bool acceptTelebirr, acceptCbe, acceptCredit;
  final bool sellsProducts, sellsServices;
  final BusinessTypeConfig config;

  static TenantInfo fromJson(Map<String, dynamic> j) => TenantInfo(
        id: j['id'] is int ? j['id'] : int.tryParse('${j['id']}') ?? 0,
        name: j['name'] ?? '',
        businessType: j['business_type'] ?? 'general',
        language: j['language'] ?? 'en',
        plan: j['plan'] ?? 'free',
        telebirrNumber: j['telebirr_number'] ?? '',
        cbeNumber: j['cbe_number'] ?? '',
        acceptTelebirr: j['accept_telebirr'] != false,
        acceptCbe: j['accept_cbe'] != false,
        acceptCredit: j['accept_credit'] != false,
        receiptFooter: j['receipt_footer'] ?? '',
        sellsProducts: j['sells_products'] != false,
        sellsServices: j['sells_services'] == true,
        config: BusinessTypeConfig.fromJson((j['config'] ?? {}) as Map<String, dynamic>),
      );
}

class Category {
  Category({required this.id, required this.name, this.itemCount = 0});
  final int id;
  final String name;
  final int itemCount;
  static Category fromJson(Map<String, dynamic> j) => Category(
        id: j['id'] is int ? j['id'] : int.tryParse('${j['id']}') ?? 0,
        name: j['name'] ?? '',
        itemCount: (j['item_count'] ?? 0) is num ? (j['item_count'] as num).toInt() : int.tryParse('${j['item_count']}') ?? 0,
      );
}

class Variant {
  Variant({
    required this.id,
    required this.attributes,
    required this.stockQty,
    this.priceOverride,
    this.sku = '',
    this.barcode = '',
  });
  final int id;
  final Map<String, dynamic> attributes;
  final int stockQty;
  final double? priceOverride;
  final String sku, barcode;

  String get label => attributes.isEmpty
      ? ''
      : attributes.values.map((e) => '$e').join(' · ');

  static Variant fromJson(Map<String, dynamic> j) => Variant(
        id: j['id'] is int ? j['id'] : int.tryParse('${j['id']}') ?? 0,
        attributes: (j['attributes'] ?? {}) as Map<String, dynamic>,
        stockQty: (j['stock_qty'] ?? 0) is num ? (j['stock_qty'] as num).toInt() : 0,
        priceOverride: j['price_override'] == null ? null : double.tryParse('${j['price_override']}'),
        sku: j['sku'] ?? '',
        barcode: j['barcode'] ?? '',
      );
}

class CatalogItem {
  CatalogItem({
    required this.id,
    required this.type,
    required this.name,
    required this.price,
    this.cost,
    this.category,
    this.categoryName,
    this.description = '',
    this.stockQty = 0,
    this.lowStockThreshold = 5,
    this.barcode = '',
    this.unit = 'pc',
    this.durationMinutes,
    this.requiresStock = true,
    this.isActive = true,
    this.isLowStock = false,
    this.variants = const [],
  });

  final int id;
  final String type, name, unit, barcode, description;
  final double price;
  final double? cost;
  final int? category;
  final String? categoryName;
  final int stockQty, lowStockThreshold;
  final int? durationMinutes;
  final bool requiresStock, isActive, isLowStock;
  final List<Variant> variants;

  bool get isService => type == 'service';
  String get effectiveUnitLabel => isService ? '' : unit;

  static CatalogItem fromJson(Map<String, dynamic> j) => CatalogItem(
        id: j['id'] is int ? j['id'] : int.tryParse('${j['id']}') ?? 0,
        type: j['type'] ?? 'product',
        name: j['name'] ?? '',
        price: double.tryParse('${j['price']}') ?? 0,
        cost: j['cost'] == null ? null : double.tryParse('${j['cost']}'),
        category: j['category'] == null ? null : int.tryParse('${j['category']}'),
        categoryName: j['category_name'],
        description: j['description'] ?? '',
        stockQty: _asInt(j['stock_qty']),
        lowStockThreshold: _asInt(j['low_stock_threshold'], 5),
        barcode: j['barcode'] ?? '',
        unit: (j['unit'] ?? 'pc').toString(),
        durationMinutes: j['duration_minutes'] == null ? null : int.tryParse('${j['duration_minutes']}'),
        requiresStock: j['requires_stock'] != false,
        isActive: j['is_active'] != false,
        isLowStock: j['is_low_stock'] == true,
        variants: ((j['variants'] ?? []) as List).map((v) => Variant.fromJson(v as Map<String, dynamic>)).toList(),
      );
}

class Customer {
  Customer({
    required this.id,
    required this.name,
    this.phone = '',
    this.notes = '',
    this.balance = 0,
  });
  final int id;
  final String name, phone, notes;
  final double balance;
  bool get owes => balance > 0.009;

  static Customer fromJson(Map<String, dynamic> j) => Customer(
        id: j['id'] is int ? j['id'] : int.tryParse('${j['id']}') ?? 0,
        name: j['name'] ?? '',
        phone: j['phone'] ?? '',
        notes: j['notes'] ?? '',
        balance: double.tryParse('${j['balance']}') ?? 0,
      );
}

class LedgerEntry {
  LedgerEntry({
    required this.id,
    required this.type,
    required this.amount,
    required this.balanceAfter,
    required this.note,
    required this.createdAt,
    this.staffName,
  });
  final int id;
  final String type;
  final double amount, balanceAfter;
  final String note, createdAt;
  final String? staffName;

  static LedgerEntry fromJson(Map<String, dynamic> j) => LedgerEntry(
        id: j['id'] is int ? j['id'] : int.tryParse('${j['id']}') ?? 0,
        type: j['type'] ?? '',
        amount: double.tryParse('${j['amount']}') ?? 0,
        balanceAfter: double.tryParse('${j['balance_after']}') ?? 0,
        note: j['note'] ?? '',
        createdAt: j['created_at'] ?? '',
        staffName: j['staff_name'],
      );
}

class PaymentLine {
  PaymentLine({
    required this.method,
    required this.amount,
    this.referenceNumber = '',
    this.status = 'verified',
  });
  final String method;
  final double amount;
  final String referenceNumber, status;

  static PaymentLine fromJson(Map<String, dynamic> j) => PaymentLine(
        method: j['method'] ?? '',
        amount: double.tryParse('${j['amount']}') ?? 0,
        referenceNumber: j['reference_number'] ?? '',
        status: j['status'] ?? 'verified',
      );
}

class SaleItemLine {
  SaleItemLine({
    required this.name,
    required this.qty,
    required this.unitPrice,
    this.discount = 0,
  });
  final String name;
  final double qty, unitPrice, discount;

  static SaleItemLine fromJson(Map<String, dynamic> j) => SaleItemLine(
        name: j['item_name'] ?? j['name_snapshot'] ?? '',
        qty: double.tryParse('${j['qty']}') ?? 0,
        unitPrice: double.tryParse('${j['unit_price']}') ?? 0,
        discount: double.tryParse('${j['discount']}') ?? 0,
      );
}

class Sale {
  Sale({
    required this.id,
    required this.receiptNumber,
    required this.total,
    required this.subtotal,
    required this.createdAt,
    required this.status,
    this.discountTotal = 0,
    this.taxTotal = 0,
    this.staffName,
    this.customerName,
    this.items = const [],
    this.payments = const [],
  });
  final int id, receiptNumber;
  final double total, subtotal, discountTotal, taxTotal;
  final String createdAt, status;
  final String? staffName, customerName;
  final List<SaleItemLine> items;
  final List<PaymentLine> payments;

  static Sale fromJson(Map<String, dynamic> j) => Sale(
        id: j['id'] is int ? j['id'] : int.tryParse('${j['id']}') ?? 0,
        receiptNumber: (j['receipt_number'] ?? 0) is num ? (j['receipt_number'] as num).toInt() : 0,
        total: double.tryParse('${j['total']}') ?? 0,
        subtotal: double.tryParse('${j['subtotal']}') ?? 0,
        discountTotal: double.tryParse('${j['discount_total'] ?? '0'}') ?? 0,
        taxTotal: double.tryParse('${j['tax_total'] ?? '0'}') ?? 0,
        createdAt: j['created_at'] ?? '',
        status: j['status'] ?? 'completed',
        staffName: j['staff_name'],
        customerName: j['customer_name'],
        items: ((j['items'] ?? []) as List).map((e) => SaleItemLine.fromJson(e as Map<String, dynamic>)).toList(),
        payments: ((j['payments'] ?? []) as List).map((e) => PaymentLine.fromJson(e as Map<String, dynamic>)).toList(),
      );
}

class HeldSaleInfo {
  HeldSaleInfo({required this.id, required this.label, required this.payload, required this.createdAt});
  final int id;
  final String label, createdAt;
  final Map<String, dynamic> payload;
  static HeldSaleInfo fromJson(Map<String, dynamic> j) => HeldSaleInfo(
        id: j['id'] is int ? j['id'] : int.tryParse('${j['id']}') ?? 0,
        label: j['label'] ?? '',
        payload: (j['payload'] ?? {}) as Map<String, dynamic>,
        createdAt: j['created_at'] ?? '',
      );
}

class StaffMember {
  StaffMember({
    required this.id,
    required this.name,
    required this.phone,
    required this.role,
    this.commissionPercent = 0,
    this.active = true,
    this.branchId,
    this.salesTodayCount = 0,
    this.salesTodayTotal = 0,
  });
  final int id;
  final String name, phone, role;
  final double commissionPercent, salesTodayTotal;
  final bool active;
  final int? branchId;
  final int salesTodayCount;

  static StaffMember fromJson(Map<String, dynamic> j) => StaffMember(
        id: j['id'] is int ? j['id'] : int.tryParse('${j['id']}') ?? 0,
        name: j['name'] ?? '',
        phone: j['phone'] ?? '',
        role: j['role'] ?? 'staff',
        commissionPercent: double.tryParse('${j['commission_percent'] ?? '0'}') ?? 0,
        active: j['active'] != false,
        branchId: j['branch'] == null ? null : int.tryParse('${j['branch']}'),
        salesTodayCount: (j['sales_today_count'] ?? 0) is num ? (j['sales_today_count'] as num).toInt() : 0,
        salesTodayTotal: double.tryParse('${j['sales_today_total'] ?? '0'}') ?? 0,
      );
}

class Expense {
  Expense({
    required this.id,
    required this.amount,
    required this.note,
    required this.date,
    this.categoryName,
    this.categoryId,
  });
  final int id;
  final double amount;
  final String note, date;
  final String? categoryName;
  final int? categoryId;

  static Expense fromJson(Map<String, dynamic> j) => Expense(
        id: j['id'] is int ? j['id'] : int.tryParse('${j['id']}') ?? 0,
        amount: double.tryParse('${j['amount']}') ?? 0,
        note: j['note'] ?? '',
        date: j['date'] ?? '',
        categoryName: j['category_name'],
        categoryId: j['category'] == null ? null : int.tryParse('${j['category']}'),
      );
}

class ExpenseCategory {
  ExpenseCategory({required this.id, required this.name});
  final int id;
  final String name;
  static ExpenseCategory fromJson(Map<String, dynamic> j) => ExpenseCategory(
        id: j['id'] is int ? j['id'] : int.tryParse('${j['id']}') ?? 0,
        name: j['name'] ?? '',
      );
}

// ------------------------------------------------------------- reports
class DashboardData {
  DashboardData({
    required this.todayTotal,
    required this.todayCount,
    required this.yesterdayTotal,
    required this.weekTotal,
    required this.lowStockCount,
    required this.topItems,
    this.trendPct,
  });
  final double todayTotal, yesterdayTotal, weekTotal;
  final int todayCount, lowStockCount;
  final double? trendPct;
  final List<TopItem> topItems;

  static DashboardData fromJson(Map<String, dynamic> j) {
    final today = (j['today'] ?? {}) as Map<String, dynamic>;
    return DashboardData(
      todayTotal: double.tryParse('${today['total'] ?? '0'}') ?? 0,
      todayCount: (today['count'] ?? 0) is num ? (today['count'] as num).toInt() : 0,
      yesterdayTotal: double.tryParse('${today['yesterday_total'] ?? '0'}') ?? 0,
      weekTotal: double.tryParse('${j['week_total'] ?? '0'}') ?? 0,
      lowStockCount: (j['low_stock_count'] ?? 0) is num ? (j['low_stock_count'] as num).toInt() : 0,
      topItems: ((j['top_items'] ?? []) as List)
          .map((e) => TopItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      trendPct: today['trend_pct'] == null ? null : double.tryParse('${today['trend_pct']}'),
    );
  }
}

class TopItem {
  TopItem({required this.name, required this.qty, required this.revenue});
  final String name;
  final double qty, revenue;
  static TopItem fromJson(Map<String, dynamic> j) => TopItem(
        name: j['name'] ?? '',
        qty: double.tryParse('${j['qty']}') ?? 0,
        revenue: double.tryParse('${j['revenue']}') ?? 0,
      );
}

class SalesReport {
  SalesReport({
    required this.total,
    required this.count,
    required this.average,
    required this.series,
    required this.byMethod,
    required this.byStaff,
  });
  final double total, average;
  final int count;
  final List<SeriesPoint> series;
  final List<MethodSlice> byMethod;
  final List<StaffSlice> byStaff;

  static SalesReport fromJson(Map<String, dynamic> j) => SalesReport(
        total: double.tryParse('${j['total'] ?? '0'}') ?? 0,
        count: (j['count'] ?? 0) is num ? (j['count'] as num).toInt() : 0,
        average: double.tryParse('${j['average'] ?? '0'}') ?? 0,
        series: ((j['series'] ?? []) as List).map((e) => SeriesPoint.fromJson(e as Map<String, dynamic>)).toList(),
        byMethod: ((j['by_method'] ?? []) as List).map((e) => MethodSlice.fromJson(e as Map<String, dynamic>)).toList(),
        byStaff: ((j['by_staff'] ?? []) as List).map((e) => StaffSlice.fromJson(e as Map<String, dynamic>)).toList(),
      );
}

class SeriesPoint {
  SeriesPoint({required this.date, required this.total, required this.count});
  final String date;
  final double total;
  final int count;
  static SeriesPoint fromJson(Map<String, dynamic> j) => SeriesPoint(
        date: j['date'] ?? '',
        total: double.tryParse('${j['total']}') ?? 0,
        count: (j['count'] ?? 0) is num ? (j['count'] as num).toInt() : 0,
      );
}

class MethodSlice {
  MethodSlice({required this.method, required this.total, required this.count});
  final String method;
  final double total;
  final int count;
  static MethodSlice fromJson(Map<String, dynamic> j) => MethodSlice(
        method: j['method'] ?? '',
        total: double.tryParse('${j['total']}') ?? 0,
        count: (j['count'] ?? 0) is num ? (j['count'] as num).toInt() : 0,
      );
}

class StaffSlice {
  StaffSlice({required this.staff, required this.total, required this.count});
  final String staff;
  final double total;
  final int count;
  static StaffSlice fromJson(Map<String, dynamic> j) => StaffSlice(
        staff: j['staff'] ?? '—',
        total: double.tryParse('${j['total']}') ?? 0,
        count: (j['count'] ?? 0) is num ? (j['count'] as num).toInt() : 0,
      );
}

class PnlReport {
  PnlReport({
    required this.revenue,
    required this.cogs,
    required this.grossProfit,
    required this.expenseTotal,
    required this.netProfit,
    required this.expenses,
    this.estimateWarning = false,
  });
  final double revenue, cogs, grossProfit, expenseTotal, netProfit;
  final bool estimateWarning;
  final List<CategorySlice> expenses;

  static PnlReport fromJson(Map<String, dynamic> j) => PnlReport(
        revenue: double.tryParse('${j['revenue'] ?? '0'}') ?? 0,
        cogs: double.tryParse('${j['cogs'] ?? '0'}') ?? 0,
        grossProfit: double.tryParse('${j['gross_profit'] ?? '0'}') ?? 0,
        expenseTotal: double.tryParse('${j['expense_total'] ?? '0'}') ?? 0,
        netProfit: double.tryParse('${j['net_profit'] ?? '0'}') ?? 0,
        expenses: ((j['expenses'] ?? []) as List).map((e) => CategorySlice.fromJson(e as Map<String, dynamic>)).toList(),
        estimateWarning: j['estimate_warning'] == true,
      );
}

class CategorySlice {
  CategorySlice({required this.category, required this.total});
  final String category;
  final double total;
  static CategorySlice fromJson(Map<String, dynamic> j) => CategorySlice(
        category: j['category'] ?? 'Other',
        total: double.tryParse('${j['total']}') ?? 0,
      );
}
