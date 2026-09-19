"""Create or update the owner superuser from env vars (idempotent).

Usage: python manage.py bootstrap_admin
Env:   VELO_ADMIN_USER, VELO_ADMIN_PASSWORD, VELO_ADMIN_EMAIL (optional)
"""
import os

from django.contrib.auth import get_user_model
from django.core.management.base import BaseCommand, CommandError


class Command(BaseCommand):
    help = "Create/update the Velo owner superuser from env vars."

    def handle(self, *args, **options):
        username = os.environ.get("VELO_ADMIN_USER")
        password = os.environ.get("VELO_ADMIN_PASSWORD")
        if not username or not password:
            raise CommandError(
                "VELO_ADMIN_USER and VELO_ADMIN_PASSWORD must be set "
                "(backend/.env in the sandbox, Render env vars in prod).")
        User = get_user_model()
        user, created = User.objects.update_or_create(
            username=username,
            defaults={
                "email": os.environ.get("VELO_ADMIN_EMAIL", "owner@velo.app"),
                "is_staff": True,
                "is_superuser": True,
                "is_active": True,
            },
        )
        user.set_password(password)
        user.save()
        self.stdout.write(self.style.SUCCESS(
            f"{'Created' if created else 'Updated'} owner superuser '{username}'"))
