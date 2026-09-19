from django.apps import AppConfig
from django.db.backends.signals import connection_created


def _set_search_path(sender, connection, **kwargs):
    """Set search_path on every new Postgres connection.

    The Supavisor session pooler strips startup `options`, so search_path
    cannot be configured in DATABASES. Django's own tables must land in the
    private `django_admin` schema (never `public`), business tables resolve
    from `public`, and the auth-users view from `adminpanel`.
    """
    if connection.vendor == "postgresql":
        with connection.cursor() as cur:
            cur.execute("SET search_path TO django_admin, adminpanel, public")


class AdminpanelConfig(AppConfig):
    default_auto_field = "django.db.models.BigAutoField"
    name = "adminpanel"
    verbose_name = "Velo Owner Console"

    def ready(self):
        connection_created.connect(
            _set_search_path, dispatch_uid="velo_admin_search_path")
