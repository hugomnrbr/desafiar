-- QuizUp v38 - Painel administrativo modular, loja reconstruída, títulos/emblemas e retomada de partida
-- Execute APÓS as migrations anteriores. É idempotente e não apaga partidas/contas.

-- ================================================================
-- 1. Corrige a compatibilidade da Loja / purchase_premium_item
-- ================================================================
alter table if exists public.premium_items add column if not exists description text;
alter table if exists public.premium_items add column if not exists price_cents bigint;
alter table if exists public.premium_items add column if not exists price_coins bigint;
alter table if exists public.premium_items add column if not exists promo_price_cents bigint;
alter table if exists public.premium_items add column if not exists promo_price_coins bigint;
alter table if exists public.premium_items add column if not exists promo_active boolean not null default false;
alter table if exists public.premium_items add column if not exists promo_expires_at timestamptz;
alter table if exists public.premium_items add column if not exists icon text;
alter table if exists public.premium_items add column if not exists asset_url text;
alter table if exists public.premium_items add column if not exists kind text;
alter table if exists public.premium_items add column if not exists active boolean not null default true;
alter table if exists public.premium_items add column if not exists created_by uuid;

update public.premium_items set price_coins=coalesce(price_coins,price_cents,0), price_cents=coalesce(price_cents,price_coins,0) where true;

-- Remove versões antigas com assinaturas diferentes. Isso evita que uma RPC antiga
-- continue sendo chamada pelo PostgREST e provoque o erro 42P10/colunas inexistentes.
do $$
declare r record;
begin
  for r in select oid::regprocedure::text as sig from pg_proc where pronamespace='public'::regnamespace and proname='purchase_premium_item' loop
    execute 'drop function if exists '||r.sig||' cascade';
  end loop;
exception when undefined_function then null;
end $$;

create or replace function public.purchase_premium_item(p_item_id text,p_expected_price bigint default null)
returns jsonb language plpgsql security definer set search_path=public as $$
declare
  it public.premium_items;
  charge bigint;
  bal bigint;
  promo_ok boolean;
begin
  if auth.uid() is null then raise exception 'Não autenticado'; end if;
  select * into it from public.premium_items where id::text=trim(p_item_id) and active=true limit 1;
  if it.id is null then raise exception 'Item não encontrado ou indisponível'; end if;
  if exists(select 1 from public.premium_store_settings where id=1 and (coalesce(enabled,false)=false or coalesce(cosmetics_enabled,false)=false)) then
    raise exception 'A loja de cosméticos está desativada';
  end if;
  promo_ok:=coalesce(it.promo_active,false)
    and coalesce(it.promo_price_coins,0)>0
    and coalesce(it.promo_price_coins,0)<coalesce(it.price_coins,0)
    and (it.promo_expires_at is null or it.promo_expires_at>now());
  charge:=case when promo_ok then it.promo_price_coins else coalesce(it.price_coins,it.price_cents,0) end;
  if charge is null or charge<0 then raise exception 'Preço do item inválido'; end if;
  if p_expected_price is not null and p_expected_price<>charge then raise exception 'O preço do item mudou. Atualize a loja e tente novamente.'; end if;
  if exists(select 1 from public.user_premium_items where user_id=auth.uid() and item_id=it.id) then
    select coins into bal from public.profiles where id=auth.uid();
    return jsonb_build_object('ok',true,'already_owned',true,'balance',coalesce(bal,0),'charge',0,'item_id',it.id);
  end if;
  update public.profiles set coins=coalesce(coins,0)-charge where id=auth.uid() and coalesce(coins,0)>=charge returning coins into bal;
  if bal is null then raise exception 'Você não possui QuizCoins suficientes'; end if;
  insert into public.user_premium_items(user_id,item_id,active,purchased_at) values(auth.uid(),it.id,true,now());
  insert into public.coin_ledger(user_id,amount,source_type,source_id,description)
    values(auth.uid(),-charge,'premium_purchase',gen_random_uuid()::text,'Compra: '||coalesce(it.name,'Item'));
  return jsonb_build_object('ok',true,'already_owned',false,'balance',bal,'charge',charge,'item_id',it.id);
