"""Velo owner console admin registration (Unfold-powered UI).

Safety model:
- Shop profiles are EDITABLE (the owner fixes tenant profile data).
- Everything else is strictly READ-ONLY (view + search + filter only) so the
  console can never corrupt live transactional data by accident.
- Nothing can be added or deleted through the console.
- Tenant suspension (v1.8.0) is the ONE destructive-ish control: it flips
  shops.is_suspended only — data is never touched, and it is reversible.

UI model (v1.8.0):
- django-unfold theme with Velo's Ethiopian-green brand palette.
- Curated sidebar navigation grouped by domain (Tenancy / Sales / Catalog /
  Operations) instead of a flat app list.
- Unfold dropdown filters whose options are derived from live column values.
- Dashboard chart period selector (7/14/30/90), MRR & churn row, and a
  danger zone for suspending/restoring tenants.
"""
from django.contrib import admin, messages
from django.db import connection
from django.http import HttpResponseRedirect
from django.urls import path
from django.utils.html import format_html
from unfold.admin import ModelAdmin
from unfold.contrib.filters.admin import RangeNumericFilter, RelatedDropdownFilter
from unfold.sites import UnfoldAdminSite

from . import models
from .dashboard import PERIODS, kpis
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
    SuspendedFilter,
)


class VeloAdminSite(UnfoldAdminSite):
    site_header = "Velo Owner Console"
    site_title = "Velo Admin"
    index_title = "Platform overview"
    index_template = "admin/velo_index.html"

    def index(self, request, extra_context=None):
        try:
            period = int(request.GET.get("period", 14))
        except (TypeError, ValueError):
            period = 14
        ctx = {"kpi": kpis(period)}
        if extra_context:
            ctx.update(extra_context)
        return super().index(request, extra_context=ctx)

    # ---- tenant suspension (danger zone) -------------------------------
    def get_urls(self):
        urls = super().get_urls()
        return [
            path("tenant/suspend/",
                 self.admin_view(self.suspend_tenant),
                 name="velo_tenant_suspend_any"),
            path("tenant/<int:shop_id>/suspend/",
                 self.admin_view(self.suspend_tenant),
                 name="velo_tenant_suspend"),
            path("tenant/<int:shop_id>/restore/",
                 self.admin_view(self.restore_tenant),
                 name="velo_tenant_restore"),
        ] + urls

    def _set_suspension(self, request, shop_id, suspend: bool):
        """Flip shops.is_suspended only — never touches business data."""
        if request.method != "POST":
            return HttpResponseRedirect("/admin/")
        if not shop_id:  # dashboard form posts the id in the body
            try:
                shop_id = int(request.POST.get("shop_id") or 0)
            except (TypeError, ValueError):
                shop_id = 0
        if not shop_id:
            messages.add_message(request, messages.ERROR,
                                 "Choose a tenant to suspend first.")
            return HttpResponseRedirect("/admin/")
        note = (request.POST.get("note") or "").strip()
        action = "suspended" if suspend else "restored"
        with connection.cursor() as cur:
            cur.execute(
                "update public.shops set is_suspended = %s, "
                "suspended_at = case when %s then now() else null end, "
                "suspended_note = %s where id = %s returning name",
                [suspend, suspend, note if suspend else "", shop_id])
            row = cur.fetchone()
        name = row[0] if row else f"#{shop_id}"
        level = messages.WARNING if suspend else messages.SUCCESS
        messages.add_message(
            request, level,
            f"Tenant “{name}” {action}."
            + (" Reason noted." if suspend and note else ""))
        return HttpResponseRedirect(request.POST.get("next") or "/admin/")

    def suspend_tenant(self, request, shop_id=None):
        return self._set_suspension(request, shop_id or 0, suspend=True)

    def restore_tenant(self, request, shop_id):
        return self._set_suspension(request, shop_id, suspend=False)


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
                    "location_badge", "suspension_badge", "created_at")
    list_filter = (
        ("business_type", RelatedDropdownFilter),
        PlanFilter,
        LanguageFilter,
        SuspendedFilter,
    )
    list_filter_submit = True
    list_fullwidth = True
    search_fields = ("name", "phone", "address", "tin",
                     "telebirr_number", "cbe_number")
    search_help_text = "Search by name, phone, address, TIN or payment numbers"
    ordering = ("-created_at",)
    readonly_fields = ("id", "created_at", "suspended_at")
    actions = ("suspend_selected", "restore_selected")
    fieldsets = (
        ("Identity", {"fields": ("name", "business_type", "plan", "language")}),
        ("Contact & location", {"fields": (
            "phone", "address", "tin", "latitude", "longitude")}),
        ("Payments", {"fields": (
            "currency", "telebirr_number", "cbe_number",
            "accept_telebirr", "accept_cbe", "accept_credit")}),
        ("Receipt", {"fields": ("receipt_footer",)}),
        ("System", {"fields": ("id", "created_at")}),
        ("Danger zone — suspend tenant", {
            "classes": ("vp-danger-zone",),
            "description": "Suspension flags the tenant for the platform. "
                           "It never deletes data and is fully reversible.",
            "fields": ("is_suspended", "suspended_note", "suspended_at"),
        }),
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

    @admin.display(description="Status")
    def suspension_badge(self, obj):
        if obj.is_suspended:
            return format_html(
                '<span class="vp-pill vp-pill-suspended">suspended</span>')
        return format_html(
            '<span class="vp-pill vp-pill-active">active</span>')

    @admin.action(description="Suspend selected tenants (reversible)")
    def suspend_selected(self, request, queryset):
        count = 0
        for shop in queryset:
            if not shop.is_suspended:
                with connection.cursor() as cur:
                    cur.execute(
                        "update public.shops set is_suspended = true, "
                        "suspended_at = now() where id = %s", [shop.id])
                count += 1
        self.message_user(request, f"{count} tenant(s) suspended.",
                          level=messages.WARNING)

    @admin.action(description="Restore selected tenants")
    def restore_selected(self, request, queryset):
        count = 0
        for shop in queryset:
            if shop.is_suspended:
                with connection.cursor() as cur:
                    cur.execute(
                        "update public.shops set is_suspended = false, "
                        "suspended_at = null, suspended_note = '' "
                        "where id = %s", [shop.id])
                count += 1
        self.message_user(request, f"{count} tenant(s) restored.")


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
