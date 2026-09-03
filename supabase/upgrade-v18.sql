-- QuizUp v18
-- Matchmaking sem partidas duplicadas, fila anônima por avatares,
-- rematch na tela final, presença na sala final e suporte ao contador entre rodadas.
-- Execute depois do upgrade-v17.sql.

-- 1) Impede que o mesmo usuário seja colocado em duas partidas simultâneas,
-- mesmo se ele abrir várias abas/dispositivos ao mesmo tempo.
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
  qids uuid[];
  shuffled uuid[];
  team_a uuid[];
  team_b uuid[];
  seed int;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  if p_mode not in ('1v1','2v2') then raise exception 'invalid mode'; end if;
  if p_category is null or length(trim(p_category))=0 then raise exception 'invalid category'; end if;

  -- Um lock por usuário serializa todas as tentativas de matchmaking desse usuário.
  perform pg_advisory_xact_lock(hashtext(uid::text));

  -- Se já existe partida ativa, nunca cria outra.
  select m.id into mid
  from public.matches m
  where uid=any(m.player_ids)
    and m.status in ('waiting','ready','playing')
  order by m.created_at desc
  limit 1;
  if mid is not null then
    update public.match_queue
    set status='cancelled',last_seen_at=now()
    where user_id=uid and status='waiting';
    return mid;
  end if;

  -- Remove entradas antigas do próprio usuário em outras filas.
  update public.match_queue
  set status='cancelled',last_seen_at=now()
  where user_id=uid and status='waiting'
    and not(mode=p_mode and category=p_category);

  insert into public.match_queue(user_id,mode,category,status,last_seen_at)
  values(uid,p_mode,p_category,'waiting',now())
  on conflict (user_id,mode,category) where status='waiting'
  do update set last_seen_at=now();

  ids:=array[uid];
  for q in
    select mq.id,mq.user_id
    from public.match_queue mq
    where mq.mode=p_mode
      and mq.category=p_category
      and mq.status='waiting'
      and mq.user_id<>uid
      and mq.last_seen_at>now()-interval '5 seconds'
    order by random()
    for update skip locked
  loop
    if array_length(ids,1)>=needed then exit; end if;
    if not(q.user_id=any(ids)) then ids:=array_append(ids,q.user_id); end if;
  end loop;

  if array_length(ids,1)<needed then return null; end if;

  -- Confere novamente que nenhum dos candidatos entrou em outra partida.
  if exists(
    select 1 from public.matches m
    where m.status in ('waiting','ready','playing')
      and m.player_ids && ids
  ) then
    return null;
  end if;

  select array_agg(x.id order by random()) into qids
  from (
    select id from public.questions
    where active=true and approval_status='approved' and category_name=p_category
    order by random() limit 7
  ) x;
  if coalesce(array_length(qids,1),0)<7 then return null; end if;

  shuffled:=ids;
  if p_mode='1v1' then
    team_a:=array[shuffled[1]];team_b:=array[shuffled[2]];
  else
    seed:=floor(random()*1000000)::int;
    if seed%2=0 then
      team_a:=array[shuffled[1],shuffled[2]];team_b:=array[shuffled[3],shuffled[4]];
    else
      team_a:=array[shuffled[1],shuffled[3]];team_b:=array[shuffled[2],shuffled[4]];
    end if;
  end if;

  insert into public.matches(mode,category,player_ids,team_a,team_b,question_ids,scores,answers,state,status)
  values(
    p_mode,p_category,ids,team_a,team_b,qids,
    (select jsonb_object_agg(x::text,0) from unnest(ids)x),
    '{}'::jsonb,
    jsonb_build_object('question_started_at',null,'answered',jsonb_build_object()),
    'playing'
  ) returning id into mid;

  update public.match_queue
  set status='matched',last_seen_at=now()
  where user_id=any(ids) and mode=p_mode and category=p_category and status='waiting';

  update public.matches set started_at=now() where id=mid;
  return mid;
end;
$$;

