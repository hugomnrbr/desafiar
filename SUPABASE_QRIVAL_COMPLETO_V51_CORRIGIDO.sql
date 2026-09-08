-- Q-RIVAL — SQL COMPLETO V51
--
-- ARQUIVO ÚNICO PARA INSTALAÇÃO INICIAL
-- Inclui: base V42 + conquistas V46 + correções V47/V48 +
-- engajamento V49 + modos/torneios/admin V51.
--
-- Este arquivo foi montado para quem AINDA NÃO executou os SQLs
-- anteriores. Execute SOMENTE este arquivo no Supabase SQL Editor.
-- Não execute os SQL históricos depois dele.
--
-- Observação: o SQL é idempotente nas estruturas que usam IF NOT EXISTS/
-- CREATE OR REPLACE. Como não temos acesso ao seu projeto Supabase real,
-- não é possível garantir compatibilidade com alterações externas que
-- você tenha feito manualmente no banco.


-- ================================================================
-- INÍCIO: Q-RIVAL_V42_SQL_DEFINITIVO.sql
-- ================================================================

-- Q-Rival v42 — SQL DEFINITIVO
-- Execute este arquivo inteiro no Supabase SQL Editor.
-- Ele reúne a base da Loja/Premium (v40), correções finais da v41.13
-- e a camada comercial sem anúncios da v42.

-- ============================================================================
-- QuizUp v40.3 FINAL — limpeza de cosméticos antigos + reações de partida
-- Execute ESTE ÚNICO arquivo no Supabase SQL Editor.
-- Não apaga contas, partidas, amizades, notícias ou histórico.
-- ============================================================================

begin;

-- Função-base usada pelas políticas do painel.
create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path=public
as $$
  select exists(select 1 from public.profiles where id=auth.uid() and role='admin');
$$;
revoke all on function public.is_admin() from public;
grant execute on function public.is_admin() to authenticated;

-- Campos e estrutura de títulos.
alter table if exists public.profiles add column if not exists main_title_id uuid;
alter table if exists public.titles add column if not exists asset_width integer;
alter table if exists public.titles add column if not exists asset_height integer;
alter table if exists public.titles add column if not exists title_color text default '#ffd21a';
alter table if exists public.titles add column if not exists title_font text default 'Inter';
alter table if exists public.titles add column if not exists title_font_url text;
alter table if exists public.titles add column if not exists title_font_asset_url text;

create table if not exists public.user_titles(
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  title_id uuid not null references public.titles(id) on delete cascade,
  is_main boolean not null default false,
  acquired_at timestamptz not null default now(),
  unique(user_id,title_id)
);
alter table public.user_titles enable row level security;
drop policy if exists "user titles own read" on public.user_titles;
create policy "user titles own read" on public.user_titles for select to authenticated using(user_id=auth.uid() or public.is_admin());
drop policy if exists "user titles own main update" on public.user_titles;
create policy "user titles own main update" on public.user_titles for update to authenticated using(user_id=auth.uid()) with check(user_id=auth.uid());
drop policy if exists "user titles admin insert" on public.user_titles;
create policy "user titles admin insert" on public.user_titles for insert to authenticated with check(public.is_admin());

-- --------------------------------------------------------------------------
-- 1) Campos necessários para o novo catálogo administrável
-- --------------------------------------------------------------------------
alter table if exists public.profiles add column if not exists premium_avatar text;
alter table if exists public.profiles add column if not exists premium_frame text;
alter table if exists public.profiles add column if not exists premium_effect text;
alter table if exists public.profiles add column if not exists premium_theme text;
alter table if exists public.profiles add column if not exists premium_background text;
alter table if exists public.profiles add column if not exists premium_title text;
alter table if exists public.profiles add column if not exists premium_badge text;
alter table if exists public.profiles add column if not exists main_title_id uuid;

alter table if exists public.premium_items add column if not exists description text;
alter table if exists public.premium_items add column if not exists price_cents bigint;
alter table if exists public.premium_items add column if not exists price_coins bigint;
alter table if exists public.premium_items add column if not exists promo_price_cents bigint;
alter table if exists public.premium_items add column if not exists promo_price_coins bigint;
alter table if exists public.premium_items add column if not exists promo_active boolean not null default false;
alter table if exists public.premium_items add column if not exists promo_expires_at timestamptz;
alter table if exists public.premium_items add column if not exists icon text;
alter table if exists public.premium_items add column if not exists asset_url text;
alter table if exists public.premium_items add column if not exists asset_type text;
alter table if exists public.premium_items add column if not exists kind text;
alter table if exists public.premium_items add column if not exists effect_style text;
alter table if exists public.premium_items add column if not exists title_color text;
alter table if exists public.premium_items add column if not exists title_font text;
alter table if exists public.premium_items add column if not exists title_font_url text;
alter table if exists public.premium_items add column if not exists title_font_asset_url text;
alter table if exists public.premium_items add column if not exists source_type text;
alter table if exists public.premium_items add column if not exists source_id text;
alter table if exists public.premium_items add column if not exists asset_width integer;
alter table if exists public.premium_items add column if not exists asset_height integer;
alter table if exists public.premium_items add column if not exists frame_inset_percent numeric(5,2);
alter table if exists public.premium_items add column if not exists frame_version text;
alter table if exists public.premium_items add column if not exists active boolean not null default true;
alter table if exists public.premium_items add column if not exists created_by uuid;

update public.premium_items
set price_coins=coalesce(price_coins,price_cents,0),
    price_cents=coalesce(price_cents,price_coins,0),
    effect_style=coalesce(nullif(effect_style,''),'none'),
    title_color=coalesce(nullif(title_color,''),'#ffd21a'),
    title_font=coalesce(nullif(title_font,''),'Inter')
where true;

-- --------------------------------------------------------------------------
-- 2) Categorias oficiais da loja
-- --------------------------------------------------------------------------
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

insert into public.store_categories(name,description,icon,sort_order,active)
values
 ('Avatares','Avatares oficiais do jogador.','👤',1,true),
 ('Molduras','Molduras circulares para o avatar.','⭕',2,true),
 ('Títulos','Títulos visuais do jogador.','🏷️',3,true),
 ('Fundos de Perfil','Fundos do perfil do jogador.','🖼️',4,true),
 ('Emojis','Emojis e reações especiais.','😊',5,true),
 ('Efeitos','Efeitos visuais do perfil e da partida.','✨',6,true)
on conflict(name) do update set description=excluded.description,icon=excluded.icon,sort_order=excluded.sort_order,active=true;

alter table public.store_categories enable row level security;
drop policy if exists "store categories read active" on public.store_categories;
create policy "store categories read active" on public.store_categories for select to authenticated using(active=true or public.is_admin());
drop policy if exists "store categories admin insert" on public.store_categories;
create policy "store categories admin insert" on public.store_categories for insert to authenticated with check(public.is_admin());
drop policy if exists "store categories admin update" on public.store_categories;
create policy "store categories admin update" on public.store_categories for update to authenticated using(public.is_admin()) with check(public.is_admin());

-- O nome antigo "Emblemas" deixa de aparecer como categoria da loja.
update public.store_categories set active=false where name='Emblemas';

-- Converte os anéis que já existiam como "Emblemas" para o novo conceito de Moldura.
update public.premium_items
set category='Molduras',kind='frame',source_type='frame',
    asset_width=coalesce(asset_width,256),asset_height=coalesce(asset_height,256),
    frame_version=coalesce(frame_version,'static-v3')
where category='Emblemas'
  and (asset_url ilike '%assets/store/emblems/%' or name in ('Emblema de Fogo','Emblema de Água','Emblema Galáxia'));

update public.premium_items set active=false where category='Emblemas';

-- --------------------------------------------------------------------------
-- 3) As seis molduras da referência — 256 x 256
-- --------------------------------------------------------------------------
insert into public.premium_items(
  id,name,category,description,price_cents,price_coins,
  promo_price_cents,promo_price_coins,promo_active,promo_expires_at,
  icon,effect_style,asset_url,asset_type,kind,source_type,source_id,
  asset_width,asset_height,frame_inset_percent,frame_version,active
)
values
 ('frame-fire','Fogo','Molduras','Moldura Fogo estática — 256 × 256 px, PNG transparente.',500,500,null,null,false,null,'🔥','fire','assets/store/frames/fire.png','image/png','frame','frame','frame-fire',256,256,0,'static-v3',true),
 ('frame-water','Água','Molduras','Moldura Água estática — 256 × 256 px, PNG transparente.',500,500,null,null,false,null,'💧','water','assets/store/frames/water.png','image/png','frame','frame','frame-water',256,256,0,'static-v3',true),
 ('frame-earth','Terra','Molduras','Moldura Terra estática — 256 × 256 px, PNG transparente.',500,500,null,null,false,null,'🌿','earth','assets/store/frames/earth.png','image/png','frame','frame','frame-earth',256,256,0,'static-v3',true),
 ('frame-air','Ar','Molduras','Moldura Ar estática — 256 × 256 px, PNG transparente.',500,500,null,null,false,null,'🌪️','air','assets/store/frames/air.png','image/png','frame','frame','frame-air',256,256,0,'static-v3',true),
 ('frame-darkness','Trevas','Molduras','Moldura Trevas estática — 256 × 256 px, PNG transparente.',500,500,null,null,false,null,'🌑','darkness','assets/store/frames/darkness.png','image/png','frame','frame','frame-darkness',256,256,0,'static-v3',true),
 ('frame-light','Luz','Molduras','Moldura Luz estática — 256 × 256 px, PNG transparente.',500,500,null,null,false,null,'✨','light','assets/store/frames/light.png','image/png','frame','frame','frame-light',256,256,0,'static-v3',true)
on conflict(id) do update set
 name=excluded.name,category=excluded.category,description=excluded.description,
 price_cents=excluded.price_cents,price_coins=excluded.price_coins,
 icon=excluded.icon,effect_style=excluded.effect_style,asset_url=excluded.asset_url,
 asset_type=excluded.asset_type,kind='frame',source_type='frame',source_id=excluded.source_id,
 asset_width=256,asset_height=256,frame_inset_percent=0,frame_version='static-v3',active=true;

-- Garantia: as seis molduras oficiais são sempre estáticas e sem GIF.
update public.premium_items
set asset_type='image/png',asset_width=256,asset_height=256,frame_inset_percent=0,frame_version='static-v3'
where id in ('frame-fire','frame-water','frame-earth','frame-air','frame-darkness','frame-light');

-- Se existirem cópias antigas com os mesmos nomes, os seis oficiais são os únicos vendidos.
update public.premium_items
set active=false
where category='Molduras'
  and name in ('Fogo','Água','Terra','Ar','Trevas','Luz')
  and id not in ('frame-fire','frame-water','frame-earth','frame-air','frame-darkness','frame-light');

-- --------------------------------------------------------------------------
-- 4) Resoluções oficiais do catálogo
-- --------------------------------------------------------------------------
-- Avatar: 256 x 256
update public.premium_items set asset_width=256,asset_height=256
where kind='avatar' and asset_url is not null;
-- Moldura: 256 x 256
update public.premium_items set asset_width=256,asset_height=256,frame_version=coalesce(frame_version,'static-v3')
where kind='frame' and asset_url is not null;
-- Título: 600 x 160
update public.titles set asset_width=600,asset_height=160 where asset_url is not null;
update public.premium_items pi set asset_width=600,asset_height=160
where pi.kind='title' and pi.asset_url is not null;
-- Fundo de perfil: 800 x 500
update public.premium_items set asset_width=800,asset_height=500
where kind='background' and asset_url is not null;
-- Emoji: 128 x 128
update public.premium_items set asset_width=128,asset_height=128
where kind='emoji' and asset_url is not null;
-- Emblemas legados: 128 x 128
update public.premium_items set asset_width=128,asset_height=128
where kind='badge' and asset_url is not null;

-- Títulos precisam ser visíveis no painel mesmo quando a consulta de perguntas falhar.
alter table public.titles enable row level security;
drop policy if exists "titles authenticated read" on public.titles;
create policy "titles authenticated read" on public.titles
for select to authenticated using(true);
drop policy if exists "titles admin manage" on public.titles;
create policy "titles admin manage" on public.titles
for all to authenticated using(public.is_admin()) with check(public.is_admin());

-- Emblemas legados também podem ser administrados sem depender da tela de perguntas.
alter table public.badges enable row level security;
drop policy if exists "badges authenticated read" on public.badges;
create policy "badges authenticated read" on public.badges
for select to authenticated using(true);
drop policy if exists "badges admin manage" on public.badges;
create policy "badges admin manage" on public.badges
for all to authenticated using(public.is_admin()) with check(public.is_admin());

-- --------------------------------------------------------------------------
-- 5) RLS e Storage para o painel poder cadastrar artes
-- --------------------------------------------------------------------------
alter table public.premium_items enable row level security;
drop policy if exists "premium items authenticated read" on public.premium_items;
create policy "premium items authenticated read" on public.premium_items
for select to authenticated using(true);
drop policy if exists "premium items admin manage" on public.premium_items;
create policy "premium items admin manage" on public.premium_items
for all to authenticated using(public.is_admin()) with check(public.is_admin());

insert into storage.buckets(id,name,public)
values ('premium-assets','premium-assets',true),('admin-assets','admin-assets',true)
on conflict(id) do update set public=true;

drop policy if exists "quizup premium assets public read" on storage.objects;
create policy "quizup premium assets public read" on storage.objects
for select to public using(bucket_id='premium-assets');
drop policy if exists "quizup premium assets admin insert" on storage.objects;
create policy "quizup premium assets admin insert" on storage.objects
for insert to authenticated with check(bucket_id='premium-assets' and public.is_admin());
drop policy if exists "quizup premium assets admin update" on storage.objects;
create policy "quizup premium assets admin update" on storage.objects
for update to authenticated using(bucket_id='premium-assets' and public.is_admin()) with check(bucket_id='premium-assets' and public.is_admin());
drop policy if exists "quizup premium assets admin delete" on storage.objects;
create policy "quizup premium assets admin delete" on storage.objects
for delete to authenticated using(bucket_id='premium-assets' and public.is_admin());

