"""Owner dashboard KPIs — raw SQL over the live tables (velo_admin role has
BYPASSRLS, same visibility as Supabase Studio). All "today" boundaries speak
Addis Ababa time, exactly like the app does since v1.4.1.

v1.8.0 additions:
- Chart period selector: 7 / 14 / 30 days shown as daily bars, 90 days
  aggregated per ISO week (13 bars) so the chart stays readable.
- Growth & retention metrics: MRR / ARR from the plan price map, paying
  tenants, ARPU, churn (tenants with no sales in 30d), activation.
- Danger zone data: tenant list with suspension + last-sale context.

v2.0.0 additions — MONEY RADAR (revenue intelligence):
- Tenant health scores (0–100) computed from recency, momentum, depth and
  billing tier — every signal comes from live business data, never invented.
- Upsell pipeline: free-tier tenants showing paid-plan behaviour, ranked by
  the MRR upside of the recommended plan.
- Churn risk: previously-active tenants going quiet (14d+ silence or a
  steep momentum drop) while still on a paid plan.
- Win-back: churned tenants whose lifetime revenue ranks high — the cheapest
  revenue the platform can recover.
- Platform benchmark: per-tenant percentile of 30-day revenue vs the
  platform median, so the owner can spot outliers in both directions.

v2.2.0 addition — CALL-SHEET STALENESS:
- Every upsell target carries its own hours-silent pill (fresh / cooling /
  silent / never) so the owner sees per-tenant staleness in hours, not
  just the platform-wide heartbeat.

v2.1.0 addition — PLATFORM HEARTBEAT:
- Watches the platform as a whole, complementing the per-tenant churn logic:
  hours since the last ring of the register (live < 24h / cooling 24–48h /
  silent 48h+ / empty), 24h sales momentum vs the prior 24h, how many
  tenants are actively selling, and the consecutive sale-day streak —
  so a platform-wide stall is flagged in hours, not weeks.

v2.4.0 additions — OWNER OS (patterns borrowed from how the best platforms
run their own back-office: Stripe/Shopify-style auditability, support-grade
tenant visibility, operator metrics):
- Activation funnel: signup → catalog → first sale → 5-sale habit →
  active this week. The operator's #1 early-stage metric — month-one churn
  spikes are onboarding problems, and the funnel shows exactly which
  milestone leaks.
- Weekly cohort grid: tenants grouped by signup week, tracked by activity
  week since signup — onboarding quality you can see.
- Owner audit trail: every privileged action (suspend, ban, plan moves,
  test flags, deletes, notes) is written to adminpanel.owner_audit with
  actor, target, details and IP — and the console surfaces it on a
  reviewable, filterable page ("logging enabled" is not compliance;
  "someone actually reads it" is).
- Tenant 360: one read-only dossier per tenant — health, money trajectory,
  catalog depth, team, payment rails, recent receipts, notes — so a call
  starts informed. Full login-as impersonation needs Supabase admin APIs
  and app-side trust; this is the safe 80/20.
"""
from datetime import date, timedelta
from decimal import Decimal

from django.db import connection

EAT = "Africa/Addis_Ababa"

# Published Velo plan pricing (ETB / month). The console never invents
# revenue: plans not listed here are billed at 0 until pricing is defined.
PLAN_PRICES_ETB = {
    "free": 0,
    "starter": 299,
    "pro": 599,
    "business": 999,
}

PERIODS = (7, 14, 30, 90)


def _one(sql, params=None):
    with connection.cursor() as cur:
        cur.execute(sql, params or [])
        row = cur.fetchone()
    return row[0] if row else None


def _rows(sql, params=None):
    with connection.cursor() as cur:
        cur.execute(sql, params or [])
        cols = [c[0] for c in cur.description]
        return [dict(zip(cols, r)) for r in cur.fetchall()]


def _money(v):
    return f"{v:,.2f}" if isinstance(v, (int, float, Decimal)) else "0.00"


