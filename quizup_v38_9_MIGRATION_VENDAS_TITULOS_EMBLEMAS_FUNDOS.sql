-- QuizUp v38.9
-- Sistema unificado de venda/posse/ativação de Títulos, Emblemas e Fundos de Perfil.
-- Execute APÓS v38.8. É idempotente.

alter table if exists public.premium_items add column if not exists source_type text;
alter table if exists public.premium_items add column if not exists source_id text;

-- Mantém as categorias oficiais da loja.
insert into public.store_categories(name,description,icon,sort_order,created_by)
values
 ('Títulos','Títulos que o jogador pode comprar e equipar no perfil.','🏷️',4,null),
 ('Emblemas','Emblemas colecionáveis para a identidade do jogador.','🏅',6,null),
 ('Fundos de Perfil','Fundos estáticos ou animados para o perfil do jogador.','🖼️',8,null)
on conflict(name) do update set description=excluded.description, icon=excluded.icon, sort_order=excluded.sort_order;

-- Converte itens antigos criados diretamente pela Loja em objetos reais.
-- Assim nenhum título antigo fica preso ao ID `custom-...` no perfil.
insert into public.titles(name,description,icon,effect_style,active,created_by)
select distinct pi.name, pi.description, coalesce(nullif(pi.icon,''),'🏷️'), coalesce(pi.effect_style,'none'), true, pi.created_by
from public.premium_items pi
where pi.category='Títulos'
  and not exists(select 1 from public.titles t where lower(trim(t.name))=lower(trim(pi.name)));

insert into public.badges(name,description,icon,active,created_by)
select distinct pi.name, pi.description, '', true, pi.created_by
from public.premium_items pi
where pi.category in ('Emblemas','Badges')
  and not exists(select 1 from public.badges b where lower(trim(b.name))=lower(trim(pi.name)));

-- Vincula itens antigos da categoria Títulos/Emblemas pelo nome quando possível.
update public.premium_items pi
set source_type='title', source_id=t.id::text
from public.titles t
where coalesce(pi.source_type,'')='' and pi.category='Títulos' and lower(trim(pi.name))=lower(trim(t.name));

update public.premium_items pi
set source_type='badge', source_id=b.id::text
from public.badges b
where coalesce(pi.source_type,'')='' and pi.category in ('Emblemas','Badges') and lower(trim(pi.name))=lower(trim(b.name));

-- Entrega aos jogadores os títulos que já haviam sido comprados em versões anteriores.
insert into public.user_titles(user_id,title_id,is_main)
select up.user_id, t.id, false
from public.user_premium_items up
join public.premium_items pi on pi.id=up.item_id
join public.titles t on t.id::text=pi.source_id
where pi.kind='title' and pi.source_type='title'
on conflict(user_id,title_id) do nothing;

-- Se um título comprado estava ativo, ele vira o título principal.
update public.user_titles ut
set is_main=true
from public.user_premium_items up
join public.premium_items pi on pi.id=up.item_id
where ut.user_id=up.user_id
  and ut.title_id::text=pi.source_id
  and pi.kind='title'
  and pi.source_type='title'
  and up.active=true;

-- RPC de compra: além de debitar Coins, entrega o objeto real (principalmente títulos).
do $$
declare r record;
begin
  for r in select oid::regprocedure::text as sig
          from pg_proc
          where pronamespace='public'::regnamespace
            and proname='purchase_premium_item'
  loop
    execute 'drop function if exists '||r.sig||' cascade';
  end loop;
end $$;

create or replace function public.purchase_premium_item(p_item_id text,p_expected_price bigint default null)
returns jsonb language plpgsql security definer set search_path=public as $$
declare
  it public.premium_items;
  charge bigint;
  bal bigint;
  promo_ok boolean;
  title_uuid uuid;
  already boolean;
