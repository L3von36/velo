#!/bin/bash
# Velo owner-admin deploy for PythonAnywhere (run inside a scheduled task).
# Idempotent: safe to re-run on every deploy.
set -x
cd /home/novelwolde/velo/backend || exit 1

PY=$(ls /usr/bin/python3.1[2-3] 2>/dev/null | sort -V | tail -1)
[ -z "$PY" ] && PY=$(ls /usr/bin/python3.1* 2>/dev/null | sort -V | tail -1)
echo "using python: $PY"

if [ ! -x /home/novelwolde/velo-venv/bin/python ]; then
  "$PY" -m venv /home/novelwolde/velo-venv
fi
/home/novelwolde/velo-venv/bin/pip install -U pip wheel setuptools
/home/novelwolde/velo-venv/bin/pip install -r requirements.txt

/home/novelwolde/velo-venv/bin/python manage.py migrate --noinput
/home/novelwolde/velo-venv/bin/python manage.py bootstrap_admin
/home/novelwolde/velo-venv/bin/python manage.py collectstatic --noinput

echo PA_DEPLOY_DONE
