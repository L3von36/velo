"""Create or update owner/admin superusers from env vars (idempotent).

Usage: python manage.py bootstrap_admin

Accounts:
- VELO_ADMIN_USER / VELO_ADMIN_PASSWORD          -> the "owner" account
- VELO_ADMIN2_USER / VELO_ADMIN2_PASSWORD        -> optional second "admin"
                                                   account (same superuser
                                                   privileges, separate
                                                   credentials for a team
                                                   member)

Both accounts are Django superusers: inside the owner console they have
identical, maximum privileges. Separating the credentials lets the owner
revoke one without touching the other.
"""
import os

from django.contrib.auth import get_user_model
from django.core.management.base import BaseCommand, CommandError


class Command(BaseCommand):
    help = "Create/update Velo owner & admin superusers from env vars."

    def _upsert(self, username, password, email, label):
        User = get_user_model()
        user, created = User.objects.update_or_create(
            username=username,
            defaults={
                "email": email,
                "is_staff": True,
                "is_superuser": True,
                "is_active": True,
            },
        )
        user.set_password(password)
        user.save()
        self.stdout.write(self.style.SUCCESS(
            f"{'Created' if created else 'Updated'} {label} superuser "
            f"'{username}'"))

    def handle(self, *args, **options):
        username = os.environ.get("VELO_ADMIN_USER")
        password = os.environ.get("VELO_ADMIN_PASSWORD")
        if not username or not password:
            raise CommandError(
                "VELO_ADMIN_USER and VELO_ADMIN_PASSWORD must be set "
                "(backend/.env in the sandbox, platform env vars in prod).")
        self._upsert(username, password,
                     os.environ.get("VELO_ADMIN_EMAIL", "owner@velo.app"),
                     "owner")

        admin2_user = os.environ.get("VELO_ADMIN2_USER")
        admin2_password = os.environ.get("VELO_ADMIN2_PASSWORD")
        if admin2_user and admin2_password:
            self._upsert(admin2_user, admin2_password,
                         os.environ.get("VELO_ADMIN2_EMAIL",
                                        "admin@velo.app"),
                         "admin")
        elif admin2_user or admin2_password:
            self.stdout.write(self.style.WARNING(
                "VELO_ADMIN2_* partially set — both USER and PASSWORD are "
                "required to provision the second account; skipped."))
