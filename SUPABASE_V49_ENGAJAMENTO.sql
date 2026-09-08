-- Q-Rival v49 — Engajamento administrável
-- Execute DEPOIS dos SQLs base/v47/v48. Não apaga dados existentes.

create extension if not exists pgcrypto;

create table if not exists public.qr_events (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  description text,
  icon text default '🔥',
  event_type text not null default 'weekly',
  category text,
  start_at timestamptz not null,
  end_at timestamptz not null,
  active boolean not null default true,
  xp_multiplier numeric(6,2) not null default 1,
  coin_reward integer not null default 0,
  reward_item_id text,
  rules jsonb not null default '{}'::jsonb,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  constraint qr_events_dates check (end_at > start_at),
  constraint qr_events_type check (event_type in ('weekly','category','special'))
);

create table if not exists public.qr_missions (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  description text,
  icon text default '🎯',
  criteria_type text not null default 'games',
  target integer not null default 1,
  reward_xp integer not null default 0,
  reward_coins integer not null default 0,
  reward_item_id text,
  category text,
  start_at timestamptz not null,
  end_at timestamptz not null,
  active boolean not null default true,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  constraint qr_missions_dates check (end_at > start_at),
  constraint qr_missions_target check (target > 0),
  constraint qr_missions_type check (criteria_type in ('games','wins','streak','score'))
);

create table if not exists public.qr_seasons (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  start_at timestamptz not null,
  end_at timestamptz not null,
  active boolean not null default true,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  constraint qr_seasons_dates check (end_at > start_at)
);

create table if not exists public.qr_tournaments (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  description text,
  icon text default '🏟️',
  category text,
  start_at timestamptz not null,
  end_at timestamptz not null,
  status text not null default 'open',
  max_players integer not null default 64,
  reward_xp integer not null default 0,
  reward_coins integer not null default 0,
  reward_item_id text,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  constraint qr_tournaments_dates check (end_at > start_at),
  constraint qr_tournaments_status check (status in ('open','running','closed')),
  constraint qr_tournaments_max check (max_players >= 2)
);

