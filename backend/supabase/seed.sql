-- ============================================================
-- Velo — demo seed data (3 shops, matches seed_demo.py)
-- Run AFTER schema.sql and AFTER auth users were created via
-- the Admin API (emails: 0911000001@velo.app .. 0911000003)
-- ============================================================

-- business type configs (from backend business_types.py)
insert into business_types(key, config, sort) values
('clothing', '{"key":"clothing","label_en":"Clothing shop","label_am":"የልብስ ሱቅ","icon":"checkroom","catalog_label":"Products","sells_products":true,"sells_services":false,"variants":true,"variant_attributes":["size","color"],"inventory":true,"appointments":false,"barcode":"optional","expiry_tracking":false,"staff_commission":false,"default_categories":["Men","Women","Kids","Shoes & Accessories"]}', 1),
('shoes', '{"key":"shoes","label_en":"Shoe shop","label_am":"የጫማ ሱቅ","icon":"ice_skating","catalog_label":"Products","sells_products":true,"sells_services":false,"variants":true,"variant_attributes":["size","color"],"inventory":true,"appointments":false,"barcode":"optional","expiry_tracking":false,"staff_commission":false,"default_categories":["Men","Women","Kids","Sports"]}', 2),
('supermarket', '{"key":"supermarket","label_en":"Supermarket","label_am":"ሱፈርማርኬት","icon":"shopping_cart","catalog_label":"Products","sells_products":true,"sells_services":false,"variants":false,"variant_attributes":["unit"],"inventory":true,"appointments":false,"barcode":"required","expiry_tracking":true,"staff_commission":false,"default_categories":["Beverages","Snacks","Dairy","Household","Grains & Pulses"]}', 3),
('minimarket', '{"key":"minimarket","label_en":"Mini-market","label_am":"ጥቃት ሱቅ","icon":"storefront","catalog_label":"Products","sells_products":true,"sells_services":false,"variants":false,"variant_attributes":["unit"],"inventory":true,"appointments":false,"barcode":"optional","expiry_tracking":false,"staff_commission":false,"default_categories":["Beverages","Snacks","Household","Other"]}', 4),
('barbershop', '{"key":"barbershop","label_en":"Barbershop / Salon","label_am":"የፀጉር ቤት","icon":"content_cut","catalog_label":"Services","sells_products":false,"sells_services":true,"variants":false,"variant_attributes":["duration"],"inventory":false,"appointments":true,"barcode":"no","expiry_tracking":false,"staff_commission":true,"default_categories":["Haircut","Beard trim","Shave","Hair treatment"]}', 5),
('general', '{"key":"general","label_en":"General seller","label_am":"አጠቃላይ ሻጭ","icon":"category","catalog_label":"Products","sells_products":true,"sells_services":false,"variants":false,"variant_attributes":[],"inventory":true,"appointments":false,"barcode":"optional","expiry_tracking":false,"staff_commission":false,"default_categories":["General","Other"]}', 6),
('hybrid', '{"key":"hybrid","label_en":"Hybrid (products + services)","label_am":"ድብልቅ (ᝍፍት + አገልግሎት)","icon":"widgets","catalog_label":"Catalog","sells_products":true,"sells_services":true,"variants":true,"variant_attributes":["size","color"],"inventory":true,"appointments":true,"barcode":"optional","expiry_tracking":false,"staff_commission":true,"default_categories":["Services","Retail products"]}', 7)
on conflict (key) do update set config = excluded.config;

-- ============================================================
-- Shops (owner users must already exist in auth.users)
-- ============================================================
insert into shops(id, name, business_type, phone, address, receipt_footer)
OVERRIDING SYSTEM VALUE
values (1, 'Sheger Supermarket', 'supermarket', '0911000001', 'Bole Road, Addis Ababa', 'Thank you for shopping with us!'),
       (2, 'Merkato Fashion House', 'clothing', '0911000002', 'Merkato, Addis Ababa', 'Exchange within 7 days with receipt.'),
       (3, 'Addis Fade Barbershop', 'barbershop', '0911000003', 'Piassa, Addis Ababa', 'Walk-ins welcome!')
on conflict (id) do nothing;
select setval(pg_get_serial_sequence('shops','id'), (select max(id) from shops));

