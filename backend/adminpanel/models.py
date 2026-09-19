"""Unmanaged models mirroring the LIVE Supabase schema (public schema) plus a
read-only view over auth.users.

Rules:
- managed = False everywhere: Django never creates/alters/drops business data.
- Money columns are numeric in Postgres -> DecimalField (validation only).
- FKs use db_column matching the real columns, on_delete DO_NOTHING, and are
  only used for admin display joins (shop__name etc.).
- AdminAuthUser maps to the adminpanel.auth_users VIEW (read-only, private
  schema; view owner does the actual auth.users read).
"""
from django.db import models

DEC = dict(max_digits=14, decimal_places=2)


class BusinessType(models.Model):
    key = models.CharField(primary_key=True, max_length=64)
    config = models.JSONField()
    sort = models.IntegerField(default=0)

    class Meta:
        managed = False
        db_table = "business_types"
        verbose_name = "business type"
        verbose_name_plural = "business types"
        ordering = ["sort"]

    def __str__(self):
        return self.key


class Shop(models.Model):
    id = models.BigAutoField(primary_key=True)
    name = models.CharField(max_length=200)
    business_type = models.ForeignKey(
        BusinessType, db_column="business_type", to_field="key",
        on_delete=models.DO_NOTHING, related_name="+")
    language = models.CharField(max_length=8, default="en")
    plan = models.CharField(max_length=32, default="free")
    phone = models.CharField(max_length=32, blank=True, default="")
    address = models.TextField(blank=True, default="")
    currency = models.CharField(max_length=8, default="ETB")
    telebirr_number = models.CharField(max_length=32, blank=True, default="")
    cbe_number = models.CharField(max_length=32, blank=True, default="")
    accept_telebirr = models.BooleanField(default=True)
    accept_cbe = models.BooleanField(default=True)
    accept_credit = models.BooleanField(default=True)
    receipt_footer = models.TextField(blank=True, default="")
    latitude = models.FloatField(null=True, blank=True)
    longitude = models.FloatField(null=True, blank=True)
    tin = models.CharField(max_length=64, blank=True, default="")
    created_at = models.DateTimeField()
    is_suspended = models.BooleanField(default=False)
    suspended_at = models.DateTimeField(null=True, blank=True)
    suspended_note = models.TextField(blank=True, default="")

    class Meta:
        managed = False
        db_table = "shops"
        verbose_name = "shop (tenant)"
        verbose_name_plural = "shops (tenants)"
        ordering = ["-created_at"]

    def __str__(self):
        return f"{self.name} (#{self.id})"

    @property
    def has_location(self):
        return self.latitude is not None and self.longitude is not None

    @property
    def is_active_tenant(self):
        return not self.is_suspended


class Staff(models.Model):
    id = models.BigAutoField(primary_key=True)
    shop = models.ForeignKey(Shop, db_column="shop_id",
                             on_delete=models.DO_NOTHING, related_name="+")
    user_id = models.UUIDField(null=True, blank=True)
    name = models.CharField(max_length=120)
    phone = models.CharField(max_length=32, blank=True, default="")
    role = models.CharField(max_length=32, default="staff")
    commission_percent = models.DecimalField(default=0, **DEC)
    active = models.BooleanField(default=True)
    language = models.CharField(max_length=8, default="en")
    created_at = models.DateTimeField()

    class Meta:
        managed = False
        db_table = "staff"
        verbose_name = "staff member"
        verbose_name_plural = "staff members"
        ordering = ["-created_at"]

    def __str__(self):
        return f"{self.name} @ {self.shop_id}"


class Category(models.Model):
    id = models.BigAutoField(primary_key=True)
    shop = models.ForeignKey(Shop, db_column="shop_id",
                             on_delete=models.DO_NOTHING, related_name="+")
    name = models.CharField(max_length=120)
    created_at = models.DateTimeField()

    class Meta:
        managed = False
        db_table = "categories"
        verbose_name = "category"
        verbose_name_plural = "categories"
        ordering = ["name"]

    def __str__(self):
        return self.name


class Item(models.Model):
    id = models.BigAutoField(primary_key=True)
    shop = models.ForeignKey(Shop, db_column="shop_id",
                             on_delete=models.DO_NOTHING, related_name="+")
    category = models.ForeignKey(Category, db_column="category_id", null=True,
                                 blank=True, on_delete=models.DO_NOTHING,
                                 related_name="+")
    type = models.CharField(max_length=16, default="product")
    name = models.CharField(max_length=200)
    description = models.TextField(blank=True, default="")
    price = models.DecimalField(default=0, **DEC)
    cost = models.DecimalField(default=0, **DEC)
    stock_qty = models.IntegerField(default=0)
    low_stock_threshold = models.IntegerField(default=5)
    barcode = models.CharField(max_length=64, blank=True, default="")
    unit = models.CharField(max_length=16, default="pc")
    duration_minutes = models.IntegerField(null=True, blank=True)
    requires_stock = models.BooleanField(default=True)
    is_active = models.BooleanField(default=True)
    created_at = models.DateTimeField()

    class Meta:
        managed = False
        db_table = "items"
        verbose_name = "catalog item"
        verbose_name_plural = "catalog items"
        ordering = ["-created_at"]

    def __str__(self):
        return f"{self.name} @ {self.shop_id}"


