"""
Django settings for the Velo OWNER ADMIN console.

Architecture (v1.6.0):
- The Flutter app talks to Supabase directly (PostgREST + RLS). This Django
  project does NOT replace that. It is a private, server-rendered console for
  the product owner, connected to the SAME live Supabase Postgres through the
  IPv4 session pooler, logging in with the dedicated `velo_admin` DB role
  (BYPASSRLS — same visibility as Supabase Studio, no JWT/RLS involvement).
- Django's OWN tables (owner login, sessions, admin audit log, migrations)
  live in the private `django_admin` schema (never in `public`, so PostgREST
  can never expose them). Business tables in `public` are used via unmanaged
  models (no migrations are ever emitted against them).
- search_path is set per-connection in adminpanel.apps (the Supavisor pooler
  strips startup `options`, so it cannot be set in DATABASES OPTIONS).
"""
import os
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent.parent


def _load_env(path: Path) -> None:
    """Tiny .env loader (no extra dependency). Existing env vars win."""
    if path.exists():
        for line in path.read_text().splitlines():
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                key, val = line.split("=", 1)
                os.environ.setdefault(key.strip(), val.strip())


_load_env(BASE_DIR / ".env")

SECRET_KEY = os.environ.get(
    "SECRET_KEY", "django-insecure-velo-admin-dev-key-not-for-production")
DEBUG = os.environ.get("VELO_DEBUG", "0") == "1"
# v2.8.0 — pinned instead of "*": Host-header validation is back on. The
# leading-dot entry covers the prod domain AND Vercel preview deployments;
# localhost entries keep local dev working.
ALLOWED_HOSTS = [".vercel.app", "localhost", "127.0.0.1"]
# Sandbox preview, Render, localhost — CSRF only trusts POSTs from these origins.
CSRF_TRUSTED_ORIGINS = [
    "https://*.space-z.ai",
    "https://*.onrender.com",
    "https://novelwolde.pythonanywhere.com",
    "https://*.vercel.app",
    "http://localhost:3000",
    "http://127.0.0.1:3000",
]

INSTALLED_APPS = [
    "unfold",                     # modern admin theme — MUST precede django.contrib.admin
    "unfold.contrib.filters",    # dropdown/numeric filter widgets
    "django.contrib.admin",
    "django.contrib.auth",
    "django.contrib.contenttypes",
    "django.contrib.sessions",
    "django.contrib.messages",
    "django.contrib.staticfiles",
    "adminpanel",
]

MIDDLEWARE = [
    "django.middleware.security.SecurityMiddleware",
    "adminpanel.middleware.ContentSecurityPolicyMiddleware",
    "whitenoise.middleware.WhiteNoiseMiddleware",
    "django.contrib.sessions.middleware.SessionMiddleware",
    "django.middleware.common.CommonMiddleware",
    "django.middleware.csrf.CsrfViewMiddleware",
    "django.contrib.auth.middleware.AuthenticationMiddleware",
    "django.contrib.messages.middleware.MessageMiddleware",
    "django.middleware.clickjacking.XFrameOptionsMiddleware",
]

ROOT_URLCONF = "config.urls"
WSGI_APPLICATION = "config.wsgi.application"

TEMPLATES = [
    {
        "BACKEND": "django.template.backends.django.DjangoTemplates",
        # DIRS precedes APP_DIRS, so adminpanel's admin/login.html outranks
        # the one bundled with unfold (which sits earlier in INSTALLED_APPS).
        "DIRS": [BASE_DIR / "adminpanel" / "templates"],
        "APP_DIRS": True,
        "OPTIONS": {
            "context_processors": [
                "django.template.context_processors.request",
                "django.contrib.auth.context_processors.auth",
                "django.contrib.messages.context_processors.messages",
            ],
        },
    },
]

_database = {
    "ENGINE": "django.db.backends.postgresql",
    "NAME": os.environ.get("VELO_DB_NAME", "postgres"),
    "USER": os.environ["VELO_DB_USER"],
    "PASSWORD": os.environ["VELO_DB_PASSWORD"],
    "HOST": os.environ["VELO_DB_HOST"],
    "PORT": os.environ.get("VELO_DB_PORT", "5432"),
    "CONN_MAX_AGE": int(os.environ.get("VELO_CONN_MAX_AGE", "120")),
    "OPTIONS": {"sslmode": "require"},
    "ATOMIC_REQUESTS": False,
}
DATABASES = {"default": _database}

AUTH_PASSWORD_VALIDATORS = [
    {"NAME": "django.contrib.auth.password_validation.MinimumLengthValidator"},
]

LANGUAGE_CODE = "en-us"
TIME_ZONE = "Africa/Addis_Ababa"  # everything the owner sees speaks Addis time
USE_I18N = True
USE_TZ = True

