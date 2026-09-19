"""Velo owner-admin URLs: the admin console is the whole app."""
from django.http import HttpResponse
from django.urls import path
from django.views.generic import RedirectView

from adminpanel.admin import velo_admin_site


def healthz(_request):
    return HttpResponse("ok", content_type="text/plain")


urlpatterns = [
    # Health probe (Render) — no auth, no DB touch.
    path("healthz", healthz, name="healthz"),
    path("admin/", velo_admin_site.urls),
    path("", RedirectView.as_view(url="/admin/", permanent=False)),
]
