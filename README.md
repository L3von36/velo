# Velo

**Velo** is an offline-first, multi-tenant business management SaaS for Ethiopian SMBs — shops, supermarkets, barbershops, restaurants and more. Run your whole business from your phone: catalog, point-of-sale, customers & credit, staff, expenses, reports — in **English or Amharic**, with **Ethiopian Birr (ETB)** and local payment methods (**Telebirr**, **CBE Birr**) built in.

| | |
|---|---|
| **Mobile / Desktop / Web client** | Flutter 3.35 (Material 3, adaptive layout: bottom nav on phones, rail/sidebar on desktop) |
| **Backend** | Django 6 + Django REST Framework, JWT auth, multi-tenant isolated |
| **Database** | SQLite (dev) / PostgreSQL (production-ready swap) |
| **Languages** | English · አማርኛ (Amharic) |
| **Currency** | ETB (Br) |

---

## Features (Phase 1 MVP)

- **Auth** — phone-number + password login, JWT with refresh, role-aware UI
- **Onboarding wizard** — business type → profile → first branch → setup checklist
- **Dashboard** — role-scoped: today's sales, transactions, low stock, receivables
- **Catalog** — products & services, categories, variants, stock tracking, low-stock alerts
- **POS** — split-view cart, quantity steppers, discounts, hold/resume sales, receipts
- **Payments** — cash with change calc, Telebirr / CBE Birr (reference entry), customer credit
- **Customers** — debt-sorted list, append-only credit ledger, quick payment recording
- **Staff** — owner/manager/cashier roles, capability matrix, activate/deactivate
- **Expenses** — categorized expenses, month grouping
- **Reports** — sales trend, best sellers, staff performance, P&L, debtors, method breakdown
- **Offline-aware** — connectivity banner, cart persistence, cloud backend (Supabase Postgres/Auth)

## Repository layout

```
velo/
├── backend/            # Django + DRF API (multi-tenant) + Supabase SQL
│   ├── config/         #   settings, urls, wsgi
│   ├── core/           #   models, serializers, views, tenancy, permissions
│   │   └── management/commands/seed_demo.py
│   ├── supabase/       #   schema.sql + seed.sql — hosted Postgres edition
│   └── requirements.txt
├── flutter_app/        # Velo mobile/desktop/web client (Supabase backend)
│   ├── lib/            #   api, config, models, providers (Riverpod), screens, l10n, theme
│   ├── android/ ios/ web/ windows/
│   └── assets/icon/    # Velo launcher icon source
└── .github/workflows/  # CI: APK, iOS, Web (Pages), Windows builds + Releases
```

## Backend: Supabase (hosted Postgres + Auth)

The Flutter client talks **directly to Supabase** — no server to host. The
web build on GitHub Pages, the Android APK and the Windows EXE all work
out of the box against the hosted database.

- **Data**: 15 Postgres tables (shops, staff, items, variants, customers,
  sales, sale_items, sale_payments, append-only `ledger_entries`, expenses,
  held_sales, stock_movements, ...).
- **Multi-tenancy**: Row Level Security on every table via
  `current_shop_id()` — each signed-in user can only ever touch their own
  shop's rows. Cross-tenant access returns empty results (404-not-403).
- **Business logic**: atomic Postgres functions (`app_checkout`,
  `app_refund_sale`, `app_stock_adjust`, `app_add_ledger`, `app_dashboard`,
  `app_sales_report`, `app_pnl`, `app_debtors`, ...) mirror the Django
  logic: server-side pricing, stock deduction + movements, credit →
  append-only customer ledger, Telebirr/CBE `pending_verification`.
- **Auth**: phone-first. `0911000001` signs in as `0911000001@velo.app`
  (synthetic email — no SMS provider needed). Sessions persist + refresh
  automatically via `supabase_flutter`.

Schema lives in `backend/supabase/`:

```bash
psql "$DATABASE_URL" -f backend/supabase/schema.sql   # tables, RLS, RPCs
psql "$DATABASE_URL" -f backend/supabase/seed.sql     # demo tenants + data
```

## Quick start — legacy Django backend (optional, self-hosted)

The Django API remains available for self-hosting / offline server needs:

```bash
cd backend
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
python manage.py migrate
python manage.py seed_demo          # creates 3 demo tenants with data
python manage.py runserver 0.0.0.0:8000
```

