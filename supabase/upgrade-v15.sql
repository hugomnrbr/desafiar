-- QuizUp v15 - matchmaking somente com jogadores realmente presentes.
-- Corrige matches criados a partir de entradas antigas da fila quando o outro
-- jogador já fechou o navegador.
-- Execute depois do upgrade-v13.sql (e do upgrade-v14, se estiver usando a v14).

alter table public.match_queue
  add column if not exists last_seen_at timestamptz not null default now();

create index if not exists queue_presence_idx
  on public.match_queue(mode, category, status, last_seen_at);

-- Limpa entradas antigas que ficaram presas quando o navegador foi fechado.
update public.match_queue
set status='cancelled'
where status='waiting'
  and last_seen_at < now() - interval '8 seconds';

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
  first_id uuid;
  second_id uuid;
  seed int;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  if p_mode not in ('1v1','2v2') then raise exception 'invalid mode'; end if;
  if p_category is null or length(trim(p_category))=0 then raise exception 'invalid category'; end if;

  -- Nunca reaproveita uma partida antiga abandonada. Uma partida normal dura
  -- menos de 90 segundos (7 rodadas x 10s + contagem). Isso evita que um
  -- jogador offline seja tratado como adversário disponível.
  select m.id into mid
  from public.matches m
  where uid = any(m.player_ids)
    and m.status in ('waiting','ready','playing')
    and m.created_at > now() - interval '90 seconds'
  order by m.created_at desc
  limit 1;
  if mid is not null then return mid; end if;

  -- Marca a presença do jogador a cada tentativa. Fechar a aba/navegador
  -- faz a presença expirar automaticamente em poucos segundos.
  update public.match_queue
  set status='waiting', last_seen_at=now()
  where user_id=uid and mode=p_mode and category=p_category and status='waiting';

  if not found then
    insert into public.match_queue(user_id,mode,category,status,last_seen_at)
    values(uid,p_mode,p_category,'waiting',now());
  end if;

  -- Só considera jogadores que fizeram heartbeat nos últimos 5 segundos.
  -- Portanto uma fila antiga nunca cria uma partida fantasma.
  ids := array[uid];
  for q in
    select mq.id,mq.user_id
    from public.match_queue mq
    where mq.mode=p_mode
      and mq.category=p_category
      and mq.status='waiting'
      and mq.user_id<>uid
      and mq.last_seen_at > now() - interval '5 seconds'
    order by mq.created_at
    for update skip locked
  loop
    if array_length(ids,1) >= needed then exit; end if;
    if not (q.user_id = any(ids)) then ids := array_append(ids,q.user_id); end if;
  end loop;

  if array_length(ids,1) < needed then return null; end if;

  select array_agg(x.id order by random()) into qids
  from (
    select id
    from public.questions
    where active=true and category_name=p_category
    order by random()
    limit 7
  ) x;
  if coalesce(array_length(qids,1),0) < 7 then return null; end if;

  shuffled := ids;
  first_id := shuffled[1]; second_id := shuffled[2];
  if p_mode='1v1' then
    team_a := array[first_id]; team_b := array[second_id];
  else
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

  update public.match_queue
  set status='matched', last_seen_at=now()
  where user_id = any(ids)
    and mode=p_mode
    and category=p_category
    and status='waiting';

  update public.matches set started_at=now() where id=mid;
  return mid;
end;
$$;

grant execute on function public.find_or_create_match(text,text) to authenticated;
notify pgrst, 'reload schema';