drop policy if exists "quizup admin assets public read" on storage.objects;
create policy "quizup admin assets public read" on storage.objects
for select to public using(bucket_id='admin-assets');
drop policy if exists "quizup admin assets admin insert" on storage.objects;
create policy "quizup admin assets admin insert" on storage.objects
for insert to authenticated with check(bucket_id='admin-assets' and public.is_admin());
drop policy if exists "quizup admin assets admin update" on storage.objects;
create policy "quizup admin assets admin update" on storage.objects
for update to authenticated using(bucket_id='admin-assets' and public.is_admin()) with check(bucket_id='admin-assets' and public.is_admin());
drop policy if exists "quizup admin assets admin delete" on storage.objects;
create policy "quizup admin assets admin delete" on storage.objects
for delete to authenticated using(bucket_id='admin-assets' and public.is_admin());

-- --------------------------------------------------------------------------
-- 6) Compra segura: uma única RPC, preço verificado no servidor
-- --------------------------------------------------------------------------
drop function if exists public.purchase_premium_item(text,bigint);
drop function if exists public.purchase_premium_item(integer);

create function public.purchase_premium_item(p_item_id text,p_expected_price bigint default null)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  it public.premium_items;
  charge bigint;
  bal bigint;
  promo_ok boolean;
  already boolean;
  cosmetics_on boolean:=true;
  category_on boolean:=true;
begin
  if auth.uid() is null then raise exception 'Não autenticado'; end if;

  select * into it from public.premium_items
  where id::text=trim(p_item_id) and active=true
  limit 1;
  if it.id is null then raise exception 'Item não encontrado ou indisponível'; end if;

  select coalesce(enabled,true) and coalesce(cosmetics_enabled,true)
    into cosmetics_on
  from public.premium_store_settings where id=1;
  if cosmetics_on=false then raise exception 'A loja de cosméticos está desativada'; end if;

  if it.category='VIP' then category_on:=coalesce((select vip_enabled from public.premium_store_settings where id=1),true);
  elsif it.category='Moedas' then category_on:=coalesce((select coins_enabled and payments_enabled from public.premium_store_settings where id=1),false);
  elsif it.category='Passe' then category_on:=coalesce((select pass_enabled from public.premium_store_settings where id=1),true);
  else category_on:=coalesce((select cosmetics_enabled from public.premium_store_settings where id=1),true);
  end if;
  if category_on=false then raise exception 'As compras desta categoria estão desativadas'; end if;

  promo_ok:=coalesce(it.promo_active,false)
    and coalesce(it.promo_price_coins,0)>0
    and coalesce(it.promo_price_coins,0)<coalesce(it.price_coins,0)
    and (it.promo_expires_at is null or it.promo_expires_at>now());
  charge:=case when promo_ok then it.promo_price_coins else coalesce(it.price_coins,it.price_cents,0) end;
  if charge is null or charge<0 then raise exception 'Preço do item inválido'; end if;
  if p_expected_price is not null and p_expected_price<>charge then raise exception 'O preço do item mudou. Atualize a loja e tente novamente.'; end if;

  select exists(select 1 from public.user_premium_items where user_id=auth.uid() and item_id=it.id) into already;
  if not already then
    update public.profiles
       set coins=coalesce(coins,0)-charge
     where id=auth.uid() and coalesce(coins,0)>=charge
     returning coins into bal;
    if bal is null then raise exception 'Você não possui QuizCoins suficientes'; end if;

    insert into public.user_premium_items(user_id,item_id,active,purchased_at)
    values(auth.uid(),it.id,false,now());

    insert into public.coin_ledger(user_id,amount,source_type,source_id,description)
    values(auth.uid(),-charge,'premium_purchase',gen_random_uuid()::text,'Compra: '||coalesce(it.name,'Item'));
  else
    select coins into bal from public.profiles where id=auth.uid();
  end if;

  return jsonb_build_object('ok',true,'already_owned',already,'balance',coalesce(bal,0),'charge',case when already then 0 else charge end,'item_id',it.id,'kind',it.kind,'source_type',it.source_type,'source_id',it.source_id);
exception when unique_violation then
  select coins into bal from public.profiles where id=auth.uid();
  return jsonb_build_object('ok',true,'already_owned',true,'balance',coalesce(bal,0),'charge',0,'item_id',it.id,'kind',it.kind);
end $$;
revoke all on function public.purchase_premium_item(text,bigint) from public;
grant execute on function public.purchase_premium_item(text,bigint) to authenticated;

-- --------------------------------------------------------------------------
-- 7) Ativação segura: só ativa itens realmente comprados
-- --------------------------------------------------------------------------
drop function if exists public.activate_premium_item(text);
drop function if exists public.activate_premium_item(integer);

create function public.activate_premium_item(p_item_id text)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  it public.premium_items;
  bal bigint;
  title_uuid uuid;
  is_admin boolean:=false;
begin
  if auth.uid() is null then raise exception 'Não autenticado'; end if;
  select exists(select 1 from public.profiles where id=auth.uid() and role='admin') into is_admin;

  select * into it from public.premium_items where id::text=trim(p_item_id) limit 1;
  if it.id is null then raise exception 'Item não encontrado'; end if;
  if not exists(select 1 from public.user_premium_items where user_id=auth.uid() and item_id=it.id) then raise exception 'Você ainda não possui este item'; end if;

  -- Emojis são colecionáveis; não ocupam um slot único.
  if it.kind='emoji' then
    select coins into bal from public.profiles where id=auth.uid();
    return jsonb_build_object('ok',true,'item_id',it.id,'kind','emoji','balance',coalesce(bal,0));
  end if;

  -- Administrador mantém o título de sistema "Administrador".
  if it.kind='title' and is_admin then
    update public.user_premium_items set active=false where user_id=auth.uid() and item_id=it.id;
    select coins into bal from public.profiles where id=auth.uid();
    return jsonb_build_object('ok',true,'item_id',it.id,'kind','title','system_title','Administrador','balance',coalesce(bal,0));
  end if;

  update public.user_premium_items up set active=false
  where up.user_id=auth.uid()
    and exists(select 1 from public.premium_items x where x.id=up.item_id and x.kind=it.kind);
  update public.user_premium_items set active=true where user_id=auth.uid() and item_id=it.id;

  if it.kind='frame' then
    update public.profiles set premium_frame=it.id::text where id=auth.uid();
  elsif it.kind='avatar' then
    update public.profiles set premium_avatar=it.id::text where id=auth.uid();
  elsif it.kind='effect' then
    update public.profiles set premium_effect=it.id::text where id=auth.uid();
  elsif it.kind='theme' then
    update public.profiles set premium_theme=it.id::text where id=auth.uid();
  elsif it.kind='background' then
    update public.profiles set premium_background=it.id::text where id=auth.uid();
  elsif it.kind='badge' then
    update public.profiles set premium_badge=it.id::text where id=auth.uid();
  elsif it.kind='title' then
    if coalesce(it.source_type,'')='title' and coalesce(it.source_id,'')<>'' then
      begin title_uuid:=it.source_id::uuid; exception when others then title_uuid:=null; end;
    end if;
    if title_uuid is null then
      select id into title_uuid from public.titles where lower(trim(name))=lower(trim(it.name)) and active=true limit 1;
    end if;
    if title_uuid is not null then
      update public.user_titles set is_main=false where user_id=auth.uid();
      insert into public.user_titles(user_id,title_id,is_main)
      values(auth.uid(),title_uuid,true)
      on conflict(user_id,title_id) do update set is_main=true;
      update public.profiles set main_title_id=title_uuid,premium_title=it.id::text where id=auth.uid();
    else
      update public.profiles set premium_title=it.id::text where id=auth.uid();
    end if;
  elsif it.kind='vip' then
    update public.profiles set premium_vip=true where id=auth.uid();
  end if;

  select coins into bal from public.profiles where id=auth.uid();
  return jsonb_build_object('ok',true,'item_id',it.id,'kind',it.kind,'balance',coalesce(bal,0));
end $$;
revoke all on function public.activate_premium_item(text) from public;
grant execute on function public.activate_premium_item(text) to authenticated;

-- --------------------------------------------------------------------------
-- 8) Título principal: somente um por jogador; admin usa título do sistema
-- --------------------------------------------------------------------------
do $$
begin
  if to_regclass('public.user_titles') is not null then
    create unique index if not exists user_titles_one_main_per_user on public.user_titles(user_id) where is_main=true;
  end if;
end $$;

create or replace function public.set_main_title(p_title_id uuid)
returns jsonb language plpgsql security definer set search_path=public
as $$
begin
  if auth.uid() is null then raise exception 'Não autenticado'; end if;
  if exists(select 1 from public.profiles where id=auth.uid() and role='admin') then
    update public.user_titles set is_main=false where user_id=auth.uid();
    update public.profiles set main_title_id=null where id=auth.uid();
    return jsonb_build_object('ok',true,'main_title_id',null,'system_title','Administrador');
  end if;
  if p_title_id is not null and not exists(select 1 from public.user_titles where user_id=auth.uid() and title_id=p_title_id) then
    raise exception 'Você ainda não conquistou este título';
  end if;
  update public.user_titles set is_main=false where user_id=auth.uid();
  if p_title_id is not null then update public.user_titles set is_main=true where user_id=auth.uid() and title_id=p_title_id; end if;
  update public.profiles set main_title_id=p_title_id,premium_title=null where id=auth.uid();
  return jsonb_build_object('ok',true,'main_title_id',p_title_id);
end $$;
revoke all on function public.set_main_title(uuid) from public;
grant execute on function public.set_main_title(uuid) to authenticated;

-- --------------------------------------------------------------------------
-- 9) Remoção administrativa: tira da loja, inventário e perfil
-- --------------------------------------------------------------------------
drop function if exists public.admin_remove_premium_item(text,text,text);
drop function if exists public.admin_remove_premium_item(text);

create function public.admin_remove_premium_item(p_item_id text,p_source_type text default null,p_source_id text default null)
returns jsonb language plpgsql security definer set search_path=public
as $$
declare
  it public.premium_items;
  source_uuid uuid;
  removed_count bigint:=0;
begin
  if not public.is_admin() then raise exception 'Acesso negado'; end if;
  select * into it from public.premium_items where id::text=trim(p_item_id) limit 1;
  if it.id is null and coalesce(p_source_type,'')<>'' then
    select * into it from public.premium_items where source_type=p_source_type and source_id=p_source_id limit 1;
  end if;
  if it.id is null then raise exception 'Item não encontrado'; end if;

  delete from public.user_premium_items where item_id=it.id;
  get diagnostics removed_count=row_count;

  if it.kind='avatar' then update public.profiles set premium_avatar=null where premium_avatar=it.id::text;
  elsif it.kind='frame' then update public.profiles set premium_frame=null where premium_frame=it.id::text;
  elsif it.kind='background' then update public.profiles set premium_background=null where premium_background=it.id::text;
  elsif it.kind='effect' then update public.profiles set premium_effect=null where premium_effect=it.id::text;
  elsif it.kind='theme' then update public.profiles set premium_theme=null where premium_theme=it.id::text;
  elsif it.kind='badge' then update public.profiles set premium_badge=null where premium_badge=it.id::text;
  elsif it.kind='title' then update public.profiles set premium_title=null where premium_title=it.id::text;
  end if;

  if coalesce(it.source_type,'')='title' and coalesce(it.source_id,'')<>'' then
    begin
      source_uuid:=it.source_id::uuid;
      delete from public.user_titles where title_id=source_uuid;
      update public.profiles set main_title_id=null where main_title_id=source_uuid;
      update public.titles set active=false where id=source_uuid;
    exception when others then null; end;
  end if;

  update public.premium_items set active=false where id=it.id;
  return jsonb_build_object('ok',true,'item_id',it.id,'removed_from_inventory',removed_count);
end $$;
revoke all on function public.admin_remove_premium_item(text,text,text) from public;
grant execute on function public.admin_remove_premium_item(text,text,text) to authenticated;

-- --------------------------------------------------------------------------
-- 9.1) Exclusão administrativa de títulos e emblemas
-- --------------------------------------------------------------------------
drop function if exists public.admin_delete_title(uuid);
create function public.admin_delete_title(p_title_id uuid)
returns jsonb language plpgsql security definer set search_path=public
as $$
begin
  if not public.is_admin() then raise exception 'Acesso negado'; end if;
  delete from public.user_titles where title_id=p_title_id;
  update public.profiles set main_title_id=null where main_title_id=p_title_id;
  update public.profiles set premium_title=null where premium_title in (
    select id::text from public.premium_items where source_type='title' and source_id=p_title_id::text
  );
  update public.premium_items set active=false where source_type='title' and source_id=p_title_id::text;
  delete from public.titles where id=p_title_id;
  return jsonb_build_object('ok',true,'title_id',p_title_id);
end $$;
revoke all on function public.admin_delete_title(uuid) from public;
grant execute on function public.admin_delete_title(uuid) to authenticated;

drop function if exists public.admin_delete_badge(uuid);
create function public.admin_delete_badge(p_badge_id uuid)
returns jsonb language plpgsql security definer set search_path=public
as $$
declare sale_id text;
begin
  if not public.is_admin() then raise exception 'Acesso negado'; end if;
  select id into sale_id from public.premium_items where source_type='badge' and source_id=p_badge_id::text limit 1;
  if sale_id is not null then
    delete from public.user_premium_items where item_id=sale_id;
    update public.profiles set premium_badge=null where premium_badge=sale_id;
    update public.premium_items set active=false where id=sale_id;
  end if;
  delete from public.badges where id=p_badge_id;
  return jsonb_build_object('ok',true,'badge_id',p_badge_id);
end $$;
revoke all on function public.admin_delete_badge(uuid) from public;
grant execute on function public.admin_delete_badge(uuid) to authenticated;

-- --------------------------------------------------------------------------
-- 10) Loja e pagamentos: Mercado Pago continua DESATIVADO
-- --------------------------------------------------------------------------
update public.premium_store_settings
set payments_enabled=false
where id=1;

-- --------------------------------------------------------------------------
-- 11) Índices para carregamento do catálogo/inventário
-- --------------------------------------------------------------------------
create index if not exists premium_items_category_active_idx on public.premium_items(category,active);
create index if not exists premium_items_kind_active_idx on public.premium_items(kind,active);
create index if not exists user_premium_items_user_active_idx on public.user_premium_items(user_id,active);


-- --------------------------------------------------------------------------
-- 12) LIMPEZA SEGURA DE PRODUTOS COSMÉTICOS ANTIGOS/QUEBRADOS
-- --------------------------------------------------------------------------
-- Esta limpeza não usa tabela temporária.
--
-- Remove somente itens explicitamente pertencentes ao catálogo antigo de
-- Emblemas ou cosméticos sem arte utilizável. Itens funcionais com arte
-- válida permanecem disponíveis.

