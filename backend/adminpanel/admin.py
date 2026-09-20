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

v2.4.0 — OWNER OS (research-driven: how Stripe/Shopify-class platforms run
their own back-office):
- Owner audit trail: every privileged action taken through the console
  (suspend, restore, ban, unban, plan moves, test flags, deletes, notes)
  is appended to adminpanel.owner_audit — actor, target, details, IP — and
  surfaced on a filterable, reviewable page at /admin/audit/.
- Tenant 360 at /admin/tenant/<id>/: support-grade, read-only dossier
  (the safe stand-in for login-as impersonation) with CRM notes and
  audited quick actions (plan move, test flag).
- Call-sheet CSV export at /admin/money-radar/export.csv.

v2.9.0 — OWNER OS II (impersonation, feature flags, staff RBAC):
- Login-as kit at /admin/tenant/<id>/login-as/: mints a SHORT-LIVED
  Supabase magic link + 6-digit OTP for one of the tenant's auth users
  (admin generate_link via service key) — no passwords touched, nothing
  stored, every issuance audited (user.loginas). The tenant-360 "login
  as" card targets the shop's owner-role account.
- Feature flags at /admin/flags/ (matrix) + per-tenant card on tenant
  360: public.tenant_flags booleans, RLS read-only for app users, console
  is the only writer (tenant.flag_set audited). Catalog: receipt ads,
  AI insights, beta reports, maintenance kill switch — plus custom keys.
- Console staff RBAC at /admin/staff/ (owner-only page): roles
  owner > support > observer in django_admin.console_roles, default-deny
  for unlisted users. Every ModelAdmin and custom view re-checks the
  role server-side; Django superuser is always owner.
