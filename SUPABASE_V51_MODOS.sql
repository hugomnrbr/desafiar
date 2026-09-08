-- Q-Rival v51 — modos, torneios e administração centralizada
-- Execute DEPOIS dos SQLs anteriores. Não apaga dados existentes.
create extension if not exists pgcrypto;

create table if not exists public.qr_mode_settings (
  id integer primary key default 1 check(id=1),
  enabled boolean not null default true,
  sudden_death_enabled boolean not null default true,
  sudden_death_max_players integer not null default 8 check(sudden_death_max_players between 2 and 8),
  sudden_death_questions integer not null default 10 check(sudden_death_questions between 3 and 20),
  sudden_death_seconds integer not null default 15 check(sudden_death_seconds between 5 and 60),
  daily_missions_enabled boolean not null default true,
  streak_enabled boolean not null default true,
  free_chest_enabled boolean not null default true,
  creator_system_enabled boolean not null default true,
  special_events_enabled boolean not null default true,
  season_pass_enabled boolean not null default true,
  rotating_shop_enabled boolean not null default true,
  impossible_challenge_enabled boolean not null default true,
  updated_at timestamptz not null default now()
);
insert into public.qr_mode_settings(id) values(1) on conflict(id) do nothing;

create table if not exists public.qr_sudden_rooms (
  id uuid primary key default gen_random_uuid(),
  code text unique not null,
  host_id uuid not null references public.profiles(id) on delete cascade,
  category text not null default 'Geral',
  max_players integer not null default 8 check(max_players between 2 and 8),
  question_ids uuid[] not null default '{}',
  current_question integer not null default 0,
  status text not null default 'waiting' check(status in ('waiting','running','finished','cancelled')),
  state jsonb not null default '{}'::jsonb,
  winner_id uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  started_at timestamptz,
  finished_at timestamptz
);
create table if not exists public.qr_sudden_players (
  room_id uuid not null references public.qr_sudden_rooms(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  score integer not null default 0,
  status text not null default 'active' check(status in ('active','eliminated','winner')),
  joined_at timestamptz not null default now(),
  last_answer_question integer not null default -1,
  primary key(room_id,user_id)
);
create index if not exists qr_sudden_players_room on public.qr_sudden_players(room_id,status,score desc);

alter table public.qr_sudden_rooms enable row level security;
alter table public.qr_sudden_players enable row level security;
do $$ begin
 if not exists(select 1 from pg_policies where tablename='qr_sudden_rooms' and policyname='qr_sudden_rooms_read') then
  create policy qr_sudden_rooms_read on public.qr_sudden_rooms for select to authenticated using(status in ('waiting','running') or host_id=auth.uid() or public.is_admin());
 end if;
 if not exists(select 1 from pg_policies where tablename='qr_sudden_players' and policyname='qr_sudden_players_read') then
  create policy qr_sudden_players_read on public.qr_sudden_players for select to authenticated using(exists(select 1 from public.qr_sudden_players me where me.room_id=qr_sudden_players.room_id and me.user_id=auth.uid()) or public.is_admin());
 end if;
end $$;

create or replace function public.qr_create_sudden_room(p_category text default 'Geral')
returns uuid language plpgsql security definer set search_path=public as $$
declare rid uuid; c text; maxp integer;
begin
 if auth.uid() is null then raise exception 'Faça login.'; end if;
 if not exists(select 1 from qr_mode_settings where id=1 and enabled and sudden_death_enabled) then raise exception 'Modo Morte Súbita está desativado.'; end if;
 select sudden_death_max_players into maxp from qr_mode_settings where id=1;
 loop c:=upper(substr(encode(gen_random_bytes(5),'hex'),1,6)); exit when not exists(select 1 from qr_sudden_rooms where code=c); end loop;
 insert into qr_sudden_rooms(code,host_id,category,max_players) values(c,auth.uid(),coalesce(nullif(trim(p_category),''),'Geral'),maxp) returning id into rid;
 insert into qr_sudden_players(room_id,user_id) values(rid,auth.uid());
 return rid;
end $$;
revoke all on function public.qr_create_sudden_room(text) from public; grant execute on function public.qr_create_sudden_room(text) to authenticated;

create or replace function public.qr_join_sudden_room(p_code text)
returns uuid language plpgsql security definer set search_path=public as $$
declare r qr_sudden_rooms; n integer;
begin
 if auth.uid() is null then raise exception 'Faça login.'; end if;
 select * into r from qr_sudden_rooms where code=upper(trim(p_code)) for update;
 if not found then raise exception 'Sala não encontrada.'; end if;
 if r.status<>'waiting' then raise exception 'Esta sala já começou ou terminou.'; end if;
 select count(*) into n from qr_sudden_players where room_id=r.id;
 if n>=r.max_players then raise exception 'Sala lotada.'; end if;
 insert into qr_sudden_players(room_id,user_id) values(r.id,auth.uid()) on conflict do nothing;
 return r.id;
end $$;
revoke all on function public.qr_join_sudden_room(text) from public; grant execute on function public.qr_join_sudden_room(text) to authenticated;

create or replace function public.qr_find_sudden_room(p_category text default 'Geral')
returns uuid language plpgsql security definer set search_path=public as $$
declare rid uuid;
begin
 select r.id into rid from qr_sudden_rooms r where r.status='waiting' and r.category=coalesce(nullif(trim(p_category),''),'Geral') and exists(select 1 from qr_sudden_players p where p.room_id=r.id and p.user_id<>auth.uid()) order by r.created_at limit 1 for update skip locked;
 if rid is null then return public.qr_create_sudden_room(p_category); end if;
 perform public.qr_join_sudden_room((select code from qr_sudden_rooms where id=rid));
 return rid;
end $$;
revoke all on function public.qr_find_sudden_room(text) from public; grant execute on function public.qr_find_sudden_room(text) to authenticated;

create or replace function public.qr_start_sudden_room(p_room_id uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare r qr_sudden_rooms; ids uuid[]; qn integer; lim integer; st timestamptz;
begin
 select * into r from qr_sudden_rooms where id=p_room_id for update;
 if not found then raise exception 'Sala não encontrada.'; end if;
 if r.host_id<>auth.uid() and not public.is_admin() then raise exception 'Somente o criador da sala pode iniciar.'; end if;
 if r.status<>'waiting' then return jsonb_build_object('ok',true,'status',r.status); end if;
 select count(*) into lim from qr_sudden_players where room_id=r.id;
 if lim<2 then raise exception 'É preciso ter pelo menos 2 jogadores.'; end if;
 select array_agg(id order by random()) into ids from (select id from questions where active=true and approval_status='approved' and category_name=r.category order by random() limit (select sudden_death_questions from qr_mode_settings where id=1)) q;
 if coalesce(array_length(ids,1),0)<3 then select array_agg(id order by random()) into ids from (select id from questions where active=true and approval_status='approved' order by random() limit (select sudden_death_questions from qr_mode_settings where id=1)) q; end if;
 if coalesce(array_length(ids,1),0)<3 then raise exception 'Não há perguntas suficientes.'; end if;
 st:=now();
 update qr_sudden_rooms set question_ids=ids,current_question=0,status='running',started_at=st,state=jsonb_build_object('question_started_at',extract(epoch from st),'question_seconds',(select sudden_death_seconds from qr_mode_settings where id=1)) where id=r.id;
 return jsonb_build_object('ok',true,'room_id',r.id);
end $$;
revoke all on function public.qr_start_sudden_room(uuid) from public; grant execute on function public.qr_start_sudden_room(uuid) to authenticated;

create or replace function public.qr_submit_sudden_answer(p_room_id uuid,p_question_index integer,p_answer_index integer)
returns jsonb language plpgsql security definer set search_path=public as $$
declare r qr_sudden_rooms; me qr_sudden_players; q questions; correct boolean; remain integer; active_count integer; winner uuid; st timestamptz; nextq integer;
begin
 select * into r from qr_sudden_rooms where id=p_room_id for update;
 if not found or r.status<>'running' then raise exception 'Sala não está em partida.'; end if;
 select * into me from qr_sudden_players where room_id=r.id and user_id=auth.uid() for update;
 if not found or me.status<>'active' then raise exception 'Você foi eliminado.'; end if;
 if me.last_answer_question=p_question_index then return jsonb_build_object('ok',true,'duplicate',true); end if;
 if p_question_index<>r.current_question then raise exception 'Pergunta desatualizada.'; end if;
 select * into q from questions where id=r.question_ids[p_question_index+1];
 correct:=q.correct_index=p_answer_index;
 if correct then update qr_sudden_players set score=score+1,last_answer_question=p_question_index where room_id=r.id and user_id=auth.uid(); else update qr_sudden_players set status='eliminated',last_answer_question=p_question_index where room_id=r.id and user_id=auth.uid(); end if;
 select count(*) into active_count from qr_sudden_players where room_id=r.id and status='active';
 if active_count<=1 then
   select user_id into winner from qr_sudden_players where room_id=r.id and status='active' order by score desc,joined_at limit 1;
   if winner is null then select user_id into winner from qr_sudden_players where room_id=r.id order by score desc,joined_at limit 1; end if;
   update qr_sudden_players set status='winner' where room_id=r.id and user_id=winner;
   update qr_sudden_rooms set status='finished',winner_id=winner,finished_at=now() where id=r.id;
   return jsonb_build_object('ok',true,'correct',correct,'finished',true,'winner_id',winner);
 end if;
 -- Só avança quando todos os jogadores que ainda estão vivos responderam à pergunta.
 if exists(select 1 from qr_sudden_players where room_id=r.id and status='active' and last_answer_question<>p_question_index) then
   return jsonb_build_object('ok',true,'correct',correct,'finished',false,'waiting',true);
 end if;
 nextq:=r.current_question+1;
 if nextq>=coalesce(array_length(r.question_ids,1),0) then
   select user_id into winner from qr_sudden_players where room_id=r.id and status='active' order by score desc,joined_at limit 1;
   update qr_sudden_players set status='winner' where room_id=r.id and user_id=winner;
   update qr_sudden_rooms set status='finished',winner_id=winner,finished_at=now() where id=r.id;
   return jsonb_build_object('ok',true,'correct',correct,'finished',true,'winner_id',winner);
 end if;
 st:=now();
 update qr_sudden_rooms set current_question=nextq,state=jsonb_build_object('question_started_at',extract(epoch from st),'question_seconds',(select sudden_death_seconds from qr_mode_settings where id=1)) where id=r.id;
 return jsonb_build_object('ok',true,'correct',correct,'finished',false,'next_question',nextq);
end $$;
revoke all on function public.qr_submit_sudden_answer(uuid,integer,integer) from public; grant execute on function public.qr_submit_sudden_answer(uuid,integer,integer) to authenticated;

-- Avaliação dos quizzes criados pelos jogadores.
create table if not exists public.qr_quiz_ratings (
  quiz_category_id uuid not null references public.categories(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  rating integer not null check(rating between 1 and 5),
  review text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key(quiz_category_id,user_id)
);
create index if not exists qr_quiz_ratings_category on public.qr_quiz_ratings(quiz_category_id);
alter table public.qr_quiz_ratings enable row level security;
do $$ begin
 if not exists(select 1 from pg_policies where tablename='qr_quiz_ratings' and policyname='qr_quiz_ratings_read') then create policy qr_quiz_ratings_read on public.qr_quiz_ratings for select to authenticated using(true); end if;
 if not exists(select 1 from pg_policies where tablename='qr_quiz_ratings' and policyname='qr_quiz_ratings_write') then create policy qr_quiz_ratings_write on public.qr_quiz_ratings for insert to authenticated with check(user_id=auth.uid()); end if;
 if not exists(select 1 from pg_policies where tablename='qr_quiz_ratings' and policyname='qr_quiz_ratings_update') then create policy qr_quiz_ratings_update on public.qr_quiz_ratings for update to authenticated using(user_id=auth.uid()) with check(user_id=auth.uid()); end if;
end $$;

create or replace function public.qr_rate_quiz(p_category_id uuid,p_rating integer,p_review text default null)
returns jsonb language plpgsql security definer set search_path=public as $$
begin
 if not exists(select 1 from categories where id=p_category_id and approved=true) then raise exception 'Quiz não encontrado.'; end if;
 insert into qr_quiz_ratings(quiz_category_id,user_id,rating,review) values(p_category_id,auth.uid(),p_rating,nullif(trim(p_review),'')) on conflict(quiz_category_id,user_id) do update set rating=excluded.rating,review=excluded.review,updated_at=now();
 return jsonb_build_object('ok',true);
end $$;
revoke all on function public.qr_rate_quiz(uuid,integer,text) from public; grant execute on function public.qr_rate_quiz(uuid,integer,text) to authenticated;

-- Torneios: exatamente 4 faixas de entrada e no máximo 18 jogadores.
alter table public.qr_tournaments add column if not exists entry_fee integer not null default 100;
alter table public.qr_tournaments add column if not exists prize_pool bigint not null default 0;
update public.qr_tournaments set max_players=least(coalesce(max_players,18),18), entry_fee=case when entry_fee in (100,200,500,1000) then entry_fee else 100 end where max_players>18 or entry_fee not in (100,200,500,1000);
alter table public.qr_tournaments add column if not exists winner_id uuid references public.profiles(id) on delete set null;
do $$ begin
 if not exists(select 1 from pg_constraint where conrelid='public.qr_tournaments'::regclass and conname='qr_tournaments_entry_fee') then alter table public.qr_tournaments add constraint qr_tournaments_entry_fee check(entry_fee in (100,200,500,1000)); end if;
 alter table public.qr_tournaments drop constraint if exists qr_tournaments_max;
 alter table public.qr_tournaments add constraint qr_tournaments_max check(max_players between 2 and 18);
end $$;

create or replace function public.qr_join_tournament(p_tournament_id uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare t qr_tournaments; n integer; newbal bigint;
begin
 if auth.uid() is null then raise exception 'Faça login.'; end if;
 select * into t from qr_tournaments where id=p_tournament_id for update;
 if not found then raise exception 'Torneio não encontrado.'; end if;
 if t.status<>'open' or now()<t.start_at or now()>t.end_at then raise exception 'Inscrições fechadas.'; end if;
 select count(*) into n from qr_tournament_entries where tournament_id=t.id;
 if n>=least(t.max_players,18) then raise exception 'Torneio lotado.'; end if;
 if exists(select 1 from qr_tournament_entries where tournament_id=t.id and user_id=auth.uid()) then return jsonb_build_object('ok',true,'already',true); end if;
 update profiles set coins=coalesce(coins,0)-t.entry_fee where id=auth.uid() and coalesce(coins,0)>=t.entry_fee returning coins into newbal;
 if newbal is null then raise exception 'Você não tem QuizCoins suficientes.'; end if;
 insert into qr_tournament_entries(tournament_id,user_id) values(t.id,auth.uid());
 update qr_tournaments set prize_pool=coalesce(prize_pool,0)+t.entry_fee where id=t.id;
 return jsonb_build_object('ok',true,'balance',newbal,'entry_fee',t.entry_fee,'prize_pool',coalesce(t.prize_pool,0)+t.entry_fee);
end $$;
revoke all on function public.qr_join_tournament(uuid) from public; grant execute on function public.qr_join_tournament(uuid) to authenticated;

create or replace function public.qr_finish_tournament(p_tournament_id uuid,p_winner_id uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare t qr_tournaments; pool bigint; exists_entry boolean; newbal bigint;
begin
 if not public.is_admin() then raise exception 'Acesso negado.'; end if;
 select * into t from qr_tournaments where id=p_tournament_id for update;
 if not found then raise exception 'Torneio não encontrado.'; end if;
 select exists(select 1 from qr_tournament_entries where tournament_id=t.id and user_id=p_winner_id) into exists_entry;
 if not exists_entry then raise exception 'O vencedor precisa estar inscrito.'; end if;
 if t.winner_id is not null then raise exception 'Este torneio já tem vencedor.'; end if;
 pool:=coalesce(t.prize_pool,0);
 update profiles set coins=coalesce(coins,0)+pool where id=p_winner_id returning coins into newbal;
 update qr_tournaments set winner_id=p_winner_id,status='closed' where id=t.id;
 return jsonb_build_object('ok',true,'winner_id',p_winner_id,'prize_pool',pool,'winner_balance',newbal);
end $$;
revoke all on function public.qr_finish_tournament(uuid,uuid) from public; grant execute on function public.qr_finish_tournament(uuid,uuid) to authenticated;

-- Temporadas / passe
create table if not exists public.qr_season_rewards (
 id uuid primary key default gen_random_uuid(), season_id uuid not null references public.qr_seasons(id) on delete cascade,
 level integer not null check(level>0), reward_type text not null default 'coins', reward_coins integer not null default 0, reward_item_id text, premium_only boolean not null default false,
 unique(season_id,level)
);

-- Loja rotativa
create table if not exists public.qr_shop_rotation (
 id uuid primary key default gen_random_uuid(), item_id text not null, starts_at timestamptz not null, ends_at timestamptz not null, active boolean not null default true, sort_order integer not null default 0, created_by uuid references public.profiles(id), check(ends_at>starts_at)
);
create index if not exists qr_shop_rotation_active on public.qr_shop_rotation(active,starts_at,ends_at);

-- Desafio impossível controlado pelo admin
create table if not exists public.qr_impossible_challenges (
 id uuid primary key default gen_random_uuid(), title text not null, description text, category text, question_id uuid references public.questions(id) on delete set null, reward_coins integer not null default 0, reward_xp integer not null default 0, reward_item_id text, starts_at timestamptz not null, ends_at timestamptz not null, active boolean not null default true, created_by uuid references public.profiles(id), check(ends_at>starts_at)
);

-- Todos os novos catálogos são administráveis apenas pelo admin.
alter table public.qr_mode_settings enable row level security;
alter table public.qr_season_rewards enable row level security;
alter table public.qr_shop_rotation enable row level security;
alter table public.qr_impossible_challenges enable row level security;
do $$ begin
 if not exists(select 1 from pg_policies where tablename='qr_mode_settings' and policyname='qr_mode_settings_read') then create policy qr_mode_settings_read on public.qr_mode_settings for select to authenticated using(true); end if;
 if not exists(select 1 from pg_policies where tablename='qr_mode_settings' and policyname='qr_mode_settings_admin') then create policy qr_mode_settings_admin on public.qr_mode_settings for all to authenticated using(public.is_admin()) with check(public.is_admin()); end if;
 if not exists(select 1 from pg_policies where tablename='qr_season_rewards' and policyname='qr_season_rewards_read') then create policy qr_season_rewards_read on public.qr_season_rewards for select to authenticated using(true); end if;
 if not exists(select 1 from pg_policies where tablename='qr_season_rewards' and policyname='qr_season_rewards_admin') then create policy qr_season_rewards_admin on public.qr_season_rewards for all to authenticated using(public.is_admin()) with check(public.is_admin()); end if;
 if not exists(select 1 from pg_policies where tablename='qr_shop_rotation' and policyname='qr_shop_rotation_read') then create policy qr_shop_rotation_read on public.qr_shop_rotation for select to authenticated using(active=true or public.is_admin()); end if;
 if not exists(select 1 from pg_policies where tablename='qr_shop_rotation' and policyname='qr_shop_rotation_admin') then create policy qr_shop_rotation_admin on public.qr_shop_rotation for all to authenticated using(public.is_admin()) with check(public.is_admin()); end if;
 if not exists(select 1 from pg_policies where tablename='qr_impossible_challenges' and policyname='qr_impossible_challenges_read') then create policy qr_impossible_challenges_read on public.qr_impossible_challenges for select to authenticated using((active=true and now() between starts_at and ends_at) or public.is_admin()); end if;
 if not exists(select 1 from pg_policies where tablename='qr_impossible_challenges' and policyname='qr_impossible_challenges_admin') then create policy qr_impossible_challenges_admin on public.qr_impossible_challenges for all to authenticated using(public.is_admin()) with check(public.is_admin()); end if;
end $$;

-- Realtime para salas.
do $$ begin
 if exists(select 1 from pg_publication where pubname='supabase_realtime') then
   if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='qr_sudden_rooms') then execute 'alter publication supabase_realtime add table public.qr_sudden_rooms'; end if;
   if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='qr_sudden_players') then execute 'alter publication supabase_realtime add table public.qr_sudden_players'; end if;
 end if;
exception when others then null; end $$;

-- Ranking de criadores por avaliações e partidas das categorias criadas.
create or replace function public.qr_creator_leaderboard(p_limit integer default 50)
returns table(rank bigint,user_id uuid,username text,avatar_url text,quizzes bigint,plays bigint,avg_rating numeric,rating_count bigint)
language sql security definer set search_path=public as $$
with cats as (
 select c.id,c.created_by,count(gr.*)::bigint plays
 from categories c left join game_results gr on gr.category=c.name
 where c.approved=true and c.created_by is not null
 group by c.id,c.created_by
), agg as (
 select c.created_by,count(distinct c.id)::bigint quizzes,coalesce(sum(c.plays),0)::bigint plays,
        coalesce(avg(r.rating),0)::numeric(10,2) avg_rating,count(r.rating)::bigint rating_count
 from cats c left join qr_quiz_ratings r on r.quiz_category_id=c.id
 group by c.created_by
), ranked as (select row_number() over(order by avg_rating desc,plays desc,quizzes desc)::bigint rank,* from agg)
select ranked.rank,p.id,p.username,p.avatar_url,ranked.quizzes,ranked.plays,ranked.avg_rating,ranked.rating_count
from ranked join profiles p on p.id=ranked.user_id order by ranked.rank limit greatest(1,least(coalesce(p_limit,50),100));
$$;
revoke all on function public.qr_creator_leaderboard(integer) from public; grant execute on function public.qr_creator_leaderboard(integer) to authenticated;

-- Sequência diária e baú diário: uma reivindicação por dia.
create table if not exists public.qr_daily_claims (
 user_id uuid not null references public.profiles(id) on delete cascade,
 claim_date date not null default current_date,
 streak integer not null default 1,
 reward_coins integer not null default 0,
 reward_item_id text,
 chest boolean not null default false,
 created_at timestamptz not null default now(),
 primary key(user_id,claim_date)
);
alter table public.qr_daily_claims enable row level security;
do $$ begin
 if not exists(select 1 from pg_policies where tablename='qr_daily_claims' and policyname='qr_daily_claims_read') then create policy qr_daily_claims_read on public.qr_daily_claims for select to authenticated using(user_id=auth.uid() or public.is_admin()); end if;
end $$;
create or replace function public.qr_claim_daily_reward(p_chest boolean default false)
returns jsonb language plpgsql security definer set search_path=public as $$
declare today date:=current_date; prev date; laststreak integer:=0; v_coins integer:=0; item text:=null; already boolean; nextstreak integer;
begin
 if auth.uid() is null then raise exception 'Faça login.'; end if;
 select exists(select 1 from qr_daily_claims where user_id=auth.uid() and claim_date=today and chest=p_chest) into already;
 if already then raise exception 'Recompensa de hoje já foi resgatada.'; end if;
 select max(claim_date),coalesce(max(streak),0) into prev,laststreak from qr_daily_claims where user_id=auth.uid() and chest=false;
 nextstreak:=case when prev=today-1 then laststreak+1 else 1 end;
 if p_chest then v_coins:=floor(random()*(greatest(0,(select chest_max_coins from qr_mode_settings where id=1)-(select chest_min_coins from qr_mode_settings where id=1))+1))::int+(select least(chest_min_coins,chest_max_coins) from qr_mode_settings where id=1); select id::text into item from premium_items where active=true and rarity in ('rare','epic','legendary','mythic') and random()<(select chest_item_chance from qr_mode_settings where id=1) order by random() limit 1; else v_coins:=(select daily_coin_base from qr_mode_settings where id=1)+least(nextstreak,25)*2; end if;
 insert into qr_daily_claims(user_id,claim_date,streak,reward_coins,reward_item_id,chest) values(auth.uid(),today,nextstreak,v_coins,item,p_chest);
 update profiles set coins=coalesce(profiles.coins,0)+v_coins where id=auth.uid();
 if item is not null then insert into user_premium_items(user_id,item_id,active,purchased_at) values(auth.uid(),item,false,now()) on conflict do nothing; end if;
 return jsonb_build_object('ok',true,'coins',v_coins,'item_id',item,'streak',nextstreak);
end $$;
revoke all on function public.qr_claim_daily_reward(boolean) from public; grant execute on function public.qr_claim_daily_reward(boolean) to authenticated;

-- Segurança: o administrador pode criar qualquer conteúdo, mas jogadores não podem alterar configurações do sistema.
alter table public.qr_seasons add column if not exists description text;
alter table public.qr_seasons add column if not exists xp_per_level integer not null default 250;

create table if not exists public.qr_impossible_claims (
  challenge_id uuid not null references public.qr_impossible_challenges(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key(challenge_id,user_id)
);
alter table public.qr_impossible_claims enable row level security;
do $$ begin
 if not exists(select 1 from pg_policies where tablename='qr_impossible_claims' and policyname='qr_impossible_claims_read') then create policy qr_impossible_claims_read on public.qr_impossible_claims for select to authenticated using(user_id=auth.uid() or public.is_admin()); end if;
end $$;
create or replace function public.qr_claim_impossible(p_challenge_id uuid,p_answer_index integer)
returns jsonb language plpgsql security definer set search_path=public as $$
declare c qr_impossible_challenges; q questions; already boolean; v_coins integer; v_xp integer;
begin
 if auth.uid() is null then raise exception 'Faça login.'; end if;
 select * into c from qr_impossible_challenges where id=p_challenge_id and active=true and now() between starts_at and ends_at;
 if not found then raise exception 'Desafio encerrado.'; end if;
 select exists(select 1 from qr_impossible_claims where challenge_id=c.id and user_id=auth.uid()) into already;
 if already then raise exception 'Você já respondeu este desafio.'; end if;
 if c.question_id is null then raise exception 'Pergunta não configurada.'; end if;
 select * into q from questions where id=c.question_id;
 if q.correct_index<>p_answer_index then insert into qr_impossible_claims(challenge_id,user_id) values(c.id,auth.uid()) on conflict do nothing; return jsonb_build_object('ok',false,'correct',false); end if;
 insert into qr_impossible_claims(challenge_id,user_id) values(c.id,auth.uid());
 v_coins:=greatest(0,c.reward_coins);v_xp:=greatest(0,c.reward_xp);
 update profiles set coins=coalesce(coins,0)+v_coins,xp=coalesce(xp,0)+v_xp where id=auth.uid();
 if c.reward_item_id is not null then insert into user_premium_items(user_id,item_id,active,purchased_at) values(auth.uid(),c.reward_item_id,false,now()) on conflict do nothing; end if;
 return jsonb_build_object('ok',true,'correct',true,'coins',v_coins,'xp',v_xp,'item_id',c.reward_item_id);
end $$;
revoke all on function public.qr_claim_impossible(uuid,integer) from public; grant execute on function public.qr_claim_impossible(uuid,integer) to authenticated;
alter table public.premium_items add column if not exists rarity text not null default 'common';
do $$ begin
 if not exists(select 1 from pg_constraint where conrelid='public.premium_items'::regclass and conname='premium_items_rarity_check') then alter table public.premium_items add constraint premium_items_rarity_check check(rarity in ('common','uncommon','rare','epic','legendary','mythic')); end if;
end $$;
alter table public.qr_mode_settings add column if not exists daily_coin_base integer not null default 25;
alter table public.qr_mode_settings add column if not exists chest_min_coins integer not null default 50;
alter table public.qr_mode_settings add column if not exists chest_max_coins integer not null default 150;
alter table public.qr_mode_settings add column if not exists chest_item_chance numeric(5,4) not null default 0.08;
