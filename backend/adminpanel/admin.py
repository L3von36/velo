"""Velo owner console admin registration (Unfold-powered UI).

Safety model:
- Shop profiles are EDITABLE (the owner fixes tenant profile data).
- Everything else is strictly READ-ONLY (view + search + filter only) so the
  console can never corrupt live transactional data by accident.
- Nothing can be added or deleted through the console.

UI model (v1.7.0):
- django-unfold theme with Velo's Ethiopian-green brand palette.
- Curated sidebar navigation grouped by domain (Tenancy / Sales / Catalog /
  Operations) instead of a flat app list.
- Unfold dropdown filters whose options are derived from live column values.
"""
from django.contrib import admin
from unfold.admin import ModelAdmin
from unfold.contrib.filters.admin import RangeNumericFilter, RelatedDropdownFilter
from unfold.sites import UnfoldAdminSite

from . import models
from .dashboard import kpis
from .filters import (
    ItemTypeFilter,
    LanguageFilter,
    LedgerTypeFilter,
    PaymentMethodFilter,
    PaymentStatusFilter,
    PlanFilter,
    SaleMethodFilter,
    SaleStatusFilter,
    StaffRoleFilter,
    StockReasonFilter,
)


class VeloAdminSite(UnfoldAdminSite):
    site_header = "Velo Owner Console"
    site_title = "Velo Admin"
    index_title = "Platform overview"
    index_template = "admin/velo_index.html"

    def index(self, request, extra_context=None):
        ctx = {"kpi": kpis()}
        if extra_context:
            ctx.update(extra_context)
        return super().index(request, extra_context=ctx)


velo_admin_site = VeloAdminSite(name="velo_admin")


class ReadOnlyAdmin(ModelAdmin):
    """Pure viewer: no add/change/delete, every field read-only on detail."""

    list_fullwidth = True
    list_disable_select_all = True

    def has_add_permission(self, request):
        return False

    def has_change_permission(self, request, obj=None):
        return False

    def has_delete_permission(self, request, obj=None):
        return False

    def get_readonly_fields(self, request, obj=None):
        return [f.name for f in self.model._meta.fields]


@admin.register(models.Shop, site=velo_admin_site)
class ShopAdmin(ModelAdmin):
    list_display = ("id", "name", "business_type", "plan", "phone",
                    "location_badge", "currency", "created_at")
    list_filter = (
        ("business_type", RelatedDropdownFilter),
        PlanFilter,
        LanguageFilter,
    )
    list_filter_submit = True
    list_fullwidth = True
    search_fields = ("name", "phone", "address", "tin",
                     "telebirr_number", "cbe_number")
    search_help_text = "Search by name, phone, address, TIN or payment numbers"
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
    search_help_text = "Search by phone or email"
    ordering = ("-created_at",)
    list_per_page = 50

    @admin.display(description="Signed in before", boolean=True)
    def is_fresh(self, obj):
        return obj.last_sign_in_at is not None


@admin.register(models.Staff, site=velo_admin_site)
class StaffAdmin(ReadOnlyAdmin):
    list_display = ("id", "name", "shop", "role", "phone",
                    "commission_percent", "active", "created_at")
    list_filter = (StaffRoleFilter, "active", ("shop", RelatedDropdownFilter))
    list_filter_submit = True
    search_fields = ("name", "phone")
    list_select_related = ("shop",)


@admin.register(models.Item, site=velo_admin_site)
class ItemAdmin(ReadOnlyAdmin):
    list_display = ("id", "name", "shop", "type", "price", "cost",
                    "stock_qty", "barcode", "is_active", "created_at")
    list_filter = (ItemTypeFilter, "is_active",
                   ("shop", RelatedDropdownFilter))
    list_filter_submit = True
    search_fields = ("name", "barcode", "description")
    search_help_text = "Search by name, barcode or description"
    list_select_related = ("shop",)


@admin.register(models.ItemVariant, site=velo_admin_site)
class ItemVariantAdmin(ReadOnlyAdmin):
    list_display = ("id", "item", "shop", "stock_qty", "price_override",
                    "sku", "barcode", "is_active")
    list_filter = ("is_active", ("shop", RelatedDropdownFilter))
    list_filter_submit = True
    search_fields = ("sku", "barcode")
    list_select_related = ("item", "shop")
    ordering = ("-id",)


