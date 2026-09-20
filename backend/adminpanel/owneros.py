"""v2.9.0 — OWNER OS: console staff roles, per-tenant feature flags,
login-as impersonation kit.

Research-driven (how Stripe/Shopify/Pigment-class platforms run their own
back-office):

- RBAC (Oso/IBM least-privilege): every privileged path re-checks the
  actor's role SERVER-SIDE. Roles: owner > support > observer. Unknown or
  unlisted console users default to `observer` (default-deny). The Django
  superuser is always `owner`. Roles live in django_admin.console_roles
  (lazy table — zero migrations, same pattern as login_throttle).

- Impersonation (Pigment engineering, catjam.fi's Supabase recipe): never
  touch or share tenant passwords. The console mints a SHORT-LIVED
  magic-link + OTP via Supabase Auth Admin API (generate_link, service
  role) — nothing is emailed, nothing is stored, every issuance is
  audited with the impersonated identity. App-side consumption (support
  sign-in hook) is the queued Flutter counterpart.

- Feature flags (LaunchDarkly/ConfigCat/Schematic): per-tenant booleans in
  public.tenant_flags with RLS SELECT-only for app users. The console is
  the only writer. Catalog flags are plan/monetization levers + a
  per-tenant kill switch; custom keys are allowed for experiments.
"""
import re
import urllib.error
import urllib.request

from django.conf import settings
from django.contrib.auth import get_user_model
from django.db import connection

# ---------------------------------------------------------------------------
# Console staff RBAC
# ---------------------------------------------------------------------------

ROLES = {
    "owner":    {"rank": 3, "label": "Owner",
                 "blurb": "Full power — billing, deletes, console staff"},
    "support":  {"rank": 2, "label": "Support",
                 "blurb": "Read everything · notes, flags, bans, suspend — "
                          "no deletes, no plan moves, no staff mgmt"},
    "observer": {"rank": 1, "label": "Observer",
                 "blurb": "Read-only — dashboards, tenants, audit trail"},
}
_ROLE_RANK = {k: v["rank"] for k, v in ROLES.items()}
_FLAG_NAME_RE = re.compile(r"^[a-z0-9_]{2,64}$")


def _ensure_roles_table(cur) -> None:
    cur.execute(
        "create table if not exists django_admin.console_roles ("
        "user_id bigint primary key references django_admin.auth_user(id) "
        "  on delete cascade, "
        "role text not null check (role in ('owner','support','observer')), "
        "updated_by text not null default '', "
        "updated_at timestamptz not null default now())")


def role_of(user) -> str:
    """Resolve a console user's role. Superuser = owner; unlisted users
    default to observer (default-deny — least privilege)."""
    if user is None or not getattr(user, "is_authenticated", False):
        return "observer"
    if getattr(user, "is_superuser", False):
        return "owner"
    try:
        with connection.cursor() as cur:
            _ensure_roles_table(cur)
            cur.execute(
                "select role from django_admin.console_roles where user_id = %s",
                [user.pk])
            row = cur.fetchone()
    except Exception:
        return "observer"
    return row[0] if row and row[0] in ROLES else "observer"


def rank(user) -> int:
    return _ROLE_RANK.get(role_of(user), 1)


def role_of_by_id(user_id: int) -> str:
    """Resolve a role by console user id (staff page edits, guards)."""
    if not user_id:
        return "observer"
    try:
        with connection.cursor() as cur:
            _ensure_roles_table(cur)
            cur.execute(
                "select coalesce(r.role, case when u.is_superuser "
                "then 'owner' end) "
                "from django_admin.auth_user u "
                "left join django_admin.console_roles r on r.user_id = u.id "
                "where u.id = %s", [user_id])
            row = cur.fetchone()
    except Exception:
        return "observer"
    return row[0] if row and row[0] in ROLES else "observer"


def at_least(user, minimum: str) -> bool:
    """Server-side gate: user's role >= minimum role."""
    return rank(user) >= _ROLE_RANK.get(minimum, 99)


def set_role(user_id: int, role: str, updated_by: str) -> bool:
    if role not in ROLES:
        return False
    with connection.cursor() as cur:
        _ensure_roles_table(cur)
        cur.execute(
            "insert into django_admin.console_roles (user_id, role, updated_by) "
            "values (%s, %s, %s) on conflict (user_id) do update "
            "set role = excluded.role, updated_by = excluded.updated_by, "
            "updated_at = now()", [user_id, role, updated_by])
    return True


