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
    # Django's default LOGIN_REDIRECT_URL — land on the dashboard instead
    # of a 404 when someone logs in via /admin/login/ without ?next=.
    path("accounts/profile/", RedirectView.as_view(url="/admin/", permanent=False)),
    path("", RedirectView.as_view(url="/admin/", permanent=False)),
]
