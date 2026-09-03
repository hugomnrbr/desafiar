-- QuizUp v16
-- 1) Abandono: se um jogador sair da partida, os demais vencem.
-- 2) Presença: heartbeat para detectar fechamento do app/aba mesmo quando
--    beforeunload/pagehide não for executado pelo navegador.
-- 3) Desafios entre amigos: o desafiante recebe a partida em tempo real
--    quando o amigo aceita.

create table if not exists public.match_presence(
  match_id uuid not null references public.matches(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  last_seen_at timestamptz not null default now(),
  primary key(match_id,user_id)
);

create index if not exists match_presence_seen_idx
  on public.match_presence(match_id,last_seen_at);

alter table public.match_presence enable row level security;

revoke all on public.match_presence from anon;
grant select,insert,update on public.match_presence to authenticated;

drop policy if exists match_presence_select on public.match_presence;
drop policy if exists match_presence_insert on public.match_presence;
drop policy if exists match_presence_update on public.match_presence;

create policy match_presence_select on public.match_presence
for select to authenticated
using(user_id=(select auth.uid()) or exists(
  select 1 from public.matches m
  where m.id=match_presence.match_id
    and (select auth.uid())=any(m.player_ids)
));

create policy match_presence_insert on public.match_presence
for insert to authenticated
with check(user_id=(select auth.uid()));

create policy match_presence_update on public.match_presence
for update to authenticated
using(user_id=(select auth.uid()))
with check(user_id=(select auth.uid()));

create or replace function public.heartbeat_match(p_match_id uuid)
returns boolean
language plpgsql
security definer
set search_path=''
as $$
declare
  uid uuid := auth.uid();
  m public.matches;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  select * into m from public.matches where id=p_match_id;
  if m.id is null or not(uid=any(m.player_ids)) then return false; end if;
  if m.status <> 'playing' then return false; end if;

  insert into public.match_presence(match_id,user_id,last_seen_at)
  values(p_match_id,uid,now())
  on conflict(match_id,user_id) do update set last_seen_at=excluded.last_seen_at;
  return true;
end;
$$;

create or replace function public._finish_forfeit(p_match_id uuid,p_forfeiting_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  m public.matches;
  winners uuid[];
  pid uuid;
  mine int;
  won boolean;
begin
  select * into m from public.matches where id=p_match_id for update;
  if m.id is null or not(p_forfeiting_id=any(m.player_ids)) then
    raise exception 'match not found';
  end if;
  if m.status='finished' then
    return jsonb_build_object('ok',true,'already_finished',true);
  end if;

  if m.mode='2v2' then
    if p_forfeiting_id=any(coalesce(m.team_a,'{}'::uuid[])) then
      winners:=coalesce(m.team_b,'{}'::uuid[]);
    else
      winners:=coalesce(m.team_a,'{}'::uuid[]);
    end if;
  else
    winners:=array(select x from unnest(m.player_ids) x where x<>p_forfeiting_id);
  end if;

  update public.matches
  set status='finished',
      finished_at=now(),
      state=jsonb_set(
        jsonb_set(coalesce(state,'{}'::jsonb),'{forfeited_by}',to_jsonb(p_forfeiting_id::text),true),
        '{forfeit}',to_jsonb(true),true
      )
  where id=m.id;

  foreach pid in array m.player_ids loop
    mine:=coalesce((m.scores->>pid::text)::int,0);
    won:=pid=any(winners);
    if not exists(select 1 from public.game_results gr where gr.match_id=m.id and gr.user_id=pid) then
      insert into public.game_results(user_id,category,mode,score,won,match_id)
      values(pid,m.category,m.mode,mine,won,m.id);

      update public.profiles
      set xp=xp+greatest(mine,0),
          wins=wins+case when won then 1 else 0 end,
          losses=losses+case when won then 0 else 1 end,
          streak=case when won then streak+1 else 0 end,
          level=greatest(1,1+floor((xp+greatest(mine,0))/1000)::int)
      where id=pid;
    end if;
  end loop;

  return jsonb_build_object('ok',true,'forfeited_by',p_forfeiting_id,'winners',to_jsonb(winners),'scores',m.scores);
end;
$$;

create or replace function public.forfeit_match(p_match_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  uid uuid:=auth.uid();
  m public.matches;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  select * into m from public.matches where id=p_match_id;
  if m.id is null or not(uid=any(m.player_ids)) then raise exception 'match not found'; end if;
  return public._finish_forfeit(p_match_id,uid);
end;
$$;

create or replace function public.check_match_presence(p_match_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  uid uuid:=auth.uid();
  m public.matches;
  stale_user uuid;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  select * into m from public.matches where id=p_match_id for update;
  if m.id is null or not(uid=any(m.player_ids)) then raise exception 'match not found'; end if;
  if m.status='finished' then return jsonb_build_object('finished',true,'status','finished'); end if;

  insert into public.match_presence(match_id,user_id,last_seen_at)
  values(p_match_id,uid,now())
  on conflict(match_id,user_id) do update set last_seen_at=excluded.last_seen_at;

  select x into stale_user
  from unnest(m.player_ids) x
  where x<>uid
    and not exists(
      select 1 from public.match_presence mp
      where mp.match_id=m.id
        and mp.user_id=x
        and mp.last_seen_at>now()-interval '5 seconds'
    )
  limit 1;

  if stale_user is not null then
    return public._finish_forfeit(m.id,stale_user);
  end if;

  return jsonb_build_object('finished',false,'present',true);
end;
$$;

revoke all on function public.heartbeat_match(uuid) from public;
revoke all on function public.forfeit_match(uuid) from public;
revoke all on function public.check_match_presence(uuid) from public;
grant execute on function public.heartbeat_match(uuid) to authenticated;
grant execute on function public.forfeit_match(uuid) to authenticated;
grant execute on function public.check_match_presence(uuid) to authenticated;

notify pgrst, 'reload schema';
