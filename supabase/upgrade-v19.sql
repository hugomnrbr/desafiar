-- QuizUp v19 - notificações em tempo real
create table if not exists public.notifications(
  id uuid primary key default gen_random_uuid(),
  recipient_id uuid not null references public.profiles(id) on delete cascade,
  actor_id uuid references public.profiles(id) on delete set null,
  type text not null check(type in ('friend_request','challenge','message','system')),
  title text not null,
  body text not null,
  data jsonb not null default '{}'::jsonb,
  read_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists notifications_recipient_created_idx on public.notifications(recipient_id,created_at desc);
create index if not exists notifications_unread_idx on public.notifications(recipient_id,read_at) where read_at is null;

alter table public.notifications enable row level security;
drop policy if exists notifications_select on public.notifications;
drop policy if exists notifications_update on public.notifications;
create policy notifications_select on public.notifications
for select to authenticated
using(recipient_id=(select auth.uid()));
create policy notifications_update on public.notifications
for update to authenticated
using(recipient_id=(select auth.uid()))
with check(recipient_id=(select auth.uid()));

-- Cria uma notificação quando alguém envia pedido de amizade.
create or replace function public.notify_friend_request()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
declare uname text;
begin
  if new.status='pending' then
    select username into uname from public.profiles where id=new.requester_id;
    insert into public.notifications(recipient_id,actor_id,type,title,body,data)
    values(new.addressee_id,new.requester_id,'friend_request','Novo pedido de amizade',coalesce(uname,'Alguém')||' quer adicionar você como amigo',jsonb_build_object('friendship_id',new.id));
  end if;
  return new;
end;
$$;

drop trigger if exists trg_notify_friend_request on public.friendships;
create trigger trg_notify_friend_request
after insert on public.friendships
for each row execute function public.notify_friend_request();

-- Cria uma notificação quando alguém desafia um amigo.
create or replace function public.notify_challenge()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
declare uname text;
begin
  if new.status='pending' then
    select username into uname from public.profiles where id=new.challenger_id;
    insert into public.notifications(recipient_id,actor_id,type,title,body,data)
    values(new.challenged_id,new.challenger_id,'challenge','Novo desafio',coalesce(uname,'Alguém')||' desafiou você em '||new.category,jsonb_build_object('challenge_id',new.id,'category',new.category));
  end if;
  return new;
end;
$$;

drop trigger if exists trg_notify_challenge on public.challenges;
create trigger trg_notify_challenge
after insert on public.challenges
for each row execute function public.notify_challenge();

-- Cria uma notificação quando chega uma mensagem direta.
create or replace function public.notify_direct_message()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
declare uname text; preview text;
begin
  select username into uname from public.profiles where id=new.sender_id;
  preview:=case when coalesce(new.message_type,'text')='photo' then '📷 Enviou uma foto' else left(coalesce(new.message,''),80) end;
  insert into public.notifications(recipient_id,actor_id,type,title,body,data)
  values(new.receiver_id,new.sender_id,'message','Nova mensagem',coalesce(uname,'Alguém')||': '||preview,jsonb_build_object('message_id',new.id));
  return new;
end;
$$;

drop trigger if exists trg_notify_direct_message on public.direct_messages;
create trigger trg_notify_direct_message
after insert on public.direct_messages
for each row execute function public.notify_direct_message();

-- Realtime para o sino atualizar sem recarregar a página.
do $$
begin
  begin alter publication supabase_realtime add table public.notifications; exception when duplicate_object then null; end;
end $$;

notify pgrst,'reload schema';
