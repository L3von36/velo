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
- **Offline-aware** — connectivity banner, cart persistence, server URL configurable in-app

## Repository layout

```
velo/
├── backend/            # Django + DRF API (multi-tenant)
│   ├── config/         #   settings, urls, wsgi
│   ├── core/           #   models, serializers, views, tenancy, permissions
│   │   └── management/commands/seed_demo.py
│   └── requirements.txt
├── flutter_app/        # Velo mobile/desktop/web client
│   ├── lib/            #   api, models, providers (Riverpod), screens, l10n, theme
│   ├── android/ ios/ web/ windows/
│   └── assets/icon/    # Velo launcher icon source
└── .github/workflows/  # CI: APK, iOS, Web (Pages), Windows builds
```

## Quick start — backend

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
flutter run                # Android emulator reaches the API via 10.0.2.2:8000
```

On real devices, open **Settings → Server URL** in the app and point it at your machine's LAN IP (e.g. `http://192.168.1.10:8000/api`).

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
