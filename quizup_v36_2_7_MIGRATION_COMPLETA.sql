-- QuizUp v36.2.7 - migration consolidada Mercado Pago + Coins + segurança
-- Execute depois das migrations anteriores. Não apaga dados existentes.

-- 1. Segurança de cadastro
create unique index if not exists profiles_username_lower_unique on public.profiles(lower(username)) where username is not null;
create or replace function public.is_username_available(p_username text) returns boolean language sql security definer set search_path=public as $$ select not exists(select 1 from public.profiles where lower(username)=lower(trim(p_username))); $$;
revoke all on function public.is_username_available(text) from public; grant execute on function public.is_username_available(text) to anon,authenticated;

-- 2. Controle da loja/pagamentos
-- Corrigido: a tabela precisa existir ANTES de qualquer ALTER ou função que a referencie.
create table if not exists public.premium_store_settings (
  id integer primary key check (id = 1),
  enabled boolean not null default true,
  cosmetics_enabled boolean not null default true,
  vip_enabled boolean not null default true,
  coins_enabled boolean not null default true,
  pass_enabled boolean not null default true,
  payments_enabled boolean not null default false,
  updated_at timestamptz not null default now()
);

alter table public.premium_store_settings
  add column if not exists enabled boolean not null default true,
  add column if not exists cosmetics_enabled boolean not null default true,
  add column if not exists vip_enabled boolean not null default true,
  add column if not exists coins_enabled boolean not null default true,
  add column if not exists pass_enabled boolean not null default true,
  add column if not exists payments_enabled boolean not null default false,
  add column if not exists updated_at timestamptz not null default now();

insert into public.premium_store_settings
  (id, enabled, cosmetics_enabled, vip_enabled, coins_enabled, pass_enabled, payments_enabled)
values
  (1, true, true, true, true, true, false)
on conflict (id) do nothing;

-- 2.1. Compatibilidade: cria as tabelas premium somente se uma instalação anterior ainda não as tiver.
-- Se elas já existirem, nada é alterado aqui.
create table if not exists public.premium_items (
  id text primary key,
  name text not null,
  category text not null,
  description text,
  price_cents integer not null default 0,
  price_coins bigint not null default 0,
  promo_price_cents integer,
  promo_price_coins bigint,
  promo_active boolean not null default false,
  promo_expires_at timestamptz,
  icon text,
  asset_url text,
  kind text,
  active boolean not null default true,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);

create table if not exists public.user_premium_items (
  user_id uuid not null references public.profiles(id) on delete cascade,
  item_id text not null references public.premium_items(id) on delete cascade,
  active boolean not null default false,
  purchased_at timestamptz not null default now(),
  primary key (user_id, item_id)
);

alter table public.premium_items enable row level security;
drop policy if exists "premium items read active" on public.premium_items;
create policy "premium items read active"
  on public.premium_items for select
  to anon, authenticated
  using (active = true or exists (
    select 1 from public.profiles p
    where p.id = auth.uid() and p.role = 'admin'
  ));

drop policy if exists "premium items admin insert" on public.premium_items;
create policy "premium items admin insert"
  on public.premium_items for insert
  to authenticated
  with check (exists (
    select 1 from public.profiles p
    where p.id = auth.uid() and p.role = 'admin'
  ));

drop policy if exists "premium items admin update" on public.premium_items;
create policy "premium items admin update"
  on public.premium_items for update
  to authenticated
  using (exists (
    select 1 from public.profiles p
    where p.id = auth.uid() and p.role = 'admin'
  ))
  with check (exists (
    select 1 from public.profiles p
    where p.id = auth.uid() and p.role = 'admin'
  ));

alter table public.user_premium_items enable row level security;
drop policy if exists "user premium own read" on public.user_premium_items;
create policy "user premium own read"
  on public.user_premium_items for select
  to authenticated
  using (user_id = auth.uid());

drop policy if exists "user premium own insert" on public.user_premium_items;
create policy "user premium own insert"
  on public.user_premium_items for insert
  to authenticated
  with check (user_id = auth.uid());

drop policy if exists "user premium own update" on public.user_premium_items;
create policy "user premium own update"
  on public.user_premium_items for update
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- Garante que a coluna de Coins exista em instalações que ainda não receberam essa parte.
alter table public.profiles add column if not exists coins bigint not null default 0;

