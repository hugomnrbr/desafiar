-- QuizUp v39.2 — pacote final de correções e catálogo inicial
-- Execute no Supabase SQL Editor DEPOIS das migrations anteriores.

begin;

-- ================================================================
-- 1) Remove overloads antigos que causam RPC ambígua / 42883.
-- ================================================================
do $$
declare r record;
begin
  for r in select oid::regprocedure::text sig
           from pg_proc
           where pronamespace='public'::regnamespace
             and proname='activate_premium_item'
  loop
    execute 'drop function if exists '||r.sig||' cascade';
  end loop;
end $$;

create function public.activate_premium_item(p_item_id text)
returns jsonb language plpgsql security definer set search_path=public
as $$
declare
  it public.premium_items;
  bal bigint;
  title_uuid uuid;
  is_admin boolean;
begin
  if auth.uid() is null then raise exception 'Não autenticado'; end if;
  select exists(select 1 from public.profiles where id=auth.uid() and role='admin') into is_admin;
  select * into it from public.premium_items where id::text=trim(p_item_id) and active=true limit 1;
  if it.id is null then raise exception 'Item não encontrado ou inativo'; end if;
  if not exists(select 1 from public.user_premium_items where user_id=auth.uid() and item_id=it.id) then
    raise exception 'Você ainda não possui este item';
  end if;

  update public.user_premium_items up set active=false
  where up.user_id=auth.uid()
    and exists(select 1 from public.premium_items x where x.id=up.item_id and x.kind=it.kind);
  update public.user_premium_items set active=true where user_id=auth.uid() and item_id=it.id;

  if it.kind='frame' then update public.profiles set premium_frame=it.id::text where id=auth.uid();
  elsif it.kind='avatar' then update public.profiles set premium_avatar=it.id::text where id=auth.uid();
  elsif it.kind='effect' then update public.profiles set premium_effect=it.id::text where id=auth.uid();
  elsif it.kind='theme' then update public.profiles set premium_theme=it.id::text where id=auth.uid();
  elsif it.kind='background' then update public.profiles set premium_background=it.id::text where id=auth.uid();
  elsif it.kind='badge' then update public.profiles set premium_badge=it.id::text where id=auth.uid();
  elsif it.kind='title' then
    -- Jogador normal: título principal.
    -- Administrador: mantém 👑 Administrador e usa este item como SEGUNDO título.
    if is_admin then
      update public.user_premium_items set active=false
      where user_id=auth.uid() and item_id=it.id;
      update public.profiles set premium_title=it.id::text where id=auth.uid();
    else
      title_uuid:=null;
      if coalesce(it.source_type,'')='title' and coalesce(it.source_id,'')<>'' then
        begin title_uuid:=it.source_id::uuid; exception when others then title_uuid:=null; end;
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
    end if;
  elsif it.kind='vip' then update public.profiles set premium_vip=true where id=auth.uid();
  end if;

  select coins into bal from public.profiles where id=auth.uid();
  return jsonb_build_object('ok',true,'item_id',it.id,'kind',it.kind,'balance',coalesce(bal,0));
end $$;
revoke all on function public.activate_premium_item(text) from public;
grant execute on function public.activate_premium_item(text) to authenticated;

-- ================================================================
-- 2) RPC de remoção: manter as DUAS assinaturas para bases antigas.
-- ================================================================
drop function if exists public.admin_remove_premium_item(text,text,text);
drop function if exists public.admin_remove_premium_item(text,text);
drop function if exists public.admin_remove_premium_item(text);

create function public.admin_remove_premium_item(p_item_id text,p_source_type text,p_source_id text)
returns jsonb language plpgsql security definer set search_path=public
as $$
declare
  it public.premium_items;
  removed_count bigint:=0;
  source_uuid uuid;
