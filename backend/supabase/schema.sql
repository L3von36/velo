-- ============================================================
-- Velo — Supabase schema (multi-tenant business SaaS, Ethiopia)
-- Mirrors the Django models: shops, staff, catalog, POS, credit
-- ledger (append-only), expenses, reports via RPC functions.
-- ============================================================

create extension if not exists pg_trgm;

-- ---------------------------------------------------------- business types
create table if not exists business_types (
  key text primary key,
  config jsonb not null,
  sort int not null default 0
);

-- ---------------------------------------------------------- shops (tenants)
create table if not exists shops (
  id bigint generated always as identity primary key,
  name text not null,
  business_type text not null default 'general' references business_types(key),
  language text not null default 'en',
  plan text not null default 'free',
  phone text not null default '',
  address text not null default '',
  currency text not null default 'ETB',
  telebirr_number text not null default '',
  cbe_number text not null default '',
  accept_telebirr boolean not null default true,
  accept_cbe boolean not null default true,
  accept_credit boolean not null default true,
  receipt_footer text not null default '',
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------- staff
create table if not exists staff (
  id bigint generated always as identity primary key,
  shop_id bigint not null references shops(id) on delete cascade,
  user_id uuid unique references auth.users(id) on delete cascade,
  name text not null,
  phone text not null default '',
  role text not null default 'staff' check (role in ('owner','manager','cashier','staff')),
  commission_percent numeric(5,2) not null default 0,
  active boolean not null default true,
  language text not null default 'en',
  created_at timestamptz not null default now()
);
create index if not exists staff_shop_idx on staff(shop_id);

-- ---------------------------------------------------------- catalog
create table if not exists categories (
  id bigint generated always as identity primary key,
  shop_id bigint not null references shops(id) on delete cascade,
  name text not null,
  created_at timestamptz not null default now()
);
create index if not exists categories_shop_idx on categories(shop_id);

create table if not exists items (
  id bigint generated always as identity primary key,
  shop_id bigint not null references shops(id) on delete cascade,
  category_id bigint references categories(id) on delete set null,
  type text not null default 'product' check (type in ('product','service')),
  name text not null,
  description text not null default '',
  price numeric(12,2) not null default 0,
  cost numeric(12,2) not null default 0,
  stock_qty int not null default 0,
  low_stock_threshold int not null default 5,
  barcode text not null default '',
  unit text not null default 'pc',
  duration_minutes int,
  requires_stock boolean not null default true,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);
create index if not exists items_shop_idx on items(shop_id);
create index if not exists items_name_trgm on items using gin (name gin_trgm_ops);

create table if not exists item_variants (
  id bigint generated always as identity primary key,
  shop_id bigint not null references shops(id) on delete cascade,
  item_id bigint not null references items(id) on delete cascade,
  attributes jsonb not null default '{}'::jsonb,
  stock_qty int not null default 0,
  price_override numeric(12,2),
  sku text not null default '',
  barcode text not null default '',
  is_active boolean not null default true
);
create index if not exists variants_item_idx on item_variants(item_id);

-- ---------------------------------------------------------- customers
create table if not exists customers (
  id bigint generated always as identity primary key,
  shop_id bigint not null references shops(id) on delete cascade,
  name text not null,
  phone text not null default '',
  notes text not null default '',
  balance numeric(12,2) not null default 0,
  created_at timestamptz not null default now()
);
create index if not exists customers_shop_idx on customers(shop_id);
create index if not exists customers_name_trgm on customers using gin (name gin_trgm_ops);

-- ---------------------------------------------------------- sales
create table if not exists sales (
  id bigint generated always as identity primary key,
  shop_id bigint not null references shops(id) on delete cascade,
  receipt_number bigint not null,
  customer_id bigint references customers(id) on delete set null,
  customer_name text,
  staff_id bigint references staff(id) on delete set null,
  staff_name text,
  subtotal numeric(12,2) not null default 0,
  discount_total numeric(12,2) not null default 0,
  tax_total numeric(12,2) not null default 0,
  total numeric(12,2) not null default 0,
  method text not null default 'cash',
  status text not null default 'completed'
    check (status in ('completed','pending_verification','refunded')),
  reference text not null default '',
  amount_paid numeric(12,2) not null default 0,
  change_due numeric(12,2) not null default 0,
  refund_reason text,
  created_at timestamptz not null default now()
);
create unique index if not exists sales_receipt_idx on sales(shop_id, receipt_number);
create index if not exists sales_shop_created_idx on sales(shop_id, created_at desc);
create index if not exists sales_customer_idx on sales(customer_id);

create table if not exists sale_items (
  id bigint generated always as identity primary key,
  shop_id bigint not null references shops(id) on delete cascade,
  sale_id bigint not null references sales(id) on delete cascade,
  item_id bigint references items(id) on delete set null,
  variant_id bigint references item_variants(id) on delete set null,
  name_snapshot text not null,
  qty numeric(12,3) not null default 1,
  unit_price numeric(12,2) not null default 0,
  discount numeric(12,2) not null default 0,
  line_total numeric(12,2) not null default 0,
  cost_snapshot numeric(12,2) not null default 0
);
create index if not exists sale_items_sale_idx on sale_items(sale_id);
create index if not exists sale_items_item_idx on sale_items(item_id);

create table if not exists sale_payments (
  id bigint generated always as identity primary key,
  shop_id bigint not null references shops(id) on delete cascade,
  sale_id bigint not null references sales(id) on delete cascade,
  method text not null,
  amount numeric(12,2) not null default 0,
  reference_number text not null default '',
  status text not null default 'verified'
    check (status in ('verified','pending_verification','manual','failed'))
);
create index if not exists sale_payments_sale_idx on sale_payments(sale_id);

-- ---------------------------------------------------------- credit ledger (append-only)
create table if not exists ledger_entries (
  id bigint generated always as identity primary key,
  shop_id bigint not null references shops(id) on delete cascade,
  customer_id bigint not null references customers(id) on delete cascade,
  sale_id bigint references sales(id) on delete set null,
  type text not null check (type in ('charge','payment','adjustment')),
  amount numeric(12,2) not null default 0,
  balance_after numeric(12,2) not null default 0,
  note text not null default '',
  staff_name text,
  created_at timestamptz not null default now()
);
create index if not exists ledger_customer_idx on ledger_entries(customer_id, created_at desc);

-- ---------------------------------------------------------- expenses
create table if not exists expense_categories (
  id bigint generated always as identity primary key,
  shop_id bigint not null references shops(id) on delete cascade,
  name text not null
);
create index if not exists exp_cats_shop_idx on expense_categories(shop_id);

create table if not exists expenses (
  id bigint generated always as identity primary key,
  shop_id bigint not null references shops(id) on delete cascade,
  category_id bigint references expense_categories(id) on delete set null,
  amount numeric(12,2) not null default 0,
  note text not null default '',
  spent_date date not null default current_date,
  created_at timestamptz not null default now()
);
create index if not exists expenses_shop_date_idx on expenses(shop_id, spent_date desc);

-- ---------------------------------------------------------- held sales
create table if not exists held_sales (
  id bigint generated always as identity primary key,
  shop_id bigint not null references shops(id) on delete cascade,
  label text not null default '',
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index if not exists held_shop_idx on held_sales(shop_id);

-- ---------------------------------------------------------- stock movements (append-only)
create table if not exists stock_movements (
  id bigint generated always as identity primary key,
  shop_id bigint not null references shops(id) on delete cascade,
  item_id bigint not null references items(id) on delete cascade,
  variant_id bigint references item_variants(id) on delete set null,
  qty_change int not null,
  reason text not null default '',
  created_at timestamptz not null default now()
);
create index if not exists movements_item_idx on stock_movements(item_id, created_at desc);

-- ============================================================
-- Helper functions (SECURITY DEFINER to avoid RLS recursion)
-- ============================================================
create or replace function current_shop_id() returns bigint
language sql stable security definer set search_path = public as $$
  select shop_id from staff where user_id = auth.uid() and active limit 1;
$$;

create or replace function current_role_name() returns text
language sql stable security definer set search_path = public as $$
  select role from staff where user_id = auth.uid() and active limit 1;
$$;

create or replace function has_role(roles text[]) returns boolean
language sql stable security definer set search_path = public as $$
  select exists(select 1 from staff
                where user_id = auth.uid() and active and role = any(roles));
$$;

-- ============================================================
-- RLS
-- ============================================================
alter table shops enable row level security;
alter table staff enable row level security;
alter table categories enable row level security;
alter table items enable row level security;
alter table item_variants enable row level security;
alter table customers enable row level security;
alter table sales enable row level security;
alter table sale_items enable row level security;
alter table sale_payments enable row level security;
alter table ledger_entries enable row level security;
alter table expenses enable row level security;
alter table expense_categories enable row level security;
alter table held_sales enable row level security;
alter table stock_movements enable row level security;

-- shops
drop policy if exists shops_select on shops;
create policy shops_select on shops for select
  using (id = current_shop_id());
drop policy if exists shops_update on shops;
create policy shops_update on shops for update
  using (id = current_shop_id() and has_role(array['owner','manager']));

-- staff
drop policy if exists staff_select on staff;
create policy staff_select on staff for select
  using (shop_id = current_shop_id());
drop policy if exists staff_write on staff;
create policy staff_write on staff for insert
  with check (shop_id = current_shop_id() and has_role(array['owner','manager']));
drop policy if exists staff_update on staff;
create policy staff_update on staff for update
  using (shop_id = current_shop_id() and has_role(array['owner','manager']));

-- generic tenant policies (same-shop members: read + write)
do $$
declare t text;
begin
  foreach t in array array['categories','items','item_variants','customers',
                           'expenses','expense_categories','held_sales'] loop
    execute format('drop policy if exists %I_select on %I', t, t);
    execute format('create policy %I_select on %I for select using (shop_id = current_shop_id())', t, t);
    execute format('drop policy if exists %I_insert on %I', t, t);
    execute format('create policy %I_insert on %I for insert with check (shop_id = current_shop_id())', t, t);
    execute format('drop policy if exists %I_update on %I', t, t);
    execute format('create policy %I_update on %I for update using (shop_id = current_shop_id())', t, t);
    execute format('drop policy if exists %I_delete on %I', t, t);
    execute format('create policy %I_delete on %I for delete using (shop_id = current_shop_id())', t, t);
  end loop;
end $$;

-- sales family + ledger + movements: members can create/read; updates only owner/manager
do $$
declare t text;
begin
  foreach t in array array['sales','sale_items','sale_payments','ledger_entries','stock_movements'] loop
    execute format('drop policy if exists %I_select on %I', t, t);
    execute format('create policy %I_select on %I for select using (shop_id = current_shop_id())', t, t);
    execute format('drop policy if exists %I_insert on %I', t, t);
    execute format('create policy %I_insert on %I for insert with check (shop_id = current_shop_id())', t, t);
    execute format('drop policy if exists %I_update on %I', t, t);
    execute format('create policy %I_update on %I for update using (shop_id = current_shop_id() and has_role(array[''owner'',''manager'']))', t, t);
    execute format('drop policy if exists %I_delete on %I', t, t);
    execute format('create policy %I_delete on %I for delete using (shop_id = current_shop_id() and has_role(array[''owner'',''manager'']))', t, t);
  end loop;
end $$;

-- ============================================================
-- RPC: shop creation (used right after auth.signUp; definer
-- because the caller has no staff row yet)
-- ============================================================
create or replace function app_create_shop(
  p_shop_name text,
  p_business_type text default 'general',
  p_phone text default '',
  p_address text default ''
) returns bigint
language plpgsql volatile security definer set search_path = public as $$
declare
  v_shop bigint;
  v_bt jsonb;
  v_cat text;
  v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'Not signed in'; end if;
  if exists(select 1 from staff where user_id = v_uid) then
    return current_shop_id();
  end if;

  insert into shops(name, business_type, phone, address)
  values (p_shop_name, p_business_type, p_phone, p_address)
  returning id into v_shop;

  insert into staff(shop_id, user_id, name, phone, role)
  values (v_shop, v_uid,
          coalesce((select raw_user_meta_data->>'name' from auth.users where id = v_uid), 'Owner'),
          p_phone, 'owner');

  select config into v_bt from business_types where key = p_business_type;
  if v_bt is not null then
    for v_cat in select jsonb_array_elements_text(v_bt->'default_categories') loop
      insert into categories(shop_id, name) values (v_shop, v_cat);
    end loop;
  end if;

  insert into expense_categories(shop_id, name)
  select v_shop, x from unnest(array['Rent','Utilities','Salaries','Supplies','Transport','Other']) x;

  return v_shop;
end $$;

-- ============================================================
-- RPC: checkout (server-side pricing, stock, ledger)
-- ============================================================
create or replace function app_checkout(p_payload jsonb) returns jsonb
language plpgsql volatile security invoker set search_path = public as $$
declare
  v_shop bigint := current_shop_id();
  v_line jsonb;
  v_item items%rowtype;
  v_variant item_variants%rowtype;
  v_subtotal numeric := 0;
  v_discount numeric := coalesce((p_payload->>'discount')::numeric, 0);
  v_total numeric;
  v_sale bigint;
  v_receipt bigint;
  v_sid bigint;
  v_sname text;
  v_cust bigint := (p_payload->>'customer_id')::bigint;
  v_cust_name text;
  v_method text;
  v_pay jsonb;
  v_pay_status text;
  v_sale_status text := 'completed';
  v_res jsonb;
  v_held bigint := (p_payload->>'held_sale_id')::bigint;
  v_first bool := true;
begin
  if v_shop is null then raise exception 'No active shop for this user'; end if;
  if jsonb_array_length(coalesce(p_payload->'items','[]'::jsonb)) = 0 then
    raise exception 'Cart is empty';
  end if;

  select id, name into v_sid, v_sname from staff where user_id = auth.uid() and active limit 1;

  -- resolve customer
  if v_cust is not null then
    select name into v_cust_name from customers where id = v_cust and shop_id = v_shop;
    if v_cust_name is null then raise exception 'Customer not found'; end if;
  end if;

  -- server-side pricing pass
  for v_line in select * from jsonb_array_elements(p_payload->'items') loop
    select * into v_item from items
      where id = (v_line->>'item_id')::bigint and shop_id = v_shop;
    if not found then raise exception 'Item % not found', v_line->>'item_id'; end if;
    if v_line->>'variant_id' is not null then
      select * into v_variant from item_variants
        where id = (v_line->>'variant_id')::bigint and item_id = v_item.id;
      if found and v_variant.price_override is not null then
        v_subtotal := v_subtotal + v_variant.price_override * (v_line->>'qty')::numeric;
      else
        v_subtotal := v_subtotal + v_item.price * (v_line->>'qty')::numeric;
      end if;
    else
      v_subtotal := v_subtotal + v_item.price * (v_line->>'qty')::numeric;
    end if;
  end loop;

  v_total := greatest(v_subtotal - v_discount, 0);

  -- primary payment method
  v_pay := p_payload->'payments'->0;
  v_method := coalesce(v_pay->>'method', 'cash');
  v_pay_status := case when v_method in ('telebirr','cbe') then 'pending_verification' else 'verified' end;
  if v_pay_status = 'pending_verification' then v_sale_status := 'pending_verification'; end if;

  if v_method = 'credit' and v_cust is null then
    raise exception 'Credit sales need a customer';
  end if;
  if v_method = 'telebirr' then
    if not exists(select 1 from shops where id = v_shop and accept_telebirr) then
      raise exception 'Telebirr is not accepted';
    end if;
  elsif v_method = 'cbe' then
    if not exists(select 1 from shops where id = v_shop and accept_cbe) then
      raise exception 'CBE Birr is not accepted';
    end if;
  elsif v_method = 'credit' then
    if not exists(select 1 from shops where id = v_shop and accept_credit) then
      raise exception 'Credit sales are disabled';
    end if;
  end if;

  select coalesce(max(receipt_number), 100) + 1 into v_receipt from sales where shop_id = v_shop;

  insert into sales(shop_id, receipt_number, customer_id, customer_name, staff_id, staff_name,
                    subtotal, discount_total, total, method, status, reference,
                    amount_paid, change_due)
  values (v_shop, v_receipt, v_cust, v_cust_name, v_sid, v_sname,
          v_subtotal, v_discount, v_total, v_method, v_sale_status,
          coalesce(v_pay->>'reference_number',''),
          coalesce((v_pay->>'amount')::numeric, v_total),
          greatest(coalesce((v_pay->>'amount')::numeric, v_total) - v_total, 0))
  returning id into v_sale;

  -- lines: stock + movements + sale_items
  for v_line in select * from jsonb_array_elements(p_payload->'items') loop
    select * into v_item from items where id = (v_line->>'item_id')::bigint and shop_id = v_shop;
    if v_item.requires_stock and v_item.type = 'product' then
      if v_line->>'variant_id' is not null then
        select * into v_variant from item_variants where id = (v_line->>'variant_id')::bigint and item_id = v_item.id;
        if found then
          if v_variant.stock_qty < (v_line->>'qty')::int then
            raise exception 'Not enough stock for %', v_item.name;
          end if;
          update item_variants set stock_qty = stock_qty - (v_line->>'qty')::int where id = v_variant.id;
          insert into stock_movements(shop_id, item_id, variant_id, qty_change, reason)
          values (v_shop, v_item.id, v_variant.id, -(v_line->>'qty')::int, 'sale');
        end if;
      else
        if v_item.stock_qty < (v_line->>'qty')::int then
          raise exception 'Not enough stock for %', v_item.name;
        end if;
      end if;
      if v_line->>'variant_id' is null then
        update items set stock_qty = stock_qty - (v_line->>'qty')::int where id = v_item.id;
        insert into stock_movements(shop_id, item_id, qty_change, reason)
        values (v_shop, v_item.id, -(v_line->>'qty')::int, 'sale');
      end if;
    end if;

    insert into sale_items(shop_id, sale_id, item_id, variant_id, name_snapshot,
                           qty, unit_price, line_total, cost_snapshot)
    values (
      v_shop, v_sale, v_item.id,
      nullif(v_line->>'variant_id','')::bigint,
      v_item.name,
      (v_line->>'qty')::numeric,
      case when v_line->>'variant_id' is not null and v_variant.price_override is not null
           then v_variant.price_override else v_item.price end,
      case when v_line->>'variant_id' is not null and v_variant.price_override is not null
           then v_variant.price_override * (v_line->>'qty')::numeric
           else v_item.price * (v_line->>'qty')::numeric end,
      v_item.cost
    );
  end loop;

  -- payments
  for v_pay in select * from jsonb_array_elements(coalesce(p_payload->'payments','[]'::jsonb)) loop
    insert into sale_payments(shop_id, sale_id, method, amount, reference_number, status)
    values (v_shop, v_sale, v_pay->>'method', coalesce((v_pay->>'amount')::numeric, v_total),
            coalesce(v_pay->>'reference_number',''),
            case when v_pay->>'method' in ('telebirr','cbe') then 'pending_verification' else 'verified' end);
  end loop;

  -- credit → ledger charge
  if v_method = 'credit' then
    insert into ledger_entries(shop_id, customer_id, sale_id, type, amount, balance_after, note, staff_name)
    values (v_shop, v_cust, v_sale, 'charge', v_total, 0, 'Credit sale #' || v_receipt, v_sname);
    update customers
       set balance = balance + v_total
     where id = v_cust;
    update ledger_entries
       set balance_after = (select balance from customers where id = v_cust)
     where id = (select max(id) from ledger_entries where customer_id = v_cust and sale_id = v_sale);
  end if;

  -- delete resumed held sale
  if v_held is not null then
    delete from held_sales where id = v_held and shop_id = v_shop;
  end if;

  return app_sale_json(v_sale);
end $$;

-- sale JSON in the exact API shape the Flutter models expect
create or replace function app_sale_json(p_sale bigint) returns jsonb
language sql stable security invoker set search_path = public as $$
  select json_build_object(
    'id', s.id,
    'receipt_number', s.receipt_number,
    'subtotal', s.subtotal,
    'discount_total', s.discount_total,
    'tax_total', s.tax_total,
    'total', s.total,
    'created_at', s.created_at,
    'status', s.status,
    'staff_name', s.staff_name,
    'customer_name', s.customer_name,
    'items', (
      select coalesce(json_agg(json_build_object(
                 'item_name', si.name_snapshot, 'qty', si.qty,
                 'unit_price', si.unit_price, 'discount', si.discount) order by si.id), '[]'::json)
      from sale_items si where si.sale_id = s.id),
    'payments', (
      select coalesce(json_agg(json_build_object(
                 'method', sp.method, 'amount', sp.amount,
                 'reference_number', sp.reference_number, 'status', sp.status) order by sp.id), '[]'::json)
      from sale_payments sp where sp.sale_id = s.id)
  )
  from sales s
  where s.id = p_sale and s.shop_id = current_shop_id();
$$;

-- ============================================================
-- RPC: stock adjust / ledger / refund
-- ============================================================
create or replace function app_stock_adjust(p_item bigint, p_delta int, p_reason text default '')
returns jsonb
language plpgsql volatile security invoker set search_path = public as $$
declare v_shop bigint := current_shop_id();
begin
  update items set stock_qty = greatest(stock_qty + p_delta, 0)
   where id = p_item and shop_id = v_shop;
  if not found then raise exception 'Item not found'; end if;
  insert into stock_movements(shop_id, item_id, qty_change, reason)
  values (v_shop, p_item, p_delta, coalesce(nullif(p_reason,''), 'manual adjustment'));
  return json_build_object('stock_qty', (select stock_qty from items where id = p_item));
end $$;

create or replace function app_add_ledger(p_customer bigint, p_type text, p_amount numeric, p_note text default '')
returns jsonb
language plpgsql volatile security invoker set search_path = public as $$
declare
  v_shop bigint := current_shop_id();
  v_bal numeric;
  v_id bigint;
begin
  if p_amount is null or p_amount <= 0 then raise exception 'Enter a valid amount'; end if;
  select balance into v_bal from customers where id = p_customer and shop_id = v_shop;
  if not found then raise exception 'Customer not found'; end if;

  v_bal := case when p_type = 'payment' then greatest(v_bal - p_amount, 0)
                else v_bal + p_amount end;

  update customers set balance = v_bal where id = p_customer;

  insert into ledger_entries(shop_id, customer_id, type, amount, balance_after, note, staff_name)
  values (v_shop, p_customer, p_type, p_amount, v_bal, p_note,
          (select name from staff where user_id = auth.uid() and active limit 1))
  returning id into v_id;

  return json_build_object('id', v_id, 'type', p_type, 'amount', p_amount,
                           'balance_after', v_bal, 'note', p_note,
                           'created_at', now(),
                           'balance', v_bal);
end $$;

create or replace function app_refund_sale(p_sale bigint, p_reason text default '')
returns jsonb
language plpgsql volatile security invoker set search_path = public as $$
declare
  v_shop bigint := current_shop_id();
  v_sale sales%rowtype;
  v_li sale_items%rowtype;
begin
  select * into v_sale from sales where id = p_sale and shop_id = v_shop;
  if not found then raise exception 'Sale not found'; end if;
  if v_sale.status = 'refunded' then raise exception 'Sale already refunded'; end if;

  for v_li in select * from sale_items where sale_id = p_sale loop
    if v_li.item_id is not null then
      update items set stock_qty = stock_qty + v_li.qty::int where id = v_li.item_id;
      insert into stock_movements(shop_id, item_id, qty_change, reason)
      values (v_shop, v_li.item_id, v_li.qty::int, 'refund #' || v_sale.receipt_number);
    end if;
  end loop;

  -- reverse credit
  if v_sale.method = 'credit' and v_sale.customer_id is not null then
    update customers set balance = greatest(balance - v_sale.total, 0) where id = v_sale.customer_id;
    insert into ledger_entries(shop_id, customer_id, sale_id, type, amount, balance_after, note, staff_name)
    values (v_shop, v_sale.customer_id, p_sale, 'payment', v_sale.total,
            (select balance from customers where id = v_sale.customer_id),
            'Refund of sale #' || v_sale.receipt_number,
            (select name from staff where user_id = auth.uid() and active limit 1));
  end if;

  update sales set status = 'refunded', refund_reason = p_reason where id = p_sale;
  return app_sale_json(p_sale);
end $$;

-- ============================================================
-- RPC: customer detail
-- ============================================================
create or replace function app_customer_detail(p_customer bigint) returns jsonb
language plpgsql stable security invoker set search_path = public as $$
declare v_shop bigint := current_shop_id(); v_res jsonb;
begin
  select json_build_object(
    'customer', to_jsonb(c),
    'sales', coalesce((
      select json_agg(json_build_object(
               'id', s.id, 'receipt_number', s.receipt_number, 'total', s.total,
               'subtotal', s.subtotal, 'discount_total', s.discount_total, 'tax_total', s.tax_total,
               'created_at', s.created_at, 'status', s.status,
               'staff_name', s.staff_name, 'customer_name', s.customer_name,
               'items', coalesce((select json_agg(json_build_object('item_name', si.name_snapshot,
                                  'qty', si.qty, 'unit_price', si.unit_price, 'discount', si.discount))
                                 from sale_items si where si.sale_id = s.id), '[]'::json),
               'payments', coalesce((select json_agg(json_build_object('method', sp.method, 'amount', sp.amount,
                                        'reference_number', sp.reference_number, 'status', sp.status))
                                    from sale_payments sp where sp.sale_id = s.id), '[]'::json))
             order by s.created_at desc)
      from (select * from sales where customer_id = p_customer and shop_id = v_shop
            order by created_at desc limit 20) s), '[]'::json),
    'ledger', coalesce((
      select json_agg(json_build_object(
               'id', l.id, 'type', l.type, 'amount', l.amount, 'balance_after', l.balance_after,
               'note', l.note, 'created_at', l.created_at, 'staff_name', l.staff_name)
             order by l.created_at desc)
      from (select * from ledger_entries where customer_id = p_customer and shop_id = v_shop
            order by created_at desc limit 50) l), '[]'::json)
  )
  into v_res
  from customers c
  where c.id = p_customer and c.shop_id = v_shop;
  if v_res is null then raise exception 'Customer not found'; end if;
  return v_res;
end $$;

-- ============================================================
-- RPC: reports
-- ============================================================
create or replace function app_dashboard() returns jsonb
language plpgsql stable security invoker set search_path = public as $$
declare v_shop bigint := current_shop_id(); v_res jsonb;
begin
  if v_shop is null then return json_build_object('today', json_build_object('total',0,'count',0), 'week_total', 0, 'low_stock_count', 0, 'top_items', '[]'::json); end if;
  select json_build_object(
    'today', json_build_object(
      'total', (select coalesce(sum(total),0) from sales
                 where shop_id = v_shop and status <> 'refunded' and created_at >= date_trunc('day', now())),
      'count', (select count(*) from sales
                 where shop_id = v_shop and status <> 'refunded' and created_at >= date_trunc('day', now())),
      'yesterday_total', (select coalesce(sum(total),0) from sales
                 where shop_id = v_shop and status <> 'refunded'
                   and created_at >= date_trunc('day', now()) - interval '1 day'
                   and created_at < date_trunc('day', now())),
      'trend_pct', case
        when (select coalesce(sum(total),0) from sales where shop_id = v_shop and status <> 'refunded'
                and created_at >= date_trunc('day', now()) - interval '1 day'
                and created_at < date_trunc('day', now())) = 0 then null
        else round(( (select coalesce(sum(total),0) from sales where shop_id = v_shop and status <> 'refunded' and created_at >= date_trunc('day', now()))
                   - (select coalesce(sum(total),0) from sales where shop_id = v_shop and status <> 'refunded'
                        and created_at >= date_trunc('day', now()) - interval '1 day' and created_at < date_trunc('day', now()))
                   ) / nullif((select coalesce(sum(total),0) from sales where shop_id = v_shop and status <> 'refunded'
                        and created_at >= date_trunc('day', now()) - interval '1 day' and created_at < date_trunc('day', now())),0) * 100, 1)
      end),
    'week_total', (select coalesce(sum(total),0) from sales
                     where shop_id = v_shop and status <> 'refunded' and created_at >= now() - interval '7 days'),
    'low_stock_count', (select count(*) from items
                          where shop_id = v_shop and is_active and type = 'product'
                            and stock_qty <= low_stock_threshold),
    'top_items', coalesce((
      select json_agg(json_build_object('name', name, 'qty', qty, 'revenue', revenue))
      from (select si.name_snapshot as name, sum(si.qty) as qty, sum(si.line_total) as revenue
            from sale_items si join sales s on s.id = si.sale_id
            where si.shop_id = v_shop and s.status <> 'refunded'
              and s.created_at >= now() - interval '30 days'
            group by si.name_snapshot order by qty desc limit 5) ti), '[]'::json)
  ) into v_res;
  return v_res;
end $$;

create or replace function app_sales_report(f date, t date) returns jsonb
language plpgsql stable security invoker set search_path = public as $$
declare v_shop bigint := current_shop_id(); v_res jsonb;
begin
  if v_shop is null then return json_build_object('total',0,'count',0,'average',0,'series','[]'::json,'by_method','[]'::json,'by_staff','[]'::json); end if;
  select json_build_object(
    'total', coalesce((select sum(total) from sales
                        where shop_id = v_shop and status <> 'refunded'
                          and created_at::date between f and t), 0),
    'count', coalesce((select count(*) from sales
                        where shop_id = v_shop and status <> 'refunded'
                          and created_at::date between f and t), 0),
    'average', coalesce((select avg(total) from sales
                        where shop_id = v_shop and status <> 'refunded'
                          and created_at::date between f and t), 0),
    'series', coalesce((
      select json_agg(json_build_object('date', d, 'total', tot, 'count', cnt) order by d)
      from (select created_at::date as d, sum(total) as tot, count(*) as cnt
            from sales where shop_id = v_shop and status <> 'refunded'
              and created_at::date between f and t
            group by 1) s), '[]'::json),
    'by_method', coalesce((
      select json_agg(json_build_object('method', method, 'total', tot, 'count', cnt))
      from (select method, sum(total) as tot, count(*) as cnt
            from sales where shop_id = v_shop and status <> 'refunded'
              and created_at::date between f and t
            group by method order by tot desc) m), '[]'::json),
    'by_staff', coalesce((
      select json_agg(json_build_object('staff', st, 'total', tot, 'count', cnt))
      from (select coalesce(staff_name,'—') as st, sum(total) as tot, count(*) as cnt
            from sales where shop_id = v_shop and status <> 'refunded'
              and created_at::date between f and t
            group by 1 order by tot desc) st), '[]'::json)
  ) into v_res;
  return v_res;
end $$;

create or replace function app_best_sellers(f date, t date, by_mode text default 'qty') returns jsonb
language sql stable security invoker set search_path = public as $$
  select json_build_object('results', coalesce((
    select json_agg(json_build_object('name', name, 'qty', qty, 'revenue', revenue))
    from (select si.name_snapshot as name, sum(si.qty) as qty, sum(si.line_total) as revenue
          from sale_items si join sales s on s.id = si.sale_id
          where si.shop_id = current_shop_id() and s.status <> 'refunded'
            and s.created_at::date between f and t
          group by 1
          order by case when by_mode = 'revenue' then sum(si.line_total) else sum(si.qty) end desc
          limit 20) b), '[]'::json));
$$;

create or replace function app_staff_performance(f date, t date) returns jsonb
language sql stable security invoker set search_path = public as $$
  select json_build_object('results', coalesce((
    select json_agg(json_build_object('staff', st, 'total', tot, 'count', cnt))
    from (select coalesce(staff_name,'—') as st, sum(total) as tot, count(*) as cnt
          from sales where shop_id = current_shop_id() and status <> 'refunded'
            and created_at::date between f and t
          group by 1 order by tot desc) s), '[]'::json));
$$;

create or replace function app_pnl(f date, t date) returns jsonb
language plpgsql stable security invoker set search_path = public as $$
declare
  v_shop bigint := current_shop_id();
  v_rev numeric; v_cogs numeric; v_exp numeric; v_res jsonb;
begin
  if v_shop is null then return json_build_object('revenue',0,'cogs',0,'gross_profit',0,'expense_total',0,'net_profit',0,'expenses','[]'::json); end if;
  select coalesce(sum(si.line_total),0), coalesce(sum(si.cost_snapshot * si.qty),0)
    into v_rev, v_cogs
  from sale_items si join sales s on s.id = si.sale_id
  where si.shop_id = v_shop and s.status <> 'refunded'
    and s.created_at::date between f and t;

  select coalesce(sum(amount),0) into v_exp from expenses
   where shop_id = v_shop and spent_date between f and t;

  select json_build_object(
    'revenue', v_rev, 'cogs', v_cogs,
    'gross_profit', v_rev - v_cogs,
    'expense_total', v_exp,
    'net_profit', v_rev - v_cogs - v_exp,
    'estimate_warning', false,
    'expenses', coalesce((
      select json_agg(json_build_object('category', cat, 'total', tot))
      from (select coalesce(ec.name, 'Other') as cat, sum(e.amount) as tot
            from expenses e left join expense_categories ec on ec.id = e.category_id
            where e.shop_id = v_shop and e.spent_date between f and t
            group by 1 order by tot desc) x), '[]'::json)
  ) into v_res;
  return v_res;
end $$;

create or replace function app_debtors() returns jsonb
language sql stable security invoker set search_path = public as $$
  select json_build_object('results', coalesce((
    select json_agg(json_build_object('id', id, 'name', name, 'phone', phone, 'balance', balance))
    from (select id, name, phone, balance from customers
          where shop_id = current_shop_id() and balance > 0.009
          order by balance desc) d), '[]'::json));
$$;
