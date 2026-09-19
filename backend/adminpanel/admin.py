"""Velo owner console admin registration (Unfold-powered UI).

Privilege model (v2.0.0 — the owner and admins are SUPERUSERS, full power):
- The console is the platform's cockpit: the owner can add, change and
  delete master data (shops, catalog, staff, customers, expenses,
  business types) and repair transactional data (sales, payments, ledger,
  stock movements) when something went wrong in the field.
- One guardrail stays: transactional records cannot be FABRICATED from the
  console (no "add sale" form) because sales must originate in the app —
  they can still be edited or removed. Every change is logged by Django
  admin history.
- Tenant suspension (v1.8.0) flips shops.is_suspended only — reversible.
- App users (Supabase auth): the owner can BAN and UNBAN accounts via the
  adminpanel.auth_users view (UPDATE granted to velo_admin).

UI model:
- django-unfold theme, Velo brand, curated sidebar.
- Money Radar (v2.0.0): health scores, upsell pipeline, churn risk,
  win-back list, revenue benchmarks — the revenue-intelligence page.
"""
from django.contrib import admin, messages
from django.db import connection, IntegrityError, transaction
from django.http import HttpResponseRedirect
from django.shortcuts import render
from django.urls import path
from django.utils.html import format_html
from unfold.admin import ModelAdmin
from unfold.contrib.filters.admin import RangeNumericFilter, RelatedDropdownFilter
from unfold.sites import UnfoldAdminSite

from . import models
from .dashboard import PERIODS, kpis, money_radar
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
    TestFilter,
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

    # ---- custom owner pages --------------------------------------------
    def get_urls(self):
        urls = super().get_urls()
        return [
            path("money-radar/",
                 self.admin_view(self.money_radar_view),
                 name="velo_money_radar"),
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

    def money_radar_view(self, request):
        return render(request, "admin/velo_money_radar.html",
                      {"radar": money_radar(),
                       **self.each_context(request)})

    # ---- tenant suspension (danger zone) -------------------------------
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
            f"Tenant \u201c{name}\u201d {action}."
            + (" Reason noted." if suspend and note else ""))
        return HttpResponseRedirect(request.POST.get("next") or "/admin/")

    def suspend_tenant(self, request, shop_id=None):
        return self._set_suspension(request, shop_id or 0, suspend=True)

    def restore_tenant(self, request, shop_id):
        return self._set_suspension(request, shop_id, suspend=False)


velo_admin_site = VeloAdminSite(name="velo_admin")


_BLOCKED_MSG = (
    "Blocked: other records still reference this row (sales history, "
    "ledger lines, stock moves…). Clean up the references first — the "
    "console never orphans live data.")


class _GuardedDeleteMixin:
    """Deletes that can never 500 on foreign-key walls.

    Single delete: the Delete button only appears on rows with no live
    references (checked per object; direct URL access gets a standard
    PermissionDenied).
    Bulk delete: keeps Django's confirmation page, then deletes per object
    and reports an honest 'N deleted, M blocked' summary instead of dying
    on the first referenced row.
    """

    # Subclasses can raise this to forbid single-row deletion entirely.
    allow_single_delete = True

    def _reference_count(self, obj) -> int:
        """How many rows across the live schema still point at obj."""
        table = self.model._meta.db_table
        checks = {
            "shops": """
                (select count(*) from public.sales where shop_id = t.id) +
                (select count(*) from public.items where shop_id = t.id) +
                (select count(*) from public.staff where shop_id = t.id) +
                (select count(*) from public.customers where shop_id = t.id) +
                (select count(*) from public.expenses where shop_id = t.id) +
                (select count(*) from public.categories where shop_id = t.id) +
                (select count(*) from public.held_sales where shop_id = t.id) +
                (select count(*) from public.stock_movements where shop_id = t.id) +
                (select count(*) from public.ledger_entries where shop_id = t.id) +
                (select count(*) from public.sale_payments sp
                   join public.sales s on s.id = sp.sale_id where s.shop_id = t.id) +
                (select count(*) from public.sale_items si
                   join public.sales s on s.id = si.sale_id where s.shop_id = t.id)""",
            "items": """
                (select count(*) from public.sale_items where item_id = t.id) +
                (select count(*) from public.item_variants where item_id = t.id) +
                (select count(*) from public.stock_movements where item_id = t.id)""",
            "customers": """
                (select count(*) from public.sales where customer_id = t.id) +
                (select count(*) from public.ledger_entries where customer_id = t.id)""",
            "categories": """
                (select count(*) from public.items where category_id = t.id)""",
            "sales": """
                (select count(*) from public.sale_items where sale_id = t.id) +
                (select count(*) from public.sale_payments where sale_id = t.id) +
                (select count(*) from public.ledger_entries where sale_id = t.id)""",
            "expense_categories": """
                (select count(*) from public.expenses where category_id = t.id)""",
        }.get(table)
        if checks is None:
            return 0
        with connection.cursor() as cur:
            cur.execute(f"select {checks} from public.{table} t where t.id = %s",
                        [obj.pk])
            row = cur.fetchone()
        return row[0] if row else 0

    def has_delete_permission(self, request, obj=None):
        if not self.allow_single_delete:
            return False
        if obj is None:
            return True
        return self._reference_count(obj) == 0

    def delete_model(self, request, obj):
        try:
            with transaction.atomic():
                super().delete_model(request, obj)
        except IntegrityError:
            self.message_user(request, _BLOCKED_MSG, level=messages.ERROR)

    @admin.action(permissions=["delete"])
    def delete_selected(self, request, queryset):
        """Django's delete_selected flow with an FK guard per object."""
        opts = self.model._meta
        if request.POST.get("post"):
            done = blocked = 0
            for obj in queryset:
                try:
                    with transaction.atomic():
                        self.log_deletion(request, obj, str(obj))
                        obj.delete()
                    done += 1
                except IntegrityError:
                    blocked += 1
            if done:
                self.message_user(
                    request, f"Successfully deleted {done} {opts.verbose_name_plural}.",
                    level=messages.SUCCESS)
            if blocked:
                self.message_user(
                    request,
                    f"{blocked} {opts.verbose_name_plural} skipped — still "
                    "referenced by other records.",
                    level=messages.WARNING)
            return None
        # No confirmation yet → fall through to Django's standard confirm page.
        return admin.actions.delete_selected(self, request, queryset)


