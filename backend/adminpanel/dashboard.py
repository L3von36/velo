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

v2.1.0 addition — PLATFORM HEARTBEAT:
- Watches the platform as a whole, complementing the per-tenant churn logic:
  hours since the last ring of the register (live < 24h / cooling 24–48h /
  silent 48h+ / empty), 24h sales momentum vs the prior 24h, how many
  tenants are actively selling, and the consecutive sale-day streak —
  so a platform-wide stall is flagged in hours, not weeks.
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
        select plan, count(*) as shops from public.shops group by plan""")
    shops_total = sum(r["shops"] for r in by_plan)

    mrr = sum(PLAN_PRICES_ETB.get(r["plan"], 0) * r["shops"] for r in by_plan)
    paying = sum(r["shops"] for r in by_plan if PLAN_PRICES_ETB.get(r["plan"], 0) > 0)

    # Churn: tenants older than 30d with zero sales in the last 30d.
    mature = _one("""
        select count(*) from public.shops
        where created_at < now() - interval '30 days'""") or 0
    churned = _one("""
        select count(*) from public.shops s
        where s.created_at < now() - interval '30 days'
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
select m.*, sh.name, sh.plan, sh.business_type, sh.is_suspended, sh.created_at
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
          (select count(*) from public.shops where not is_suspended)
            as shops_total""") or [{}])[0]

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
            "is_suspended": r["is_suspended"],
            "items_cnt": r["items_cnt"], "users_cnt": r["users_cnt"],
            "cust_cnt": r["cust_cnt"], "age_days": r["age_days"],
            "last_sale": r["last_sale"],
            "is_new": r["age_days"] <= 7,
        })
        kinds = {"upsell": 0, "winback": 1, "churn": 2}
        c["signals"] = sorted(c["signals"], key=lambda s: kinds.get(s["kind"], 9))
        tenants.append(c)

    upsells = sorted(
        (t for t in tenants if any(s["kind"] == "upsell" for s in t["signals"])),
        key=lambda t: -max((s["upside"] for s in t["signals"]
                            if s["kind"] == "upsell"), default=0))
    churn = sorted(
        (t for t in tenants if any(s["kind"] == "churn" for s in t["signals"])),
        key=lambda t: -min((s["days_silent"] for s in t["signals"]
                            if s["kind"] == "churn"), default=0))
    winback = sorted(
        (t for t in tenants if any(s["kind"] == "winback" for s in t["signals"])),
        key=lambda t: -t["rev_life"])

    pipeline_mrr = sum(s["upside"] for t in upsells for s in t["signals"]
                       if s["kind"] == "upsell")

    bands = {b: sum(1 for t in tenants
                    if t["band"] == b and not t["is_suspended"])
             for b in ("healthy", "watch", "at_risk", "critical")}

    live = [t for t in tenants if not t["is_suspended"]]
    avg_health = (sum(t["health"] for t in live) // len(live)) if live else 0

    return {"tenants": tenants, "upsells": upsells[:8], "churn": churn[:8],
            "winback": winback[:8], "pipeline_mrr": pipeline_mrr,
            "pipeline_arr": pipeline_mrr * 12, "bands": bands,
            "avg_health": avg_health, "median30": median30,
            "heartbeat": _heartbeat()}