begin
  if not public.is_admin() then raise exception 'Acesso negado'; end if;
  select * into it from public.premium_items where id::text=trim(p_item_id) limit 1;
  if it.id is null and coalesce(p_source_type,'')<>'' then
    select * into it from public.premium_items
    where source_type=p_source_type and source_id=p_source_id limit 1;
  end if;
  if it.id is null then raise exception 'Item não encontrado'; end if;

  delete from public.user_premium_items where item_id=it.id;
  get diagnostics removed_count=row_count;
  if it.kind='avatar' then update public.profiles set premium_avatar=null where premium_avatar=it.id::text;
  elsif it.kind='badge' then update public.profiles set premium_badge=null where premium_badge=it.id::text;
  elsif it.kind='background' then update public.profiles set premium_background=null where premium_background=it.id::text;
  elsif it.kind='title' then update public.profiles set premium_title=null where premium_title=it.id::text;
  elsif it.kind='frame' then update public.profiles set premium_frame=null where premium_frame=it.id::text;
  elsif it.kind='effect' then update public.profiles set premium_effect=null where premium_effect=it.id::text;
  elsif it.kind='theme' then update public.profiles set premium_theme=null where premium_theme=it.id::text;
  end if;

  if coalesce(it.source_type,'')='title' and coalesce(it.source_id,'')<>'' then
    begin source_uuid:=it.source_id::uuid;
      delete from public.user_titles where title_id=source_uuid;
      update public.profiles set main_title_id=null where main_title_id=source_uuid;
      update public.titles set active=false where id=source_uuid;
    exception when others then null; end;
  elsif coalesce(it.source_type,'')='badge' and coalesce(it.source_id,'')<>'' then
    begin source_uuid:=it.source_id::uuid;
      update public.badges set active=false where id=source_uuid;
    exception when others then null; end;
  end if;
  update public.premium_items set active=false where id=it.id;
  return jsonb_build_object('ok',true,'item_id',it.id,'removed_from_inventory',removed_count);
end $$;

create function public.admin_remove_premium_item(p_item_id text)
returns jsonb language sql security definer set search_path=public
as $$ select public.admin_remove_premium_item(p_item_id,null::text,null::text); $$;
revoke all on function public.admin_remove_premium_item(text,text,text) from public;
revoke all on function public.admin_remove_premium_item(text) from public;
grant execute on function public.admin_remove_premium_item(text,text,text) to authenticated;
grant execute on function public.admin_remove_premium_item(text) to authenticated;

-- ================================================================
-- 3) Notificações: aceita os tipos usados pelo aplicativo.
-- ================================================================
alter table if exists public.notifications drop constraint if exists notifications_type_check;
alter table if exists public.notifications add constraint notifications_type_check
check (type in ('like','comment','friend_request','message','challenge','achievement','coin','system','broadcast'));

-- ================================================================
-- 4) Campos de cosméticos.
-- ================================================================
alter table if exists public.profiles add column if not exists premium_avatar text;
alter table if exists public.profiles add column if not exists premium_badge text;
alter table if exists public.profiles add column if not exists premium_background text;
alter table if exists public.profiles add column if not exists premium_title text;

-- ================================================================
-- 5) Limpa o catálogo cosmético antigo solicitado pelo administrador.
-- Preserva conquistas e categorias de jogo; remove apenas cosméticos antigos.
-- ================================================================
delete from public.user_premium_items
where item_id in (select id from public.premium_items where kind in ('avatar','badge','title','background'));
update public.profiles set premium_avatar=null where premium_avatar is not null;
update public.profiles set premium_badge=null where premium_badge is not null;
update public.profiles set premium_background=null where premium_background is not null;
update public.profiles set premium_title=null where premium_title is not null and premium_title in (select id::text from public.premium_items where kind='title');
update public.achievements set title_id=null where title_id in (select id from public.titles);
delete from public.user_titles;
delete from public.premium_items where kind in ('avatar','badge','title','background');
delete from public.badges;
delete from public.titles;

-- ================================================================
-- 6) Categorias da nova loja.
-- ================================================================
insert into public.store_categories(name,description,icon,sort_order,active)
values
('Avatares','Avatares oficiais do novo estilo QuizUp.','👤',1,true),
('Emblemas','Emblemas animados que acompanham o perfil.','🏅',2,true),
('Títulos','Títulos em PNG 600 × 160 com efeito configurável.','🏷️',3,true),
('Fundos de Perfil','Fundos 800 × 500 para o perfil.','🖼️',4,true)
on conflict(name) do update set description=excluded.description,icon=excluded.icon,sort_order=excluded.sort_order,active=true;

