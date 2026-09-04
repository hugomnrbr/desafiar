-- QuizUp v38.4 - artes de títulos/emblemas/conquistas, contas e avatar somente do inventário
-- Execute APÓS a migration v38. Não apaga partidas.

alter table if exists public.titles add column if not exists asset_url text;
alter table if exists public.titles add column if not exists asset_type text;
alter table if exists public.badges add column if not exists asset_url text;
alter table if exists public.badges add column if not exists asset_type text;
alter table if exists public.achievements add column if not exists asset_url text;
alter table if exists public.achievements add column if not exists asset_type text;

-- Usuários não podem mais usar foto própria como avatar. O avatar visual vem exclusivamente do inventário.
update public.profiles set avatar_url=null where avatar_url is not null;
create or replace function public.enforce_inventory_avatar()
returns trigger language plpgsql as $$
begin
  new.avatar_url := null;
  return new;
end $$;
drop trigger if exists trg_profiles_inventory_avatar on public.profiles;
create trigger trg_profiles_inventory_avatar before insert or update on public.profiles
for each row execute function public.enforce_inventory_avatar();

-- Bucket público para artes administradas pelo painel. Escrita somente para administradores.
insert into storage.buckets(id,name,public)
values('admin-assets','admin-assets',true)
on conflict(id) do update set public=true;

drop policy if exists "quizup admin assets public read" on storage.objects;
create policy "quizup admin assets public read" on storage.objects for select to public using(bucket_id='admin-assets');
drop policy if exists "quizup admin assets admin insert" on storage.objects;
create policy "quizup admin assets admin insert" on storage.objects for insert to authenticated
with check(bucket_id='admin-assets' and exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin'));
drop policy if exists "quizup admin assets admin update" on storage.objects;
create policy "quizup admin assets admin update" on storage.objects for update to authenticated
using(bucket_id='admin-assets' and exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin'))
with check(bucket_id='admin-assets' and exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin'));

-- RPC confiável para o painel listar todas as contas registradas, inclusive administradores.
drop function if exists public.admin_list_accounts();
create or replace function public.admin_list_accounts()
returns table(id uuid,username text,display_name text,email text,role text,created_at timestamptz)
language plpgsql security definer set search_path=public,auth as $$
begin
  if not exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin') then
    raise exception 'Acesso negado';
  end if;
  return query
    select p.id,p.username,p.display_name,u.email,p.role,u.created_at
    from public.profiles p
    left join auth.users u on u.id=p.id
    order by coalesce(u.created_at,p.created_at) desc;
end $$;
revoke all on function public.admin_list_accounts() from public;
grant execute on function public.admin_list_accounts() to authenticated;

-- Garantir que títulos/conquistas/emblemas podem ser vistos por jogadores autenticados.
alter table if exists public.badges enable row level security;
drop policy if exists "badges read active" on public.badges;
create policy "badges read active" on public.badges for select to authenticated
using(active=true or exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin'));
drop policy if exists "badges admin insert" on public.badges;
create policy "badges admin insert" on public.badges for insert to authenticated
with check(exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin'));
drop policy if exists "badges admin update" on public.badges;
create policy "badges admin update" on public.badges for update to authenticated
using(exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin'))
with check(exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin'));

alter table if exists public.achievements enable row level security;
drop policy if exists "achievements read active" on public.achievements;
create policy "achievements read active" on public.achievements for select to authenticated
using(active=true or exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin'));
drop policy if exists "achievements admin insert" on public.achievements;
create policy "achievements admin insert" on public.achievements for insert to authenticated
with check(exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin'));
drop policy if exists "achievements admin update" on public.achievements;
create policy "achievements admin update" on public.achievements for update to authenticated
using(exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin'))
with check(exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin'));
