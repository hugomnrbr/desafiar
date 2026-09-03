-- QuizUp v8 - chat entre amigos + desafios 1x1 por categoria
-- Execute DEPOIS do upgrade-v7.sql / schema-v6.sql.

create table if not exists public.direct_messages(
  id uuid primary key default gen_random_uuid(),
  sender_id uuid not null references public.profiles(id) on delete cascade,
  receiver_id uuid not null references public.profiles(id) on delete cascade,
  message text not null check(length(trim(message)) between 1 and 500),
  created_at timestamptz not null default now(),
  check(sender_id<>receiver_id)
);
create index if not exists direct_messages_pair_idx on public.direct_messages(sender_id,receiver_id,created_at);
create index if not exists direct_messages_receiver_idx on public.direct_messages(receiver_id,created_at);

create table if not exists public.challenges(
  id uuid primary key default gen_random_uuid(),
  challenger_id uuid not null references public.profiles(id) on delete cascade,
  challenged_id uuid not null references public.profiles(id) on delete cascade,
  category text not null,
  mode text not null default '1v1' check(mode='1v1'),
  status text not null default 'pending' check(status in ('pending','accepted','rejected','expired','cancelled')),
  match_id uuid references public.matches(id) on delete set null,
  created_at timestamptz not null default now(),
  responded_at timestamptz,
  check(challenger_id<>challenged_id)
);
create index if not exists challenges_receiver_idx on public.challenges(challenged_id,status,created_at desc);
create index if not exists challenges_sender_idx on public.challenges(challenger_id,status,created_at desc);

alter table public.direct_messages enable row level security;
alter table public.challenges enable row level security;

-- Mensagens: somente os dois participantes da conversa podem ler/enviar.
drop policy if exists direct_messages_select on public.direct_messages;
drop policy if exists direct_messages_insert on public.direct_messages;
create policy direct_messages_select on public.direct_messages
for select to authenticated
using(sender_id=(select auth.uid()) or receiver_id=(select auth.uid()));
create policy direct_messages_insert on public.direct_messages
for insert to authenticated
with check(sender_id=(select auth.uid()) and exists(
  select 1 from public.friendships f
  where f.status='accepted'
    and ((f.requester_id=(select auth.uid()) and f.addressee_id=receiver_id)
      or (f.requester_id=receiver_id and f.addressee_id=(select auth.uid())))
));

-- Desafios: jogador cria apenas para amigo aceito; cada participante lê seus próprios desafios.
drop policy if exists challenges_select on public.challenges;
drop policy if exists challenges_insert on public.challenges;
drop policy if exists challenges_update on public.challenges;
create policy challenges_select on public.challenges
for select to authenticated
using(challenger_id=(select auth.uid()) or challenged_id=(select auth.uid()));
create policy challenges_insert on public.challenges
for insert to authenticated
with check(challenger_id=(select auth.uid()) and exists(
  select 1 from public.friendships f
  where f.status='accepted'
    and ((f.requester_id=(select auth.uid()) and f.addressee_id=challenged_id)
      or (f.requester_id=challenged_id and f.addressee_id=(select auth.uid())))
));
create policy challenges_update on public.challenges
for update to authenticated
using(challenged_id=(select auth.uid()) or challenger_id=(select auth.uid()))
with check(challenged_id=(select auth.uid()) or challenger_id=(select auth.uid()));

grant select,insert on public.direct_messages to authenticated;
grant select,insert,update on public.challenges to authenticated;

-- Envia um desafio para um amigo em uma categoria aprovada.
create or replace function public.create_friend_challenge(p_friend_id uuid,p_category text)
returns uuid
language plpgsql
security definer
set search_path=''
as $$
declare
  uid uuid := auth.uid();
  cid uuid;
  fid uuid;
  existing uuid;
begin
  if uid is null then raise exception 'Não autenticado'; end if;
  if p_friend_id is null or p_friend_id=uid then raise exception 'Amigo inválido'; end if;
  if p_category is null or length(trim(p_category))=0 then raise exception 'Categoria inválida'; end if;
  select c.id into cid from public.categories c where c.approved=true and lower(c.name)=lower(trim(p_category)) limit 1;
  if cid is null then raise exception 'Categoria não encontrada ou não aprovada'; end if;
  if not exists(
    select 1 from public.friendships f
    where f.status='accepted'
      and ((f.requester_id=uid and f.addressee_id=p_friend_id) or (f.requester_id=p_friend_id and f.addressee_id=uid))
  ) then raise exception 'Vocês precisam ser amigos para desafiar'; end if;
  select id into existing from public.challenges
  where challenger_id=uid and challenged_id=p_friend_id and status='pending'
  order by created_at desc limit 1;
  if existing is not null then return existing; end if;
  insert into public.challenges(challenger_id,challenged_id,category,status)
  values(uid,p_friend_id,trim(p_category),'pending') returning id into fid;
  return fid;
end;
$$;
revoke all on function public.create_friend_challenge(uuid,text) from public;
grant execute on function public.create_friend_challenge(uuid,text) to authenticated;

-- Aceita um desafio e cria imediatamente uma partida 1x1 com 10 perguntas da categoria.
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
  from (select id from public.questions where active=true and approval_status='approved' and category_name=c.category order by random() limit 10) x;
  if coalesce(array_length(qids,1),0)<10 then raise exception 'Esta categoria ainda não possui 10 perguntas ativas'; end if;

  players:=array[c.challenger_id,c.challenged_id];
  insert into public.matches(mode,category,player_ids,team_a,team_b,question_ids,scores,answers,state,status,started_at)
  values('1v1',c.category,players,array[c.challenger_id],array[c.challenged_id],qids,
    (select jsonb_object_agg(x::text,0) from unnest(players) x),
    '{}'::jsonb,
    jsonb_build_object('question_started_at',extract(epoch from clock_timestamp()),'answered',jsonb_build_object()),
    'playing',now()) returning id into mid;

  update public.challenges set status='accepted',match_id=mid,responded_at=now() where id=c.id;
  return mid;
end;
$$;
revoke all on function public.accept_friend_challenge(uuid) from public;
grant execute on function public.accept_friend_challenge(uuid) to authenticated;

-- Realtime para chat, desafios e partidas.
do $$
begin
  begin alter publication supabase_realtime add table public.direct_messages; exception when duplicate_object then null; end;
  begin alter publication supabase_realtime add table public.challenges; exception when duplicate_object then null; end;
end $$;

notify pgrst, 'reload schema';
