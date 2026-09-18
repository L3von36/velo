"""Seed demo tenants with realistic Ethiopian business data.

Creates 3 demo tenants (all password demo1234):
  +251911000001  Sheger Supermarket      (supermarket)
  +251911000002  Merkato Fashion House   (clothing)
  +251911000003  Addis Fade Barbershop   (barbershop)
"""
import random
from datetime import timedelta
from decimal import Decimal

from django.contrib.auth.hashers import make_password
from django.core.management.base import BaseCommand
from django.utils import timezone

from core.business_types import business_config
from core.models import (Branch, CatalogItem, Category, Customer,
                         CustomerLedger, Expense, ExpenseCategory, ItemVariant,
                         Payment, Sale, SaleItem, StockMovement, Tenant, User)

random.seed(42)

CATALOG_SEED = {
    'supermarket': [
        ('Coca-Cola 330ml', 'Beverages', 22.00, 17.00, 'pc', 120, 20),
        ('Coca-Cola 1.5L', 'Beverages', 68.00, 55.00, 'pc', 48, 10),
        ('Pepsi 500ml', 'Beverages', 35.00, 27.00, 'pc', 60, 12),
        ('Ambassa Water 1L', 'Beverages', 20.00, 14.00, 'pc', 90, 24),
        ('Dashen Beer', 'Beverages', 55.00, 45.00, 'pc', 72, 24),
        ('Biscuit Kolo Mix', 'Snacks', 30.00, 22.00, 'pc', 40, 10, None),
        ('Popcorn 100g', 'Snacks', 18.00, 11.00, 'pc', 55, 15),
        ('Shuro Powder 500g', 'Grains & Pulses', 95.00, 72.00, 'pc', 25, 8),
        ('Berbere 250g', 'Grains & Pulses', 110.00, 84.00, 'pc', 30, 8),
        ('Shelfer Teff 5kg', 'Grains & Pulses', 520.00, 430.00, 'pc', 14, 4),
        ('Milk 1L Mama', 'Dairy', 78.00, 62.00, 'litre', 35, 10),
        ('Yogurt 500g', 'Dairy', 92.00, 70.00, 'pc', 18, 6),
        ('Metata 1kg', 'Grains & Pulses', 45.00, 33.00, 'kg', 22, 6),
        ('Detergent 2kg', 'Household', 240.00, 190.00, 'pc', 16, 5),
        ('Toilet Paper 4pk', 'Household', 88.00, 66.00, 'pc', 44, 12),
        ('Soap Excel 125g', 'Household', 25.00, 18.00, 'pc', 80, 20),
        ('Cooking Oil 1L', 'Household', 320.00, 275.00, 'litre', 26, 8),
        ('Sugar 1kg', 'Grains & Pulses', 78.00, 66.00, 'kg', 60, 15),
        ('Pasta 500g', 'Grains & Pulses', 48.00, 38.00, 'pc', 50, 12),
        ('Injera Pack 5', 'Grains & Pulses', 120.00, 88.00, 'pc', 12, 5),
    ],
    'clothing': [
        ('Men T-Shirt Cotton', 'Men', 450.00, 300.00, 'pc', 30, 6, ['size:S,M,L,XL', 'color:Black,White,Blue']),
        ('Men Jeans Slim', 'Men', 1250.00, 850.00, 'pc', 18, 5, ['size:30,32,34,36', 'color:Blue,Black']),
        ('Women Kemis Modern', 'Women', 1800.00, 1250.00, 'pc', 12, 4, ['size:S,M,L', 'color:White,Green']),
        ('Women Netela Scarf', 'Women', 350.00, 210.00, 'pc', 40, 10, ['color:White,Beige,Pink']),
        ('Kids Hoodie', 'Kids', 520.00, 340.00, 'pc', 24, 6, ['size:4Y,6Y,8Y', 'color:Red,Grey']),
        ('Kids School Uniform', 'Kids', 680.00, 470.00, 'pc', 35, 10, ['size:6Y,8Y,10Y,12Y']),
        ('Sport Sneakers', 'Shoes & Accessories', 1600.00, 1100.00, 'pc', 15, 5, ['size:39,40,41,42,43', 'color:Black,White']),
        ('Leather Belt', 'Shoes & Accessories', 320.00, 180.00, 'pc', 28, 8, ['color:Black,Brown']),
        ('Winter Jacket', 'Men', 2400.00, 1700.00, 'pc', 8, 3, ['size:M,L,XL']),
        ('Traditional Habesha Suit', 'Men', 4500.00, 3200.00, 'pc', 6, 2, ['size:M,L,XL']),
    ],
    'barbershop': [
        ('Haircut (Fade)', 'Haircut', 150.00, None, None, None, 0, None),
        ('Haircut (Classic)', 'Haircut', 120.00, None, None, None, 0, None),
        ('Kids Haircut', 'Haircut', 90.00, None, None, None, 0, None),
        ('Beard Trim', 'Beard trim', 70.00, None, None, None, 0, None),
        ('Beard Sculpt & Oil', 'Beard trim', 130.00, None, None, None, 0, None),
        ('Hot Towel Shave', 'Shave', 100.00, None, None, None, 0, None),
        ('Hair Wash & Style', 'Hair treatment', 200.00, None, None, None, 0, None),
        ('Color & Touch-up', 'Hair treatment', 450.00, None, None, None, 0, None),
        ('Shampoo Sale 250ml', 'Retail products', 180.00, 110.00, 'pc', 20, 5, None),
    ],
}