def _revenue_series(days: int) -> list[dict]:
    """Daily bars for 7/14/30, ISO-week bars for 90. Zero-filled, EAT days."""
    if days <= 30:
        return _rows(f"""
            with days as (
                select generate_series(
                    ((now() at time zone {EAT!r})::date
                     - interval '{days - 1} days')::date,
                    (now() at time zone {EAT!r})::date,
                    interval '1 day')::date as d)
            select to_char(days.d, 'Mon DD') as label,
                   coalesce(sum(s.total), 0) as total,
                   count(s.id) as cnt
            from days
            left join public.sales s
              on (s.created_at at time zone {EAT!r})::date = days.d
            group by days.d order by days.d""")
    # 90 days -> 13 ISO weeks (current week included, zero-filled)
    return _rows(f"""
        with weeks as (
            select generate_series(
                date_trunc('week',
                    (now() at time zone {EAT!r})::date) - interval '12 weeks',
                date_trunc('week',
                    (now() at time zone {EAT!r})::date),
                interval '1 week')::date as w)
        select to_char(weeks.w, 'Mon DD') || ' +' as label,
               coalesce(sum(s.total), 0) as total,
               count(s.id) as cnt
        from weeks
        left join public.sales s
          on date_trunc('week',
             (s.created_at at time zone {EAT!r})::date) = weeks.w
        group by weeks.w order by weeks.w""")


def _growth() -> dict:
    """MRR / churn / activation — the owner's commercial lens."""
    by_plan = _rows("""
        select plan, count(*) as shops from public.shops
        where not is_test group by plan""")
    shops_total = sum(r["shops"] for r in by_plan)

    mrr = sum(PLAN_PRICES_ETB.get(r["plan"], 0) * r["shops"] for r in by_plan)
    paying = sum(r["shops"] for r in by_plan if PLAN_PRICES_ETB.get(r["plan"], 0) > 0)

    # Churn: tenants older than 30d with zero sales in the last 30d.
    # Test tenants are excluded — demo shops are not churn evidence.
    mature = _one("""
        select count(*) from public.shops
        where created_at < now() - interval '30 days' and not is_test""") or 0
    churned = _one("""
        select count(*) from public.shops s
        where s.created_at < now() - interval '30 days'
          and not s.is_test
          and not exists (
            select 1 from public.sales x
            where x.shop_id = s.id
              and x.created_at > now() - interval '30 days')""") or 0
    active_30d = _one("""
        select count(distinct shop_id) from public.sales
        where created_at > now() - interval '30 days'""") or 0
    ever_active = _one("""
        select count(distinct shop_id) from public.sales""") or 0
    suspended = _one(
        "select count(*) from public.shops where is_suspended") or 0

    return {
        "mrr": _money(mrr),
        "arr": _money(mrr * 12),
        "paying": paying,
        "arpu": _money(mrr / shops_total) if shops_total else "0.00",
        "churned": churned,
        "churn_rate": f"{(churned / mature * 100):.1f}" if mature else "0.0",
        "mature": mature,
        "active_30d": active_30d,
        "activation_rate": f"{(ever_active / shops_total * 100):.1f}"
                           if shops_total else "0.0",
        "suspended": suspended,
        "by_plan": by_plan,
    }


def _tenant_health() -> list[dict]:
    """One row per tenant for the danger zone / tenant health panel."""
    return _rows("""
        select sh.id, sh.name, sh.plan, sh.business_type,
               sh.is_suspended, sh.suspended_at, sh.suspended_note,
               (select count(*) from public.sales s
                 where s.shop_id = sh.id) as sales_total,
               (select max(s.created_at) from public.sales s
                 where s.shop_id = sh.id) as last_sale
        from public.shops sh
        order by sh.is_suspended desc,
                 (select max(s.created_at) from public.sales s
                   where s.shop_id = sh.id) desc nulls last,
                 sh.created_at desc""")