Demo logins (password `demo1234`):

| Phone | Business |
|---|---|
| `0911000001` | Sheger Supermarket |
| `0911000002` | Merkato Fashion House |
| `0911000003` | Addis Fade Barbershop |

API base: `http://localhost:8000/api/` · JWT: `POST /api/auth/token/` `{phone, password}` · Admin: `http://localhost:8000/admin/` (create a superuser with `python manage.py createsuperuser`).

## Quick start — Flutter client

```bash
cd flutter_app
flutter pub get
flutter run                # works immediately — Supabase URL is embedded
```

No server URL configuration needed: the Supabase project URL + public anon
key live in `lib/config/supabase_config.dart`, and all isolation is enforced
server-side by RLS.

## Releases & signing

**Every version tag creates a GitHub Release with all installers attached.**

```bash
git tag v1.0.1 && git push origin v1.0.1
# -> "Release" workflow builds everything, then publishes
#    https://github.com/L3von36/velo/releases/tag/v1.0.1
```

Each release contains: signed `app-release.apk`, Play-Store-ready `app-release.aab`, signed/unsigned iOS `ipa`, `velo-windows-x64.zip`, and `velo-web-dist.zip`. App version name is taken from the tag (`v1.2.3` → versionName `1.2.3`).

### Android signing (already configured)

- Release keystore is stored as repo secrets (`ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`) — never committed.
- `android/app/build.gradle.kts` signs release builds when `ANDROID_KEYSTORE_PATH` is set (CI), or via `android/key.properties` (local), and falls back to the debug key otherwise.
- ⚠️ Keep a backup of `velo-release.jks` — it is the identity of the app on Google Play.

### iOS / TestFlight (add your Apple account)

The signed TestFlight job runs automatically once these repo **secrets** are set (Settings → Secrets and variables → Actions):

| Secret | Where to get it |
|---|---|
| `IOS_P12_BASE64`, `IOS_P12_PASSWORD` | Apple Developer → Certificates → export "Apple Distribution" cert as `.p12` |
| `IOS_PROVISION_PROFILE_BASE64` | Profiles → App Store profile matching `com.velo.app` (base64 of `.mobileprovision`) |
| `APPLE_TEAM_ID` | Membership page (10-char ID) |
| `APPSTORE_ISSUER_ID`, `APPSTORE_KEY_ID`, `APPSTORE_API_PRIVATE_KEY` | App Store Connect → Users and Access → Integrations → API key (base64 of `.p8` into the private key secret) |

Without them the workflow still publishes an **unsigned IPA** so nothing breaks.

## CI/CD — automated builds

`.github/workflows/build.yml` runs on every push to `main` and produces download artifacts:

| Job | Runner | Output |
|---|---|---|
| `build-android` | ubuntu-latest | `velo-android-apk` → signed `app-release.apk` |
| `build-ios` | macos-latest | `velo-ios-unsigned-ipa` → unsigned `Payload` IPA (add your signing cert/team in Xcode to distribute via TestFlight) |
| `build-web` | ubuntu-latest | `velo-web-dist` + auto-deploy to **GitHub Pages** |
| `build-windows` | windows-latest | `velo-windows-x64.zip` containing the release `.exe` |

`.github/workflows/release.yml` runs on `v*` tags and **publishes GitHub Releases** with every artifact attached (see above).

The web app is published at `https://<owner>.github.io/velo/` after the first successful run (GitHub → Settings → Pages → Source: *GitHub Actions*).

## Multi-tenancy & security notes

- Every queryset is pinned to the requesting user's tenant (`core/tenancy.py`) — cross-tenant access returns 404, never data.
- Roles (owner / manager / cashier / staff) are enforced server-side (`core/permissions.py`) via a capability matrix, not just hidden in the UI.
- Credit sales write to an **append-only** customer ledger — balances can only change via new ledger entries.
- For production: set `DEBUG=0`, provide `DJANGO_SECRET_KEY`, switch `DATABASES` to PostgreSQL, and put the API behind TLS.

## Roadmap (per PRD)

- Phase 2: real SMS/OTP auth, thermal (ESC/POS) receipt printing, multi-branch stock transfers, Drift offline sync engine
- Phase 3: subscriptions & billing, advanced analytics, supplier management