@admin.register(models.Category, site=velo_admin_site)
class CategoryAdmin(ReadOnlyAdmin):
    list_display = ("id", "name", "shop", "created_at")
    list_filter = (("shop", RelatedDropdownFilter),)
    list_filter_submit = True
    search_fields = ("name",)
    list_select_related = ("shop",)


@admin.register(models.Customer, site=velo_admin_site)
class CustomerAdmin(ReadOnlyAdmin):
    list_display = ("id", "name", "shop", "phone", "balance", "created_at")
    list_filter = (("shop", RelatedDropdownFilter),)
    list_filter_submit = True
    search_fields = ("name", "phone")
    list_select_related = ("shop",)


@admin.register(models.Sale, site=velo_admin_site)
class SaleAdmin(ReadOnlyAdmin):
    list_display = ("id", "shop", "receipt_number", "total", "method",
                    "status", "staff_name", "created_at")
    list_filter = (
        SaleMethodFilter,
        SaleStatusFilter,
        ("total", RangeNumericFilter),
        ("shop", RelatedDropdownFilter),
    )
    list_filter_submit = True
    search_fields = ("receipt_number", "customer_name", "reference",
                     "staff_name")
    search_help_text = "Search by receipt number, customer, reference or staff"
    date_hierarchy = "created_at"
    list_per_page = 50
    list_select_related = ("shop",)


@admin.register(models.SaleItem, site=velo_admin_site)
class SaleItemAdmin(ReadOnlyAdmin):
    list_display = ("id", "sale", "shop", "name_snapshot", "qty",
                    "unit_price", "line_total")
    list_filter = (("shop", RelatedDropdownFilter),)
    list_filter_submit = True
    search_fields = ("name_snapshot",)
    list_select_related = ("sale", "shop")


@admin.register(models.SalePayment, site=velo_admin_site)
class SalePaymentAdmin(ReadOnlyAdmin):
    list_display = ("id", "sale", "shop", "method", "amount",
                    "reference_number", "status")
    list_filter = (PaymentMethodFilter, PaymentStatusFilter,
                   ("shop", RelatedDropdownFilter))
    list_filter_submit = True
    list_select_related = ("sale", "shop")
    ordering = ("-id",)


@admin.register(models.LedgerEntry, site=velo_admin_site)
class LedgerEntryAdmin(ReadOnlyAdmin):
    list_display = ("id", "shop", "customer", "type", "amount",
                    "balance_after", "staff_name", "created_at")
    list_filter = (LedgerTypeFilter, ("shop", RelatedDropdownFilter))
    list_filter_submit = True
    date_hierarchy = "created_at"
    list_select_related = ("shop", "customer")


@admin.register(models.Expense, site=velo_admin_site)
class ExpenseAdmin(ReadOnlyAdmin):
    list_display = ("id", "shop", "category", "amount", "spent_date", "note")
    list_filter = (("shop", RelatedDropdownFilter),)
    list_filter_submit = True
    date_hierarchy = "created_at"
    list_select_related = ("shop", "category")


@admin.register(models.ExpenseCategory, site=velo_admin_site)
class ExpenseCategoryAdmin(ReadOnlyAdmin):
    list_display = ("id", "name", "shop")
    list_filter = (("shop", RelatedDropdownFilter),)
    list_filter_submit = True
    search_fields = ("name",)
    list_select_related = ("shop",)
    ordering = ("-id",)


@admin.register(models.StockMovement, site=velo_admin_site)
class StockMovementAdmin(ReadOnlyAdmin):
    list_display = ("id", "shop", "item", "qty_change", "reason", "created_at")
    list_filter = (StockReasonFilter, ("shop", RelatedDropdownFilter))
    list_filter_submit = True
    date_hierarchy = "created_at"
    list_select_related = ("shop", "item")


@admin.register(models.HeldSale, site=velo_admin_site)
class HeldSaleAdmin(ReadOnlyAdmin):
    list_display = ("id", "shop", "label", "created_at")
    list_filter = (("shop", RelatedDropdownFilter),)
    list_filter_submit = True
    list_select_related = ("shop",)
    ordering = ("-created_at",)


@admin.register(models.BusinessType, site=velo_admin_site)
class BusinessTypeAdmin(ReadOnlyAdmin):
    list_display = ("key", "sort")
