-- QuizUp Mobile v5 - Supabase schema
-- Execute este arquivo no SQL Editor do Supabase.

create extension if not exists pgcrypto;

create table if not exists public.profiles(
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null unique,
  avatar_url text,
  level int not null default 1,
  xp int not null default 0,
  wins int not null default 0,
  losses int not null default 0,
  streak int not null default 0,
  role text not null default 'player' check(role in ('player','admin')),
  created_at timestamptz not null default now()
);

create table if not exists public.categories(
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  icon text default '🌐',
  description text,
  created_at timestamptz not null default now()
);

create table if not exists public.questions(
  id uuid primary key default gen_random_uuid(),
  category_id uuid references public.categories(id) on delete cascade,
  category_name text not null,
  question_text text not null,
  options jsonb not null,
  correct_index int not null check(correct_index between 0 and 3),
  image_url text,
  active boolean not null default true,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);

create table if not exists public.friendships(
  id uuid primary key default gen_random_uuid(),
  requester_id uuid not null references public.profiles(id) on delete cascade,
  addressee_id uuid not null references public.profiles(id) on delete cascade,
  status text not null default 'pending' check(status in ('pending','accepted','blocked')),
  created_at timestamptz not null default now(),
  unique(requester_id,addressee_id),
  check(requester_id<>addressee_id)
);

create table if not exists public.match_queue(
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  mode text not null check(mode in ('1v1','2v2')),
  category text not null,
  status text not null default 'waiting' check(status in ('waiting','matched','cancelled')),
  team_id uuid,
  created_at timestamptz not null default now()
);

create table if not exists public.matches(
  id uuid primary key default gen_random_uuid(),
  mode text not null check(mode in ('1v1','2v2')),
  category text not null,
  player_ids uuid[] not null default '{}',
  team_a uuid[] not null default '{}',
  team_b uuid[] not null default '{}',
  question_ids uuid[] not null default '{}',
  scores jsonb not null default '{}'::jsonb,
  answers jsonb not null default '{}'::jsonb,
  state jsonb not null default '{}'::jsonb,
  status text not null default 'waiting' check(status in ('waiting','ready','playing','finished','cancelled')),
  current_question int not null default 0,
  created_at timestamptz not null default now(),
  started_at timestamptz,
  finished_at timestamptz
);

-- Compatibilidade com instalações anteriores.
alter table public.matches add column if not exists question_ids uuid[] not null default '{}';
alter table public.matches add column if not exists scores jsonb not null default '{}'::jsonb;
alter table public.matches add column if not exists answers jsonb not null default '{}'::jsonb;
alter table public.matches add column if not exists state jsonb not null default '{}'::jsonb;
alter table public.matches add column if not exists started_at timestamptz;
alter table public.matches add column if not exists finished_at timestamptz;

create table if not exists public.game_results(
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  category text not null,
  mode text not null,
  score int not null default 0,
  won boolean not null default false,
  match_id uuid references public.matches(id) on delete set null,
  created_at timestamptz not null default now()
);
alter table public.game_results add column if not exists match_id uuid references public.matches(id) on delete set null;

create index if not exists profiles_xp_idx on public.profiles(xp desc);
create index if not exists queue_lookup_idx on public.match_queue(mode,category,status,created_at);
create unique index if not exists queue_user_waiting_idx on public.match_queue(user_id,mode,category) where status='waiting';
create index if not exists game_results_category_idx on public.game_results(category,score desc);
create index if not exists matches_players_idx on public.matches using gin(player_ids);

insert into public.categories(name,icon) values
('Geral','🌐'),('Ciência','⚗'),('Entretenimento','🎬'),('Esportes','⚽'),('História','🏛'),('Geografia','📍')
on conflict(name) do nothing;

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path=''
as $$
begin
  insert into public.profiles(id,display_name)
  values(new.id,coalesce(nullif(trim(new.raw_user_meta_data->>'display_name'),''),split_part(new.email,'@',1)))
  on conflict(id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users for each row execute procedure public.handle_new_user();

create or replace function public.apply_game_result(p_user_id uuid,p_category text,p_score int,p_won boolean)
returns void language plpgsql security definer set search_path=''
as $$
begin
  if p_user_id <> (select auth.uid()) then raise exception 'unauthorized'; end if;
  update public.profiles
  set xp=xp+greatest(p_score,0),
      wins=wins+case when p_won then 1 else 0 end,
      losses=losses+case when p_won then 0 else 1 end,
      streak=case when p_won then streak+1 else 0 end,
      level=greatest(1,1+floor((xp+greatest(p_score,0))/1000)::int)
  where id=p_user_id;
end;
$$;

-- Cria uma partida de verdade, com bloqueio transacional para evitar dois jogos usando o mesmo jogador.
create or replace function public.find_or_create_match(p_mode text, p_category text)
returns uuid
language plpgsql
security definer
set search_path=''
as $$
declare
  uid uuid := auth.uid();
  needed int := case when p_mode='2v2' then 4 else 2 end;
  ids uuid[];
  mid uuid;
  q record;
  qid uuid;
  qids uuid[];
  shuffled uuid[];
  team_a uuid[];
  team_b uuid[];
  first_id uuid;
  second_id uuid;
  seed int;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  if p_mode not in ('1v1','2v2') then raise exception 'invalid mode'; end if;
  if p_category is null or length(trim(p_category))=0 then raise exception 'invalid category'; end if;

  -- Se o jogador já tem partida ativa, devolve essa partida.
  select m.id into mid
  from public.matches m
  where uid = any(m.player_ids) and m.status in ('waiting','ready','playing')
  order by m.created_at desc limit 1;
  if mid is not null then return mid; end if;

  -- Registra o jogador na fila, sem duplicar sua entrada.
  if not exists (select 1 from public.match_queue mq where mq.user_id=uid and mq.mode=p_mode and mq.category=p_category and mq.status='waiting') then
    insert into public.match_queue(user_id,mode,category,status) values(uid,p_mode,p_category,'waiting');
  end if;

  ids := array[uid];
  for q in
    select mq.id,mq.user_id
    from public.match_queue mq
    where mq.mode=p_mode and mq.category=p_category and mq.status='waiting'
      and mq.user_id<>uid
    order by mq.created_at
    for update skip locked
  loop
    if array_length(ids,1) >= needed then exit; end if;
    if not (q.user_id = any(ids)) then ids := array_append(ids,q.user_id); end if;
  end loop;

  if array_length(ids,1) < needed then return null; end if;

  -- Perguntas da categoria. A partida só nasce quando temos 10 questões.
  select array_agg(x.id order by random()) into qids
  from (select id from public.questions where active=true and category_name=p_category order by random() limit 10) x;
  if coalesce(array_length(qids,1),0) < 10 then
    -- Para não bloquear a fila se a categoria ainda não tiver perguntas suficientes.
    return null;
  end if;

  shuffled := ids;
  first_id := shuffled[1]; second_id := shuffled[2];
  if p_mode='1v1' then
    team_a := array[first_id]; team_b := array[second_id];
  else
    -- Sorteio simples e transparente das equipes a cada partida.
    seed := floor(random()*1000000)::int;
    if seed % 2 = 0 then
      team_a := array[shuffled[1],shuffled[2]]; team_b := array[shuffled[3],shuffled[4]];
    else
      team_a := array[shuffled[1],shuffled[3]]; team_b := array[shuffled[2],shuffled[4]];
    end if;
  end if;

  insert into public.matches(mode,category,player_ids,team_a,team_b,question_ids,scores,answers,state,status)
  values(
    p_mode,p_category,ids,team_a,team_b,qids,
    (select jsonb_object_agg(x::text,0) from unnest(ids) x),
    '{}'::jsonb,
    jsonb_build_object('question_started_at',extract(epoch from clock_timestamp()),'answered',jsonb_build_object()),
    'playing'
  ) returning id into mid;

  update public.match_queue set status='matched' where user_id = any(ids) and mode=p_mode and category=p_category and status='waiting';
  update public.matches set started_at=now() where id=mid;
  return mid;
end;
$$;

-- Responde uma questão no servidor: o índice correto nunca é enviado pelo navegador.
create or replace function public.submit_match_answer(p_match_id uuid,p_question_index int,p_answer_index int,p_seconds int)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  uid uuid := auth.uid();
  m public.matches;
  q public.questions;
  old_score int;
  add_score int := 0;
  key text;
  new_scores jsonb;
  new_answers jsonb;
  done_count int;
  result jsonb;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  if p_seconds < 0 or p_seconds > 15 then raise exception 'invalid seconds'; end if;
  select * into m from public.matches where id=p_match_id for update;
  if m.id is null or not (uid=any(m.player_ids)) then raise exception 'match not found'; end if;
  if m.status <> 'playing' then raise exception 'match is not playing'; end if;
  if p_question_index <> m.current_question then raise exception 'question out of sync'; end if;
  if p_answer_index < -1 or p_answer_index > 3 then raise exception 'invalid answer'; end if;

  key := uid::text || ':' || p_question_index::text;
  if (m.answers ? key) then
    return jsonb_build_object('ok',true,'already_answered',true,'score',coalesce((m.scores->>uid::text)::int,0),'finished',m.status='finished');
  end if;

  if array_length(m.question_ids,1) is null or p_question_index+1 > array_length(m.question_ids,1) then raise exception 'question missing'; end if;
  select * into q from public.questions where id=m.question_ids[p_question_index+1];
  if q.id is null then raise exception 'question missing'; end if;

  if p_answer_index=q.correct_index then add_score := least(greatest(p_seconds,0),10); end if;
  old_score := coalesce((m.scores->>uid::text)::int,0);
  new_scores := jsonb_set(m.scores, array[uid::text], to_jsonb(old_score+add_score), true);
  new_answers := jsonb_set(m.answers, array[key], jsonb_build_object('answer',p_answer_index,'correct',p_answer_index=q.correct_index,'score',add_score), true);

  -- Avança a pergunta apenas quando todos os jogadores responderam.
  select count(*) into done_count
  from jsonb_object_keys(new_answers) k
  where split_part(k,':',2)=p_question_index::text;

  if done_count >= array_length(m.player_ids,1) then
    if p_question_index >= array_length(m.question_ids,1)-1 then
      update public.matches set scores=new_scores,answers=new_answers,status='finished',finished_at=now() where id=m.id;
      result := jsonb_build_object('ok',true,'score',old_score+add_score,'added',add_score,'finished',true,'scores',new_scores);
    else
      update public.matches set scores=new_scores,answers=new_answers,current_question=p_question_index+1,state=jsonb_build_object('question_started_at',extract(epoch from clock_timestamp())) where id=m.id;
      result := jsonb_build_object('ok',true,'score',old_score+add_score,'added',add_score,'finished',false,'next_question',p_question_index+1,'scores',new_scores);
    end if;
  else
    update public.matches set scores=new_scores,answers=new_answers where id=m.id;
    result := jsonb_build_object('ok',true,'score',old_score+add_score,'added',add_score,'finished',false,'waiting',true,'scores',new_scores);
  end if;
  return result;
end;
$$;

create or replace function public.cancel_match_queue()
returns void language plpgsql security definer set search_path=''
as $$
begin
  delete from public.match_queue where user_id=auth.uid() and status='waiting';
end;
$$;

alter table public.profiles enable row level security;
alter table public.categories enable row level security;
alter table public.questions enable row level security;
alter table public.friendships enable row level security;
alter table public.match_queue enable row level security;
alter table public.matches enable row level security;
alter table public.game_results enable row level security;

revoke all on public.profiles,public.categories,public.questions,public.friendships,public.match_queue,public.matches,public.game_results from anon;
grant select on public.profiles,public.categories,public.questions to authenticated;
grant select,insert,update,delete on public.friendships to authenticated;
grant select on public.match_queue to authenticated;
grant select on public.matches to authenticated;
grant insert on public.game_results to authenticated;
grant insert,update,delete on public.categories,public.questions to authenticated;
grant execute on function public.apply_game_result(uuid,text,int,boolean) to authenticated;
grant execute on function public.find_or_create_match(text,text) to authenticated;
grant execute on function public.submit_match_answer(uuid,int,int,int) to authenticated;
grant execute on function public.cancel_match_queue() to authenticated;

-- Evita erro ao rodar o arquivo novamente.
drop policy if exists profiles_read on public.profiles;
drop policy if exists profiles_self on public.profiles;
drop policy if exists categories_read on public.categories;
drop policy if exists categories_admin_insert on public.categories;
drop policy if exists categories_admin_update on public.categories;
drop policy if exists categories_admin_delete on public.categories;
drop policy if exists questions_read on public.questions;
drop policy if exists questions_admin_insert on public.questions;
drop policy if exists questions_admin_update on public.questions;
drop policy if exists questions_admin_delete on public.questions;
drop policy if exists friendships_own on public.friendships;
drop policy if exists queue_read on public.match_queue;
drop policy if exists matches_member_read on public.matches;
drop policy if exists results_insert on public.game_results;
drop policy if exists results_read on public.game_results;

create policy profiles_read on public.profiles for select to authenticated using(true);
create policy profiles_self on public.profiles for update to authenticated using((select auth.uid())=id) with check((select auth.uid())=id);
create policy categories_read on public.categories for select to authenticated using(true);
create policy categories_admin_insert on public.categories for insert to authenticated with check(exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='admin'));
create policy categories_admin_update on public.categories for update to authenticated using(exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='admin')) with check(exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='admin'));
create policy categories_admin_delete on public.categories for delete to authenticated using(exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='admin'));
create policy questions_read on public.questions for select to authenticated using(active=true or exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='admin'));
create policy questions_admin_insert on public.questions for insert to authenticated with check(exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='admin'));
create policy questions_admin_update on public.questions for update to authenticated using(exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='admin')) with check(exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='admin'));
create policy questions_admin_delete on public.questions for delete to authenticated using(exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='admin'));
create policy friendships_own on public.friendships for all to authenticated using(requester_id=(select auth.uid()) or addressee_id=(select auth.uid())) with check(requester_id=(select auth.uid()) or addressee_id=(select auth.uid()));
create policy queue_read on public.match_queue for select to authenticated using(user_id=(select auth.uid()));
create policy matches_member_read on public.matches for select to authenticated using((select auth.uid())=any(player_ids));
create policy results_insert on public.game_results for insert to authenticated with check(user_id=(select auth.uid()));
create policy results_read on public.game_results for select to authenticated using(user_id=(select auth.uid()));