insert into staff(shop_id, user_id, name, phone, role)
select s.id, u.id,
       case s.id when 1 then 'Abebe Kebede' when 2 then 'Sara Tesfaye' else 'Dawit Mengistu' end,
       case s.id when 1 then '0911000001' when 2 then '0911000002' else '0911000003' end,
       'owner'
from shops s join auth.users u
  on u.email = case s.id when 1 then '0911000001@velo.app'
                         when 2 then '0911000002@velo.app'
                         else '0911000003@velo.app' end
on conflict do nothing;

-- one cashier + one staff per shop (no login account yet)
insert into staff(shop_id, name, phone, role, commission_percent)
select id, 'Hanna Girma', '0912345670', 'cashier', 0 from shops
union all
select id, 'Yonas Alemu', '0912345671', 'staff', 5.0 from shops;

-- categories
insert into categories(shop_id, name)
select 1, x from unnest(array['Beverages','Snacks','Dairy','Household','Grains & Pulses']) x
union all select 2, x from unnest(array['Men','Women','Kids','Shoes & Accessories']) x
union all select 3, x from unnest(array['Haircut','Beard trim','Shave','Hair treatment']) x;

-- expense categories
insert into expense_categories(shop_id, name)
select s.id, x from shops s, unnest(array['Rent','Utilities','Salaries','Supplies','Transport','Other']) x;

-- ============================================================
-- Items
-- ============================================================
insert into items(shop_id, category_id, type, name, price, cost, stock_qty, low_stock_threshold, barcode, unit)
values
-- Sheger Supermarket (shop 1)
(1, (select id from categories where shop_id=1 and name='Beverages'), 'product', 'Coca-Cola 500ml', 45, 32, 120, 24, '5449000000996', 'pc'),
(1, (select id from categories where shop_id=1 and name='Beverages'), 'product', 'Sprite 500ml', 45, 32, 96, 24, '5449000000016', 'pc'),
(1, (select id from categories where shop_id=1 and name='Beverages'), 'product', 'Pepsi 500ml', 42, 30, 60, 24, '5506000130505', 'pc'),
(1, (select id from categories where shop_id=1 and name='Beverages'), 'product', 'Ambo Mineral Water 500ml', 25, 17, 200, 40, '5670000000012', 'pc'),
(1, (select id from categories where shop_id=1 and name='Dairy'), 'product', 'Mama Milk 1L', 95, 78, 40, 10, '5670000000029', 'pc'),
(1, (select id from categories where shop_id=1 and name='Dairy'), 'product', 'Yogurt Cup 500g', 110, 85, 25, 8, '5670000000036', 'pc'),
(1, (select id from categories where shop_id=1 and name='Snacks'), 'product', 'Emburg Peanut 50g', 15, 10, 300, 50, '5670000000043', 'pc'),
(1, (select id from categories where shop_id=1 and name='Snacks'), 'product', 'Biscuit Cream Pack', 35, 24, 150, 30, '5670000000050', 'pc'),
(1, (select id from categories where shop_id=1 and name='Household'), 'product', 'Detergent Soap 200g', 60, 45, 80, 20, '5670000000067', 'pc'),
(1, (select id from categories where shop_id=1 and name='Household'), 'product', 'Toilet Paper 4 rolls', 130, 98, 55, 12, '5670000000074', 'pc'),
(1, (select id from categories where shop_id=1 and name='Grains & Pulses'), 'product', 'Rice 1kg', 145, 118, 90, 20, '5670000000081', 'kg'),
(1, (select id from categories where shop_id=1 and name='Grains & Pulses'), 'product', 'Berbere 500g', 320, 260, 30, 8, '5670000000098', 'pc'),
(1, (select id from categories where shop_id=1 and name='Grains & Pulses'), 'product', 'Shiro Powder 500g', 180, 140, 5, 8, '5670000000104', 'pc'),
(1, (select id from categories where shop_id=1 and name='Beverages'), 'product', 'Sheba Coffee 250g', 260, 205, 48, 10, '5670000000111', 'pc'),
-- Merkato Fashion House (shop 2)
(2, (select id from categories where shop_id=2 and name='Men'), 'product', 'Men T-Shirt Cotton', 850, 600, 40, 6, '', 'pc'),
(2, (select id from categories where shop_id=2 and name='Men'), 'product', 'Men Jeans Slim', 2200, 1600, 25, 5, '', 'pc'),
(2, (select id from categories where shop_id=2 and name='Men'), 'product', 'Men Shirt Formal', 1750, 1250, 18, 4, '', 'pc'),
(2, (select id from categories where shop_id=2 and name='Women'), 'product', 'Women Dress Netela', 1450, 1000, 22, 5, '', 'pc'),
(2, (select id from categories where shop_id=2 and name='Women'), 'product', 'Habesha Kemis Modern', 3800, 2700, 10, 3, '', 'pc'),
(2, (select id from categories where shop_id=2 and name='Women'), 'product', 'Women Handbag', 1250, 850, 15, 4, '', 'pc'),
(2, (select id from categories where shop_id=2 and name='Kids'), 'product', 'Kids Hoodie', 750, 520, 30, 6, '', 'pc'),
(2, (select id from categories where shop_id=2 and name='Shoes & Accessories'), 'product', 'Leather Belt', 480, 300, 35, 8, '', 'pc'),
(2, (select id from categories where shop_id=2 and name='Shoes & Accessories'), 'product', 'Sneakers Urban', 2600, 1900, 4, 5, '', 'pc'),
(2, (select id from categories where shop_id=2 and name='Men'), 'product', 'Men Jacket Winter', 3200, 2300, 12, 3, '', 'pc'),
-- Addis Fade Barbershop (shop 3) — services
(3, (select id from categories where shop_id=3 and name='Haircut'), 'service', 'Fade Haircut', 350, 0, 0, 0, '', ''),
(3, (select id from categories where shop_id=3 and name='Haircut'), 'service', 'Classic Haircut', 250, 0, 0, 0, '', ''),
(3, (select id from categories where shop_id=3 and name='Haircut'), 'service', 'Kids Haircut', 180, 0, 0, 0, '', ''),
(3, (select id from categories where shop_id=3 and name='Beard trim'), 'service', 'Beard Trim & Shape', 150, 0, 0, 0, '', ''),
(3, (select id from categories where shop_id=3 and name='Shave'), 'service', 'Hot Towel Shave', 200, 0, 0, 0, '', ''),
(3, (select id from categories where shop_id=3 and name='Hair treatment'), 'service', 'Hair Wash & Style', 220, 0, 0, 0, '', '')
on conflict do nothing;