end $$;
revoke all on function public.purchase_premium_item(text,bigint) from public;
grant execute on function public.purchase_premium_item(text,bigint) to authenticated;

create or replace function public.purchase_premium_item(p_item_id integer)
returns jsonb language sql security definer set search_path=public as $$
  select public.purchase_premium_item(p_item_id::text,null::bigint);
$$;
revoke all on function public.purchase_premium_item(integer) from public;
grant execute on function public.purchase_premium_item(integer) to authenticated;

-- ================================================================
-- 2. Categorias próprias da loja
-- ================================================================
create table if not exists public.store_categories(
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  description text,
  icon text not null default '🛍️',
  active boolean not null default true,
  sort_order integer not null default 0,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);
alter table public.store_categories enable row level security;
drop policy if exists "store categories read active" on public.store_categories;
create policy "store categories read active" on public.store_categories for select to authenticated using(active=true or exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin'));
drop policy if exists "store categories admin insert" on public.store_categories;
create policy "store categories admin insert" on public.store_categories for insert to authenticated with check(exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin'));
drop policy if exists "store categories admin update" on public.store_categories;
create policy "store categories admin update" on public.store_categories for update to authenticated using(exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin')) with check(exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin'));

insert into public.store_categories(name,description,icon,sort_order,created_by)
values
('Avatares','Avatares personalizados para o perfil.','🧑',1,null),
('Molduras','Bordas circulares para o avatar.','⭕',2,null),
('Efeitos','Efeitos visuais de perfil e partida.','✨',3,null),
('Títulos','Títulos visuais do jogador.','🏷️',4,null),
('Emojis','Reações e emojis especiais.','😈',5,null),
('Emblemas','Emblemas colecionáveis.','🏅',6,null),
('Temas','Temas visuais do perfil.','🎨',7,null)
on conflict(name) do nothing;

-- ================================================================
-- 3. Títulos conquistáveis
-- ================================================================
create table if not exists public.titles(
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  description text,
  icon text not null default '🏷️',
  active boolean not null default true,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);
create table if not exists public.user_titles(
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  title_id uuid not null references public.titles(id) on delete cascade,
  is_main boolean not null default false,
  acquired_at timestamptz not null default now(),
  unique(user_id,title_id)
);
alter table public.profiles add column if not exists main_title_id uuid references public.titles(id) on delete set null;
alter table public.achievements add column if not exists title_id uuid references public.titles(id) on delete set null;

alter table public.titles enable row level security;
alter table public.user_titles enable row level security;
drop policy if exists "titles read active" on public.titles;
create policy "titles read active" on public.titles for select to authenticated using(active=true or exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin'));
drop policy if exists "titles admin insert" on public.titles;
create policy "titles admin insert" on public.titles for insert to authenticated with check(exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin'));
drop policy if exists "titles admin update" on public.titles;
create policy "titles admin update" on public.titles for update to authenticated using(exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin')) with check(exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin'));
drop policy if exists "user titles own read" on public.user_titles;
create policy "user titles own read" on public.user_titles for select to authenticated using(user_id=auth.uid() or exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin'));
drop policy if exists "user titles own main update" on public.user_titles;
create policy "user titles own main update" on public.user_titles for update to authenticated using(user_id=auth.uid()) with check(user_id=auth.uid());
drop policy if exists "user titles admin insert" on public.user_titles;
create policy "user titles admin insert" on public.user_titles for insert to authenticated with check(exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin'));


create or replace function public.set_main_title(p_title_id uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
begin
  if p_title_id is not null and not exists(select 1 from public.user_titles where user_id=auth.uid() and title_id=p_title_id) then
    raise exception 'Você ainda não conquistou este título';
  end if;
  update public.user_titles set is_main=false where user_id=auth.uid();
  if p_title_id is not null then update public.user_titles set is_main=true where user_id=auth.uid() and title_id=p_title_id; end if;
  update public.profiles set main_title_id=p_title_id where id=auth.uid();
  return jsonb_build_object('ok',true,'main_title_id',p_title_id);
end $$;
revoke all on function public.set_main_title(uuid) from public;
grant execute on function public.set_main_title(uuid) to authenticated;

-- Ao desbloquear uma conquista vinculada a título, entrega o título automaticamente.
create or replace function public.quizup_notify_achievement()
returns trigger language plpgsql security definer set search_path=public as $$
declare a record;
begin
  select title,description,icon,title_id into a from public.achievements where id=new.achievement_id;
  if a.title_id is not null then
    insert into public.user_titles(user_id,title_id,is_main) values(new.user_id,a.title_id,false) on conflict do nothing;
  end if;
  insert into public.notifications(recipient_id,actor_id,type,title,body,data)
  values(new.user_id,null,'achievement',coalesce(a.icon,'🏆')||' Conquista desbloqueada',coalesce(a.description,a.title),jsonb_build_object('achievement_id',new.achievement_id,'title_id',a.title_id));
  return new;
end $$;
drop trigger if exists trg_quizup_notify_achievement on public.user_achievements;
create trigger trg_quizup_notify_achievement after insert on public.user_achievements for each row execute function public.quizup_notify_achievement();

-- ================================================================
-- 4. Emblemas administráveis
-- ================================================================
create table if not exists public.badges(
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  description text,
  icon text not null default '🏅',
  active boolean not null default true,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);
alter table public.badges enable row level security;
drop policy if exists "badges read active" on public.badges;
create policy "badges read active" on public.badges for select to authenticated using(active=true or exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin'));
drop policy if exists "badges admin insert" on public.badges;
create policy "badges admin insert" on public.badges for insert to authenticated with check(exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin'));
drop policy if exists "badges admin update" on public.badges;
create policy "badges admin update" on public.badges for update to authenticated using(exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin')) with check(exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin'));

-- ================================================================
-- 5. Padronização dos avatares
-- ================================================================
insert into storage.buckets(id,name,public) values('premium-assets','premium-assets',true) on conflict(id) do update set public=true;
drop policy if exists "premium assets upload admin" on storage.objects;
create policy "premium assets upload admin" on storage.objects for insert to authenticated with check(bucket_id='premium-assets' and exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin'));
drop policy if exists "premium assets update admin" on storage.objects;
create policy "premium assets update admin" on storage.objects for update to authenticated using(bucket_id='premium-assets' and exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin'));
drop policy if exists "premium assets delete admin" on storage.objects;
create policy "premium assets delete admin" on storage.objects for delete to authenticated using(bucket_id='premium-assets' and exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin'));

-- ================================================================
-- 6. Mercado Pago continua OFF e a loja começa apenas com cosméticos.
-- Itens antigos não são apagados; ficam desativados para a nova loja poder ser
-- cadastrada pelo administrador sem misturar o catálogo antigo.
-- ================================================================
update public.premium_store_settings set payments_enabled=false where id=1;
update public.premium_items set active=false where active=true;

-- ================================================================
-- 7. Realtime para títulos e loja
-- ================================================================
do $$
begin
  begin alter publication supabase_realtime add table public.user_titles; exception when duplicate_object then null; end;
  begin alter publication supabase_realtime add table public.titles; exception when duplicate_object then null; end;
  begin alter publication supabase_realtime add table public.store_categories; exception when duplicate_object then null; end;
exception when undefined_object then null;
end $$;

-- Todos os jogadores autenticados podem visualizar os títulos conquistados de um perfil.
drop policy if exists "user titles own read" on public.user_titles;
create policy "user titles public read" on public.user_titles for select to authenticated using(true);
