-- QuizUp v38.8 - Fundos de Perfil (estáticos e animados)
-- Execute APÓS a migration v38.7. É idempotente.

alter table if exists public.premium_items add column if not exists asset_type text;
alter table if exists public.profiles add column if not exists premium_background text;

-- Categoria oficial da nova área da loja.
insert into public.store_categories(name,description,icon,sort_order,created_by)
values ('Fundos de Perfil','Fundos estáticos ou animados para o perfil do jogador.','🖼️',7,null)
on conflict(name) do update set description=excluded.description, icon=excluded.icon;

-- Regras do slot de fundo: somente o dono pode ativar um item que possui.
-- O fundo é salvo em profiles.premium_background para carregar também em perfis públicos.
do $$
declare r record;
begin
  for r in select oid::regprocedure::text as sig from pg_proc where pronamespace='public'::regnamespace and proname='activate_premium_item' loop
    execute 'drop function if exists '||r.sig||' cascade';
  end loop;
end $$;

create or replace function public.activate_premium_item(p_item_id text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare
  it public.premium_items;
  new_balance bigint;
begin
  if auth.uid() is null then raise exception 'Não autenticado'; end if;
  select * into it from public.premium_items where id::text=trim(p_item_id) and active=true limit 1;
  if it.id is null then raise exception 'Item não encontrado ou inativo'; end if;
  if not exists(select 1 from public.user_premium_items where user_id=auth.uid() and item_id=it.id) then
    raise exception 'Você ainda não possui este item';
  end if;

  -- Um item ativo por categoria/slot.
  update public.user_premium_items up
     set active=false
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
  elsif it.kind='title' then
    update public.profiles set premium_title=it.id::text where id=auth.uid();
  elsif it.kind='badge' then
    update public.profiles set premium_badge=it.id::text where id=auth.uid();
  elsif it.kind='vip' then
    update public.profiles set premium_vip=true where id=auth.uid();
  end if;

  select coins into new_balance from public.profiles where id=auth.uid();
  return jsonb_build_object('ok',true,'item_id',it.id,'kind',it.kind,'balance',coalesce(new_balance,0));
end $$;
revoke all on function public.activate_premium_item(text) from public;
grant execute on function public.activate_premium_item(text) to authenticated;

-- Mantém o comportamento para bases que ainda possuem a assinatura integer.
drop function if exists public.activate_premium_item(integer);
create or replace function public.activate_premium_item(p_item_id integer)
returns jsonb language sql security definer set search_path=public as $$
  select public.activate_premium_item(p_item_id::text);
$$;
revoke all on function public.activate_premium_item(integer) from public;
grant execute on function public.activate_premium_item(integer) to authenticated;
