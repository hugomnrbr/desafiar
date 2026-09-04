-- QuizUp v39.0.4 — correção de RPCs e integridade
-- Execute este arquivo no Supabase DEPOIS da migration que já foi executada
-- (ou depois de corrigir o 23514 de effect_style).

begin;

-- 1) Campos de cosméticos que o código usa em profiles.
-- Alguns bancos antigos já possuem estes campos; IF NOT EXISTS mantém os dados.
alter table if exists public.profiles add column if not exists premium_frame text;
alter table if exists public.profiles add column if not exists premium_effect text;
alter table if exists public.profiles add column if not exists premium_theme text;
alter table if exists public.profiles add column if not exists premium_avatar text;
alter table if exists public.profiles add column if not exists premium_background text;
alter table if exists public.profiles add column if not exists premium_badge text;

-- 2) Normaliza valores antes das constraints. Isso evita novos 23514 em bases legadas.
update public.titles
set effect_style='none'
where effect_style is null
   or lower(trim(effect_style)) not in ('none','fire','water','earth','air','lightning','darkness','light','gold','silver','bronze','vip','diamond','ruby','emerald');
update public.titles set effect_style=lower(trim(effect_style));

update public.premium_items
set effect_style='none'
where effect_style is null
   or lower(trim(effect_style)) not in ('none','fire','water','earth','air','lightning','darkness','light','gold','silver','bronze','vip','diamond','ruby','emerald');
update public.premium_items set effect_style=lower(trim(effect_style));

update public.titles
set title_color='#ffd21a'
where title_color is null or title_color !~ '^#[0-9A-Fa-f]{6}$';
update public.premium_items
set title_color='#ffd21a'
where title_color is null or title_color !~ '^#[0-9A-Fa-f]{6}$';

update public.titles
set title_font='Inter'
where title_font is null or title_font not in ('Inter','Arial','Georgia','Trebuchet MS','Courier New','Impact','Verdana');
update public.premium_items
set title_font='Inter'
where title_font is null or title_font not in ('Inter','Arial','Georgia','Trebuchet MS','Courier New','Impact','Verdana');

alter table if exists public.titles drop constraint if exists titles_effect_style_check;
alter table if exists public.titles add constraint titles_effect_style_check
check (effect_style in ('none','fire','water','earth','air','lightning','darkness','light','gold','silver','bronze','vip','diamond','ruby','emerald'));

alter table if exists public.premium_items drop constraint if exists premium_items_effect_style_check;
alter table if exists public.premium_items add constraint premium_items_effect_style_check
check (effect_style in ('none','fire','water','earth','air','lightning','darkness','light','gold','silver','bronze','vip','diamond','ruby','emerald'));

-- 3) RPC de exclusão administrativa.
-- A versão anterior tinha DEFAULTs nos 3 argumentos. O PostgREST pode tentar
-- resolver a chamada como admin_remove_premium_item(text), causando 42883.
-- Agora mantemos uma assinatura exata de 3 argumentos + um wrapper de 1 argumento.
drop function if exists public.admin_remove_premium_item(text,text,text);
drop function if exists public.admin_remove_premium_item(text,text);
drop function if exists public.admin_remove_premium_item(text);

create function public.admin_remove_premium_item(
  p_item_id text,
  p_source_type text,
  p_source_id text
)
returns jsonb
language plpgsql security definer set search_path=public
as $$
declare
  it public.premium_items;
  removed_count bigint := 0;
  source_uuid uuid;
begin
  if not exists (
    select 1 from public.profiles
    where id=auth.uid() and role='admin'
  ) then
    raise exception 'Acesso negado';
  end if;

  if coalesce(trim(p_item_id),'')<>'' then
    select * into it
    from public.premium_items
    where id::text=trim(p_item_id)
    limit 1;
  else
    select * into it
    from public.premium_items
    where coalesce(source_type,'')=coalesce(p_source_type,'')
      and coalesce(source_id,'')=coalesce(p_source_id,'')
    limit 1;
  end if;

  if it.id is null then
    raise exception 'Item não encontrado';
  end if;

  delete from public.user_premium_items where item_id=it.id;
  get diagnostics removed_count=row_count;

  if it.kind='frame' then
    update public.profiles set premium_frame=null where premium_frame=it.id::text;
  elsif it.kind='avatar' then
    update public.profiles set premium_avatar=null where premium_avatar=it.id::text;
  elsif it.kind='effect' then
    update public.profiles set premium_effect=null where premium_effect=it.id::text;
  elsif it.kind='theme' then
    update public.profiles set premium_theme=null where premium_theme=it.id::text;
  elsif it.kind='background' then
    update public.profiles set premium_background=null where premium_background=it.id::text;
  elsif it.kind='badge' then
    update public.profiles set premium_badge=null where premium_badge=it.id::text;
  elsif it.kind='title' then
    update public.profiles set premium_title=null where premium_title=it.id::text;
  end if;

  if coalesce(it.source_type,'')='title' and coalesce(it.source_id,'')<>'' then
    begin
      source_uuid:=it.source_id::uuid;
      delete from public.user_titles where title_id=source_uuid;
      update public.profiles set main_title_id=null where main_title_id=source_uuid;
      update public.titles set active=false where id=source_uuid;
    exception when others then null;
    end;
  elsif coalesce(it.source_type,'')='badge' and coalesce(it.source_id,'')<>'' then
    begin
      source_uuid:=it.source_id::uuid;
      update public.badges set active=false where id=source_uuid;
    exception when others then null;
    end;
  end if;

  update public.premium_items set active=false where id=it.id;

  return jsonb_build_object(
    'ok',true,
    'item_id',it.id,
    'removed_from_inventory',removed_count
  );
end;
$$;

create function public.admin_remove_premium_item(p_item_id text)
returns jsonb
language sql security definer set search_path=public
as $$
  select public.admin_remove_premium_item(p_item_id, null::text, null::text);
$$;

revoke all on function public.admin_remove_premium_item(text,text,text) from public;
revoke all on function public.admin_remove_premium_item(text) from public;
grant execute on function public.admin_remove_premium_item(text,text,text) to authenticated;
grant execute on function public.admin_remove_premium_item(text) to authenticated;

-- 4) A policy de notícias precisa permitir que o dono faça UPDATE para marcar
-- a publicação como deleted (o app usa UPDATE, não DELETE físico).
drop policy if exists "social posts owner update" on public.social_posts;
create policy "social posts owner update" on public.social_posts
for update to authenticated
using(user_id=auth.uid() or public.is_admin())
with check(user_id=auth.uid() or public.is_admin());

commit;

-- Conferência rápida
select proname, oid::regprocedure::text
from pg_proc
where pronamespace='public'::regnamespace
  and proname='admin_remove_premium_item'
order by oid::regprocedure::text;
