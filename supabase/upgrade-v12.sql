-- QuizUp v12
-- Partidas no formato clássico: 7 rodadas, 10 segundos por pergunta.
-- Rodadas 1-6: acerto = 10 pontos + 1 ponto por segundo restante (máx. 20).
-- Rodada 7 (bônus): acerto = 20 pontos + 2 pontos por segundo restante (máx. 40).
-- Erro ou tempo esgotado = 0 pontos.
-- Execute depois do upgrade-v11.sql.

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

  -- Perguntas da categoria. A partida só nasce quando temos 7 questões.
  select array_agg(x.id order by random()) into qids
  from (select id from public.questions where active=true and category_name=p_category order by random() limit 7) x;
  if coalesce(array_length(qids,1),0) < 7 then
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
    jsonb_build_object('question_started_at',null,'answered',jsonb_build_object()),
    'playing'
  ) returning id into mid;

  update public.match_queue set status='matched' where user_id = any(ids) and mode=p_mode and category=p_category and status='waiting';
  update public.matches set started_at=now() where id=mid;
  return mid;
end;
$$;


-- Inicia o cronômetro da rodada somente depois da tela 3-2-1.
-- A primeira chamada grava o horário; chamadas seguintes apenas devolvem o estado.
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

create or replace function public.submit_match_answer(
  p_match_id uuid,
  p_question_index int,
  p_answer_index int,
  p_seconds int
)
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
begin
  if uid is null then raise exception 'not authenticated'; end if;
  if p_seconds < 0 or p_seconds > 15 then raise exception 'invalid seconds'; end if;

  select * into m from public.matches where id=p_match_id for update;

  if m.id is null or not (uid=any(m.player_ids)) then
    raise exception 'match not found';
  end if;

  -- Se a partida já terminou, devolve o estado atual em vez de gerar erro.
  if m.status <> 'playing' then
    return jsonb_build_object(
      'ok',false,
      'resync',true,
      'finished',m.status='finished',
      'status',m.status,
      'current_question',m.current_question,
      'scores',m.scores,
      'answers',m.answers,
      'state',m.state
    );
  end if;

  -- Se o navegador perdeu um UPDATE do Realtime, devolve o estado autoritativo.
  -- O app então troca silenciosamente para a pergunta correta.
  if p_question_index <> m.current_question then
    return jsonb_build_object(
      'ok',false,
      'resync',true,
      'finished',false,
      'status',m.status,
      'current_question',m.current_question,
      'scores',m.scores,
      'answers',m.answers,
      'state',m.state
    );
  end if;

  if p_answer_index < -1 or p_answer_index > 3 then
    raise exception 'invalid answer';
  end if;

  key := uid::text || ':' || p_question_index::text;

  -- Reenvio da mesma resposta é idempotente.
  if (m.answers ? key) then
    return jsonb_build_object(
      'ok',true,
      'already_answered',true,
      'score',coalesce((m.scores->>uid::text)::int,0),
      'finished',m.status='finished'
    );
  end if;

  if array_length(m.question_ids,1) is null
     or p_question_index+1 > array_length(m.question_ids,1) then
    raise exception 'question missing';
  end if;

  select * into q from public.questions where id=m.question_ids[p_question_index+1];
  if q.id is null then raise exception 'question missing'; end if;

  if p_answer_index=q.correct_index then
    if p_question_index=6 then
      add_score := 20 + (least(greatest(p_seconds,0),10) * 2);
    else
      add_score := 10 + least(greatest(p_seconds,0),10);
    end if;
  end if;

  old_score := coalesce((m.scores->>uid::text)::int,0);
  new_scores := jsonb_set(m.scores,array[uid::text],to_jsonb(old_score+add_score),true);
  new_answers := jsonb_set(
    m.answers,
    array[key],
    jsonb_build_object(
      'answer',p_answer_index,
      'correct',p_answer_index=q.correct_index,
      'score',add_score
    ),true
  );

  select count(*) into done_count
  from jsonb_object_keys(new_answers) k
  where split_part(k,':',2)=p_question_index::text;

  if done_count >= array_length(m.player_ids,1) then
    if p_question_index >= array_length(m.question_ids,1)-1 then
      update public.matches
      set scores=new_scores,
          answers=new_answers,
          status='finished',
          finished_at=now()
      where id=m.id;

      return jsonb_build_object(
        'ok',true,
        'score',old_score+add_score,
        'added',add_score,
        'finished',true,
        'scores',new_scores
      );
    else
      update public.matches
      set scores=new_scores,
          answers=new_answers,
          current_question=p_question_index+1,
          state=jsonb_build_object(
            'question_started_at',extract(epoch from clock_timestamp()),
            'answered',jsonb_build_object()
          )
      where id=m.id;

      return jsonb_build_object(
        'ok',true,
        'score',old_score+add_score,
        'added',add_score,
        'finished',false,
        'next_question',p_question_index+1,
        'scores',new_scores
      );
    end if;
  else
    update public.matches
    set scores=new_scores,answers=new_answers
    where id=m.id;

    return jsonb_build_object(
      'ok',true,
      'score',old_score+add_score,
      'added',add_score,
      'finished',false,
      'waiting',true,
      'scores',new_scores
    );
  end if;
end;
$$;


create or replace function public.accept_friend_challenge(p_challenge_id uuid)
returns uuid
language plpgsql
security definer
set search_path=''
as $$
declare
  uid uuid := auth.uid();
  c public.challenges;
  mid uuid;
  qids uuid[];
  players uuid[];
begin
  if uid is null then raise exception 'Não autenticado'; end if;
  select * into c from public.challenges where id=p_challenge_id for update;
  if c.id is null then raise exception 'Desafio não encontrado'; end if;
  if c.challenged_id<>uid then raise exception 'Você não pode aceitar este desafio'; end if;
  if c.status<>'pending' then raise exception 'Este desafio não está mais disponível'; end if;

  select array_agg(x.id order by random()) into qids
  from (select id from public.questions where active=true and approval_status='approved' and category_name=c.category order by random() limit 7) x;
  if coalesce(array_length(qids,1),0)<7 then raise exception 'Esta categoria ainda não possui 7 perguntas ativas'; end if;

  players:=array[c.challenger_id,c.challenged_id];
  insert into public.matches(mode,category,player_ids,team_a,team_b,question_ids,scores,answers,state,status,started_at)
  values('1v1',c.category,players,array[c.challenger_id],array[c.challenged_id],qids,
    (select jsonb_object_agg(x::text,0) from unnest(players) x),
    '{}'::jsonb,
    jsonb_build_object('question_started_at',null,'answered',jsonb_build_object()),
    'playing',now()) returning id into mid;

  update public.challenges set status='accepted',match_id=mid,responded_at=now() where id=c.id;
  return mid;
end;
$$;

grant execute on function public.start_match_round(uuid) to authenticated;
grant execute on function public.submit_match_answer(uuid,int,int,int) to authenticated;
grant execute on function public.find_or_create_match(text,text) to authenticated;
grant execute on function public.accept_friend_challenge(uuid) to authenticated;

notify pgrst, 'reload schema';