class FullPowerAdmin(_GuardedDeleteMixin, ModelAdmin):
    """Owner-level CRUD: add, change, delete — the console's nuclear option."""

    list_fullwidth = True

    def has_add_permission(self, request):
        return True

    def has_change_permission(self, request, obj=None):
        return True


class TransactionalAdmin(_GuardedDeleteMixin, ModelAdmin):
    """Repair-level access for transactional records: edit & delete only.

    These rows originate in the app (sales, payments, ledger, stock); the
    console can fix or remove them but never fabricate them, keeping the
    app's invariants (receipt numbering, stock math) intact.
    """

    list_fullwidth = True

    def has_add_permission(self, request):
        return False

    def has_change_permission(self, request, obj=None):
        return True


def _plan_action(plan_name):
    def action(self, request, queryset):
        count = queryset.update(plan=plan_name)
        self.message_user(
            request, f"{count} tenant(s) moved to the {plan_name} plan.",
            level=messages.SUCCESS)
    action.__name__ = f"set_plan_{plan_name}"
    action.__qualname__ = action.__name__
    return action


@admin.register(models.Shop, site=velo_admin_site)
class ShopAdmin(FullPowerAdmin):
    list_display = ("id", "name", "business_type", "plan", "phone",
                    "location_badge", "suspension_badge", "test_badge",
                    "created_at")
    list_filter = (
        ("business_type", RelatedDropdownFilter),
        PlanFilter,
        LanguageFilter,
        SuspendedFilter,
        TestFilter,
    )
    list_filter_submit = True
    list_fullwidth = True
    search_fields = ("name", "phone", "address", "tin",
                     "telebirr_number", "cbe_number")
    search_help_text = "Search by name, phone, address, TIN or payment numbers"
    ordering = ("-created_at",)
    readonly_fields = ("id", "created_at", "suspended_at")
    actions = ("suspend_selected", "restore_selected",
               "mark_test", "unmark_test",
               "set_plan_free", "set_plan_starter",
               "set_plan_pro", "set_plan_business")
    fieldsets = (
        ("Identity", {"fields": ("name", "business_type", "plan", "language")}),
        ("Contact & location", {"fields": (
            "phone", "address", "tin", "latitude", "longitude")}),
        ("Payments", {"fields": (
            "currency", "telebirr_number", "cbe_number",
            "accept_telebirr", "accept_cbe", "accept_credit")}),
        ("Receipt", {"fields": ("receipt_footer",)}),
        ("System", {"fields": ("id", "created_at")}),
        ("Diagnostics — test tenant", {
            "classes": ("vp-test-zone",),
            "description": "Test/demo tenants are excluded from health bands, "
                           "avg health, the upsell pipeline and heartbeat "
                           "counts. Fully reversible — unflag when the shop "
                           "goes live.",
            "fields": ("is_test",),
        }),
        ("Danger zone — suspend tenant", {
            "classes": ("vp-danger-zone",),
            "description": "Suspension flags the tenant for the platform. "
                           "It never deletes data and is fully reversible.",
            "fields": ("is_suspended", "suspended_note", "suspended_at"),
        }),
    )

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

    @admin.display(boolean=None, description="Test")
    def test_badge(self, obj):
        if obj.is_test:
            return format_html(
                '<span class="vp-pill vp-pill-test">test</span>')
        return ""

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

    # v2.3.0 — test-tenant flag: keeps demo/signup-test shops out of the
    # radar's health bands, upsell pipeline and heartbeat denominators.
    @admin.action(description="Mark selected shops as TEST tenants")
    def mark_test(self, request, queryset):
        count = queryset.update(is_test=True)
        self.message_user(
            request,
            f"{count} shop(s) marked as test tenants — excluded from "
            "radar health stats.", level=messages.SUCCESS)

    @admin.action(description="Unmark test tenants (back to real)")
    def unmark_test(self, request, queryset):
        count = queryset.update(is_test=False)
        self.message_user(
            request,
            f"{count} shop(s) unmarked — back in radar health stats.",
            level=messages.SUCCESS)

    # Bulk plan management — the billing lever, one click away.
    set_plan_free = _plan_action("free")
    set_plan_free.short_description = "Move selected tenants to FREE plan"
    set_plan_starter = _plan_action("starter")
    set_plan_starter.short_description = "Move selected tenants to STARTER (299 ETB/mo)"
    set_plan_pro = _plan_action("pro")
    set_plan_pro.short_description = "Move selected tenants to PRO (599 ETB/mo)"
    set_plan_business = _plan_action("business")
    set_plan_business.short_description = "Move selected tenants to BUSINESS (999 ETB/mo)"


