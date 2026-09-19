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

    return {"cards": cards, "recent_shops": recent_shops,
            "recent_sales": recent_sales, "by_type": by_type,
            "by_plan": by_plan}