-- ================================================================
-- 7) 3 avatares + 3 emblemas + 3 títulos + 3 backgrounds.
-- Todos ativos e compráveis com QuizCoins.
-- Os arquivos ficam dentro do próprio ZIP e são publicados pelo GitHub Pages.
-- ================================================================
do $$
declare
  x record;
  tid uuid;
  bid uuid;
begin
  -- Títulos: PNG padrão 600x160.
  for x in select * from (values
    ('Campeão','assets/store/titles/campeao.png','fire',750),
    ('Mestre','assets/store/titles/mestre.png','water',750),
    ('Lendário','assets/store/titles/lenda.png','darkness',900)
  ) v(name,asset,effect,price)
  loop
    insert into public.titles(name,icon,description,effect_style,asset_url,asset_type,active,title_color,title_font)
    values(x.name,'', 'Título oficial de exemplo em PNG.',x.effect,x.asset,'png',true,'#ffd21a','Inter')
    returning id into tid;
    insert into public.premium_items(id,name,category,description,price_cents,price_coins,promo_active,icon,effect_style,asset_url,asset_type,kind,source_type,source_id,active)
    values('title-'||tid::text,x.name,'Títulos','PNG 600 × 160 com efeito animado ao redor.',x.price,x.price,false,'',x.effect,x.asset,'png','title','title',tid::text,true)
    on conflict(id) do update set name=excluded.name,category=excluded.category,description=excluded.description,price_coins=excluded.price_coins,price_cents=excluded.price_cents,effect_style=excluded.effect_style,asset_url=excluded.asset_url,asset_type=excluded.asset_type,kind='title',source_type='title',source_id=excluded.source_id,active=true;
  end loop;

  -- Emblemas animados.
  for x in select * from (values
    ('Emblema de Fogo','🔥','fire','assets/store/emblems/fire.svg',650),
    ('Emblema de Água','💧','water','assets/store/emblems/water.svg',650),
    ('Emblema Galáxia','🌌','darkness','assets/store/emblems/galaxy.svg',750)
  ) v(name,icon,effect,asset,price)
  loop
    insert into public.badges(name,description,icon,asset_url,asset_type,active)
    values(x.name,'Emblema animado que gira ao redor do avatar.',x.icon,x.asset,'svg',true)
    returning id into bid;
    insert into public.premium_items(id,name,category,description,price_cents,price_coins,promo_active,icon,effect_style,asset_url,asset_type,kind,source_type,source_id,active)
    values('badge-'||bid::text,x.name,'Emblemas','Animação ao redor do perfil do jogador.',x.price,x.price,false,x.icon,x.effect,x.asset,'svg','badge','badge',bid::text,true)
    on conflict(id) do update set name=excluded.name,category=excluded.category,description=excluded.description,price_coins=excluded.price_coins,price_cents=excluded.price_cents,effect_style=excluded.effect_style,asset_url=excluded.asset_url,asset_type=excluded.asset_type,kind='badge',source_type='badge',source_id=excluded.source_id,active=true;
  end loop;

  -- Avatares.
  for x in select * from (values
    ('Avatar Neon','assets/store/avatars/neon.png',500),
    ('Avatar Cósmico','assets/store/avatars/cosmic.png',500),
    ('Avatar Sombra','assets/store/avatars/shadow.png',600)
  ) v(name,asset,price)
  loop
    insert into public.premium_items(id,name,category,description,price_cents,price_coins,promo_active,icon,effect_style,asset_url,asset_type,kind,source_type,source_id,active)
    values('avatar-'||md5(x.name),x.name,'Avatares','Avatar oficial do novo estilo.',x.price,x.price,false,'👤','none',x.asset,'png','avatar','avatar',md5(x.name),true)
    on conflict(id) do update set name=excluded.name,category=excluded.category,description=excluded.description,price_coins=excluded.price_coins,price_cents=excluded.price_cents,asset_url=excluded.asset_url,asset_type=excluded.asset_type,kind='avatar',source_type='avatar',source_id=excluded.source_id,active=true;
  end loop;

  -- Backgrounds 800x500.
  for x in select * from (values
    ('Aurora','assets/store/backgrounds/aurora.png',400),
    ('Nebulosa','assets/store/backgrounds/nebula.png',400),
    ('Cyber Night','assets/store/backgrounds/cyber.png',450)
  ) v(name,asset,price)
  loop
    insert into public.premium_items(id,name,category,description,price_cents,price_coins,promo_active,icon,effect_style,asset_url,asset_type,kind,source_type,source_id,active)
    values('background-'||md5(x.name),x.name,'Fundos de Perfil','Fundo de perfil oficial 800 × 500.',x.price,x.price,false,'🖼️','none',x.asset,'png','background','background',md5(x.name),true)
    on conflict(id) do update set name=excluded.name,category=excluded.category,description=excluded.description,price_coins=excluded.price_coins,price_cents=excluded.price_cents,asset_url=excluded.asset_url,asset_type=excluded.asset_type,kind='background',source_type='background',source_id=excluded.source_id,active=true;
  end loop;
