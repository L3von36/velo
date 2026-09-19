"""Owner dashboard KPIs — raw SQL over the live tables (velo_admin role has
BYPASSRLS, same visibility as Supabase Studio). All "today" boundaries speak
Addis Ababa time, exactly like the app does since v1.4.1.

v1.8.0 additions:
- Chart period selector: 7 / 14 / 30 days shown as daily bars, 90 days
  aggregated per ISO week (13 bars) so the chart stays readable.
- Growth & retention metrics: MRR / ARR from the plan price map, paying
  tenants, ARPU, churn (tenants with no sales in 30d), activation.
- Danger zone data: tenant list with suspension + last-sale context.
"""
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
            "plan_prices": PLAN_PRICES_ETB}