class ItemVariant(models.Model):
    id = models.BigAutoField(primary_key=True)
    shop = models.ForeignKey(Shop, db_column="shop_id",
                             on_delete=models.DO_NOTHING, related_name="+")
    item = models.ForeignKey(Item, db_column="item_id",
                             on_delete=models.DO_NOTHING, related_name="+")
    attributes = models.JSONField(default=dict)
    stock_qty = models.IntegerField(default=0)
    price_override = models.DecimalField(null=True, blank=True, **DEC)
    sku = models.CharField(max_length=64, blank=True, default="")
    barcode = models.CharField(max_length=64, blank=True, default="")
    is_active = models.BooleanField(default=True)

    class Meta:
        managed = False
        db_table = "item_variants"
        verbose_name = "item variant"
        verbose_name_plural = "item variants"

    def __str__(self):
        return f"variant {self.id} of item {self.item_id}"


class Customer(models.Model):
    id = models.BigAutoField(primary_key=True)
    shop = models.ForeignKey(Shop, db_column="shop_id",
                             on_delete=models.DO_NOTHING, related_name="+")
    name = models.CharField(max_length=120)
    phone = models.CharField(max_length=32, blank=True, default="")
    notes = models.TextField(blank=True, default="")
    balance = models.DecimalField(default=0, **DEC)
    created_at = models.DateTimeField()

    class Meta:
        managed = False
        db_table = "customers"
        verbose_name = "customer"
        verbose_name_plural = "customers"
        ordering = ["-created_at"]

    def __str__(self):
        return self.name


class Sale(models.Model):
    id = models.BigAutoField(primary_key=True)
    shop = models.ForeignKey(Shop, db_column="shop_id",
                             on_delete=models.DO_NOTHING, related_name="+")
    receipt_number = models.BigIntegerField()
    customer = models.ForeignKey(Customer, db_column="customer_id", null=True,
                                 blank=True, on_delete=models.DO_NOTHING,
                                 related_name="+")
    customer_name = models.CharField(max_length=120, null=True, blank=True)
    staff = models.ForeignKey(Staff, db_column="staff_id", null=True,
                              blank=True, on_delete=models.DO_NOTHING,
                              related_name="+")
    staff_name = models.CharField(max_length=120, null=True, blank=True)
    subtotal = models.DecimalField(default=0, **DEC)
    discount_total = models.DecimalField(default=0, **DEC)
    tax_total = models.DecimalField(default=0, **DEC)
    total = models.DecimalField(default=0, **DEC)
    method = models.CharField(max_length=32, default="cash")
    status = models.CharField(max_length=32, default="completed")
    reference = models.CharField(max_length=64, blank=True, default="")
    amount_paid = models.DecimalField(default=0, **DEC)
    change_due = models.DecimalField(default=0, **DEC)
    refund_reason = models.TextField(null=True, blank=True)
    created_at = models.DateTimeField()

    class Meta:
        managed = False
        db_table = "sales"
        ordering = ["-created_at"]

    def __str__(self):
        return f"Sale #{self.id} {self.total}"


class SaleItem(models.Model):
    id = models.BigAutoField(primary_key=True)
    shop = models.ForeignKey(Shop, db_column="shop_id",
                             on_delete=models.DO_NOTHING, related_name="+")
    sale = models.ForeignKey(Sale, db_column="sale_id",
                             on_delete=models.DO_NOTHING, related_name="+")
    item = models.ForeignKey(Item, db_column="item_id", null=True, blank=True,
                             on_delete=models.DO_NOTHING, related_name="+")
    variant = models.ForeignKey(ItemVariant, db_column="variant_id", null=True,
                                blank=True, on_delete=models.DO_NOTHING,
                                related_name="+")
    name_snapshot = models.CharField(max_length=200)
    qty = models.DecimalField(default=1, **DEC)
    unit_price = models.DecimalField(default=0, **DEC)
    discount = models.DecimalField(default=0, **DEC)
    line_total = models.DecimalField(default=0, **DEC)
    cost_snapshot = models.DecimalField(default=0, **DEC)

    class Meta:
        managed = False
        db_table = "sale_items"
        verbose_name = "sale item"
        verbose_name_plural = "sale items"

    def __str__(self):
        return f"{self.qty}x {self.name_snapshot}"


class SalePayment(models.Model):
    id = models.BigAutoField(primary_key=True)
    shop = models.ForeignKey(Shop, db_column="shop_id",
                             on_delete=models.DO_NOTHING, related_name="+")
    sale = models.ForeignKey(Sale, db_column="sale_id",
                             on_delete=models.DO_NOTHING, related_name="+")
    method = models.CharField(max_length=32)
    amount = models.DecimalField(default=0, **DEC)
    reference_number = models.CharField(max_length=64, blank=True, default="")
    status = models.CharField(max_length=32, default="verified")

    class Meta:
        managed = False
        db_table = "sale_payments"
        verbose_name = "sale payment"
        verbose_name_plural = "sale payments"

    def __str__(self):
        return f"{self.method} {self.amount}"