-- variants for selected clothing items
insert into item_variants(shop_id, item_id, attributes, stock_qty, price_override)
select i.shop_id, i.id, jsonb_build_object('size', s, 'color', c), v, null
from items i
join (values ('Men T-Shirt Cotton', 850), ('Kids Hoodie', 750)) seeds(seede, po) on i.name = seeds.seede
cross join (values ('M','Black',12),('M','White',10),('L','Black',9),('L','White',9)) s(s, c, v)
where i.shop_id = 2;

insert into item_variants(shop_id, item_id, attributes, stock_qty)
select i.shop_id, i.id, jsonb_build_object('size', s, 'color', c), v
from items i
join (values ('Men Jeans Slim')) seeds(seede) on i.name = seeds.seede
cross join (values ('30','Blue',8),('32','Blue',9),('34','Blue',8)) s(s, c, v)
where i.shop_id = 2;

-- ============================================================
-- Customers + consistent credit ledgers
-- ============================================================
insert into customers(shop_id, name, phone, notes, balance)
values (1, 'Alem Tadesse', '0912112201', 'Regular — buys weekly', 0),
       (1, 'Marta Wolde', '0912112202', '', 0),
       (1, 'Kebede Chala', '0912112203', 'Office account — Sheger Traders', 0),
       (1, 'Fatuma Nur', '0912112204', '', 0),
       (1, 'Girma Bekele', '0912112205', 'Neighbors with shop', 0),
       (2, 'Selam Girmay', '0912112211', 'Wholesale buyer', 0),
       (2, 'Nardos Haile', '0912112212', '', 0),
       (2, 'Bdu Express Hotel', '0912112213', 'Bulk uniform orders', 0),
       (2, 'Rahel Assefa', '0912112214', '', 0),
       (3, 'Mikiyas Tadesse', '0912112221', 'Every Friday', 0),
       (3, 'Abel Fikru', '0912112222', '', 0),
       (3, 'Henok Mulugeta', '0912112223', 'Monthly plan', 0)