create table if not exists public.qr_tournament_entries (
  id uuid primary key default gen_random_uuid(),
  tournament_id uuid not null references public.qr_tournaments(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  joined_at timestamptz not null default now(),
  score integer not null default 0,
  rank integer,
  unique(tournament_id,user_id)
);

create index if not exists qr_events_active_dates on public.qr_events(active,start_at,end_at);
create index if not exists qr_missions_active_dates on public.qr_missions(active,start_at,end_at);
create index if not exists qr_tournaments_status_dates on public.qr_tournaments(status,start_at,end_at);
create index if not exists qr_tournament_entries_tournament on public.qr_tournament_entries(tournament_id,score desc);

alter table public.qr_events enable row level security;
alter table public.qr_missions enable row level security;
alter table public.qr_seasons enable row level security;
alter table public.qr_tournaments enable row level security;
alter table public.qr_tournament_entries enable row level security;

do $$ begin
  if not exists (select 1 from pg_policies where tablename='qr_events' and policyname='qr_events_public_select') then
    create policy qr_events_public_select on public.qr_events for select to authenticated using (active=true or exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin'));
  end if;
  if not exists (select 1 from pg_policies where tablename='qr_events' and policyname='qr_events_admin_write') then
    create policy qr_events_admin_write on public.qr_events for all to authenticated using (exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin')) with check (exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin'));
  end if;
  if not exists (select 1 from pg_policies where tablename='qr_missions' and policyname='qr_missions_public_select') then
    create policy qr_missions_public_select on public.qr_missions for select to authenticated using (active=true or exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin'));
  end if;
  if not exists (select 1 from pg_policies where tablename='qr_missions' and policyname='qr_missions_admin_write') then
    create policy qr_missions_admin_write on public.qr_missions for all to authenticated using (exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin')) with check (exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin'));
  end if;
  if not exists (select 1 from pg_policies where tablename='qr_seasons' and policyname='qr_seasons_public_select') then
    create policy qr_seasons_public_select on public.qr_seasons for select to authenticated using (active=true or exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin'));
  end if;
  if not exists (select 1 from pg_policies where tablename='qr_seasons' and policyname='qr_seasons_admin_write') then
    create policy qr_seasons_admin_write on public.qr_seasons for all to authenticated using (exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin')) with check (exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin'));
  end if;
  if not exists (select 1 from pg_policies where tablename='qr_tournaments' and policyname='qr_tournaments_public_select') then
    create policy qr_tournaments_public_select on public.qr_tournaments for select to authenticated using (status in ('open','running') or exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin'));
  end if;
  if not exists (select 1 from pg_policies where tablename='qr_tournaments' and policyname='qr_tournaments_admin_write') then
    create policy qr_tournaments_admin_write on public.qr_tournaments for all to authenticated using (exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin')) with check (exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin'));
  end if;
  if not exists (select 1 from pg_policies where tablename='qr_tournament_entries' and policyname='qr_tournament_entries_select') then
    create policy qr_tournament_entries_select on public.qr_tournament_entries for select to authenticated using (user_id=auth.uid() or exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin'));
  end if;
  if not exists (select 1 from pg_policies where tablename='qr_tournament_entries' and policyname='qr_tournament_entries_insert') then
    create policy qr_tournament_entries_insert on public.qr_tournament_entries for insert to authenticated with check (user_id=auth.uid());
  end if;
end $$;

create or replace function public.qr_join_tournament(p_tournament_id uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare t record; n integer;
begin
  if auth.uid() is null then raise exception 'Faça login para participar.'; end if;
  select * into t from public.qr_tournaments where id=p_tournament_id for update;
  if not found then raise exception 'Torneio não encontrado.'; end if;
  if t.status <> 'open' or now() < t.start_at or now() > t.end_at then raise exception 'As inscrições deste torneio estão fechadas.'; end if;
  select count(*) into n from public.qr_tournament_entries where tournament_id=p_tournament_id;
  if n >= t.max_players then raise exception 'Torneio lotado.'; end if;
  insert into public.qr_tournament_entries(tournament_id,user_id) values(p_tournament_id,auth.uid()) on conflict(tournament_id,user_id) do nothing;
  return jsonb_build_object('ok',true,'message','Inscrição confirmada!');
end $$;
revoke all on function public.qr_join_tournament(uuid) from public;
grant execute on function public.qr_join_tournament(uuid) to authenticated;

create or replace function public.qr_weekly_leaderboard()
returns table(rank bigint,user_id uuid,username text,avatar_url text,points bigint,wins bigint,games bigint,league text)
language sql security definer set search_path=public as $$
with r as (
  select gr.user_id,
         sum(case when gr.won then 25 when gr.outcome='draw' then 8 else 3 end)::bigint + floor(sum(greatest(0,gr.score))/10.0)::bigint points,
         count(*)::bigint games,
         count(*) filter(where gr.won)::bigint wins
  from public.game_results gr
  where gr.created_at >= now()-interval '7 days'
  group by gr.user_id
), ranked as (
 select row_number() over(order by points desc,games desc)::bigint rnk,* from r
)
select ranked.rnk,p.id,p.username,p.avatar_url,ranked.points,ranked.wins,ranked.games,
 case when ranked.points>=1500 then 'Lendário' when ranked.points>=1000 then 'Mestre' when ranked.points>=650 then 'Diamante' when ranked.points>=400 then 'Ouro' when ranked.points>=200 then 'Prata' else 'Bronze' end
from ranked join public.profiles p on p.id=ranked.user_id
order by ranked.rnk;
$$;
revoke all on function public.qr_weekly_leaderboard() from public;
grant execute on function public.qr_weekly_leaderboard() to authenticated;

-- Recompensas configuradas pelo admin para missões concluídas.
-- O cliente só marca a conclusão; o crédito é feito por esta função, uma vez por missão/período.
create table if not exists public.qr_mission_claims (
 id uuid primary key default gen_random_uuid(), mission_id uuid not null references public.qr_missions(id) on delete cascade,
 user_id uuid not null references auth.users(id) on delete cascade, claimed_at timestamptz not null default now(), unique(mission_id,user_id)
);
alter table public.qr_mission_claims enable row level security;
do $$ begin
 if not exists(select 1 from pg_policies where tablename='qr_mission_claims' and policyname='qr_mission_claims_select') then create policy qr_mission_claims_select on public.qr_mission_claims for select to authenticated using(user_id=auth.uid() or exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin')); end if;
 if not exists(select 1 from pg_policies where tablename='qr_mission_claims' and policyname='qr_mission_claims_insert') then create policy qr_mission_claims_insert on public.qr_mission_claims for insert to authenticated with check(user_id=auth.uid()); end if;
end $$;

-- Compatibilidade: atualiza a sequência máxima quando uma partida termina, se a coluna existir.
create or replace function public.qr_current_streak(p_user_id uuid)
returns integer language plpgsql security definer set search_path=public as $$
declare r record; n integer:=0;
begin
 for r in select won from public.game_results where user_id=p_user_id order by created_at desc loop
   if coalesce(r.won,false) then n:=n+1; else exit; end if;
 end loop;
 return n;
end $$;
revoke all on function public.qr_current_streak(uuid) from public;
grant execute on function public.qr_current_streak(uuid) to authenticated;

-- Seed opcional: não cria eventos/missões automaticamente para não alterar a configuração do administrador.

-- Resgate seguro das missões. Cada missão pode ser resgatada uma única vez por jogador.
create or replace function public.qr_claim_mission(p_mission_id uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare m record; already boolean; v_games integer; v_wins integer; v_score integer; v_streak integer;
begin
  if auth.uid() is null then raise exception 'Faça login para resgatar.'; end if;
  select * into m from public.qr_missions where id=p_mission_id and active=true and now() between start_at and end_at;
  if not found then raise exception 'Missão indisponível.'; end if;
  select exists(select 1 from public.qr_mission_claims where mission_id=p_mission_id and user_id=auth.uid()) into already;
  if already then raise exception 'Esta recompensa já foi resgatada.'; end if;
  select count(*)::int,count(*) filter(where won)::int,coalesce(sum(score),0)::int into v_games,v_wins,v_score
    from public.game_results where user_id=auth.uid() and created_at>=date_trunc('day',now());
  v_streak:=public.qr_current_streak(auth.uid());
  if (m.criteria_type='games' and v_games<m.target) or (m.criteria_type='wins' and v_wins<m.target) or (m.criteria_type='score' and v_score<m.target) or (m.criteria_type='streak' and v_streak<m.target) then
    raise exception 'Você ainda não concluiu esta missão.';
  end if;
  insert into public.qr_mission_claims(mission_id,user_id) values(p_mission_id,auth.uid());
  update public.profiles set xp=coalesce(xp,0)+coalesce(m.reward_xp,0), coins=coalesce(coins,0)+coalesce(m.reward_coins,0) where id=auth.uid();
  if m.reward_item_id is not null then
    insert into public.user_premium_items(user_id,item_id,active,purchased_at) values(auth.uid(),m.reward_item_id,false,now()) on conflict do nothing;
  end if;
  return jsonb_build_object('ok',true,'message','Recompensa resgatada com sucesso!');
end $$;
revoke all on function public.qr_claim_mission(uuid) from public;
grant execute on function public.qr_claim_mission(uuid) to authenticated;
