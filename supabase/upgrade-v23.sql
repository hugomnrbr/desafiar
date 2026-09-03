-- QuizUp v23 - desafios de amigos assíncronos
-- Execute DEPOIS do upgrade-v22.sql.
-- Não recrie o schema inteiro em um banco já existente.

-- Uma partida assíncrona usa as mesmas 7 perguntas para os dois jogadores,
-- mas cada jogador responde no seu próprio horário.
alter table public.matches add column if not exists match_kind text not null default 'live';
alter table public.matches add column if not exists async_challenge_id uuid references public.challenges(id) on delete set null;
alter table public.matches add column if not exists player_progress jsonb not null default '{}'::jsonb;
alter table public.matches add column if not exists player_started_at jsonb not null default '{}'::jsonb;
alter table public.matches add column if not exists player_finished jsonb not null default '{}'::jsonb;

create index if not exists matches_async_challenge_idx on public.matches(async_challenge_id);

-- Cria o desafio E a partida no mesmo momento.
-- O desafio continua pendente para o amigo, mas o criador já pode jogar.
create or replace function public.create_friend_challenge(p_friend_id uuid,p_category text)
returns uuid
language plpgsql
security definer
set search_path=''
as $$
declare
  uid uuid:=auth.uid();
  cid uuid;
  fid uuid;
  mid uuid;
  qids uuid[];
  players uuid[];
  scores jsonb;
  progress jsonb;
  started jsonb;
  finished jsonb;
begin
  if uid is null then raise exception 'Não autenticado'; end if;
  if p_friend_id is null or p_friend_id=uid then raise exception 'Amigo inválido'; end if;
  if p_category is null or length(trim(p_category))=0 then raise exception 'Categoria inválida'; end if;

  select c.id into cid
  from public.categories c
  where c.approved=true and lower(c.name)=lower(trim(p_category))
  limit 1;
  if cid is null then raise exception 'Categoria não encontrada ou não aprovada'; end if;

  if not exists(
    select 1 from public.friendships f
    where f.status='accepted'
      and ((f.requester_id=uid and f.addressee_id=p_friend_id)
        or (f.requester_id=p_friend_id and f.addressee_id=uid))
  ) then raise exception 'Vocês precisam ser amigos para desafiar'; end if;

  select c.id into fid
  from public.challenges c
  where c.challenger_id=uid
    and c.challenged_id=p_friend_id
    and c.status='pending'
  order by c.created_at desc
  limit 1;
  if fid is not null then return fid; end if;

  select array_agg(x.id order by x.ord) into qids
  from (
    select id,row_number() over(order by random()) as ord
    from public.questions
    where active=true and approval_status='approved' and category_name=trim(p_category)
  ) x
  where x.ord<=7;
  if coalesce(array_length(qids,1),0)<7 then raise exception 'Esta categoria ainda não possui 7 perguntas ativas'; end if;

  players:=array[uid,p_friend_id];
  scores:=jsonb_build_object(uid::text,0,p_friend_id::text,0);
  progress:=jsonb_build_object(uid::text,0,p_friend_id::text,0);
  started:='{}'::jsonb;
  finished:=jsonb_build_object(uid::text,false,p_friend_id::text,false);

  insert into public.matches(
    mode,category,player_ids,team_a,team_b,question_ids,scores,answers,state,status,started_at,
    match_kind,player_progress,player_started_at,player_finished
  ) values(
    '1v1',trim(p_category),players,array[uid],array[p_friend_id],qids,scores,'{}'::jsonb,
    jsonb_build_object('async',true), 'playing',now(),
    'async_friend',progress,started,finished
  ) returning id into mid;

  insert into public.challenges(challenger_id,challenged_id,category,status,match_id)
  values(uid,p_friend_id,trim(p_category),'pending',mid)
  returning id into fid;

  update public.matches set async_challenge_id=fid where id=mid;
  return fid;
end;
$$;

revoke all on function public.create_friend_challenge(uuid,text) from public;
grant execute on function public.create_friend_challenge(uuid,text) to authenticated;

