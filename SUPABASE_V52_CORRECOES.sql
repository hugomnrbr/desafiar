-- Q-Rival V52 — correções para o banco já instalado pela V51
-- Corrige:
-- 1) qr_daily_claims: recompensa diária + baú no mesmo dia geravam conflito de PK.
-- 2) Morte Súbita: não depende mais de gen_random_bytes().
-- 3) Reforça a função de criação de sala e a consulta de torneios.

begin;

-- ================================================================
-- 1. RECOMPENSA DIÁRIA / BAÚ
-- ================================================================
-- A PK antiga era (user_id, claim_date), mas o sistema possui duas
-- recompensas independentes no mesmo dia: diária e baú.
alter table if exists public.qr_daily_claims
  drop constraint if exists qr_daily_claims_pkey;

alter table if exists public.qr_daily_claims
  add primary key (user_id, claim_date, chest);

create or replace function public.qr_claim_daily_reward(p_chest boolean default false)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  today date := current_date;
  prev date;
  laststreak integer := 0;
  v_coins integer := 0;
  item text := null;
  nextstreak integer := 1;
  inserted_user uuid;
  min_coins integer := 0;
  max_coins integer := 0;
  item_chance numeric := 0;
begin
  if auth.uid() is null then
    raise exception 'Faça login.';
  end if;

  select max(claim_date), coalesce(max(streak),0)
    into prev,laststreak
  from public.qr_daily_claims
  where user_id=auth.uid() and chest=false;

  nextstreak := case
    when prev=today-1 then laststreak+1
    else 1
  end;

  select
    greatest(0,coalesce(chest_min_coins,50)),
    greatest(0,coalesce(chest_max_coins,150)),
    greatest(0,least(1,coalesce(chest_item_chance,0.08)))
  into min_coins,max_coins,item_chance
  from public.qr_mode_settings
  where id=1;

  if p_chest then
    if max_coins < min_coins then
      max_coins := min_coins;
    end if;

    v_coins := floor(random() * (max_coins-min_coins+1))::integer + min_coins;

    -- Itens raros são escolhidos somente entre produtos ativos.
    select id::text
      into item
    from public.premium_items
    where active=true
      and lower(coalesce(rarity,'')) in ('rare','epic','legendary','mythic','raro','épico','lendário','mítico')
      and random() < item_chance
    order by random()
    limit 1;
  else
    v_coins := greatest(0,coalesce((select daily_coin_base from public.qr_mode_settings where id=1),25))
               + least(nextstreak,25)*2;
  end if;

  -- Idempotência + proteção contra dois cliques simultâneos.
  insert into public.qr_daily_claims(
    user_id,claim_date,streak,reward_coins,reward_item_id,chest
  ) values(
    auth.uid(),today,nextstreak,v_coins,item,p_chest
  )
  on conflict (user_id,claim_date,chest) do nothing
  returning user_id into inserted_user;

  if inserted_user is null then
    raise exception 'Recompensa de hoje já foi resgatada.';
  end if;

  update public.profiles
     set coins=coalesce(coins,0)+v_coins
   where id=auth.uid();

  if item is not null then
    insert into public.user_premium_items(user_id,item_id,active,purchased_at)
    values(auth.uid(),item,false,now())
    on conflict do nothing;
  end if;

  return jsonb_build_object(
    'ok',true,
    'coins',v_coins,
    'item_id',item,
    'streak',nextstreak,
    'chest',p_chest
  );
end;
$$;

revoke all on function public.qr_claim_daily_reward(boolean) from public;
grant execute on function public.qr_claim_daily_reward(boolean) to authenticated;

-- ================================================================
-- 2. MORTE SÚBITA — criação de código sem pgcrypto
-- ================================================================
-- Usa MD5 + random/clock_timestamp, disponíveis no PostgreSQL padrão.
-- Assim a sala funciona mesmo quando a extensão pgcrypto não estiver ativa.
create or replace function public.qr_create_sudden_room(p_category text default 'Geral')
returns uuid
language plpgsql
security definer
set search_path=public
as $$
declare
  rid uuid;
  c text;
  maxp integer;
  tries integer := 0;
begin
  if auth.uid() is null then
    raise exception 'Faça login.';
  end if;

  if not exists(
    select 1 from public.qr_mode_settings
    where id=1 and enabled=true and sudden_death_enabled=true
  ) then
    raise exception 'Modo Morte Súbita está desativado.';
  end if;

  select least(8,greatest(2,coalesce(sudden_death_max_players,8)))
    into maxp
  from public.qr_mode_settings
  where id=1;

  if maxp is null then maxp := 8; end if;

  loop
    tries := tries + 1;
    c := upper(substr(md5(random()::text || clock_timestamp()::text || auth.uid()::text),1,6));
    exit when not exists(select 1 from public.qr_sudden_rooms where code=c);
    if tries > 20 then
      raise exception 'Não foi possível gerar o código da sala. Tente novamente.';
    end if;
  end loop;

  insert into public.qr_sudden_rooms(code,host_id,category,max_players)
  values(c,auth.uid(),coalesce(nullif(trim(p_category),''),'Geral'),maxp)
  returning id into rid;

  insert into public.qr_sudden_players(room_id,user_id)
  values(rid,auth.uid())
  on conflict do nothing;

  return rid;
end;
$$;

revoke all on function public.qr_create_sudden_room(text) from public;
grant execute on function public.qr_create_sudden_room(text) to authenticated;

-- ================================================================
-- 3. TORNEIOS — consulta segura e função de entrada
-- ================================================================
-- Garante os quatro valores permitidos e limite de 18 jogadores.
update public.qr_tournaments
set max_players=least(greatest(coalesce(max_players,18),2),18),
    entry_fee=case when entry_fee in (100,200,500,1000) then entry_fee else 100 end;

-- ================================================================
-- 4. PGCRYPTO: pode existir no Supabase, mas não é mais requisito
-- para criar salas. Se o projeto permitir a extensão, ela fica ativa
-- para as demais funções que usam gen_random_uuid().
-- ================================================================
create extension if not exists pgcrypto;

commit;
