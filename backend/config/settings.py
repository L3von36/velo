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
ALLOWED_HOSTS = ["*"]
# Sandbox preview, Render, localhost — CSRF only trusts POSTs from these origins.
CSRF_TRUSTED_ORIGINS = [
    "https://*.space-z.ai",
    "https://*.onrender.com",
    "http://localhost:3000",
    "http://127.0.0.1:3000",
]

INSTALLED_APPS = [
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
        "DIRS": [],
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
    "CONN_MAX_AGE": 120,
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
STATIC_ROOT = BASE_DIR / "staticfiles"
STORAGES = {
    "default": {"BACKEND": "django.core.files.storage.FileSystemStorage"},
    "staticfiles": {"BACKEND": "whitenoise.storage.CompressedManifestStaticFilesStorage"},
}

DEFAULT_AUTO_FIELD = "django.db.models.BigAutoField"

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
