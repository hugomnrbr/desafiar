-- QuizUp v36.2.5 - sessão persistente, amigos, desafios, contas admin e pacotes de Coins
-- Execute este arquivo depois da migration v36.2.4.

-- 1) Desafios recusados: o desafiante vê a recusa uma vez.
alter table public.challenges add column if not exists decline_seen_by_challenger boolean not null default false;

create or replace function public.decline_friend_challenge(p_challenge_id uuid)
returns public.challenges
language plpgsql security definer set search_path=public
as $$
declare c public.challenges;
begin
  select * into c from public.challenges where id=p_challenge_id and challenged_id=auth.uid() for update;
  if c.id is null then raise exception 'Desafio não encontrado'; end if;
  if c.status not in ('pending','accepted') then return c; end if;
  update public.challenges set status='declined', decline_seen_by_challenger=false where id=p_challenge_id returning * into c;
  return c;
end $$;

create or replace function public.mark_declined_challenge_seen(p_challenge_id uuid)
returns public.challenges
language plpgsql security definer set search_path=public
as $$
declare c public.challenges;
begin
  update public.challenges set decline_seen_by_challenger=true where id=p_challenge_id and challenger_id=auth.uid() and status='declined' returning * into c;
  if c.id is null then raise exception 'Recusa não encontrada'; end if;
  return c;
end $$;

grant execute on function public.decline_friend_challenge(uuid) to authenticated;
grant execute on function public.mark_declined_challenge_seen(uuid) to authenticated;

-- 2) Pacotes de QuizCoins. O preço é em centavos; a loja mostra em reais.
create table if not exists public.coin_packages (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  coins bigint not null check(coins>0),
  price_cents integer not null check(price_cents>=0),
  active boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete set null
);
alter table public.coin_packages enable row level security;
drop policy if exists "coin packages read active" on public.coin_packages;
create policy "coin packages read active" on public.coin_packages for select to authenticated using(active=true or exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin'));
drop policy if exists "coin packages admin insert" on public.coin_packages;
create policy "coin packages admin insert" on public.coin_packages for insert to authenticated with check(exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin'));
drop policy if exists "coin packages admin update" on public.coin_packages;
create policy "coin packages admin update" on public.coin_packages for update to authenticated using(exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin')) with check(exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin'));
drop policy if exists "coin packages admin delete" on public.coin_packages;
create policy "coin packages admin delete" on public.coin_packages for delete to authenticated using(exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin'));

insert into public.coin_packages(name,coins,price_cents,sort_order,active)
select v.name,v.coins,v.price_cents,v.sort_order,true from (values
('Pacote 1.000 Coins',1000,1000,1),
('Pacote 2.500 Coins',2500,2000,2),
('Pacote 6.000 Coins',6000,4500,3)
) as v(name,coins,price_cents,sort_order)
where not exists(select 1 from public.coin_packages cp where cp.coins=v.coins and cp.price_cents=v.price_cents);

-- 3) Contas para o painel administrativo. O e-mail vem de auth.users e não fica exposto ao usuário comum.
create or replace function public.admin_list_accounts()
returns table(id uuid, username text, display_name text, email text, role text, created_at timestamptz)
language plpgsql security definer set search_path=public,auth
as $$
begin
  if not exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin') then raise exception 'Acesso negado'; end if;
  return query
  select p.id,p.username,p.display_name,u.email,p.role,u.created_at
  from public.profiles p join auth.users u on u.id=p.id
  order by u.created_at desc;
end $$;
grant execute on function public.admin_list_accounts() to authenticated;

-- 4) Dar/remover título pelo painel sem depender das policies normais de profiles.
create or replace function public.admin_set_player_title(p_user_id uuid,p_title text)
returns public.profiles
language plpgsql security definer set search_path=public
as $$
declare p public.profiles;
begin
  if not exists(select 1 from public.profiles a where a.id=auth.uid() and a.role='admin') then raise exception 'Acesso negado'; end if;
  update public.profiles set premium_title=nullif(trim(p_title),'') where id=p_user_id returning * into p;
  if p.id is null then raise exception 'Jogador não encontrado'; end if;
  return p;
end $$;
grant execute on function public.admin_set_player_title(uuid,text) to authenticated;

-- 5) Segurança: ativação de cosméticos só para itens que o usuário possui.
-- A função existente v36.2.4 já faz esta validação; mantemos a migration idempotente.

-- 6) Índices úteis para histórico entre amigos.
create index if not exists matches_finished_players_idx on public.matches(status,created_at desc);
create index if not exists challenges_user_status_idx on public.challenges(challenger_id,status,created_at desc);
create index if not exists challenges_target_status_idx on public.challenges(challenged_id,status,created_at desc);
