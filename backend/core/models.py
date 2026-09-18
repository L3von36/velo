"""Data model — PRD §6, adapted to Django ORM.

Every tenant-scoped model carries tenant_id; isolation is enforced in the
TenancyManager (see tenancy.py) so one shop can never read another's data.
"""
from decimal import Decimal

from django.conf import settings
from django.contrib.auth.base_user import AbstractBaseUser, BaseUserManager
from django.contrib.auth.hashers import make_password
from django.db import models
from django.utils import timezone

from .business_types import BUSINESS_TYPE_CHOICES, ROLES


class TenancyQuerySet(models.QuerySet):
    def for_user(self, user):
        if user is None or not getattr(user, 'is_authenticated', False):
            return self.none()
        return self.filter(tenant_id=user.tenant_id)


class TenancyManager(models.Manager):
    def get_queryset(self):
        return TenancyQuerySet(self.model, using=self._db)


class TimestampedModel(models.Model):
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        abstract = True


class Tenant(TimestampedModel):
    BUSINESS = BUSINESS_TYPE_CHOICES

    name = models.CharField(max_length=120)
    business_type = models.CharField(max_length=20, choices=BUSINESS_TYPE_CHOICES, default='general')
    sells_products = models.BooleanField(default=True)
    sells_services = models.BooleanField(default=False)
    plan = models.CharField(max_length=10, default='free')  # free | basic | pro
    language = models.CharField(max_length=5, default='en')  # en | am
    currency = models.CharField(max_length=8, default='ETB')
    # Shop identity (A8)
    phone = models.CharField(max_length=20, blank=True, default='')
    address = models.CharField(max_length=200, blank=True, default='')
    # Payment methods setup (K9)
    telebirr_number = models.CharField(max_length=20, blank=True, default='')
    cbe_number = models.CharField(max_length=30, blank=True, default='')
    accept_telebirr = models.BooleanField(default=True)
    accept_cbe = models.BooleanField(default=True)
    accept_credit = models.BooleanField(default=True)
    # Receipt settings (K7)
    receipt_footer = models.CharField(max_length=160, blank=True, default='Thank you for shopping with us!')
    receipt_logo_enabled = models.BooleanField(default=True)
    tax_enabled = models.BooleanField(default=False)
    tax_rate_percent = models.DecimalField(max_digits=5, decimal_places=2, default=Decimal('0.00'))

    def __str__(self):
        return self.name


class Branch(TimestampedModel):
    tenant = models.ForeignKey(Tenant, on_delete=models.CASCADE, related_name='branches')
    name = models.CharField(max_length=120)
    address = models.CharField(max_length=200, blank=True, default='')
    phone = models.CharField(max_length=20, blank=True, default='')
    is_default = models.BooleanField(default=False)

    class Meta:
        ordering = ['id']

    def save(self, *args, **kwargs):
        """Ensure every tenant has exactly one default branch (A9)."""
        if self.is_default:
            Branch.objects.filter(tenant=self.tenant).exclude(pk=self.pk).update(is_default=False)
        elif not self.tenant_id and Branch.objects.filter(tenant=self.tenant, is_default=True).exists():
            pass
        super().save(*args, **kwargs)


class UserManager(BaseUserManager):
    use_in_migrations = True

    def create_user(self, phone, password=None, **extra):
        if not phone:
            raise ValueError('Phone number is required')
        user = self.model(phone=phone, **extra)
        user.password = make_password(password)
        user.save(using=self._db)
        return user

    def create_superuser(self, phone, password=None, **extra):
        extra.setdefault('role', 'owner')
        return self.create_user(phone, password, **extra)


class User(AbstractBaseUser):
    """Phone-first identity — matches how Ethiopians register for services (A3)."""

    tenant = models.ForeignKey(Tenant, on_delete=models.CASCADE, related_name='users', null=True, blank=True)
    branch = models.ForeignKey(Branch, on_delete=models.SET_NULL, related_name='staff', null=True, blank=True)
    name = models.CharField(max_length=120)
    phone = models.CharField(max_length=20, unique=True)
    role = models.CharField(max_length=10, choices=[(r, r) for r in ROLES], default='cashier')
    commission_percent = models.DecimalField(max_digits=5, decimal_places=2, default=Decimal('0.00'))
    active = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)

    USERNAME_FIELD = 'phone'
    REQUIRED_FIELDS = ['name']
    objects = UserManager()

    @property
    def is_staff(self):
        return self.role in ('owner', 'manager')

    @property
    def is_active(self):
        return self.active

    @property
    def is_anonymous(self):
        return False

    @property
    def is_authenticated(self):
        return True

    def get_username(self):
        return self.phone

    def __str__(self):
        return f'{self.name} ({self.phone})'


class Category(TimestampedModel):
    tenant = models.ForeignKey(Tenant, on_delete=models.CASCADE, related_name='categories')
    name = models.CharField(max_length=120)
    sort_order = models.PositiveIntegerField(default=0)

    class Meta:
        ordering = ['sort_order', 'id']
        unique_together = [('tenant', 'name')]

    def __str__(self):
        return self.name