STATIC_URL = "static/"
_static_root_env = os.environ.get("VELO_STATIC_ROOT")
# `static_root/` is the committed, pre-collected bundle used by the Vercel
# serverless bundle (whitenoise serves straight from it in production).
STATIC_ROOT = Path(_static_root_env) if _static_root_env else BASE_DIR / "static_root"
STORAGES = {
    "default": {"BACKEND": "django.core.files.storage.FileSystemStorage"},
    "staticfiles": {"BACKEND": "whitenoise.storage.CompressedManifestStaticFilesStorage"},
}

DEFAULT_AUTO_FIELD = "django.db.models.BigAutoField"

# ---------------------------------------------------------------------------
# Unfold theme — Velo brand (Ethiopian deep green #0E7A3D + gold #E8A200,
# mirroring flutter_app/lib/theme/app_theme.dart).
# ---------------------------------------------------------------------------
_VELO_GREEN = {
    "50": "#ECFDF3",
    "100": "#D3F8DF",
    "200": "#A9EFC6",
    "300": "#71E0A6",
    "400": "#3FCA85",
    "500": "#14A457",
    "600": "#0E7A3D",   # brand primary (app seed color)
    "700": "#0B5D30",
    "800": "#0A4D28",
    "900": "#093F22",
    "950": "#052A16",
}

UNFOLD = {
    "SITE_TITLE": "Velo Admin",
    "SITE_HEADER": "Velo Owner Console",
    "SITE_SUBHEADER": "Live platform data · Addis Ababa time",
    "SITE_VERSION": "v2.8.0",
    "SITE_URL": "/admin/",
    "SITE_LOGO": "/static/adminpanel/velo.svg",
    "SITE_FAVICONS": [
        {"href": "/static/adminpanel/velo.svg", "type": "image/svg+xml"},
    ],
    # NOTE: no UNFOLD "LOGIN" image — the custom login template renders a
    # contained brand panel instead of the cover-cropped watermark.
    "COLORS": {"primary": _VELO_GREEN},
    "STYLES": ["/static/adminpanel/velo_admin.css"],
    "SIDEBAR": {
        "show_search": True,
        "show_all_applications": False,
        "navigation": [
            {"title": "Overview", "items": [
                {"title": "Dashboard", "icon": "dashboard", "link": "/admin/"},
                {"title": "Money Radar", "icon": "radar",
                 "link": "/admin/money-radar/"},
                {"title": "Owner audit", "icon": "history",
                 "link": "/admin/audit/"},
            ]},
            {"title": "Tenancy", "items": [
                {"title": "Shops", "icon": "storefront",
                 "link": "/admin/adminpanel/shop/"},
                {"title": "App users", "icon": "group",
                 "link": "/admin/adminpanel/adminauthuser/"},
                {"title": "Business types", "icon": "category",
                 "link": "/admin/adminpanel/businesstype/"},
            ]},
            {"title": "Sales", "items": [
                {"title": "Sales", "icon": "receipt_long",
                 "link": "/admin/adminpanel/sale/"},
                {"title": "Sale items", "icon": "receipt",
                 "link": "/admin/adminpanel/saleitem/"},
                {"title": "Sale payments", "icon": "payments",
                 "link": "/admin/adminpanel/salepayment/"},
                {"title": "Customer ledger", "icon": "account_balance_wallet",
                 "link": "/admin/adminpanel/ledgerentry/"},
            ]},
            {"title": "Catalog", "items": [
                {"title": "Items", "icon": "inventory_2",
                 "link": "/admin/adminpanel/item/"},
                {"title": "Item variants", "icon": "layers",
                 "link": "/admin/adminpanel/itemvariant/"},
                {"title": "Categories", "icon": "folder",
                 "link": "/admin/adminpanel/category/"},
            ]},
            {"title": "Operations", "items": [
                {"title": "Staff", "icon": "badge",
                 "link": "/admin/adminpanel/staff/"},
                {"title": "Expenses", "icon": "account_balance",
                 "link": "/admin/adminpanel/expense/"},
                {"title": "Expense categories", "icon": "sell",
                 "link": "/admin/adminpanel/expensecategory/"},
                {"title": "Stock movements", "icon": "swap_vert",
                 "link": "/admin/adminpanel/stockmovement/"},
                {"title": "Held sales", "icon": "pause_circle",
                 "link": "/admin/adminpanel/heldsale/"},
            ]},
        ],
    },
}

# The owner account lives ONLY in the django_admin schema — completely
# separate from Supabase Auth tenant users.
SESSION_COOKIE_AGE = 60 * 60 * 8  # 8 hours
SESSION_COOKIE_NAME = "velo_admin_session"

if not DEBUG:
    SECURE_PROXY_SSL_HEADER = ("HTTP_X_FORWARDED_PROTO", "https")
    SECURE_SSL_REDIRECT = True
    SESSION_COOKIE_SECURE = True
    CSRF_COOKIE_SECURE = True
    SECURE_HSTS_SECONDS = 31536000
    SECURE_HSTS_INCLUDE_SUBDOMAINS = True

# explicit — Django's default is True since 3.0, but the probe should see intent
SECURE_CONTENT_TYPE_NOSNIFF = True
