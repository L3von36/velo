"""Owner dashboard KPIs — raw SQL over the live tables (velo_admin role has
BYPASSRLS, same visibility as Supabase Studio). All "today" boundaries speak
Addis Ababa time, exactly like the app does since v1.4.1."""
from decimal import Decimal

from django.db import connection

EAT = "Africa/Addis_Ababa"


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


def kpis() -> dict:
    today_sql = f"({EAT!r})"  # informational only; SQL below inlines tz literal
    del today_sql

    cards = {
        "shops_total": _one("select count(*) from public.shops"),
        "shops_new_30d": _one(
            "select count(*) from public.shops where created_at > now() - interval '30 days'"),
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
        select s.id, s.name, s.business_type, s.plan, s.phone, s.created_at
        from public.shops s order by s.created_at desc limit 8""")

    recent_sales = _rows("""
        select s.id, sh.name as shop_name, s.total, s.method, s.status,
               s.created_at
        from public.sales s join public.shops sh on sh.id = s.shop_id
        order by s.created_at desc limit 8""")

    by_type = _rows("""
        select business_type, count(*) as shops
        from public.shops group by business_type order by shops desc""")

    by_plan = _rows("""
        select plan, count(*) as shops from public.shops
        group by plan order by shops desc""")

    # Daily revenue for the last 14 days (EAT calendar days, gaps included).
    series_14d = _rows("""
        with days as (
            select generate_series(
                ((now() at time zone 'Africa/Addis_Ababa')::date
                 - interval '13 days')::date,
                (now() at time zone 'Africa/Addis_Ababa')::date,
                interval '1 day')::date as d)
        select to_char(days.d, 'Mon DD') as label,
               coalesce(sum(s.total), 0) as total,
               count(s.id) as cnt
        from days
        left join public.sales s
          on (s.created_at at time zone 'Africa/Addis_Ababa')::date = days.d
        group by days.d order by days.d""")

    # Busiest tenants over the last 30 days.
    top_shops = _rows("""
        select sh.name, sh.plan, count(s.id) as cnt,
               coalesce(sum(s.total), 0) as total
        from public.sales s
        join public.shops sh on sh.id = s.shop_id
        where s.created_at > now() - interval '30 days'
        group by sh.id, sh.name, sh.plan
        order by total desc limit 5""")

    max_daily = max((float(r["total"]) for r in series_14d), default=0.0)

    return {"cards": cards, "recent_shops": recent_shops,
            "recent_sales": recent_sales, "by_type": by_type,
            "by_plan": by_plan, "series_14d": series_14d,
            "top_shops": top_shops, "max_daily": max_daily}