def kpis(period: int = 14) -> dict:
    if period not in PERIODS:
        period = 14

    cards = {
        "shops_total": _one("select count(*) from public.shops"),
        "shops_new_30d": _one(
            "select count(*) from public.shops where created_at > now() - interval '30 days'"),
        "shops_suspended": _one(
            "select count(*) from public.shops where is_suspended"),
        "users_total": _one("select count(*) from auth_users"),
        "users_active_7d": _one(
            "select count(*) from auth_users where last_sign_in_at > now() - interval '7 days'"),
        "items_total": _one("select count(*) from public.items"),
        "sales_all_count": _one("select count(*) from public.sales"),
        "sales_all_sum": _money(_one("select coalesce(sum(total),0) from public.sales")),
        "sales_today_count": _one(
            "select count(*) from public.sales "
            "where (created_at at time zone 'Africa/Addis_Ababa')::date "
            "= (now() at time zone 'Africa/Addis_Ababa')::date"),
        "sales_today_sum": _money(_one(
            "select coalesce(sum(total),0) from public.sales "
            "where (created_at at time zone 'Africa/Addis_Ababa')::date "
            "= (now() at time zone 'Africa/Addis_Ababa')::date")),
        "sales_7d_sum": _money(_one(
            "select coalesce(sum(total),0) from public.sales "
            "where created_at > now() - interval '7 days'")),
        "sales_7d_count": _one(
            "select count(*) from public.sales "
            "where created_at > now() - interval '7 days'"),
        "expenses_7d_sum": _money(_one(
            "select coalesce(sum(amount),0) from public.expenses "
            "where created_at > now() - interval '7 days'")),
    }

    recent_shops = _rows("""
        select s.id, s.name, s.business_type, s.plan, s.phone,
               s.is_suspended, s.created_at
        from public.shops s order by s.created_at desc limit 8""")

    recent_sales = _rows("""
        select s.id, sh.name as shop_name, sh.is_suspended as shop_suspended,
               s.total, s.method, s.status, s.created_at
        from public.sales s join public.shops sh on sh.id = s.shop_id
        order by s.created_at desc limit 8""")

    by_type = _rows("""
        select business_type, count(*) as shops
        from public.shops group by business_type order by shops desc""")

    by_plan = _rows("""
        select plan, count(*) as shops from public.shops
        group by plan order by shops desc""")

    series = _revenue_series(period)

    # Busiest tenants over the last 30 days.
    top_shops = _rows("""
        select sh.id, sh.name, sh.plan, count(s.id) as cnt,
               coalesce(sum(s.total), 0) as total
        from public.sales s
        join public.shops sh on sh.id = s.shop_id
        where s.created_at > now() - interval '30 days'
        group by sh.id, sh.name, sh.plan
        order by total desc limit 5""")

    max_daily = max((float(r["total"]) for r in series), default=0.0)

    return {"cards": cards, "recent_shops": recent_shops,
            "recent_sales": recent_sales, "by_type": by_type,
            "by_plan": by_plan, "series": series,
            "period": period, "periods": PERIODS,
            "growth": _growth(), "tenants": _tenant_health(),
            "top_shops": top_shops, "max_daily": max_daily,
            "radar": money_radar(),
            "funnel": _funnel(), "cohorts": _cohorts(),
            "plan_prices": PLAN_PRICES_ETB}




# ---------------------------------------------------------------------------
# v2.0.0 — MONEY RADAR
# Every signal below is computed from live business data: sales, catalog,
# staff and billing plan. Nothing is hardcoded per tenant, nothing invented.
# ---------------------------------------------------------------------------

_RADAR_SQL = """
with m as (
    select sh.id,
           coalesce((select sum(s.total) from public.sales s
                      where s.shop_id = sh.id
                        and s.created_at > now() - interval '30 days'), 0) as rev30,
           coalesce((select sum(s.total) from public.sales s
                      where s.shop_id = sh.id
                        and s.created_at <= now() - interval '30 days'
                        and s.created_at > now() - interval '60 days'), 0) as rev_prev30,
           coalesce((select count(s.id) from public.sales s
                      where s.shop_id = sh.id
                        and s.created_at > now() - interval '30 days'), 0) as cnt30,
           coalesce((select sum(s.total) from public.sales s
                      where s.shop_id = sh.id), 0) as rev_life,
           (select max(s.created_at) from public.sales s
             where s.shop_id = sh.id) as last_sale,
           (select count(*) from public.items i where i.shop_id = sh.id) as items_cnt,
           (select count(*) from public.staff st
             where st.shop_id = sh.id and st.user_id is not null) as users_cnt,
           (select count(*) from public.customers c
             where c.shop_id = sh.id) as cust_cnt,
           extract(day from now() - sh.created_at)::int as age_days
    from public.shops sh
)
select m.*, sh.name, sh.plan, sh.business_type, sh.is_suspended, sh.is_test,
       sh.phone, sh.created_at,
       case when m.last_sale is null then null
            else extract(epoch from (now() - m.last_sale)) / 3600.0
       end as hours_silent
from m join public.shops sh on sh.id = m.id
"""


