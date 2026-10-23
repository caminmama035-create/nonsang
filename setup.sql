-- ===== ติดตั้งฐานข้อมูลร้าน (รันครั้งเดียวในโปรเจกต์ Supabase ใหม่) =====
create table if not exists products(
  id uuid primary key default gen_random_uuid(),
  name text not null, description text, price int not null,
  active boolean not null default true, image_url text, preview_url text,
  created_at timestamptz default now());
create table if not exists admins(user_id uuid primary key references auth.users on delete cascade);
create table if not exists orders(
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users on delete cascade default auth.uid(),
  email text, drive_email text, total int not null, slip_path text,
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  created_at timestamptz default now());
create table if not exists order_items(
  id bigint generated always as identity primary key,
  order_id bigint not null references orders on delete cascade,
  product_id uuid references products on delete set null, price int not null);
create table if not exists product_files(
  product_id uuid primary key references products on delete cascade,
  drive_url text, file_path text);
create table if not exists shop_settings(id int primary key default 1, data jsonb not null default '{}'::jsonb);

create or replace function public.is_admin() returns boolean language sql stable security definer set search_path=public as
$$ select exists(select 1 from admins where user_id = auth.uid()) $$;

alter table products enable row level security;
alter table admins enable row level security;
alter table orders enable row level security;
alter table order_items enable row level security;
alter table product_files enable row level security;
alter table shop_settings enable row level security;

grant select on products, shop_settings to anon;

create policy products_read on products for select to anon, authenticated using (active or is_admin());
create policy products_admin on products for all to authenticated using (is_admin()) with check (is_admin());
create policy admins_self on admins for select to authenticated using (user_id = auth.uid());
create policy orders_read on orders for select to authenticated using (user_id = auth.uid() or is_admin());
create policy orders_insert on orders for insert to authenticated with check (user_id = auth.uid() and status = 'pending');
create policy orders_admin_update on orders for update to authenticated using (is_admin()) with check (is_admin());
create policy items_read on order_items for select to authenticated using (is_admin() or exists(select 1 from orders o where o.id = order_id and o.user_id = auth.uid()));
create policy items_insert on order_items for insert to authenticated with check (exists(select 1 from orders o where o.id = order_id and o.user_id = auth.uid() and o.status = 'pending'));
create policy pf_admin on product_files for all to authenticated using (is_admin()) with check (is_admin());
create policy pf_customer_read on product_files for select to authenticated using (exists(
  select 1 from order_items i join orders o on o.id = i.order_id
  where i.product_id = product_files.product_id and o.user_id = auth.uid() and o.status = 'approved'));
create policy settings_read on shop_settings for select to anon, authenticated using (true);
create policy settings_admin on shop_settings for all to authenticated using (is_admin()) with check (is_admin());
insert into shop_settings(id,data) values (1,'{}') on conflict do nothing;

insert into storage.buckets(id,name,public) values ('slips','slips',false),('covers','covers',true) on conflict (id) do nothing;
create policy slips_upload on storage.objects for insert to authenticated with check (bucket_id='slips' and (storage.foldername(name))[1] = auth.uid()::text);
create policy slips_read on storage.objects for select to authenticated using (bucket_id='slips' and ((storage.foldername(name))[1] = auth.uid()::text or is_admin()));
create policy covers_admin_insert on storage.objects for insert to authenticated with check (bucket_id='covers' and is_admin());
create policy covers_admin_delete on storage.objects for delete to authenticated using (bucket_id='covers' and is_admin());
