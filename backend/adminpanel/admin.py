"""Velo owner console admin registration.

Safety model:
- Shop profiles are EDITABLE (the owner fixes tenant profile data).
- Everything else is strictly READ-ONLY (view + search + filter only) so the
  console can never corrupt live transactional data by accident.
- Nothing can be added or deleted through the console.
"""
from django.contrib import admin

from . import models
from .dashboard import kpis


class VeloAdminSite(admin.AdminSite):
    site_header = "Velo Owner Console"
    site_title = "Velo Admin"
    index_title = "Business overview"
    index_template = "admin/velo_index.html"

    def index(self, request, extra_context=None):
        ctx = {"kpi": kpis()}
        if extra_context:
            ctx.update(extra_context)
        return super().index(request, extra_context=ctx)


velo_admin_site = VeloAdminSite(name="velo_admin")


class ReadOnlyAdmin(admin.ModelAdmin):
    """Pure viewer: no add/change/delete, every field read-only on detail."""

    def has_add_permission(self, request):
        return False

    def has_change_permission(self, request, obj=None):
        return False

    def has_delete_permission(self, request, obj=None):
        return False

    def get_readonly_fields(self, request, obj=None):
        return [f.name for f in self.model._meta.fields]


@admin.register(models.Shop, site=velo_admin_site)
class ShopAdmin(admin.ModelAdmin):
    list_display = ("id", "name", "business_type", "plan", "phone",
                    "location_badge", "currency", "created_at")
    list_filter = ("business_type", "plan", "language", "currency")
    search_fields = ("name", "phone", "address", "tin",
                     "telebirr_number", "cbe_number")
    ordering = ("-created_at",)
    readonly_fields = ("id", "created_at")
    fieldsets = (
        ("Identity", {"fields": ("name", "business_type", "plan", "language")}),
        ("Contact & location", {"fields": (
            "phone", "address", "tin", "latitude", "longitude")}),
        ("Payments", {"fields": (
            "currency", "telebirr_number", "cbe_number",
            "accept_telebirr", "accept_cbe", "accept_credit")}),
        ("Receipt", {"fields": ("receipt_footer",)}),
        ("System", {"fields": ("id", "created_at")}),
    )

    # Edit-only: shops are created by real signups in the app; the console
    # must never create orphan tenants or delete live ones.
    def has_add_permission(self, request):
        return False

    def has_delete_permission(self, request, obj=None):
        return False

    @admin.display(boolean=True, description="GPS set")
    def location_badge(self, obj):
        return obj.has_location


@admin.register(models.AdminAuthUser, site=velo_admin_site)
class AdminAuthUserAdmin(ReadOnlyAdmin):
    list_display = ("phone", "email", "shop_name", "created_at",
                    "last_sign_in_at", "is_fresh")
    search_fields = ("phone", "email")
    ordering = ("-created_at",)
    list_per_page = 50

    @admin.display(description="Signup")
    def is_fresh(self, obj):
        return obj.last_sign_in_at is not None


@admin.register(models.Staff, site=velo_admin_site)
class StaffAdmin(ReadOnlyAdmin):
    list_display = ("id", "name", "shop", "role", "phone",
                    "commission_percent", "active", "created_at")
    list_filter = ("role", "active", "shop")
    search_fields = ("name", "phone")


@admin.register(models.Item, site=velo_admin_site)
class ItemAdmin(ReadOnlyAdmin):
    list_display = ("id", "name", "shop", "type", "price", "cost",
                    "stock_qty", "barcode", "is_active", "created_at")
    list_filter = ("type", "is_active", "shop")
    search_fields = ("name", "barcode", "description")


@admin.register(models.ItemVariant, site=velo_admin_site)
class ItemVariantAdmin(ReadOnlyAdmin):
    list_display = ("id", "item", "shop", "stock_qty", "price_override",
                    "sku", "barcode", "is_active")
    list_filter = ("is_active", "shop")
    search_fields = ("sku", "barcode")


@admin.register(models.Category, site=velo_admin_site)
class CategoryAdmin(ReadOnlyAdmin):
    list_display = ("id", "name", "shop", "created_at")
    list_filter = ("shop",)
    search_fields = ("name",)


@admin.register(models.Customer, site=velo_admin_site)
class CustomerAdmin(ReadOnlyAdmin):
    list_display = ("id", "name", "shop", "phone", "balance", "created_at")
    list_filter = ("shop",)
    search_fields = ("name", "phone")


@admin.register(models.Sale, site=velo_admin_site)
class SaleAdmin(ReadOnlyAdmin):
    list_display = ("id", "shop", "receipt_number", "total", "method",
                    "status", "staff_name", "created_at")
    list_filter = ("method", "status", "shop")
    search_fields = ("receipt_number", "customer_name", "reference",
                     "staff_name")
    date_hierarchy = "created_at"


@admin.register(models.SaleItem, site=velo_admin_site)
class SaleItemAdmin(ReadOnlyAdmin):
    list_display = ("id", "sale", "shop", "name_snapshot", "qty",
                    "unit_price", "line_total")
    list_filter = ("shop",)
    search_fields = ("name_snapshot",)


@admin.register(models.SalePayment, site=velo_admin_site)
class SalePaymentAdmin(ReadOnlyAdmin):
    list_display = ("id", "sale", "shop", "method", "amount",
                    "reference_number", "status")
    list_filter = ("method", "status", "shop")


@admin.register(models.LedgerEntry, site=velo_admin_site)
class LedgerEntryAdmin(ReadOnlyAdmin):
    list_display = ("id", "shop", "customer", "type", "amount",
                    "balance_after", "staff_name", "created_at")
    list_filter = ("type", "shop")
    date_hierarchy = "created_at"


@admin.register(models.Expense, site=velo_admin_site)
class ExpenseAdmin(ReadOnlyAdmin):
    list_display = ("id", "shop", "category", "amount", "spent_date", "note")
    list_filter = ("shop",)
    date_hierarchy = "created_at"


@admin.register(models.ExpenseCategory, site=velo_admin_site)
class ExpenseCategoryAdmin(ReadOnlyAdmin):
    list_display = ("id", "name", "shop")
    list_filter = ("shop",)
    search_fields = ("name",)


@admin.register(models.StockMovement, site=velo_admin_site)
class StockMovementAdmin(ReadOnlyAdmin):
    list_display = ("id", "shop", "item", "qty_change", "reason", "created_at")
    list_filter = ("reason", "shop")
    date_hierarchy = "created_at"


@admin.register(models.HeldSale, site=velo_admin_site)
class HeldSaleAdmin(ReadOnlyAdmin):
    list_display = ("id", "shop", "label", "created_at")
    list_filter = ("shop",)


@admin.register(models.BusinessType, site=velo_admin_site)
class BusinessTypeAdmin(ReadOnlyAdmin):
    list_display = ("key", "sort")