"""
import csv

from django.contrib import admin, messages
from django.contrib.auth.signals import user_login_failed
from django.core.exceptions import PermissionDenied
from django.db import connection, IntegrityError, transaction
from django.http import HttpResponse, HttpResponseRedirect
from django.shortcuts import render
from django.urls import path
from django.utils.html import format_html
from unfold.admin import ModelAdmin
from unfold.contrib.filters.admin import RangeNumericFilter, RelatedDropdownFilter
from unfold.sites import UnfoldAdminSite

from . import models
from . import owneros
from . import throttle
from .dashboard import (
    PERIODS,
    PLAN_PRICES_ETB,
    add_note,
    audit_actions,
    audit_trail,
    kpis,
    money_radar,
    radar_call_sheet,
    tenant_360,
)
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


def _require_role(minimum: str):
    """v2.9.0 — server-side role gate for custom admin views.
    Insufficient role raises 403 (never a silent UI hide)."""
    def deco(fn):
        def wrapper(self, request, *args, **kwargs):
            if not owneros.at_least(request.user, minimum):
                raise PermissionDenied(
                    f"Your console role ({owneros.ROLES[owneros.role_of(request.user)]['label']}) "
                    f"does not allow this action — minimum: "
                    f"{owneros.ROLES[minimum]['label']}.")
            return fn(self, request, *args, **kwargs)
        wrapper.__name__ = fn.__name__
        wrapper.__qualname__ = fn.__qualname__
        return wrapper
    return deco


class VeloAdminSite(UnfoldAdminSite):
    site_header = "Velo Owner Console"
    site_title = "Velo Admin"
    index_title = "Platform overview"
    index_template = "admin/velo_index.html"

    def each_context(self, request):
        ctx = super().each_context(request)
        role = owneros.role_of(request.user)
        ctx["velo_role"] = role
        ctx["velo_role_label"] = owneros.ROLES[role]["label"]
        ctx["velo_role_blurb"] = owneros.ROLES[role]["blurb"]
        return ctx

    def login(self, request, extra_context=None):
        """v2.8.0 — brute-force gate: after 5 failed attempts for the same
        username or source IP inside 15 minutes, further attempts (even with
        the right password) are bounced for the lockout window. Failures are
        recorded by the user_login_failed signal below."""
        if request.method == "POST":
            username = request.POST.get("username") or ""
            if throttle.is_locked(username, _client_ip(request)):
                messages.add_message(
                    request, messages.ERROR,
                    "Too many failed sign-in attempts — try again in "
                    f"{throttle.LOCKOUT_MINUTES} minutes.")
                return HttpResponseRedirect("/admin/login/")
        return super().login(request, extra_context=extra_context)

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
            path("money-radar/export.csv",
                 self.admin_view(self.radar_export),
                 name="velo_radar_export"),
            path("tenant/<int:shop_id>/",
                 self.admin_view(self.tenant_view),
                 name="velo_tenant360"),
            path("audit/",
                 self.admin_view(self.audit_view),
                 name="velo_audit"),
            path("tenant/suspend/",
                 self.admin_view(self.suspend_tenant),
                 name="velo_tenant_suspend_any"),
            path("tenant/<int:shop_id>/suspend/",
                 self.admin_view(self.suspend_tenant),
                 name="velo_tenant_suspend"),
            path("tenant/<int:shop_id>/restore/",
                 self.admin_view(self.restore_tenant),
                 name="velo_tenant_restore"),
            path("flags/",
                 self.admin_view(self.flags_view),
                 name="velo_flags"),
            path("staff/",
                 self.admin_view(self.staff_view),
                 name="velo_staff"),
            path("tenant/<int:shop_id>/login-as/",
                 self.admin_view(self.login_as_view),
                 name="velo_loginas"),
        ] + urls

    def money_radar_view(self, request):
        return render(request, "admin/velo_money_radar.html",
                      {"radar": money_radar(),
                       **self.each_context(request)})

    # ---- v2.9.0: feature-flag matrix (read: all roles · write: support+)
    def flags_view(self, request):
        if request.method == "POST":
            if not owneros.at_least(request.user, "support"):
                raise PermissionDenied("Support role or higher required to "
                                       "change tenant flags.")
            try:
                shop_id = int(request.POST.get("shop_id") or 0)
            except (TypeError, ValueError):
                shop_id = 0
            flag = (request.POST.get("flag") or "").strip()
            enabled = request.POST.get("enabled") == "1"
            if shop_id and owneros.valid_flag_name(flag):
                with connection.cursor() as cur:
                    cur.execute("select name from public.shops where id = %s",
                                [shop_id])
                    row = cur.fetchone()
                owneros.set_flag(shop_id, flag, enabled, "",
                                 request.user.username)
                _audit(request, "tenant.flag_set",
                       f"shop #{shop_id} {row[0] if row else ''}",
                       f"{flag} → {'ON' if enabled else 'OFF'}")
                messages.add_message(
                    request, messages.SUCCESS,
                    f"Flag “{flag}” {'enabled' if enabled else 'disabled'}.")
            else:
                messages.add_message(request, messages.ERROR,
                                     "Invalid flag or tenant.")
            return HttpResponseRedirect("/admin/flags/")
        with connection.cursor() as cur:
            cur.execute(
                "select id, name, plan, is_test, is_suspended "
                "from public.shops order by is_test, name")
            cols = [c[0] for c in cur.description]
            shops = [dict(zip(cols, r)) for r in cur.fetchall()]
        fmap = owneros.tenant_flags_map()
        tenants = [{**s, "flags": fmap.get(s["id"], {})} for s in shops]
        return render(request, "admin/velo_flags.html",
                      {"tenants": tenants,
                       "catalog": owneros.FLAGS_CATALOG,
                       "can_write": owneros.at_least(request.user, "support"),
                       **self.each_context(request)})

    # ---- v2.9.0: console staff RBAC (owner-only page)
    @_require_role("owner")
    def staff_view(self, request):
        if request.method == "POST":
            action = request.POST.get("action", "")
            if action == "create":
                user, err = owneros.create_staff_user(
                    request.POST.get("username"),
                    request.POST.get("password") or "",
                    request.POST.get("role") or "observer",
                    request.user.username)
                if err:
                    messages.add_message(request, messages.ERROR, err)
                else:
                    _audit(request, "staff.create",
                           f"console user {user.username}",
                           f"role {request.POST.get('role')}")
                    messages.add_message(
                        request, messages.SUCCESS,
                        f"Console user “{user.username}” created.")
            elif action == "role":
                try:
                    uid = int(request.POST.get("user_id") or 0)
                except (TypeError, ValueError):
                    uid = 0
                target = owneros.role_of_by_id(uid)
                new_role = request.POST.get("role") or ""
                if uid and target != "owner" and \
                        owneros.set_role(uid, new_role,
                                         request.user.username):
                    _audit(request, "staff.role",
                           f"console user #{uid}", f"role set → {new_role}")
                    messages.add_message(request, messages.SUCCESS,
                                         "Role updated.")
                else:
                    messages.add_message(
                        request, messages.ERROR,
                        "Could not set role (owners keep their role; "
                        "invalid role value).")
            elif action == "active":
                try:
                    uid = int(request.POST.get("user_id") or 0)
                except (TypeError, ValueError):
                    uid = 0
                active = request.POST.get("active") == "1"
                err = owneros.set_active(uid, active, request.user)
                if err:
                    messages.add_message(request, messages.ERROR, err)
                else:
                    _audit(request, "staff.active", f"console user #{uid}",
                           "deactivated" if not active else "reactivated")
                    messages.add_message(request, messages.SUCCESS,
                                         "Account status updated.")
            return HttpResponseRedirect("/admin/staff/")
        return render(request, "admin/velo_staff.html",
                      {"staff": owneros.staff_list(),
                       "roles": owneros.ROLES,
                       **self.each_context(request)})

    # ---- v2.9.0: login-as impersonation kit (support+)
    @_require_role("support")
    def login_as_view(self, request, shop_id):
        if request.method != "POST":
            return HttpResponseRedirect(f"/admin/tenant/{shop_id}/")
        target = request.POST.get("user_id") or None
        try:
            kit = owneros.login_as_kit(shop_id, target)
        except owneros.LoginAsError as e:
            messages.add_message(request, messages.ERROR, str(e))
            return HttpResponseRedirect(f"/admin/tenant/{shop_id}/")
        _audit(request, "user.loginas",
               f"shop #{shop_id} {kit['name']}",
               f"magic link + OTP issued for {kit['email']} "
               f"(type={kit['verification_type']})")
        return render(request, "admin/velo_loginas.html",
                      {"kit": kit,
                       **self.each_context(request)})

    # ---- v2.4.0: tenant 360 (read-only dossier + notes + quick actions)
    # v2.9.0: role gates per action — note/test: support+, plan: owner.
    def tenant_view(self, request, shop_id):
        data = tenant_360(shop_id)
        if data is None:
            messages.add_message(request, messages.ERROR,
                                 f"Tenant #{shop_id} not found.")
            return HttpResponseRedirect("/admin/money-radar/")
        name = data["shop"]["name"]
        if request.method == "POST":
            action = request.POST.get("action", "")
            if action == "note":
                if not owneros.at_least(request.user, "support"):
                    raise PermissionDenied("Support role or higher required "
                                           "to add notes.")
                body = (request.POST.get("body") or "").strip()
                if body:
                    add_note(shop_id, request.user.username, body[:2000])
                    _audit(request, "tenant.note",
                           f"shop #{shop_id} {name}", body[:160])
                    messages.add_message(request, messages.SUCCESS,
                                         "Note added to the tenant trail.")
            elif action == "plan":
                if not owneros.at_least(request.user, "owner"):
                    raise PermissionDenied("Only the owner can move plans "
                                           "(billing lever).")
                plan = request.POST.get("plan", "")
                if plan in {"free", "starter", "pro", "business"}:
                    with connection.cursor() as cur:
                        cur.execute(
                            "update public.shops set plan = %s where id = %s",
                            [plan, shop_id])
                    _audit(request, "tenant.plan",
                           f"shop #{shop_id} {name}", f"plan set → {plan}")
                    messages.add_message(request, messages.SUCCESS,
                                         f"Tenant moved to the {plan} plan.")
            elif action == "test":
                if not owneros.at_least(request.user, "support"):
                    raise PermissionDenied("Support role or higher required "
                                           "to change the test flag.")
                flag = request.POST.get("flag") == "1"
                with connection.cursor() as cur:
                    cur.execute(
                        "update public.shops set is_test = %s where id = %s",
                        [flag, shop_id])
                _audit(request, "tenant.test_flag",
                       f"shop #{shop_id} {name}",
                       "marked as test tenant" if flag
                       else "unmarked — back to real")
                messages.add_message(request, messages.SUCCESS,
                                     "Test flag updated.")
            elif action == "flag":
                if not owneros.at_least(request.user, "support"):
                    raise PermissionDenied("Support role or higher required "
                                           "to change tenant flags.")
                flag = (request.POST.get("flag_name") or "").strip()
                enabled = request.POST.get("enabled") == "1"
                if owneros.valid_flag_name(flag):
                    owneros.set_flag(shop_id, flag, enabled,
                                     (request.POST.get("note") or "").strip(),
                                     request.user.username)
                    _audit(request, "tenant.flag_set",
                           f"shop #{shop_id} {name}",
                           f"{flag} → {'ON' if enabled else 'OFF'}")
                    messages.add_message(
                        request, messages.SUCCESS,
                        f"Flag “{flag}” {'enabled' if enabled else 'disabled'}.")
                else:
                    messages.add_message(
                        request, messages.ERROR,
                        "Flag keys are lowercase letters, digits and "
                        "underscores (2–64 chars).")
            return HttpResponseRedirect(f"/admin/tenant/{shop_id}/")
        return render(request, "admin/velo_tenant.html",
                      {"t360": data, "plan_choices": PLAN_PRICES_ETB,
                       "flags": owneros.tenant_flags(shop_id),
                       "catalog": owneros.FLAGS_CATALOG,
                       "imp_available": owneros.impersonation_available(),
                       "imp_targets": owneros.impersonation_targets(shop_id),
                       **self.each_context(request)})

    # ---- v2.4.0: owner audit trail page (who did what, when, from where)
    def audit_view(self, request):
        action = request.GET.get("action", "")
        q = (request.GET.get("q") or "").strip()
        return render(request, "admin/velo_audit.html",
                      {"entries": audit_trail(action=action, q=q),
                       "actions": audit_actions(),
                       "f_action": action, "f_q": q,
                       **self.each_context(request)})

    # ---- v2.4.0: call-sheet CSV export
    def radar_export(self, request):
        rows = radar_call_sheet()
        resp = HttpResponse(content_type="text/csv")
        resp["Content-Disposition"] = \
            'attachment; filename="velo-call-sheet.csv"'
        w = csv.writer(resp)
        if rows:
            w.writerow(list(rows[0].keys()))
            for r in rows:
                w.writerow([r[k] for k in rows[0].keys()])
        else:
            w.writerow(["tenant", "phone", "plan", "recommended",
                        "upside_etb_mo", "health", "band", "rev30",
                        "cnt30", "lifetime", "last_sale", "silent_days",
                        "churn_risk", "suspended"])
        return resp

    # ---- tenant suspension (danger zone) -------------------------------
    def _set_suspension(self, request, shop_id, suspend: bool):
        """Flip shops.is_suspended only — never touches business data.
        v2.9.0: support role or higher (server-side, not just UI)."""
        if not owneros.at_least(request.user, "support"):
            raise PermissionDenied("Support role or higher required to "
                                   "suspend or restore tenants.")
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
        _audit(request, "tenant.suspend" if suspend else "tenant.restore",
               f"shop #{shop_id} {name}", note)
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


def _client_ip(request) -> str:
    """Best-effort client IP for the audit trail (Vercel proxies set XFF)."""
    xff = (request.META.get("HTTP_X_FORWARDED_FOR") or "").split(",")[0].strip()
    return xff or request.META.get("REMOTE_ADDR", "")


def _record_login_failure(sender, credentials=None, request=None, **kwargs):
    """v2.8.0 — feed the brute-force throttle from Django's own signal so
    every failed authentication path is counted (username + source IP)."""
    try:
        throttle.record_failure(
            (credentials or {}).get("username") or "",
            _client_ip(request) if request is not None else "")
    except Exception:
        pass


user_login_failed.connect(_record_login_failure, weak=False)


def _audit(request, action: str, target: str, details: str = "") -> None:
    """v2.4.0 — append one privileged action to the owner audit trail.

    Research-backed (SOC 2 / Stripe-class ops): every console action that
    can change tenant state must land in a tamper-evident, reviewable
    trail — who, what, when, from where. Django's LogEntry already covers
    ORM saves; this covers the raw-SQL paths that used to bypass it.
    """
    try:
        with connection.cursor() as cur:
            cur.execute(
                "insert into adminpanel.owner_audit "
                "(actor, action, target, details, ip) "
                "values (%s, %s, %s, %s, %s)",
                [request.user.username, action, target, details or "",
                 _client_ip(request)])
    except Exception:  # never let audit logging break the action itself
        pass


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
            _audit(request, "record.delete",
                   f"{self.model._meta.verbose_name} #{obj.pk}",
                   str(obj)[:200])
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
                    _audit(request, "record.delete",
                           f"{opts.verbose_name} #{obj.pk}", str(obj)[:200])
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


class RoleGateMixin:
    """v2.9.0 — RBAC for every ModelAdmin page.

    owner:    add/change/delete as before (reference-guarded deletes).
    support:  view everything, change NOTHING through model forms —
              support acts through the audited custom views (tenant 360
              quick actions, flags, bans, suspensions) instead.
    observer: view-only, everywhere.

    The site itself already requires an active staff login; roles never
    widen access, they only narrow it.
    """

    def has_module_permission(self, request):
        return True  # all console roles may browse the sidebar

    def has_view_permission(self, request, obj=None):
        return True

    def has_add_permission(self, request):
        return owneros.at_least(request.user, "owner")

    def has_change_permission(self, request, obj=None):
        return owneros.at_least(request.user, "owner")

    def has_delete_permission(self, request, obj=None):
        return (owneros.at_least(request.user, "owner")
                and super().has_delete_permission(request, obj))


class FullPowerAdmin(RoleGateMixin, _GuardedDeleteMixin, ModelAdmin):
    """Owner-level CRUD: add, change, delete — the console's nuclear option
    (v2.9.0: owner role only — see RoleGateMixin)."""

    list_fullwidth = True


class TransactionalAdmin(RoleGateMixin, _GuardedDeleteMixin, ModelAdmin):
    """Repair-level access for transactional records: edit & delete only.

    These rows originate in the app (sales, payments, ledger, stock); the
    console can fix or remove them but never fabricate them, keeping the
    app's invariants (receipt numbering, stock math) intact.
    v2.9.0: owner role only for edits/deletes; adds stay impossible for
    everyone.
    """

    list_fullwidth = True

    def has_add_permission(self, request):
        return False  # transactional records are never fabricated


def _plan_action(plan_name):
    def action(self, request, queryset):
        names = {s.id: s.name for s in queryset}
        count = queryset.update(plan=plan_name)
        for sid, name in names.items():
            _audit(request, "tenant.plan", f"shop #{sid} {name}",
                   f"bulk move → {plan_name}")
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

    def save_model(self, request, obj, form, change):
        """Audit plan changes made through the shop change form — the one
        billing lever that used to be invisible to the audit trail."""
        old_plan = None
        if change and "plan" in form.changed_data:
            old_plan = (models.Shop.objects.filter(pk=obj.pk)
                        .values_list("plan", flat=True).first())
        super().save_model(request, obj, form, change)
        if change and "plan" in form.changed_data and old_plan != obj.plan:
            _audit(request, "tenant.plan", f"shop #{obj.pk} {obj.name}",
                   f"{old_plan} → {obj.plan}")

    @admin.action(description="Suspend selected tenants (reversible)",
                  permissions=["view"])
    def suspend_selected(self, request, queryset):
        if not owneros.at_least(request.user, "support"):
            self.message_user(request, "Support role or higher required.",
                              level=messages.ERROR)
            return
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

    @admin.action(description="Restore selected tenants", permissions=["view"])
    def restore_selected(self, request, queryset):
        if not owneros.at_least(request.user, "support"):
            self.message_user(request, "Support role or higher required.",
                              level=messages.ERROR)
            return
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
    # v2.9.0 — support+ (server-side), visible in list UI for all roles.
    @admin.action(description="Mark selected shops as TEST tenants",
                  permissions=["view"])
    def mark_test(self, request, queryset):
        if not owneros.at_least(request.user, "support"):
            self.message_user(request, "Support role or higher required.",
                              level=messages.ERROR)
            return
        names = [f"shop #{s.id} {s.name}" for s in queryset]
        count = queryset.update(is_test=True)
        for nm in names:
            _audit(request, "tenant.test_flag", nm, "marked as test tenant")
        self.message_user(
            request,
            f"{count} shop(s) marked as test tenants — excluded from "
            "radar health stats.", level=messages.SUCCESS)

    @admin.action(description="Unmark test tenants (back to real)",
                  permissions=["view"])
    def unmark_test(self, request, queryset):
        if not owneros.at_least(request.user, "support"):
            self.message_user(request, "Support role or higher required.",
                              level=messages.ERROR)
            return
        names = [f"shop #{s.id} {s.name}" for s in queryset]
        count = queryset.update(is_test=False)
        for nm in names:
            _audit(request, "tenant.test_flag", nm, "unmarked — back to real")
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

    list_display = ("phone_display", "email", "shop_name", "created_at",
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

    @admin.display(description="Phone", ordering="phone")
    def phone_display(self, obj):
        """v2.8.0 — the Phone column used to render '-' for every account:
        the real number hides inside <phone>@velo.app emails. Fall back to
        the local part when it looks like a phone number."""
        if obj.phone:
            return obj.phone
        email = obj.email or ""
        if email.endswith("@velo.app"):
            local = email.split("@")[0]
            if local.isdigit() and len(local) >= 9:
                return local
        return "—"

    @admin.display(description="Status")
    def ban_badge(self, obj):
        if obj.banned_until:
            return format_html(
                '<span class="vp-pill vp-pill-suspended">banned</span>')
        return format_html('<span class="vp-pill vp-pill-active">ok</span>')

    @admin.action(description="Ban selected app users (blocks sign-in)",
                  permissions=["view"])
    def ban_users(self, request, queryset):
        if not owneros.at_least(request.user, "support"):
            self.message_user(request, "Support role or higher required.",
                              level=messages.ERROR)
            return
        count = 0
        for user in queryset:
            with connection.cursor() as cur:
                cur.execute(
                    "update adminpanel.auth_users set banned_until = %s "
                    "where id = %s",
                    ["2099-01-01 00:00:00+00", str(user.id)])
            _audit(request, "user.ban",
                   f"app user {user.phone or user.email or user.id}")
            count += 1
        self.message_user(request,
                          f"{count} app user(s) banned (sign-in blocked).",
                          level=messages.WARNING)

    @admin.action(description="Unban selected app users", permissions=["view"])
    def unban_users(self, request, queryset):
        if not owneros.at_least(request.user, "support"):
            self.message_user(request, "Support role or higher required.",
                              level=messages.ERROR)
            return
        count = 0
        for user in queryset:
            with connection.cursor() as cur:
                cur.execute(
                    "update adminpanel.auth_users set banned_until = null "
                    "where id = %s", [str(user.id)])
            _audit(request, "user.unban",
                   f"app user {user.phone or user.email or user.id}")
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