@admin.register(models.AdminAuthUser, site=velo_admin_site)
class AdminAuthUserAdmin(TransactionalAdmin):
    """Supabase auth accounts: view + ban/unban (no fabrication, no delete —
    banning blocks sign-in without destroying account history)."""

    allow_single_delete = False  # never delete auth accounts from the console

    list_display = ("phone", "email", "shop_name", "created_at",
                    "last_sign_in_at", "ban_badge")
    search_fields = ("phone", "email")
    search_help_text = "Search by phone or email"
    ordering = ("-created_at",)
    list_per_page = 50
    readonly_fields = ("id", "email", "phone", "email_confirmed_at",
                       "created_at", "last_sign_in_at",
                       "raw_user_meta_data", "banned_until")
    actions = ("ban_users", "unban_users")

    def get_readonly_fields(self, request, obj=None):
        return self.readonly_fields

    @admin.display(description="Status")
    def ban_badge(self, obj):
        if obj.banned_until:
            return format_html(
                '<span class="vp-pill vp-pill-suspended">banned</span>')
        return format_html('<span class="vp-pill vp-pill-active">ok</span>')

    @admin.action(description="Ban selected app users (blocks sign-in)")
    def ban_users(self, request, queryset):
        count = 0
        for user in queryset:
            with connection.cursor() as cur:
                cur.execute(
                    "update adminpanel.auth_users set banned_until = %s "
                    "where id = %s",
                    ["2099-01-01 00:00:00+00", str(user.id)])
            count += 1
        self.message_user(request,
                          f"{count} app user(s) banned (sign-in blocked).",
                          level=messages.WARNING)

    @admin.action(description="Unban selected app users")
    def unban_users(self, request, queryset):
        count = 0
        for user in queryset:
            with connection.cursor() as cur:
                cur.execute(
                    "update adminpanel.auth_users set banned_until = null "
                    "where id = %s", [str(user.id)])
            count += 1
        self.message_user(request, f"{count} app user(s) unbanned.",
                          level=messages.SUCCESS)


@admin.register(models.Staff, site=velo_admin_site)
class StaffAdmin(FullPowerAdmin):
    list_display = ("id", "name", "shop", "role", "phone",
                    "commission_percent", "active", "created_at")
    list_filter = (StaffRoleFilter, "active", ("shop", RelatedDropdownFilter))
    list_filter_submit = True
    search_fields = ("name", "phone")
    list_select_related = ("shop",)


@admin.register(models.Item, site=velo_admin_site)
class ItemAdmin(FullPowerAdmin):
    list_display = ("id", "name", "shop", "type", "price", "cost",
                    "stock_qty", "barcode", "is_active", "created_at")
    list_filter = (ItemTypeFilter, "is_active",
                   ("shop", RelatedDropdownFilter))
    list_filter_submit = True
    search_fields = ("name", "barcode", "description")
    search_help_text = "Search by name, barcode or description"
    list_select_related = ("shop",)


