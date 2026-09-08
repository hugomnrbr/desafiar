-- Q-Rival v48 — correções de inventário, emojis e acesso administrativo
-- Execute no SQL Editor do Supabase.

-- 1) Função oficial de verificação administrativa.
create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path=public
as $$
  select exists(
    select 1 from public.profiles
    where id=auth.uid() and role='admin'
  );
$$;
revoke all on function public.is_admin() from public;
grant execute on function public.is_admin() to authenticated;

-- 2) Inventário: o próprio jogador pode ler/ativar seus itens.
alter table public.user_premium_items enable row level security;
drop policy if exists "user premium items own read" on public.user_premium_items;
create policy "user premium items own read"
on public.user_premium_items for select to authenticated
using (user_id=auth.uid() or public.is_admin());
drop policy if exists "user premium items own update" on public.user_premium_items;
create policy "user premium items own update"
on public.user_premium_items for update to authenticated
using (user_id=auth.uid() or public.is_admin())
with check (user_id=auth.uid() or public.is_admin());

-- 3) Reações da partida: garante tabela, RLS, Realtime e RPC.
create table if not exists public.match_reactions(
  id uuid primary key default gen_random_uuid(),
  match_id uuid not null references public.matches(id) on delete cascade,
  sender_id uuid not null references public.profiles(id) on delete cascade,
  emoji text not null check(char_length(emoji) between 1 and 120),
  created_at timestamptz not null default now()
);
create index if not exists match_reactions_match_created_idx
  on public.match_reactions(match_id,created_at desc);
create index if not exists match_reactions_sender_created_idx
  on public.match_reactions(sender_id,created_at desc);

alter table public.match_reactions enable row level security;
drop policy if exists "match reactions read authenticated" on public.match_reactions;
create policy "match reactions read authenticated"
on public.match_reactions for select to authenticated using (true);
drop policy if exists "match reactions insert own" on public.match_reactions;
create policy "match reactions insert own"
on public.match_reactions for insert to authenticated
with check (sender_id=auth.uid());
drop policy if exists "match reactions delete own" on public.match_reactions;
create policy "match reactions delete own"
on public.match_reactions for delete to authenticated
using (sender_id=auth.uid());

do $$
begin
  if exists(select 1 from pg_publication where pubname='supabase_realtime')
     and not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='match_reactions') then
    execute 'alter publication supabase_realtime add table public.match_reactions';
  end if;
exception when others then null;
end $$;

drop function if exists public.send_match_reaction(uuid,text);
create function public.send_match_reaction(p_match_id uuid,p_emoji text)
returns public.match_reactions
language plpgsql
security definer
set search_path=public
as $$
declare
  r public.match_reactions;
  participant boolean;
begin
  if auth.uid() is null then raise exception 'Não autenticado'; end if;
  if coalesce(trim(p_emoji),'')='' then raise exception 'Emoji inválido'; end if;
  select exists(
    select 1 from public.matches m
    where m.id=p_match_id
      and auth.uid()=any(m.player_ids)
      and m.status<>'finished'
  ) into participant;
  if not participant then raise exception 'Você não participa desta partida'; end if;
  if exists(
    select 1 from public.match_reactions
    where match_id=p_match_id and sender_id=auth.uid()
      and created_at>now()-interval '3 seconds'
  ) then raise exception 'Aguarde 3 segundos para enviar outro emoji.'; end if;
  insert into public.match_reactions(match_id,sender_id,emoji)
  values(p_match_id,auth.uid(),trim(p_emoji)) returning * into r;
  return r;
end;
$$;
revoke all on function public.send_match_reaction(uuid,text) from public;
grant execute on function public.send_match_reaction(uuid,text) to authenticated;
