-- QuizUp v38.5 - contas no painel + molduras com arte padronizada
-- Execute APÓS v38.4. Idempotente.

-- ================================================================
-- 1) Corrige a RPC das contas: não depende de profiles.created_at
-- ================================================================
drop function if exists public.admin_list_accounts();
create or replace function public.admin_list_accounts()
returns table(
  id uuid,
  username text,
  display_name text,
  email text,
  role text,
  created_at timestamptz
)
language plpgsql
security definer
set search_path=public,auth
as $$
begin
  if auth.uid() is null then raise exception 'Não autenticado'; end if;
  if not exists(select 1 from public.profiles p where p.id=auth.uid() and lower(coalesce(p.role,''))='admin') then
    raise exception 'Acesso negado';
  end if;
  return query
    select p.id,
           p.username::text,
           p.display_name::text,
           u.email::text,
           p.role::text,
           u.created_at
      from public.profiles p
      left join auth.users u on u.id=p.id
     order by u.created_at desc nulls last, p.username asc;
end $$;
revoke all on function public.admin_list_accounts() from public;
grant execute on function public.admin_list_accounts() to authenticated;

-- ================================================================
-- 2) Metadados padronizados das molduras
-- ================================================================
alter table if exists public.premium_items add column if not exists asset_width integer;
alter table if exists public.premium_items add column if not exists asset_height integer;
alter table if exists public.premium_items add column if not exists frame_inset_percent numeric(5,2);
alter table if exists public.premium_items add column if not exists frame_version text;

update public.premium_items
   set asset_width=coalesce(asset_width,256),
       asset_height=coalesce(asset_height,256),
       frame_inset_percent=coalesce(frame_inset_percent,0),
       frame_version=coalesce(frame_version,'v1')
 where kind='frame';

-- O arquivo da moldura é uma sobreposição transparente. O avatar fica por baixo.
-- Tamanho oficial do canvas: 256x256 px. A moldura deve deixar o centro transparente.