-- Primeiro remove a posse dos itens antigos/quebrados.
delete from public.user_premium_items up
where exists (
  select 1
  from public.premium_items pi
  where pi.id=up.item_id
    and (
      pi.category in ('Emblemas','Emblem')
      or pi.asset_url ilike '%/assets/store/emblems/%'
      or pi.asset_url ilike '%/assets/emblems/%'
      or (pi.kind in ('avatar','frame','title','background','emoji','badge')
          and coalesce(trim(pi.asset_url),'')='')
    )
);

-- Limpa referências de perfil para os itens que serão removidos.
update public.profiles p
set premium_avatar=case when exists (select 1 from public.premium_items pi where pi.id::text=p.premium_avatar and (pi.category in ('Emblemas','Emblem') or pi.asset_url ilike '%/assets/store/emblems/%' or pi.asset_url ilike '%/assets/emblems/%' or (pi.kind in ('avatar','frame','title','background','emoji','badge') and coalesce(trim(pi.asset_url),'')=''))) then null else p.premium_avatar end,
    premium_frame=case when exists (select 1 from public.premium_items pi where pi.id::text=p.premium_frame and (pi.category in ('Emblemas','Emblem') or pi.asset_url ilike '%/assets/store/emblems/%' or pi.asset_url ilike '%/assets/emblems/%' or (pi.kind in ('avatar','frame','title','background','emoji','badge') and coalesce(trim(pi.asset_url),'')=''))) then null else p.premium_frame end,
    premium_effect=case when exists (select 1 from public.premium_items pi where pi.id::text=p.premium_effect and (pi.category in ('Emblemas','Emblem') or pi.asset_url ilike '%/assets/store/emblems/%' or pi.asset_url ilike '%/assets/emblems/%' or (pi.kind in ('avatar','frame','title','background','emoji','badge') and coalesce(trim(pi.asset_url),'')=''))) then null else p.premium_effect end,
    premium_theme=case when exists (select 1 from public.premium_items pi where pi.id::text=p.premium_theme and (pi.category in ('Emblemas','Emblem') or pi.asset_url ilike '%/assets/store/emblems/%' or pi.asset_url ilike '%/assets/emblems/%' or (pi.kind in ('avatar','frame','title','background','emoji','badge') and coalesce(trim(pi.asset_url),'')=''))) then null else p.premium_theme end,
    premium_background=case when exists (select 1 from public.premium_items pi where pi.id::text=p.premium_background and (pi.category in ('Emblemas','Emblem') or pi.asset_url ilike '%/assets/store/emblems/%' or pi.asset_url ilike '%/assets/emblems/%' or (pi.kind in ('avatar','frame','title','background','emoji','badge') and coalesce(trim(pi.asset_url),'')=''))) then null else p.premium_background end,
    premium_title=case when exists (select 1 from public.premium_items pi where pi.id::text=p.premium_title and (pi.category in ('Emblemas','Emblem') or pi.asset_url ilike '%/assets/store/emblems/%' or pi.asset_url ilike '%/assets/emblems/%' or (pi.kind in ('avatar','frame','title','background','emoji','badge') and coalesce(trim(pi.asset_url),'')=''))) then null else p.premium_title end,
    premium_badge=case when exists (select 1 from public.premium_items pi where pi.id::text=p.premium_badge and (pi.category in ('Emblemas','Emblem') or pi.asset_url ilike '%/assets/store/emblems/%' or pi.asset_url ilike '%/assets/emblems/%' or (pi.kind in ('avatar','frame','title','background','emoji','badge') and coalesce(trim(pi.asset_url),'')=''))) then null else p.premium_badge end
where
  exists (select 1 from public.premium_items pi where pi.id::text=p.premium_avatar and (pi.category in ('Emblemas','Emblem') or pi.asset_url ilike '%/assets/store/emblems/%' or pi.asset_url ilike '%/assets/emblems/%' or (pi.kind in ('avatar','frame','title','background','emoji','badge') and coalesce(trim(pi.asset_url),'')='')))
  or exists (select 1 from public.premium_items pi where pi.id::text=p.premium_frame and (pi.category in ('Emblemas','Emblem') or pi.asset_url ilike '%/assets/store/emblems/%' or pi.asset_url ilike '%/assets/emblems/%' or (pi.kind in ('avatar','frame','title','background','emoji','badge') and coalesce(trim(pi.asset_url),'')='')))
  or exists (select 1 from public.premium_items pi where pi.id::text=p.premium_effect and (pi.category in ('Emblemas','Emblem') or pi.asset_url ilike '%/assets/store/emblems/%' or pi.asset_url ilike '%/assets/emblems/%' or (pi.kind in ('avatar','frame','title','background','emoji','badge') and coalesce(trim(pi.asset_url),'')='')))
  or exists (select 1 from public.premium_items pi where pi.id::text=p.premium_theme and (pi.category in ('Emblemas','Emblem') or pi.asset_url ilike '%/assets/store/emblems/%' or pi.asset_url ilike '%/assets/emblems/%' or (pi.kind in ('avatar','frame','title','background','emoji','badge') and coalesce(trim(pi.asset_url),'')='')))
  or exists (select 1 from public.premium_items pi where pi.id::text=p.premium_background and (pi.category in ('Emblemas','Emblem') or pi.asset_url ilike '%/assets/store/emblems/%' or pi.asset_url ilike '%/assets/emblems/%' or (pi.kind in ('avatar','frame','title','background','emoji','badge') and coalesce(trim(pi.asset_url),'')='')))
  or exists (select 1 from public.premium_items pi where pi.id::text=p.premium_title and (pi.category in ('Emblemas','Emblem') or pi.asset_url ilike '%/assets/store/emblems/%' or pi.asset_url ilike '%/assets/emblems/%' or (pi.kind in ('avatar','frame','title','background','emoji','badge') and coalesce(trim(pi.asset_url),'')='')))
  or exists (select 1 from public.premium_items pi where pi.id::text=p.premium_badge and (pi.category in ('Emblemas','Emblem') or pi.asset_url ilike '%/assets/store/emblems/%' or pi.asset_url ilike '%/assets/emblems/%' or (pi.kind in ('avatar','frame','title','background','emoji','badge') and coalesce(trim(pi.asset_url),'')='')));

-- Remove todas as molduras antigas e com efeitos.
-- Permanecem SOMENTE as seis molduras estáticas oficiais da referência.
delete from public.user_premium_items up
where exists (
  select 1 from public.premium_items pi
  where pi.id=up.item_id
    and pi.kind='frame'
    and pi.id not in ('frame-fire','frame-water','frame-earth','frame-air','frame-darkness','frame-light')
);

update public.profiles p
set premium_frame=null
where p.premium_frame is not null
  and p.premium_frame::text not in ('frame-fire','frame-water','frame-earth','frame-air','frame-darkness','frame-light');

delete from public.premium_items pi
where pi.kind='frame'
  and pi.id not in ('frame-fire','frame-water','frame-earth','frame-air','frame-darkness','frame-light');

-- As molduras oficiais não possuem efeito de execução.
update public.premium_items
set effect_style='none', asset_type='image/png', asset_width=256, asset_height=256, frame_version='static-v3'
where id in ('frame-fire','frame-water','frame-earth','frame-air','frame-darkness','frame-light');

-- Finalmente exclui do catálogo somente os itens antigos/quebrados.
delete from public.premium_items pi
where
  pi.category in ('Emblemas','Emblem')
  or pi.asset_url ilike '%/assets/store/emblems/%'
  or pi.asset_url ilike '%/assets/emblems/%'
  or (pi.kind in ('avatar','frame','title','background','emoji','badge')
      and coalesce(trim(pi.asset_url),'')='');

-- --------------------------------------------------------------------------
-- 13) REAÇÕES/EMOJIS DURANTE A PARTIDA
-- --------------------------------------------------------------------------
-- Garante que o recurso exista mesmo em bancos onde a tabela não foi criada
-- por uma migration anterior.
create table if not exists public.match_reactions(
  id uuid primary key default gen_random_uuid(),
  match_id uuid not null,
  sender_id uuid not null references public.profiles(id) on delete cascade,
  emoji text not null check (char_length(emoji) between 1 and 120),
  created_at timestamptz not null default now()
);

create index if not exists match_reactions_match_created_idx
  on public.match_reactions(match_id,created_at desc);
create index if not exists match_reactions_sender_idx
  on public.match_reactions(sender_id);

alter table public.match_reactions enable row level security;
drop policy if exists "match reactions read authenticated" on public.match_reactions;
create policy "match reactions read authenticated"
  on public.match_reactions for select to authenticated
  using (true);

drop policy if exists "match reactions insert own" on public.match_reactions;
create policy "match reactions insert own"
  on public.match_reactions for insert to authenticated
  with check (sender_id=auth.uid());

drop policy if exists "match reactions delete own" on public.match_reactions;
create policy "match reactions delete own"
  on public.match_reactions for delete to authenticated
  using (sender_id=auth.uid());

-- Habilita realtime sem gerar erro se a tabela já estiver publicada.
do $$
begin
  if exists(select 1 from pg_publication where pubname='supabase_realtime')
     and not exists(
       select 1 from pg_publication_tables
       where pubname='supabase_realtime'
         and schemaname='public'
         and tablename='match_reactions'
     ) then
    execute 'alter publication supabase_realtime add table public.match_reactions';
  end if;
exception when others then
  -- A tabela continua funcional mesmo que o projeto não permita alterar a publicação.
  null;
end $$;

commit;



-- ================================================================
-- V41.13 FINAL PATCH
-- ================================================================
-- QuizUp v41.13 - patch final
-- Execute no Supabase SQL Editor.
-- Inclui: reações da partida + cooldown server-side + criação/revisão de quizzes.

begin;

-- ============================================================
-- 1) REAÇÕES DURANTE A PARTIDA
-- ============================================================
create table if not exists public.match_reactions(
  id uuid primary key default gen_random_uuid(),
  match_id uuid not null references public.matches(id) on delete cascade,
  sender_id uuid not null references public.profiles(id) on delete cascade,
  emoji text not null check(char_length(emoji) between 1 and 120),
  created_at timestamptz not null default now()
);
create index if not exists match_reactions_match_created_idx on public.match_reactions(match_id,created_at desc);
create index if not exists match_reactions_sender_created_idx on public.match_reactions(sender_id,created_at desc);

alter table public.match_reactions enable row level security;
drop policy if exists "match reactions read authenticated" on public.match_reactions;
create policy "match reactions read authenticated" on public.match_reactions
for select to authenticated using (true);
drop policy if exists "match reactions insert own" on public.match_reactions;
create policy "match reactions insert own" on public.match_reactions
for insert to authenticated with check (sender_id=auth.uid());
drop policy if exists "match reactions delete own" on public.match_reactions;
create policy "match reactions delete own" on public.match_reactions
for delete to authenticated using (sender_id=auth.uid());

-- Mantém a tabela no Supabase Realtime quando permitido.
do $$
begin
  if exists(select 1 from pg_publication where pubname='supabase_realtime')
     and not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='match_reactions') then
    execute 'alter publication supabase_realtime add table public.match_reactions';
  end if;
exception when others then
  null;
end $$;

-- RPC opcional para envio server-side com intervalo mínimo de 3 segundos.
drop function if exists public.send_match_reaction(uuid,text);
create function public.send_match_reaction(p_match_id uuid,p_emoji text)
returns public.match_reactions
language plpgsql security definer set search_path=public
as $$
declare
  r public.match_reactions;
  participant boolean;
begin
  if auth.uid() is null then raise exception 'Não autenticado'; end if;
  if coalesce(trim(p_emoji),'')='' then raise exception 'Emoji inválido'; end if;
  select exists(select 1 from public.matches m where m.id=p_match_id and auth.uid()=any(m.player_ids) and m.status<>'finished') into participant;
  if not participant then raise exception 'Você não participa desta partida'; end if;
  if exists(select 1 from public.match_reactions where match_id=p_match_id and sender_id=auth.uid() and created_at>now()-interval '3 seconds') then
    raise exception 'Aguarde 3 segundos para enviar outro emoji.';
  end if;
  insert into public.match_reactions(match_id,sender_id,emoji)
  values(p_match_id,auth.uid(),trim(p_emoji))
  returning * into r;
  return r;
end;
$$;
revoke all on function public.send_match_reaction(uuid,text) from public;
grant execute on function public.send_match_reaction(uuid,text) to authenticated;

-- ============================================================
-- 2) CRIAÇÃO DE QUIZ PELO JOGADOR + REVISÃO DO ADMIN
-- ============================================================
create table if not exists public.category_submissions(
  id uuid primary key default gen_random_uuid(),
  name text not null,
  icon text not null default '🌐',
  description text,
  questions jsonb not null default '[]'::jsonb,
  created_by uuid not null references public.profiles(id) on delete cascade,
  status text not null default 'pending' check(status in ('pending','approved','rejected')),
  created_at timestamptz not null default now(),
  reviewed_at timestamptz,
  reviewed_by uuid references public.profiles(id) on delete set null
);
create index if not exists category_submissions_status_created_idx on public.category_submissions(status,created_at desc);
create index if not exists category_submissions_creator_idx on public.category_submissions(created_by,created_at desc);