end $$;

-- ================================================================
-- 8) Regras para PNG de título.
-- ================================================================
alter table if exists public.titles add column if not exists asset_width integer;
alter table if exists public.titles add column if not exists asset_height integer;
update public.titles set asset_width=600,asset_height=160;

commit;

-- Conferência opcional:
select id,name,category,kind,price_coins,asset_url,active
from public.premium_items
where kind in ('avatar','badge','title','background')
order by category,name;
select oid::regprocedure::text from pg_proc
where pronamespace='public'::regnamespace
and proname in ('activate_premium_item','admin_remove_premium_item')
order by 1;


-- ================================================================
-- V39.3 — Conquistas com recompensa da Loja
-- ================================================================
-- Campos usados pelo painel para escolher qualquer produto da Loja.
alter table if exists public.achievements add column if not exists reward_type text;
alter table if exists public.achievements add column if not exists reward_item_id text;

-- Recompensa automática: ao desbloquear uma conquista, entrega o produto
-- escolhido no inventário do jogador. O produto NÃO precisa estar ativo na Loja
-- para ser entregue como prêmio; ele só precisa existir no catálogo.
create or replace function public.quizup_notify_achievement()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare
  a record;
  it public.premium_items;
  title_uuid uuid;
begin
  select title, description, icon, title_id, reward_type, reward_item_id
    into a
    from public.achievements
   where id=new.achievement_id;

  -- Título configurado diretamente na conquista.
  if a.title_id is not null then
    insert into public.user_titles(user_id,title_id,is_main)
    values(new.user_id,a.title_id,false)
    on conflict(user_id,title_id) do nothing;
  end if;

  -- Produto escolhido no catálogo da Loja.
  if coalesce(trim(a.reward_item_id),'')<>'' then
    select * into it
      from public.premium_items
     where id::text=trim(a.reward_item_id)
     limit 1;

    if it.id is not null then
      insert into public.user_premium_items(user_id,item_id,active,purchased_at)
      values(new.user_id,it.id,false,now())
      on conflict(user_id,item_id) do nothing;

      -- Se o prêmio for um título baseado na tabela titles, ele também passa
      -- a constar como título disponível no inventário de títulos.
      if it.kind='title'
         and coalesce(it.source_type,'')='title'
         and coalesce(it.source_id,'')<>'' then
        begin
          title_uuid:=it.source_id::uuid;
          insert into public.user_titles(user_id,title_id,is_main)
          values(new.user_id,title_uuid,false)
          on conflict(user_id,title_id) do nothing;
        exception when others then
          -- Um item de título pode existir sem uma origem UUID válida.
          null;
        end;
      end if;
    end if;
  end if;

  insert into public.notifications(recipient_id,actor_id,type,title,body,data)
  values(
    new.user_id,
    null,
    'achievement',
    coalesce(a.icon,'🏆')||' Conquista desbloqueada',
    case
      when coalesce(trim(a.reward_item_id),'')<>'' and it.id is not null
        then coalesce(a.description,a.title)||' • 🎁 Recompensa: '||it.name
      else coalesce(a.description,a.title)
    end,
    jsonb_build_object(
      'achievement_id',new.achievement_id,
      'title_id',a.title_id,
      'reward_type',a.reward_type,
      'reward_item_id',a.reward_item_id,
      'reward_item_name',case when it.id is not null then it.name else null end
    )
  );

  return new;