CUSTOMER_NAMES = ['Abebe Kebede', 'Tigist Alemu', 'Dawit Haile', 'Meron Tadesse',
                  'Yonas Girma', 'Hanna Bekele', 'Solomon Tesfaye', 'Rahel Mekonnen',
                  'Biruk Assefa', 'Lidya Solomon', 'Mulugeta Negash', 'Selamawit Fikru',
                  'Getachew Demissie', 'Tsion Hagos', 'Fikremariam Wolde', 'Genet Ayele']


class Command(BaseCommand):
    help = 'Seed demo tenants with realistic data'

    def handle(self, *args, **options):
        if User.objects.filter(phone='0911000001').exists():
            self.stdout.write('Demo data already seeded — skipping.')
            return

        self._tenant_supermarket()
        self._tenant_clothing()
        self._tenant_barbershop()
        self.stdout.write(self.style.SUCCESS('Seeded 3 demo tenants.'))

    # ------------------------------------------------------------- helpers
    def _base_tenant(self, name, btype, owner_name, phone, telebirr):
        cfg = business_config(btype)
        tenant = Tenant.objects.create(
            name=name, business_type=btype,
            sells_products=cfg['sells_products'], sells_services=cfg['sells_services'],
            phone=phone, address='Bole Road, Addis Ababa', telebirr_number=telebirr,
            cbe_number='1000 2345 6789',
        )
        branch = Branch.objects.create(tenant=tenant, name='Main branch',
                                       address='Bole Road, Addis Ababa', is_default=True)
        owner = User.objects.create_user(
            phone=phone, password='demo1234', name=owner_name,
            role='owner', tenant=tenant, branch=branch)
        cashier = User.objects.create_user(
            phone=f'09{random.randint(10, 99)}{random.randint(100000, 999999)}',
            password='demo1234', name=random.choice(['Keleab Tewolde', 'Samuel Molla', 'Bethel Girma']),
            role='cashier', tenant=tenant, branch=branch)
        for i, c in enumerate(cfg['default_categories']):
            Category.objects.create(tenant=tenant, name=c, sort_order=i)
        for i, c in enumerate(['Rent', 'Salaries', 'Utilities', 'Supplies', 'Other']):
            ExpenseCategory.objects.create(tenant=tenant, name=c)
        return tenant, branch, owner, cashier

    def _mk_items(self, tenant):
        items = []
        for raw in CATALOG_SEED[tenant.business_type]:
            row = (*raw, None) if len(raw) == 7 else raw
            name, cat, price, cost, unit, stock, threshold, variant_spec = row
            category = Category.objects.filter(tenant=tenant, name=cat).first()
            is_service = cost is None and unit is None
            item = CatalogItem.objects.create(
                tenant=tenant, type='service' if is_service else 'product',
                category=category, name=name,
                price=Decimal(str(price)), cost=Decimal(str(cost)) if cost else None,
                unit=unit or '', requires_stock=not is_service,
                low_stock_threshold=threshold,
                barcode=f'{random.randint(100000000000, 999999999999)}' if not is_service else '',
                duration_minutes=random.choice([15, 20, 30, 45]) if is_service else None,
            )
            if is_service:
                items.append((item, None))
                continue
            if variant_spec:
                attrs_list = [{}]
                for spec in variant_spec:
                    key, vals = spec.split(':')
                    attrs_list = [{**a, key: v} for a in attrs_list for v in vals.split(',')]
                for attrs in attrs_list:
                    v = ItemVariant.objects.create(
                        item=item, attributes=attrs,
                        stock_qty=max(0, stock // len(attrs_list) + random.randint(-2, 2)))
                    items.append((item, v))
            else:
                v = ItemVariant.objects.create(item=item, attributes={}, stock_qty=stock)
                items.append((item, v))
            StockMovement.objects.create(tenant=tenant, item=item, variant=item.variants.first(),
                                         delta_qty=stock, reason='initial', reference_type='initial')
        return items

    def _make_sales(self, tenant, branch, staff_users, items, days=14, per_day=(4, 12)):
        customers = []
        for i, name in enumerate(random.sample(CUSTOMER_NAMES, 10)):
            c = Customer.objects.create(
                tenant=tenant, name=name,
                phone=f'09{random.randint(10, 99)}{random.randint(100000, 999999)}')
            customers.append(c)

        now = timezone.localtime()
        receipt = 0
        for d in range(days, 0, -1):
            day = now - timedelta(days=d)
            for _ in range(random.randint(*per_day)):
                receipt += 1
                created = day.replace(hour=random.randint(8, 20), minute=random.randint(0, 59))
                staff = random.choice(staff_users)
                n_lines = random.randint(1, 4)
                chosen = random.sample(items, min(n_lines, len(items)))
                subtotal = Decimal('0.00')
                cogs = Decimal('0.00')
                sale = Sale(tenant=tenant, branch=branch, staff=staff,
                            customer=random.choice(customers) if random.random() < 0.6 else None,
                            receipt_number=receipt, created_at=created)
                sitems = []
                for item, variant in chosen:
                    price = variant.effective_price if variant and variant.price_override is not None else item.price
                    if item.unit in ('kg', 'litre'):
                        qty = Decimal(str(random.choice([0.5, 1, 1.5, 2, 2.5])))
                    else:
                        qty = Decimal(random.randint(1, 3))
                    if item.type == 'product' and variant and variant.stock_qty < qty:
                        continue
                    line = (price * qty).quantize(Decimal('0.01'))
                    subtotal += line
                    cogs += (item.cost or Decimal('0.00')) * qty
                    sitems.append((item, variant, qty, price))
                if not sitems:
                    continue
                discount = Decimal('0.00')
                if random.random() < 0.15:
                    discount = (subtotal * Decimal('0.05')).quantize(Decimal('0.01'))
                total = (subtotal - discount).quantize(Decimal('0.01'))
                sale.subtotal = subtotal
                sale.discount_total = discount
                sale.total = total
                sale.save()
                for item, variant, qty, price in sitems:
                    SaleItem.objects.create(sale=sale, item=item, variant=variant,
                                            name_snapshot=item.name, qty=qty,
                                            unit_price=price, cost_at_sale=(item.cost or Decimal('0.00')) * qty)
                    if item.type == 'product' and variant:
                        variant.stock_qty = max(0, variant.stock_qty - qty)
                        variant.save(update_fields=['stock_qty'])
                        StockMovement.objects.create(tenant=tenant, branch=branch, item=item,
                                                     variant=variant, delta_qty=-qty, reason='sale',
                                                     reference_type='sale', staff=staff,
                                                     created_at=created)
                method = random.choices(['cash', 'telebirr', 'cbe', 'credit'], weights=[55, 25, 12, 8])[0]
                if method == 'credit' and sale.customer:
                    Payment.objects.create(sale=sale, method='credit', amount=total, status='verified')
                    sale.customer.balance = (sale.customer.balance + total).quantize(Decimal('0.01'))
                    sale.customer.save(update_fields=['balance'])
                    CustomerLedger.objects.create(tenant=tenant, customer=sale.customer,
                                                  type='charge', amount=total,
                                                  balance_after=sale.customer.balance,
                                                  note=f'Credit sale #{receipt}', staff=staff, sale=sale,
                                                  created_at=created)
                else:
                    Payment.objects.create(sale=sale, method=method, amount=total, status='verified')

        # A couple of expenses
        for d in (2, 7, 12):
            date = (now - timedelta(days=d)).date()
            Expense.objects.create(tenant=tenant, branch=branch,
                                   category=ExpenseCategory.objects.filter(tenant=tenant)[d % 5 - 1],
                                   amount=Decimal(random.choice([1500, 2500, 4000, 800])),
                                   note='Demo expense', date=date)
        # One manual ledger payment for a debtor
        debtor = Customer.objects.filter(tenant=tenant, balance__gt=0).first()
        if debtor:
            pay = (debtor.balance * Decimal('0.3')).quantize(Decimal('0.01'))
            debtor.balance = (debtor.balance - pay).quantize(Decimal('0.01'))
            debtor.save(update_fields=['balance'])
            CustomerLedger.objects.create(tenant=tenant, customer=debtor, type='payment',
                                          amount=pay, balance_after=debtor.balance,
                                          note='Partial payment', staff=staff_users[0])

    # ------------------------------------------------------------- tenants
    def _tenant_supermarket(self):
        tenant, branch, owner, cashier = self._base_tenant(
            'Sheger Supermarket', 'supermarket', 'Alemayehu Worku', '0911000001', '0911000001')
        items = self._mk_items(tenant)
        self._make_sales(tenant, branch, [owner, cashier], items, days=14, per_day=(6, 14))

    def _tenant_clothing(self):
        tenant, branch, owner, cashier = self._base_tenant(
            'Merkato Fashion House', 'clothing', 'Sara Nuru', '0911000002', '0911000002')
        items = self._mk_items(tenant)
        self._make_sales(tenant, branch, [owner, cashier], items, days=14, per_day=(3, 8))

    def _tenant_barbershop(self):
        tenant, branch, owner, cashier = self._base_tenant(
            'Addis Fade Barbershop', 'barbershop', 'Yohannes Bekele', '0911000003', '0911000003')
        barber = User.objects.create_user(
            phone='0934711204', password='demo1234', name='Mikiyas Tadesse',
            role='staff', tenant=tenant, branch=branch,
            commission_percent=Decimal('40.00'))
        tenant.cashier = cashier
        items = self._mk_items(tenant)
        self._make_sales(tenant, branch, [owner, barber], items, days=10, per_day=(5, 11))