-- 3. Pacotes de Coins
create table if not exists public.coin_packages(id uuid primary key default gen_random_uuid(),name text not null,coins bigint not null check(coins>0),price_cents integer not null check(price_cents>0),active boolean not null default true,sort_order integer not null default 0,created_at timestamptz not null default now(),created_by uuid references public.profiles(id) on delete set null);
alter table public.coin_packages enable row level security;
drop policy if exists "coin packages read active" on public.coin_packages;
create policy "coin packages read active" on public.coin_packages for select to authenticated using(active=true or exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin'));
drop policy if exists "coin packages admin insert" on public.coin_packages;
create policy "coin packages admin insert" on public.coin_packages for insert to authenticated with check(exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin'));
drop policy if exists "coin packages admin update" on public.coin_packages;
create policy "coin packages admin update" on public.coin_packages for update to authenticated using(exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin')) with check(exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin'));

insert into public.coin_packages(name,coins,price_cents,sort_order,active) select v.name,v.coins,v.price_cents,v.sort_order,true from (values('Pacote 1.000 Coins',1000,1000,1),('Pacote 2.500 Coins',2500,2000,2),('Pacote 6.000 Coins',6000,4500,3)) v(name,coins,price_cents,sort_order) where not exists(select 1 from public.coin_packages cp where cp.coins=v.coins and cp.price_cents=v.price_cents);

-- 4. Pedidos reais de Coins
create table if not exists public.coin_orders(id uuid primary key default gen_random_uuid(),user_id uuid not null references public.profiles(id) on delete cascade,package_id uuid references public.coin_packages(id) on delete set null,coins bigint not null check(coins>0),amount_cents integer not null check(amount_cents>0),status text not null default 'pending' check(status in ('pending','approved','paid','rejected','cancelled','refunded')),provider text not null default 'mercadopago',provider_preference_id text,provider_payment_id text,external_reference text not null unique,raw_payment jsonb,created_at timestamptz not null default now(),updated_at timestamptz not null default now(),paid_at timestamptz);
create unique index if not exists coin_orders_provider_payment_uidx on public.coin_orders(provider,provider_payment_id) where provider_payment_id is not null;
create index if not exists coin_orders_user_created_idx on public.coin_orders(user_id,created_at desc);
create index if not exists coin_orders_status_idx on public.coin_orders(status,created_at desc);
alter table public.coin_orders enable row level security;
drop policy if exists "coin orders own read" on public.coin_orders;
create policy "coin orders own read" on public.coin_orders for select to authenticated using(user_id=auth.uid());
drop policy if exists "coin orders admin read" on public.coin_orders;
create policy "coin orders admin read" on public.coin_orders for select to authenticated using(exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin'));

-- 5. Ledger idempotente
create table if not exists public.coin_ledger(id bigint generated by default as identity primary key,user_id uuid not null references public.profiles(id) on delete cascade,amount bigint not null,source_type text not null,source_id text not null,description text,created_at timestamptz not null default now(),unique(source_type,source_id,user_id));
alter table public.coin_ledger enable row level security;
drop policy if exists "coin ledger own read" on public.coin_ledger;
create policy "coin ledger own read" on public.coin_ledger for select to authenticated using(user_id=auth.uid());

-- 6. Pedido criado no servidor. O cliente não envia preço.
create or replace function public.create_coin_order(p_package_id uuid) returns public.coin_orders language plpgsql security definer set search_path=public as $$
declare p public.coin_packages; s public.premium_store_settings; o public.coin_orders; ref text;
begin
 if auth.uid() is null then raise exception 'Não autenticado'; end if;
 if (select count(*) from public.coin_orders where user_id=auth.uid() and status='pending' and created_at>now()-interval '10 minutes') >= 5 then raise exception 'Muitas compras pendentes. Aguarde alguns minutos antes de criar outra.'; end if;
 select * into s from public.premium_store_settings where id=1;
 if coalesce(s.enabled,false)=false or coalesce(s.coins_enabled,false)=false or coalesce(s.payments_enabled,false)=false then raise exception 'A compra de QuizCoins está desativada'; end if;
 select * into p from public.coin_packages where id=p_package_id and active=true;
 if p.id is null then raise exception 'Pacote de Coins não encontrado ou inativo'; end if;
 o.id:=gen_random_uuid(); ref:='quizup_'||replace(o.id::text,'-','');
 insert into public.coin_orders(id,user_id,package_id,coins,amount_cents,status,external_reference) values(o.id,auth.uid(),p.id,p.coins,p.price_cents,'pending',ref) returning * into o;
 return o;
end $$;
revoke all on function public.create_coin_order(uuid) from public; grant execute on function public.create_coin_order(uuid) to authenticated;

-- 7. Confirmação server-side e crédito atômico. Somente service_role pode executar.
create or replace function public.finalize_coin_payment(p_order_id uuid,p_payment_id text,p_status text,p_amount_cents integer,p_raw jsonb default '{}'::jsonb) returns jsonb language plpgsql security definer set search_path=public as $$
declare o public.coin_orders; bal bigint; final_status text;
begin
 select * into o from public.coin_orders where id=p_order_id for update;
 if o.id is null then raise exception 'Pedido não encontrado'; end if;
 final_status:=case when p_status='approved' then 'approved' when p_status in ('pending','in_process','authorized') then 'pending' when p_status in ('cancelled','refunded','charged_back') then 'refunded' else 'rejected' end;
 if o.status in ('approved','paid') then return jsonb_build_object('ok',true,'already_processed',true,'status',o.status,'coins',o.coins); end if;
 if final_status='approved' then
   if p_amount_cents<>o.amount_cents then raise exception 'Valor do pagamento não corresponde ao pedido'; end if;
   if exists(select 1 from public.coin_ledger l where l.source_type='mercadopago_payment' and l.source_id=p_payment_id and l.user_id=o.user_id) then
     update public.coin_orders set status='approved',provider_payment_id=p_payment_id,raw_payment=p_raw,updated_at=now(),paid_at=coalesce(paid_at,now()) where id=o.id;
     return jsonb_build_object('ok',true,'already_processed',true,'status','approved','coins',o.coins);
   end if;
   update public.profiles set coins=coalesce(coins,0)+o.coins where id=o.user_id returning coins into bal;
   insert into public.coin_ledger(user_id,amount,source_type,source_id,description) values(o.user_id,o.coins,'mercadopago_payment',p_payment_id,'Compra de QuizCoins') on conflict do nothing;
   update public.coin_orders set status='approved',provider_payment_id=p_payment_id,raw_payment=p_raw,updated_at=now(),paid_at=now() where id=o.id;
   return jsonb_build_object('ok',true,'already_processed',false,'status','approved','coins',o.coins,'balance',bal);
 end if;
 update public.coin_orders set status=final_status,provider_payment_id=coalesce(provider_payment_id,p_payment_id),raw_payment=p_raw,updated_at=now() where id=o.id;
 return jsonb_build_object('ok',true,'already_processed',false,'status',final_status,'coins',0);
end $$;
revoke all on function public.finalize_coin_payment(uuid,text,text,integer,jsonb) from public; grant execute on function public.finalize_coin_payment(uuid,text,text,integer,jsonb) to service_role;

-- 8. Atualiza preferência pelo usuário autenticado
create or replace function public.set_coin_order_preference(p_order_id uuid,p_preference_id text) returns public.coin_orders language plpgsql security definer set search_path=public as $$
declare o public.coin_orders;
begin update public.coin_orders set provider_preference_id=p_preference_id,updated_at=now() where id=p_order_id and user_id=auth.uid() and status='pending' returning * into o; if o.id is null then raise exception 'Pedido não encontrado'; end if; return o; end $$;
revoke all on function public.set_coin_order_preference(uuid,text) from public; grant execute on function public.set_coin_order_preference(uuid,text) to authenticated;

-- 9. Administração de vendas/contas
create or replace function public.admin_list_coin_orders(p_limit integer default 100) returns table(id uuid,username text,email text,coins bigint,amount_cents integer,status text,provider_payment_id text,created_at timestamptz,paid_at timestamptz) language plpgsql security definer set search_path=public,auth as $$
begin if not exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin') then raise exception 'Acesso negado'; end if; return query select o.id,p.username,u.email,o.coins,o.amount_cents,o.status,o.provider_payment_id,o.created_at,o.paid_at from public.coin_orders o join public.profiles p on p.id=o.user_id join auth.users u on u.id=o.user_id order by o.created_at desc limit greatest(1,least(coalesce(p_limit,100),500)); end $$;
revoke all on function public.admin_list_coin_orders(integer) from public; grant execute on function public.admin_list_coin_orders(integer) to authenticated;
create or replace function public.admin_list_accounts() returns table(id uuid,username text,display_name text,email text,role text,created_at timestamptz) language plpgsql security definer set search_path=public,auth as $$ begin if not exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin') then raise exception 'Acesso negado'; end if; return query select p.id,p.username,p.display_name,u.email,p.role,u.created_at from public.profiles p join auth.users u on u.id=p.id order by u.created_at desc; end $$;
grant execute on function public.admin_list_accounts() to authenticated;
create or replace function public.admin_set_player_title(p_user_id uuid,p_title text) returns public.profiles language plpgsql security definer set search_path=public as $$ declare p public.profiles; begin if not exists(select 1 from public.profiles a where a.id=auth.uid() and a.role='admin') then raise exception 'Acesso negado'; end if; update public.profiles set premium_title=nullif(trim(p_title),'') where id=p_user_id returning * into p; if p.id is null then raise exception 'Jogador não encontrado'; end if; return p; end $$;
grant execute on function public.admin_set_player_title(uuid,text) to authenticated;

-- 10. Índices úteis
create index if not exists coin_orders_external_ref_idx on public.coin_orders(external_reference);
