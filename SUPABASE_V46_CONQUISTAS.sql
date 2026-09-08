-- Q-Rival v46 — correção das conquistas
-- Execute no SQL Editor do Supabase depois de publicar o v46.
-- Não remove dados existentes.

create or replace function public.quizup_check_achievements_v2(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  a record;
  games_count integer := 0;
  wins_count integer := 0;
  coins_count bigint := 0;
  streak_count integer := 0;
  current_streak integer := 0;
  r record;
  should_unlock boolean;
begin
  if p_user_id is null then return; end if;
  if auth.uid() is not null and auth.uid() <> p_user_id and not exists (
    select 1 from public.profiles where id=auth.uid() and role='admin'
  ) then
    raise exception 'not allowed';
  end if;

  select count(*)::int, count(*) filter (where coalesce(won,false))::int
    into games_count, wins_count
    from public.game_results
   where user_id=p_user_id;

  select coalesce(coins,0)::bigint into coins_count
    from public.profiles where id=p_user_id;

  -- Maior sequência consecutiva de vitórias no histórico do jogador.
  for r in
    select coalesce(won,false) as won
      from public.game_results
     where user_id=p_user_id
     order by created_at asc
  loop
    if r.won then
      current_streak := current_streak + 1;
      if current_streak > streak_count then streak_count := current_streak; end if;
    else
      current_streak := 0;
    end if;
  end loop;

  for a in
    select id, criteria_type, coalesce(threshold,1)::int as threshold
      from public.achievements
     where active=true
  loop
    should_unlock := false;
    case lower(coalesce(a.criteria_type,''))
      when 'wins' then should_unlock := wins_count >= a.threshold;
      when 'games' then should_unlock := games_count >= a.threshold;
      when 'streak' then should_unlock := streak_count >= a.threshold;
      when 'coins' then should_unlock := coins_count >= a.threshold;
      when 'first_game' then should_unlock := games_count >= 1;
      else should_unlock := false;
    end case;

    if should_unlock and not exists (
      select 1 from public.user_achievements ua
       where ua.user_id=p_user_id and ua.achievement_id=a.id
    ) then
      insert into public.user_achievements(user_id,achievement_id,unlocked_at)
      values(p_user_id,a.id,now());
    end if;
  end loop;
end;
$$;

revoke all on function public.quizup_check_achievements_v2(uuid) from public;
grant execute on function public.quizup_check_achievements_v2(uuid) to authenticated;

-- Pontuação oficial da nova tabela de tempo.
create or replace function public.quizup_points_for_remaining_seconds(p_seconds integer)
returns integer
language sql
immutable
as $$
  select case
    when greatest(0,least(20,coalesce(p_seconds,0))) <= 0 then 0
    else greatest(8,20-floor((20-greatest(0,least(20,coalesce(p_seconds,0))))/3.0)::int*2)
  end;
$$;

revoke all on function public.quizup_points_for_remaining_seconds(integer) from public;
grant execute on function public.quizup_points_for_remaining_seconds(integer) to authenticated;

-- Corrige também partidas online já existentes sem precisar substituir a RPC
-- submit_match_answer: quando a RPC grava `remaining`/`score` dentro de answers,
-- este trigger ajusta o total para a tabela oficial de 20 segundos.
create or replace function public.quizup_fix_match_score_v46()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  item record;
  player_id text;
  old_score integer;
  remaining integer;
  desired integer;
  scores jsonb := coalesce(new.scores,'{}'::jsonb);
  current_total integer;
begin
  if new.answers is null then return new; end if;

  for item in select key, value from jsonb_each(new.answers)
  loop
    player_id := split_part(item.key, ':', 1);
    if player_id is null or player_id='' then continue; end if;
    if coalesce((item.value->>'correct')::boolean,false)
       and (item.value ? 'remaining')
       and (item.value->>'remaining') ~ '^-?[0-9]+$' then
      remaining := greatest(0,least(20,(item.value->>'remaining')::integer));
      desired := public.quizup_points_for_remaining_seconds(remaining);
      old_score := greatest(0,coalesce((item.value->>'score')::integer,0));
      current_total := coalesce((scores->>player_id)::integer,0);
      scores := jsonb_set(scores, array[player_id], to_jsonb(greatest(0,current_total-old_score+desired)), true);
    end if;
  end loop;

  new.scores := scores;
  return new;
end;
$$;

drop trigger if exists trg_quizup_fix_match_score_v46 on public.matches;
create trigger trg_quizup_fix_match_score_v46
after update of answers on public.matches
for each row
execute function public.quizup_fix_match_score_v46();