@admin.register(models.ItemVariant, site=velo_admin_site)
class ItemVariantAdmin(FullPowerAdmin):
    list_display = ("id", "item", "shop", "stock_qty", "price_override",
                    "sku", "barcode", "is_active")
    list_filter = ("is_active", ("shop", RelatedDropdownFilter))
    list_filter_submit = True
    search_fields = ("sku", "barcode")
    list_select_related = ("item", "shop")
    ordering = ("-id",)


@admin.register(models.Category, site=velo_admin_site)
class CategoryAdmin(FullPowerAdmin):
    list_display = ("id", "name", "shop", "created_at")
    list_filter = (("shop", RelatedDropdownFilter),)
    list_filter_submit = True
    search_fields = ("name",)
    list_select_related = ("shop",)


@admin.register(models.Customer, site=velo_admin_site)
class CustomerAdmin(FullPowerAdmin):
    list_display = ("id", "name", "shop", "phone", "balance", "created_at")
    list_filter = (("shop", RelatedDropdownFilter),)
    list_filter_submit = True
    search_fields = ("name", "phone")
    list_select_related = ("shop",)


@admin.register(models.Sale, site=velo_admin_site)
class SaleAdmin(TransactionalAdmin):
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
    fieldsets = (
        ("Sale", {"fields": ("shop", "receipt_number", "customer",
                             "customer_name", "staff", "staff_name")}),
        ("Money", {"fields": ("subtotal", "discount_total", "tax_total",
                              "total", "amount_paid", "change_due")}),
        ("Status", {"fields": ("method", "status", "reference",
                               "refund_reason")}),
        ("System", {"fields": ("id", "created_at")}),
    )
    readonly_fields = ("id", "created_at")


@admin.register(models.SaleItem, site=velo_admin_site)
class SaleItemAdmin(TransactionalAdmin):
    list_display = ("id", "sale", "shop", "name_snapshot", "qty",
                    "unit_price", "line_total")
    list_filter = (("shop", RelatedDropdownFilter),)
    list_filter_submit = True
    search_fields = ("name_snapshot",)
    list_select_related = ("sale", "shop")
    readonly_fields = ("id",)


@admin.register(models.SalePayment, site=velo_admin_site)
class SalePaymentAdmin(TransactionalAdmin):
    list_display = ("id", "sale", "shop", "method", "amount",
                    "reference_number", "status")
    list_filter = (PaymentMethodFilter, PaymentStatusFilter,
                   ("shop", RelatedDropdownFilter))
    list_filter_submit = True
    list_select_related = ("sale", "shop")
    ordering = ("-id",)
    readonly_fields = ("id",)


@admin.register(models.LedgerEntry, site=velo_admin_site)
class LedgerEntryAdmin(TransactionalAdmin):
    list_display = ("id", "shop", "customer", "type", "amount",
                    "balance_after", "staff_name", "created_at")
    list_filter = (LedgerTypeFilter, ("shop", RelatedDropdownFilter))
    list_filter_submit = True
    date_hierarchy = "created_at"
    list_select_related = ("shop", "customer")
    readonly_fields = ("id", "created_at")


@admin.register(models.Expense, site=velo_admin_site)
class ExpenseAdmin(FullPowerAdmin):
    list_display = ("id", "shop", "category", "amount", "spent_date", "note")
    list_filter = (("shop", RelatedDropdownFilter),)
    list_filter_submit = True
    date_hierarchy = "created_at"
    list_select_related = ("shop", "category")


@admin.register(models.ExpenseCategory, site=velo_admin_site)
class ExpenseCategoryAdmin(FullPowerAdmin):
    list_display = ("id", "name", "shop")
    list_filter = (("shop", RelatedDropdownFilter),)
    list_filter_submit = True
    search_fields = ("name",)
    list_select_related = ("shop",)
    ordering = ("-id",)


@admin.register(models.StockMovement, site=velo_admin_site)
class StockMovementAdmin(TransactionalAdmin):
    list_display = ("id", "shop", "item", "qty_change", "reason", "created_at")
    list_filter = (StockReasonFilter, ("shop", RelatedDropdownFilter))
    list_filter_submit = True
    date_hierarchy = "created_at"
    list_select_related = ("shop", "item")
    readonly_fields = ("id", "created_at")


@admin.register(models.HeldSale, site=velo_admin_site)
class HeldSaleAdmin(FullPowerAdmin):
    list_display = ("id", "shop", "label", "created_at")
    list_filter = (("shop", RelatedDropdownFilter),)
    list_filter_submit = True
    list_select_related = ("shop",)
    ordering = ("-created_at",)


@admin.register(models.BusinessType, site=velo_admin_site)
class BusinessTypeAdmin(FullPowerAdmin):
    list_display = ("key", "sort")