insert into storage.buckets(id,name,public) values('question-images','question-images',true) on conflict(id) do update set public=true;
drop policy if exists question_images_read on storage.objects;
drop policy if exists question_images_insert on storage.objects;
drop policy if exists question_images_delete on storage.objects;
create policy question_images_read on storage.objects for select to public using(bucket_id='question-images');
create policy question_images_insert on storage.objects for insert to authenticated with check(bucket_id='question-images' and exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='admin'));
create policy question_images_delete on storage.objects for delete to authenticated using(bucket_id='question-images' and exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='admin'));

-- Realtime: partida e amizades chegam ao navegador imediatamente.
do $$
begin
  begin alter publication supabase_realtime add table public.matches; exception when duplicate_object then null; end;
  begin alter publication supabase_realtime add table public.friendships; exception when duplicate_object then null; end;
end $$;

notify pgrst, 'reload schema';
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
-- QuizUp Mobile v6 - 300 perguntas iniciais (50 por categoria)
-- Pode ser executado depois do schema.sql e do upgrade-v6.sql.


-- Geral: 50 perguntas
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Geral','Qual é a capital do Brasil?','["Brasília","Rio de Janeiro","São Paulo","Salvador"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='Geral' and q.question_text='Qual é a capital do Brasil?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Geral','Qual é o maior planeta do Sistema Solar?','["Terra","Marte","Júpiter","Saturno"]'::jsonb,2,true 
where not exists (select 1 from public.questions q where q.category_name='Geral' and q.question_text='Qual é o maior planeta do Sistema Solar?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Geral','Quantos dias tem uma semana?','["5","6","7","8"]'::jsonb,2,true 
where not exists (select 1 from public.questions q where q.category_name='Geral' and q.question_text='Quantos dias tem uma semana?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Geral','Qual é o idioma mais falado no Brasil?','["Espanhol","Português","Inglês","Francês"]'::jsonb,1,true 
where not exists (select 1 from public.questions q where q.category_name='Geral' and q.question_text='Qual é o idioma mais falado no Brasil?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Geral','Qual é o satélite natural da Terra?','["Sol","Lua","Marte","Vênus"]'::jsonb,1,true 
where not exists (select 1 from public.questions q where q.category_name='Geral' and q.question_text='Qual é o satélite natural da Terra?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Geral','Quantos meses tem um ano?','["10","11","12","13"]'::jsonb,2,true 
where not exists (select 1 from public.questions q where q.category_name='Geral' and q.question_text='Quantos meses tem um ano?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Geral','Qual animal é conhecido como rei da selva?','["Tigre","Leão","Elefante","Lobo"]'::jsonb,1,true 
where not exists (select 1 from public.questions q where q.category_name='Geral' and q.question_text='Qual animal é conhecido como rei da selva?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Geral','Qual é o maior oceano da Terra?','["Atlântico","Índico","Pacífico","Ártico"]'::jsonb,2,true 
where not exists (select 1 from public.questions q where q.category_name='Geral' and q.question_text='Qual é o maior oceano da Terra?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Geral','Qual instrumento mede a temperatura?','["Barômetro","Termômetro","Higrômetro","Bússola"]'::jsonb,1,true 
where not exists (select 1 from public.questions q where q.category_name='Geral' and q.question_text='Qual instrumento mede a temperatura?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Geral','Qual é a moeda oficial do Japão?','["Won","Yuan","Iene","Rúpia"]'::jsonb,2,true 
where not exists (select 1 from public.questions q where q.category_name='Geral' and q.question_text='Qual é a moeda oficial do Japão?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Geral','Quantas cores há na bandeira do Brasil?','["3","4","5","6"]'::jsonb,1,true 
where not exists (select 1 from public.questions q where q.category_name='Geral' and q.question_text='Quantas cores há na bandeira do Brasil?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Geral','Qual é o continente onde fica o Brasil?','["Ásia","África","América do Sul","Europa"]'::jsonb,2,true 
where not exists (select 1 from public.questions q where q.category_name='Geral' and q.question_text='Qual é o continente onde fica o Brasil?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Geral','Quem escreveu Dom Casmurro?','["José de Alencar","Machado de Assis","Carlos Drummond","Monteiro Lobato"]'::jsonb,1,true 
where not exists (select 1 from public.questions q where q.category_name='Geral' and q.question_text='Quem escreveu Dom Casmurro?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Geral','Qual é o maior mamífero do mundo?','["Elefante-africano","Baleia-azul","Girafa","Orca"]'::jsonb,1,true 
where not exists (select 1 from public.questions q where q.category_name='Geral' and q.question_text='Qual é o maior mamífero do mundo?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Geral','Quantos lados tem um hexágono?','["5","6","7","8"]'::jsonb,1,true 
where not exists (select 1 from public.questions q where q.category_name='Geral' and q.question_text='Quantos lados tem um hexágono?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Geral','Qual é o símbolo químico do ouro?','["Ag","Au","Fe","O"]'::jsonb,1,true 
where not exists (select 1 from public.questions q where q.category_name='Geral' and q.question_text='Qual é o símbolo químico do ouro?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Geral','Qual planeta é conhecido como Planeta Vermelho?','["Vênus","Marte","Júpiter","Mercúrio"]'::jsonb,1,true 
where not exists (select 1 from public.questions q where q.category_name='Geral' and q.question_text='Qual planeta é conhecido como Planeta Vermelho?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Geral','Qual é a capital da França?','["Paris","Roma","Lisboa","Berlim"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='Geral' and q.question_text='Qual é a capital da França?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Geral','Quantos minutos há em uma hora?','["30","45","60","90"]'::jsonb,2,true 
where not exists (select 1 from public.questions q where q.category_name='Geral' and q.question_text='Quantos minutos há em uma hora?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Geral','Qual é o maior país do mundo em área?','["Canadá","China","Rússia","Brasil"]'::jsonb,2,true 
where not exists (select 1 from public.questions q where q.category_name='Geral' and q.question_text='Qual é o maior país do mundo em área?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Geral','Qual destes é um mamífero?','["Tubarão","Golfinho","Pinguim","Tartaruga"]'::jsonb,1,true 
where not exists (select 1 from public.questions q where q.category_name='Geral' and q.question_text='Qual destes é um mamífero?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Geral','Qual é o número romano para 50?','["L","C","X","V"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='Geral' and q.question_text='Qual é o número romano para 50?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Geral','Qual é a capital de Portugal?','["Porto","Lisboa","Coimbra","Braga"]'::jsonb,1,true 
where not exists (select 1 from public.questions q where q.category_name='Geral' and q.question_text='Qual é a capital de Portugal?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Geral','Quantos lados tem um triângulo?','["2","3","4","5"]'::jsonb,1,true 
where not exists (select 1 from public.questions q where q.category_name='Geral' and q.question_text='Quantos lados tem um triângulo?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Geral','Qual é o metal líquido em temperatura ambiente?','["Ferro","Mercúrio","Cobre","Alumínio"]'::jsonb,1,true 
where not exists (select 1 from public.questions q where q.category_name='Geral' and q.question_text='Qual é o metal líquido em temperatura ambiente?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Geral','Qual é a cor formada pela mistura de azul e amarelo?','["Roxo","Verde","Laranja","Rosa"]'::jsonb,1,true 
where not exists (select 1 from public.questions q where q.category_name='Geral' and q.question_text='Qual é a cor formada pela mistura de azul e amarelo?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Geral','Qual é o maior órgão do corpo humano?','["Coração","Fígado","Pele","Pulmão"]'::jsonb,2,true 
where not exists (select 1 from public.questions q where q.category_name='Geral' and q.question_text='Qual é o maior órgão do corpo humano?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Geral','Em qual direção o Sol nasce?','["Norte","Sul","Leste","Oeste"]'::jsonb,2,true 
where not exists (select 1 from public.questions q where q.category_name='Geral' and q.question_text='Em qual direção o Sol nasce?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Geral','Qual é a capital da Argentina?','["Santiago","Buenos Aires","Montevidéu","Lima"]'::jsonb,1,true 
where not exists (select 1 from public.questions q where q.category_name='Geral' and q.question_text='Qual é a capital da Argentina?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Geral','Quantos segundos tem um minuto?','["30","45","60","90"]'::jsonb,2,true 
where not exists (select 1 from public.questions q where q.category_name='Geral' and q.question_text='Quantos segundos tem um minuto?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Geral','Qual é o gás mais abundante na atmosfera terrestre?','["Oxigênio","Nitrogênio","Hélio","Dióxido de carbono"]'::jsonb,1,true 
where not exists (select 1 from public.questions q where q.category_name='Geral' and q.question_text='Qual é o gás mais abundante na atmosfera terrestre?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Geral','Qual destes é um instrumento musical?','["Violino","Martelo","Bússola","Microscópio"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='Geral' and q.question_text='Qual destes é um instrumento musical?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Geral','Qual é a estrela mais próxima da Terra?','["Sirius","Sol","Vega","Polaris"]'::jsonb,1,true 
where not exists (select 1 from public.questions q where q.category_name='Geral' and q.question_text='Qual é a estrela mais próxima da Terra?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Geral','Qual é a capital da Itália?','["Milão","Roma","Nápoles","Veneza"]'::jsonb,1,true 
where not exists (select 1 from public.questions q where q.category_name='Geral' and q.question_text='Qual é a capital da Itália?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Geral','Quantos jogadores um time de futebol começa em campo?','["9","10","11","12"]'::jsonb,2,true 
where not exists (select 1 from public.questions q where q.category_name='Geral' and q.question_text='Quantos jogadores um time de futebol começa em campo?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Geral','Qual é o formato aproximado da Terra?','["Cúbico","Esférico","Triangular","Plano"]'::jsonb,1,true 
where not exists (select 1 from public.questions q where q.category_name='Geral' and q.question_text='Qual é o formato aproximado da Terra?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Geral','Qual é a língua oficial do México?','["Português","Espanhol","Inglês","Italiano"]'::jsonb,1,true 
where not exists (select 1 from public.questions q where q.category_name='Geral' and q.question_text='Qual é a língua oficial do México?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Geral','Qual destes animais põe ovos?','["Cachorro","Gato","Ornitorrinco","Cavalo"]'::jsonb,2,true 
where not exists (select 1 from public.questions q where q.category_name='Geral' and q.question_text='Qual destes animais põe ovos?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Geral','Qual é o maior deserto quente do mundo?','["Saara","Atacama","Gobi","Kalahari"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='Geral' and q.question_text='Qual é o maior deserto quente do mundo?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Geral','Qual é a capital do Chile?','["Santiago","Lima","Quito","Bogotá"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='Geral' and q.question_text='Qual é a capital do Chile?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Geral','Qual destes alimentos é produzido pelas abelhas?','["Leite","Mel","Farinha","Queijo"]'::jsonb,1,true 
where not exists (select 1 from public.questions q where q.category_name='Geral' and q.question_text='Qual destes alimentos é produzido pelas abelhas?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Geral','Qual é a unidade básica da vida?','["Átomo","Célula","Órgão","Tecido"]'::jsonb,1,true 
where not exists (select 1 from public.questions q where q.category_name='Geral' and q.question_text='Qual é a unidade básica da vida?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Geral','Qual é o plural de ''cidadão''?','["Cidadãos","Cidadões","Cidadães","Cidadãns"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='Geral' and q.question_text='Qual é o plural de ''cidadão''?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Geral','Qual é a capital do Canadá?','["Toronto","Vancouver","Ottawa","Montreal"]'::jsonb,2,true 
where not exists (select 1 from public.questions q where q.category_name='Geral' and q.question_text='Qual é a capital do Canadá?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Geral','Qual é o maior continente em área?','["África","Ásia","Europa","América do Norte"]'::jsonb,1,true 
where not exists (select 1 from public.questions q where q.category_name='Geral' and q.question_text='Qual é o maior continente em área?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Geral','Qual é a cor resultante da mistura de vermelho e branco?','["Rosa","Marrom","Verde","Cinza"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='Geral' and q.question_text='Qual é a cor resultante da mistura de vermelho e branco?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Geral','Qual é o símbolo químico do ferro?','["Fe","Fr","Ir","F"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='Geral' and q.question_text='Qual é o símbolo químico do ferro?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Geral','Qual é a principal estrela do Sistema Solar?','["Lua","Sol","Júpiter","Sirius"]'::jsonb,1,true 
where not exists (select 1 from public.questions q where q.category_name='Geral' and q.question_text='Qual é a principal estrela do Sistema Solar?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Geral','Quantos graus tem um ângulo reto?','["45","90","120","180"]'::jsonb,1,true 
where not exists (select 1 from public.questions q where q.category_name='Geral' and q.question_text='Quantos graus tem um ângulo reto?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Geral','Qual é o maior planeta rochoso do Sistema Solar?','["Mercúrio","Vênus","Terra","Marte"]'::jsonb,2,true 
where not exists (select 1 from public.questions q where q.category_name='Geral' and q.question_text='Qual é o maior planeta rochoso do Sistema Solar?');

-- Ciência: 50 perguntas
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Ciência','Qual gás as plantas absorvem principalmente na fotossíntese?','["Oxigênio","Nitrogênio","Dióxido de carbono","Hélio"]'::jsonb,2,true 
where not exists (select 1 from public.questions q where q.category_name='Ciência' and q.question_text='Qual gás as plantas absorvem principalmente na fotossíntese?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Ciência','Qual é a fórmula da água?','["CO2","H2O","O2","NaCl"]'::jsonb,1,true 
where not exists (select 1 from public.questions q where q.category_name='Ciência' and q.question_text='Qual é a fórmula da água?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Ciência','Qual órgão bombeia o sangue?','["Pulmão","Coração","Rim","Fígado"]'::jsonb,1,true 
where not exists (select 1 from public.questions q where q.category_name='Ciência' and q.question_text='Qual órgão bombeia o sangue?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Ciência','Qual é a unidade de força no SI?','["Joule","Watt","Newton","Pascal"]'::jsonb,2,true 
where not exists (select 1 from public.questions q where q.category_name='Ciência' and q.question_text='Qual é a unidade de força no SI?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Ciência','Qual planeta é o mais próximo do Sol?','["Vênus","Mercúrio","Terra","Marte"]'::jsonb,1,true 
where not exists (select 1 from public.questions q where q.category_name='Ciência' and q.question_text='Qual planeta é o mais próximo do Sol?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Ciência','Qual partícula tem carga elétrica negativa?','["Próton","Nêutron","Elétron","Núcleo"]'::jsonb,2,true 
where not exists (select 1 from public.questions q where q.category_name='Ciência' and q.question_text='Qual partícula tem carga elétrica negativa?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Ciência','Qual é o centro do átomo?','["Elétron","Núcleo","Molécula","Célula"]'::jsonb,1,true 
where not exists (select 1 from public.questions q where q.category_name='Ciência' and q.question_text='Qual é o centro do átomo?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Ciência','Qual vitamina é produzida na pele com ajuda da luz solar?','["Vitamina A","Vitamina C","Vitamina D","Vitamina K"]'::jsonb,2,true 
where not exists (select 1 from public.questions q where q.category_name='Ciência' and q.question_text='Qual vitamina é produzida na pele com ajuda da luz solar?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Ciência','Qual é o maior órgão interno do corpo humano?','["Cérebro","Fígado","Pulmão","Rim"]'::jsonb,1,true 
where not exists (select 1 from public.questions q where q.category_name='Ciência' and q.question_text='Qual é o maior órgão interno do corpo humano?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Ciência','Qual processo transforma líquido em vapor?','["Condensação","Evaporação","Fusão","Solidificação"]'::jsonb,1,true 
where not exists (select 1 from public.questions q where q.category_name='Ciência' and q.question_text='Qual processo transforma líquido em vapor?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Ciência','Qual processo transforma vapor em líquido?','["Evaporação","Condensação","Sublimação","Fusão"]'::jsonb,1,true 
where not exists (select 1 from public.questions q where q.category_name='Ciência' and q.question_text='Qual processo transforma vapor em líquido?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Ciência','Qual é a velocidade aproximada da luz no vácuo?','["30 mil km/s","300 mil km/s","3 milhões km/s","3 mil km/s"]'::jsonb,1,true 
where not exists (select 1 from public.questions q where q.category_name='Ciência' and q.question_text='Qual é a velocidade aproximada da luz no vácuo?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Ciência','Qual é o planeta conhecido por seus anéis mais visíveis?','["Saturno","Marte","Mercúrio","Terra"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='Ciência' and q.question_text='Qual é o planeta conhecido por seus anéis mais visíveis?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Ciência','Qual sistema do corpo é responsável pelas trocas gasosas?','["Digestório","Respiratório","Nervoso","Endócrino"]'::jsonb,1,true 
where not exists (select 1 from public.questions q where q.category_name='Ciência' and q.question_text='Qual sistema do corpo é responsável pelas trocas gasosas?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Ciência','Qual é a unidade de temperatura no SI?','["Celsius","Kelvin","Fahrenheit","Joule"]'::jsonb,1,true 
where not exists (select 1 from public.questions q where q.category_name='Ciência' and q.question_text='Qual é a unidade de temperatura no SI?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Ciência','Qual força mantém os planetas em órbita?','["Atrito","Gravidade","Eletricidade","Magnetismo"]'::jsonb,1,true 
where not exists (select 1 from public.questions q where q.category_name='Ciência' and q.question_text='Qual força mantém os planetas em órbita?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Ciência','Qual é o pH de uma solução neutra a 25 °C?','["0","5","7","14"]'::jsonb,2,true 
where not exists (select 1 from public.questions q where q.category_name='Ciência' and q.question_text='Qual é o pH de uma solução neutra a 25 °C?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Ciência','Qual metal tem símbolo Fe?','["Ferro","Flúor","Frâncio","Fósforo"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='Ciência' and q.question_text='Qual metal tem símbolo Fe?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Ciência','Qual é a menor unidade de um elemento químico?','["Célula","Átomo","Tecido","Órgão"]'::jsonb,1,true 
where not exists (select 1 from public.questions q where q.category_name='Ciência' and q.question_text='Qual é a menor unidade de um elemento químico?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Ciência','Qual estrutura celular contém o material genético em células eucarióticas?','["Ribossomo","Núcleo","Lisossomo","Membrana"]'::jsonb,1,true 
where not exists (select 1 from public.questions q where q.category_name='Ciência' and q.question_text='Qual estrutura celular contém o material genético em células eucarióticas?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Ciência','Qual é o nome do processo de divisão celular que gera duas células geneticamente semelhantes?','["Meiose","Mitose","Mutação","Fecundação"]'::jsonb,1,true 
where not exists (select 1 from public.questions q where q.category_name='Ciência' and q.question_text='Qual é o nome do processo de divisão celular que gera duas células geneticamente semelhantes?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Ciência','Qual molécula carrega grande parte da energia usada pelas células?','["DNA","ATP","RNA","Glicose"]'::jsonb,1,true 
where not exists (select 1 from public.questions q where q.category_name='Ciência' and q.question_text='Qual molécula carrega grande parte da energia usada pelas células?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Ciência','Qual planeta é o maior do Sistema Solar?','["Saturno","Júpiter","Netuno","Urano"]'::jsonb,1,true 
where not exists (select 1 from public.questions q where q.category_name='Ciência' and q.question_text='Qual planeta é o maior do Sistema Solar?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Ciência','Qual é a camada da atmosfera onde ocorre a maior parte do clima?','["Estratosfera","Troposfera","Mesosfera","Termosfera"]'::jsonb,1,true 
where not exists (select 1 from public.questions q where q.category_name='Ciência' and q.question_text='Qual é a camada da atmosfera onde ocorre a maior parte do clima?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Ciência','Qual instrumento é usado para observar objetos muito distantes no espaço?','["Microscópio","Telescópio","Barômetro","Espectrômetro"]'::jsonb,1,true 
where not exists (select 1 from public.questions q where q.category_name='Ciência' and q.question_text='Qual instrumento é usado para observar objetos muito distantes no espaço?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Ciência','Qual é a ciência que estuda os seres vivos?','["Geologia","Biologia","Astronomia","Física"]'::jsonb,1,true 
where not exists (select 1 from public.questions q where q.category_name='Ciência' and q.question_text='Qual é a ciência que estuda os seres vivos?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Ciência','Qual é a ciência que estuda a matéria e suas transformações?','["Química","Geografia","Ecologia","Botânica"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='Ciência' and q.question_text='Qual é a ciência que estuda a matéria e suas transformações?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Ciência','Qual é a ciência que estuda os astros e o universo?','["Astronomia","Anatomia","Genética","Oceanografia"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='Ciência' and q.question_text='Qual é a ciência que estuda os astros e o universo?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Ciência','Qual é a unidade básica da hereditariedade?','["Gene","Átomo","Enzima","Tecido"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='Ciência' and q.question_text='Qual é a unidade básica da hereditariedade?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Ciência','Qual é o nome do pigmento verde das plantas?','["Hemoglobina","Clorofila","Melanina","Queratina"]'::jsonb,1,true 
where not exists (select 1 from public.questions q where q.category_name='Ciência' and q.question_text='Qual é o nome do pigmento verde das plantas?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Ciência','Qual é o principal componente do ar atmosférico?','["Oxigênio","Nitrogênio","Argônio","CO2"]'::jsonb,1,true 
where not exists (select 1 from public.questions q where q.category_name='Ciência' and q.question_text='Qual é o principal componente do ar atmosférico?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Ciência','Qual órgão é responsável principalmente pela filtragem do sangue e produção de urina?','["Rim","Estômago","Pulmão","Pâncreas"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='Ciência' and q.question_text='Qual órgão é responsável principalmente pela filtragem do sangue e produção de urina?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Ciência','Qual é o nome da passagem do estado sólido diretamente para o gasoso?','["Fusão","Sublimação","Condensação","Ebulição"]'::jsonb,1,true 
where not exists (select 1 from public.questions q where q.category_name='Ciência' and q.question_text='Qual é o nome da passagem do estado sólido diretamente para o gasoso?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Ciência','Qual é a unidade de potência no SI?','["Watt","Newton","Volt","Ohm"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='Ciência' and q.question_text='Qual é a unidade de potência no SI?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Ciência','Qual instrumento mede a pressão atmosférica?','["Barômetro","Termômetro","Balança","Calorímetro"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='Ciência' and q.question_text='Qual instrumento mede a pressão atmosférica?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Ciência','Qual é a unidade de corrente elétrica no SI?','["Volt","Ampere","Ohm","Watt"]'::jsonb,1,true 
where not exists (select 1 from public.questions q where q.category_name='Ciência' and q.question_text='Qual é a unidade de corrente elétrica no SI?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Ciência','Qual doença é causada pelo vírus SARS-CoV-2?','["Dengue","COVID-19","Malária","Sarampo"]'::jsonb,1,true 
where not exists (select 1 from public.questions q where q.category_name='Ciência' and q.question_text='Qual doença é causada pelo vírus SARS-CoV-2?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Ciência','Qual célula do sangue transporta principalmente oxigênio?','["Plaqueta","Hemácia","Leucócito","Plasma"]'::jsonb,1,true 
where not exists (select 1 from public.questions q where q.category_name='Ciência' and q.question_text='Qual célula do sangue transporta principalmente oxigênio?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Ciência','Qual é o osso mais longo do corpo humano?','["Fêmur","Úmero","Tíbia","Rádio"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='Ciência' and q.question_text='Qual é o osso mais longo do corpo humano?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Ciência','Qual órgão produz insulina?','["Pâncreas","Fígado","Baço","Tireoide"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='Ciência' and q.question_text='Qual órgão produz insulina?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Ciência','Qual é o satélite natural de Marte que é maior?','["Deimos","Fobos","Lua","Io"]'::jsonb,1,true 
where not exists (select 1 from public.questions q where q.category_name='Ciência' and q.question_text='Qual é o satélite natural de Marte que é maior?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Ciência','Qual planeta tem o dia mais longo entre os oito planetas em termos de rotação?','["Vênus","Mercúrio","Marte","Júpiter"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='Ciência' and q.question_text='Qual planeta tem o dia mais longo entre os oito planetas em termos de rotação?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Ciência','Qual é o estado da matéria com volume definido e forma variável?','["Sólido","Líquido","Gasoso","Plasma"]'::jsonb,1,true 
where not exists (select 1 from public.questions q where q.category_name='Ciência' and q.question_text='Qual é o estado da matéria com volume definido e forma variável?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Ciência','Qual vitamina é associada à coagulação do sangue?','["A","C","D","K"]'::jsonb,3,true 
where not exists (select 1 from public.questions q where q.category_name='Ciência' and q.question_text='Qual vitamina é associada à coagulação do sangue?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Ciência','Qual é o nome da força que se opõe ao movimento entre duas superfícies?','["Gravidade","Atrito","Empuxo","Tração"]'::jsonb,1,true 
where not exists (select 1 from public.questions q where q.category_name='Ciência' and q.question_text='Qual é o nome da força que se opõe ao movimento entre duas superfícies?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Ciência','Qual gás é essencial para a respiração aeróbica humana?','["Oxigênio","Hidrogênio","Hélio","Nitrogênio"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='Ciência' and q.question_text='Qual gás é essencial para a respiração aeróbica humana?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Ciência','Qual é a unidade de energia no SI?','["Joule","Newton","Pascal","Tesla"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='Ciência' and q.question_text='Qual é a unidade de energia no SI?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Ciência','Qual cientista é associado às leis do movimento e da gravitação clássica?','["Isaac Newton","Louis Pasteur","Gregor Mendel","Niels Bohr"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='Ciência' and q.question_text='Qual cientista é associado às leis do movimento e da gravitação clássica?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Ciência','Qual estrutura celular controla a entrada e saída de substâncias?','["Membrana plasmática","Núcleo","Ribossomo","Centríolo"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='Ciência' and q.question_text='Qual estrutura celular controla a entrada e saída de substâncias?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Ciência','Qual é o nome da galáxia que abriga o Sistema Solar?','["Andrômeda","Via Láctea","Triângulo","Sombrero"]'::jsonb,1,true 
where not exists (select 1 from public.questions q where q.category_name='Ciência' and q.question_text='Qual é o nome da galáxia que abriga o Sistema Solar?');

-- Entretenimento: 50 perguntas
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Entretenimento','Qual personagem é conhecido por usar um martelo chamado Mjolnir?','["Batman","Thor","Superman","Flash"]'::jsonb,1,true 
where not exists (select 1 from public.questions q where q.category_name='Entretenimento' and q.question_text='Qual personagem é conhecido por usar um martelo chamado Mjolnir?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Entretenimento','Em qual saga aparece o personagem Harry Potter?','["Star Wars","Harry Potter","O Senhor dos Anéis","Matrix"]'::jsonb,1,true 
where not exists (select 1 from public.questions q where q.category_name='Entretenimento' and q.question_text='Em qual saga aparece o personagem Harry Potter?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Entretenimento','Qual filme apresenta o personagem Jack Sparrow?','["Piratas do Caribe","Avatar","Titanic","Gladiador"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='Entretenimento' and q.question_text='Qual filme apresenta o personagem Jack Sparrow?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Entretenimento','Qual é o nome do reino de Elsa e Anna em Frozen?','["Arendelle","Nárnia","Wakanda","Genovia"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='Entretenimento' and q.question_text='Qual é o nome do reino de Elsa e Anna em Frozen?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Entretenimento','Qual super-herói é conhecido como Homem-Aranha?','["Peter Parker","Bruce Wayne","Clark Kent","Tony Stark"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='Entretenimento' and q.question_text='Qual super-herói é conhecido como Homem-Aranha?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Entretenimento','Qual banda lançou a música Bohemian Rhapsody?','["Queen","ABBA","U2","Nirvana"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='Entretenimento' and q.question_text='Qual banda lançou a música Bohemian Rhapsody?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Entretenimento','Quem é o protagonista de O Rei Leão?','["Simba","Mufasa","Scar","Timon"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='Entretenimento' and q.question_text='Quem é o protagonista de O Rei Leão?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Entretenimento','Qual personagem vive em uma casa em forma de abacaxi no fundo do mar?','["Bob Esponja","Nemo","Popeye","Garfield"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='Entretenimento' and q.question_text='Qual personagem vive em uma casa em forma de abacaxi no fundo do mar?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Entretenimento','Qual série apresenta o personagem Walter White?','["Breaking Bad","Friends","Lost","The Office"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='Entretenimento' and q.question_text='Qual série apresenta o personagem Walter White?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Entretenimento','Qual é o nome do ogro protagonista de uma famosa franquia da DreamWorks?','["Shrek","Po","Gru","Hiccup"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='Entretenimento' and q.question_text='Qual é o nome do ogro protagonista de uma famosa franquia da DreamWorks?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Entretenimento','Qual personagem da Pixar é um robô compactador de lixo?','["WALL-E","Woody","Remy","Carl"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='Entretenimento' and q.question_text='Qual personagem da Pixar é um robô compactador de lixo?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Entretenimento','Qual é o nome do cowboy de Toy Story?','["Woody","Buzz","Andy","Forky"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='Entretenimento' and q.question_text='Qual é o nome do cowboy de Toy Story?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Entretenimento','Qual personagem diz ser um ''amigo'' de Woody e é um brinquedo espacial?','["Buzz Lightyear","Zurg","Rex","Slinky"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='Entretenimento' and q.question_text='Qual personagem diz ser um ''amigo'' de Woody e é um brinquedo espacial?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Entretenimento','Qual filme ganhou o Oscar de Melhor Filme em 1998 e conta uma história a bordo de um navio?','["Titanic","Rocky","Amadeus","Gladiador"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='Entretenimento' and q.question_text='Qual filme ganhou o Oscar de Melhor Filme em 1998 e conta uma história a bordo de um navio?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Entretenimento','Qual é o nome do protagonista de Matrix?','["Neo","Morpheus","Trinity","Cypher"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='Entretenimento' and q.question_text='Qual é o nome do protagonista de Matrix?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Entretenimento','Qual universo cinematográfico reúne Homem de Ferro, Capitão América e Hulk?','["Marvel","DC","Pixar","Lucasfilm"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='Entretenimento' and q.question_text='Qual universo cinematográfico reúne Homem de Ferro, Capitão América e Hulk?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Entretenimento','Qual herói é alter ego de Bruce Wayne?','["Batman","Superman","Aquaman","Lanterna Verde"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='Entretenimento' and q.question_text='Qual herói é alter ego de Bruce Wayne?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Entretenimento','Qual herói é alter ego de Clark Kent?','["Superman","Batman","Flash","Ciborgue"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='Entretenimento' and q.question_text='Qual herói é alter ego de Clark Kent?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Entretenimento','Qual princesa é conhecida por ter cabelos mágicos e muito longos?','["Rapunzel","Ariel","Bela","Mulan"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='Entretenimento' and q.question_text='Qual princesa é conhecida por ter cabelos mágicos e muito longos?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Entretenimento','Qual animação acompanha emoções como Alegria e Tristeza dentro da mente de uma menina?','["Divertida Mente","Encanto","Up","Toy Story"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='Entretenimento' and q.question_text='Qual animação acompanha emoções como Alegria e Tristeza dentro da mente de uma menina?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Entretenimento','Qual filme da Disney apresenta a família Madrigal?','["Encanto","Moana","Frozen","Valente"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='Entretenimento' and q.question_text='Qual filme da Disney apresenta a família Madrigal?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Entretenimento','Qual é o nome do boneco de neve de Frozen?','["Olaf","Sven","Kristoff","Hans"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='Entretenimento' and q.question_text='Qual é o nome do boneco de neve de Frozen?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Entretenimento','Qual série de ficção científica ficou famosa pelo Mundo Invertido?','["Stranger Things","Dark","Lost","Westworld"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='Entretenimento' and q.question_text='Qual série de ficção científica ficou famosa pelo Mundo Invertido?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Entretenimento','Qual é o nome da escola de magia frequentada por Harry Potter?','["Hogwarts","Beauxbatons","Durmstrang","Ilvermorny"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='Entretenimento' and q.question_text='Qual é o nome da escola de magia frequentada por Harry Potter?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Entretenimento','Qual personagem de O Senhor dos Anéis carrega o Um Anel por grande parte da história?','["Frodo","Aragorn","Gandalf","Legolas"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='Entretenimento' and q.question_text='Qual personagem de O Senhor dos Anéis carrega o Um Anel por grande parte da história?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Entretenimento','Qual é o nome do mago cinzento de O Senhor dos Anéis?','["Gandalf","Saruman","Radagast","Dumbledore"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='Entretenimento' and q.question_text='Qual é o nome do mago cinzento de O Senhor dos Anéis?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Entretenimento','Qual franquia tem os personagens Luke Skywalker e Darth Vader?','["Star Wars","Star Trek","Duna","Alien"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='Entretenimento' and q.question_text='Qual franquia tem os personagens Luke Skywalker e Darth Vader?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Entretenimento','Qual é o nome do vilão principal de O Rei Leão?','["Scar","Mufasa","Zazu","Rafiki"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='Entretenimento' and q.question_text='Qual é o nome do vilão principal de O Rei Leão?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Entretenimento','Qual personagem da DC usa um laço da verdade?','["Mulher-Maravilha","Supergirl","Batgirl","Arlequina"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='Entretenimento' and q.question_text='Qual personagem da DC usa um laço da verdade?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Entretenimento','Qual cantor é conhecido como ''Rei do Pop''?','["Michael Jackson","Elvis Presley","Prince","Frank Sinatra"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='Entretenimento' and q.question_text='Qual cantor é conhecido como ''Rei do Pop''?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Entretenimento','Qual cantora lançou o álbum 21?','["Adele","Rihanna","Beyoncé","Taylor Swift"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='Entretenimento' and q.question_text='Qual cantora lançou o álbum 21?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Entretenimento','Qual instrumento é central em uma bateria?','["Tambores","Violino","Flauta","Harpa"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='Entretenimento' and q.question_text='Qual instrumento é central em uma bateria?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Entretenimento','Qual gênero musical nasceu em Nova Orleans e é marcado pela improvisação?','["Jazz","Reggae","Fado","Sertanejo"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='Entretenimento' and q.question_text='Qual gênero musical nasceu em Nova Orleans e é marcado pela improvisação?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Entretenimento','Qual filme apresenta um parque com dinossauros recriados por engenharia genética?','["Jurassic Park","King Kong","Godzilla","Avatar"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='Entretenimento' and q.question_text='Qual filme apresenta um parque com dinossauros recriados por engenharia genética?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Entretenimento','Qual personagem é o detetive criado por Arthur Conan Doyle?','["Sherlock Holmes","Hercule Poirot","Philip Marlowe","Sam Spade"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='Entretenimento' and q.question_text='Qual personagem é o detetive criado por Arthur Conan Doyle?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Entretenimento','Qual escritor criou o personagem Sherlock Holmes?','["Arthur Conan Doyle","Agatha Christie","Jules Verne","George Orwell"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='Entretenimento' and q.question_text='Qual escritor criou o personagem Sherlock Holmes?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Entretenimento','Qual série de comédia acompanha seis amigos em Nova York?','["Friends","Seinfeld","How I Met Your Mother","Modern Family"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='Entretenimento' and q.question_text='Qual série de comédia acompanha seis amigos em Nova York?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Entretenimento','Qual é o nome do café frequentado pelos personagens de Friends?','["Central Perk","Monk''s Café","Luke''s","MacLaren''s"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='Entretenimento' and q.question_text='Qual é o nome do café frequentado pelos personagens de Friends?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Entretenimento','Qual filme apresenta o personagem Forrest Gump?','["Forrest Gump","O Poderoso Chefão","Rocky","Casablanca"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='Entretenimento' and q.question_text='Qual filme apresenta o personagem Forrest Gump?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Entretenimento','Qual personagem da Pixar é um rato que sonha em cozinhar?','["Remy","Dory","Miguel","Lightning McQueen"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='Entretenimento' and q.question_text='Qual personagem da Pixar é um rato que sonha em cozinhar?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Entretenimento','Qual filme da Pixar tem uma casa levada por balões?','["Up","Wall-E","Soul","Carros"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='Entretenimento' and q.question_text='Qual filme da Pixar tem uma casa levada por balões?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Entretenimento','Qual personagem é conhecido como o ''Bruxo'' na série The Witcher?','["Geralt de Rívia","Jaskier","Vesemir","Ciri"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='Entretenimento' and q.question_text='Qual personagem é conhecido como o ''Bruxo'' na série The Witcher?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Entretenimento','Qual é o nome da cidade fictícia de Gotham?','["Gotham City","Metropolis","Central City","Star City"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='Entretenimento' and q.question_text='Qual é o nome da cidade fictícia de Gotham?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Entretenimento','Qual herói é associado a Metropolis?','["Superman","Batman","Flash","Arqueiro Verde"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='Entretenimento' and q.question_text='Qual herói é associado a Metropolis?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Entretenimento','Qual animação tem personagens chamados Woody, Buzz e Jessie?','["Toy Story","Cars","Shrek","Madagascar"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='Entretenimento' and q.question_text='Qual animação tem personagens chamados Woody, Buzz e Jessie?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Entretenimento','Qual é o nome do dragão de estimação de Soluço em Como Treinar o Seu Dragão?','["Banguela","Dente-de-Leite","Tempestade","Fúria"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='Entretenimento' and q.question_text='Qual é o nome do dragão de estimação de Soluço em Como Treinar o Seu Dragão?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Entretenimento','Qual filme apresenta a personagem Neytiri?','["Avatar","Duna","Matrix","Titanic"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='Entretenimento' and q.question_text='Qual filme apresenta a personagem Neytiri?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Entretenimento','Qual franquia apresenta o personagem Indiana Jones?','["Indiana Jones","James Bond","Missão: Impossível","Jason Bourne"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='Entretenimento' and q.question_text='Qual franquia apresenta o personagem Indiana Jones?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Entretenimento','Qual é o nome do agente secreto conhecido pelo código 007?','["James Bond","Ethan Hunt","Jack Ryan","Jason Bourne"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='Entretenimento' and q.question_text='Qual é o nome do agente secreto conhecido pelo código 007?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Entretenimento','Qual personagem de Pokémon é um rato elétrico amarelo?','["Pikachu","Eevee","Meowth","Jigglypuff"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='Entretenimento' and q.question_text='Qual personagem de Pokémon é um rato elétrico amarelo?');

-- Esportes: 50 perguntas
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Esportes','Quantos jogadores um time de futebol tem em campo no início da partida?','["9","10","11","12"]'::jsonb,2,true 
where not exists (select 1 from public.questions q where q.category_name='Esportes' and q.question_text='Quantos jogadores um time de futebol tem em campo no início da partida?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Esportes','Qual país sediou a Copa do Mundo de 2014?','["Brasil","Rússia","Alemanha","França"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='Esportes' and q.question_text='Qual país sediou a Copa do Mundo de 2014?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Esportes','Quantos pontos vale uma cesta de três pontos no basquete?','["1","2","3","4"]'::jsonb,2,true 
where not exists (select 1 from public.questions q where q.category_name='Esportes' and q.question_text='Quantos pontos vale uma cesta de três pontos no basquete?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Esportes','Qual esporte usa uma raquete e uma peteca?','["Tênis","Badminton","Squash","Tênis de mesa"]'::jsonb,1,true 
where not exists (select 1 from public.questions q where q.category_name='Esportes' and q.question_text='Qual esporte usa uma raquete e uma peteca?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Esportes','Em qual esporte se usa a expressão ''hole in one''?','["Golfe","Tênis","Beisebol","Vôlei"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='Esportes' and q.question_text='Em qual esporte se usa a expressão ''hole in one''?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Esportes','Quantos jogadores há em quadra por equipe no vôlei?','["5","6","7","8"]'::jsonb,1,true 
where not exists (select 1 from public.questions q where q.category_name='Esportes' and q.question_text='Quantos jogadores há em quadra por equipe no vôlei?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Esportes','Qual país é famoso pela seleção de rúgbi All Blacks?','["Austrália","Nova Zelândia","Inglaterra","África do Sul"]'::jsonb,1,true 
where not exists (select 1 from public.questions q where q.category_name='Esportes' and q.question_text='Qual país é famoso pela seleção de rúgbi All Blacks?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Esportes','Qual é a distância oficial de uma maratona?','["21,097 km","40 km","42,195 km","50 km"]'::jsonb,2,true 
where not exists (select 1 from public.questions q where q.category_name='Esportes' and q.question_text='Qual é a distância oficial de uma maratona?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Esportes','Qual esporte é praticado na Fórmula 1?','["Ciclismo","Automobilismo","Motociclismo","Atletismo"]'::jsonb,1,true 
where not exists (select 1 from public.questions q where q.category_name='Esportes' and q.question_text='Qual esporte é praticado na Fórmula 1?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Esportes','Qual é o principal torneio de seleções de futebol da Europa?','["Eurocopa","Copa América","Copa Africana","Liga das Nações da Ásia"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='Esportes' and q.question_text='Qual é o principal torneio de seleções de futebol da Europa?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Esportes','Qual país venceu a primeira Copa do Mundo de futebol em 1930?','["Brasil","Uruguai","Argentina","Itália"]'::jsonb,1,true 
where not exists (select 1 from public.questions q where q.category_name='Esportes' and q.question_text='Qual país venceu a primeira Copa do Mundo de futebol em 1930?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Esportes','Quantos sets uma partida masculina de Grand Slam de tênis pode ter no máximo?','["3","4","5","6"]'::jsonb,2,true 
where not exists (select 1 from public.questions q where q.category_name='Esportes' and q.question_text='Quantos sets uma partida masculina de Grand Slam de tênis pode ter no máximo?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Esportes','Qual esporte tem posições como levantador e líbero?','["Basquete","Vôlei","Futebol","Handebol"]'::jsonb,1,true 
where not exists (select 1 from public.questions q where q.category_name='Esportes' and q.question_text='Qual esporte tem posições como levantador e líbero?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Esportes','Qual peça é usada para rebater a bola no hóquei no gelo?','["Taco","Raquete","Bastão","Bate"]'::jsonb,2,true 
where not exists (select 1 from public.questions q where q.category_name='Esportes' and q.question_text='Qual peça é usada para rebater a bola no hóquei no gelo?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Esportes','Em qual esporte existe o ''home run''?','["Beisebol","Críquete","Rúgbi","Hóquei"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='Esportes' and q.question_text='Em qual esporte existe o ''home run''?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Esportes','Quantos anéis aparecem no símbolo olímpico?','["4","5","6","7"]'::jsonb,1,true 
where not exists (select 1 from public.questions q where q.category_name='Esportes' and q.question_text='Quantos anéis aparecem no símbolo olímpico?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Esportes','Qual é a cor tradicional da camisa da seleção brasileira de futebol?','["Azul","Verde","Amarela","Branca"]'::jsonb,2,true 
where not exists (select 1 from public.questions q where q.category_name='Esportes' and q.question_text='Qual é a cor tradicional da camisa da seleção brasileira de futebol?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Esportes','Qual esporte é conhecido como ''esporte da mente'' e usa um tabuleiro de 64 casas?','["Damas","Xadrez","Go","Shogi"]'::jsonb,1,true 
where not exists (select 1 from public.questions q where q.category_name='Esportes' and q.question_text='Qual esporte é conhecido como ''esporte da mente'' e usa um tabuleiro de 64 casas?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Esportes','Quantos jogadores formam uma equipe de basquete em quadra?','["4","5","6","7"]'::jsonb,1,true 
where not exists (select 1 from public.questions q where q.category_name='Esportes' and q.question_text='Quantos jogadores formam uma equipe de basquete em quadra?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Esportes','Qual é a superfície tradicional de Wimbledon?','["Saibro","Grama","Cimento","Carpete"]'::jsonb,1,true 
where not exists (select 1 from public.questions q where q.category_name='Esportes' and q.question_text='Qual é a superfície tradicional de Wimbledon?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Esportes','Qual país é conhecido por ter sediado os Jogos Olímpicos de 2016?','["Brasil","China","Grécia","Japão"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='Esportes' and q.question_text='Qual país é conhecido por ter sediado os Jogos Olímpicos de 2016?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Esportes','Em qual esporte se disputa a prova dos 100 metros rasos?','["Natação","Atletismo","Ciclismo","Ginástica"]'::jsonb,1,true 
where not exists (select 1 from public.questions q where q.category_name='Esportes' and q.question_text='Em qual esporte se disputa a prova dos 100 metros rasos?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Esportes','Qual é o objeto usado no curling?','["Pedra","Bola","Disco","Peteca"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='Esportes' and q.question_text='Qual é o objeto usado no curling?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Esportes','Qual esporte combina esqui e tiro ao alvo?','["Biathlon","Triatlo","Pentatlo","Decatlo"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='Esportes' and q.question_text='Qual esporte combina esqui e tiro ao alvo?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Esportes','Qual é o nome da competição internacional de seleções de futebol realizada a cada quatro anos?','["Copa do Mundo","Champions League","Libertadores","Euroleague"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='Esportes' and q.question_text='Qual é o nome da competição internacional de seleções de futebol realizada a cada quatro anos?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Esportes','Quantos jogadores formam uma equipe de handebol em quadra?','["5","6","7","8"]'::jsonb,2,true 
where not exists (select 1 from public.questions q where q.category_name='Esportes' and q.question_text='Quantos jogadores formam uma equipe de handebol em quadra?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Esportes','Qual esporte utiliza um tatame e golpes como ippon?','["Judô","Esgrima","Boxe","Natação"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='Esportes' and q.question_text='Qual esporte utiliza um tatame e golpes como ippon?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Esportes','Qual esporte utiliza florete, espada ou sabre?','["Esgrima","Judô","Luta livre","Arco e flecha"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='Esportes' and q.question_text='Qual esporte utiliza florete, espada ou sabre?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Esportes','Qual é o nome da maior prova do ciclismo de estrada na França?','["Tour de France","Giro d''Italia","Vuelta","Paris-Roubaix"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='Esportes' and q.question_text='Qual é o nome da maior prova do ciclismo de estrada na França?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Esportes','Qual esporte tem um ''quarterback''?','["Futebol americano","Beisebol","Hóquei","Rúgbi"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='Esportes' and q.question_text='Qual esporte tem um ''quarterback''?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Esportes','Qual é a duração regulamentar de uma partida de futebol, sem acréscimos?','["60 minutos","80 minutos","90 minutos","120 minutos"]'::jsonb,2,true 
where not exists (select 1 from public.questions q where q.category_name='Esportes' and q.question_text='Qual é a duração regulamentar de uma partida de futebol, sem acréscimos?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Esportes','Qual esporte usa uma bola oval?','["Rúgbi","Vôlei","Tênis","Futsal"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='Esportes' and q.question_text='Qual esporte usa uma bola oval?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Esportes','Qual é o termo para três gols do mesmo jogador em uma partida de futebol?','["Hat-trick","Triple play","Grand slam","Knockout"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='Esportes' and q.question_text='Qual é o termo para três gols do mesmo jogador em uma partida de futebol?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Esportes','Qual esporte é praticado no ringue e usa luvas acolchoadas?','["Boxe","Golfe","Vôlei","Esgrima"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='Esportes' and q.question_text='Qual esporte é praticado no ringue e usa luvas acolchoadas?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Esportes','Qual prova de natação usa os estilos borboleta, costas, peito e livre?','["Medley","Revezamento livre","Maratona aquática","Sprint"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='Esportes' and q.question_text='Qual prova de natação usa os estilos borboleta, costas, peito e livre?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Esportes','Qual é o maior torneio de clubes de futebol da América do Sul?','["Libertadores","Sul-Americana","Recopa","Copa do Brasil"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='Esportes' and q.question_text='Qual é o maior torneio de clubes de futebol da América do Sul?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Esportes','Qual país é conhecido pela equipe de basquete da NBA chamada Los Angeles Lakers?','["Estados Unidos","Canadá","Espanha","Austrália"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='Esportes' and q.question_text='Qual país é conhecido pela equipe de basquete da NBA chamada Los Angeles Lakers?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Esportes','Qual esporte tem um ''slam dunk''?','["Basquete","Vôlei","Tênis","Handebol"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='Esportes' and q.question_text='Qual esporte tem um ''slam dunk''?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Esportes','Qual modalidade olímpica usa cavalo, espada e tiro em um mesmo conjunto de provas?','["Pentatlo moderno","Triatlo","Decatlo","Hipismo"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='Esportes' and q.question_text='Qual modalidade olímpica usa cavalo, espada e tiro em um mesmo conjunto de provas?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Esportes','Qual esporte tem um ''strike'' e um ''spare''?','["Boliche","Beisebol","Críquete","Golfe"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='Esportes' and q.question_text='Qual esporte tem um ''strike'' e um ''spare''?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Esportes','Qual é o nome da área onde o goleiro atua no futebol?','["Grande área","Meia-lua","Linha de fundo","Círculo central"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='Esportes' and q.question_text='Qual é o nome da área onde o goleiro atua no futebol?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Esportes','Qual esporte é conhecido por termos como birdie, eagle e bogey?','["Golfe","Tênis","Críquete","Beisebol"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='Esportes' and q.question_text='Qual esporte é conhecido por termos como birdie, eagle e bogey?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Esportes','Qual modalidade é conhecida pelas provas de argolas e barras?','["Ginástica artística","Atletismo","Natação","Esgrima"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='Esportes' and q.question_text='Qual modalidade é conhecida pelas provas de argolas e barras?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Esportes','Qual é o país de origem do judô?','["China","Japão","Coreia do Sul","Tailândia"]'::jsonb,1,true 
where not exists (select 1 from public.questions q where q.category_name='Esportes' and q.question_text='Qual é o país de origem do judô?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Esportes','Qual esporte tem uma rede dividindo a quadra e permite bloqueios com as mãos?','["Vôlei","Tênis","Badminton","Futebol"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='Esportes' and q.question_text='Qual esporte tem uma rede dividindo a quadra e permite bloqueios com as mãos?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Esportes','Qual é o nome da liga profissional de futebol americano dos EUA?','["NFL","NBA","MLB","NHL"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='Esportes' and q.question_text='Qual é o nome da liga profissional de futebol americano dos EUA?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Esportes','Qual liga reúne as principais equipes profissionais de basquete dos EUA e Canadá?','["NBA","NFL","MLB","NHL"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='Esportes' and q.question_text='Qual liga reúne as principais equipes profissionais de basquete dos EUA e Canadá?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Esportes','Qual esporte é disputado em uma pista oval com patins sobre rodas?','["Patinação de velocidade","Esqui alpino","Bobsled","Surfe"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='Esportes' and q.question_text='Qual esporte é disputado em uma pista oval com patins sobre rodas?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Esportes','Qual esporte é praticado sobre ondas com uma prancha?','["Surfe","Remo","Canoagem","Polo aquático"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='Esportes' and q.question_text='Qual esporte é praticado sobre ondas com uma prancha?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Esportes','Qual prova do atletismo combina dez modalidades?','["Decatlo","Heptatlo","Pentatlo","Triatlo"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='Esportes' and q.question_text='Qual prova do atletismo combina dez modalidades?');

-- História: 50 perguntas
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'História','Em que ano o Brasil declarou sua independência de Portugal?','["1500","1822","1889","1888"]'::jsonb,1,true 
where not exists (select 1 from public.questions q where q.category_name='História' and q.question_text='Em que ano o Brasil declarou sua independência de Portugal?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'História','Quem proclamou a Independência do Brasil?','["Dom Pedro I","Dom Pedro II","Tiradentes","Getúlio Vargas"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='História' and q.question_text='Quem proclamou a Independência do Brasil?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'História','Em que ano foi proclamada a República no Brasil?','["1822","1889","1930","1964"]'::jsonb,1,true 
where not exists (select 1 from public.questions q where q.category_name='História' and q.question_text='Em que ano foi proclamada a República no Brasil?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'História','Qual civilização construiu Machu Picchu?','["Maia","Inca","Asteca","Romana"]'::jsonb,1,true 
where not exists (select 1 from public.questions q where q.category_name='História' and q.question_text='Qual civilização construiu Machu Picchu?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'História','Qual civilização construiu as pirâmides de Gizé?','["Egípcia","Grega","Romana","Persa"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='História' and q.question_text='Qual civilização construiu as pirâmides de Gizé?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'História','Quem foi o primeiro imperador do Brasil?','["Dom Pedro I","Dom Pedro II","Joaquim Nabuco","Deodoro da Fonseca"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='História' and q.question_text='Quem foi o primeiro imperador do Brasil?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'História','Quem foi o último imperador do Brasil?','["Dom Pedro I","Dom Pedro II","Getúlio Vargas","Floriano Peixoto"]'::jsonb,1,true 
where not exists (select 1 from public.questions q where q.category_name='História' and q.question_text='Quem foi o último imperador do Brasil?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'História','Qual lei aboliu oficialmente a escravidão no Brasil em 1888?','["Lei do Ventre Livre","Lei Áurea","Lei Eusébio de Queirós","Lei de Terras"]'::jsonb,1,true 
where not exists (select 1 from public.questions q where q.category_name='História' and q.question_text='Qual lei aboliu oficialmente a escravidão no Brasil em 1888?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'História','Quem assinou a Lei Áurea?','["Princesa Isabel","Dom Pedro II","Maria Leopoldina","Chiquinha Gonzaga"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='História' and q.question_text='Quem assinou a Lei Áurea?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'História','Qual foi o conflito mundial de 1939 a 1945?','["Primeira Guerra Mundial","Segunda Guerra Mundial","Guerra Fria","Guerra da Crimeia"]'::jsonb,1,true 
where not exists (select 1 from public.questions q where q.category_name='História' and q.question_text='Qual foi o conflito mundial de 1939 a 1945?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'História','Qual conflito ocorreu de 1914 a 1918?','["Primeira Guerra Mundial","Segunda Guerra Mundial","Guerra do Vietnã","Guerra Fria"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='História' and q.question_text='Qual conflito ocorreu de 1914 a 1918?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'História','Qual cidade italiana foi soterrada pela erupção do Vesúvio em 79 d.C.?','["Pompeia","Veneza","Milão","Florença"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='História' and q.question_text='Qual cidade italiana foi soterrada pela erupção do Vesúvio em 79 d.C.?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'História','Quem foi conhecido como o ''Pai da Independência'' dos Estados Unidos?','["George Washington","Abraham Lincoln","Thomas Edison","Benjamin Franklin"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='História' and q.question_text='Quem foi conhecido como o ''Pai da Independência'' dos Estados Unidos?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'História','Quem foi o primeiro presidente dos Estados Unidos?','["George Washington","Abraham Lincoln","John Adams","Thomas Jefferson"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='História' and q.question_text='Quem foi o primeiro presidente dos Estados Unidos?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'História','Qual império tinha Constantinopla como capital por grande parte de sua história?','["Bizantino","Mongol","Asteca","Inca"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='História' and q.question_text='Qual império tinha Constantinopla como capital por grande parte de sua história?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'História','Qual evento é tradicionalmente usado para marcar o fim da Idade Média em 1453?','["Queda de Constantinopla","Descobrimento do Brasil","Revolução Francesa","Queda de Roma"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='História' and q.question_text='Qual evento é tradicionalmente usado para marcar o fim da Idade Média em 1453?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'História','Em que ano Cristóvão Colombo chegou às Américas?','["1492","1500","1453","1519"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='História' and q.question_text='Em que ano Cristóvão Colombo chegou às Américas?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'História','Qual navegador português chegou à Índia por via marítima em 1498?','["Vasco da Gama","Pedro Álvares Cabral","Fernão de Magalhães","Bartolomeu Dias"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='História' and q.question_text='Qual navegador português chegou à Índia por via marítima em 1498?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'História','Quem chegou ao Brasil em 1500 segundo a narrativa tradicional portuguesa?','["Pedro Álvares Cabral","Vasco da Gama","Cristóvão Colombo","Martim Afonso"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='História' and q.question_text='Quem chegou ao Brasil em 1500 segundo a narrativa tradicional portuguesa?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'História','Qual revolução começou na França em 1789?','["Revolução Francesa","Revolução Industrial","Revolução Russa","Revolução Gloriosa"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='História' and q.question_text='Qual revolução começou na França em 1789?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'História','Qual documento inglês de 1215 limitou o poder do rei?','["Magna Carta","Bill of Rights","Constituição de Cádiz","Código Napoleônico"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='História' and q.question_text='Qual documento inglês de 1215 limitou o poder do rei?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'História','Quem foi Napoleão Bonaparte?','["Imperador francês","Rei inglês","Czar russo","Presidente americano"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='História' and q.question_text='Quem foi Napoleão Bonaparte?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'História','Qual muro caiu em 1989 e simbolizou o fim da divisão de Berlim?','["Muro de Berlim","Muro de Adriano","Muro da China","Muro de Varsóvia"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='História' and q.question_text='Qual muro caiu em 1989 e simbolizou o fim da divisão de Berlim?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'História','Qual guerra foi travada entre Atenas e Esparta no século V a.C.?','["Guerra do Peloponeso","Guerras Púnicas","Guerras Médicas","Guerra de Troia"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='História' and q.question_text='Qual guerra foi travada entre Atenas e Esparta no século V a.C.?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'História','Qual povo antigo ficou famoso pela cidade de Troia nas epopeias gregas?','["Gregos e troianos","Romanos","Egípcios","Persas"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='História' and q.question_text='Qual povo antigo ficou famoso pela cidade de Troia nas epopeias gregas?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'História','Quem escreveu a Ilíada e a Odisseia segundo a tradição?','["Homero","Platão","Aristóteles","Sófocles"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='História' and q.question_text='Quem escreveu a Ilíada e a Odisseia segundo a tradição?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'História','Qual filósofo foi mestre de Alexandre, o Grande?','["Aristóteles","Sócrates","Platão","Epicuro"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='História' and q.question_text='Qual filósofo foi mestre de Alexandre, o Grande?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'História','Qual líder macedônio criou um enorme império no século IV a.C.?','["Alexandre, o Grande","Júlio César","Nero","Hannibal"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='História' and q.question_text='Qual líder macedônio criou um enorme império no século IV a.C.?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'História','Qual cidade foi centro do Império Romano?','["Roma","Atenas","Cartago","Alexandria"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='História' and q.question_text='Qual cidade foi centro do Império Romano?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'História','Quem foi Júlio César?','["General e político romano","Faraó egípcio","Rei persa","Filósofo grego"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='História' and q.question_text='Quem foi Júlio César?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'História','Qual civilização usava hieróglifos?','["Egípcia","Inca","Romana","Viking"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='História' and q.question_text='Qual civilização usava hieróglifos?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'História','Qual povo construiu uma extensa rede de estradas nos Andes?','["Incas","Romanos","Fenícios","Vikings"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='História' and q.question_text='Qual povo construiu uma extensa rede de estradas nos Andes?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'História','Qual foi a capital do Império Asteca?','["Tenochtitlán","Cusco","Teotihuacan","Chichén Itzá"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='História' and q.question_text='Qual foi a capital do Império Asteca?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'História','Qual revolução marcou a mecanização e industrialização iniciada na Grã-Bretanha?','["Revolução Industrial","Revolução Francesa","Revolução Russa","Revolução Agrícola"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='História' and q.question_text='Qual revolução marcou a mecanização e industrialização iniciada na Grã-Bretanha?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'História','Quem liderou a independência da Índia com uma estratégia de não violência?','["Mahatma Gandhi","Nelson Mandela","Martin Luther King Jr.","Jawaharlal Nehru"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='História' and q.question_text='Quem liderou a independência da Índia com uma estratégia de não violência?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'História','Qual líder sul-africano lutou contra o apartheid e tornou-se presidente?','["Nelson Mandela","Gandhi","Churchill","De Gaulle"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='História' and q.question_text='Qual líder sul-africano lutou contra o apartheid e tornou-se presidente?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'História','Qual evento de 1917 derrubou o regime czarista na Rússia?','["Revolução Russa","Revolução Francesa","Revolução Industrial","Primavera dos Povos"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='História' and q.question_text='Qual evento de 1917 derrubou o regime czarista na Rússia?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'História','Qual organização internacional foi criada em 1945 após a Segunda Guerra Mundial?','["ONU","OTAN","União Europeia","Mercosul"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='História' and q.question_text='Qual organização internacional foi criada em 1945 após a Segunda Guerra Mundial?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'História','Qual foi a cidade japonesa atingida por uma bomba atômica em 6 de agosto de 1945?','["Hiroshima","Nagasaki","Kyoto","Osaka"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='História' and q.question_text='Qual foi a cidade japonesa atingida por uma bomba atômica em 6 de agosto de 1945?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'História','Qual outra cidade japonesa foi atingida por uma bomba atômica em 9 de agosto de 1945?','["Nagasaki","Hiroshima","Tokyo","Sapporo"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='História' and q.question_text='Qual outra cidade japonesa foi atingida por uma bomba atômica em 9 de agosto de 1945?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'História','Qual período de tensão geopolítica marcou EUA e URSS após a Segunda Guerra Mundial?','["Guerra Fria","Guerra dos Cem Anos","Guerra do Golfo","Guerra do Vietnã"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='História' and q.question_text='Qual período de tensão geopolítica marcou EUA e URSS após a Segunda Guerra Mundial?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'História','Qual império foi governado por sultões e teve Constantinopla como centro após 1453?','["Otomano","Romano","Inca","Mali"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='História' and q.question_text='Qual império foi governado por sultões e teve Constantinopla como centro após 1453?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'História','Qual explorador liderou a primeira expedição que realizou a primeira circunavegação do globo?','["Fernão de Magalhães","Vasco da Gama","Marco Polo","James Cook"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='História' and q.question_text='Qual explorador liderou a primeira expedição que realizou a primeira circunavegação do globo?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'História','Qual documento de 1787 estabeleceu a Constituição dos Estados Unidos?','["Constituição dos EUA","Magna Carta","Declaração de Direitos Humanos","Tratado de Versalhes"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='História' and q.question_text='Qual documento de 1787 estabeleceu a Constituição dos Estados Unidos?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'História','Qual tratado encerrou formalmente a Primeira Guerra Mundial com a Alemanha?','["Tratado de Versalhes","Tratado de Tordesilhas","Tratado de Utrecht","Tratado de Paris"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='História' and q.question_text='Qual tratado encerrou formalmente a Primeira Guerra Mundial com a Alemanha?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'História','Qual rainha inglesa deu nome à Era Vitoriana?','["Rainha Vitória","Elizabeth I","Elizabeth II","Mary I"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='História' and q.question_text='Qual rainha inglesa deu nome à Era Vitoriana?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'História','Qual civilização antiga criou a democracia em Atenas?','["Gregos","Romanos","Egípcios","Persas"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='História' and q.question_text='Qual civilização antiga criou a democracia em Atenas?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'História','Qual povo antigo fundou Cartago?','["Fenícios","Romanos","Gregos","Egípcios"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='História' and q.question_text='Qual povo antigo fundou Cartago?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'História','Qual líder francês foi uma figura central na resistência e depois presidente após a Segunda Guerra Mundial?','["Charles de Gaulle","Napoleão","Robespierre","Louis XIV"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='História' and q.question_text='Qual líder francês foi uma figura central na resistência e depois presidente após a Segunda Guerra Mundial?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'História','Qual revolta brasileira ocorreu na Bahia entre 1837 e 1838?','["Sabinada","Inconfidência Mineira","Balaiada","Cabanagem"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='História' and q.question_text='Qual revolta brasileira ocorreu na Bahia entre 1837 e 1838?');

-- Geografia: 50 perguntas
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Geografia','Qual é a capital do Brasil?','["Brasília","São Paulo","Rio de Janeiro","Salvador"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='Geografia' and q.question_text='Qual é a capital do Brasil?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Geografia','Qual é o maior país do mundo em área?','["Rússia","Canadá","China","Brasil"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='Geografia' and q.question_text='Qual é o maior país do mundo em área?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Geografia','Qual é o menor país do mundo em área?','["Mônaco","Vaticano","Malta","San Marino"]'::jsonb,1,true 
where not exists (select 1 from public.questions q where q.category_name='Geografia' and q.question_text='Qual é o menor país do mundo em área?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Geografia','Qual é o maior oceano do planeta?','["Atlântico","Pacífico","Índico","Ártico"]'::jsonb,1,true 
where not exists (select 1 from public.questions q where q.category_name='Geografia' and q.question_text='Qual é o maior oceano do planeta?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Geografia','Qual é o rio mais extenso tradicionalmente reconhecido como o maior do mundo por volume de água?','["Amazonas","Nilo","Mississipi","Danúbio"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='Geografia' and q.question_text='Qual é o rio mais extenso tradicionalmente reconhecido como o maior do mundo por volume de água?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Geografia','Em qual continente fica o Egito?','["Ásia","África","Europa","Oceania"]'::jsonb,1,true 
where not exists (select 1 from public.questions q where q.category_name='Geografia' and q.question_text='Em qual continente fica o Egito?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Geografia','Em qual continente fica o Japão?','["Europa","Ásia","África","Oceania"]'::jsonb,1,true 
where not exists (select 1 from public.questions q where q.category_name='Geografia' and q.question_text='Em qual continente fica o Japão?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Geografia','Qual é a capital da Austrália?','["Sydney","Melbourne","Canberra","Perth"]'::jsonb,2,true 
where not exists (select 1 from public.questions q where q.category_name='Geografia' and q.question_text='Qual é a capital da Austrália?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Geografia','Qual é a capital do Canadá?','["Toronto","Ottawa","Vancouver","Montreal"]'::jsonb,1,true 
where not exists (select 1 from public.questions q where q.category_name='Geografia' and q.question_text='Qual é a capital do Canadá?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Geografia','Qual é a capital da Argentina?','["Córdoba","Buenos Aires","Mendoza","Rosário"]'::jsonb,1,true 
where not exists (select 1 from public.questions q where q.category_name='Geografia' and q.question_text='Qual é a capital da Argentina?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Geografia','Qual é a capital do Chile?','["Santiago","Valparaíso","Lima","Quito"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='Geografia' and q.question_text='Qual é a capital do Chile?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Geografia','Qual é a capital do Peru?','["Cusco","Lima","Arequipa","Trujillo"]'::jsonb,1,true 
where not exists (select 1 from public.questions q where q.category_name='Geografia' and q.question_text='Qual é a capital do Peru?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Geografia','Qual é a capital da Colômbia?','["Medellín","Cali","Bogotá","Cartagena"]'::jsonb,2,true 
where not exists (select 1 from public.questions q where q.category_name='Geografia' and q.question_text='Qual é a capital da Colômbia?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Geografia','Qual é a capital do México?','["Guadalajara","Cancún","Cidade do México","Monterrey"]'::jsonb,2,true 
where not exists (select 1 from public.questions q where q.category_name='Geografia' and q.question_text='Qual é a capital do México?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Geografia','Qual é a capital da França?','["Lyon","Paris","Marselha","Nice"]'::jsonb,1,true 
where not exists (select 1 from public.questions q where q.category_name='Geografia' and q.question_text='Qual é a capital da França?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Geografia','Qual é a capital da Alemanha?','["Munique","Frankfurt","Berlim","Hamburgo"]'::jsonb,2,true 
where not exists (select 1 from public.questions q where q.category_name='Geografia' and q.question_text='Qual é a capital da Alemanha?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Geografia','Qual é a capital da Itália?','["Roma","Milão","Turim","Nápoles"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='Geografia' and q.question_text='Qual é a capital da Itália?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Geografia','Qual é a capital da Espanha?','["Barcelona","Madrid","Sevilha","Valência"]'::jsonb,1,true 
where not exists (select 1 from public.questions q where q.category_name='Geografia' and q.question_text='Qual é a capital da Espanha?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Geografia','Qual é a capital de Portugal?','["Porto","Lisboa","Braga","Faro"]'::jsonb,1,true 
where not exists (select 1 from public.questions q where q.category_name='Geografia' and q.question_text='Qual é a capital de Portugal?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Geografia','Qual é a capital do Reino Unido?','["Manchester","Londres","Liverpool","Edimburgo"]'::jsonb,1,true 
where not exists (select 1 from public.questions q where q.category_name='Geografia' and q.question_text='Qual é a capital do Reino Unido?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Geografia','Qual é a capital da Rússia?','["São Petersburgo","Moscou","Kazan","Sochi"]'::jsonb,1,true 
where not exists (select 1 from public.questions q where q.category_name='Geografia' and q.question_text='Qual é a capital da Rússia?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Geografia','Qual é a capital da China?','["Xangai","Pequim","Hong Kong","Guangzhou"]'::jsonb,1,true 
where not exists (select 1 from public.questions q where q.category_name='Geografia' and q.question_text='Qual é a capital da China?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Geografia','Qual é a capital da Índia?','["Mumbai","Nova Délhi","Calcutá","Bangalore"]'::jsonb,1,true 
where not exists (select 1 from public.questions q where q.category_name='Geografia' and q.question_text='Qual é a capital da Índia?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Geografia','Qual é a capital do Japão?','["Osaka","Kyoto","Tóquio","Nagoya"]'::jsonb,2,true 
where not exists (select 1 from public.questions q where q.category_name='Geografia' and q.question_text='Qual é a capital do Japão?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Geografia','Qual é a capital do Egito?','["Alexandria","Cairo","Luxor","Gizé"]'::jsonb,1,true 
where not exists (select 1 from public.questions q where q.category_name='Geografia' and q.question_text='Qual é a capital do Egito?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Geografia','Qual é a montanha mais alta do mundo acima do nível do mar?','["K2","Everest","Aconcágua","Kilimanjaro"]'::jsonb,1,true 
where not exists (select 1 from public.questions q where q.category_name='Geografia' and q.question_text='Qual é a montanha mais alta do mundo acima do nível do mar?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Geografia','Em qual cordilheira fica o Monte Everest?','["Andes","Himalaia","Alpes","Rochosas"]'::jsonb,1,true 
where not exists (select 1 from public.questions q where q.category_name='Geografia' and q.question_text='Em qual cordilheira fica o Monte Everest?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Geografia','Qual é o maior deserto quente do mundo?','["Saara","Gobi","Atacama","Kalahari"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='Geografia' and q.question_text='Qual é o maior deserto quente do mundo?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Geografia','Qual é o maior deserto do mundo considerando também os desertos frios?','["Saara","Antártida","Gobi","Arábia"]'::jsonb,1,true 
where not exists (select 1 from public.questions q where q.category_name='Geografia' and q.question_text='Qual é o maior deserto do mundo considerando também os desertos frios?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Geografia','Qual país tem formato frequentemente comparado a uma bota?','["Itália","Grécia","Chile","Portugal"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='Geografia' and q.question_text='Qual país tem formato frequentemente comparado a uma bota?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Geografia','Qual país possui a maior população da América do Sul?','["Argentina","Colômbia","Brasil","Peru"]'::jsonb,2,true 
where not exists (select 1 from public.questions q where q.category_name='Geografia' and q.question_text='Qual país possui a maior população da América do Sul?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Geografia','Qual é a maior ilha do mundo, excluindo continentes?','["Madagascar","Groenlândia","Bornéu","Nova Guiné"]'::jsonb,1,true 
where not exists (select 1 from public.questions q where q.category_name='Geografia' and q.question_text='Qual é a maior ilha do mundo, excluindo continentes?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Geografia','Qual país é conhecido por ter o maior número de ilhas do mundo?','["Suécia","Brasil","Japão","Canadá"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='Geografia' and q.question_text='Qual país é conhecido por ter o maior número de ilhas do mundo?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Geografia','Qual mar separa a Europa da África em grande parte de sua extensão?','["Mar Mediterrâneo","Mar do Norte","Mar Báltico","Mar Negro"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='Geografia' and q.question_text='Qual mar separa a Europa da África em grande parte de sua extensão?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Geografia','Qual estreito separa a Europa da África?','["Estreito de Bering","Estreito de Gibraltar","Estreito de Malaca","Estreito de Ormuz"]'::jsonb,1,true 
where not exists (select 1 from public.questions q where q.category_name='Geografia' and q.question_text='Qual estreito separa a Europa da África?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Geografia','Qual canal liga o Oceano Atlântico ao Oceano Pacífico através da América Central?','["Canal de Suez","Canal do Panamá","Canal da Mancha","Canal de Kiel"]'::jsonb,1,true 
where not exists (select 1 from public.questions q where q.category_name='Geografia' and q.question_text='Qual canal liga o Oceano Atlântico ao Oceano Pacífico através da América Central?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Geografia','Qual canal liga o Mar Mediterrâneo ao Mar Vermelho?','["Canal do Panamá","Canal de Suez","Canal de Corinto","Canal de Kiel"]'::jsonb,1,true 
where not exists (select 1 from public.questions q where q.category_name='Geografia' and q.question_text='Qual canal liga o Mar Mediterrâneo ao Mar Vermelho?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Geografia','Qual é o país mais ao sul da América do Sul?','["Brasil","Chile","Argentina","Uruguai"]'::jsonb,1,true 
where not exists (select 1 from public.questions q where q.category_name='Geografia' and q.question_text='Qual é o país mais ao sul da América do Sul?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Geografia','Qual país fica entre a França e a Espanha nos Pireneus?','["Andorra","Mônaco","Luxemburgo","Bélgica"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='Geografia' and q.question_text='Qual país fica entre a França e a Espanha nos Pireneus?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Geografia','Qual é a capital da Grécia?','["Atenas","Esparta","Salônica","Corinto"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='Geografia' and q.question_text='Qual é a capital da Grécia?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Geografia','Qual é a capital da Turquia?','["Istambul","Ancara","Esmirna","Bursa"]'::jsonb,1,true 
where not exists (select 1 from public.questions q where q.category_name='Geografia' and q.question_text='Qual é a capital da Turquia?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Geografia','Qual é a capital do Marrocos?','["Casablanca","Rabat","Fez","Marrakech"]'::jsonb,1,true 
where not exists (select 1 from public.questions q where q.category_name='Geografia' and q.question_text='Qual é a capital do Marrocos?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Geografia','Qual é a capital da África do Sul administrativa?','["Cidade do Cabo","Pretória","Joanesburgo","Durban"]'::jsonb,1,true 
where not exists (select 1 from public.questions q where q.category_name='Geografia' and q.question_text='Qual é a capital da África do Sul administrativa?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Geografia','Qual é a capital da Nova Zelândia?','["Auckland","Wellington","Christchurch","Hamilton"]'::jsonb,1,true 
where not exists (select 1 from public.questions q where q.category_name='Geografia' and q.question_text='Qual é a capital da Nova Zelândia?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Geografia','Qual é o país conhecido pelo formato de ''bota'' na América do Sul?','["Chile","Brasil","Argentina","Uruguai"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='Geografia' and q.question_text='Qual é o país conhecido pelo formato de ''bota'' na América do Sul?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Geografia','Qual é a região brasileira famosa pela Floresta Amazônica?','["Norte","Sul","Sudeste","Centro-Oeste"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='Geografia' and q.question_text='Qual é a região brasileira famosa pela Floresta Amazônica?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Geografia','Qual é a maior região brasileira em área?','["Norte","Nordeste","Sul","Sudeste"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='Geografia' and q.question_text='Qual é a maior região brasileira em área?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Geografia','Qual é a capital do estado do Amazonas?','["Belém","Manaus","Rio Branco","Macapá"]'::jsonb,1,true 
where not exists (select 1 from public.questions q where q.category_name='Geografia' and q.question_text='Qual é a capital do estado do Amazonas?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Geografia','Qual é a capital do Pará?','["Belém","Manaus","Santarém","Macapá"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='Geografia' and q.question_text='Qual é a capital do Pará?');
insert into public.questions(category_name,question_text,options,correct_index,active) 
select 'Geografia','Qual é a capital de Pernambuco?','["Recife","Olinda","João Pessoa","Maceió"]'::jsonb,0,true 
where not exists (select 1 from public.questions q where q.category_name='Geografia' and q.question_text='Qual é a capital de Pernambuco?');

notify pgrst, 'reload schema';-- QuizUp v7 - categorias/subcategorias, conteúdo enviado por usuários e conquistas
-- Execute DEPOIS do schema-v6.sql no SQL Editor do Supabase.

-- =========================================================
-- 1. CATEGORIAS: subcategorias, aprovação e autor
-- =========================================================
alter table public.categories add column if not exists parent_id uuid references public.categories(id) on delete set null;
alter table public.categories add column if not exists approved boolean not null default true;
alter table public.categories add column if not exists created_by uuid references auth.users(id) on delete set null;

update public.categories set approved=true where approved is null;
create index if not exists categories_parent_idx on public.categories(parent_id);
create index if not exists categories_approved_idx on public.categories(approved,name);

-- =========================================================
-- 2. PERGUNTAS: aprovação
-- =========================================================
alter table public.questions add column if not exists approval_status text not null default 'approved';
update public.questions set approval_status='approved' where approval_status is null or approval_status='';
alter table public.questions drop constraint if exists questions_approval_status_check;
alter table public.questions add constraint questions_approval_status_check check(approval_status in ('pending','approved','rejected'));
create index if not exists questions_approval_idx on public.questions(approval_status,active,category_name);
create index if not exists questions_created_by_idx on public.questions(created_by);

-- =========================================================
-- 3. CONQUISTAS
-- =========================================================
create table if not exists public.achievements(
  id uuid primary key default gen_random_uuid(),
  title text not null unique,
  description text,
  icon text default '🏆',
  active boolean not null default true,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);
create index if not exists achievements_active_idx on public.achievements(active,created_at);

-- Conquistas iniciais do jogo, sem duplicar as existentes.
insert into public.achievements(title,description,icon,active)
values
('Primeira Vitória','Vença sua primeira partida.','🏆',true),
('Sequência de 3','Vença 3 partidas seguidas.','🔥',true),
('Rápido no Gatilho','Responda perguntas rapidamente.','⚡',true)
on conflict(title) do nothing;

-- =========================================================
-- 4. RLS / PERMISSÕES
-- =========================================================
alter table public.categories enable row level security;
alter table public.questions enable row level security;
alter table public.achievements enable row level security;

-- Categorias: todos autenticados veem apenas aprovadas; admin vê todas.
drop policy if exists categories_read on public.categories;
drop policy if exists categories_admin_insert on public.categories;
drop policy if exists categories_admin_update on public.categories;
drop policy if exists categories_admin_delete on public.categories;
drop policy if exists categories_user_insert on public.categories;

create policy categories_read on public.categories
for select to authenticated
using(
  approved=true
  or created_by=(select auth.uid())
  or exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='admin')
);

create policy categories_admin_insert on public.categories
for insert to authenticated
with check(
  approved=true
  and exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='admin')
);

create policy categories_user_insert on public.categories
for insert to authenticated
with check(
  approved=false
  and created_by=(select auth.uid())
);

create policy categories_admin_update on public.categories
for update to authenticated
using(exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='admin'))
with check(exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='admin'));

create policy categories_admin_delete on public.categories
for delete to authenticated
using(exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='admin'));

-- Perguntas: jogadores só veem aprovadas/ativas, ou suas próprias pendentes; admin vê tudo.
drop policy if exists questions_read on public.questions;
drop policy if exists questions_admin_insert on public.questions;
drop policy if exists questions_admin_update on public.questions;
drop policy if exists questions_admin_delete on public.questions;
drop policy if exists questions_user_insert on public.questions;

create policy questions_read on public.questions
for select to authenticated
using(
  (active=true and approval_status='approved')
  or created_by=(select auth.uid())
  or exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='admin')
);

create policy questions_admin_insert on public.questions
for insert to authenticated
with check(
  approval_status='approved'
  and active=true
  and exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='admin')
);

create policy questions_user_insert on public.questions
for insert to authenticated
with check(
  approval_status='pending'
  and active=false
  and created_by=(select auth.uid())
);

create policy questions_admin_update on public.questions
for update to authenticated
using(exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='admin'))
with check(exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='admin'));

create policy questions_admin_delete on public.questions
for delete to authenticated
using(exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='admin'));

-- Conquistas: usuários veem apenas publicadas/ativas; somente admin cria/edita/exclui.
drop policy if exists achievements_read on public.achievements;
drop policy if exists achievements_admin_insert on public.achievements;
drop policy if exists achievements_admin_update on public.achievements;
drop policy if exists achievements_admin_delete on public.achievements;

create policy achievements_read on public.achievements
for select to authenticated
using(active=true or exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='admin'));

create policy achievements_admin_insert on public.achievements
for insert to authenticated
with check(exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='admin'));

create policy achievements_admin_update on public.achievements
for update to authenticated
using(exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='admin'))
with check(exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='admin'));

create policy achievements_admin_delete on public.achievements
for delete to authenticated
using(exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='admin'));

-- Permissões necessárias ao cliente.
grant select on public.achievements to authenticated;
grant insert on public.achievements to authenticated;
grant update,delete on public.achievements to authenticated;
grant select,insert on public.categories to authenticated;
grant update,delete on public.categories to authenticated;
grant select,insert on public.questions to authenticated;
grant update,delete on public.questions to authenticated;

notify pgrst, 'reload schema';
