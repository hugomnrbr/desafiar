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