def staff_list() -> list:
    """Console users + roles, for the owner-only staff page."""
    with connection.cursor() as cur:
        _ensure_roles_table(cur)
        cur.execute(
            "select u.id, u.username, u.is_active, u.is_superuser, "
            "u.last_login, u.date_joined, "
            "coalesce(r.role, case when u.is_superuser then 'owner' end) as role, "
            "r.updated_by, r.updated_at "
            "from django_admin.auth_user u "
            "left join django_admin.console_roles r on r.user_id = u.id "
            "order by u.id")
        cols = [c[0] for c in cur.description]
        return [dict(zip(cols, r)) for r in cur.fetchall()]


def create_staff_user(username: str, password: str, role: str,
                      updated_by: str):
    """Create a non-superuser console account with is_staff=True and the
    chosen role. Returns (user, error)."""
    username = (username or "").strip()
    if not username or len(username) > 150:
        return None, "Username is required (max 150 chars)."
    if role not in ("support", "observer"):
        return None, "Role must be support or observer."
    if len(password or "") < 10:
        return None, "Password must be at least 10 characters."
    User = get_user_model()
    if User.objects.filter(username__iexact=username).exists():
        return None, f"Username “{username}” already exists."
    user = User.objects.create_user(username=username, password=password)
    user.is_staff = True
    user.is_superuser = False
    user.save(update_fields=["is_staff", "is_superuser"])
    set_role(user.pk, role, updated_by)
    return user, None


def set_active(user_id: int, active: bool, acting_user) -> str | None:
    """Deactivate/reactivate a console user. Guards: never yourself, never
    the last active owner."""
    User = get_user_model()
    if user_id == acting_user.pk and not active:
        return "You cannot deactivate your own account."
    with connection.cursor() as cur:
        _ensure_roles_table(cur)
        cur.execute(
            "select coalesce(r.role, case when u.is_superuser then 'owner' end), "
            "u.is_active from django_admin.auth_user u "
            "left join django_admin.console_roles r on r.user_id = u.id "
            "where u.id = %s", [user_id])
        row = cur.fetchone()
    if not row:
        return "Console user not found."
    role, is_active = row[0], bool(row[1])
    if is_active and not active and role == "owner":
        cur_ok = True
        with connection.cursor() as cur:
            cur.execute(
                "select count(*) from django_admin.auth_user u "
                "left join django_admin.console_roles r on r.user_id = u.id "
                "where u.is_active and coalesce(r.role, "
                "case when u.is_superuser then 'owner' end) = 'owner'")
            cur_ok = (cur.fetchone() or [0])[0] > 1
        if not cur_ok:
            return "Refusing to deactivate the last active owner."
    User.objects.filter(pk=user_id).update(is_active=active)
    return None


# ---------------------------------------------------------------------------
# Per-tenant feature flags
# ---------------------------------------------------------------------------

FLAGS_CATALOG = [
    {"flag": "receipt_ads", "label": "Receipt ads",
     "desc": "Promo footer on customer receipts — the free-plan "
             "monetization lever. Turn off for paying plans."},
    {"flag": "ai_insights", "label": "AI insights",
     "desc": "AI-powered sales insights & suggestions (beta)."},
    {"flag": "beta_reports", "label": "Beta reports",
     "desc": "Opt-in analytics screens still under development."},
    {"flag": "maintenance_mode", "label": "Maintenance mode",
     "desc": "Per-tenant kill switch — the app shows a maintenance notice "
             "instead of live data. Use only for incidents."},
]


def valid_flag_name(flag: str) -> bool:
    return bool(_FLAG_NAME_RE.match(flag or ""))


def tenant_flags(shop_id: int) -> list:
    with connection.cursor() as cur:
        cur.execute(
            "select flag, enabled, note, updated_at, updated_by "
            "from public.tenant_flags where shop_id = %s order by flag",
            [shop_id])
        cols = [c[0] for c in cur.description]
        return [dict(zip(cols, r)) for r in cur.fetchall()]