begin
  if auth.uid() is null then raise exception 'Não autenticado'; end if;

  select * into it
  from public.premium_items
  where id::text=trim(p_item_id) and active=true
  limit 1;
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

  select exists(select 1 from public.user_premium_items where user_id=auth.uid() and item_id=it.id) into already;

  if not already then
    update public.profiles
       set coins=coalesce(coins,0)-charge
     where id=auth.uid() and coalesce(coins,0)>=charge
     returning coins into bal;
    if bal is null then raise exception 'Você não possui QuizCoins suficientes'; end if;

    insert into public.user_premium_items(user_id,item_id,active,purchased_at)
    values(auth.uid(),it.id,true,now());

    insert into public.coin_ledger(user_id,amount,source_type,source_id,description)
    values(auth.uid(),-charge,'premium_purchase',gen_random_uuid()::text,'Compra: '||coalesce(it.name,'Item'));
  else
    select coins into bal from public.profiles where id=auth.uid();
  end if;

  -- Títulos são objetos reais em user_titles. Comprar já concede e equipa como principal.
  if it.kind='title' then
    title_uuid:=null;
    if coalesce(it.source_type,'')='title' and coalesce(it.source_id,'')<>'' then
      begin title_uuid:=it.source_id::uuid; exception when others then title_uuid:=null; end;
    end if;
    if title_uuid is null then
      select id into title_uuid from public.titles where lower(trim(name))=lower(trim(it.name)) and active=true limit 1;
    end if;
    if title_uuid is not null then
      insert into public.user_titles(user_id,title_id,is_main)
      values(auth.uid(),title_uuid,true)
      on conflict(user_id,title_id) do update set is_main=true;
      update public.user_titles set is_main=false where user_id=auth.uid() and title_id<>title_uuid;
      update public.profiles set main_title_id=title_uuid, premium_title=it.id::text where id=auth.uid();
    else
      update public.profiles set premium_title=it.id::text where id=auth.uid();
    end if;
  elsif it.kind='badge' then
    update public.profiles set premium_badge=it.id::text where id=auth.uid();
  elsif it.kind='background' then
    update public.profiles set premium_background=it.id::text where id=auth.uid();
  end if;

  return jsonb_build_object(
    'ok',true,
    'already_owned',already,
    'balance',coalesce(bal,0),
    'charge',case when already then 0 else charge end,
    'item_id',it.id,
    'kind',it.kind,
    'source_type',it.source_type,
    'source_id',it.source_id
  );
exception when unique_violation then
  select coins into bal from public.profiles where id=auth.uid();
  return jsonb_build_object('ok',true,'already_owned',true,'balance',coalesce(bal,0),'charge',0,'item_id',it.id,'kind',it.kind);
end $$;
revoke all on function public.purchase_premium_item(text,bigint) from public;
grant execute on function public.purchase_premium_item(text,bigint) to authenticated;

drop function if exists public.purchase_premium_item(integer);
create or replace function public.purchase_premium_item(p_item_id integer)
returns jsonb language sql security definer set search_path=public as $$
  select public.purchase_premium_item(p_item_id::text,null::bigint);
$$;
revoke all on function public.purchase_premium_item(integer) from public;
grant execute on function public.purchase_premium_item(integer) to authenticated;

-- Ativação também entende os vínculos oficiais.
do $$
declare r record;
begin
  for r in select oid::regprocedure::text as sig
          from pg_proc
          where pronamespace='public'::regnamespace
            and proname='activate_premium_item'
  loop
    execute 'drop function if exists '||r.sig||' cascade';
  end loop;
end $$;

create or replace function public.activate_premium_item(p_item_id text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare
  it public.premium_items;
  bal bigint;
  title_uuid uuid;
begin
  if auth.uid() is null then raise exception 'Não autenticado'; end if;
  select * into it from public.premium_items where id::text=trim(p_item_id) and active=true limit 1;
  if it.id is null then raise exception 'Item não encontrado ou inativo'; end if;
  if not exists(select 1 from public.user_premium_items where user_id=auth.uid() and item_id=it.id) then
    raise exception 'Você ainda não possui este item';
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
    title_uuid:=null;
    if coalesce(it.source_type,'')='title' and coalesce(it.source_id,'')<>'' then
      begin title_uuid:=it.source_id::uuid; exception when others then title_uuid:=null; end;
    end if;
    if title_uuid is null then
      select id into title_uuid from public.titles where lower(trim(name))=lower(trim(it.name)) and active=true limit 1;
    end if;
    if title_uuid is not null then
      insert into public.user_titles(user_id,title_id,is_main) values(auth.uid(),title_uuid,true)
      on conflict(user_id,title_id) do update set is_main=true;
      update public.user_titles set is_main=false where user_id=auth.uid() and title_id<>title_uuid;
      update public.profiles set main_title_id=title_uuid,premium_title=it.id::text where id=auth.uid();
    else
      update public.profiles set premium_title=it.id::text where id=auth.uid();
    end if;
  elsif it.kind='vip' then
    update public.profiles set premium_vip=true where id=auth.uid();
  end if;

  select coins into bal from public.profiles where id=auth.uid();
  return jsonb_build_object('ok',true,'item_id',it.id,'kind',it.kind,'source_type',it.source_type,'source_id',it.source_id,'balance',coalesce(bal,0));
end $$;
revoke all on function public.activate_premium_item(text) from public;
grant execute on function public.activate_premium_item(text) to authenticated;

create or replace function public.activate_premium_item(p_item_id integer)
returns jsonb language sql security definer set search_path=public as $$
  select public.activate_premium_item(p_item_id::text);
$$;
revoke all on function public.activate_premium_item(integer) from public;
grant execute on function public.activate_premium_item(integer) to authenticated;