alter table public.category_submissions enable row level security;
drop policy if exists "category submissions own insert" on public.category_submissions;
create policy "category submissions own insert" on public.category_submissions
for insert to authenticated with check(created_by=auth.uid());
drop policy if exists "category submissions own read" on public.category_submissions;
create policy "category submissions own read" on public.category_submissions
for select to authenticated using(created_by=auth.uid() or exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin'));

-- Remove/recria as RPCs para evitar conflitos de assinatura antigos.
drop function if exists public.submit_category_package(text,text,text,jsonb);
create function public.submit_category_package(p_name text,p_icon text,p_description text,p_questions jsonb)
returns jsonb
language plpgsql security definer set search_path=public
as $$
declare sid uuid;
begin
  if auth.uid() is null then raise exception 'Não autenticado'; end if;
  if length(trim(coalesce(p_name,'')))<2 then raise exception 'Informe um nome válido para o quiz'; end if;
  if jsonb_typeof(coalesce(p_questions,'[]'::jsonb))<>'array' or jsonb_array_length(p_questions)<>10 then raise exception 'O quiz precisa ter exatamente 10 perguntas'; end if;
  if exists(select 1 from public.category_submissions where created_by=auth.uid() and lower(name)=lower(trim(p_name)) and status='pending') then raise exception 'Você já possui um quiz com este nome aguardando revisão'; end if;
  insert into public.category_submissions(name,icon,description,questions,created_by)
  values(trim(p_name),left(coalesce(trim(p_icon),'🌐'),8),nullif(trim(coalesce(p_description,'')),''),p_questions,auth.uid())
  returning id into sid;
  return jsonb_build_object('ok',true,'id',sid);
end;
$$;
revoke all on function public.submit_category_package(text,text,text,jsonb) from public;
grant execute on function public.submit_category_package(text,text,text,jsonb) to authenticated;

drop function if exists public.admin_list_category_submissions();
create function public.admin_list_category_submissions()
returns table(id uuid,name text,icon text,description text,questions jsonb,created_at timestamptz,creator_username text)
language plpgsql security definer set search_path=public
as $$
begin
  if not exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin') then raise exception 'Acesso negado'; end if;
  return query
  select s.id,s.name,s.icon,s.description,s.questions,s.created_at,coalesce(p.username,p.display_name,'Jogador')
  from public.category_submissions s
  left join public.profiles p on p.id=s.created_by
  where s.status='pending'
  order by s.created_at desc;
end;
$$;
revoke all on function public.admin_list_category_submissions() from public;
grant execute on function public.admin_list_category_submissions() to authenticated;

drop function if exists public.admin_review_category_submission(uuid,boolean);
create function public.admin_review_category_submission(p_submission_id uuid,p_approve boolean)
returns jsonb
language plpgsql security definer set search_path=public
as $$
declare
  s public.category_submissions;
  q jsonb;
  category_id uuid;
begin
  if not exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin') then raise exception 'Acesso negado'; end if;
  select * into s from public.category_submissions where id=p_submission_id and status='pending' for update;
  if s.id is null then raise exception 'Solicitação não encontrada ou já revisada'; end if;
  if not p_approve then
    update public.category_submissions set status='rejected',reviewed_at=now(),reviewed_by=auth.uid() where id=s.id;
    return jsonb_build_object('ok',true,'status','rejected');
  end if;
  if exists(select 1 from public.categories where lower(name)=lower(s.name)) then raise exception 'Já existe uma categoria com o nome "%"',s.name; end if;
  insert into public.categories(name,icon,description,approved,created_by)
  values(s.name,coalesce(s.icon,'🌐'),s.description,true,s.created_by)
  returning id into category_id;
  for q in select value from jsonb_array_elements(s.questions) loop
    insert into public.questions(category_name,question_text,options,correct_index,image_url,created_by,approval_status,active)
    values(s.name,
           q->>'question_text',
           q->'options',
           greatest(0,least(3,coalesce((q->>'correct_index')::integer,0))),
           nullif(q->>'image_url',''),
           s.created_by,
           'approved',true);
  end loop;
  update public.category_submissions set status='approved',reviewed_at=now(),reviewed_by=auth.uid() where id=s.id;
  return jsonb_build_object('ok',true,'status','approved','category_id',category_id);
end;
$$;
revoke all on function public.admin_review_category_submission(uuid,boolean) from public;
grant execute on function public.admin_review_category_submission(uuid,boolean) to authenticated;

commit;


-- ================================================================
-- V42 MONETIZAÇÃO SEM ANÚNCIOS
-- ================================================================

alter table public.profiles add column if not exists premium_pass_until timestamptz;
alter table public.user_premium_items add column if not exists expires_at timestamptz;

-- Ativa a camada de pagamentos, mas continua sem publicidade.
insert into public.premium_store_settings(id,enabled,cosmetics_enabled,vip_enabled,coins_enabled,pass_enabled,payments_enabled)
values(1,true,true,true,true,true,true)
on conflict(id) do update set
 enabled=true, cosmetics_enabled=true, vip_enabled=true, coins_enabled=true, pass_enabled=true, payments_enabled=true;

-- Categorias comerciais.
insert into public.store_categories(name,description,icon,sort_order,active)
values
 ('VIP','Benefícios permanentes e identidade VIP.','👑',10,true),
 ('Passe','Passe de temporada com benefícios por 30 dias.','🎟️',11,true),
 ('Moedas','Pacotes de QuizCoins pagos com dinheiro real.','⚡',12,true)
on conflict(name) do update set active=true,description=excluded.description,icon=excluded.icon,sort_order=excluded.sort_order;

-- Produtos iniciais. O administrador poderá editar/remover depois.
insert into public.premium_items(
 id,name,category,description,price_cents,price_coins,promo_active,icon,effect_style,kind,source_type,source_id,active
) values
 ('qrvip-permanente','Q-Rival VIP','VIP','VIP permanente: +25% de XP nas vitórias, identificação VIP e acesso aos benefícios VIP.',2490,2490,false,'👑','vip','vip','vip','qrvip-permanente',true),
 ('qrpass-s1','Passe de Temporada — S1','Passe','Passe da temporada: +10% de XP e benefícios exclusivos durante 30 dias.',1490,1490,false,'🎟️','gold','pass','pass','qrpass-s1',true),
 ('qrtitle-champion','Título Campeão','Títulos','Título exclusivo para destacar seu perfil.',790,790,false,'🏆','gold','title','title',null,true)
on conflict(id) do update set
 name=excluded.name,category=excluded.category,description=excluded.description,
 price_cents=excluded.price_cents,price_coins=excluded.price_coins,icon=excluded.icon,
 effect_style=excluded.effect_style,kind=excluded.kind,source_type=excluded.source_type,active=true;

-- Compra segura: Pass recebe validade de 30 dias.
drop function if exists public.purchase_premium_item(text,bigint);
create function public.purchase_premium_item(p_item_id text,p_expected_price bigint default null)
returns jsonb language plpgsql security definer set search_path=public as $$
declare
  it public.premium_items; charge bigint; bal bigint; promo_ok boolean; already boolean; category_on boolean:=true;
  expires timestamptz;
begin
  if auth.uid() is null then raise exception 'Não autenticado'; end if;
  select * into it from public.premium_items where id::text=trim(p_item_id) and active=true limit 1;
  if it.id is null then raise exception 'Item não encontrado ou indisponível'; end if;
  if it.category='VIP' then category_on:=coalesce((select vip_enabled from public.premium_store_settings where id=1),true);
  elsif it.category='Moedas' then category_on:=coalesce((select coins_enabled and payments_enabled from public.premium_store_settings where id=1),false);
  elsif it.category='Passe' then category_on:=coalesce((select pass_enabled from public.premium_store_settings where id=1),true);
  else category_on:=coalesce((select cosmetics_enabled from public.premium_store_settings where id=1),true);
  end if;
  if not coalesce((select enabled from public.premium_store_settings where id=1),true) or not category_on then raise exception 'As compras desta categoria estão desativadas'; end if;
  promo_ok:=coalesce(it.promo_active,false) and coalesce(it.promo_price_coins,0)>0 and coalesce(it.promo_price_coins,0)<coalesce(it.price_coins,0) and (it.promo_expires_at is null or it.promo_expires_at>now());
  charge:=case when promo_ok then it.promo_price_coins else coalesce(it.price_coins,it.price_cents,0) end;
  if p_expected_price is not null and p_expected_price<>charge then raise exception 'O preço do item mudou. Atualize a loja e tente novamente.'; end if;
  select exists(select 1 from public.user_premium_items where user_id=auth.uid() and item_id=it.id and (expires_at is null or expires_at>now())) into already;
  if not already then
    update public.profiles set coins=coalesce(coins,0)-charge where id=auth.uid() and coalesce(coins,0)>=charge returning coins into bal;
    if bal is null then raise exception 'Você não possui QuizCoins suficientes'; end if;
    expires:=case when it.kind='pass' then now()+interval '30 days' else null end;
    if exists(select 1 from public.user_premium_items where user_id=auth.uid() and item_id=it.id) then
      update public.user_premium_items set purchased_at=now(),expires_at=expires,active=false where user_id=auth.uid() and item_id=it.id;
    else
      insert into public.user_premium_items(user_id,item_id,active,purchased_at,expires_at) values(auth.uid(),it.id,false,now(),expires);
    end if;
    insert into public.coin_ledger(user_id,amount,source_type,source_id,description) values(auth.uid(),-charge,'premium_purchase',gen_random_uuid()::text,'Compra: '||coalesce(it.name,'Item'));
    if it.kind='pass' then update public.profiles set premium_pass_until=expires where id=auth.uid(); end if;
  else
    select coins into bal from public.profiles where id=auth.uid();
  end if;
  return jsonb_build_object('ok',true,'already_owned',already,'balance',coalesce(bal,0),'charge',case when already then 0 else charge end,'item_id',it.id,'kind',it.kind,'expires_at',case when it.kind='pass' then coalesce(expires,(select expires_at from public.user_premium_items where user_id=auth.uid() and item_id=it.id)) else null end);
end $$;
revoke all on function public.purchase_premium_item(text,bigint) from public;
grant execute on function public.purchase_premium_item(text,bigint) to authenticated;

-- Ativação com validade para o Passe.
drop function if exists public.activate_premium_item(text);
create function public.activate_premium_item(p_item_id text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare it public.premium_items; bal bigint; title_uuid uuid; expires timestamptz;
begin
  if auth.uid() is null then raise exception 'Não autenticado'; end if;
  select * into it from public.premium_items where id::text=trim(p_item_id) limit 1;
  if it.id is null then raise exception 'Item não encontrado'; end if;
  select expires_at into expires from public.user_premium_items where user_id=auth.uid() and item_id=it.id and (expires_at is null or expires_at>now());
  if not exists(select 1 from public.user_premium_items where user_id=auth.uid() and item_id=it.id and (expires_at is null or expires_at>now())) then raise exception 'Você ainda não possui este item ativo'; end if;
  if it.kind='pass' then
    update public.profiles set premium_pass_until=coalesce(expires,now()+interval '30 days') where id=auth.uid();
  elsif it.kind='vip' then
    update public.profiles set premium_vip=true where id=auth.uid();
  elsif it.kind='frame' then update public.profiles set premium_frame=it.id::text where id=auth.uid();
  elsif it.kind='avatar' then update public.profiles set premium_avatar=it.id::text where id=auth.uid();
  elsif it.kind='effect' then update public.profiles set premium_effect=it.id::text where id=auth.uid();
  elsif it.kind='theme' then update public.profiles set premium_theme=it.id::text where id=auth.uid();
  elsif it.kind='background' then update public.profiles set premium_background=it.id::text where id=auth.uid();
  elsif it.kind='badge' then update public.profiles set premium_badge=it.id::text where id=auth.uid();
  elsif it.kind='title' then
    update public.profiles set premium_title=it.id::text where id=auth.uid();
  end if;
  update public.user_premium_items set active=true where user_id=auth.uid() and item_id=it.id;
  select coins into bal from public.profiles where id=auth.uid();
  return jsonb_build_object('ok',true,'item_id',it.id,'kind',it.kind,'balance',coalesce(bal,0),'expires_at',expires);
end $$;
revoke all on function public.activate_premium_item(text) from public;
grant execute on function public.activate_premium_item(text) to authenticated;

-- Reforça os pacotes comerciais padrão.
insert into public.coin_packages(name,coins,price_cents,active,sort_order)
select v.name,v.coins,v.price_cents,true,v.sort_order from (values
 ('1.000 QuizCoins',1000,499,1),
 ('2.500 QuizCoins',2500,999,2),
 ('6.000 QuizCoins',6000,1999,3),
 ('15.000 QuizCoins',15000,3999,4)
) v(name,coins,price_cents,sort_order)
where not exists(select 1 from public.coin_packages cp where cp.coins=v.coins and cp.price_cents=v.price_cents);

commit;
-- Q-Rival: compra manual de QuizCoins enquanto o gateway automático não está disponível.
-- O jogador solicita o pacote, conversa com o administrador, recebe o link de pagamento,
-- envia o comprovante e somente o administrador pode aprovar e creditar as Coins.

create table if not exists public.manual_coin_orders (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  coin_package_id uuid references public.coin_packages(id) on delete set null,
  coins bigint not null check (coins > 0),
  amount_cents bigint not null check (amount_cents > 0),
  status text not null default 'pending' check (status in ('pending','payment_link_sent','payment_submitted','approved','rejected','cancelled')),
  payment_link text,
  proof_path text,
  admin_note text,
  rejection_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  approved_at timestamptz,
  approved_by uuid references auth.users(id)
);

create table if not exists public.manual_coin_messages (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.manual_coin_orders(id) on delete cascade,
  sender_id uuid not null references auth.users(id) on delete cascade,
  message text not null check (length(trim(message)) > 0),
  message_type text not null default 'text' check (message_type in ('text','payment_link','proof','system')),
  media_path text,
  created_at timestamptz not null default now()
);

create index if not exists manual_coin_orders_user_idx on public.manual_coin_orders(user_id,created_at desc);
create index if not exists manual_coin_orders_status_idx on public.manual_coin_orders(status,updated_at desc);
create index if not exists manual_coin_messages_order_idx on public.manual_coin_messages(order_id,created_at);

alter table public.manual_coin_orders enable row level security;
alter table public.manual_coin_messages enable row level security;

drop policy if exists "manual coin orders own read" on public.manual_coin_orders;
create policy "manual coin orders own read" on public.manual_coin_orders
for select to authenticated using (user_id=auth.uid() or public.is_admin());

drop policy if exists "manual coin messages participant read" on public.manual_coin_messages;
create policy "manual coin messages participant read" on public.manual_coin_messages
for select to authenticated using (
  public.is_admin() or exists(select 1 from public.manual_coin_orders o where o.id=order_id and o.user_id=auth.uid())
);

drop policy if exists "manual coin messages own insert" on public.manual_coin_messages;
create policy "manual coin messages own insert" on public.manual_coin_messages
for insert to authenticated with check (
  sender_id=auth.uid() and (
    public.is_admin() or exists(select 1 from public.manual_coin_orders o where o.id=order_id and o.user_id=auth.uid())
  )
);

drop policy if exists "manual coin orders admin update" on public.manual_coin_orders;
create policy "manual coin orders admin update" on public.manual_coin_orders
for update to authenticated using(public.is_admin()) with check(public.is_admin());

-- O bucket é privado: comprovantes de pagamento não ficam publicamente acessíveis.
insert into storage.buckets(id,name,public)
values('purchase-proofs','purchase-proofs',false)
on conflict (id) do update set public=false;

drop policy if exists "purchase proofs user upload" on storage.objects;
create policy "purchase proofs user upload" on storage.objects
for insert to authenticated with check (
  bucket_id='purchase-proofs' and (storage.foldername(name))[1]=auth.uid()::text
);

drop policy if exists "purchase proofs owner or admin read" on storage.objects;
create policy "purchase proofs owner or admin read" on storage.objects
for select to authenticated using (
  bucket_id='purchase-proofs' and ((storage.foldername(name))[1]=auth.uid()::text or public.is_admin())
);

drop policy if exists "purchase proofs owner delete" on storage.objects;
create policy "purchase proofs owner delete" on storage.objects
for delete to authenticated using (
  bucket_id='purchase-proofs' and ((storage.foldername(name))[1]=auth.uid()::text or public.is_admin())
);

-- Realtime para o bate-papo de compra.
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname='supabase_realtime' and schemaname='public' and tablename='manual_coin_messages'
  ) then
    execute 'alter publication supabase_realtime add table public.manual_coin_messages';
  end if;
end $$;

create or replace function public.create_manual_coin_order(p_coin_package_id uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare p public.coin_packages; o public.manual_coin_orders;
begin
  if auth.uid() is null then raise exception 'Não autenticado'; end if;
  select * into p from public.coin_packages where id=p_coin_package_id and active=true limit 1;
  if p.id is null then raise exception 'Pacote de QuizCoins indisponível'; end if;
  insert into public.manual_coin_orders(user_id,coin_package_id,coins,amount_cents,status)
  values(auth.uid(),p.id,p.coins,p.price_cents,'pending') returning * into o;
  insert into public.manual_coin_messages(order_id,sender_id,message,message_type)
  values(o.id,auth.uid(),'Olá! Quero comprar '||p.coins||' QuizCoins por R$ '||to_char(p.price_cents/100.0,'FM999999990D00')||'. Aguardo o link de pagamento.','system');
  return jsonb_build_object('id',o.id,'coins',o.coins,'amount_cents',o.amount_cents,'status',o.status);
end $$;
revoke all on function public.create_manual_coin_order(uuid) from public;
grant execute on function public.create_manual_coin_order(uuid) to authenticated;

create or replace function public.admin_set_manual_coin_payment_link(p_order_id uuid,p_link text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare o public.manual_coin_orders;
begin
  if not public.is_admin() then raise exception 'Acesso negado'; end if;
  if coalesce(trim(p_link),'')='' then raise exception 'Informe o link de pagamento'; end if;
  update public.manual_coin_orders
     set payment_link=trim(p_link),status=case when status in ('approved','rejected','cancelled') then status else 'payment_link_sent' end,updated_at=now()
   where id=p_order_id returning * into o;
  if o.id is null then raise exception 'Pedido não encontrado'; end if;
  insert into public.manual_coin_messages(order_id,sender_id,message,message_type)
  values(o.id,auth.uid(),'🔗 Link de pagamento: '||trim(p_link),'payment_link');
  return jsonb_build_object('ok',true,'id',o.id,'status',o.status);
end $$;
revoke all on function public.admin_set_manual_coin_payment_link(uuid,text) from public;
grant execute on function public.admin_set_manual_coin_payment_link(uuid,text) to authenticated;

create or replace function public.submit_manual_coin_proof(p_order_id uuid,p_proof_path text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare o public.manual_coin_orders;
begin
  if auth.uid() is null then raise exception 'Não autenticado'; end if;
  update public.manual_coin_orders
     set proof_path=trim(p_proof_path),status=case when status='approved' then status else 'payment_submitted' end,updated_at=now()
   where id=p_order_id and user_id=auth.uid() and status not in ('approved','rejected','cancelled')
   returning * into o;
  if o.id is null then raise exception 'Pedido não encontrado ou já finalizado'; end if;
  insert into public.manual_coin_messages(order_id,sender_id,message,message_type,media_path)
  values(o.id,auth.uid(),'📎 Comprovante de pagamento enviado. Aguardo a confirmação do administrador.','proof',trim(p_proof_path));
  return jsonb_build_object('ok',true,'id',o.id,'status',o.status);
end $$;
revoke all on function public.submit_manual_coin_proof(uuid,text) from public;
grant execute on function public.submit_manual_coin_proof(uuid,text) to authenticated;

create or replace function public.admin_approve_manual_coin_order(p_order_id uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare o public.manual_coin_orders; new_balance bigint;
begin
  if not public.is_admin() then raise exception 'Acesso negado'; end if;
  select * into o from public.manual_coin_orders where id=p_order_id for update;
  if o.id is null then raise exception 'Pedido não encontrado'; end if;
  if o.status='approved' then
    select coins into new_balance from public.profiles where id=o.user_id;
    return jsonb_build_object('ok',true,'already_approved',true,'coins',o.coins,'balance',coalesce(new_balance,0));
  end if;
  if o.status not in ('payment_submitted','payment_link_sent','pending') then raise exception 'Este pedido não pode ser aprovado no status atual'; end if;
  update public.profiles set coins=coalesce(coins,0)+o.coins where id=o.user_id returning coins into new_balance;
  if new_balance is null then raise exception 'Jogador não encontrado'; end if;
  insert into public.coin_ledger(user_id,amount,source_type,source_id,description)
  values(o.user_id,o.coins,'manual_purchase',o.id::text,'Compra manual de '||o.coins||' QuizCoins');
  update public.manual_coin_orders set status='approved',approved_at=now(),approved_by=auth.uid(),updated_at=now() where id=o.id;
  insert into public.manual_coin_messages(order_id,sender_id,message,message_type)
  values(o.id,auth.uid(),'✅ Pagamento confirmado! As '||o.coins||' QuizCoins foram liberadas na sua conta.','system');
  return jsonb_build_object('ok',true,'already_approved',false,'coins',o.coins,'balance',new_balance);
end $$;
revoke all on function public.admin_approve_manual_coin_order(uuid) from public;
grant execute on function public.admin_approve_manual_coin_order(uuid) to authenticated;

create or replace function public.admin_reject_manual_coin_order(p_order_id uuid,p_reason text default 'Pagamento não confirmado')
returns jsonb language plpgsql security definer set search_path=public as $$
declare o public.manual_coin_orders;
begin
  if not public.is_admin() then raise exception 'Acesso negado'; end if;
  update public.manual_coin_orders set status='rejected',rejection_reason=coalesce(nullif(trim(p_reason),''),'Pagamento não confirmado'),updated_at=now()
   where id=p_order_id and status<>'approved' returning * into o;
  if o.id is null then raise exception 'Pedido não encontrado ou já aprovado'; end if;
  insert into public.manual_coin_messages(order_id,sender_id,message,message_type)
  values(o.id,auth.uid(),'❌ Pedido recusado: '||o.rejection_reason,'system');
  return jsonb_build_object('ok',true,'id',o.id,'status',o.status);
end $$;
revoke all on function public.admin_reject_manual_coin_order(uuid,text) from public;
grant execute on function public.admin_reject_manual_coin_order(uuid,text) to authenticated;

-- Mantém a venda manual de Coins disponível mesmo sem o gateway automático.
update public.premium_store_settings
set coins_enabled=true, payments_enabled=true
where id=1;


-- ================================================================
-- INÍCIO: SUPABASE_V46_CONQUISTAS.sql
-- ================================================================

-- Q-Rival v46 — correção das conquistas
-- Execute no SQL Editor do Supabase depois de publicar o v46.
-- Não remove dados existentes.

create or replace function public.quizup_check_achievements_v2(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  a record;
  games_count integer := 0;
  wins_count integer := 0;
  coins_count bigint := 0;
  streak_count integer := 0;
  current_streak integer := 0;
  r record;
  should_unlock boolean;
begin
  if p_user_id is null then return; end if;
  if auth.uid() is not null and auth.uid() <> p_user_id and not exists (
    select 1 from public.profiles where id=auth.uid() and role='admin'
  ) then
    raise exception 'not allowed';
  end if;

  select count(*)::int, count(*) filter (where coalesce(won,false))::int
    into games_count, wins_count
    from public.game_results
   where user_id=p_user_id;

  select coalesce(coins,0)::bigint into coins_count
    from public.profiles where id=p_user_id;

  -- Maior sequência consecutiva de vitórias no histórico do jogador.
  for r in
    select coalesce(won,false) as won
      from public.game_results
     where user_id=p_user_id
     order by created_at asc
  loop
    if r.won then
      current_streak := current_streak + 1;
      if current_streak > streak_count then streak_count := current_streak; end if;
    else
      current_streak := 0;
    end if;
  end loop;

  for a in
    select id, criteria_type, coalesce(threshold,1)::int as threshold
      from public.achievements
     where active=true
  loop
    should_unlock := false;
    case lower(coalesce(a.criteria_type,''))
      when 'wins' then should_unlock := wins_count >= a.threshold;
      when 'games' then should_unlock := games_count >= a.threshold;
      when 'streak' then should_unlock := streak_count >= a.threshold;
      when 'coins' then should_unlock := coins_count >= a.threshold;
      when 'first_game' then should_unlock := games_count >= 1;
      else should_unlock := false;
    end case;

    if should_unlock and not exists (
      select 1 from public.user_achievements ua
       where ua.user_id=p_user_id and ua.achievement_id=a.id
    ) then
      insert into public.user_achievements(user_id,achievement_id,unlocked_at)
      values(p_user_id,a.id,now());
    end if;
  end loop;
end;
$$;

revoke all on function public.quizup_check_achievements_v2(uuid) from public;
grant execute on function public.quizup_check_achievements_v2(uuid) to authenticated;

-- Pontuação oficial da nova tabela de tempo.
create or replace function public.quizup_points_for_remaining_seconds(p_seconds integer)
returns integer
language sql
immutable
as $$
  select case
    when greatest(0,least(20,coalesce(p_seconds,0))) <= 0 then 0
    else greatest(8,20-floor((20-greatest(0,least(20,coalesce(p_seconds,0))))/3.0)::int*2)
  end;
$$;

revoke all on function public.quizup_points_for_remaining_seconds(integer) from public;
grant execute on function public.quizup_points_for_remaining_seconds(integer) to authenticated;

-- Corrige também partidas online já existentes sem precisar substituir a RPC
-- submit_match_answer: quando a RPC grava `remaining`/`score` dentro de answers,
-- este trigger ajusta o total para a tabela oficial de 20 segundos.
create or replace function public.quizup_fix_match_score_v46()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  item record;
  player_id text;
  old_score integer;
  remaining integer;
  desired integer;
  scores jsonb := coalesce(new.scores,'{}'::jsonb);
  current_total integer;
begin
  if new.answers is null then return new; end if;

  for item in select key, value from jsonb_each(new.answers)
  loop
    player_id := split_part(item.key, ':', 1);
    if player_id is null or player_id='' then continue; end if;
    if coalesce((item.value->>'correct')::boolean,false)
       and (item.value ? 'remaining')
       and (item.value->>'remaining') ~ '^-?[0-9]+$' then
      remaining := greatest(0,least(20,(item.value->>'remaining')::integer));
      desired := public.quizup_points_for_remaining_seconds(remaining);
      old_score := greatest(0,coalesce((item.value->>'score')::integer,0));
      current_total := coalesce((scores->>player_id)::integer,0);
      scores := jsonb_set(scores, array[player_id], to_jsonb(greatest(0,current_total-old_score+desired)), true);
    end if;
  end loop;

  new.scores := scores;
  return new;
end;
$$;

drop trigger if exists trg_quizup_fix_match_score_v46 on public.matches;
create trigger trg_quizup_fix_match_score_v46
after update of answers on public.matches
for each row
execute function public.quizup_fix_match_score_v46();


-- ================================================================
-- INÍCIO: SUPABASE_V47_CORRECOES.sql
-- ================================================================

-- Q-Rival v47 — inventário, XP, partidas contra bot e nível 1-1000
-- Execute este arquivo no SQL Editor do Supabase.
-- Não apaga produtos, inventário, partidas ou conquistas existentes.

-- 1) O inventário do jogador estava sem políticas de leitura/alteração próprias.
-- A compra via RPC podia funcionar, mas o app não conseguia enxergar a linha criada.
alter table public.user_premium_items enable row level security;

drop policy if exists "user premium items own read" on public.user_premium_items;
create policy "user premium items own read"
on public.user_premium_items for select to authenticated
using (user_id=auth.uid() or public.is_admin());

drop policy if exists "user premium items own update" on public.user_premium_items;
create policy "user premium items own update"
on public.user_premium_items for update to authenticated
using (user_id=auth.uid() or public.is_admin())
with check (user_id=auth.uid() or public.is_admin());

-- 2) Nível global: 250 XP por nível, até o nível 1000.
-- Nível 1 começa em 0 XP; nível 1000 fica travado a partir de 249.750 XP.
create or replace function public.quizup_balance_level_v47()
returns trigger
language plpgsql
as $$
begin
  new.xp := greatest(0,coalesce(new.xp,0));
  new.level := least(1000,greatest(1,1+floor(new.xp/250)::int));
  return new;
end;
$$;

drop trigger if exists quizup_balance_level_v47 on public.profiles;
create trigger quizup_balance_level_v47
before insert or update of xp on public.profiles
for each row execute function public.quizup_balance_level_v47();

update public.profiles
set level=least(1000,greatest(1,1+floor(greatest(0,coalesce(xp,0))/250)::int));

-- 3) Reforça a função de pontuação oficial de 20 segundos.
create or replace function public.quizup_points_for_remaining_seconds(p_seconds integer)
returns integer
language sql
immutable
as $$
  select case
    when greatest(0,least(20,coalesce(p_seconds,0))) <= 0 then 0
    else greatest(8,20-floor((20-greatest(0,least(20,coalesce(p_seconds,0))))/3.0)::int*2)
  end;
$$;
revoke all on function public.quizup_points_for_remaining_seconds(integer) from public;
grant execute on function public.quizup_points_for_remaining_seconds(integer) to authenticated;

-- 4) Garante que conquistas sejam verificadas também após resultado contra bot.
-- A função existente da v46 é reaproveitada; esta chamada serve para usuários
-- que já possuem resultados e querem sincronizar as conquistas imediatamente.
-- Não altera conquistas já liberadas.

-- 5) Corrige níveis por tópico para o mesmo ritmo do nível global.
create or replace function public.quizup_topic_level_v47(p_xp bigint)
returns integer
language sql
immutable
as $$
  select least(1000,greatest(1,1+floor(greatest(0,coalesce(p_xp,0))/250)::int));
$$;
revoke all on function public.quizup_topic_level_v47(bigint) from public;
grant execute on function public.quizup_topic_level_v47(bigint) to authenticated;


-- ================================================================
-- INÍCIO: SUPABASE_V48_CORRECOES.sql
-- ================================================================

-- Q-Rival v48 — correções de inventário, emojis e acesso administrativo
-- Execute no SQL Editor do Supabase.

-- 1) Função oficial de verificação administrativa.
create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path=public
as $$
  select exists(
    select 1 from public.profiles
    where id=auth.uid() and role='admin'
  );