class CatalogItem(TimestampedModel):
    TYPE_PRODUCT = 'product'
    TYPE_SERVICE = 'service'

    tenant = models.ForeignKey(Tenant, on_delete=models.CASCADE, related_name='catalog_items')
    type = models.CharField(max_length=10, choices=[(TYPE_PRODUCT, 'product'), (TYPE_SERVICE, 'service')])
    category = models.ForeignKey(Category, on_delete=models.SET_NULL, related_name='items', null=True, blank=True)
    name = models.CharField(max_length=200)
    description = models.TextField(blank=True, default='')
    price = models.DecimalField(max_digits=12, decimal_places=2)
    cost = models.DecimalField(max_digits=12, decimal_places=2, null=True, blank=True)
    # Service fields (C5)
    duration_minutes = models.PositiveIntegerField(null=True, blank=True)
    # Product fields (C4)
    requires_stock = models.BooleanField(default=True)
    low_stock_threshold = models.PositiveIntegerField(default=5)
    barcode = models.CharField(max_length=64, blank=True, default='')
    unit = models.CharField(max_length=10, blank=True, default='pc')  # pc | kg | litre
    expiry_date = models.DateField(null=True, blank=True)  # E9 — supermarket
    is_active = models.BooleanField(default=True)

    class Meta:
        ordering = ['name']
        indexes = [models.Index(fields=['tenant', 'type', 'is_active'])]

    @property
    def stock_qty(self) -> int:
        agg = self.variants.aggregate(total=models.Sum('stock_qty'))
        return int(agg['total'] or 0)

    def __str__(self):
        return self.name


class ItemVariant(TimestampedModel):
    """Generic variant system — size/color for clothing, unit packs for markets (C8)."""

    item = models.ForeignKey(CatalogItem, on_delete=models.CASCADE, related_name='variants')
    attributes = models.JSONField(default=dict)  # {"size": "M", "color": "Blue"}
    sku = models.CharField(max_length=64, blank=True, default='')
    barcode = models.CharField(max_length=64, blank=True, default='')
    price_override = models.DecimalField(max_digits=12, decimal_places=2, null=True, blank=True)
    stock_qty = models.IntegerField(default=0)

    @property
    def effective_price(self):
        return self.price_override if self.price_override is not None else self.item.price

    def __str__(self):
        return f'{self.item.name} {self.attributes}'


class StockMovement(TimestampedModel):
    """Append-only audit trail — every stock change lands here (E1, §7)."""

    REF_TYPES = [
        ('sale', 'sale'), ('adjustment', 'adjustment'), ('refund', 'refund'),
        ('initial', 'initial'), ('purchase_order', 'purchase_order'),
        ('transfer', 'transfer'), ('count', 'count'),
    ]

    tenant = models.ForeignKey(Tenant, on_delete=models.CASCADE, related_name='stock_movements')
    branch = models.ForeignKey(Branch, on_delete=models.SET_NULL, null=True)
    item = models.ForeignKey(CatalogItem, on_delete=models.CASCADE, related_name='stock_movements')
    variant = models.ForeignKey(ItemVariant, on_delete=models.CASCADE, related_name='stock_movements', null=True, blank=True)
    delta_qty = models.IntegerField()
    reason = models.CharField(max_length=30, default='sale')
    reference_type = models.CharField(max_length=20, choices=REF_TYPES, default='adjustment')
    reference_id = models.CharField(max_length=64, blank=True, default='')
    staff = models.ForeignKey(User, on_delete=models.SET_NULL, null=True)
    note = models.CharField(max_length=200, blank=True, default='')

    class Meta:
        ordering = ['-created_at']


class Customer(TimestampedModel):
    tenant = models.ForeignKey(Tenant, on_delete=models.CASCADE, related_name='customers')
    name = models.CharField(max_length=120)
    phone = models.CharField(max_length=20, blank=True, default='')
    notes = models.TextField(blank=True, default='')
    balance = models.DecimalField(max_digits=12, decimal_places=2, default=Decimal('0.00'))  # >0 means owes
    birthday = models.DateField(null=True, blank=True)

    class Meta:
        ordering = ['-created_at']


class CustomerLedger(TimestampedModel):
    """Append-only debt ledger — corrections are new offsetting entries (F4)."""

    TYPES = [('charge', 'charge'), ('payment', 'payment'), ('adjustment', 'adjustment')]

    tenant = models.ForeignKey(Tenant, on_delete=models.CASCADE, related_name='customer_ledger')
    customer = models.ForeignKey(Customer, on_delete=models.CASCADE, related_name='ledger_entries')
    type = models.CharField(max_length=12, choices=TYPES)
    amount = models.DecimalField(max_digits=12, decimal_places=2)
    balance_after = models.DecimalField(max_digits=12, decimal_places=2)
    note = models.CharField(max_length=200, blank=True, default='')
    staff = models.ForeignKey(User, on_delete=models.SET_NULL, null=True)
    sale = models.ForeignKey('Sale', on_delete=models.SET_NULL, null=True, blank=True)

    class Meta:
        ordering = ['-created_at']