-- Inicia a pergunta atual somente para o jogador que está entrando.
-- O outro jogador não é afetado.
create or replace function public.start_async_challenge(p_match_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  uid uuid:=auth.uid();
  m public.matches;
  c public.challenges;
  progress int;
  started numeric;
  pp jsonb;
  ps jsonb;
  pf jsonb;
begin
  if uid is null then raise exception 'Não autenticado'; end if;
  select * into m from public.matches where id=p_match_id for update;
  if m.id is null or not(uid=any(m.player_ids)) then raise exception 'Desafio não encontrado'; end if;
  if coalesce(m.match_kind,'live')<>'async_friend' then raise exception 'Esta não é uma partida assíncrona'; end if;

  if m.async_challenge_id is not null then
    select * into c from public.challenges where id=m.async_challenge_id;
    if c.id is null then raise exception 'Desafio não encontrado'; end if;
    if uid=c.challenged_id and c.status='pending' then
      update public.challenges set status='accepted',responded_at=now() where id=c.id;
    end if;
  end if;

  progress:=coalesce((m.player_progress->>uid::text)::int,0);
  pp:=coalesce(m.player_progress,'{}'::jsonb);
  ps:=coalesce(m.player_started_at,'{}'::jsonb);
  pf:=coalesce(m.player_finished,'{}'::jsonb);

  if progress>=7 then
    update public.matches set player_progress=pp,player_started_at=ps,player_finished=pf where id=m.id;
  elsif not (ps ? uid::text) then
    ps:=jsonb_set(ps,array[uid::text],to_jsonb(extract(epoch from clock_timestamp())),true);
    update public.matches set player_started_at=ps where id=m.id returning * into m;
  end if;

  return jsonb_build_object(
    'id',m.id,'status',m.status,'category',m.category,'match_kind',m.match_kind,
    'player_ids',to_jsonb(m.player_ids),'question_ids',to_jsonb(m.question_ids),
    'scores',m.scores,'answers',m.answers,'state',m.state,
    'player_progress',coalesce(m.player_progress,'{}'::jsonb),
    'player_started_at',coalesce(m.player_started_at,'{}'::jsonb),
    'player_finished',coalesce(m.player_finished,'{}'::jsonb)
  );
end;
$$;

grant execute on function public.start_async_challenge(uuid) to authenticated;

-- Registra a resposta de UM jogador sem alterar a pergunta/progresso do outro.
-- Cada pergunta tem 10 segundos contados a partir do momento em que aquele
-- jogador iniciou aquela pergunta.
create or replace function public.submit_async_challenge_answer(
  p_match_id uuid,p_question_index int,p_answer_index int
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
  progress int;
  started numeric;
  elapsed numeric;
  remaining int;
  add_score int:=0;
  correct_answer boolean:=false;
  timed_out boolean:=false;
  key text;
  new_scores jsonb;
  new_answers jsonb;
  new_progress jsonb;
  new_started jsonb;
  new_finished jsonb;
  other_id uuid;
  other_progress int;
  both_finished boolean:=false;
  old_score int;
begin
  if uid is null then raise exception 'Não autenticado'; end if;
  if p_answer_index < -1 or p_answer_index > 3 then raise exception 'Resposta inválida'; end if;

  select * into m from public.matches where id=p_match_id for update;
  if m.id is null or not(uid=any(m.player_ids)) then raise exception 'Desafio não encontrado'; end if;
  if coalesce(m.match_kind,'live')<>'async_friend' then raise exception 'Partida não é assíncrona'; end if;
  if m.status='finished' then
    return jsonb_build_object('ok',false,'finished',true,'scores',m.scores,'player_progress',m.player_progress,'answers',m.answers);
  end if;

  progress:=coalesce((m.player_progress->>uid::text)::int,0);
  if p_question_index<>progress then
    return jsonb_build_object('ok',false,'resync',true,'finished',false,'progress',progress,
      'scores',m.scores,'answers',m.answers,'player_progress',m.player_progress,
      'player_started_at',m.player_started_at,'player_finished',m.player_finished);
  end if;
  if progress>=7 then
    return jsonb_build_object('ok',true,'finished',false,'progress',progress,'scores',m.scores);
  end if;

  key:=uid::text||':'||p_question_index::text;
  if m.answers ? key then
    return jsonb_build_object('ok',true,'already_answered',true,'progress',progress,'scores',m.scores);
  end if;

  select * into q from public.questions where id=m.question_ids[p_question_index+1];
  if q.id is null then raise exception 'Pergunta não encontrada'; end if;

  started:=nullif(m.player_started_at->>uid::text,'')::numeric;
  if started is null then
    started:=extract(epoch from clock_timestamp());
  end if;
  elapsed:=extract(epoch from clock_timestamp())-started;
  remaining:=greatest(0,10-floor(greatest(elapsed,0))::int);
  timed_out:=elapsed>=10;
  correct_answer:=p_answer_index>=0 and p_answer_index=q.correct_index;

  if p_answer_index=-1 or timed_out then
    add_score:=0;
  elsif correct_answer then
    if p_question_index=6 then add_score:=20+least(remaining,10)*2;
    else add_score:=10+least(remaining,10);
    end if;
  end if;

  old_score:=coalesce((m.scores->>uid::text)::int,0);
  new_scores:=jsonb_set(coalesce(m.scores,'{}'::jsonb),array[uid::text],to_jsonb(old_score+add_score),true);
  new_answers:=jsonb_set(coalesce(m.answers,'{}'::jsonb),array[key],jsonb_build_object(
    'answer',p_answer_index,
    'correct',case when p_answer_index=-1 then false else correct_answer end,
    'score',add_score,
    'remaining',remaining,
    'timeout',p_answer_index=-1 or timed_out
  ),true);
  new_progress:=jsonb_set(coalesce(m.player_progress,'{}'::jsonb),array[uid::text],to_jsonb(progress+1),true);
  new_started:=coalesce(m.player_started_at,'{}'::jsonb) - uid::text;
  new_finished:=jsonb_set(coalesce(m.player_finished,'{}'::jsonb),array[uid::text],to_jsonb(progress+1>=7),true);

  other_id:=(select x from unnest(m.player_ids) x where x<>uid limit 1);
  other_progress:=coalesce((m.player_progress->>other_id::text)::int,0);
  both_finished:=(progress+1>=7 and other_progress>=7);

  if both_finished then
    update public.matches
    set scores=new_scores,answers=new_answers,player_progress=new_progress,
        player_started_at=new_started,player_finished=new_finished,
        status='finished',finished_at=now()
    where id=m.id;
  else
    update public.matches
    set scores=new_scores,answers=new_answers,player_progress=new_progress,
        player_started_at=new_started,player_finished=new_finished
    where id=m.id;
  end if;

  return jsonb_build_object(
    'ok',true,'added',add_score,'score',old_score+add_score,
    'progress',progress+1,'finished',both_finished,'scores',new_scores,
    'answers',new_answers,'player_progress',new_progress,
    'player_started_at',new_started,'player_finished',new_finished
  );
end;
$$;

grant execute on function public.submit_async_challenge_answer(uuid,int,int) to authenticated;

-- Permite ao jogador consultar o relógio oficial do servidor da partida assíncrona.
-- get_match_clock já verifica que ele participa da partida.

notify pgrst,'reload schema';

-- Aviso aos dois jogadores quando o desafio assíncrono termina.
create or replace function public.notify_async_challenge_finished()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
declare
  c public.challenges;
  a uuid;
  b uuid;
begin
  if new.match_kind<>'async_friend' or new.status<>'finished' or old.status='finished' then
    return new;
  end if;
  if new.async_challenge_id is null then return new; end if;
  select * into c from public.challenges where id=new.async_challenge_id;
  if c.id is null then return new; end if;
  a:=c.challenger_id;b:=c.challenged_id;
  insert into public.notifications(recipient_id,actor_id,type,title,body,data)
  select a,b,'system','⚔️ Desafio finalizado',
    'Seu desafio de '||c.category||' terminou. Veja o resultado.',jsonb_build_object('match_id',new.id,'challenge_id',c.id)
  where not exists(select 1 from public.notifications n where n.recipient_id=a and n.type='system' and n.data->>'match_id'=new.id::text);
  insert into public.notifications(recipient_id,actor_id,type,title,body,data)
  select b,a,'system','⚔️ Desafio finalizado',
    'Seu desafio de '||c.category||' terminou. Veja o resultado.',jsonb_build_object('match_id',new.id,'challenge_id',c.id)
  where not exists(select 1 from public.notifications n where n.recipient_id=b and n.type='system' and n.data->>'match_id'=new.id::text);
  return new;
end;
$$;

drop trigger if exists trg_notify_async_challenge_finished on public.matches;
create trigger trg_notify_async_challenge_finished
after update of status on public.matches
for each row execute function public.notify_async_challenge_finished();

notify pgrst,'reload schema';