$$;
revoke all on function public.is_admin() from public;
grant execute on function public.is_admin() to authenticated;

-- 2) Inventário: o próprio jogador pode ler/ativar seus itens.
alter table public.user_premium_items enable row level security;
drop policy if exists "user premium items own read" on public.user_premium_items;
create policy "user premium items own read"
on public.user_premium_items for select to authenticated
using (user_id=auth.uid() or public.is_admin());
drop policy if exists "user premium items own update" on public.user_premium_items;
create policy "user premium items own update"
on public.user_premium_items for update to authenticated
using (user_id=auth.uid() or public.is_admin())
with check (user_id=auth.uid() or public.is_admin());

-- 3) Reações da partida: garante tabela, RLS, Realtime e RPC.
create table if not exists public.match_reactions(
  id uuid primary key default gen_random_uuid(),
  match_id uuid not null references public.matches(id) on delete cascade,
  sender_id uuid not null references public.profiles(id) on delete cascade,
  emoji text not null check(char_length(emoji) between 1 and 120),
  created_at timestamptz not null default now()
);
create index if not exists match_reactions_match_created_idx
  on public.match_reactions(match_id,created_at desc);
create index if not exists match_reactions_sender_created_idx
  on public.match_reactions(sender_id,created_at desc);

alter table public.match_reactions enable row level security;
drop policy if exists "match reactions read authenticated" on public.match_reactions;
create policy "match reactions read authenticated"
on public.match_reactions for select to authenticated using (true);
drop policy if exists "match reactions insert own" on public.match_reactions;
create policy "match reactions insert own"
on public.match_reactions for insert to authenticated
with check (sender_id=auth.uid());
drop policy if exists "match reactions delete own" on public.match_reactions;
create policy "match reactions delete own"
on public.match_reactions for delete to authenticated
using (sender_id=auth.uid());