class Sale(TimestampedModel):
    STATUS_COMPLETED = 'completed'
    STATUS_REFUNDED = 'refunded'
    STATUS_VOID = 'void'

    tenant = models.ForeignKey(Tenant, on_delete=models.CASCADE, related_name='sales')
    branch = models.ForeignKey(Branch, on_delete=models.SET_NULL, null=True)
    staff = models.ForeignKey(User, on_delete=models.SET_NULL, null=True)
    customer = models.ForeignKey(Customer, on_delete=models.SET_NULL, null=True, blank=True)
    receipt_number = models.PositiveIntegerField()
    subtotal = models.DecimalField(max_digits=12, decimal_places=2)
    discount_total = models.DecimalField(max_digits=12, decimal_places=2, default=Decimal('0.00'))
    tax_total = models.DecimalField(max_digits=12, decimal_places=2, default=Decimal('0.00'))
    total = models.DecimalField(max_digits=12, decimal_places=2)
    status = models.CharField(max_length=10, default='completed')
    void_reason = models.CharField(max_length=200, blank=True, default='')

    class Meta:
        ordering = ['-created_at']
        unique_together = [('tenant', 'receipt_number')]
        indexes = [models.Index(fields=['tenant', 'created_at'])]

    @property
    def cogs(self):
        agg = self.items.aggregate(c=models.Sum('cost_at_sale'))
        return agg['c'] or Decimal('0.00')


class SaleItem(models.Model):
    sale = models.ForeignKey(Sale, on_delete=models.CASCADE, related_name='items')
    item = models.ForeignKey(CatalogItem, on_delete=models.SET_NULL, null=True)
    variant = models.ForeignKey(ItemVariant, on_delete=models.SET_NULL, null=True)
    name_snapshot = models.CharField(max_length=220)
    qty = models.DecimalField(max_digits=10, decimal_places=2)
    unit_price = models.DecimalField(max_digits=12, decimal_places=2)
    discount = models.DecimalField(max_digits=12, decimal_places=2, default=Decimal('0.00'))
    cost_at_sale = models.DecimalField(max_digits=12, decimal_places=2, default=Decimal('0.00'))


class Payment(TimestampedModel):
    METHODS = [('cash', 'cash'), ('telebirr', 'telebirr'), ('cbe', 'cbe'), ('credit', 'credit')]
    STATUSES = [('verified', 'verified'), ('pending_verification', 'pending_verification'),
                ('manual', 'manual'), ('failed', 'failed')]

    sale = models.ForeignKey(Sale, on_delete=models.CASCADE, related_name='payments')
    method = models.CharField(max_length=12, choices=METHODS)
    amount = models.DecimalField(max_digits=12, decimal_places=2)
    reference_number = models.CharField(max_length=64, blank=True, default='')
    status = models.CharField(max_length=20, choices=STATUSES, default='verified')


class HeldSale(TimestampedModel):
    """Parked carts (D11/D12)."""

    tenant = models.ForeignKey(Tenant, on_delete=models.CASCADE, related_name='held_sales')
    branch = models.ForeignKey(Branch, on_delete=models.SET_NULL, null=True)
    staff = models.ForeignKey(User, on_delete=models.SET_NULL, null=True)
    label = models.CharField(max_length=120, blank=True, default='')
    payload = models.JSONField(default=dict)

    class Meta:
        ordering = ['-created_at']


class ExpenseCategory(TimestampedModel):
    tenant = models.ForeignKey(Tenant, on_delete=models.CASCADE, related_name='expense_categories')
    name = models.CharField(max_length=120)

    class Meta:
        ordering = ['id']


class Expense(TimestampedModel):
    tenant = models.ForeignKey(Tenant, on_delete=models.CASCADE, related_name='expenses')
    branch = models.ForeignKey(Branch, on_delete=models.SET_NULL, null=True)
    category = models.ForeignKey(ExpenseCategory, on_delete=models.SET_NULL, null=True)
    amount = models.DecimalField(max_digits=12, decimal_places=2)
    note = models.CharField(max_length=200, blank=True, default='')
    date = models.DateField(default=timezone.localdate)
    staff = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True)

    class Meta:
        ordering = ['-date']


class Appointment(TimestampedModel):
    """Service bookings (H1–H3) — Phase 2 scope, model ready from day one."""

    STATUSES = [('booked', 'booked'), ('confirmed', 'confirmed'), ('in_progress', 'in_progress'),
                ('completed', 'completed'), ('no_show', 'no_show'), ('cancelled', 'cancelled')]

    tenant = models.ForeignKey(Tenant, on_delete=models.CASCADE, related_name='appointments')
    branch = models.ForeignKey(Branch, on_delete=models.SET_NULL, null=True)
    customer = models.ForeignKey(Customer, on_delete=models.SET_NULL, null=True)
    staff = models.ForeignKey(User, on_delete=models.SET_NULL, null=True)
    services = models.ManyToManyField(CatalogItem, blank=True, related_name='appointments')
    start_time = models.DateTimeField()
    duration_minutes = models.PositiveIntegerField(default=30)
    status = models.CharField(max_length=12, choices=STATUSES, default='booked')
    note = models.CharField(max_length=200, blank=True, default='')

    class Meta:
        ordering = ['start_time']