def _classify(row: dict, median30: float) -> dict:
    """Turn one tenant's live metrics into a health score + money signals."""
    plan = row["plan"]
    price_now = PLAN_PRICES_ETB.get(plan, 0)
    rev30 = float(row["rev30"] or 0)
    prev30 = float(row["rev_prev30"] or 0)
    cnt30 = int(row["cnt30"] or 0)
    rev_life = float(row["rev_life"] or 0)
    items = int(row["items_cnt"] or 0)
    users = int(row["users_cnt"] or 0)
    days_silent = int(row["days_silent"])

    # -- health score (0..100) --------------------------------------------
    # recency   /40 : linear decay, 0 days silent = full marks, 45d = zero
    # momentum  /30 : rev30 vs rev_prev30 ratio; new activity counts as 30
    # depth     /20 : catalog size + linked app users (proxy for commitment)
    # tier      /10 : paying plans score full marks
    score_rec = max(0.0, 40 - min(days_silent, 45) * (40 / 45.0)) \
        if days_silent < 900 else 0.0
    if prev30 > 0:
        ratio = rev30 / prev30
        score_mom = 30.0 if ratio >= 1.0 else max(5.0, 30.0 * ratio)
    else:
        score_mom = 30.0 if rev30 > 0 else 10.0
    score_depth = min(items, 12) * (20 / 12.0) + min(users, 8) * (20 / 8.0)
    score_tier = 10.0 if price_now > 0 else 3.0
    health = int(round(score_rec + score_mom + score_depth + score_tier))
    health = max(0, min(100, health))

    if health >= 75:
        band = "healthy"
    elif health >= 50:
        band = "watch"
    elif health >= 25:
        band = "at_risk"
    else:
        band = "critical"

    # -- money signals ------------------------------------------------------
    signals = []

    # 1) Upsell: free tenant performing at paid-plan levels.
    rec_plan = None
    if price_now == 0 and not row["is_suspended"]:
        if rev30 >= 8000 or cnt30 >= 25:
            rec_plan = "pro"
        elif rev30 >= 3000 or cnt30 >= 10 or items >= 25:
            rec_plan = "starter"
    if rec_plan:
        signals.append({
            "kind": "upsell", "plan": rec_plan,
            "upside": PLAN_PRICES_ETB[rec_plan] - price_now,
            "why": f"ETB {rev30:,.0f} in 30d · {cnt30} sales · {items} items"})

    # 2) Churn risk: was active, now going quiet.
    if not row["is_suspended"] and days_silent >= 14 and rev_life > 0:
        drop_txt = ""
        if prev30 > 0 and rev30 < prev30:
            drop_txt = f" · revenue down {(1 - rev30 / prev30) * 100:.0f}%"
        signals.append({
            "kind": "churn", "days_silent": days_silent,
            "why": f"silent {days_silent}d{drop_txt}"})

    # 3) Win-back: mature, silent 30d+, meaningful lifetime revenue.
    if not row["is_suspended"] and days_silent >= 30 and rev_life >= 5000:
        signals.append({
            "kind": "winback",
            "why": f"ETB {rev_life:,.0f} lifetime · {days_silent}d silent"})

    # 4) Benchmark vs the platform median (only when the platform is active).
    pct = None
    if median30 > 0 and rev30 > 0:
        pct = min(100, int(round(rev30 / (median30 * 2) * 100)))
    return {"health": health, "band": band, "signals": signals,
            "benchmark_pct": pct, "rev30": rev30, "prev30": prev30,
            "cnt30": cnt30, "days_silent": days_silent,
            "rev_life": rev_life, "price_now": price_now}


def _staleness(hours):
    """v2.2.0 — per-tenant staleness band + display text (pure, testable).
    fresh < 24h / cooling 24-48h / silent 48h+ / never sold. Mirrors the
    heartbeat's platform bands so one color language carries from the
    platform pulse down to each revenue call."""
    if hours is None:
        return "never", "never sold"
    if hours < 24:
        return "fresh", f"{hours:.0f}h ago"
    if hours < 48:
        return "cooling", f"{hours:.0f}h ago"
    return "silent", f"{round(hours / 24)}d ago"


def _sale_streak(days: list, today) -> tuple[int, bool]:
    """Consecutive sale-day streak ending at today (or yesterday, with
    today still quiet → flagged at risk). Pure helper, unit-testable."""
    streak, streak_at_risk = 0, False
    if days:
        cursor = days[0]  # count backwards from the most recent sale day
        if days[0] == today:
            pass
        elif (today - days[0]).days == 1:
            streak_at_risk = True  # streak alive but today still quiet
        else:
            return 0, False  # streak already broken
        for d in days:
            if d == cursor:
                streak += 1
                cursor -= timedelta(days=1)
            else:
                break
    return streak, streak_at_risk