do $$
begin
  if exists(select 1 from pg_publication where pubname='supabase_realtime')
     and not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='match_reactions') then
    execute 'alter publication supabase_realtime add table public.match_reactions';
  end if;
exception when others then null;
end $$;

drop function if exists public.send_match_reaction(uuid,text);
create function public.send_match_reaction(p_match_id uuid,p_emoji text)
returns public.match_reactions
language plpgsql
security definer
set search_path=public
as $$
declare
  r public.match_reactions;
  participant boolean;
begin
  if auth.uid() is null then raise exception 'Não autenticado'; end if;
  if coalesce(trim(p_emoji),'')='' then raise exception 'Emoji inválido'; end if;
  select exists(
    select 1 from public.matches m
    where m.id=p_match_id
      and auth.uid()=any(m.player_ids)
      and m.status<>'finished'
  ) into participant;
  if not participant then raise exception 'Você não participa desta partida'; end if;
  if exists(
    select 1 from public.match_reactions
    where match_id=p_match_id and sender_id=auth.uid()
      and created_at>now()-interval '3 seconds'
  ) then raise exception 'Aguarde 3 segundos para enviar outro emoji.'; end if;
  insert into public.match_reactions(match_id,sender_id,emoji)
  values(p_match_id,auth.uid(),trim(p_emoji)) returning * into r;
  return r;
end;
$$;
revoke all on function public.send_match_reaction(uuid,text) from public;
grant execute on function public.send_match_reaction(uuid,text) to authenticated;


-- ================================================================
-- INÍCIO: SUPABASE_V49_ENGAJAMENTO.sql
-- ================================================================

-- Q-Rival v49 — Engajamento administrável
-- Execute DEPOIS dos SQLs base/v47/v48. Não apaga dados existentes.

create extension if not exists pgcrypto;

create table if not exists public.qr_events (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  description text,
  icon text default '🔥',
  event_type text not null default 'weekly',
  category text,
  start_at timestamptz not null,
  end_at timestamptz not null,
  active boolean not null default true,
  xp_multiplier numeric(6,2) not null default 1,
  coin_reward integer not null default 0,
  reward_item_id text,
  rules jsonb not null default '{}'::jsonb,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  constraint qr_events_dates check (end_at > start_at),
  constraint qr_events_type check (event_type in ('weekly','category','special'))
);

create table if not exists public.qr_missions (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  description text,
  icon text default '🎯',
  criteria_type text not null default 'games',
  target integer not null default 1,
  reward_xp integer not null default 0,
  reward_coins integer not null default 0,
  reward_item_id text,
  category text,
  start_at timestamptz not null,
  end_at timestamptz not null,
  active boolean not null default true,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  constraint qr_missions_dates check (end_at > start_at),
  constraint qr_missions_target check (target > 0),
  constraint qr_missions_type check (criteria_type in ('games','wins','streak','score'))
);

create table if not exists public.qr_seasons (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  start_at timestamptz not null,
  end_at timestamptz not null,
  active boolean not null default true,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  constraint qr_seasons_dates check (end_at > start_at)
);

create table if not exists public.qr_tournaments (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  description text,
  icon text default '🏟️',
  category text,
  start_at timestamptz not null,
  end_at timestamptz not null,
  status text not null default 'open',
  max_players integer not null default 64,
  reward_xp integer not null default 0,
  reward_coins integer not null default 0,
  reward_item_id text,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  constraint qr_tournaments_dates check (end_at > start_at),
  constraint qr_tournaments_status check (status in ('open','running','closed')),
  constraint qr_tournaments_max check (max_players >= 2)
);

