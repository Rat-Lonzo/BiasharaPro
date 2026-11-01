-- BiasharaPro multi-tenant schema. Run this in Supabase SQL Editor.
create extension if not exists pgcrypto;
create table if not exists public.profiles (
 id uuid primary key references auth.users(id) on delete cascade,
 business_name text not null default 'Biashara yangu',
 business_type text not null default 'Duka la rejareja',
 created_at timestamptz not null default now()
);
create table if not exists public.products (
 id uuid primary key default gen_random_uuid(),
 owner_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
 name text not null,
 sku text,
 quantity numeric(14,2) not null default 0 check (quantity >= 0),
 cost_price numeric(14,2) not null default 0 check (cost_price >= 0),
 selling_price numeric(14,2) not null default 0 check (selling_price >= 0),
 created_at timestamptz not null default now()
);
create unique index if not exists products_owner_sku_unique on public.products(owner_id,sku) where sku is not null and sku <> '';
create table if not exists public.transactions (
 id uuid primary key default gen_random_uuid(),
 owner_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
 product_id uuid references public.products(id) on delete set null,
 type text not null check (type in ('sale','purchase')),
 quantity numeric(14,2) not null default 1 check (quantity > 0),
 total numeric(14,2) not null check (total >= 0),
 description text,
 occurred_at timestamptz not null default now(),
 created_at timestamptz not null default now()
);
create index if not exists products_owner_idx on public.products(owner_id);
create index if not exists transactions_owner_date_idx on public.transactions(owner_id,occurred_at desc);

-- Create a profile automatically when a user signs up.
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
 insert into public.profiles(id,business_name,business_type)
 values(new.id,coalesce(new.raw_user_meta_data->>'business_name','Biashara yangu'),coalesce(new.raw_user_meta_data->>'business_type','Duka la rejareja'))
 on conflict (id) do nothing;
 return new;
end; $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users for each row execute procedure public.handle_new_user();

-- All records are isolated by authenticated user (each self-registered shop).
alter table public.profiles enable row level security;
alter table public.products enable row level security;
alter table public.transactions enable row level security;
drop policy if exists "profile own read" on public.profiles;
create policy "profile own read" on public.profiles for select to authenticated using (id=auth.uid());
drop policy if exists "profile own update" on public.profiles;
create policy "profile own update" on public.profiles for update to authenticated using (id=auth.uid()) with check (id=auth.uid());
drop policy if exists "products own all" on public.products;
create policy "products own all" on public.products for all to authenticated using (owner_id=auth.uid()) with check (owner_id=auth.uid());
drop policy if exists "transactions own all" on public.transactions;
create policy "transactions own all" on public.transactions for all to authenticated using (owner_id=auth.uid()) with check (owner_id=auth.uid());

-- Stock adjustment function verifies that the product belongs to the caller.
create or replace function public.adjust_product_stock(p_product_id uuid,p_quantity numeric)
returns void language plpgsql security invoker set search_path=public as $$
begin
 update public.products set quantity=quantity+p_quantity
 where id=p_product_id and owner_id=auth.uid() and quantity+p_quantity>=0;
 if not found then raise exception 'Bidhaa haipo kwenye akaunti yako au stock haitoshi.'; end if;
end; $$;
grant execute on function public.adjust_product_stock(uuid,numeric) to authenticated;