grant execute on function public.find_or_create_match(text,text) to authenticated;

-- 2) A fila mostra somente avatares, sem expor nomes.
create or replace function public.get_queue_avatars(p_mode text,p_category text)
returns jsonb
language sql
security definer
set search_path=''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'avatar_url',p.avatar_url) order by random()),'[]'::jsonb)
  from (
    select mq.user_id
    from public.match_queue mq
    where mq.mode=p_mode and mq.category=p_category and mq.status='waiting'
      and mq.last_seen_at>now()-interval '5 seconds'
    order by random() limit 6
  ) q
  join public.profiles p on p.id=q.user_id;
$$;

grant execute on function public.get_queue_avatars(text,text) to authenticated;

-- 3) Presença na tela de resultado final.
create or replace function public.heartbeat_result_presence(p_match_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare uid uuid:=auth.uid();m public.matches;rid uuid;
begin
  if uid is null then raise exception 'not authenticated';end if;
  select * into m from public.matches where id=p_match_id;
  if m.id is null or not(uid=any(m.player_ids)) then raise exception 'match not found';end if;
  if m.status<>'finished' then return jsonb_build_object('ok',false);end if;
  insert into public.match_presence(match_id,user_id,last_seen_at)
  values(p_match_id,uid,now())
  on conflict(match_id,user_id) do update set last_seen_at=excluded.last_seen_at;
  rid:=nullif(m.state->>'rematch_match_id','')::uuid;
  return jsonb_build_object('ok',true,'rematch_match_id',rid);
end;
$$;

grant execute on function public.heartbeat_result_presence(uuid) to authenticated;

-- 4) Rematch direto somente se o outro jogador ainda estiver na tela final.
create or replace function public.rematch_match(p_match_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  uid uuid:=auth.uid();m public.matches;opp uuid;mid uuid;qids uuid[];scores jsonb;state jsonb;
begin
  if uid is null then raise exception 'not authenticated';end if;
  perform pg_advisory_xact_lock(hashtext(p_match_id::text));
  select * into m from public.matches where id=p_match_id for update;
  if m.id is null or m.status<>'finished' or not(uid=any(m.player_ids)) then
    return jsonb_build_object('ok',false,'opponent_present',false);
  end if;

  if m.state ? 'rematch_match_id' then
    mid:=nullif(m.state->>'rematch_match_id','')::uuid;
    if mid is not null then return jsonb_build_object('ok',true,'match_id',mid);end if;
  end if;

  select x into opp from unnest(m.player_ids)x where x<>uid limit 1;
  if opp is null then return jsonb_build_object('ok',false,'opponent_present',false);end if;
  if not exists(select 1 from public.match_presence mp where mp.match_id=m.id and mp.user_id=opp and mp.last_seen_at>now()-interval '6 seconds') then
    return jsonb_build_object('ok',false,'opponent_present',false);
  end if;

  select array_agg(x.id order by random()) into qids
  from (select id from public.questions where active=true and approval_status='approved' and category_name=m.category order by random() limit 7)x;
  if coalesce(array_length(qids,1),0)<7 then raise exception 'category does not have enough questions';end if;

  scores:=jsonb_build_object(uid::text,0,opp::text,0);
  state:=jsonb_build_object('question_started_at',null,'answered',jsonb_build_object());
  insert into public.matches(mode,category,player_ids,team_a,team_b,question_ids,scores,answers,state,status)
  values('1v1',m.category,array[uid,opp],array[uid],array[opp],qids,scores,'{}'::jsonb,state,'playing')
  returning id into mid;

  update public.matches
  set state=jsonb_set(coalesce(state,'{}'::jsonb),'{rematch_match_id}',to_jsonb(mid::text),true)
  where id=m.id;

  return jsonb_build_object('ok',true,'match_id',mid);
end;
$$;

grant execute on function public.rematch_match(uuid) to authenticated;
notify pgrst,'reload schema';

-- 5) Ao concluir uma rodada, a próxima pergunta fica agendada para +3s.
-- O cliente exibe "Próxima pergunta" durante esse intervalo e só então inicia os 10s.
create or replace function public.submit_match_answer(
  p_match_id uuid,p_question_index int,p_answer_index int,p_seconds int
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  uid uuid:=auth.uid();m public.matches;q public.questions;old_score int;add_score int:=0;key text;new_scores jsonb;new_answers jsonb;done_count int;elapsed numeric;remaining int;
begin
  if uid is null then raise exception 'not authenticated';end if;
  if p_answer_index<-1 or p_answer_index>3 then raise exception 'invalid answer';end if;
  select * into m from public.matches where id=p_match_id for update;
  if m.id is null or not(uid=any(m.player_ids)) then raise exception 'match not found';end if;
  if m.status<>'playing' then
    return jsonb_build_object('ok',false,'resync',true,'finished',m.status='finished','status',m.status,'current_question',m.current_question,'scores',m.scores,'answers',m.answers,'state',m.state);
  end if;
  if p_question_index<>m.current_question then
    return jsonb_build_object('ok',false,'resync',true,'finished',false,'status',m.status,'current_question',m.current_question,'scores',m.scores,'answers',m.answers,'state',m.state);
  end if;
  key:=uid::text||':'||p_question_index::text;
  if m.answers ? key then
    return jsonb_build_object('ok',true,'already_answered',true,'score',coalesce((m.scores->>uid::text)::int,0),'finished',m.status='finished');
  end if;
  if array_length(m.question_ids,1) is null or p_question_index+1>array_length(m.question_ids,1) then raise exception 'question missing';end if;
  select * into q from public.questions where id=m.question_ids[p_question_index+1];
  if q.id is null then raise exception 'question missing';end if;

  elapsed:=extract(epoch from clock_timestamp())-coalesce((m.state->>'question_started_at')::numeric,extract(epoch from clock_timestamp()));
  remaining:=greatest(0,10-floor(greatest(elapsed,0))::int);
  if p_answer_index=q.correct_index then
    if p_question_index=6 then add_score:=20+least(remaining,10)*2;
    else add_score:=10+least(remaining,10);
    end if;
  end if;
  old_score:=coalesce((m.scores->>uid::text)::int,0);
  new_scores:=jsonb_set(coalesce(m.scores,'{}'::jsonb),array[uid::text],to_jsonb(old_score+add_score),true);
  new_answers:=jsonb_set(coalesce(m.answers,'{}'::jsonb),array[key],jsonb_build_object('answer',p_answer_index,'correct',p_answer_index=q.correct_index,'score',add_score,'remaining',remaining),true);
  select count(*) into done_count from jsonb_object_keys(new_answers) k where split_part(k,':',2)=p_question_index::text;

  if done_count>=array_length(m.player_ids,1) then
    if p_question_index>=array_length(m.question_ids,1)-1 then
      update public.matches set scores=new_scores,answers=new_answers,status='finished',finished_at=now() where id=m.id;
      return jsonb_build_object('ok',true,'score',old_score+add_score,'added',add_score,'finished',true,'scores',new_scores,'answers',new_answers);
    else
      update public.matches
      set scores=new_scores,
          answers=new_answers,
          current_question=p_question_index+1,
          state=jsonb_build_object(
            'question_started_at',extract(epoch from clock_timestamp())+3,
            'answered',jsonb_build_object(),
            'transition','next_question'
          )
      where id=m.id;
      return jsonb_build_object('ok',true,'score',old_score+add_score,'added',add_score,'finished',false,'next_question',p_question_index+1,'scores',new_scores,'answers',new_answers);
    end if;
  else
    update public.matches set scores=new_scores,answers=new_answers where id=m.id;
    return jsonb_build_object('ok',true,'score',old_score+add_score,'added',add_score,'finished',false,'waiting',true,'scores',new_scores,'answers',new_answers);
  end if;
end;
$$;

grant execute on function public.submit_match_answer(uuid,int,int,int) to authenticated;
notify pgrst,'reload schema';