on conflict do nothing;

-- credit histories (balance_after must chain correctly)
insert into ledger_entries(shop_id, customer_id, type, amount, balance_after, note, staff_name, created_at)
values
(1, (select id from customers where shop_id=1 and name='Kebede Chala'), 'charge', 1200, 1200, 'Credit sale #101', 'Abebe Kebede', now() - interval '12 days'),
(1, (select id from customers where shop_id=1 and name='Kebede Chala'), 'payment', 700, 500, 'Cash payment', 'Abebe Kebede', now() - interval '9 days'),
(1, (select id from customers where shop_id=1 and name='Kebede Chala'), 'charge', 640, 1140, 'Credit sale #118', 'Abebe Kebede', now() - interval '4 days'),
(1, (select id from customers where shop_id=1 and name='Marta Wolde'), 'charge', 350, 350, 'Credit sale #105', 'Hanna Girma', now() - interval '8 days'),
(1, (select id from customers where shop_id=1 and name='Marta Wolde'), 'payment', 350, 0, 'Full payment', 'Hanna Girma', now() - interval '2 days'),
(2, (select id from customers where shop_id=2 and name='Bdu Express Hotel'), 'charge', 9500, 9500, 'Uniform order on account', 'Sara Tesfaye', now() - interval '15 days'),
(2, (select id from customers where shop_id=2 and name='Bdu Express Hotel'), 'payment', 4000, 5500, 'Bank transfer CBE', 'Sara Tesfaye', now() - interval '6 days'),
(2, (select id from customers where shop_id=2 and name='Selam Girmay'), 'charge', 2300, 2300, 'Credit sale #131', 'Sara Tesfaye', now() - interval '3 days'),
(3, (select id from customers where shop_id=3 and name='Henok Mulugeta'), 'charge', 530, 530, 'Credit sale #107', 'Dawit Mengistu', now() - interval '7 days'),
(3, (select id from customers where shop_id=3 and name='Henok Mulugeta'), 'payment', 300, 230, 'Partial payment', 'Dawit Mengistu', now() - interval '1 day');

update customers c set balance = coalesce((
  select sum(case when l.type='payment' then -l.amount else l.amount end)
  from ledger_entries l where l.customer_id = c.id), 0);

-- ============================================================
-- Sales history: last 14 days via generator
-- ============================================================
do $$
declare
  s int; d int; n int; k int; nsale bigint;
  v_items int[]; v_qty numeric; v_line record; v_sub numeric; v_disc numeric; v_tot numeric;
  v_methods text[] := array['cash','cash','cash','telebirr','cbe','credit'];
  v_m text; v_created timestamptz; v_staff record; v_cust int; v_paying numeric;
  v_sn text; v_st int;
begin
  for s in 1..3 loop
    for d in 0..13 loop
      n := 1 + floor(random() * 4)::int; -- 1..3 sales per day
      for k in 1..n loop
        v_created := (current_date - d)::timestamptz
                     + interval '8 hours' + (random() * interval '11 hours')
                     - make_interval(hours := 0);
        if d = 0 then
          v_created := now() - (random() * interval '5 hours');
        end if;
        v_sub := 0;
        v_items := array(select id from items where shop_id = s order by random() limit (1 + floor(random()*3)::int));
        -- pick staff + customer
        select id, name into v_st, v_sn from staff where shop_id = s and role in ('owner','cashier') order by random() limit 1;
        if random() < 0.5 then
          select id into v_cust from customers where shop_id = s order by random() limit 1;
        else
          v_cust := null;
        end if;
        v_m := v_methods[1 + floor(random() * 6)::int];
        if v_m = 'credit' and v_cust is null then v_m := 'cash'; end if;

        -- create sale skeleton (temp zero, updated after lines)
        insert into sales(shop_id, receipt_number, customer_id, staff_id, staff_name, subtotal,
                          discount_total, total, method, status, amount_paid, change_due, created_at)
        values (s, (select coalesce(max(receipt_number),100)+1 from sales where shop_id = s),
                v_cust, v_st, v_sn, 0, 0, 0, v_m, 'completed', 0, 0, v_created)
        returning id into nsale;

        for v_line in
          select i.id, i.name, i.price, i.cost, i.type
          from items i where i.id = any(v_items)
        loop
          v_qty := 1 + floor(random() * 3)::int;
          insert into sale_items(shop_id, sale_id, item_id, name_snapshot, qty, unit_price, line_total, cost_snapshot)
          values (s, nsale, v_line.id, v_line.name, v_qty, v_line.price, v_line.price * v_qty, v_line.cost);
          v_sub := v_sub + v_line.price * v_qty;
        end loop;

        v_disc := case when random() < 0.15 then round(v_sub * 0.05) else 0 end;
        v_tot := v_sub - v_disc;
        update sales set subtotal = v_sub, discount_total = v_disc, total = v_tot,
               amount_paid = v_tot, change_due = 0
         where id = nsale;
        insert into sale_payments(shop_id, sale_id, method, amount, reference_number, status)
        values (s, nsale, v_m, v_tot,
                case when v_m in ('telebirr','cbe') then 'TB' || lpad((100000 + floor(random()*899999))::text, 6, '0') else '' end,
                'verified');
        if v_m = 'credit' and v_cust is not null then
          insert into ledger_entries(shop_id, customer_id, sale_id, type, amount, balance_after, note, staff_name, created_at)
          values (s, v_cust, nsale, 'charge', v_tot, 0, 'Credit sale #' || nsale, v_sn, v_created);
        end if;
      end loop;
    end loop;
  end loop;