end $$;

-- Garante que toda conquista desbloqueada passe pelo mecanismo acima.
drop trigger if exists trg_quizup_notify_achievement on public.user_achievements;
create trigger trg_quizup_notify_achievement
after insert on public.user_achievements
for each row execute function public.quizup_notify_achievement();

-- Reavalia conquistas após uma partida e quando Coins/vitórias/sequência mudam.
create or replace function public.quizup_check_achievements(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  a record;
  value bigint;
begin
  for a in
    select id, code, criteria_type, threshold
      from public.achievements
     where active=true and code is not null
  loop
    value:=0;

    if a.criteria_type in ('games','first_game') then
      select count(*) into value
        from public.game_results
       where user_id=p_user_id;
    elsif a.criteria_type='wins' then
      select count(*) into value
        from public.game_results
       where user_id=p_user_id and won=true;
    elsif a.criteria_type='streak' then
      select coalesce(streak,0) into value
        from public.profiles where id=p_user_id;
    elsif a.criteria_type='coins' then
      select coalesce(coins,0) into value
        from public.profiles where id=p_user_id;
    end if;

    if value >= coalesce(a.threshold,1) then
      insert into public.user_achievements(user_id,achievement_id)
      values(p_user_id,a.id)
      on conflict(user_id,achievement_id) do nothing;
    end if;
  end loop;
end $$;

revoke all on function public.quizup_check_achievements(uuid) from public;
grant execute on function public.quizup_check_achievements(uuid) to authenticated;

-- Entrega manual de uma conquista pelo painel administrativo.
create or replace function public.admin_grant_player_achievement(
  p_user_id uuid,
  p_achievement_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
begin
  if not exists(select 1 from public.profiles where id=auth.uid() and role='admin') then
    raise exception 'Acesso negado';
  end if;

  if not exists(select 1 from public.profiles where id=p_user_id) then
    raise exception 'Jogador não encontrado';
  end if;

  if not exists(select 1 from public.achievements where id=p_achievement_id) then
    raise exception 'Conquista não encontrada';
  end if;

  insert into public.user_achievements(user_id,achievement_id)
  values(p_user_id,p_achievement_id)
  on conflict(user_id,achievement_id) do nothing;

  return jsonb_build_object('ok',true,'user_id',p_user_id,'achievement_id',p_achievement_id);
end $$;
revoke all on function public.admin_grant_player_achievement(uuid,uuid) from public;
grant execute on function public.admin_grant_player_achievement(uuid,uuid) to authenticated;

-- Entrega manual de qualquer produto do catálogo pelo painel.
create or replace function public.admin_grant_player_item(
  p_user_id uuid,
  p_item_id text
)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  item_id_value text:=trim(p_item_id);
  found_item public.premium_items;
begin
  if not exists(select 1 from public.profiles where id=auth.uid() and role='admin') then
    raise exception 'Acesso negado';
  end if;

  select * into found_item
    from public.premium_items
   where id::text=item_id_value
   limit 1;

  if found_item.id is null then
    raise exception 'Item da Loja não encontrado';
  end if;

  if not exists(select 1 from public.profiles where id=p_user_id) then
    raise exception 'Jogador não encontrado';
  end if;

  insert into public.user_premium_items(user_id,item_id,active,purchased_at)
  values(p_user_id,found_item.id,false,now())
  on conflict(user_id,item_id) do nothing;

  return jsonb_build_object('ok',true,'user_id',p_user_id,'item_id',found_item.id,'item_name',found_item.name);
end $$;
revoke all on function public.admin_grant_player_item(uuid,text) from public;
grant execute on function public.admin_grant_player_item(uuid,text) to authenticated;

