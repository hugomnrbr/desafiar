-- QuizUp v17
-- Corrige: presença prematura no início do match, cronômetro, sincronização e UX de respostas.
-- Execute depois do upgrade-v16.sql.

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
  stale_seen timestamptz;
  opponent_count int;
  grace_seconds int := 12;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  select * into m from public.matches where id=p_match_id for update;
  if m.id is null or not(uid=any(m.player_ids)) then raise exception 'match not found'; end if;
  if m.status='finished' then return jsonb_build_object('finished',true,'status','finished'); end if;

  insert into public.match_presence(match_id,user_id,last_seen_at)
  values(p_match_id,uid,now())
  on conflict(match_id,user_id) do update set last_seen_at=excluded.last_seen_at;

  -- Nunca declare abandono antes que o adversário tenha tido uma chance real
  -- de abrir o match. Durante os primeiros segundos após a criação, o outro
  -- navegador ainda pode estar carregando a partida.
  if m.started_at is not null and now() < m.started_at + make_interval(secs=>grace_seconds) then
    return jsonb_build_object('finished',false,'present',true,'grace',true);
  end if;

  select count(*) into opponent_count
  from public.match_presence mp
  where mp.match_id=m.id
    and mp.user_id<>uid
    and mp.last_seen_at>now()-interval '5 seconds';

  if opponent_count=0 then
    -- Só considera abandono automaticamente se o adversário já registrou
    -- presença alguma vez ou se a janela inicial já passou.
    select x,mp.last_seen_at into stale_user,stale_seen
    from unnest(m.player_ids) x
    left join public.match_presence mp on mp.match_id=m.id and mp.user_id=x
    where x<>uid
    order by mp.last_seen_at nulls first
    limit 1;

    if stale_user is not null then
      return public._finish_forfeit(m.id,stale_user);
    end if;
  end if;

  return jsonb_build_object('finished',false,'present',true);
end;
$$;

-- Garante que a rodada seja iniciada uma única vez e que o timestamp oficial
-- permaneça igual para os dois jogadores.
create or replace function public.start_match_round(p_match_id uuid)
returns public.matches
language plpgsql
security definer
set search_path=''
as $$
declare
  uid uuid := auth.uid();
  m public.matches;
  started text;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  select * into m from public.matches where id=p_match_id for update;
  if m.id is null or not (uid=any(m.player_ids)) then raise exception 'match not found'; end if;
  if m.status <> 'playing' then return m; end if;
  started := m.state->>'question_started_at';
  if started is null or started='' or started='null' then
    update public.matches
      set state=jsonb_set(coalesce(m.state,'{}'::jsonb),'{question_started_at}',to_jsonb(extract(epoch from clock_timestamp())),true)
      where id=m.id
      returning * into m;
  end if;
  return m;
end;
$$;

grant execute on function public.start_match_round(uuid) to authenticated;
grant execute on function public.check_match_presence(uuid) to authenticated;
notify pgrst, 'reload schema';
