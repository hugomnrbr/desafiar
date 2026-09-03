-- QuizUp Mobile v6 - melhorias de usuários, perfis, amizades e perguntas
-- Execute DEPOIS do schema.sql/v5 no SQL Editor do Supabase.

-- 1) Nome de usuário único
alter table public.profiles add column if not exists username text;

-- Preenche usuários antigos com um nome derivado do display_name.
do $$
declare
  r record;
  base text;
  candidate text;
  n int;
begin
  for r in select id, display_name from public.profiles where username is null or trim(username)='' loop
    base := lower(regexp_replace(coalesce(r.display_name,'jogador'), '[^a-zA-Z0-9_]', '', 'g'));
    if base = '' then base := 'jogador'; end if;
    base := left(base, 16);
    candidate := base;
    n := 1;
    while exists(select 1 from public.profiles p where lower(p.username)=lower(candidate) and p.id<>r.id) loop
      candidate := left(base, 16) || n::text;
      n := n + 1;
    end loop;
    update public.profiles set username=candidate where id=r.id;
  end loop;
end $$;

alter table public.profiles alter column username set not null;
create unique index if not exists profiles_username_lower_idx on public.profiles(lower(username));
create index if not exists profiles_username_idx on public.profiles(username);

-- Foto de perfil
alter table public.profiles add column if not exists avatar_url text;

-- 2) Cadastro novo usando username + email + senha
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
declare
  desired text;
begin
  desired := lower(trim(coalesce(new.raw_user_meta_data->>'username','')));
  if desired = '' then
    desired := lower(regexp_replace(split_part(coalesce(new.email,''),'@',1), '[^a-zA-Z0-9_]', '', 'g'));
  end if;
  if desired = '' then desired := 'jogador'; end if;
  if exists(select 1 from public.profiles where lower(username)=lower(desired)) then
    raise exception 'Nome de usuário já está em uso';
  end if;

  insert into public.profiles(id,username,display_name,avatar_url)
  values(new.id,desired,desired,null)
  on conflict(id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users for each row execute procedure public.handle_new_user();

-- Consulta do e-mail pelo nome de usuário para permitir login com username.
-- Retorna somente o e-mail do username informado, sem listar outros usuários.
create or replace function public.get_login_email(p_username text)
returns text
language sql
security definer
set search_path=''
as $$
  select u.email
  from auth.users u
  join public.profiles p on p.id=u.id
  where lower(p.username)=lower(trim(p_username))
  limit 1;
$$;
revoke all on function public.get_login_email(text) from public;
grant execute on function public.get_login_email(text) to anon, authenticated;

-- 3) Amizade por username, evitando duplicidade nos dois sentidos.
create unique index if not exists friendships_pair_unique_idx
on public.friendships(least(requester_id,addressee_id), greatest(requester_id,addressee_id));

create or replace function public.send_friend_request(p_username text)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  uid uuid := auth.uid();
  target uuid;
  existing_status text;
  fid uuid;
begin
  if uid is null then raise exception 'Não autenticado'; end if;
  select id into target from public.profiles
  where lower(username)=lower(trim(p_username))
  limit 1;
  if target is null then raise exception 'Jogador não encontrado'; end if;
  if target=uid then raise exception 'Você não pode adicionar a si mesmo'; end if;

  select status,id into existing_status,fid
  from public.friendships
  where (requester_id=uid and addressee_id=target)
     or (requester_id=target and addressee_id=uid)
  limit 1;

  if fid is not null then
    return jsonb_build_object('ok',true,'existing',true,'status',existing_status,'id',fid);
  end if;

  insert into public.friendships(requester_id,addressee_id,status)
  values(uid,target,'pending')
  returning id into fid;
  return jsonb_build_object('ok',true,'existing',false,'status','pending','id',fid);
end;
$$;
revoke all on function public.send_friend_request(text) from public;
grant execute on function public.send_friend_request(text) to authenticated;

-- 4) Estatística da categoria mais jogada de cada jogador.
create or replace function public.get_most_played_category(p_user_id uuid)
returns text
language sql
security definer
set search_path=''
as $$
  select coalesce((
    select gr.category
    from public.game_results gr
    where gr.user_id=p_user_id
    group by gr.category
    order by count(*) desc, max(gr.created_at) desc
    limit 1
  ), 'Ainda não jogou');
$$;
revoke all on function public.get_most_played_category(uuid) from public;
grant execute on function public.get_most_played_category(uuid) to authenticated;

-- 5) Storage para fotos de perfil.
insert into storage.buckets(id,name,public)
values('avatars','avatars',true)
on conflict(id) do update set public=true;

drop policy if exists avatars_read on storage.objects;
drop policy if exists avatars_insert on storage.objects;
drop policy if exists avatars_update on storage.objects;
drop policy if exists avatars_delete on storage.objects;
create policy avatars_read on storage.objects for select to public
using(bucket_id='avatars');
create policy avatars_insert on storage.objects for insert to authenticated
with check(bucket_id='avatars' and (name like (auth.uid()::text || '/%')));
create policy avatars_update on storage.objects for update to authenticated
using(bucket_id='avatars' and (name like (auth.uid()::text || '/%')))
with check(bucket_id='avatars' and (name like (auth.uid()::text || '/%')));
create policy avatars_delete on storage.objects for delete to authenticated
using(bucket_id='avatars' and (name like (auth.uid()::text || '/%')));

-- 6) Permissões/índices para o painel e perfis.
grant update on public.profiles to authenticated;
notify pgrst, 'reload schema';

-- Permite carregar estatísticas públicas do perfil (categoria/resultado), sem expor e-mail ou senha.
drop policy if exists results_read on public.game_results;
create policy results_read on public.game_results for select to authenticated using(true);

notify pgrst, 'reload schema';
