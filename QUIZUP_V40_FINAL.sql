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
 ('frame-fire','Fogo','Molduras','Moldura Fogo estática — 256 × 256 px, PNG/SVG transparente.',500,500,null,null,false,null,'🔥','fire','assets/store/frames/fire.svg','image/svg+xml','frame','frame','frame-fire',256,256,0,'static-v3',true),
 ('frame-water','Água','Molduras','Moldura Água estática — 256 × 256 px, PNG/SVG transparente.',500,500,null,null,false,null,'💧','water','assets/store/frames/water.svg','image/svg+xml','frame','frame','frame-water',256,256,0,'static-v3',true),
 ('frame-earth','Terra','Molduras','Moldura Terra estática — 256 × 256 px, PNG/SVG transparente.',500,500,null,null,false,null,'🌿','earth','assets/store/frames/earth.svg','image/svg+xml','frame','frame','frame-earth',256,256,0,'static-v3',true),
 ('frame-air','Ar','Molduras','Moldura Ar estática — 256 × 256 px, PNG/SVG transparente.',500,500,null,null,false,null,'🌪️','air','assets/store/frames/air.svg','image/svg+xml','frame','frame','frame-air',256,256,0,'static-v3',true),
 ('frame-darkness','Trevas','Molduras','Moldura Trevas estática — 256 × 256 px, PNG/SVG transparente.',500,500,null,null,false,null,'🌑','darkness','assets/store/frames/darkness.svg','image/svg+xml','frame','frame','frame-darkness',256,256,0,'static-v3',true),
 ('frame-light','Luz','Molduras','Moldura Luz estática — 256 × 256 px, PNG/SVG transparente.',500,500,null,null,false,null,'✨','light','assets/store/frames/light.svg','image/svg+xml','frame','frame','frame-light',256,256,0,'static-v3',true)
on conflict(id) do update set
 name=excluded.name,category=excluded.category,description=excluded.description,
 price_cents=excluded.price_cents,price_coins=excluded.price_coins,
 icon=excluded.icon,effect_style=excluded.effect_style,asset_url=excluded.asset_url,
 asset_type=excluded.asset_type,kind='frame',source_type='frame',source_id=excluded.source_id,
 asset_width=256,asset_height=256,frame_inset_percent=0,frame_version='static-v3',active=true;

-- Garantia: as seis molduras oficiais são sempre estáticas e sem GIF.
update public.premium_items
set asset_type='image/svg+xml',asset_width=256,asset_height=256,frame_inset_percent=0,frame_version='static-v3'
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
-- Remove somente cosméticos que não têm arte utilizável ou que pertencem
-- explicitamente ao catálogo antigo de Emblemas. Itens funcionais com arte
-- válida permanecem disponíveis.
create temp table _quizup_remove_items on commit drop as
select id, kind, source_type, source_id
from public.premium_items
where
  -- antigo catálogo de Emblemas/molduras que não deve mais ser usado
  category in ('Emblemas','Emblem')
  or asset_url ilike '%/assets/store/emblems/%'
  or asset_url ilike '%/assets/emblems/%'
  -- cosmético sem arquivo: não pode ser exibido/comprado corretamente
  or (kind in ('avatar','frame','title','background','emoji','badge')
      and coalesce(trim(asset_url),'')='');

-- Primeiro remove a posse dos itens que serão excluídos, evitando referências
-- antigas no inventário.
delete from public.user_premium_items up
where up.item_id in (select id from _quizup_remove_items);

-- Limpa referências de perfil para itens antigos/removidos.
update public.profiles p
set premium_avatar=case when premium_avatar in (select id::text from _quizup_remove_items) then null else premium_avatar end,
    premium_frame=case when premium_frame in (select id::text from _quizup_remove_items) then null else premium_frame end,
    premium_effect=case when premium_effect in (select id::text from _quizup_remove_items) then null else premium_effect end,
    premium_theme=case when premium_theme in (select id::text from _quizup_remove_items) then null else premium_theme end,
    premium_background=case when premium_background in (select id::text from _quizup_remove_items) then null else premium_background end,
    premium_title=case when premium_title in (select id::text from _quizup_remove_items) then null else premium_title end,
    premium_badge=case when premium_badge in (select id::text from _quizup_remove_items) then null else premium_badge end
where
  premium_avatar in (select id::text from _quizup_remove_items)
  or premium_frame in (select id::text from _quizup_remove_items)
  or premium_effect in (select id::text from _quizup_remove_items)
  or premium_theme in (select id::text from _quizup_remove_items)
  or premium_background in (select id::text from _quizup_remove_items)
  or premium_title in (select id::text from _quizup_remove_items)
  or premium_badge in (select id::text from _quizup_remove_items);

delete from public.premium_items
where id in (select id from _quizup_remove_items);

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

-- Conferência rápida no SQL Editor:
select id,name,category,kind,price_coins,asset_width,asset_height,active
from public.premium_items
where kind in ('avatar','frame','title','background','emoji')
order by category,name;
