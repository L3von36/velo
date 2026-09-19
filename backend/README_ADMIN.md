# Velo Owner Admin (Django)

A private, server-rendered console for the **product owner** — you. It reads and
manages the SAME live Supabase Postgres that the Flutter app uses, but through a
dedicated DB role, so it sees across all tenants exactly like Supabase Studio
(no RLS, no JWT), while normal app users keep their RLS isolation.

## What it gives you

- **Dashboard**: shops, app users (active this week), catalog items, sales
  all-time / today / last-7d (all "today" boundaries in Addis Ababa time),
  expenses last 7d, newest shops, latest sales, shops by type & plan.
- **Shop (tenant) profiles — EDITABLE**: name, business type, plan, language,
  phone, address, TIN, GPS latitude/longitude, payment settings
  (Telebirr/CBE/credit), receipt footer. This is how you fix a tenant's profile
  when they can't.
- **Read-only visibility** (search + filter, cannot corrupt data):
  - App users (Supabase auth): phone/email, shop name, created, last sign-in
  - Catalog items + variants (price, cost, stock, barcode, per shop)
  - Sales + sale items + sale payments (date drill-down, per shop/method)
  - Staff, customers, ledger entries, expenses, stock movements, held carts
  - Business types
- **Audit log**: every change made through the console is recorded by Django
  (django_admin schema, viewable under "Log entries").
- **Safety model**: nothing can be added or deleted from the console; only shop
  profile fields are editable. Everything else is strictly view-only.

## Architecture (why this is safe)

| Concern | Design |
|---|---|
| DB role | `velo_admin` (LOGIN, BYPASSRLS) — created once by `scripts/provision_velo_admin.py` (in the sandbox toolkit), full DML on `public` tables |
| Django's own tables (owner login, sessions, audit log) | private **`django_admin` schema** — set via search_path on every connection (`adminpanel/apps.py`); PostgREST only ever exposes `public`, so these can never leak through the app's anon key |
| Supabase `auth.users` access | read-only **view `adminpanel.auth_users`** (private schema, no password hashes, only identity + activity); `anon`/`authenticated` explicitly revoked |
| Business tables | unmanaged Django models (`managed=False`) — Django never migrates/alters live data |
| Transport | TLS (`sslmode=require`) to the Supavisor session pooler (IPv4) |

The Flutter app is untouched: it still talks to Supabase PostgREST + Auth with
RLS. This console is a separate tool for you.

## Run it locally (sandbox / laptop)

```bash
cd backend
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
# .env must contain VELO_DB_* (host/port/user/password) — see .env.example
python manage.py migrate            # creates Django tables in django_admin schema
python manage.py bootstrap_admin    # creates/updates the owner superuser from env
python manage.py runserver 0.0.0.0:3000
```

Open `http://localhost:3000/admin/` and log in with `VELO_ADMIN_USER` /
`VELO_ADMIN_PASSWORD`.

Required env vars (put them in `backend/.env` — gitignored):

```
VELO_DB_HOST=aws-0-eu-central-1.pooler.supabase.com
VELO_DB_PORT=5432
VELO_DB_USER=velo_admin.izidltyssalvvsnievmq
VELO_DB_PASSWORD=<the velo_admin password>
VELO_ADMIN_USER=owner
VELO_ADMIN_PASSWORD=<your owner console password>
VELO_DEBUG=0            # 1 only for local dev
SECRET_KEY=<random string>
```

## Deploy it permanently (Render, free)

1. Push this repo to GitHub (already done for you).
2. Render → **New + → Blueprint** → pick the repo → Render reads `render.yaml`.
3. Fill the `sync: false` secrets: `VELO_DB_PASSWORD`, `VELO_ADMIN_USER`,
   `VELO_ADMIN_PASSWORD`.
4. Deploy. Build runs `build.sh` (deps → static → migrate → bootstrap_admin).
   Free plan sleeps after 15 min idle; the first visit wakes it (~30 s).

Any PaaS works the same way (Railway/Fly/PythonAnywhere): start command
`gunicorn config.wsgi:application`, same env vars.

## Sandbox preview note

In the dev sandbox the platform starts this service automatically via
`/home/z/my-project/.zscripts/dev.sh` (binds port 3000 = preview port).
After a sandbox reset the server may need a moment before the Preview panel
responds; if the preview shows an error, it will come up on the next platform
boot — for an always-on console use the Render deployment.

## Changing the owner password

Either set a new `VELO_ADMIN_PASSWORD` and re-run `python manage.py
bootstrap_admin`, or use the "Change password" link in the console's top-right
menu.

## Future ideas (say the word)

- Suspend/activate a shop (needs an `is_active` column + app-side check)
- Broadcast announcements to all shops (new table + app banner)
- Revenue chart per month, export CSV
- Per-shop detail page with their top items
