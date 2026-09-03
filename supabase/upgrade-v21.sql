-- QuizUp v21 - cronômetro sincronizado e timeout por rodada
-- Execute DEPOIS do upgrade-v20.sql.
-- Não recrie o schema em um banco já existente.

-- Retorna o relógio oficial do banco para que os dois celulares/abas
-- calculem o mesmo tempo restante, independentemente do relógio local.
create or replace function public.get_match_clock(p_match_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  uid uuid := auth.uid();
  m public.matches;
  started numeric;
  now_epoch numeric;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  select * into m from public.matches where id=p_match_id;
  if m.id is null or not (uid=any(m.player_ids)) then raise exception 'match not found'; end if;
  started := nullif(m.state->>'question_started_at','')::numeric;
  now_epoch := extract(epoch from clock_timestamp());
  return jsonb_build_object(
    'server_now',now_epoch,
    'question_started_at',started,
    'current_question',m.current_question,
    'status',m.status
  );
end;
$$;

grant execute on function public.get_match_clock(uuid) to authenticated;

-- Versão autoritativa do envio de resposta.
-- Regras:
--   * 7 perguntas, 10 segundos.
--   * Resposta correta antes do timeout recebe a pontuação pela velocidade.
--   * Depois de 10s qualquer resposta vale 0.
--   * -1 representa timeout e sempre vale 0.
--   * A próxima pergunta só começa quando TODOS os jogadores tiverem
--     registrado resposta ou timeout.
create or replace function public.submit_match_answer(
  p_match_id uuid,p_question_index int,p_answer_index int,p_seconds int
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  uid uuid:=auth.uid();
  m public.matches;
  q public.questions;
  old_score int;
  add_score int:=0;
  key text;
  new_scores jsonb;
  new_answers jsonb;
  done_count int;
  elapsed numeric;
  remaining int;
  timed_out boolean:=false;
  correct_answer boolean:=false;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  if p_answer_index < -1 or p_answer_index > 3 then raise exception 'invalid answer'; end if;

  select * into m from public.matches where id=p_match_id for update;
  if m.id is null or not(uid=any(m.player_ids)) then raise exception 'match not found'; end if;

  if m.status<>'playing' then
    return jsonb_build_object('ok',false,'resync',true,'finished',m.status='finished',
      'status',m.status,'current_question',m.current_question,'scores',m.scores,
      'answers',m.answers,'state',m.state);
  end if;

  if p_question_index<>m.current_question then
    return jsonb_build_object('ok',false,'resync',true,'finished',false,
      'status',m.status,'current_question',m.current_question,'scores',m.scores,
      'answers',m.answers,'state',m.state);
  end if;

  key:=uid::text||':'||p_question_index::text;
  if m.answers ? key then
    return jsonb_build_object('ok',true,'already_answered',true,
      'score',coalesce((m.scores->>uid::text)::int,0),'finished',m.status='finished');
  end if;

  if array_length(m.question_ids,1) is null or p_question_index+1>array_length(m.question_ids,1) then
    raise exception 'question missing';
  end if;

  select * into q from public.questions where id=m.question_ids[p_question_index+1];
  if q.id is null then raise exception 'question missing'; end if;

  elapsed:=extract(epoch from clock_timestamp())-
           coalesce((m.state->>'question_started_at')::numeric,extract(epoch from clock_timestamp()));
  remaining:=greatest(0,10-floor(greatest(elapsed,0))::int);
  timed_out := elapsed >= 10;
  correct_answer := p_answer_index >= 0 and p_answer_index=q.correct_index;

  -- Timeout (-1) nunca dá pontos. Também não permitimos que um cliente
  -- invente uma resposta rápida quando o servidor já marcou o fim do tempo.
  if p_answer_index=-1 then
    add_score:=0;
  elsif timed_out then
    add_score:=0;
  elsif correct_answer then
    if p_question_index=6 then
      add_score:=20+least(remaining,10)*2;
    else
      add_score:=10+least(remaining,10);
    end if;
  end if;

  old_score:=coalesce((m.scores->>uid::text)::int,0);
  new_scores:=jsonb_set(coalesce(m.scores,'{}'::jsonb),array[uid::text],
    to_jsonb(old_score+add_score),true);

  new_answers:=jsonb_set(coalesce(m.answers,'{}'::jsonb),array[key],
    jsonb_build_object(
      'answer',p_answer_index,
      'correct',case when p_answer_index=-1 then false else correct_answer end,
      'score',add_score,
      'remaining',remaining,
      'timeout',p_answer_index=-1 or timed_out
    ),true);

  select count(*) into done_count
  from jsonb_object_keys(new_answers) k
  where split_part(k,':',2)=p_question_index::text;

  -- Só uma resposta/timeout de CADA jogador libera a próxima pergunta.
  if done_count>=array_length(m.player_ids,1) then
    if p_question_index>=array_length(m.question_ids,1)-1 then
      update public.matches
      set scores=new_scores,answers=new_answers,status='finished',finished_at=now()
      where id=m.id;

      return jsonb_build_object('ok',true,'score',old_score+add_score,
        'added',add_score,'finished',true,'scores',new_scores,'answers',new_answers);
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

      return jsonb_build_object('ok',true,'score',old_score+add_score,
        'added',add_score,'finished',false,'next_question',p_question_index+1,
        'scores',new_scores,'answers',new_answers);
    end if;
  else
    update public.matches set scores=new_scores,answers=new_answers where id=m.id;
    return jsonb_build_object('ok',true,'score',old_score+add_score,
      'added',add_score,'finished',false,'waiting',true,
      'scores',new_scores,'answers',new_answers);
  end if;
end;
$$;

grant execute on function public.submit_match_answer(uuid,int,int,int) to authenticated;
notify pgrst,'reload schema';