def _heartbeat() -> dict:
    """v2.1.0 — Platform pulse. Catches a platform-wide stall in hours:
    time since the last completed sale (any tenant), 24h momentum vs the
    prior 24h, how many tenants are actively selling, and the consecutive
    sale-day streak. Computed in SQL so timezone handling matches the app."""
    last = _rows("""
        select sh.name as shop_name, s.total,
               extract(epoch from (now() - s.created_at)) / 3600.0 as hours_ago
        from public.sales s join public.shops sh on sh.id = s.shop_id
        where s.status = 'completed'
        order by s.created_at desc limit 1""")
    last = last[0] if last else None
    win = (_rows("""
        select
          (select count(*) from public.sales where status = 'completed'
             and created_at > now() - interval '24 hours') as n24,
          (select coalesce(sum(total), 0) from public.sales
             where status = 'completed'
             and created_at > now() - interval '24 hours') as amt24,
          (select count(distinct shop_id) from public.sales
             where status = 'completed'
             and created_at > now() - interval '24 hours') as shops24,
          (select count(*) from public.sales where status = 'completed'
             and created_at <= now() - interval '24 hours'
             and created_at > now() - interval '48 hours') as prev24,
          (select count(*) from public.shops
            where not is_suspended and not is_test) as shops_total""") or [{}])[0]

    # Consecutive sale-day streak (EAT days), ending at today or yesterday.
    days = [r["day"] for r in _rows("""
        select distinct (created_at at time zone 'Africa/Addis_Ababa')::date as day
        from public.sales where status = 'completed'
        order by day desc limit 60""")]
    today = _one("""
        select (now() at time zone 'Africa/Addis_Ababa')::date""")
    streak, streak_at_risk = _sale_streak(days, today)

    n24 = int(win.get("n24") or 0)
    prev24 = int(win.get("prev24") or 0)
    shops24 = int(win.get("shops24") or 0)
    shops_total = int(win.get("shops_total") or 0)

    if not last:
        hours = None
        status = "empty"
        pulse = "No sales yet"
        ago_text = ""
        headline = "Waiting for the platform's first sale"
        detail = ("Once tenants start ringing up sales, this light stays "
                  "green while the platform is active.")
        card_sub = "no completed sale on record yet"
    else:
        hours = float(last["hours_ago"] or 0)
        ago = (f"{int(hours * 60)}m" if hours < 1
               else f"{hours / 24:.0f}d" if hours >= 48 else f"{hours:.0f}h")
        ago_text = ago
        where = f"ETB {_money(last['total'])} at {last['shop_name']}"
        momentum = ""
        if n24 or prev24:
            if prev24 and n24 < prev24 / 2 and n24 < 5:
                momentum = (f" · momentum fading: {n24} sales in 24h "
                            f"vs {prev24} the prior 24h")
            elif prev24 and n24 > prev24:
                momentum = f" · accelerating: {n24} sales in 24h vs {prev24} prior"
            else:
                momentum = f" · {n24} sales in the last 24h"
        if hours < 24:
            status = "live"
            pulse = "Live"
            headline = f"Last sale {ago} ago — the register is ringing"
            detail = f"{where}{momentum} · {shops24} of {shops_total} tenants selling in 24h · {streak}-day streak"
            card_sub = f"last sale {ago} ago · {streak}-day streak"
        elif hours < 48:
            status = "cooling"
            pulse = "Cooling"
            headline = f"No sale in {ago} — the platform is cooling"
            detail = (f"Last: {where}. {n24} sales in 24h vs {prev24} prior · "
                      f"{streak}-day streak"
                      + (" — today still quiet, at risk" if streak_at_risk else "")
                      + ". Nudge your busiest tenants today.")
            card_sub = f"silent {ago} · streak {streak}d at risk"
        else:
            status = "silent"
            pulse = "Silent"
            headline = f"Platform silent for {ago} — act now"
            detail = (f"Last sale ever: {where}. Nobody has sold anything in "
                      f"{ago}. Call your top tenants before silence becomes churn.")
            card_sub = f"silent {ago} · call top tenants"

    return {"status": status, "pulse": pulse, "headline": headline,
            "detail": detail, "card_sub": card_sub, "hours": hours,
            "ago_text": ago_text,
            "n24": n24, "prev24": prev24, "amt24": _money(win.get("amt24") or 0),
            "shops24": shops24, "shops_total": shops_total,
            "streak": streak, "streak_at_risk": streak_at_risk}