end $$;

-- recalc customer balances & ledger balance_after to stay consistent
update customers c set balance = coalesce((
  select sum(case when l.type='payment' then -l.amount else l.amount end)
  from ledger_entries l where l.customer_id = c.id), 0);

with chain as (
  select id, customer_id,
         sum(case when type='payment' then -amount else amount end)
           over (partition by customer_id order by created_at, id) as bal
  from ledger_entries
)
update ledger_entries l set balance_after = chain.bal
from chain where chain.id = l.id;

-- expenses this month
insert into expenses(shop_id, category_id, amount, note, spent_date)
values (1, (select id from expense_categories where shop_id=1 and name='Rent'), 18000, 'Monthly rent — Bole', current_date - 10),
       (1, (select id from expense_categories where shop_id=1 and name='Utilities'), 1450, 'Electricity', current_date - 6),
       (1, (select id from expense_categories where shop_id=1 and name='Supplies'), 900, 'Receipt books & bags', current_date - 3),
       (1, (select id from expense_categories where shop_id=1 and name='Salaries'), 6500, 'Hanna — monthly', current_date - 1),
       (2, (select id from expense_categories where shop_id=2 and name='Rent'), 22000, 'Merkato stall rent', current_date - 9),
       (2, (select id from expense_categories where shop_id=2 and name='Transport'), 800, 'Fabric pickup — Shiro Meda', current_date - 4),
       (2, (select id from expense_categories where shop_id=2 and name='Utilities'), 620, 'Water & power', current_date - 2),
       (3, (select id from expense_categories where shop_id=3 and name='Rent'), 9000, 'Piassa corner', current_date - 8),
       (3, (select id from expense_categories where shop_id=3 and name='Supplies'), 540, 'Creams & towels', current_date - 5),
       (3, (select id from expense_categories where shop_id=3 and name='Utilities'), 410, 'Electricity', current_date - 2);

-- one held sale for the supermarket
insert into held_sales(shop_id, label, payload)
values (1, 'Morning rush — colas', jsonb_build_object(
  'lines', jsonb_build_array(
    jsonb_build_object('item_id', (select id from items where shop_id=1 and name='Coca-Cola 500ml'),
                       'variant_id', null, 'name', 'Coca-Cola 500ml', 'variant_label', null,
                       'unit_price', 45, 'qty', 6, 'is_service', false, 'available_stock', 120),
    jsonb_build_object('item_id', (select id from items where shop_id=1 and name='Biscuit Cream Pack'),
                       'variant_id', null, 'name', 'Biscuit Cream Pack', 'variant_label', null,
                       'unit_price', 35, 'qty', 2, 'is_service', false, 'available_stock', 150)),
  'customer_id', null, 'customer_name', null, 'discount', 0));

-- low stock helper: make one supermarket item clearly low
update items set stock_qty = 3 where shop_id = 1 and name = 'Shiro Powder 500g';
