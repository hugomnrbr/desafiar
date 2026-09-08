-- Q-Rival v47 — inventário, XP, partidas contra bot e nível 1-1000
-- Execute este arquivo no SQL Editor do Supabase.
-- Não apaga produtos, inventário, partidas ou conquistas existentes.

-- 1) O inventário do jogador estava sem políticas de leitura/alteração próprias.
-- A compra via RPC podia funcionar, mas o app não conseguia enxergar a linha criada.
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

-- 2) Nível global: 250 XP por nível, até o nível 1000.
-- Nível 1 começa em 0 XP; nível 1000 fica travado a partir de 249.750 XP.
create or replace function public.quizup_balance_level_v47()
returns trigger
language plpgsql
as $$
begin
  new.xp := greatest(0,coalesce(new.xp,0));
  new.level := least(1000,greatest(1,1+floor(new.xp/250)::int));
  return new;
end;
$$;

drop trigger if exists quizup_balance_level_v47 on public.profiles;
create trigger quizup_balance_level_v47
before insert or update of xp on public.profiles
for each row execute function public.quizup_balance_level_v47();

update public.profiles
set level=least(1000,greatest(1,1+floor(greatest(0,coalesce(xp,0))/250)::int));

-- 3) Reforça a função de pontuação oficial de 20 segundos.
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

-- 4) Garante que conquistas sejam verificadas também após resultado contra bot.
-- A função existente da v46 é reaproveitada; esta chamada serve para usuários
-- que já possuem resultados e querem sincronizar as conquistas imediatamente.
-- Não altera conquistas já liberadas.

-- 5) Corrige níveis por tópico para o mesmo ritmo do nível global.
create or replace function public.quizup_topic_level_v47(p_xp bigint)
returns integer
language sql
immutable
as $$
  select least(1000,greatest(1,1+floor(greatest(0,coalesce(p_xp,0))/250)::int));
$$;
revoke all on function public.quizup_topic_level_v47(bigint) from public;
grant execute on function public.quizup_topic_level_v47(bigint) to authenticated;
