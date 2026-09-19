#!/usr/bin/env bash
# Render build: deps -> static -> Django tables (django_admin schema) -> owner superuser
set -euo pipefail
cd "$(dirname "$0")"
pip install -r requirements.txt
python manage.py collectstatic --noinput
python manage.py migrate
python manage.py bootstrap_admin