class LedgerEntry(models.Model):
    id = models.BigAutoField(primary_key=True)
    shop = models.ForeignKey(Shop, db_column="shop_id",
                             on_delete=models.DO_NOTHING, related_name="+")
    customer = models.ForeignKey(Customer, db_column="customer_id",
                                 on_delete=models.DO_NOTHING, related_name="+")
    sale = models.ForeignKey(Sale, db_column="sale_id", null=True, blank=True,
                             on_delete=models.DO_NOTHING, related_name="+")
    type = models.CharField(max_length=32)
    amount = models.DecimalField(default=0, **DEC)
    balance_after = models.DecimalField(default=0, **DEC)
    note = models.TextField(blank=True, default="")
    staff_name = models.CharField(max_length=120, null=True, blank=True)
    created_at = models.DateTimeField()

    class Meta:
        managed = False
        db_table = "ledger_entries"
        verbose_name = "ledger entry"
        verbose_name_plural = "ledger entries"
        ordering = ["-created_at"]

    def __str__(self):
        return f"{self.type} {self.amount}"


class ExpenseCategory(models.Model):
    id = models.BigAutoField(primary_key=True)
    shop = models.ForeignKey(Shop, db_column="shop_id",
                             on_delete=models.DO_NOTHING, related_name="+")
    name = models.CharField(max_length=120)

    class Meta:
        managed = False
        db_table = "expense_categories"
        verbose_name = "expense category"
        verbose_name_plural = "expense categories"

    def __str__(self):
        return self.name


class Expense(models.Model):
    id = models.BigAutoField(primary_key=True)
    shop = models.ForeignKey(Shop, db_column="shop_id",
                             on_delete=models.DO_NOTHING, related_name="+")
    category = models.ForeignKey(ExpenseCategory, db_column="category_id",
                                 null=True, blank=True,
                                 on_delete=models.DO_NOTHING, related_name="+")
    amount = models.DecimalField(default=0, **DEC)
    note = models.TextField(blank=True, default="")
    spent_date = models.DateField()
    created_at = models.DateTimeField()

    class Meta:
        managed = False
        db_table = "expenses"
        verbose_name = "expense"
        verbose_name_plural = "expenses"
        ordering = ["-created_at"]

    def __str__(self):
        return f"{self.amount} on {self.spent_date}"


class HeldSale(models.Model):
    id = models.BigAutoField(primary_key=True)
    shop = models.ForeignKey(Shop, db_column="shop_id",
                             on_delete=models.DO_NOTHING, related_name="+")
    label = models.CharField(max_length=120, blank=True, default="")
    payload = models.JSONField(default=dict)
    created_at = models.DateTimeField()

    class Meta:
        managed = False
        db_table = "held_sales"
        verbose_name = "held sale"
        verbose_name_plural = "held sales"

    def __str__(self):
        return self.label or f"held {self.id}"


class StockMovement(models.Model):
    id = models.BigAutoField(primary_key=True)
    shop = models.ForeignKey(Shop, db_column="shop_id",
                             on_delete=models.DO_NOTHING, related_name="+")
    item = models.ForeignKey(Item, db_column="item_id",
                             on_delete=models.DO_NOTHING, related_name="+")
    variant = models.ForeignKey(ItemVariant, db_column="variant_id", null=True,
                                blank=True, on_delete=models.DO_NOTHING,
                                related_name="+")
    qty_change = models.IntegerField()
    reason = models.CharField(max_length=64, blank=True, default="")
    created_at = models.DateTimeField()

    class Meta:
        managed = False
        db_table = "stock_movements"
        ordering = ["-created_at"]

    def __str__(self):
        return f"{self.qty_change:+d} item {self.item_id}"


class AdminAuthUser(models.Model):
    """Projection of Supabase auth.users (private adminpanel schema view).
    NEVER exposes password hashes or secrets — only what the owner may
    see and manage: identity, activity, and the ban lever (banned_until).
    The view is a simple single-table view, so UPDATEs (ban/unban) flow
    through it to auth.users; the view owner performs the underlying write.
    """
    id = models.UUIDField(primary_key=True)
    email = models.CharField(max_length=254, null=True, blank=True)
    phone = models.CharField(max_length=32, null=True, blank=True)
    email_confirmed_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField()
    last_sign_in_at = models.DateTimeField(null=True, blank=True)
    raw_user_meta_data = models.JSONField(null=True, blank=True)
    banned_until = models.DateTimeField(null=True, blank=True)

    class Meta:
        managed = False
        db_table = "auth_users"  # resolved via search_path -> adminpanel.auth_users
        verbose_name = "app user"
        verbose_name_plural = "app users (Supabase auth)"
        ordering = ["-created_at"]

    def __str__(self):
        return self.phone or self.email or str(self.id)

    @property
    def shop_name(self):
        meta = self.raw_user_meta_data or {}
        return meta.get("shop_name", "")