create table if not exists public.qr_tournament_entries (
  id uuid primary key default gen_random_uuid(),
  tournament_id uuid not null references public.qr_tournaments(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  joined_at timestamptz not null default now(),
  score integer not null default 0,
  rank integer,
  unique(tournament_id,user_id)
);

create index if not exists qr_events_active_dates on public.qr_events(active,start_at,end_at);
create index if not exists qr_missions_active_dates on public.qr_missions(active,start_at,end_at);
create index if not exists qr_tournaments_status_dates on public.qr_tournaments(status,start_at,end_at);
create index if not exists qr_tournament_entries_tournament on public.qr_tournament_entries(tournament_id,score desc);

alter table public.qr_events enable row level security;
alter table public.qr_missions enable row level security;
alter table public.qr_seasons enable row level security;
alter table public.qr_tournaments enable row level security;
alter table public.qr_tournament_entries enable row level security;

do $$ begin
  if not exists (select 1 from pg_policies where tablename='qr_events' and policyname='qr_events_public_select') then
    create policy qr_events_public_select on public.qr_events for select to authenticated using (active=true or exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin'));
  end if;
  if not exists (select 1 from pg_policies where tablename='qr_events' and policyname='qr_events_admin_write') then
    create policy qr_events_admin_write on public.qr_events for all to authenticated using (exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin')) with check (exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin'));
  end if;
  if not exists (select 1 from pg_policies where tablename='qr_missions' and policyname='qr_missions_public_select') then
    create policy qr_missions_public_select on public.qr_missions for select to authenticated using (active=true or exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin'));
  end if;
  if not exists (select 1 from pg_policies where tablename='qr_missions' and policyname='qr_missions_admin_write') then
    create policy qr_missions_admin_write on public.qr_missions for all to authenticated using (exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin')) with check (exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin'));
  end if;
  if not exists (select 1 from pg_policies where tablename='qr_seasons' and policyname='qr_seasons_public_select') then
    create policy qr_seasons_public_select on public.qr_seasons for select to authenticated using (active=true or exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin'));
  end if;
  if not exists (select 1 from pg_policies where tablename='qr_seasons' and policyname='qr_seasons_admin_write') then
    create policy qr_seasons_admin_write on public.qr_seasons for all to authenticated using (exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin')) with check (exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin'));
  end if;
  if not exists (select 1 from pg_policies where tablename='qr_tournaments' and policyname='qr_tournaments_public_select') then
    create policy qr_tournaments_public_select on public.qr_tournaments for select to authenticated using (status in ('open','running') or exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin'));
  end if;
  if not exists (select 1 from pg_policies where tablename='qr_tournaments' and policyname='qr_tournaments_admin_write') then
    create policy qr_tournaments_admin_write on public.qr_tournaments for all to authenticated using (exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin')) with check (exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin'));
  end if;
  if not exists (select 1 from pg_policies where tablename='qr_tournament_entries' and policyname='qr_tournament_entries_select') then
    create policy qr_tournament_entries_select on public.qr_tournament_entries for select to authenticated using (user_id=auth.uid() or exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin'));
  end if;
  if not exists (select 1 from pg_policies where tablename='qr_tournament_entries' and policyname='qr_tournament_entries_insert') then
    create policy qr_tournament_entries_insert on public.qr_tournament_entries for insert to authenticated with check (user_id=auth.uid());
  end if;
end $$;

create or replace function public.qr_join_tournament(p_tournament_id uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare t record; n integer;
begin
  if auth.uid() is null then raise exception 'Faça login para participar.'; end if;
  select * into t from public.qr_tournaments where id=p_tournament_id for update;
  if not found then raise exception 'Torneio não encontrado.'; end if;
  if t.status <> 'open' or now() < t.start_at or now() > t.end_at then raise exception 'As inscrições deste torneio estão fechadas.'; end if;
  select count(*) into n from public.qr_tournament_entries where tournament_id=p_tournament_id;
  if n >= t.max_players then raise exception 'Torneio lotado.'; end if;
  insert into public.qr_tournament_entries(tournament_id,user_id) values(p_tournament_id,auth.uid()) on conflict(tournament_id,user_id) do nothing;
  return jsonb_build_object('ok',true,'message','Inscrição confirmada!');
end $$;
revoke all on function public.qr_join_tournament(uuid) from public;
grant execute on function public.qr_join_tournament(uuid) to authenticated;

create or replace function public.qr_weekly_leaderboard()
returns table(rank bigint,user_id uuid,username text,avatar_url text,points bigint,wins bigint,games bigint,league text)
language sql security definer set search_path=public as $$
with r as (
  select gr.user_id,
         sum(case when gr.won then 25 when gr.outcome='draw' then 8 else 3 end)::bigint + floor(sum(greatest(0,gr.score))/10.0)::bigint points,
         count(*)::bigint games,
         count(*) filter(where gr.won)::bigint wins
  from public.game_results gr
  where gr.created_at >= now()-interval '7 days'
  group by gr.user_id
), ranked as (
 select row_number() over(order by points desc,games desc)::bigint rnk,* from r
)
select ranked.rnk,p.id,p.username,p.avatar_url,ranked.points,ranked.wins,ranked.games,
 case when ranked.points>=1500 then 'Lendário' when ranked.points>=1000 then 'Mestre' when ranked.points>=650 then 'Diamante' when ranked.points>=400 then 'Ouro' when ranked.points>=200 then 'Prata' else 'Bronze' end
from ranked join public.profiles p on p.id=ranked.user_id
order by ranked.rnk;
$$;
revoke all on function public.qr_weekly_leaderboard() from public;
grant execute on function public.qr_weekly_leaderboard() to authenticated;

-- Recompensas configuradas pelo admin para missões concluídas.
-- O cliente só marca a conclusão; o crédito é feito por esta função, uma vez por missão/período.
create table if not exists public.qr_mission_claims (
 id uuid primary key default gen_random_uuid(), mission_id uuid not null references public.qr_missions(id) on delete cascade,
 user_id uuid not null references auth.users(id) on delete cascade, claimed_at timestamptz not null default now(), unique(mission_id,user_id)
);
alter table public.qr_mission_claims enable row level security;
do $$ begin
 if not exists(select 1 from pg_policies where tablename='qr_mission_claims' and policyname='qr_mission_claims_select') then create policy qr_mission_claims_select on public.qr_mission_claims for select to authenticated using(user_id=auth.uid() or exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin')); end if;
 if not exists(select 1 from pg_policies where tablename='qr_mission_claims' and policyname='qr_mission_claims_insert') then create policy qr_mission_claims_insert on public.qr_mission_claims for insert to authenticated with check(user_id=auth.uid()); end if;
end $$;

-- Compatibilidade: atualiza a sequência máxima quando uma partida termina, se a coluna existir.
create or replace function public.qr_current_streak(p_user_id uuid)
returns integer language plpgsql security definer set search_path=public as $$
declare r record; n integer:=0;
begin
 for r in select won from public.game_results where user_id=p_user_id order by created_at desc loop
   if coalesce(r.won,false) then n:=n+1; else exit; end if;
 end loop;
 return n;
end $$;
revoke all on function public.qr_current_streak(uuid) from public;
grant execute on function public.qr_current_streak(uuid) to authenticated;

-- Seed opcional: não cria eventos/missões automaticamente para não alterar a configuração do administrador.

-- Resgate seguro das missões. Cada missão pode ser resgatada uma única vez por jogador.
create or replace function public.qr_claim_mission(p_mission_id uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare m record; already boolean; v_games integer; v_wins integer; v_score integer; v_streak integer;
begin
  if auth.uid() is null then raise exception 'Faça login para resgatar.'; end if;
  select * into m from public.qr_missions where id=p_mission_id and active=true and now() between start_at and end_at;
  if not found then raise exception 'Missão indisponível.'; end if;
  select exists(select 1 from public.qr_mission_claims where mission_id=p_mission_id and user_id=auth.uid()) into already;
  if already then raise exception 'Esta recompensa já foi resgatada.'; end if;
  select count(*)::int,count(*) filter(where won)::int,coalesce(sum(score),0)::int into v_games,v_wins,v_score
    from public.game_results where user_id=auth.uid() and created_at>=date_trunc('day',now());
  v_streak:=public.qr_current_streak(auth.uid());
  if (m.criteria_type='games' and v_games<m.target) or (m.criteria_type='wins' and v_wins<m.target) or (m.criteria_type='score' and v_score<m.target) or (m.criteria_type='streak' and v_streak<m.target) then
    raise exception 'Você ainda não concluiu esta missão.';
  end if;
  insert into public.qr_mission_claims(mission_id,user_id) values(p_mission_id,auth.uid());
  update public.profiles set xp=coalesce(xp,0)+coalesce(m.reward_xp,0), coins=coalesce(coins,0)+coalesce(m.reward_coins,0) where id=auth.uid();
  if m.reward_item_id is not null then
    insert into public.user_premium_items(user_id,item_id,active,purchased_at) values(auth.uid(),m.reward_item_id,false,now()) on conflict do nothing;
  end if;
  return jsonb_build_object('ok',true,'message','Recompensa resgatada com sucesso!');
end $$;
revoke all on function public.qr_claim_mission(uuid) from public;
grant execute on function public.qr_claim_mission(uuid) to authenticated;


-- ================================================================
-- INÍCIO: SUPABASE_V51_MODOS.sql
-- ================================================================

-- Q-Rival v51 — modos, torneios e administração centralizada
-- Execute DEPOIS dos SQLs anteriores. Não apaga dados existentes.
create extension if not exists pgcrypto;

create table if not exists public.qr_mode_settings (
  id integer primary key default 1 check(id=1),
  enabled boolean not null default true,
  sudden_death_enabled boolean not null default true,
  sudden_death_max_players integer not null default 8 check(sudden_death_max_players between 2 and 8),
  sudden_death_questions integer not null default 10 check(sudden_death_questions between 3 and 20),
  sudden_death_seconds integer not null default 15 check(sudden_death_seconds between 5 and 60),
  daily_missions_enabled boolean not null default true,
  streak_enabled boolean not null default true,
  free_chest_enabled boolean not null default true,
  creator_system_enabled boolean not null default true,
  special_events_enabled boolean not null default true,
  season_pass_enabled boolean not null default true,
  rotating_shop_enabled boolean not null default true,
  impossible_challenge_enabled boolean not null default true,
  updated_at timestamptz not null default now()
);
insert into public.qr_mode_settings(id) values(1) on conflict(id) do nothing;

create table if not exists public.qr_sudden_rooms (
  id uuid primary key default gen_random_uuid(),
  code text unique not null,
  host_id uuid not null references public.profiles(id) on delete cascade,
  category text not null default 'Geral',
  max_players integer not null default 8 check(max_players between 2 and 8),
  question_ids uuid[] not null default '{}',
  current_question integer not null default 0,
  status text not null default 'waiting' check(status in ('waiting','running','finished','cancelled')),
  state jsonb not null default '{}'::jsonb,
  winner_id uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  started_at timestamptz,
  finished_at timestamptz
);
create table if not exists public.qr_sudden_players (
  room_id uuid not null references public.qr_sudden_rooms(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  score integer not null default 0,
  status text not null default 'active' check(status in ('active','eliminated','winner')),
  joined_at timestamptz not null default now(),
  last_answer_question integer not null default -1,
  primary key(room_id,user_id)
);
create index if not exists qr_sudden_players_room on public.qr_sudden_players(room_id,status,score desc);

alter table public.qr_sudden_rooms enable row level security;
alter table public.qr_sudden_players enable row level security;
do $$ begin
 if not exists(select 1 from pg_policies where tablename='qr_sudden_rooms' and policyname='qr_sudden_rooms_read') then
  create policy qr_sudden_rooms_read on public.qr_sudden_rooms for select to authenticated using(status in ('waiting','running') or host_id=auth.uid() or public.is_admin());
 end if;
 if not exists(select 1 from pg_policies where tablename='qr_sudden_players' and policyname='qr_sudden_players_read') then
  create policy qr_sudden_players_read on public.qr_sudden_players for select to authenticated using(exists(select 1 from public.qr_sudden_players me where me.room_id=qr_sudden_players.room_id and me.user_id=auth.uid()) or public.is_admin());
 end if;
end $$;

create or replace function public.qr_create_sudden_room(p_category text default 'Geral')
returns uuid language plpgsql security definer set search_path=public as $$
declare rid uuid; c text; maxp integer;
begin
 if auth.uid() is null then raise exception 'Faça login.'; end if;
 if not exists(select 1 from qr_mode_settings where id=1 and enabled and sudden_death_enabled) then raise exception 'Modo Morte Súbita está desativado.'; end if;
 select sudden_death_max_players into maxp from qr_mode_settings where id=1;
 loop c:=upper(substr(md5(random()::text || clock_timestamp()::text || auth.uid()::text),1,6)); exit when not exists(select 1 from qr_sudden_rooms where code=c); end loop;
 insert into qr_sudden_rooms(code,host_id,category,max_players) values(c,auth.uid(),coalesce(nullif(trim(p_category),''),'Geral'),maxp) returning id into rid;
 insert into qr_sudden_players(room_id,user_id) values(rid,auth.uid());
 return rid;
end $$;
revoke all on function public.qr_create_sudden_room(text) from public; grant execute on function public.qr_create_sudden_room(text) to authenticated;

create or replace function public.qr_join_sudden_room(p_code text)
returns uuid language plpgsql security definer set search_path=public as $$
declare r qr_sudden_rooms; n integer;
begin
 if auth.uid() is null then raise exception 'Faça login.'; end if;
 select * into r from qr_sudden_rooms where code=upper(trim(p_code)) for update;
 if not found then raise exception 'Sala não encontrada.'; end if;
 if r.status<>'waiting' then raise exception 'Esta sala já começou ou terminou.'; end if;
 select count(*) into n from qr_sudden_players where room_id=r.id;
 if n>=r.max_players then raise exception 'Sala lotada.'; end if;
 insert into qr_sudden_players(room_id,user_id) values(r.id,auth.uid()) on conflict do nothing;
 return r.id;
end $$;
revoke all on function public.qr_join_sudden_room(text) from public; grant execute on function public.qr_join_sudden_room(text) to authenticated;

create or replace function public.qr_find_sudden_room(p_category text default 'Geral')
returns uuid language plpgsql security definer set search_path=public as $$
declare rid uuid;
begin
 select r.id into rid from qr_sudden_rooms r where r.status='waiting' and r.category=coalesce(nullif(trim(p_category),''),'Geral') and exists(select 1 from qr_sudden_players p where p.room_id=r.id and p.user_id<>auth.uid()) order by r.created_at limit 1 for update skip locked;
 if rid is null then return public.qr_create_sudden_room(p_category); end if;
 perform public.qr_join_sudden_room((select code from qr_sudden_rooms where id=rid));
 return rid;
end $$;
revoke all on function public.qr_find_sudden_room(text) from public; grant execute on function public.qr_find_sudden_room(text) to authenticated;

create or replace function public.qr_start_sudden_room(p_room_id uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare r qr_sudden_rooms; ids uuid[]; qn integer; lim integer; st timestamptz;
begin
 select * into r from qr_sudden_rooms where id=p_room_id for update;
 if not found then raise exception 'Sala não encontrada.'; end if;
 if r.host_id<>auth.uid() and not public.is_admin() then raise exception 'Somente o criador da sala pode iniciar.'; end if;
 if r.status<>'waiting' then return jsonb_build_object('ok',true,'status',r.status); end if;
 select count(*) into lim from qr_sudden_players where room_id=r.id;
 if lim<2 then raise exception 'É preciso ter pelo menos 2 jogadores.'; end if;
 select array_agg(id order by random()) into ids from (select id from questions where active=true and approval_status='approved' and category_name=r.category order by random() limit (select sudden_death_questions from qr_mode_settings where id=1)) q;
 if coalesce(array_length(ids,1),0)<3 then select array_agg(id order by random()) into ids from (select id from questions where active=true and approval_status='approved' order by random() limit (select sudden_death_questions from qr_mode_settings where id=1)) q; end if;
 if coalesce(array_length(ids,1),0)<3 then raise exception 'Não há perguntas suficientes.'; end if;
 st:=now();
 update qr_sudden_rooms set question_ids=ids,current_question=0,status='running',started_at=st,state=jsonb_build_object('question_started_at',extract(epoch from st),'question_seconds',(select sudden_death_seconds from qr_mode_settings where id=1)) where id=r.id;
 return jsonb_build_object('ok',true,'room_id',r.id);
end $$;
revoke all on function public.qr_start_sudden_room(uuid) from public; grant execute on function public.qr_start_sudden_room(uuid) to authenticated;

create or replace function public.qr_submit_sudden_answer(p_room_id uuid,p_question_index integer,p_answer_index integer)
returns jsonb language plpgsql security definer set search_path=public as $$
declare r qr_sudden_rooms; me qr_sudden_players; q questions; correct boolean; remain integer; active_count integer; winner uuid; st timestamptz; nextq integer;
begin
 select * into r from qr_sudden_rooms where id=p_room_id for update;
 if not found or r.status<>'running' then raise exception 'Sala não está em partida.'; end if;
 select * into me from qr_sudden_players where room_id=r.id and user_id=auth.uid() for update;
 if not found or me.status<>'active' then raise exception 'Você foi eliminado.'; end if;
 if me.last_answer_question=p_question_index then return jsonb_build_object('ok',true,'duplicate',true); end if;
 if p_question_index<>r.current_question then raise exception 'Pergunta desatualizada.'; end if;
 select * into q from questions where id=r.question_ids[p_question_index+1];
 correct:=q.correct_index=p_answer_index;
 if correct then update qr_sudden_players set score=score+1,last_answer_question=p_question_index where room_id=r.id and user_id=auth.uid(); else update qr_sudden_players set status='eliminated',last_answer_question=p_question_index where room_id=r.id and user_id=auth.uid(); end if;
 select count(*) into active_count from qr_sudden_players where room_id=r.id and status='active';
 if active_count<=1 then
   select user_id into winner from qr_sudden_players where room_id=r.id and status='active' order by score desc,joined_at limit 1;
   if winner is null then select user_id into winner from qr_sudden_players where room_id=r.id order by score desc,joined_at limit 1; end if;
   update qr_sudden_players set status='winner' where room_id=r.id and user_id=winner;
   update qr_sudden_rooms set status='finished',winner_id=winner,finished_at=now() where id=r.id;
   return jsonb_build_object('ok',true,'correct',correct,'finished',true,'winner_id',winner);
 end if;
 -- Só avança quando todos os jogadores que ainda estão vivos responderam à pergunta.
 if exists(select 1 from qr_sudden_players where room_id=r.id and status='active' and last_answer_question<>p_question_index) then
   return jsonb_build_object('ok',true,'correct',correct,'finished',false,'waiting',true);
 end if;
 nextq:=r.current_question+1;
 if nextq>=coalesce(array_length(r.question_ids,1),0) then
   select user_id into winner from qr_sudden_players where room_id=r.id and status='active' order by score desc,joined_at limit 1;
   update qr_sudden_players set status='winner' where room_id=r.id and user_id=winner;
   update qr_sudden_rooms set status='finished',winner_id=winner,finished_at=now() where id=r.id;
   return jsonb_build_object('ok',true,'correct',correct,'finished',true,'winner_id',winner);
 end if;
 st:=now();
 update qr_sudden_rooms set current_question=nextq,state=jsonb_build_object('question_started_at',extract(epoch from st),'question_seconds',(select sudden_death_seconds from qr_mode_settings where id=1)) where id=r.id;
 return jsonb_build_object('ok',true,'correct',correct,'finished',false,'next_question',nextq);
end $$;
revoke all on function public.qr_submit_sudden_answer(uuid,integer,integer) from public; grant execute on function public.qr_submit_sudden_answer(uuid,integer,integer) to authenticated;

-- Avaliação dos quizzes criados pelos jogadores.
create table if not exists public.qr_quiz_ratings (
  quiz_category_id uuid not null references public.categories(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  rating integer not null check(rating between 1 and 5),
  review text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key(quiz_category_id,user_id)
);
create index if not exists qr_quiz_ratings_category on public.qr_quiz_ratings(quiz_category_id);
alter table public.qr_quiz_ratings enable row level security;
do $$ begin
 if not exists(select 1 from pg_policies where tablename='qr_quiz_ratings' and policyname='qr_quiz_ratings_read') then create policy qr_quiz_ratings_read on public.qr_quiz_ratings for select to authenticated using(true); end if;
 if not exists(select 1 from pg_policies where tablename='qr_quiz_ratings' and policyname='qr_quiz_ratings_write') then create policy qr_quiz_ratings_write on public.qr_quiz_ratings for insert to authenticated with check(user_id=auth.uid()); end if;
 if not exists(select 1 from pg_policies where tablename='qr_quiz_ratings' and policyname='qr_quiz_ratings_update') then create policy qr_quiz_ratings_update on public.qr_quiz_ratings for update to authenticated using(user_id=auth.uid()) with check(user_id=auth.uid()); end if;
end $$;

create or replace function public.qr_rate_quiz(p_category_id uuid,p_rating integer,p_review text default null)
returns jsonb language plpgsql security definer set search_path=public as $$
begin
 if not exists(select 1 from categories where id=p_category_id and approved=true) then raise exception 'Quiz não encontrado.'; end if;
 insert into qr_quiz_ratings(quiz_category_id,user_id,rating,review) values(p_category_id,auth.uid(),p_rating,nullif(trim(p_review),'')) on conflict(quiz_category_id,user_id) do update set rating=excluded.rating,review=excluded.review,updated_at=now();
 return jsonb_build_object('ok',true);
end $$;
revoke all on function public.qr_rate_quiz(uuid,integer,text) from public; grant execute on function public.qr_rate_quiz(uuid,integer,text) to authenticated;

-- Torneios: exatamente 4 faixas de entrada e no máximo 18 jogadores.
alter table public.qr_tournaments add column if not exists entry_fee integer not null default 100;
alter table public.qr_tournaments add column if not exists prize_pool bigint not null default 0;
update public.qr_tournaments set max_players=least(coalesce(max_players,18),18), entry_fee=case when entry_fee in (100,200,500,1000) then entry_fee else 100 end where max_players>18 or entry_fee not in (100,200,500,1000);
alter table public.qr_tournaments add column if not exists winner_id uuid references public.profiles(id) on delete set null;
do $$ begin
 if not exists(select 1 from pg_constraint where conrelid='public.qr_tournaments'::regclass and conname='qr_tournaments_entry_fee') then alter table public.qr_tournaments add constraint qr_tournaments_entry_fee check(entry_fee in (100,200,500,1000)); end if;
 alter table public.qr_tournaments drop constraint if exists qr_tournaments_max;
 alter table public.qr_tournaments add constraint qr_tournaments_max check(max_players between 2 and 18);
end $$;

create or replace function public.qr_join_tournament(p_tournament_id uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare t qr_tournaments; n integer; newbal bigint;
begin
 if auth.uid() is null then raise exception 'Faça login.'; end if;
 select * into t from qr_tournaments where id=p_tournament_id for update;
 if not found then raise exception 'Torneio não encontrado.'; end if;
 if t.status<>'open' or now()<t.start_at or now()>t.end_at then raise exception 'Inscrições fechadas.'; end if;
 select count(*) into n from qr_tournament_entries where tournament_id=t.id;
 if n>=least(t.max_players,18) then raise exception 'Torneio lotado.'; end if;
 if exists(select 1 from qr_tournament_entries where tournament_id=t.id and user_id=auth.uid()) then return jsonb_build_object('ok',true,'already',true); end if;
 update profiles set coins=coalesce(coins,0)-t.entry_fee where id=auth.uid() and coalesce(coins,0)>=t.entry_fee returning coins into newbal;
 if newbal is null then raise exception 'Você não tem QuizCoins suficientes.'; end if;
 insert into qr_tournament_entries(tournament_id,user_id) values(t.id,auth.uid());
 update qr_tournaments set prize_pool=coalesce(prize_pool,0)+t.entry_fee where id=t.id;
 return jsonb_build_object('ok',true,'balance',newbal,'entry_fee',t.entry_fee,'prize_pool',coalesce(t.prize_pool,0)+t.entry_fee);
end $$;
revoke all on function public.qr_join_tournament(uuid) from public; grant execute on function public.qr_join_tournament(uuid) to authenticated;

create or replace function public.qr_finish_tournament(p_tournament_id uuid,p_winner_id uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare t qr_tournaments; pool bigint; exists_entry boolean; newbal bigint;
begin
 if not public.is_admin() then raise exception 'Acesso negado.'; end if;
 select * into t from qr_tournaments where id=p_tournament_id for update;
 if not found then raise exception 'Torneio não encontrado.'; end if;
 select exists(select 1 from qr_tournament_entries where tournament_id=t.id and user_id=p_winner_id) into exists_entry;
 if not exists_entry then raise exception 'O vencedor precisa estar inscrito.'; end if;
 if t.winner_id is not null then raise exception 'Este torneio já tem vencedor.'; end if;
 pool:=coalesce(t.prize_pool,0);
 update profiles set coins=coalesce(coins,0)+pool where id=p_winner_id returning coins into newbal;
 update qr_tournaments set winner_id=p_winner_id,status='closed' where id=t.id;
 return jsonb_build_object('ok',true,'winner_id',p_winner_id,'prize_pool',pool,'winner_balance',newbal);
end $$;
revoke all on function public.qr_finish_tournament(uuid,uuid) from public; grant execute on function public.qr_finish_tournament(uuid,uuid) to authenticated;

-- Temporadas / passe
create table if not exists public.qr_season_rewards (
 id uuid primary key default gen_random_uuid(), season_id uuid not null references public.qr_seasons(id) on delete cascade,
 level integer not null check(level>0), reward_type text not null default 'coins', reward_coins integer not null default 0, reward_item_id text, premium_only boolean not null default false,
 unique(season_id,level)
);

-- Loja rotativa
create table if not exists public.qr_shop_rotation (
 id uuid primary key default gen_random_uuid(), item_id text not null, starts_at timestamptz not null, ends_at timestamptz not null, active boolean not null default true, sort_order integer not null default 0, created_by uuid references public.profiles(id), check(ends_at>starts_at)
);
create index if not exists qr_shop_rotation_active on public.qr_shop_rotation(active,starts_at,ends_at);

-- Desafio impossível controlado pelo admin
create table if not exists public.qr_impossible_challenges (
 id uuid primary key default gen_random_uuid(), title text not null, description text, category text, question_id uuid references public.questions(id) on delete set null, reward_coins integer not null default 0, reward_xp integer not null default 0, reward_item_id text, starts_at timestamptz not null, ends_at timestamptz not null, active boolean not null default true, created_by uuid references public.profiles(id), check(ends_at>starts_at)
);

-- Todos os novos catálogos são administráveis apenas pelo admin.
alter table public.qr_mode_settings enable row level security;
alter table public.qr_season_rewards enable row level security;
alter table public.qr_shop_rotation enable row level security;
alter table public.qr_impossible_challenges enable row level security;
do $$ begin
 if not exists(select 1 from pg_policies where tablename='qr_mode_settings' and policyname='qr_mode_settings_read') then create policy qr_mode_settings_read on public.qr_mode_settings for select to authenticated using(true); end if;
 if not exists(select 1 from pg_policies where tablename='qr_mode_settings' and policyname='qr_mode_settings_admin') then create policy qr_mode_settings_admin on public.qr_mode_settings for all to authenticated using(public.is_admin()) with check(public.is_admin()); end if;
 if not exists(select 1 from pg_policies where tablename='qr_season_rewards' and policyname='qr_season_rewards_read') then create policy qr_season_rewards_read on public.qr_season_rewards for select to authenticated using(true); end if;
 if not exists(select 1 from pg_policies where tablename='qr_season_rewards' and policyname='qr_season_rewards_admin') then create policy qr_season_rewards_admin on public.qr_season_rewards for all to authenticated using(public.is_admin()) with check(public.is_admin()); end if;
 if not exists(select 1 from pg_policies where tablename='qr_shop_rotation' and policyname='qr_shop_rotation_read') then create policy qr_shop_rotation_read on public.qr_shop_rotation for select to authenticated using(active=true or public.is_admin()); end if;
 if not exists(select 1 from pg_policies where tablename='qr_shop_rotation' and policyname='qr_shop_rotation_admin') then create policy qr_shop_rotation_admin on public.qr_shop_rotation for all to authenticated using(public.is_admin()) with check(public.is_admin()); end if;
 if not exists(select 1 from pg_policies where tablename='qr_impossible_challenges' and policyname='qr_impossible_challenges_read') then create policy qr_impossible_challenges_read on public.qr_impossible_challenges for select to authenticated using((active=true and now() between starts_at and ends_at) or public.is_admin()); end if;
 if not exists(select 1 from pg_policies where tablename='qr_impossible_challenges' and policyname='qr_impossible_challenges_admin') then create policy qr_impossible_challenges_admin on public.qr_impossible_challenges for all to authenticated using(public.is_admin()) with check(public.is_admin()); end if;
end $$;

-- Realtime para salas.
do $$ begin
 if exists(select 1 from pg_publication where pubname='supabase_realtime') then
   if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='qr_sudden_rooms') then execute 'alter publication supabase_realtime add table public.qr_sudden_rooms'; end if;
   if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='qr_sudden_players') then execute 'alter publication supabase_realtime add table public.qr_sudden_players'; end if;
 end if;
exception when others then null; end $$;

-- Ranking de criadores por avaliações e partidas das categorias criadas.
create or replace function public.qr_creator_leaderboard(p_limit integer default 50)
returns table(rank bigint,user_id uuid,username text,avatar_url text,quizzes bigint,plays bigint,avg_rating numeric,rating_count bigint)
language sql security definer set search_path=public as $$
with cats as (
 select c.id,c.created_by,count(gr.*)::bigint plays
 from categories c left join game_results gr on gr.category=c.name
 where c.approved=true and c.created_by is not null
 group by c.id,c.created_by
), agg as (
 select c.created_by,count(distinct c.id)::bigint quizzes,coalesce(sum(c.plays),0)::bigint plays,
        coalesce(avg(r.rating),0)::numeric(10,2) avg_rating,count(r.rating)::bigint rating_count
 from cats c left join qr_quiz_ratings r on r.quiz_category_id=c.id
 group by c.created_by
), ranked as (select row_number() over(order by avg_rating desc,plays desc,quizzes desc)::bigint rank,created_by as user_id,quizzes,plays,avg_rating,rating_count from agg)
select ranked.rank,p.id,p.username,p.avatar_url,ranked.quizzes,ranked.plays,ranked.avg_rating,ranked.rating_count
from ranked join profiles p on p.id=ranked.user_id order by ranked.rank limit greatest(1,least(coalesce(p_limit,50),100));
$$;
revoke all on function public.qr_creator_leaderboard(integer) from public; grant execute on function public.qr_creator_leaderboard(integer) to authenticated;

-- Sequência diária e baú diário: uma reivindicação por dia.
create table if not exists public.qr_daily_claims (
 user_id uuid not null references public.profiles(id) on delete cascade,
 claim_date date not null default current_date,
 streak integer not null default 1,
 reward_coins integer not null default 0,
 reward_item_id text,
 chest boolean not null default false,
 created_at timestamptz not null default now(),
 primary key(user_id,claim_date,chest)
);
alter table public.qr_daily_claims enable row level security;
do $$ begin
 if not exists(select 1 from pg_policies where tablename='qr_daily_claims' and policyname='qr_daily_claims_read') then create policy qr_daily_claims_read on public.qr_daily_claims for select to authenticated using(user_id=auth.uid() or public.is_admin()); end if;
end $$;
create or replace function public.qr_claim_daily_reward(p_chest boolean default false)
returns jsonb language plpgsql security definer set search_path=public as $$
declare today date:=current_date; prev date; laststreak integer:=0; v_coins integer:=0; item text:=null; already boolean; nextstreak integer;
begin
 if auth.uid() is null then raise exception 'Faça login.'; end if;
 select exists(select 1 from qr_daily_claims where user_id=auth.uid() and claim_date=today and chest=p_chest) into already;
 if already then raise exception 'Recompensa de hoje já foi resgatada.'; end if;
 select max(claim_date),coalesce(max(streak),0) into prev,laststreak from qr_daily_claims where user_id=auth.uid() and chest=false;
 nextstreak:=case when prev=today-1 then laststreak+1 else 1 end;
 if p_chest then v_coins:=floor(random()*(greatest(0,(select chest_max_coins from qr_mode_settings where id=1)-(select chest_min_coins from qr_mode_settings where id=1))+1))::int+(select least(chest_min_coins,chest_max_coins) from qr_mode_settings where id=1); select id::text into item from premium_items where active=true and rarity in ('rare','epic','legendary','mythic') and random()<(select chest_item_chance from qr_mode_settings where id=1) order by random() limit 1; else v_coins:=(select daily_coin_base from qr_mode_settings where id=1)+least(nextstreak,25)*2; end if;
 insert into qr_daily_claims(user_id,claim_date,streak,reward_coins,reward_item_id,chest) values(auth.uid(),today,nextstreak,v_coins,item,p_chest) on conflict(user_id,claim_date,chest) do nothing;
 update profiles set coins=coalesce(profiles.coins,0)+v_coins where id=auth.uid();
 if item is not null then insert into user_premium_items(user_id,item_id,active,purchased_at) values(auth.uid(),item,false,now()) on conflict do nothing; end if;
 return jsonb_build_object('ok',true,'coins',v_coins,'item_id',item,'streak',nextstreak);
end $$;
revoke all on function public.qr_claim_daily_reward(boolean) from public; grant execute on function public.qr_claim_daily_reward(boolean) to authenticated;

-- Segurança: o administrador pode criar qualquer conteúdo, mas jogadores não podem alterar configurações do sistema.
alter table public.qr_seasons add column if not exists description text;
alter table public.qr_seasons add column if not exists xp_per_level integer not null default 250;

create table if not exists public.qr_impossible_claims (
  challenge_id uuid not null references public.qr_impossible_challenges(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key(challenge_id,user_id)
);
alter table public.qr_impossible_claims enable row level security;
do $$ begin
 if not exists(select 1 from pg_policies where tablename='qr_impossible_claims' and policyname='qr_impossible_claims_read') then create policy qr_impossible_claims_read on public.qr_impossible_claims for select to authenticated using(user_id=auth.uid() or public.is_admin()); end if;
end $$;
create or replace function public.qr_claim_impossible(p_challenge_id uuid,p_answer_index integer)
returns jsonb language plpgsql security definer set search_path=public as $$
declare c qr_impossible_challenges; q questions; already boolean; v_coins integer; v_xp integer;
begin
 if auth.uid() is null then raise exception 'Faça login.'; end if;
 select * into c from qr_impossible_challenges where id=p_challenge_id and active=true and now() between starts_at and ends_at;
 if not found then raise exception 'Desafio encerrado.'; end if;
 select exists(select 1 from qr_impossible_claims where challenge_id=c.id and user_id=auth.uid()) into already;
 if already then raise exception 'Você já respondeu este desafio.'; end if;
 if c.question_id is null then raise exception 'Pergunta não configurada.'; end if;
 select * into q from questions where id=c.question_id;
 if q.correct_index<>p_answer_index then insert into qr_impossible_claims(challenge_id,user_id) values(c.id,auth.uid()) on conflict do nothing; return jsonb_build_object('ok',false,'correct',false); end if;
 insert into qr_impossible_claims(challenge_id,user_id) values(c.id,auth.uid());
 v_coins:=greatest(0,c.reward_coins);v_xp:=greatest(0,c.reward_xp);
 update profiles set coins=coalesce(coins,0)+v_coins,xp=coalesce(xp,0)+v_xp where id=auth.uid();
 if c.reward_item_id is not null then insert into user_premium_items(user_id,item_id,active,purchased_at) values(auth.uid(),c.reward_item_id,false,now()) on conflict do nothing; end if;
 return jsonb_build_object('ok',true,'correct',true,'coins',v_coins,'xp',v_xp,'item_id',c.reward_item_id);
end $$;
revoke all on function public.qr_claim_impossible(uuid,integer) from public; grant execute on function public.qr_claim_impossible(uuid,integer) to authenticated;
alter table public.premium_items add column if not exists rarity text not null default 'common';
do $$ begin
 if not exists(select 1 from pg_constraint where conrelid='public.premium_items'::regclass and conname='premium_items_rarity_check') then alter table public.premium_items add constraint premium_items_rarity_check check(rarity in ('common','uncommon','rare','epic','legendary','mythic')); end if;
end $$;
alter table public.qr_mode_settings add column if not exists daily_coin_base integer not null default 25;
alter table public.qr_mode_settings add column if not exists chest_min_coins integer not null default 50;
alter table public.qr_mode_settings add column if not exists chest_max_coins integer not null default 150;
alter table public.qr_mode_settings add column if not exists chest_item_chance numeric(5,4) not null default 0.08;


-- V52: correções finais incorporadas: PK diária inclui chest e código de sala não depende de gen_random_bytes().