def tenant_flags_map() -> dict:
    """{shop_id: {flag: enabled}} for the whole flags matrix page."""
    with connection.cursor() as cur:
        cur.execute(
            "select shop_id, flag, enabled from public.tenant_flags")
        out: dict = {}
        for shop_id, flag, enabled in cur.fetchall():
            out.setdefault(shop_id, {})[flag] = bool(enabled)
        return out


def set_flag(shop_id: int, flag: str, enabled: bool, note: str,
             updated_by: str) -> None:
    with connection.cursor() as cur:
        cur.execute(
            "insert into public.tenant_flags "
            "(shop_id, flag, enabled, note, updated_by) "
            "values (%s, %s, %s, %s, %s) "
            "on conflict (shop_id, flag) do update set "
            "enabled = excluded.enabled, note = excluded.note, "
            "updated_at = now(), updated_by = excluded.updated_by",
            [shop_id, flag, bool(enabled), (note or "")[:200], updated_by])


def delete_flag(shop_id: int, flag: str) -> None:
    with connection.cursor() as cur:
        cur.execute("delete from public.tenant_flags where shop_id = %s "
                    "and flag = %s", [shop_id, flag])


# ---------------------------------------------------------------------------
# Login-as impersonation kit (Supabase Auth Admin API)
# ---------------------------------------------------------------------------

class LoginAsError(Exception):
    pass


def sb_config() -> tuple[str, str]:
    url = getattr(settings, "VELO_SB_URL", "") or ""
    key = getattr(settings, "VELO_SB_SERVICE_KEY", "") or ""
    return url, key


def impersonation_available() -> bool:
    return bool(sb_config()[0] and sb_config()[1])


def impersonation_targets(shop_id: int) -> list:
    """Auth-linked users of this shop (staff.user_id → auth.users), best
    target first (staff role 'owner' wins)."""
    with connection.cursor() as cur:
        cur.execute(
            "select au.id, au.email, s.name as staff_name, s.role as staff_role "
            "from public.staff s "
            "join adminpanel.auth_users au on au.id = s.user_id "
            "where s.shop_id = %s and s.active "
            "order by (s.role = 'owner') desc, s.name",
            [shop_id])
        cols = [c[0] for c in cur.description]
        return [dict(zip(cols, r)) for r in cur.fetchall()]


def login_as_kit(shop_id: int, user_id: str | None = None) -> dict:
    """Mint a short-lived sign-in kit for one of the shop's auth users.

    Supabase admin generate_link (type=magiclink) returns an action_link,
    a 6-digit OTP and a hashed token — nothing is emailed, no password is
    touched, no state is stored here. The caller must audit + display-once.
    """
    url, key = sb_config()
    if not (url and key):
        raise LoginAsError(
            "Impersonation is not configured on this deployment "
            "(missing VELO_SB_URL / VELO_SB_SERVICE_KEY).")

    targets = impersonation_targets(shop_id)
    if not targets:
        raise LoginAsError(
            "No auth-linked staff on this tenant — the shop has no app "
            "account to sign into.")
    target = next((t for t in targets if user_id and str(t["id"]) == user_id),
                  targets[0])
    email = target.get("email") or ""
    if not email:
        raise LoginAsError("Target user has no email identity.")

    body = {"type": "magiclink", "email": email}
    req = urllib.request.Request(
        f"{url}/auth/v1/admin/generate_link",
        data=__import__("json").dumps(body).encode(),
        headers={"apikey": key, "Authorization": f"Bearer {key}",
                 "Content-Type": "application/json"}, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=20) as resp:
            out = __import__("json").loads(resp.read().decode())
    except urllib.error.HTTPError as e:
        detail = ""
        try:
            detail = e.read().decode()[:200]
        except Exception:
            pass
        raise LoginAsError(f"Supabase auth admin API error {e.code}: {detail}")
    except Exception as e:  # network etc.
        raise LoginAsError(f"Supabase auth admin API unreachable: {e}")

    meta = out.get("user_metadata") or {}
    return {
        "shop_id": shop_id,
        "user_id": out.get("id") or target["id"],
        "email": out.get("email") or email,
        "name": target.get("staff_name") or meta.get("name") or email,
        "otp": out.get("email_otp") or "",
        "action_link": out.get("action_link") or "",
        "verification_type": out.get("verification_type") or "magiclink",
        "target_role": target.get("staff_role") or "",
    }
