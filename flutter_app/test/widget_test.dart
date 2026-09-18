import 'package:flutter_test/flutter_test.dart';
import 'package:velo/api/api.dart';
import 'package:velo/models/models.dart';

void main() {
  test('phone -> synthetic Supabase login email mapping', () {
    expect(Api.emailForPhone('0911000001'), '0911000001@velo.app');
    expect(Api.emailForPhone('+251 911 000 002'), '0911000002@velo.app');
    expect(Api.emailForPhone('251911000003'), '0911000003@velo.app');
    expect(Api.emailForPhone('911-000-004'), '0911000004@velo.app');
  });

  test('BusinessTypeConfig parses snake_case json', () {
    final c = BusinessTypeConfig.fromJson({
      'key': 'supermarket',
      'label_en': 'Supermarket',
      'label_am': 'ሱፈርማርኬት',
      'sells_products': true,
      'variants': false,
      'default_categories': ['Beverages'],
      'barcode': 'required',
    });
    expect(c.key, 'supermarket');
    expect(c.label('am'), 'ሱፈርማርኬት');
    expect(c.sellsProducts, true);
    expect(c.defaultCategories, ['Beverages']);
  });

  test('models tolerate numeric-as-string from PostgREST', () {
    final item = CatalogItem.fromJson({
      'id': '12',
      'type': 'product',
      'name': 'Coca-Cola 500ml',
      'price': '45.00',
      'stock_qty': '120',
      'is_low_stock': false,
    });
    expect(item.price, 45.0);
    expect(item.stockQty, 120);
    expect(item.isService, false);
  });
}