def money_radar() -> dict:
    """The owner's revenue-intelligence snapshot over every live tenant."""
    rows = _rows(_RADAR_SQL)

    silence = {r["id"]: int(r["d"]) for r in _rows("""
        select sh.id,
               case when max(s.created_at) is null then 999
                    else extract(day from
                         (now() at time zone 'Africa/Addis_Ababa')
                         - (max(s.created_at) at time zone 'Africa/Addis_Ababa'))::int
               end as d
        from public.shops sh
        left join public.sales s on s.shop_id = sh.id
        group by sh.id""")}
    for r in rows:
        r["days_silent"] = silence.get(r["id"], 999)

    # Platform median of 30-day revenue across active, non-suspended tenants.
    active_rev = sorted(float(r["rev30"]) for r in rows
                        if not r["is_suspended"] and float(r["rev30"]) > 0)
    n = len(active_rev)
    if n == 0:
        median30 = 0.0
    elif n % 2:
        median30 = active_rev[n // 2]
    else:
        median30 = (active_rev[n // 2 - 1] + active_rev[n // 2]) / 2

    tenants = []
    for r in rows:
        c = _classify(r, median30)
        c.update({
            "id": r["id"], "name": r["name"], "plan": r["plan"],
            "business_type": r["business_type"],
            "phone": r.get("phone", "") or "",
            "is_suspended": r["is_suspended"],
            "is_test": r.get("is_test", False),
            "items_cnt": r["items_cnt"], "users_cnt": r["users_cnt"],
            "cust_cnt": r["cust_cnt"], "age_days": r["age_days"],
            "last_sale": r["last_sale"],
            "is_new": r["age_days"] <= 7,
        })
        # v2.2.0 — per-tenant staleness in HOURS (the call-sheet lens).
        hs = r.get("hours_silent")
        c["hours_silent"] = hs
        c["silent_band"], c["silent_text"] = _staleness(hs)
        kinds = {"upsell": 0, "winback": 1, "churn": 2}
        c["signals"] = sorted(c["signals"], key=lambda s: kinds.get(s["kind"], 9))
        tenants.append(c)

    # v2.3.0 — test tenants stay visible on the board but never count as
    # pipeline, churn or health signal: demo shops are not revenue truth.
    real = [t for t in tenants if not t["is_test"]]
    upsells = sorted(
        (t for t in real if any(s["kind"] == "upsell" for s in t["signals"])),
        key=lambda t: -max((s["upside"] for s in t["signals"]
                            if s["kind"] == "upsell"), default=0))
    churn = sorted(
        (t for t in real if any(s["kind"] == "churn" for s in t["signals"])),
        key=lambda t: -min((s["days_silent"] for s in t["signals"]
                            if s["kind"] == "churn"), default=0))
    winback = sorted(
        (t for t in real if any(s["kind"] == "winback" for s in t["signals"])),
        key=lambda t: -t["rev_life"])

    pipeline_mrr = sum(s["upside"] for t in upsells for s in t["signals"]
                       if s["kind"] == "upsell")

    bands = {b: sum(1 for t in real
                    if t["band"] == b and not t["is_suspended"])
             for b in ("healthy", "watch", "at_risk", "critical")}

    live = [t for t in real if not t["is_suspended"]]
    avg_health = (sum(t["health"] for t in live) // len(live)) if live else 0

    return {"tenants": tenants, "upsells": upsells[:8], "churn": churn[:8],
            "winback": winback[:8], "pipeline_mrr": pipeline_mrr,
            "pipeline_arr": pipeline_mrr * 12, "bands": bands,
            "avg_health": avg_health, "median30": median30,
            "active_count": len(real), "test_count": len(tenants) - len(real),
            "heartbeat": _heartbeat()}


# ---------------------------------------------------------------------------
# v2.4.0 — OWNER OS
# Auditability, tenant visibility and operator metrics, following the
# patterns the best platforms use in their own back-office tooling.
# ---------------------------------------------------------------------------

def _funnel() -> dict:
    """Activation funnel over real (non-test) tenants:
    signup → built catalog (≥1 item) → first sale → habit (≥5 sales)
    → active this week. Conversion %s measure the leak at each milestone —
    the early-stage operator's single most telling lens."""
    row = (_rows("""
        select
          count(*) as signed,
          count(*) filter (where exists (
            select 1 from public.items i where i.shop_id = sh.id)) as catalog,
          count(*) filter (where exists (
            select 1 from public.sales s where s.shop_id = sh.id)) as first_sale,
          count(*) filter (where (
            select count(*) from public.sales s2
            where s2.shop_id = sh.id) >= 5) as habit,
          count(*) filter (where exists (
            select 1 from public.sales s3 where s3.shop_id = sh.id
              and s3.created_at > now() - interval '7 days')) as active_7d
        from public.shops sh
        where not sh.is_test""") or [{}])[0]

    def n(k):
        return int(row.get(k) or 0)

    steps = [("Signed up", n("signed")),
             ("Built catalog", n("catalog")),
             ("First sale", n("first_sale")),
             ("Habit · 5+ sales", n("habit")),
             ("Active this week", n("active_7d"))]
    signed = steps[0][1]
    out = []
    for label, count in steps:
        pct = (count / signed * 100) if signed else (100.0 if count else 0.0)
        out.append({"label": label, "count": count, "pct": round(pct, 1)})
    # step-to-step conversion: where does the cohort leak?
    for prev, cur in zip(out, out[1:]):
        cur["step_pct"] = round((cur["count"] / prev["count"] * 100), 1) \
            if prev["count"] else 0.0
    worst = min((s for s in out[1:] if s["count"] < out[0]["count"]),
                key=lambda s: s["step_pct"], default=None)
    return {"steps": out, "worst_step": worst}


def _cohorts() -> list:
    """Weekly signup cohorts (last 6 incl. current) × activity in each week
    since signup. Cell = tenants of that cohort that made ANY sale in that
    week. Onboarding quality you can see: healthy cohorts stay lit across
    the row; bad ones go dark after week 0."""
    sizes = _rows("""
        select date_trunc('week',
                 (sh.created_at at time zone 'Africa/Addis_Ababa'))::date as wk,
               count(*) as size
        from public.shops sh
        where not sh.is_test
          and sh.created_at >= date_trunc('week',
                (now() at time zone 'Africa/Addis_Ababa')) - interval '5 weeks'
        group by 1""")
    acts = _rows("""
        select b.wk as cohort,
               ((a.awk - b.wk) / 7) as week_n,
               count(distinct s.shop_id) as active
        from public.sales s
        join (select id, date_trunc('week',
                (created_at at time zone 'Africa/Addis_Ababa'))::date as wk
              from public.shops where not is_test) b
          on b.id = s.shop_id
        join (select shop_id, date_trunc('week',
                (created_at at time zone 'Africa/Addis_Ababa'))::date as awk
              from public.sales) a
          on a.shop_id = s.shop_id
        where b.wk >= date_trunc('week',
                (now() at time zone 'Africa/Addis_Ababa')) - interval '5 weeks'
        group by 1, 2""")
    act_map = {(a["cohort"], a["week_n"]): a["active"] for a in acts}
    this_week = _one("""
        select date_trunc('week',
            (now() at time zone 'Africa/Addis_Ababa'))::date""")
    rows = []
    for s in sorted(sizes, key=lambda r: r["wk"], reverse=True):
        max_n = ((this_week - s["wk"]).days // 7) if this_week and s["wk"] else 0
        cells = []
        # pad to 6 columns so the grid stays rectangular; weeks that have
        # not happened yet render as "·" (active=None).
        for nn in range(0, 6):
            if nn > max_n:
                cells.append({"n": nn, "active": None, "pct": 0})
                continue
            active = act_map.get((s["wk"], nn), 0)
            cells.append({"n": nn, "active": active,
                          "pct": round(active / s["size"] * 100) if s["size"] else 0})
        rows.append({"label": s["wk"].strftime("%b %d"),
                     "iso": s["wk"].isoformat(), "size": s["size"],
                     "cells": cells})
    return rows


def audit_actions() -> list:
    """Distinct actions for the audit page's filter dropdown."""
    return [r["action"] for r in
            _rows("select distinct action from adminpanel.owner_audit "
                  "order by action")]


def audit_trail(action: str = "", q: str = "", limit: int = 200) -> list:
    """The owner audit trail, newest first, optionally filtered by action
    and a free-text needle across actor/target/details."""
    sql = ("select id, created_at, actor, action, target, details, ip "
           "from adminpanel.owner_audit")
    where, params = [], []
    if action:
        where.append("action = %s")
        params.append(action)
    if q:
        where.append("(actor ilike %s or target ilike %s or details ilike %s)")
        params += [f"%{q}%"] * 3
    if where:
        sql += " where " + " and ".join(where)
    sql += " order by created_at desc limit %s"
    params.append(limit)
    return _rows(sql, params)


def tenant_360(shop_id: int) -> dict | None:
    """Everything worth knowing about one tenant, in one read-only pass.
    The safe stand-in for login-as impersonation: a call starts informed
    without touching the tenant's auth or data."""
    shop = _rows("""
        select sh.id, sh.name, sh.business_type, sh.plan, sh.phone,
               sh.address, sh.tin, sh.language, sh.currency,
               sh.telebirr_number, sh.cbe_number,
               sh.accept_telebirr, sh.accept_cbe, sh.accept_credit,
               sh.receipt_footer, sh.latitude, sh.longitude,
               sh.created_at, sh.is_suspended, sh.suspended_at,
               sh.suspended_note, sh.is_test
        from public.shops sh where sh.id = %s""", [shop_id])
    if not shop:
        return None
    shop = shop[0]

    # Health + money signals straight from the radar machinery.
    t = next((x for x in money_radar()["tenants"] if x["id"] == shop_id), None)

    weekly = _rows("""
        with weeks as (
            select generate_series(
                date_trunc('week',
                    (now() at time zone 'Africa/Addis_Ababa')) - interval '7 weeks',
                date_trunc('week',
                    (now() at time zone 'Africa/Addis_Ababa')),
                interval '1 week')::date as w)
        select to_char(weeks.w, 'Mon DD') as label,
               coalesce(sum(s.total), 0) as total,
               count(s.id) as cnt
        from weeks
        left join public.sales s
          on date_trunc('week', (s.created_at at time zone 'Africa/Addis_Ababa')::date)
             = weeks.w
        where weeks.w >= date_trunc('week',
              (select created_at from public.shops where id = %s))
          and s.shop_id = %s
        group by weeks.w order by weeks.w""", [shop_id, shop_id])

    mix = _rows("""
        select method, count(*) as cnt, coalesce(sum(total), 0) as total
        from public.sales
        where shop_id = %s and created_at > now() - interval '30 days'
        group by method order by total desc""", [shop_id])

    top_items = _rows("""
        select name_snapshot,
               sum(qty) as qty,
               coalesce(sum(line_total), 0) as revenue
        from public.sale_items
        where shop_id = %s
        group by name_snapshot
        order by revenue desc nulls last limit 8""", [shop_id])

    staff = _rows("""
        select name, role, phone, active,
               (user_id is not null) as linked
        from public.staff where shop_id = %s
        order by active desc, name""", [shop_id])

    sales = _rows("""
        select id, receipt_number, total, method, status, staff_name,
               created_at
        from public.sales where shop_id = %s
        order by created_at desc limit 10""", [shop_id])

    notes = _rows("""
        select id, author, body, created_at
        from adminpanel.tenant_notes where shop_id = %s
        order by created_at desc limit 50""", [shop_id])

    cust = (_rows("""
        select count(*) as n, coalesce(sum(balance), 0) as credit
        from public.customers where shop_id = %s""", [shop_id]) or [{}])[0]

    max_daily = max((float(r["total"]) for r in weekly), default=0.0)
    return {"shop": shop, "t": t, "weekly": weekly, "max_weekly": max_daily,
            "mix": mix, "top_items": top_items, "staff": staff,
            "sales": sales, "notes": notes,
            "customers": int(cust.get("n") or 0),
            "credit_out": _money(cust.get("credit") or 0)}


def add_note(shop_id: int, author: str, body: str) -> None:
    """Append a note to the tenant's CRM trail."""
    with connection.cursor() as cur:
        cur.execute(
            "insert into adminpanel.tenant_notes (shop_id, author, body) "
            "values (%s, %s, %s)", [shop_id, author, body])


def radar_call_sheet() -> list:
    """Flattened, export-ready call sheet: every real tenant with its plan,
    health, staleness and (if any) the recommended upgrade."""
    out = []
    for t in money_radar()["tenants"]:
        if t["is_test"]:
            continue
        upsell = next((s for s in t["signals"] if s["kind"] == "upsell"), None)
        churn = next((s for s in t["signals"] if s["kind"] == "churn"), None)
        out.append({
            "tenant": t["name"], "phone": t.get("phone", ""),
            "plan": t["plan"],
            "recommended": (upsell or {}).get("plan", ""),
            "upside_etb_mo": (upsell or {}).get("upside", ""),
            "health": t["health"], "band": t["band"],
            "rev30": t["rev30"], "cnt30": t["cnt30"],
            "lifetime": t["rev_life"],
            "last_sale": t.get("silent_text", ""),
            "silent_days": t.get("days_silent", ""),
            "churn_risk": "yes" if churn else "",
            "suspended": "yes" if t["is_suspended"] else "",
        })
    out.sort(key=lambda r: -r["health"])
    return out
