"""Business-type configuration matrix — PRD §2.

Stored as data, not hardcoded UI branches: every screen reads this config
to decide labels, which modules are visible, and which fields matter.
"""
from django.utils.text import format_lazy  # noqa: F401 (keep import light)

BUSINESS_TYPES = {
    'clothing': {
        'key': 'clothing',
        'label_en': 'Clothing shop',
        'label_am': 'የልብስ ሱቅ',
        'icon': 'checkroom',
        'catalog_label': 'Products',
        'sells_products': True,
        'sells_services': False,
        'variants': True,
        'variant_attributes': ['size', 'color'],
        'inventory': True,
        'appointments': False,
        'barcode': 'optional',
        'expiry_tracking': False,
        'staff_commission': False,
        'default_categories': ['Men', 'Women', 'Kids', 'Shoes & Accessories'],
    },
    'shoes': {
        'key': 'shoes',
        'label_en': 'Shoe shop',
        'label_am': 'የጫማ ሱቅ',
        'icon': 'ice_skating',
        'catalog_label': 'Products',
        'sells_products': True,
        'sells_services': False,
        'variants': True,
        'variant_attributes': ['size', 'color'],
        'inventory': True,
        'appointments': False,
        'barcode': 'optional',
        'expiry_tracking': False,
        'staff_commission': False,
        'default_categories': ['Men', 'Women', 'Kids', 'Sports'],
    },
    'supermarket': {
        'key': 'supermarket',
        'label_en': 'Supermarket',
        'label_am': 'ሱፈርማርኬት',
        'icon': 'shopping_cart',
        'catalog_label': 'Products',
        'sells_products': True,
        'sells_services': False,
        'variants': False,
        'variant_attributes': ['unit'],
        'inventory': True,
        'appointments': False,
        'barcode': 'required',
        'expiry_tracking': True,
        'staff_commission': False,
        'default_categories': ['Beverages', 'Snacks', 'Dairy', 'Household', 'Grains & Pulses'],
    },
    'minimarket': {
        'key': 'minimarket',
        'label_en': 'Mini-market',
        'label_am': 'ጥቃት ሱቅ',
        'icon': 'storefront',
        'catalog_label': 'Products',
        'sells_products': True,
        'sells_services': False,
        'variants': False,
        'variant_attributes': ['unit'],
        'inventory': True,
        'appointments': False,
        'barcode': 'optional',
        'expiry_tracking': False,
        'staff_commission': False,
        'default_categories': ['Beverages', 'Snacks', 'Household', 'Other'],
    },
    'barbershop': {
        'key': 'barbershop',
        'label_en': 'Barbershop / Salon',
        'label_am': 'የፀጉር ቤት',
        'icon': 'content_cut',
        'catalog_label': 'Services',
        'sells_products': False,
        'sells_services': True,
        'variants': False,
        'variant_attributes': ['duration'],
        'inventory': False,
        'appointments': True,
        'barcode': 'no',
        'expiry_tracking': False,
        'staff_commission': True,
        'default_categories': ['Haircut', 'Beard trim', 'Shave', 'Hair treatment'],
    },
    'general': {
        'key': 'general',
        'label_en': 'General seller',
        'label_am': 'አጠቃላይ ሻጭ',
        'icon': 'category',
        'catalog_label': 'Products',
        'sells_products': True,
        'sells_services': False,
        'variants': False,
        'variant_attributes': [],
        'inventory': True,
        'appointments': False,
        'barcode': 'optional',
        'expiry_tracking': False,
        'staff_commission': False,
        'default_categories': ['General', 'Other'],
    },
    'hybrid': {
        'key': 'hybrid',
        'label_en': 'Hybrid (products + services)',
        'label_am': 'ድብልቅ (ᝍፍት + አገልግሎት)',
        'icon': 'widgets',
        'catalog_label': 'Catalog',
        'sells_products': True,
        'sells_services': True,
        'variants': True,
        'variant_attributes': ['size', 'color'],
        'inventory': True,
        'appointments': True,
        'barcode': 'optional',
        'expiry_tracking': False,
        'staff_commission': True,
        'default_categories': ['Services', 'Retail products'],
    },
}

BUSINESS_TYPE_CHOICES = [(k, v['label_en']) for k, v in BUSINESS_TYPES.items()]

PAYMENT_METHODS = ['cash', 'telebirr', 'cbe', 'credit']
PAYMENT_STATUSES = ['verified', 'pending_verification', 'manual', 'failed']

ROLES = ['owner', 'manager', 'cashier', 'staff']

# Role capability matrix (PRD G3) — enforced server-side in permissions.py.
ROLE_MATRIX = {
    'owner': {
        'manage_settings': True, 'manage_staff': True, 'view_reports': True,
        'void_sales': True, 'apply_discount': True, 'edit_prices': True,
        'manage_customers': True, 'record_payment': True, 'manage_expenses': True,
        'view_profit': True, 'view_cost': True,
    },
    'manager': {
        'manage_settings': False, 'manage_staff': True, 'view_reports': True,
        'void_sales': True, 'apply_discount': True, 'edit_prices': True,
        'manage_customers': True, 'record_payment': True, 'manage_expenses': True,
        'view_profit': True, 'view_cost': True,
    },
    'cashier': {
        'manage_settings': False, 'manage_staff': False, 'view_reports': False,
        'void_sales': False, 'apply_discount': False, 'edit_prices': False,
        'manage_customers': True, 'record_payment': True, 'manage_expenses': False,
        'view_profit': False, 'view_cost': False,
    },
    'staff': {
        'manage_settings': False, 'manage_staff': False, 'view_reports': False,
        'void_sales': False, 'apply_discount': False, 'edit_prices': False,
        'manage_customers': True, 'record_payment': True, 'manage_expenses': False,
        'view_profit': False, 'view_cost': False,
    },
}


def business_config(business_type: str) -> dict:
    return BUSINESS_TYPES.get(business_type, BUSINESS_TYPES['general'])
