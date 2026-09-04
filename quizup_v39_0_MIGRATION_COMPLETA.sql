-- ================================================================
-- CORREÇÃO v39.0.1.1: função de autorização base
-- ================================================================
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

-- QUIZUP v39.0.0 - MIGRATION COMPLETA LIMPA E IDEMPOTENTE
-- Pode ser executada mesmo que parte ou toda a estrutura já exista.
-- Policies e triggers são recriados com segurança; tabelas/índices usam IF NOT EXISTS.

-- QuizUp v39.0.0 - MIGRATION COMPLETA LIMPA
-- Esta migration foi preparada para ser executada SOZINHA em um banco novo.
-- Ela reúne a estrutura/migrations necessárias das versões anteriores até v39.0.
-- Execute APENAS este arquivo no Supabase.
-- É idempotente nas alterações de estrutura previstas pelas versões.



-- ================================================================
-- INÍCIO: quizup_v36_2_7_MIGRATION_COMPLETA.sql
-- ================================================================
-- QuizUp v36.2.7 - migration consolidada Mercado Pago + Coins + segurança
-- Execute depois das migrations anteriores. Não apaga dados existentes.

-- 1. Segurança de cadastro
create unique index if not exists profiles_username_lower_unique on public.profiles(lower(username)) where username is not null;
create or replace function public.is_username_available(p_username text) returns boolean language sql security definer set search_path=public as $$ select not exists(select 1 from public.profiles where lower(username)=lower(trim(p_username))); $$;
revoke all on function public.is_username_available(text) from public; grant execute on function public.is_username_available(text) to anon,authenticated;

-- 2. Controle de pagamentos
alter table public.premium_store_settings add column if not exists payments_enabled boolean not null default false;

-- 3. Pacotes de Coins
create table if not exists public.coin_packages(id uuid primary key default gen_random_uuid(),name text not null,coins bigint not null check(coins>0),price_cents integer not null check(price_cents>0),active boolean not null default true,sort_order integer not null default 0,created_at timestamptz not null default now(),created_by uuid references public.profiles(id) on delete set null);
alter table public.coin_packages enable row level security;
drop policy if exists "coin packages read active" on public.coin_packages;
DROP POLICY IF EXISTS "coin packages read active" ON public.coin_packages;
create policy "coin packages read active" on public.coin_packages for select to authenticated using(active=true or exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin'));
drop policy if exists "coin packages admin insert" on public.coin_packages;
DROP POLICY IF EXISTS "coin packages admin insert" ON public.coin_packages;
create policy "coin packages admin insert" on public.coin_packages for insert to authenticated with check(exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin'));
drop policy if exists "coin packages admin update" on public.coin_packages;
DROP POLICY IF EXISTS "coin packages admin update" ON public.coin_packages;
create policy "coin packages admin update" on public.coin_packages for update to authenticated using(exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin')) with check(exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin'));

insert into public.coin_packages(name,coins,price_cents,sort_order,active) select v.name,v.coins,v.price_cents,v.sort_order,true from (values('Pacote 1.000 Coins',1000,1000,1),('Pacote 2.500 Coins',2500,2000,2),('Pacote 6.000 Coins',6000,4500,3)) v(name,coins,price_cents,sort_order) where not exists(select 1 from public.coin_packages cp where cp.coins=v.coins and cp.price_cents=v.price_cents);

-- 4. Pedidos reais de Coins
create table if not exists public.coin_orders(id uuid primary key default gen_random_uuid(),user_id uuid not null references public.profiles(id) on delete cascade,package_id uuid references public.coin_packages(id) on delete set null,coins bigint not null check(coins>0),amount_cents integer not null check(amount_cents>0),status text not null default 'pending' check(status in ('pending','approved','paid','rejected','cancelled','refunded')),provider text not null default 'mercadopago',provider_preference_id text,provider_payment_id text,external_reference text not null unique,raw_payment jsonb,created_at timestamptz not null default now(),updated_at timestamptz not null default now(),paid_at timestamptz);
create unique index if not exists coin_orders_provider_payment_uidx on public.coin_orders(provider,provider_payment_id) where provider_payment_id is not null;
create index if not exists coin_orders_user_created_idx on public.coin_orders(user_id,created_at desc);
create index if not exists coin_orders_status_idx on public.coin_orders(status,created_at desc);
alter table public.coin_orders enable row level security;
drop policy if exists "coin orders own read" on public.coin_orders;
DROP POLICY IF EXISTS "coin orders own read" ON public.coin_orders;
create policy "coin orders own read" on public.coin_orders for select to authenticated using(user_id=auth.uid());
drop policy if exists "coin orders admin read" on public.coin_orders;
DROP POLICY IF EXISTS "coin orders admin read" ON public.coin_orders;
create policy "coin orders admin read" on public.coin_orders for select to authenticated using(exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin'));

-- 5. Ledger idempotente
create table if not exists public.coin_ledger(id bigint generated by default as identity primary key,user_id uuid not null references public.profiles(id) on delete cascade,amount bigint not null,source_type text not null,source_id text not null,description text,created_at timestamptz not null default now(),unique(source_type,source_id,user_id));
alter table public.coin_ledger enable row level security;
drop policy if exists "coin ledger own read" on public.coin_ledger;
DROP POLICY IF EXISTS "coin ledger own read" ON public.coin_ledger;
create policy "coin ledger own read" on public.coin_ledger for select to authenticated using(user_id=auth.uid());

-- 6. Pedido criado no servidor. O cliente não envia preço.
create or replace function public.create_coin_order(p_package_id uuid) returns public.coin_orders language plpgsql security definer set search_path=public as $$
declare p public.coin_packages; s public.premium_store_settings; o public.coin_orders; ref text;
begin
 if auth.uid() is null then raise exception 'Não autenticado'; end if;
 if (select count(*) from public.coin_orders where user_id=auth.uid() and status='pending' and created_at>now()-interval '10 minutes') >= 5 then raise exception 'Muitas compras pendentes. Aguarde alguns minutos antes de criar outra.'; end if;
 select * into s from public.premium_store_settings where id=1;
 if coalesce(s.enabled,false)=false or coalesce(s.coins_enabled,false)=false or coalesce(s.payments_enabled,false)=false then raise exception 'A compra de QuizCoins está desativada'; end if;
 select * into p from public.coin_packages where id=p_package_id and active=true;
 if p.id is null then raise exception 'Pacote de Coins não encontrado ou inativo'; end if;
 o.id:=gen_random_uuid(); ref:='quizup_'||replace(o.id::text,'-','');
 insert into public.coin_orders(id,user_id,package_id,coins,amount_cents,status,external_reference) values(o.id,auth.uid(),p.id,p.coins,p.price_cents,'pending',ref) returning * into o;
 return o;
end $$;
revoke all on function public.create_coin_order(uuid) from public; grant execute on function public.create_coin_order(uuid) to authenticated;

-- 7. Confirmação server-side e crédito atômico. Somente service_role pode executar.
create or replace function public.finalize_coin_payment(p_order_id uuid,p_payment_id text,p_status text,p_amount_cents integer,p_raw jsonb default '{}'::jsonb) returns jsonb language plpgsql security definer set search_path=public as $$
declare o public.coin_orders; bal bigint; final_status text;
begin
 select * into o from public.coin_orders where id=p_order_id for update;
 if o.id is null then raise exception 'Pedido não encontrado'; end if;
 final_status:=case when p_status='approved' then 'approved' when p_status in ('pending','in_process','authorized') then 'pending' when p_status in ('cancelled','refunded','charged_back') then 'refunded' else 'rejected' end;
 if o.status in ('approved','paid') then return jsonb_build_object('ok',true,'already_processed',true,'status',o.status,'coins',o.coins); end if;
 if final_status='approved' then
   if p_amount_cents<>o.amount_cents then raise exception 'Valor do pagamento não corresponde ao pedido'; end if;
   if exists(select 1 from public.coin_ledger l where l.source_type='mercadopago_payment' and l.source_id=p_payment_id and l.user_id=o.user_id) then
     update public.coin_orders set status='approved',provider_payment_id=p_payment_id,raw_payment=p_raw,updated_at=now(),paid_at=coalesce(paid_at,now()) where id=o.id;
     return jsonb_build_object('ok',true,'already_processed',true,'status','approved','coins',o.coins);
   end if;
   update public.profiles set coins=coalesce(coins,0)+o.coins where id=o.user_id returning coins into bal;
   insert into public.coin_ledger(user_id,amount,source_type,source_id,description) values(o.user_id,o.coins,'mercadopago_payment',p_payment_id,'Compra de QuizCoins') on conflict do nothing;
   update public.coin_orders set status='approved',provider_payment_id=p_payment_id,raw_payment=p_raw,updated_at=now(),paid_at=now() where id=o.id;
   return jsonb_build_object('ok',true,'already_processed',false,'status','approved','coins',o.coins,'balance',bal);
 end if;
 update public.coin_orders set status=final_status,provider_payment_id=coalesce(provider_payment_id,p_payment_id),raw_payment=p_raw,updated_at=now() where id=o.id;
 return jsonb_build_object('ok',true,'already_processed',false,'status',final_status,'coins',0);
end $$;
revoke all on function public.finalize_coin_payment(uuid,text,text,integer,jsonb) from public; grant execute on function public.finalize_coin_payment(uuid,text,text,integer,jsonb) to service_role;

-- 8. Atualiza preferência pelo usuário autenticado
create or replace function public.set_coin_order_preference(p_order_id uuid,p_preference_id text) returns public.coin_orders language plpgsql security definer set search_path=public as $$
declare o public.coin_orders;
begin update public.coin_orders set provider_preference_id=p_preference_id,updated_at=now() where id=p_order_id and user_id=auth.uid() and status='pending' returning * into o; if o.id is null then raise exception 'Pedido não encontrado'; end if; return o; end $$;
revoke all on function public.set_coin_order_preference(uuid,text) from public; grant execute on function public.set_coin_order_preference(uuid,text) to authenticated;

-- 9. Administração de vendas/contas
create or replace function public.admin_list_coin_orders(p_limit integer default 100) returns table(id uuid,username text,email text,coins bigint,amount_cents integer,status text,provider_payment_id text,created_at timestamptz,paid_at timestamptz) language plpgsql security definer set search_path=public,auth as $$
begin if not exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin') then raise exception 'Acesso negado'; end if; return query select o.id,p.username,u.email,o.coins,o.amount_cents,o.status,o.provider_payment_id,o.created_at,o.paid_at from public.coin_orders o join public.profiles p on p.id=o.user_id join auth.users u on u.id=o.user_id order by o.created_at desc limit greatest(1,least(coalesce(p_limit,100),500)); end $$;
revoke all on function public.admin_list_coin_orders(integer) from public; grant execute on function public.admin_list_coin_orders(integer) to authenticated;
create or replace function public.admin_list_accounts() returns table(id uuid,username text,display_name text,email text,role text,created_at timestamptz) language plpgsql security definer set search_path=public,auth as $$ begin if not exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin') then raise exception 'Acesso negado'; end if; return query select p.id,p.username,p.display_name,u.email,p.role,u.created_at from public.profiles p join auth.users u on u.id=p.id order by u.created_at desc; end $$;
grant execute on function public.admin_list_accounts() to authenticated;
create or replace function public.admin_set_player_title(p_user_id uuid,p_title text) returns public.profiles language plpgsql security definer set search_path=public as $$ declare p public.profiles; begin if not exists(select 1 from public.profiles a where a.id=auth.uid() and a.role='admin') then raise exception 'Acesso negado'; end if; update public.profiles set premium_title=nullif(trim(p_title),'') where id=p_user_id returning * into p; if p.id is null then raise exception 'Jogador não encontrado'; end if; return p; end $$;
grant execute on function public.admin_set_player_title(uuid,text) to authenticated;

-- 10. Índices úteis
create index if not exists coin_orders_external_ref_idx on public.coin_orders(external_reference);


-- 11. MERCADO PAGO DESATIVADO POR PADRÃO (estrutura permanece pronta)
update public.premium_store_settings set payments_enabled=false where id=1;

-- 12. Coins: crédito manual seguro pelo administrador
create or replace function public.admin_grant_coins(p_username text,p_amount bigint,p_reason text default 'Crédito manual do administrador')
returns jsonb language plpgsql security definer set search_path=public as $$
declare target public.profiles; bal bigint; src text;
begin
  if not exists(select 1 from public.profiles where id=auth.uid() and role='admin') then raise exception 'Acesso negado'; end if;
  if p_amount is null or p_amount <= 0 then raise exception 'Quantidade de Coins inválida'; end if;
  select * into target from public.profiles where lower(username)=lower(trim(p_username)) limit 1;
  if target.id is null then raise exception 'Jogador não encontrado'; end if;
  src:='admin_grant_'||gen_random_uuid()::text;
  update public.profiles set coins=coalesce(coins,0)+p_amount where id=target.id returning coins into bal;
  insert into public.coin_ledger(user_id,amount,source_type,source_id,description)
    values(target.id,p_amount,'admin_grant',src,coalesce(nullif(trim(p_reason),''),'Crédito manual do administrador'));
  return jsonb_build_object('ok',true,'user_id',target.id,'username',target.username,'coins',p_amount,'balance',bal);
end $$;
revoke all on function public.admin_grant_coins(text,bigint,text) from public;
grant execute on function public.admin_grant_coins(text,bigint,text) to authenticated;

-- 13. Suporte / conversa com a equipe
create table if not exists public.support_threads(
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  status text not null default 'open' check(status in ('open','closed')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index if not exists support_threads_one_per_user on public.support_threads(user_id);
create index if not exists support_threads_updated_idx on public.support_threads(updated_at desc);

create table if not exists public.support_messages(
  id uuid primary key default gen_random_uuid(),
  thread_id uuid not null references public.support_threads(id) on delete cascade,
  sender_id uuid not null references public.profiles(id) on delete cascade,
  message text not null check(length(trim(message)) between 1 and 1000),
  created_at timestamptz not null default now()
);
create index if not exists support_messages_thread_idx on public.support_messages(thread_id,created_at);

alter table public.support_threads enable row level security;
alter table public.support_messages enable row level security;

drop policy if exists "support threads own read" on public.support_threads;
DROP POLICY IF EXISTS "support threads own read" ON public.support_threads;
create policy "support threads own read" on public.support_threads for select to authenticated
using(user_id=auth.uid() or exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin'));
drop policy if exists "support threads own insert" on public.support_threads;
DROP POLICY IF EXISTS "support threads own insert" ON public.support_threads;
create policy "support threads own insert" on public.support_threads for insert to authenticated
with check(user_id=auth.uid());
drop policy if exists "support threads admin update" on public.support_threads;
DROP POLICY IF EXISTS "support threads admin update" ON public.support_threads;
create policy "support threads admin update" on public.support_threads for update to authenticated
using(exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin'))
with check(exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin'));

drop policy if exists "support messages participants read" on public.support_messages;
DROP POLICY IF EXISTS "support messages participants read" ON public.support_messages;
create policy "support messages participants read" on public.support_messages for select to authenticated
using(
  exists(select 1 from public.support_threads t where t.id=thread_id and
    (t.user_id=auth.uid() or exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin')))
);
drop policy if exists "support messages participant insert" on public.support_messages;
DROP POLICY IF EXISTS "support messages participant insert" ON public.support_messages;
create policy "support messages participant insert" on public.support_messages for insert to authenticated
with check(
  sender_id=auth.uid() and
  exists(select 1 from public.support_threads t where t.id=thread_id and
    (t.user_id=auth.uid() or exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin')))
);

-- 14. Sessão única por conta: o último aparelho conectado derruba o anterior
create table if not exists public.quizup_active_sessions(
  user_id uuid primary key references public.profiles(id) on delete cascade,
  session_id text not null,
  last_seen_at timestamptz not null default now()
);
create index if not exists quizup_active_sessions_seen_idx on public.quizup_active_sessions(last_seen_at);

alter table public.quizup_active_sessions enable row level security;
drop policy if exists "quizup sessions own read" on public.quizup_active_sessions;
DROP POLICY IF EXISTS "quizup sessions own read" ON public.quizup_active_sessions;
create policy "quizup sessions own read" on public.quizup_active_sessions for select to authenticated using(user_id=auth.uid());

create or replace function public.claim_quizup_session(p_session_id text)
returns boolean language plpgsql security definer set search_path=public as $$
begin
  if auth.uid() is null or nullif(trim(p_session_id),'') is null then return false; end if;
  insert into public.quizup_active_sessions(user_id,session_id,last_seen_at)
    values(auth.uid(),trim(p_session_id),now())
  on conflict(user_id) do update set session_id=excluded.session_id,last_seen_at=now();
  return true;
end $$;
create or replace function public.touch_quizup_session(p_session_id text)
returns boolean language sql security definer set search_path=public as $$
  update public.quizup_active_sessions
    set last_seen_at=now()
  where user_id=auth.uid() and session_id=trim(p_session_id)
  returning true;
$$;
create or replace function public.release_quizup_session(p_session_id text)
returns boolean language sql security definer set search_path=public as $$
  delete from public.quizup_active_sessions where user_id=auth.uid() and session_id=trim(p_session_id)
  returning true;
$$;
revoke all on function public.claim_quizup_session(text) from public;
revoke all on function public.touch_quizup_session(text) from public;
revoke all on function public.release_quizup_session(text) from public;
grant execute on function public.claim_quizup_session(text) to authenticated;
grant execute on function public.touch_quizup_session(text) to authenticated;
grant execute on function public.release_quizup_session(text) to authenticated;

-- 15. Reações: índice e proteção contra spam/duplicação
create index if not exists match_reactions_match_created_idx on public.match_reactions(match_id,created_at desc);

-- 16. Compra de cosméticos usando QuizCoins (sem Mercado Pago)
create or replace function public.purchase_premium_item(p_item_id text,p_expected_price bigint default null)
returns jsonb language plpgsql security definer set search_path=public as $$
declare
  it public.premium_items;
  own boolean;
  charge bigint;
  bal bigint;
  promo_ok boolean;
  src text;
begin
  if auth.uid() is null then raise exception 'Não autenticado'; end if;
  select * into it from public.premium_items where id=p_item_id and active=true limit 1;
  if it.id is null then raise exception 'Item não encontrado ou indisponível'; end if;
  if exists(select 1 from public.premium_store_settings where id=1 and (enabled=false or cosmetics_enabled=false)) then
    raise exception 'A loja de cosméticos está desativada';
  end if;
  promo_ok:=coalesce(it.promo_active,false) and coalesce(it.promo_price_coins,0)>0 and coalesce(it.promo_price_coins,0)<coalesce(it.price_coins,0)
    and (it.promo_expires_at is null or it.promo_expires_at>now());
  charge:=case when promo_ok then it.promo_price_coins else it.price_coins end;
  if charge is null or charge<0 then raise exception 'Preço do item inválido'; end if;
  if p_expected_price is not null and p_expected_price<>charge then raise exception 'O preço do item mudou. Atualize a loja e tente novamente.'; end if;
  select exists(select 1 from public.user_premium_items up where up.user_id=auth.uid() and up.item_id=it.id) into own;
  if own then
    select coins into bal from public.profiles where id=auth.uid();
    return jsonb_build_object('ok',true,'already_owned',true,'balance',coalesce(bal,0),'charge',0);
  end if;
  update public.profiles set coins=coalesce(coins,0)-charge where id=auth.uid() and coalesce(coins,0)>=charge returning coins into bal;
  if bal is null then raise exception 'Você não possui QuizCoins suficientes'; end if;
  insert into public.user_premium_items(user_id,item_id,active,purchased_at) values(auth.uid(),it.id,true,now());
  src:='premium_purchase_'||gen_random_uuid()::text;
  insert into public.coin_ledger(user_id,amount,source_type,source_id,description) values(auth.uid(),-charge,'premium_purchase',src,'Compra: '||it.name);
  return jsonb_build_object('ok',true,'already_owned',false,'balance',bal,'charge',charge,'item_id',it.id);
exception when unique_violation then
  select coins into bal from public.profiles where id=auth.uid();
  return jsonb_build_object('ok',true,'already_owned',true,'balance',coalesce(bal,0),'charge',0);
end $$;
revoke all on function public.purchase_premium_item(text,bigint) from public;
grant execute on function public.purchase_premium_item(text,bigint) to authenticated;

-- 17. Reações da partida: os dois participantes podem ler/enviar
alter table public.match_reactions enable row level security;
drop policy if exists "match reactions participants read" on public.match_reactions;
DROP POLICY IF EXISTS "match reactions participants read" ON public.match_reactions;
create policy "match reactions participants read" on public.match_reactions for select to authenticated using(
  exists(select 1 from public.matches m where m.id=match_id and auth.uid()=any(m.player_ids))
);
drop policy if exists "match reactions participants insert" on public.match_reactions;
DROP POLICY IF EXISTS "match reactions participants insert" ON public.match_reactions;
create policy "match reactions participants insert" on public.match_reactions for insert to authenticated with check(
  sender_id=auth.uid() and exists(select 1 from public.matches m where m.id=match_id and auth.uid()=any(m.player_ids))
);

-- 18. Feed social do QuizUp
create table if not exists public.social_posts(
  id uuid primary key default gen_random_uuid(), user_id uuid not null references public.profiles(id) on delete cascade,
  caption text, media_url text, post_type text not null default 'text' check(post_type in ('text','image')),
  category_name text, status text not null default 'published' check(status in ('published','hidden','deleted')),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists public.social_likes(
  post_id uuid not null references public.social_posts(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(), primary key(post_id,user_id)
);
create table if not exists public.social_comments(
  id uuid primary key default gen_random_uuid(), post_id uuid not null references public.social_posts(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade, body text not null check(length(trim(body)) between 1 and 500),
  created_at timestamptz not null default now()
);
create index if not exists social_posts_feed_idx on public.social_posts(status,created_at desc);
create index if not exists social_posts_category_idx on public.social_posts(category_name,created_at desc);
create index if not exists social_comments_post_idx on public.social_comments(post_id,created_at);
alter table public.social_posts enable row level security;
alter table public.social_likes enable row level security;
alter table public.social_comments enable row level security;
drop policy if exists "social posts read published" on public.social_posts;
DROP POLICY IF EXISTS "social posts read published" ON public.social_posts;
create policy "social posts read published" on public.social_posts for select to authenticated using(status='published' or user_id=auth.uid() or exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin'));
drop policy if exists "social posts own insert" on public.social_posts;
DROP POLICY IF EXISTS "social posts own insert" ON public.social_posts;
create policy "social posts own insert" on public.social_posts for insert to authenticated with check(user_id=auth.uid());
drop policy if exists "social posts own update" on public.social_posts;
DROP POLICY IF EXISTS "social posts own update" ON public.social_posts;
create policy "social posts own update" on public.social_posts for update to authenticated using(user_id=auth.uid() or exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin')) with check(user_id=auth.uid() or exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin'));
drop policy if exists "social posts own delete" on public.social_posts;
DROP POLICY IF EXISTS "social posts own delete" ON public.social_posts;
create policy "social posts own delete" on public.social_posts for delete to authenticated using(user_id=auth.uid() or exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin'));
drop policy if exists "social likes read" on public.social_likes;
DROP POLICY IF EXISTS "social likes read" ON public.social_likes;
create policy "social likes read" on public.social_likes for select to authenticated using(true);
drop policy if exists "social likes own insert" on public.social_likes;
DROP POLICY IF EXISTS "social likes own insert" ON public.social_likes;
create policy "social likes own insert" on public.social_likes for insert to authenticated with check(user_id=auth.uid());
drop policy if exists "social likes own delete" on public.social_likes;
DROP POLICY IF EXISTS "social likes own delete" ON public.social_likes;
create policy "social likes own delete" on public.social_likes for delete to authenticated using(user_id=auth.uid());
drop policy if exists "social comments read" on public.social_comments;
DROP POLICY IF EXISTS "social comments read" ON public.social_comments;
create policy "social comments read" on public.social_comments for select to authenticated using(true);
drop policy if exists "social comments own insert" on public.social_comments;
DROP POLICY IF EXISTS "social comments own insert" ON public.social_comments;
create policy "social comments own insert" on public.social_comments for insert to authenticated with check(user_id=auth.uid());
drop policy if exists "social comments own delete" on public.social_comments;
DROP POLICY IF EXISTS "social comments own delete" ON public.social_comments;
create policy "social comments own delete" on public.social_comments for delete to authenticated using(user_id=auth.uid() or exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin'));

-- Bucket público para fotos/prints do feed. O bucket é público para exibição, mas upload/delete continuam protegidos por RLS.
insert into storage.buckets(id,name,public) values('social-posts','social-posts',true) on conflict(id) do update set public=true;
drop policy if exists "social post media upload" on storage.objects;
DROP POLICY IF EXISTS "social post media upload" ON storage.objects;
create policy "social post media upload" on storage.objects for insert to authenticated with check(bucket_id='social-posts' and (storage.foldername(name))[1]=auth.uid()::text);
drop policy if exists "social post media update" on storage.objects;
DROP POLICY IF EXISTS "social post media update" ON storage.objects;
create policy "social post media update" on storage.objects for update to authenticated using(bucket_id='social-posts' and (storage.foldername(name))[1]=auth.uid()::text);
drop policy if exists "social post media delete" on storage.objects;
DROP POLICY IF EXISTS "social post media delete" ON storage.objects;
create policy "social post media delete" on storage.objects for delete to authenticated using(bucket_id='social-posts' and ((storage.foldername(name))[1]=auth.uid()::text or exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin')));

-- 19. Realtime do feed social
alter table public.social_posts replica identity full;
alter table public.social_likes replica identity full;
alter table public.social_comments replica identity full;

-- Compatibilidade: alguns bancos antigos expõem o id do item como integer.
create or replace function public.purchase_premium_item(p_item_id integer)
returns jsonb language sql security definer set search_path=public as $$
  select public.purchase_premium_item(p_item_id::text,null::bigint);
$$;
revoke all on function public.purchase_premium_item(integer) from public;
grant execute on function public.purchase_premium_item(integer) to authenticated;

-- ================================================================
-- QuizUp v37 - Comunidade, notificações, segurança e conquistas
-- ================================================================

-- 20. Notificações persistentes
create table if not exists public.notifications(
  id uuid primary key default gen_random_uuid(),
  recipient_id uuid not null references public.profiles(id) on delete cascade,
  actor_id uuid references public.profiles(id) on delete set null,
  type text not null,
  title text not null,
  body text,
  data jsonb not null default '{}'::jsonb,
  read_at timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists notifications_recipient_idx on public.notifications(recipient_id,created_at desc);
alter table public.notifications enable row level security;
drop policy if exists "notifications own read" on public.notifications;
DROP POLICY IF EXISTS "notifications own read" ON public.notifications;
create policy "notifications own read" on public.notifications for select to authenticated using(recipient_id=auth.uid());
drop policy if exists "notifications own update" on public.notifications;
DROP POLICY IF EXISTS "notifications own update" ON public.notifications;
create policy "notifications own update" on public.notifications for update to authenticated using(recipient_id=auth.uid()) with check(recipient_id=auth.uid());
alter table public.notifications replica identity full;

-- 21. Bloqueio, silenciamento e denúncias
create table if not exists public.user_blocks(
  blocker_id uuid not null references public.profiles(id) on delete cascade,
  blocked_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key(blocker_id,blocked_id),
  check(blocker_id<>blocked_id)
);
create table if not exists public.user_mutes(
  muter_id uuid not null references public.profiles(id) on delete cascade,
  muted_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key(muter_id,muted_id),
  check(muter_id<>muted_id)
);
create table if not exists public.social_reports(
  id uuid primary key default gen_random_uuid(),
  post_id uuid references public.social_posts(id) on delete cascade,
  comment_id uuid references public.social_comments(id) on delete cascade,
  reporter_id uuid not null references public.profiles(id) on delete cascade,
  reason text not null check(length(trim(reason)) between 3 and 500),
  status text not null default 'open' check(status in ('open','reviewing','resolved','dismissed')),
  created_at timestamptz not null default now(),
  resolved_at timestamptz,
  resolved_by uuid references public.profiles(id) on delete set null,
  check(post_id is not null or comment_id is not null)
);
create index if not exists social_reports_status_idx on public.social_reports(status,created_at desc);

alter table public.user_blocks enable row level security;
alter table public.user_mutes enable row level security;
alter table public.social_reports enable row level security;
drop policy if exists "blocks own read" on public.user_blocks;
DROP POLICY IF EXISTS "blocks own read" ON public.user_blocks;
create policy "blocks own read" on public.user_blocks for select to authenticated using(blocker_id=auth.uid());
drop policy if exists "blocks own insert" on public.user_blocks;
DROP POLICY IF EXISTS "blocks own insert" ON public.user_blocks;
create policy "blocks own insert" on public.user_blocks for insert to authenticated with check(blocker_id=auth.uid());
drop policy if exists "blocks own delete" on public.user_blocks;
DROP POLICY IF EXISTS "blocks own delete" ON public.user_blocks;
create policy "blocks own delete" on public.user_blocks for delete to authenticated using(blocker_id=auth.uid());
drop policy if exists "mutes own read" on public.user_mutes;
DROP POLICY IF EXISTS "mutes own read" ON public.user_mutes;
create policy "mutes own read" on public.user_mutes for select to authenticated using(muter_id=auth.uid());
drop policy if exists "mutes own insert" on public.user_mutes;
DROP POLICY IF EXISTS "mutes own insert" ON public.user_mutes;
create policy "mutes own insert" on public.user_mutes for insert to authenticated with check(muter_id=auth.uid());
drop policy if exists "mutes own delete" on public.user_mutes;
DROP POLICY IF EXISTS "mutes own delete" ON public.user_mutes;
create policy "mutes own delete" on public.user_mutes for delete to authenticated using(muter_id=auth.uid());
drop policy if exists "reports own insert" on public.social_reports;
DROP POLICY IF EXISTS "reports own insert" ON public.social_reports;
create policy "reports own insert" on public.social_reports for insert to authenticated with check(reporter_id=auth.uid());
drop policy if exists "reports own read" on public.social_reports;
DROP POLICY IF EXISTS "reports own read" ON public.social_reports;
create policy "reports own read" on public.social_reports for select to authenticated using(reporter_id=auth.uid() or exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin'));
drop policy if exists "reports admin update" on public.social_reports;
DROP POLICY IF EXISTS "reports admin update" ON public.social_reports;
create policy "reports admin update" on public.social_reports for update to authenticated using(exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin')) with check(exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin'));

-- 22. Presença simples (online/offline) sem polling pesado
create table if not exists public.quizup_presence(
  user_id uuid primary key references public.profiles(id) on delete cascade,
  last_seen_at timestamptz not null default now()
);
create index if not exists quizup_presence_seen_idx on public.quizup_presence(last_seen_at desc);
alter table public.quizup_presence enable row level security;
drop policy if exists "presence authenticated read" on public.quizup_presence;
DROP POLICY IF EXISTS "presence authenticated read" ON public.quizup_presence;
create policy "presence authenticated read" on public.quizup_presence for select to authenticated using(true);
drop policy if exists "presence own write" on public.quizup_presence;
DROP POLICY IF EXISTS "presence own write" ON public.quizup_presence;
create policy "presence own write" on public.quizup_presence for insert to authenticated with check(user_id=auth.uid());
drop policy if exists "presence own update" on public.quizup_presence;
DROP POLICY IF EXISTS "presence own update" ON public.quizup_presence;
create policy "presence own update" on public.quizup_presence for update to authenticated using(user_id=auth.uid()) with check(user_id=auth.uid());

-- 23. Conquistas desbloqueáveis
alter table public.achievements add column if not exists code text;
alter table public.achievements add column if not exists criteria_type text;
alter table public.achievements add column if not exists threshold bigint default 1;
create unique index if not exists achievements_code_uidx on public.achievements(code) where code is not null;
create table if not exists public.user_achievements(
  user_id uuid not null references public.profiles(id) on delete cascade,
  achievement_id uuid not null references public.achievements(id) on delete cascade,
  unlocked_at timestamptz not null default now(),
  primary key(user_id,achievement_id)
);
create index if not exists user_achievements_user_idx on public.user_achievements(user_id,unlocked_at desc);
alter table public.user_achievements enable row level security;
drop policy if exists "user achievements own read" on public.user_achievements;
DROP POLICY IF EXISTS "user achievements own read" ON public.user_achievements;
create policy "user achievements own read" on public.user_achievements for select to authenticated using(user_id=auth.uid());
drop policy if exists "user achievements public read" on public.user_achievements;
DROP POLICY IF EXISTS "user achievements public read" ON public.user_achievements;
create policy "user achievements public read" on public.user_achievements for select to authenticated using(true);

insert into public.achievements(title,description,icon,active,code,criteria_type,threshold)
select v.title,v.description,v.icon,true,v.code,v.criteria_type,v.threshold
from (values
 ('Primeira partida','Jogue sua primeira partida no QuizUp.','🎮','first_game','first_game',1),
 ('Primeira vitória','Vença sua primeira partida.','🥇','wins','wins',1),
 ('Veterano','Complete 10 partidas.','🎯','games','games',10),
 ('Campeão','Consiga 10 vitórias.','🏆','wins_10','wins',10),
 ('Sequência de fogo','Alcance uma sequência de 5 vitórias.','🔥','streak','streak',5),
 ('Milionário de Coins','Acumule 1.000 QuizCoins.','⚡','coins_1000','coins',1000)
) v(title,description,icon,code,criteria_type,threshold)
where not exists(select 1 from public.achievements a where a.code=v.code);

create or replace function public.quizup_check_achievements(p_user_id uuid)
returns void language plpgsql security definer set search_path=public as $$
declare a record; value bigint; already boolean;
begin
  for a in select id,code,criteria_type,threshold,title from public.achievements where active=true and code is not null loop
    value:=0;
    if a.criteria_type='games' or a.criteria_type='first_game' then
      select count(*) into value from public.game_results where user_id=p_user_id;
    elsif a.criteria_type='wins' then
      select count(*) into value from public.game_results where user_id=p_user_id and won=true;
    elsif a.criteria_type='streak' then
      select coalesce(streak,0) into value from public.profiles where id=p_user_id;
    elsif a.criteria_type='coins' then
      select coalesce(coins,0) into value from public.profiles where id=p_user_id;
    end if;
    if value>=coalesce(a.threshold,1) then
      insert into public.user_achievements(user_id,achievement_id) values(p_user_id,a.id) on conflict do nothing;
    end if;
  end loop;
end $$;
revoke all on function public.quizup_check_achievements(uuid) from public;
grant execute on function public.quizup_check_achievements(uuid) to authenticated;

create or replace function public.quizup_notify_achievement()
returns trigger language plpgsql security definer set search_path=public as $$
declare a record;
begin
  select title,description,icon into a from public.achievements where id=new.achievement_id;
  insert into public.notifications(recipient_id,actor_id,type,title,body,data)
  values(new.user_id,null,'achievement',coalesce(a.icon,'🏆')||' Conquista desbloqueada',coalesce(a.description,a.title),jsonb_build_object('achievement_id',new.achievement_id));
  return new;
end $$;
drop trigger if exists trg_quizup_notify_achievement on public.user_achievements;
DROP TRIGGER IF EXISTS trg_quizup_notify_achievement ON public.user_achievements;
create trigger trg_quizup_notify_achievement after insert on public.user_achievements for each row execute function public.quizup_notify_achievement();

create or replace function public.quizup_game_result_achievements()
returns trigger language plpgsql security definer set search_path=public as $$
begin perform public.quizup_check_achievements(new.user_id); return new; end $$;
drop trigger if exists trg_quizup_game_result_achievements on public.game_results;
DROP TRIGGER IF EXISTS trg_quizup_game_result_achievements ON public.game_results;
create trigger trg_quizup_game_result_achievements after insert on public.game_results for each row execute function public.quizup_game_result_achievements();

-- 24. Publicação automática do resultado da partida
create or replace function public.quizup_publish_game_result()
returns trigger language plpgsql security definer set search_path=public as $$
declare u public.profiles; caption text; post_id uuid;
begin
  select * into u from public.profiles where id=new.user_id;
  caption:='🎮 Resultado da partida • '||coalesce(new.category,'Geral')||' • '||coalesce(new.score,0)||' pontos • '||case when new.won then 'Vitória 🏆' else coalesce(new.outcome,'Partida') end;
  if not exists(select 1 from public.social_posts where user_id=new.user_id and coalesce(data->>'game_result_id','')=new.id::text) then
    insert into public.social_posts(user_id,caption,post_type,category_name,status,data)
    values(new.user_id,caption,'text',new.category,'published',jsonb_build_object('game_result_id',new.id::text,'auto',true)) returning id into post_id;
  end if;
  return new;
end $$;
-- Add a JSON column only if this older schema doesn't have it.
alter table public.social_posts add column if not exists data jsonb not null default '{}'::jsonb;
drop trigger if exists trg_quizup_publish_game_result on public.game_results;
DROP TRIGGER IF EXISTS trg_quizup_publish_game_result ON public.game_results;
create trigger trg_quizup_publish_game_result after insert on public.game_results for each row execute function public.quizup_publish_game_result();

-- 25. Notificações de comunidade
create or replace function public.quizup_notify_friend_request()
returns trigger language plpgsql security definer set search_path=public as $$
declare u public.profiles;
begin
  if new.status='pending' then
    select * into u from public.profiles where id=new.requester_id;
    insert into public.notifications(recipient_id,actor_id,type,title,body,data)
    values(new.addressee_id,new.requester_id,'friend_request','♧ Nova solicitação de amizade',coalesce(u.username,'Alguém')||' quer ser seu amigo.',jsonb_build_object('friendship_id',new.id));
  end if;
  return new;
end $$;
drop trigger if exists trg_quizup_notify_friend_request on public.friendships;
DROP TRIGGER IF EXISTS trg_quizup_notify_friend_request ON public.friendships;
create trigger trg_quizup_notify_friend_request after insert on public.friendships for each row execute function public.quizup_notify_friend_request();

create or replace function public.quizup_notify_challenge()
returns trigger language plpgsql security definer set search_path=public as $$
declare u public.profiles;
begin
  if new.status='pending' then
    select * into u from public.profiles where id=new.challenger_id;
    insert into public.notifications(recipient_id,actor_id,type,title,body,data)
    values(new.challenged_id,new.challenger_id,'challenge','⚔️ Novo desafio',coalesce(u.username,'Alguém')||' te desafiou em '||coalesce(new.category,'Geral')||'.',jsonb_build_object('challenge_id',new.id));
  end if;
  return new;
end $$;
drop trigger if exists trg_quizup_notify_challenge on public.challenges;
DROP TRIGGER IF EXISTS trg_quizup_notify_challenge ON public.challenges;
create trigger trg_quizup_notify_challenge after insert on public.challenges for each row execute function public.quizup_notify_challenge();

create or replace function public.quizup_notify_message()
returns trigger language plpgsql security definer set search_path=public as $$
declare u public.profiles;
begin
  select * into u from public.profiles where id=new.sender_id;
  insert into public.notifications(recipient_id,actor_id,type,title,body,data)
  values(new.receiver_id,new.sender_id,'message','💬 Nova mensagem',coalesce(u.username,'Alguém')||' enviou uma mensagem.',jsonb_build_object('message_id',new.id));
  return new;
end $$;
drop trigger if exists trg_quizup_notify_message on public.direct_messages;
DROP TRIGGER IF EXISTS trg_quizup_notify_message ON public.direct_messages;
create trigger trg_quizup_notify_message after insert on public.direct_messages for each row execute function public.quizup_notify_message();

create or replace function public.quizup_notify_social()
returns trigger language plpgsql security definer set search_path=public as $$
declare owner_id uuid; u public.profiles; label text; typ text; payload jsonb;
begin
  if TG_TABLE_NAME='social_likes' then
    select user_id into owner_id from public.social_posts where id=new.post_id;
    if owner_id is null or owner_id=new.user_id then return new; end if;
    select * into u from public.profiles where id=new.user_id;
    typ:='like'; label:='❤️'||' Nova curtida'; payload:=jsonb_build_object('post_id',new.post_id);
  else
    select user_id into owner_id from public.social_posts where id=new.post_id;
    if owner_id is null or owner_id=new.user_id then return new; end if;
    select * into u from public.profiles where id=new.user_id;
    typ:='comment'; label:='💬 Novo comentário'; payload:=jsonb_build_object('post_id',new.post_id,'comment_id',new.id);
  end if;
  insert into public.notifications(recipient_id,actor_id,type,title,body,data)
  values(owner_id,new.user_id,typ,label,coalesce(u.username,'Alguém')||' interagiu com sua publicação.',payload);
  return new;
end $$;
drop trigger if exists trg_quizup_notify_social_like on public.social_likes;
DROP TRIGGER IF EXISTS trg_quizup_notify_social_like ON public.social_likes;
create trigger trg_quizup_notify_social_like after insert on public.social_likes for each row execute function public.quizup_notify_social();
drop trigger if exists trg_quizup_notify_social_comment on public.social_comments;
DROP TRIGGER IF EXISTS trg_quizup_notify_social_comment ON public.social_comments;
create trigger trg_quizup_notify_social_comment after insert on public.social_comments for each row execute function public.quizup_notify_social();

-- 26. Segurança contra interações após bloqueio
create or replace function public.quizup_blocked_interaction_guard()
returns trigger language plpgsql security definer set search_path=public as $$
declare other_id uuid;
begin
  if TG_TABLE_NAME='direct_messages' then other_id:=new.receiver_id;
  elsif TG_TABLE_NAME='social_likes' then select user_id into other_id from public.social_posts where id=new.post_id;
  else select user_id into other_id from public.social_posts where id=new.post_id; end if;
  if other_id is not null and (exists(select 1 from public.user_blocks where blocker_id=auth.uid() and blocked_id=other_id) or exists(select 1 from public.user_blocks where blocker_id=other_id and blocked_id=auth.uid())) then
    raise exception 'Interação bloqueada entre estes jogadores';
  end if;
  return new;
end $$;
drop trigger if exists trg_quizup_block_dm on public.direct_messages;
DROP TRIGGER IF EXISTS trg_quizup_block_dm ON public.direct_messages;
create trigger trg_quizup_block_dm before insert on public.direct_messages for each row execute function public.quizup_blocked_interaction_guard();
drop trigger if exists trg_quizup_block_like on public.social_likes;
DROP TRIGGER IF EXISTS trg_quizup_block_like ON public.social_likes;
create trigger trg_quizup_block_like before insert on public.social_likes for each row execute function public.quizup_blocked_interaction_guard();
drop trigger if exists trg_quizup_block_comment on public.social_comments;
DROP TRIGGER IF EXISTS trg_quizup_block_comment ON public.social_comments;
create trigger trg_quizup_block_comment before insert on public.social_comments for each row execute function public.quizup_blocked_interaction_guard();

-- Realtime das notificações.
alter table public.notifications replica identity full;

-- Mercado Pago permanece desligado no v37.
update public.premium_store_settings set payments_enabled=false where id=1;


-- ================================================================
-- INÍCIO: quizup_v37_MIGRATION_COMPLETA.sql
-- ================================================================
-- QuizUp v36.2.7 - migration consolidada Mercado Pago + Coins + segurança
-- Execute depois das migrations anteriores. Não apaga dados existentes.

-- 1. Segurança de cadastro
create unique index if not exists profiles_username_lower_unique on public.profiles(lower(username)) where username is not null;
create or replace function public.is_username_available(p_username text) returns boolean language sql security definer set search_path=public as $$ select not exists(select 1 from public.profiles where lower(username)=lower(trim(p_username))); $$;
revoke all on function public.is_username_available(text) from public; grant execute on function public.is_username_available(text) to anon,authenticated;

-- 2. Controle de pagamentos
alter table public.premium_store_settings add column if not exists payments_enabled boolean not null default false;

-- 3. Pacotes de Coins
create table if not exists public.coin_packages(id uuid primary key default gen_random_uuid(),name text not null,coins bigint not null check(coins>0),price_cents integer not null check(price_cents>0),active boolean not null default true,sort_order integer not null default 0,created_at timestamptz not null default now(),created_by uuid references public.profiles(id) on delete set null);
alter table public.coin_packages enable row level security;
drop policy if exists "coin packages read active" on public.coin_packages;
DROP POLICY IF EXISTS "coin packages read active" ON public.coin_packages;
create policy "coin packages read active" on public.coin_packages for select to authenticated using(active=true or exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin'));
drop policy if exists "coin packages admin insert" on public.coin_packages;
DROP POLICY IF EXISTS "coin packages admin insert" ON public.coin_packages;
create policy "coin packages admin insert" on public.coin_packages for insert to authenticated with check(exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin'));
drop policy if exists "coin packages admin update" on public.coin_packages;
DROP POLICY IF EXISTS "coin packages admin update" ON public.coin_packages;
create policy "coin packages admin update" on public.coin_packages for update to authenticated using(exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin')) with check(exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin'));

insert into public.coin_packages(name,coins,price_cents,sort_order,active) select v.name,v.coins,v.price_cents,v.sort_order,true from (values('Pacote 1.000 Coins',1000,1000,1),('Pacote 2.500 Coins',2500,2000,2),('Pacote 6.000 Coins',6000,4500,3)) v(name,coins,price_cents,sort_order) where not exists(select 1 from public.coin_packages cp where cp.coins=v.coins and cp.price_cents=v.price_cents);

-- 4. Pedidos reais de Coins
create table if not exists public.coin_orders(id uuid primary key default gen_random_uuid(),user_id uuid not null references public.profiles(id) on delete cascade,package_id uuid references public.coin_packages(id) on delete set null,coins bigint not null check(coins>0),amount_cents integer not null check(amount_cents>0),status text not null default 'pending' check(status in ('pending','approved','paid','rejected','cancelled','refunded')),provider text not null default 'mercadopago',provider_preference_id text,provider_payment_id text,external_reference text not null unique,raw_payment jsonb,created_at timestamptz not null default now(),updated_at timestamptz not null default now(),paid_at timestamptz);
create unique index if not exists coin_orders_provider_payment_uidx on public.coin_orders(provider,provider_payment_id) where provider_payment_id is not null;
create index if not exists coin_orders_user_created_idx on public.coin_orders(user_id,created_at desc);
create index if not exists coin_orders_status_idx on public.coin_orders(status,created_at desc);
alter table public.coin_orders enable row level security;
drop policy if exists "coin orders own read" on public.coin_orders;
DROP POLICY IF EXISTS "coin orders own read" ON public.coin_orders;
create policy "coin orders own read" on public.coin_orders for select to authenticated using(user_id=auth.uid());
drop policy if exists "coin orders admin read" on public.coin_orders;
DROP POLICY IF EXISTS "coin orders admin read" ON public.coin_orders;
create policy "coin orders admin read" on public.coin_orders for select to authenticated using(exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin'));

-- 5. Ledger idempotente
create table if not exists public.coin_ledger(id bigint generated by default as identity primary key,user_id uuid not null references public.profiles(id) on delete cascade,amount bigint not null,source_type text not null,source_id text not null,description text,created_at timestamptz not null default now(),unique(source_type,source_id,user_id));
alter table public.coin_ledger enable row level security;
drop policy if exists "coin ledger own read" on public.coin_ledger;
DROP POLICY IF EXISTS "coin ledger own read" ON public.coin_ledger;
create policy "coin ledger own read" on public.coin_ledger for select to authenticated using(user_id=auth.uid());

-- 6. Pedido criado no servidor. O cliente não envia preço.
create or replace function public.create_coin_order(p_package_id uuid) returns public.coin_orders language plpgsql security definer set search_path=public as $$
declare p public.coin_packages; s public.premium_store_settings; o public.coin_orders; ref text;
begin
 if auth.uid() is null then raise exception 'Não autenticado'; end if;
 if (select count(*) from public.coin_orders where user_id=auth.uid() and status='pending' and created_at>now()-interval '10 minutes') >= 5 then raise exception 'Muitas compras pendentes. Aguarde alguns minutos antes de criar outra.'; end if;
 select * into s from public.premium_store_settings where id=1;
 if coalesce(s.enabled,false)=false or coalesce(s.coins_enabled,false)=false or coalesce(s.payments_enabled,false)=false then raise exception 'A compra de QuizCoins está desativada'; end if;
 select * into p from public.coin_packages where id=p_package_id and active=true;
 if p.id is null then raise exception 'Pacote de Coins não encontrado ou inativo'; end if;
 o.id:=gen_random_uuid(); ref:='quizup_'||replace(o.id::text,'-','');
 insert into public.coin_orders(id,user_id,package_id,coins,amount_cents,status,external_reference) values(o.id,auth.uid(),p.id,p.coins,p.price_cents,'pending',ref) returning * into o;
 return o;
end $$;
revoke all on function public.create_coin_order(uuid) from public; grant execute on function public.create_coin_order(uuid) to authenticated;

-- 7. Confirmação server-side e crédito atômico. Somente service_role pode executar.
create or replace function public.finalize_coin_payment(p_order_id uuid,p_payment_id text,p_status text,p_amount_cents integer,p_raw jsonb default '{}'::jsonb) returns jsonb language plpgsql security definer set search_path=public as $$
declare o public.coin_orders; bal bigint; final_status text;
begin
 select * into o from public.coin_orders where id=p_order_id for update;
 if o.id is null then raise exception 'Pedido não encontrado'; end if;
 final_status:=case when p_status='approved' then 'approved' when p_status in ('pending','in_process','authorized') then 'pending' when p_status in ('cancelled','refunded','charged_back') then 'refunded' else 'rejected' end;
 if o.status in ('approved','paid') then return jsonb_build_object('ok',true,'already_processed',true,'status',o.status,'coins',o.coins); end if;
 if final_status='approved' then
   if p_amount_cents<>o.amount_cents then raise exception 'Valor do pagamento não corresponde ao pedido'; end if;
   if exists(select 1 from public.coin_ledger l where l.source_type='mercadopago_payment' and l.source_id=p_payment_id and l.user_id=o.user_id) then
     update public.coin_orders set status='approved',provider_payment_id=p_payment_id,raw_payment=p_raw,updated_at=now(),paid_at=coalesce(paid_at,now()) where id=o.id;
     return jsonb_build_object('ok',true,'already_processed',true,'status','approved','coins',o.coins);
   end if;
   update public.profiles set coins=coalesce(coins,0)+o.coins where id=o.user_id returning coins into bal;
   insert into public.coin_ledger(user_id,amount,source_type,source_id,description) values(o.user_id,o.coins,'mercadopago_payment',p_payment_id,'Compra de QuizCoins') on conflict do nothing;
   update public.coin_orders set status='approved',provider_payment_id=p_payment_id,raw_payment=p_raw,updated_at=now(),paid_at=now() where id=o.id;
   return jsonb_build_object('ok',true,'already_processed',false,'status','approved','coins',o.coins,'balance',bal);
 end if;
 update public.coin_orders set status=final_status,provider_payment_id=coalesce(provider_payment_id,p_payment_id),raw_payment=p_raw,updated_at=now() where id=o.id;
 return jsonb_build_object('ok',true,'already_processed',false,'status',final_status,'coins',0);
end $$;
revoke all on function public.finalize_coin_payment(uuid,text,text,integer,jsonb) from public; grant execute on function public.finalize_coin_payment(uuid,text,text,integer,jsonb) to service_role;

-- 8. Atualiza preferência pelo usuário autenticado
create or replace function public.set_coin_order_preference(p_order_id uuid,p_preference_id text) returns public.coin_orders language plpgsql security definer set search_path=public as $$
declare o public.coin_orders;
begin update public.coin_orders set provider_preference_id=p_preference_id,updated_at=now() where id=p_order_id and user_id=auth.uid() and status='pending' returning * into o; if o.id is null then raise exception 'Pedido não encontrado'; end if; return o; end $$;
revoke all on function public.set_coin_order_preference(uuid,text) from public; grant execute on function public.set_coin_order_preference(uuid,text) to authenticated;

-- 9. Administração de vendas/contas
create or replace function public.admin_list_coin_orders(p_limit integer default 100) returns table(id uuid,username text,email text,coins bigint,amount_cents integer,status text,provider_payment_id text,created_at timestamptz,paid_at timestamptz) language plpgsql security definer set search_path=public,auth as $$
begin if not exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin') then raise exception 'Acesso negado'; end if; return query select o.id,p.username,u.email,o.coins,o.amount_cents,o.status,o.provider_payment_id,o.created_at,o.paid_at from public.coin_orders o join public.profiles p on p.id=o.user_id join auth.users u on u.id=o.user_id order by o.created_at desc limit greatest(1,least(coalesce(p_limit,100),500)); end $$;
revoke all on function public.admin_list_coin_orders(integer) from public; grant execute on function public.admin_list_coin_orders(integer) to authenticated;
create or replace function public.admin_list_accounts() returns table(id uuid,username text,display_name text,email text,role text,created_at timestamptz) language plpgsql security definer set search_path=public,auth as $$ begin if not exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin') then raise exception 'Acesso negado'; end if; return query select p.id,p.username,p.display_name,u.email,p.role,u.created_at from public.profiles p join auth.users u on u.id=p.id order by u.created_at desc; end $$;
grant execute on function public.admin_list_accounts() to authenticated;
create or replace function public.admin_set_player_title(p_user_id uuid,p_title text) returns public.profiles language plpgsql security definer set search_path=public as $$ declare p public.profiles; begin if not exists(select 1 from public.profiles a where a.id=auth.uid() and a.role='admin') then raise exception 'Acesso negado'; end if; update public.profiles set premium_title=nullif(trim(p_title),'') where id=p_user_id returning * into p; if p.id is null then raise exception 'Jogador não encontrado'; end if; return p; end $$;
grant execute on function public.admin_set_player_title(uuid,text) to authenticated;

-- 10. Índices úteis
create index if not exists coin_orders_external_ref_idx on public.coin_orders(external_reference);


-- 11. MERCADO PAGO DESATIVADO POR PADRÃO (estrutura permanece pronta)
update public.premium_store_settings set payments_enabled=false where id=1;

-- 12. Coins: crédito manual seguro pelo administrador
create or replace function public.admin_grant_coins(p_username text,p_amount bigint,p_reason text default 'Crédito manual do administrador')
returns jsonb language plpgsql security definer set search_path=public as $$
declare target public.profiles; bal bigint; src text;
begin
  if not exists(select 1 from public.profiles where id=auth.uid() and role='admin') then raise exception 'Acesso negado'; end if;
  if p_amount is null or p_amount <= 0 then raise exception 'Quantidade de Coins inválida'; end if;
  select * into target from public.profiles where lower(username)=lower(trim(p_username)) limit 1;
  if target.id is null then raise exception 'Jogador não encontrado'; end if;
  src:='admin_grant_'||gen_random_uuid()::text;
  update public.profiles set coins=coalesce(coins,0)+p_amount where id=target.id returning coins into bal;
  insert into public.coin_ledger(user_id,amount,source_type,source_id,description)
    values(target.id,p_amount,'admin_grant',src,coalesce(nullif(trim(p_reason),''),'Crédito manual do administrador'));
  return jsonb_build_object('ok',true,'user_id',target.id,'username',target.username,'coins',p_amount,'balance',bal);
end $$;
revoke all on function public.admin_grant_coins(text,bigint,text) from public;
grant execute on function public.admin_grant_coins(text,bigint,text) to authenticated;

-- 13. Suporte / conversa com a equipe
create table if not exists public.support_threads(
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  status text not null default 'open' check(status in ('open','closed')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index if not exists support_threads_one_per_user on public.support_threads(user_id);
create index if not exists support_threads_updated_idx on public.support_threads(updated_at desc);

create table if not exists public.support_messages(
  id uuid primary key default gen_random_uuid(),
  thread_id uuid not null references public.support_threads(id) on delete cascade,
  sender_id uuid not null references public.profiles(id) on delete cascade,
  message text not null check(length(trim(message)) between 1 and 1000),
  created_at timestamptz not null default now()
);
create index if not exists support_messages_thread_idx on public.support_messages(thread_id,created_at);

alter table public.support_threads enable row level security;
alter table public.support_messages enable row level security;

drop policy if exists "support threads own read" on public.support_threads;
DROP POLICY IF EXISTS "support threads own read" ON public.support_threads;
create policy "support threads own read" on public.support_threads for select to authenticated
using(user_id=auth.uid() or exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin'));
drop policy if exists "support threads own insert" on public.support_threads;
DROP POLICY IF EXISTS "support threads own insert" ON public.support_threads;
create policy "support threads own insert" on public.support_threads for insert to authenticated
with check(user_id=auth.uid());
drop policy if exists "support threads admin update" on public.support_threads;
DROP POLICY IF EXISTS "support threads admin update" ON public.support_threads;
create policy "support threads admin update" on public.support_threads for update to authenticated
using(exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin'))
with check(exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin'));

drop policy if exists "support messages participants read" on public.support_messages;
DROP POLICY IF EXISTS "support messages participants read" ON public.support_messages;
create policy "support messages participants read" on public.support_messages for select to authenticated
using(
  exists(select 1 from public.support_threads t where t.id=thread_id and
    (t.user_id=auth.uid() or exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin')))
);
drop policy if exists "support messages participant insert" on public.support_messages;
DROP POLICY IF EXISTS "support messages participant insert" ON public.support_messages;
create policy "support messages participant insert" on public.support_messages for insert to authenticated
with check(
  sender_id=auth.uid() and
  exists(select 1 from public.support_threads t where t.id=thread_id and
    (t.user_id=auth.uid() or exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin')))
);

-- 14. Sessão única por conta: o último aparelho conectado derruba o anterior
create table if not exists public.quizup_active_sessions(
  user_id uuid primary key references public.profiles(id) on delete cascade,
  session_id text not null,
  last_seen_at timestamptz not null default now()
);
create index if not exists quizup_active_sessions_seen_idx on public.quizup_active_sessions(last_seen_at);

alter table public.quizup_active_sessions enable row level security;
drop policy if exists "quizup sessions own read" on public.quizup_active_sessions;
DROP POLICY IF EXISTS "quizup sessions own read" ON public.quizup_active_sessions;
create policy "quizup sessions own read" on public.quizup_active_sessions for select to authenticated using(user_id=auth.uid());

create or replace function public.claim_quizup_session(p_session_id text)
returns boolean language plpgsql security definer set search_path=public as $$
begin
  if auth.uid() is null or nullif(trim(p_session_id),'') is null then return false; end if;
  insert into public.quizup_active_sessions(user_id,session_id,last_seen_at)
    values(auth.uid(),trim(p_session_id),now())
  on conflict(user_id) do update set session_id=excluded.session_id,last_seen_at=now();
  return true;
end $$;
create or replace function public.touch_quizup_session(p_session_id text)
returns boolean language sql security definer set search_path=public as $$
  update public.quizup_active_sessions
    set last_seen_at=now()
  where user_id=auth.uid() and session_id=trim(p_session_id)
  returning true;
$$;
create or replace function public.release_quizup_session(p_session_id text)
returns boolean language sql security definer set search_path=public as $$
  delete from public.quizup_active_sessions where user_id=auth.uid() and session_id=trim(p_session_id)
  returning true;
$$;
revoke all on function public.claim_quizup_session(text) from public;
revoke all on function public.touch_quizup_session(text) from public;
revoke all on function public.release_quizup_session(text) from public;
grant execute on function public.claim_quizup_session(text) to authenticated;
grant execute on function public.touch_quizup_session(text) to authenticated;
grant execute on function public.release_quizup_session(text) to authenticated;

-- 15. Reações: índice e proteção contra spam/duplicação
create index if not exists match_reactions_match_created_idx on public.match_reactions(match_id,created_at desc);

-- 16. Compra de cosméticos usando QuizCoins (sem Mercado Pago)
create or replace function public.purchase_premium_item(p_item_id text,p_expected_price bigint default null)
returns jsonb language plpgsql security definer set search_path=public as $$
declare
  it public.premium_items;
  own boolean;
  charge bigint;
  bal bigint;
  promo_ok boolean;
  src text;
begin
  if auth.uid() is null then raise exception 'Não autenticado'; end if;
  select * into it from public.premium_items where id=p_item_id and active=true limit 1;
  if it.id is null then raise exception 'Item não encontrado ou indisponível'; end if;
  if exists(select 1 from public.premium_store_settings where id=1 and (enabled=false or cosmetics_enabled=false)) then
    raise exception 'A loja de cosméticos está desativada';
  end if;
  promo_ok:=coalesce(it.promo_active,false) and coalesce(it.promo_price_coins,0)>0 and coalesce(it.promo_price_coins,0)<coalesce(it.price_coins,0)
    and (it.promo_expires_at is null or it.promo_expires_at>now());
  charge:=case when promo_ok then it.promo_price_coins else it.price_coins end;
  if charge is null or charge<0 then raise exception 'Preço do item inválido'; end if;
  if p_expected_price is not null and p_expected_price<>charge then raise exception 'O preço do item mudou. Atualize a loja e tente novamente.'; end if;
  select exists(select 1 from public.user_premium_items up where up.user_id=auth.uid() and up.item_id=it.id) into own;
  if own then
    select coins into bal from public.profiles where id=auth.uid();
    return jsonb_build_object('ok',true,'already_owned',true,'balance',coalesce(bal,0),'charge',0);
  end if;
  update public.profiles set coins=coalesce(coins,0)-charge where id=auth.uid() and coalesce(coins,0)>=charge returning coins into bal;
  if bal is null then raise exception 'Você não possui QuizCoins suficientes'; end if;
  insert into public.user_premium_items(user_id,item_id,active,purchased_at) values(auth.uid(),it.id,true,now());
  src:='premium_purchase_'||gen_random_uuid()::text;
  insert into public.coin_ledger(user_id,amount,source_type,source_id,description) values(auth.uid(),-charge,'premium_purchase',src,'Compra: '||it.name);
  return jsonb_build_object('ok',true,'already_owned',false,'balance',bal,'charge',charge,'item_id',it.id);
exception when unique_violation then
  select coins into bal from public.profiles where id=auth.uid();
  return jsonb_build_object('ok',true,'already_owned',true,'balance',coalesce(bal,0),'charge',0);
end $$;
revoke all on function public.purchase_premium_item(text,bigint) from public;
grant execute on function public.purchase_premium_item(text,bigint) to authenticated;

-- 17. Reações da partida: os dois participantes podem ler/enviar
alter table public.match_reactions enable row level security;
drop policy if exists "match reactions participants read" on public.match_reactions;
DROP POLICY IF EXISTS "match reactions participants read" ON public.match_reactions;
create policy "match reactions participants read" on public.match_reactions for select to authenticated using(
  exists(select 1 from public.matches m where m.id=match_id and auth.uid()=any(m.player_ids))
);
drop policy if exists "match reactions participants insert" on public.match_reactions;
DROP POLICY IF EXISTS "match reactions participants insert" ON public.match_reactions;
create policy "match reactions participants insert" on public.match_reactions for insert to authenticated with check(
  sender_id=auth.uid() and exists(select 1 from public.matches m where m.id=match_id and auth.uid()=any(m.player_ids))
);

-- 18. Feed social do QuizUp
create table if not exists public.social_posts(
  id uuid primary key default gen_random_uuid(), user_id uuid not null references public.profiles(id) on delete cascade,
  caption text, media_url text, post_type text not null default 'text' check(post_type in ('text','image')),
  category_name text, status text not null default 'published' check(status in ('published','hidden','deleted')),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists public.social_likes(
  post_id uuid not null references public.social_posts(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(), primary key(post_id,user_id)
);
create table if not exists public.social_comments(
  id uuid primary key default gen_random_uuid(), post_id uuid not null references public.social_posts(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade, body text not null check(length(trim(body)) between 1 and 500),
  created_at timestamptz not null default now()
);
create index if not exists social_posts_feed_idx on public.social_posts(status,created_at desc);
create index if not exists social_posts_category_idx on public.social_posts(category_name,created_at desc);
create index if not exists social_comments_post_idx on public.social_comments(post_id,created_at);
alter table public.social_posts enable row level security;
alter table public.social_likes enable row level security;
alter table public.social_comments enable row level security;
drop policy if exists "social posts read published" on public.social_posts;
DROP POLICY IF EXISTS "social posts read published" ON public.social_posts;
create policy "social posts read published" on public.social_posts for select to authenticated using(status='published' or user_id=auth.uid() or exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin'));
drop policy if exists "social posts own insert" on public.social_posts;
DROP POLICY IF EXISTS "social posts own insert" ON public.social_posts;
create policy "social posts own insert" on public.social_posts for insert to authenticated with check(user_id=auth.uid());
drop policy if exists "social posts own update" on public.social_posts;
DROP POLICY IF EXISTS "social posts own update" ON public.social_posts;
create policy "social posts own update" on public.social_posts for update to authenticated using(user_id=auth.uid() or exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin')) with check(user_id=auth.uid() or exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin'));
drop policy if exists "social posts own delete" on public.social_posts;
DROP POLICY IF EXISTS "social posts own delete" ON public.social_posts;
create policy "social posts own delete" on public.social_posts for delete to authenticated using(user_id=auth.uid() or exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin'));
drop policy if exists "social likes read" on public.social_likes;
DROP POLICY IF EXISTS "social likes read" ON public.social_likes;
create policy "social likes read" on public.social_likes for select to authenticated using(true);
drop policy if exists "social likes own insert" on public.social_likes;
DROP POLICY IF EXISTS "social likes own insert" ON public.social_likes;
create policy "social likes own insert" on public.social_likes for insert to authenticated with check(user_id=auth.uid());
drop policy if exists "social likes own delete" on public.social_likes;
DROP POLICY IF EXISTS "social likes own delete" ON public.social_likes;
create policy "social likes own delete" on public.social_likes for delete to authenticated using(user_id=auth.uid());
drop policy if exists "social comments read" on public.social_comments;
DROP POLICY IF EXISTS "social comments read" ON public.social_comments;
create policy "social comments read" on public.social_comments for select to authenticated using(true);
drop policy if exists "social comments own insert" on public.social_comments;
DROP POLICY IF EXISTS "social comments own insert" ON public.social_comments;
create policy "social comments own insert" on public.social_comments for insert to authenticated with check(user_id=auth.uid());
drop policy if exists "social comments own delete" on public.social_comments;
DROP POLICY IF EXISTS "social comments own delete" ON public.social_comments;
create policy "social comments own delete" on public.social_comments for delete to authenticated using(user_id=auth.uid() or exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin'));

-- Bucket público para fotos/prints do feed. O bucket é público para exibição, mas upload/delete continuam protegidos por RLS.
insert into storage.buckets(id,name,public) values('social-posts','social-posts',true) on conflict(id) do update set public=true;
drop policy if exists "social post media upload" on storage.objects;
DROP POLICY IF EXISTS "social post media upload" ON storage.objects;
create policy "social post media upload" on storage.objects for insert to authenticated with check(bucket_id='social-posts' and (storage.foldername(name))[1]=auth.uid()::text);
drop policy if exists "social post media update" on storage.objects;
DROP POLICY IF EXISTS "social post media update" ON storage.objects;
create policy "social post media update" on storage.objects for update to authenticated using(bucket_id='social-posts' and (storage.foldername(name))[1]=auth.uid()::text);
drop policy if exists "social post media delete" on storage.objects;
DROP POLICY IF EXISTS "social post media delete" ON storage.objects;
create policy "social post media delete" on storage.objects for delete to authenticated using(bucket_id='social-posts' and ((storage.foldername(name))[1]=auth.uid()::text or exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin')));

-- 19. Realtime do feed social
alter table public.social_posts replica identity full;
alter table public.social_likes replica identity full;
alter table public.social_comments replica identity full;

-- Compatibilidade: alguns bancos antigos expõem o id do item como integer.
create or replace function public.purchase_premium_item(p_item_id integer)
returns jsonb language sql security definer set search_path=public as $$
  select public.purchase_premium_item(p_item_id::text,null::bigint);
$$;
revoke all on function public.purchase_premium_item(integer) from public;
grant execute on function public.purchase_premium_item(integer) to authenticated;

-- ================================================================
-- QuizUp v37 - Comunidade, notificações, segurança e conquistas
-- ================================================================

-- 20. Notificações persistentes
create table if not exists public.notifications(
  id uuid primary key default gen_random_uuid(),
  recipient_id uuid not null references public.profiles(id) on delete cascade,
  actor_id uuid references public.profiles(id) on delete set null,
  type text not null,
  title text not null,
  body text,
  data jsonb not null default '{}'::jsonb,
  read_at timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists notifications_recipient_idx on public.notifications(recipient_id,created_at desc);
alter table public.notifications enable row level security;
drop policy if exists "notifications own read" on public.notifications;
DROP POLICY IF EXISTS "notifications own read" ON public.notifications;
create policy "notifications own read" on public.notifications for select to authenticated using(recipient_id=auth.uid());
drop policy if exists "notifications own update" on public.notifications;
DROP POLICY IF EXISTS "notifications own update" ON public.notifications;
create policy "notifications own update" on public.notifications for update to authenticated using(recipient_id=auth.uid()) with check(recipient_id=auth.uid());
alter table public.notifications replica identity full;

-- 21. Bloqueio, silenciamento e denúncias
create table if not exists public.user_blocks(
  blocker_id uuid not null references public.profiles(id) on delete cascade,
  blocked_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key(blocker_id,blocked_id),
  check(blocker_id<>blocked_id)
);
create table if not exists public.user_mutes(
  muter_id uuid not null references public.profiles(id) on delete cascade,
  muted_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key(muter_id,muted_id),
  check(muter_id<>muted_id)
);
create table if not exists public.social_reports(
  id uuid primary key default gen_random_uuid(),
  post_id uuid references public.social_posts(id) on delete cascade,
  comment_id uuid references public.social_comments(id) on delete cascade,
  reporter_id uuid not null references public.profiles(id) on delete cascade,
  reason text not null check(length(trim(reason)) between 3 and 500),
  status text not null default 'open' check(status in ('open','reviewing','resolved','dismissed')),
  created_at timestamptz not null default now(),
  resolved_at timestamptz,
  resolved_by uuid references public.profiles(id) on delete set null,
  check(post_id is not null or comment_id is not null)
);
create index if not exists social_reports_status_idx on public.social_reports(status,created_at desc);

alter table public.user_blocks enable row level security;
alter table public.user_mutes enable row level security;
alter table public.social_reports enable row level security;
drop policy if exists "blocks own read" on public.user_blocks;
DROP POLICY IF EXISTS "blocks own read" ON public.user_blocks;
create policy "blocks own read" on public.user_blocks for select to authenticated using(blocker_id=auth.uid());
drop policy if exists "blocks own insert" on public.user_blocks;
DROP POLICY IF EXISTS "blocks own insert" ON public.user_blocks;
create policy "blocks own insert" on public.user_blocks for insert to authenticated with check(blocker_id=auth.uid());
drop policy if exists "blocks own delete" on public.user_blocks;
DROP POLICY IF EXISTS "blocks own delete" ON public.user_blocks;
create policy "blocks own delete" on public.user_blocks for delete to authenticated using(blocker_id=auth.uid());
drop policy if exists "mutes own read" on public.user_mutes;
DROP POLICY IF EXISTS "mutes own read" ON public.user_mutes;
create policy "mutes own read" on public.user_mutes for select to authenticated using(muter_id=auth.uid());
drop policy if exists "mutes own insert" on public.user_mutes;
DROP POLICY IF EXISTS "mutes own insert" ON public.user_mutes;
create policy "mutes own insert" on public.user_mutes for insert to authenticated with check(muter_id=auth.uid());
drop policy if exists "mutes own delete" on public.user_mutes;
DROP POLICY IF EXISTS "mutes own delete" ON public.user_mutes;
create policy "mutes own delete" on public.user_mutes for delete to authenticated using(muter_id=auth.uid());
drop policy if exists "reports own insert" on public.social_reports;
DROP POLICY IF EXISTS "reports own insert" ON public.social_reports;
create policy "reports own insert" on public.social_reports for insert to authenticated with check(reporter_id=auth.uid());
drop policy if exists "reports own read" on public.social_reports;
DROP POLICY IF EXISTS "reports own read" ON public.social_reports;
create policy "reports own read" on public.social_reports for select to authenticated using(reporter_id=auth.uid() or exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin'));
drop policy if exists "reports admin update" on public.social_reports;
DROP POLICY IF EXISTS "reports admin update" ON public.social_reports;
create policy "reports admin update" on public.social_reports for update to authenticated using(exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin')) with check(exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin'));

-- 22. Presença simples (online/offline) sem polling pesado
create table if not exists public.quizup_presence(
  user_id uuid primary key references public.profiles(id) on delete cascade,
  last_seen_at timestamptz not null default now()
);
create index if not exists quizup_presence_seen_idx on public.quizup_presence(last_seen_at desc);
alter table public.quizup_presence enable row level security;
drop policy if exists "presence authenticated read" on public.quizup_presence;
DROP POLICY IF EXISTS "presence authenticated read" ON public.quizup_presence;
create policy "presence authenticated read" on public.quizup_presence for select to authenticated using(true);
drop policy if exists "presence own write" on public.quizup_presence;
DROP POLICY IF EXISTS "presence own write" ON public.quizup_presence;
create policy "presence own write" on public.quizup_presence for insert to authenticated with check(user_id=auth.uid());
drop policy if exists "presence own update" on public.quizup_presence;
DROP POLICY IF EXISTS "presence own update" ON public.quizup_presence;
create policy "presence own update" on public.quizup_presence for update to authenticated using(user_id=auth.uid()) with check(user_id=auth.uid());

-- 23. Conquistas desbloqueáveis
alter table public.achievements add column if not exists code text;
alter table public.achievements add column if not exists criteria_type text;
alter table public.achievements add column if not exists threshold bigint default 1;
create unique index if not exists achievements_code_uidx on public.achievements(code) where code is not null;
create table if not exists public.user_achievements(
  user_id uuid not null references public.profiles(id) on delete cascade,
  achievement_id uuid not null references public.achievements(id) on delete cascade,
  unlocked_at timestamptz not null default now(),
  primary key(user_id,achievement_id)
);
create index if not exists user_achievements_user_idx on public.user_achievements(user_id,unlocked_at desc);
alter table public.user_achievements enable row level security;
drop policy if exists "user achievements own read" on public.user_achievements;
DROP POLICY IF EXISTS "user achievements own read" ON public.user_achievements;
create policy "user achievements own read" on public.user_achievements for select to authenticated using(user_id=auth.uid());
drop policy if exists "user achievements public read" on public.user_achievements;
DROP POLICY IF EXISTS "user achievements public read" ON public.user_achievements;
create policy "user achievements public read" on public.user_achievements for select to authenticated using(true);

insert into public.achievements(title,description,icon,active,code,criteria_type,threshold)
select v.title,v.description,v.icon,true,v.code,v.criteria_type,v.threshold
from (values
 ('Primeira partida','Jogue sua primeira partida no QuizUp.','🎮','first_game','first_game',1),
 ('Primeira vitória','Vença sua primeira partida.','🥇','wins','wins',1),
 ('Veterano','Complete 10 partidas.','🎯','games','games',10),
 ('Campeão','Consiga 10 vitórias.','🏆','wins_10','wins',10),
 ('Sequência de fogo','Alcance uma sequência de 5 vitórias.','🔥','streak','streak',5),
 ('Milionário de Coins','Acumule 1.000 QuizCoins.','⚡','coins_1000','coins',1000)
) v(title,description,icon,code,criteria_type,threshold)
where not exists(select 1 from public.achievements a where a.code=v.code);

create or replace function public.quizup_check_achievements(p_user_id uuid)
returns void language plpgsql security definer set search_path=public as $$
declare a record; value bigint; already boolean;
begin
  for a in select id,code,criteria_type,threshold,title from public.achievements where active=true and code is not null loop
    value:=0;
    if a.criteria_type='games' or a.criteria_type='first_game' then
      select count(*) into value from public.game_results where user_id=p_user_id;
    elsif a.criteria_type='wins' then
      select count(*) into value from public.game_results where user_id=p_user_id and won=true;
    elsif a.criteria_type='streak' then
      select coalesce(streak,0) into value from public.profiles where id=p_user_id;
    elsif a.criteria_type='coins' then
      select coalesce(coins,0) into value from public.profiles where id=p_user_id;
    end if;
    if value>=coalesce(a.threshold,1) then
      insert into public.user_achievements(user_id,achievement_id) values(p_user_id,a.id) on conflict do nothing;
    end if;
  end loop;
end $$;
revoke all on function public.quizup_check_achievements(uuid) from public;
grant execute on function public.quizup_check_achievements(uuid) to authenticated;

create or replace function public.quizup_notify_achievement()
returns trigger language plpgsql security definer set search_path=public as $$
declare a record;
begin
  select title,description,icon into a from public.achievements where id=new.achievement_id;
  insert into public.notifications(recipient_id,actor_id,type,title,body,data)
  values(new.user_id,null,'achievement',coalesce(a.icon,'🏆')||' Conquista desbloqueada',coalesce(a.description,a.title),jsonb_build_object('achievement_id',new.achievement_id));
  return new;
end $$;
drop trigger if exists trg_quizup_notify_achievement on public.user_achievements;
DROP TRIGGER IF EXISTS trg_quizup_notify_achievement ON public.user_achievements;
create trigger trg_quizup_notify_achievement after insert on public.user_achievements for each row execute function public.quizup_notify_achievement();

create or replace function public.quizup_game_result_achievements()
returns trigger language plpgsql security definer set search_path=public as $$
begin perform public.quizup_check_achievements(new.user_id); return new; end $$;
drop trigger if exists trg_quizup_game_result_achievements on public.game_results;
DROP TRIGGER IF EXISTS trg_quizup_game_result_achievements ON public.game_results;
create trigger trg_quizup_game_result_achievements after insert on public.game_results for each row execute function public.quizup_game_result_achievements();

-- 24. Publicação automática do resultado da partida
create or replace function public.quizup_publish_game_result()
returns trigger language plpgsql security definer set search_path=public as $$
declare u public.profiles; caption text; post_id uuid;
begin
  select * into u from public.profiles where id=new.user_id;
  caption:='🎮 Resultado da partida • '||coalesce(new.category,'Geral')||' • '||coalesce(new.score,0)||' pontos • '||case when new.won then 'Vitória 🏆' else coalesce(new.outcome,'Partida') end;
  if not exists(select 1 from public.social_posts where user_id=new.user_id and coalesce(data->>'game_result_id','')=new.id::text) then
    insert into public.social_posts(user_id,caption,post_type,category_name,status,data)
    values(new.user_id,caption,'text',new.category,'published',jsonb_build_object('game_result_id',new.id::text,'auto',true)) returning id into post_id;
  end if;
  return new;
end $$;
-- Add a JSON column only if this older schema doesn't have it.
alter table public.social_posts add column if not exists data jsonb not null default '{}'::jsonb;
drop trigger if exists trg_quizup_publish_game_result on public.game_results;
DROP TRIGGER IF EXISTS trg_quizup_publish_game_result ON public.game_results;
create trigger trg_quizup_publish_game_result after insert on public.game_results for each row execute function public.quizup_publish_game_result();

-- 25. Notificações de comunidade
create or replace function public.quizup_notify_friend_request()
returns trigger language plpgsql security definer set search_path=public as $$
declare u public.profiles;
begin
  if new.status='pending' then
    select * into u from public.profiles where id=new.requester_id;
    insert into public.notifications(recipient_id,actor_id,type,title,body,data)
    values(new.addressee_id,new.requester_id,'friend_request','♧ Nova solicitação de amizade',coalesce(u.username,'Alguém')||' quer ser seu amigo.',jsonb_build_object('friendship_id',new.id));
  end if;
  return new;
end $$;
drop trigger if exists trg_quizup_notify_friend_request on public.friendships;
DROP TRIGGER IF EXISTS trg_quizup_notify_friend_request ON public.friendships;
create trigger trg_quizup_notify_friend_request after insert on public.friendships for each row execute function public.quizup_notify_friend_request();

create or replace function public.quizup_notify_challenge()
returns trigger language plpgsql security definer set search_path=public as $$
declare u public.profiles;
begin
  if new.status='pending' then
    select * into u from public.profiles where id=new.challenger_id;
    insert into public.notifications(recipient_id,actor_id,type,title,body,data)
    values(new.challenged_id,new.challenger_id,'challenge','⚔️ Novo desafio',coalesce(u.username,'Alguém')||' te desafiou em '||coalesce(new.category,'Geral')||'.',jsonb_build_object('challenge_id',new.id));
  end if;
  return new;
end $$;
drop trigger if exists trg_quizup_notify_challenge on public.challenges;
DROP TRIGGER IF EXISTS trg_quizup_notify_challenge ON public.challenges;
create trigger trg_quizup_notify_challenge after insert on public.challenges for each row execute function public.quizup_notify_challenge();

create or replace function public.quizup_notify_message()
returns trigger language plpgsql security definer set search_path=public as $$
declare u public.profiles;
begin
  select * into u from public.profiles where id=new.sender_id;
  insert into public.notifications(recipient_id,actor_id,type,title,body,data)
  values(new.receiver_id,new.sender_id,'message','💬 Nova mensagem',coalesce(u.username,'Alguém')||' enviou uma mensagem.',jsonb_build_object('message_id',new.id));
  return new;
end $$;
drop trigger if exists trg_quizup_notify_message on public.direct_messages;
DROP TRIGGER IF EXISTS trg_quizup_notify_message ON public.direct_messages;
create trigger trg_quizup_notify_message after insert on public.direct_messages for each row execute function public.quizup_notify_message();

create or replace function public.quizup_notify_social()
returns trigger language plpgsql security definer set search_path=public as $$
declare owner_id uuid; u public.profiles; label text; typ text; payload jsonb;
begin
  if TG_TABLE_NAME='social_likes' then
    select user_id into owner_id from public.social_posts where id=new.post_id;
    if owner_id is null or owner_id=new.user_id then return new; end if;
    select * into u from public.profiles where id=new.user_id;
    typ:='like'; label:='❤️'||' Nova curtida'; payload:=jsonb_build_object('post_id',new.post_id);
  else
    select user_id into owner_id from public.social_posts where id=new.post_id;
    if owner_id is null or owner_id=new.user_id then return new; end if;
    select * into u from public.profiles where id=new.user_id;
    typ:='comment'; label:='💬 Novo comentário'; payload:=jsonb_build_object('post_id',new.post_id,'comment_id',new.id);
  end if;
  insert into public.notifications(recipient_id,actor_id,type,title,body,data)
  values(owner_id,new.user_id,typ,label,coalesce(u.username,'Alguém')||' interagiu com sua publicação.',payload);
  return new;
end $$;
drop trigger if exists trg_quizup_notify_social_like on public.social_likes;
DROP TRIGGER IF EXISTS trg_quizup_notify_social_like ON public.social_likes;
create trigger trg_quizup_notify_social_like after insert on public.social_likes for each row execute function public.quizup_notify_social();
drop trigger if exists trg_quizup_notify_social_comment on public.social_comments;
DROP TRIGGER IF EXISTS trg_quizup_notify_social_comment ON public.social_comments;
create trigger trg_quizup_notify_social_comment after insert on public.social_comments for each row execute function public.quizup_notify_social();

-- 26. Segurança contra interações após bloqueio
create or replace function public.quizup_blocked_interaction_guard()
returns trigger language plpgsql security definer set search_path=public as $$
declare other_id uuid;
begin
  if TG_TABLE_NAME='direct_messages' then other_id:=new.receiver_id;
  elsif TG_TABLE_NAME='social_likes' then select user_id into other_id from public.social_posts where id=new.post_id;
  else select user_id into other_id from public.social_posts where id=new.post_id; end if;
  if other_id is not null and (exists(select 1 from public.user_blocks where blocker_id=auth.uid() and blocked_id=other_id) or exists(select 1 from public.user_blocks where blocker_id=other_id and blocked_id=auth.uid())) then
    raise exception 'Interação bloqueada entre estes jogadores';
  end if;
  return new;
end $$;
drop trigger if exists trg_quizup_block_dm on public.direct_messages;
DROP TRIGGER IF EXISTS trg_quizup_block_dm ON public.direct_messages;
create trigger trg_quizup_block_dm before insert on public.direct_messages for each row execute function public.quizup_blocked_interaction_guard();
drop trigger if exists trg_quizup_block_like on public.social_likes;
DROP TRIGGER IF EXISTS trg_quizup_block_like ON public.social_likes;
create trigger trg_quizup_block_like before insert on public.social_likes for each row execute function public.quizup_blocked_interaction_guard();
drop trigger if exists trg_quizup_block_comment on public.social_comments;
DROP TRIGGER IF EXISTS trg_quizup_block_comment ON public.social_comments;
create trigger trg_quizup_block_comment before insert on public.social_comments for each row execute function public.quizup_blocked_interaction_guard();

-- Realtime das notificações.
alter table public.notifications replica identity full;

-- Mercado Pago permanece desligado no v37.
update public.premium_store_settings set payments_enabled=false where id=1;

-- 27. Garante que as notificações sejam entregues em tempo real pelo Realtime.
do $$
begin
  begin alter publication supabase_realtime add table public.notifications; exception when duplicate_object then null; end;
  begin alter publication supabase_realtime add table public.social_posts; exception when duplicate_object then null; end;
  begin alter publication supabase_realtime add table public.social_likes; exception when duplicate_object then null; end;
  begin alter publication supabase_realtime add table public.social_comments; exception when duplicate_object then null; end;
exception when undefined_object then null;
end $$;

-- 28. Notificação de amizade aceita e recebimento de Coins.
create or replace function public.quizup_notify_friend_accept()
returns trigger language plpgsql security definer set search_path=public as $$
declare u public.profiles;
begin
  if old.status is distinct from 'accepted' and new.status='accepted' then
    select * into u from public.profiles where id=new.addressee_id;
    insert into public.notifications(recipient_id,actor_id,type,title,body,data)
    values(new.requester_id,new.addressee_id,'friend_request','🤝 Solicitação aceita',coalesce(u.username,'Seu amigo')||' aceitou sua solicitação de amizade.',jsonb_build_object('friendship_id',new.id));
  end if;
  return new;
end $$;
drop trigger if exists trg_quizup_notify_friend_accept on public.friendships;
DROP TRIGGER IF EXISTS trg_quizup_notify_friend_accept ON public.friendships;
create trigger trg_quizup_notify_friend_accept after update of status on public.friendships for each row execute function public.quizup_notify_friend_accept();

create or replace function public.quizup_notify_coin_credit()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  if new.amount>0 and new.source_type in ('admin_grant','match_reward','mercadopago_payment') then
    insert into public.notifications(recipient_id,actor_id,type,title,body,data)
    values(new.user_id,null,'coin','⚡ QuizCoins recebidas','Você recebeu +'||new.amount||' QuizCoins.',jsonb_build_object('ledger_id',new.id,'amount',new.amount,'source',new.source_type));
  end if;
  return new;
end $$;
drop trigger if exists trg_quizup_notify_coin_credit on public.coin_ledger;
DROP TRIGGER IF EXISTS trg_quizup_notify_coin_credit ON public.coin_ledger;
create trigger trg_quizup_notify_coin_credit after insert on public.coin_ledger for each row execute function public.quizup_notify_coin_credit();


-- ================================================================
-- INÍCIO: quizup_v37_FIX_42P10_ACHIEVEMENTS.sql
-- ================================================================
-- QuizUp v37 - correção do erro PostgreSQL 42P10 na carga inicial de conquistas.
-- Se a migration v37 falhou exatamente em "table \"v\" has 5 columns available but 6 columns specified",
-- execute a migration v37 corrigida do ZIP. Este arquivo é apenas uma correção segura caso as colunas/tabelas já existam.

alter table public.achievements add column if not exists code text;
alter table public.achievements add column if not exists criteria_type text;
alter table public.achievements add column if not exists threshold bigint default 1;

insert into public.achievements(title,description,icon,active,code,criteria_type,threshold)
select v.title,v.description,v.icon,true,v.code,v.criteria_type,v.threshold
from (values
 ('Primeira partida','Jogue sua primeira partida no QuizUp.','🎮','first_game','first_game',1),
 ('Primeira vitória','Vença sua primeira partida.','🥇','wins','wins',1),
 ('Veterano','Complete 10 partidas.','🎯','games','games',10),
 ('Campeão','Consiga 10 vitórias.','🏆','wins_10','wins',10),
 ('Sequência de fogo','Alcance uma sequência de 5 vitórias.','🔥','streak','streak',5),
 ('Milionário de Coins','Acumule 1.000 QuizCoins.','⚡','coins_1000','coins',1000)
) v(title,description,icon,code,criteria_type,threshold)
where not exists(select 1 from public.achievements a where a.code=v.code);

create unique index if not exists achievements_code_uidx on public.achievements(code) where code is not null;


-- ================================================================
-- INÍCIO: quizup_v38_MIGRATION_COMPLETA.sql
-- ================================================================
-- QuizUp v38 - Painel administrativo modular, loja reconstruída, títulos/emblemas e retomada de partida
-- Execute APÓS as migrations anteriores. É idempotente e não apaga partidas/contas.

-- ================================================================
-- 1. Corrige a compatibilidade da Loja / purchase_premium_item
-- ================================================================
alter table if exists public.premium_items add column if not exists description text;
alter table if exists public.premium_items add column if not exists price_cents bigint;
alter table if exists public.premium_items add column if not exists price_coins bigint;
alter table if exists public.premium_items add column if not exists promo_price_cents bigint;
alter table if exists public.premium_items add column if not exists promo_price_coins bigint;
alter table if exists public.premium_items add column if not exists promo_active boolean not null default false;
alter table if exists public.premium_items add column if not exists promo_expires_at timestamptz;
alter table if exists public.premium_items add column if not exists icon text;
alter table if exists public.premium_items add column if not exists asset_url text;
alter table if exists public.premium_items add column if not exists kind text;
alter table if exists public.premium_items add column if not exists active boolean not null default true;
alter table if exists public.premium_items add column if not exists created_by uuid;

update public.premium_items set price_coins=coalesce(price_coins,price_cents,0), price_cents=coalesce(price_cents,price_coins,0) where true;

-- Remove versões antigas com assinaturas diferentes. Isso evita que uma RPC antiga
-- continue sendo chamada pelo PostgREST e provoque o erro 42P10/colunas inexistentes.
do $$
declare r record;
begin
  for r in select oid::regprocedure::text as sig from pg_proc where pronamespace='public'::regnamespace and proname='purchase_premium_item' loop
    execute 'drop function if exists '||r.sig||' cascade';
  end loop;
exception when undefined_function then null;
end $$;

create or replace function public.purchase_premium_item(p_item_id text,p_expected_price bigint default null)
returns jsonb language plpgsql security definer set search_path=public as $$
declare
  it public.premium_items;
  charge bigint;
  bal bigint;
  promo_ok boolean;
begin
  if auth.uid() is null then raise exception 'Não autenticado'; end if;
  select * into it from public.premium_items where id::text=trim(p_item_id) and active=true limit 1;
  if it.id is null then raise exception 'Item não encontrado ou indisponível'; end if;
  if exists(select 1 from public.premium_store_settings where id=1 and (coalesce(enabled,false)=false or coalesce(cosmetics_enabled,false)=false)) then
    raise exception 'A loja de cosméticos está desativada';
  end if;
  promo_ok:=coalesce(it.promo_active,false)
    and coalesce(it.promo_price_coins,0)>0
    and coalesce(it.promo_price_coins,0)<coalesce(it.price_coins,0)
    and (it.promo_expires_at is null or it.promo_expires_at>now());
  charge:=case when promo_ok then it.promo_price_coins else coalesce(it.price_coins,it.price_cents,0) end;
  if charge is null or charge<0 then raise exception 'Preço do item inválido'; end if;
  if p_expected_price is not null and p_expected_price<>charge then raise exception 'O preço do item mudou. Atualize a loja e tente novamente.'; end if;
  if exists(select 1 from public.user_premium_items where user_id=auth.uid() and item_id=it.id) then
    select coins into bal from public.profiles where id=auth.uid();
    return jsonb_build_object('ok',true,'already_owned',true,'balance',coalesce(bal,0),'charge',0,'item_id',it.id);
  end if;
  update public.profiles set coins=coalesce(coins,0)-charge where id=auth.uid() and coalesce(coins,0)>=charge returning coins into bal;
  if bal is null then raise exception 'Você não possui QuizCoins suficientes'; end if;
  insert into public.user_premium_items(user_id,item_id,active,purchased_at) values(auth.uid(),it.id,true,now());
  insert into public.coin_ledger(user_id,amount,source_type,source_id,description)
    values(auth.uid(),-charge,'premium_purchase',gen_random_uuid()::text,'Compra: '||coalesce(it.name,'Item'));
  return jsonb_build_object('ok',true,'already_owned',false,'balance',bal,'charge',charge,'item_id',it.id);
end $$;
revoke all on function public.purchase_premium_item(text,bigint) from public;
grant execute on function public.purchase_premium_item(text,bigint) to authenticated;

create or replace function public.purchase_premium_item(p_item_id integer)
returns jsonb language sql security definer set search_path=public as $$
  select public.purchase_premium_item(p_item_id::text,null::bigint);
$$;
revoke all on function public.purchase_premium_item(integer) from public;
grant execute on function public.purchase_premium_item(integer) to authenticated;

-- ================================================================
-- 2. Categorias próprias da loja
-- ================================================================
create table if not exists public.store_categories(
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  description text,
  icon text not null default '🛍️',
  active boolean not null default true,
  sort_order integer not null default 0,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);
alter table public.store_categories enable row level security;
drop policy if exists "store categories read active" on public.store_categories;
DROP POLICY IF EXISTS "store categories read active" ON public.store_categories;
create policy "store categories read active" on public.store_categories for select to authenticated using(active=true or exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin'));
drop policy if exists "store categories admin insert" on public.store_categories;
DROP POLICY IF EXISTS "store categories admin insert" ON public.store_categories;
create policy "store categories admin insert" on public.store_categories for insert to authenticated with check(exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin'));
drop policy if exists "store categories admin update" on public.store_categories;
DROP POLICY IF EXISTS "store categories admin update" ON public.store_categories;
create policy "store categories admin update" on public.store_categories for update to authenticated using(exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin')) with check(exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin'));

insert into public.store_categories(name,description,icon,sort_order,created_by)
values
('Avatares','Avatares personalizados para o perfil.','🧑',1,null),
('Molduras','Bordas circulares para o avatar.','⭕',2,null),
('Efeitos','Efeitos visuais de perfil e partida.','✨',3,null),
('Títulos','Títulos visuais do jogador.','🏷️',4,null),
('Emojis','Reações e emojis especiais.','😈',5,null),
('Emblemas','Emblemas colecionáveis.','🏅',6,null),
('Temas','Temas visuais do perfil.','🎨',7,null)
on conflict(name) do nothing;

-- ================================================================
-- 3. Títulos conquistáveis
-- ================================================================
create table if not exists public.titles(
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  description text,
  icon text not null default '🏷️',
  active boolean not null default true,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);
create table if not exists public.user_titles(
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  title_id uuid not null references public.titles(id) on delete cascade,
  is_main boolean not null default false,
  acquired_at timestamptz not null default now(),
  unique(user_id,title_id)
);
alter table public.profiles add column if not exists main_title_id uuid references public.titles(id) on delete set null;
alter table public.achievements add column if not exists title_id uuid references public.titles(id) on delete set null;

alter table public.titles enable row level security;
alter table public.user_titles enable row level security;
drop policy if exists "titles read active" on public.titles;
DROP POLICY IF EXISTS "titles read active" ON public.titles;
create policy "titles read active" on public.titles for select to authenticated using(active=true or exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin'));
drop policy if exists "titles admin insert" on public.titles;
DROP POLICY IF EXISTS "titles admin insert" ON public.titles;
create policy "titles admin insert" on public.titles for insert to authenticated with check(exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin'));
drop policy if exists "titles admin update" on public.titles;
DROP POLICY IF EXISTS "titles admin update" ON public.titles;
create policy "titles admin update" on public.titles for update to authenticated using(exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin')) with check(exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin'));
drop policy if exists "user titles own read" on public.user_titles;
DROP POLICY IF EXISTS "user titles own read" ON public.user_titles;
create policy "user titles own read" on public.user_titles for select to authenticated using(user_id=auth.uid() or exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin'));
drop policy if exists "user titles own main update" on public.user_titles;
DROP POLICY IF EXISTS "user titles own main update" ON public.user_titles;
create policy "user titles own main update" on public.user_titles for update to authenticated using(user_id=auth.uid()) with check(user_id=auth.uid());
drop policy if exists "user titles admin insert" on public.user_titles;
DROP POLICY IF EXISTS "user titles admin insert" ON public.user_titles;
create policy "user titles admin insert" on public.user_titles for insert to authenticated with check(exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin'));


create or replace function public.set_main_title(p_title_id uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
begin
  if p_title_id is not null and not exists(select 1 from public.user_titles where user_id=auth.uid() and title_id=p_title_id) then
    raise exception 'Você ainda não conquistou este título';
  end if;
  update public.user_titles set is_main=false where user_id=auth.uid();
  if p_title_id is not null then update public.user_titles set is_main=true where user_id=auth.uid() and title_id=p_title_id; end if;
  update public.profiles set main_title_id=p_title_id where id=auth.uid();
  return jsonb_build_object('ok',true,'main_title_id',p_title_id);
end $$;
revoke all on function public.set_main_title(uuid) from public;
grant execute on function public.set_main_title(uuid) to authenticated;

-- Ao desbloquear uma conquista vinculada a título, entrega o título automaticamente.
create or replace function public.quizup_notify_achievement()
returns trigger language plpgsql security definer set search_path=public as $$
declare a record;
begin
  select title,description,icon,title_id into a from public.achievements where id=new.achievement_id;
  if a.title_id is not null then
    insert into public.user_titles(user_id,title_id,is_main) values(new.user_id,a.title_id,false) on conflict do nothing;
  end if;
  insert into public.notifications(recipient_id,actor_id,type,title,body,data)
  values(new.user_id,null,'achievement',coalesce(a.icon,'🏆')||' Conquista desbloqueada',coalesce(a.description,a.title),jsonb_build_object('achievement_id',new.achievement_id,'title_id',a.title_id));
  return new;
end $$;
drop trigger if exists trg_quizup_notify_achievement on public.user_achievements;
DROP TRIGGER IF EXISTS trg_quizup_notify_achievement ON public.user_achievements;
create trigger trg_quizup_notify_achievement after insert on public.user_achievements for each row execute function public.quizup_notify_achievement();

-- ================================================================
-- 4. Emblemas administráveis
-- ================================================================
create table if not exists public.badges(
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  description text,
  icon text not null default '🏅',
  active boolean not null default true,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);
alter table public.badges enable row level security;
drop policy if exists "badges read active" on public.badges;
DROP POLICY IF EXISTS "badges read active" ON public.badges;
create policy "badges read active" on public.badges for select to authenticated using(active=true or exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin'));
drop policy if exists "badges admin insert" on public.badges;
DROP POLICY IF EXISTS "badges admin insert" ON public.badges;
create policy "badges admin insert" on public.badges for insert to authenticated with check(exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin'));
drop policy if exists "badges admin update" on public.badges;
DROP POLICY IF EXISTS "badges admin update" ON public.badges;
create policy "badges admin update" on public.badges for update to authenticated using(exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin')) with check(exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin'));

-- ================================================================
-- 5. Padronização dos avatares
-- ================================================================
insert into storage.buckets(id,name,public) values('premium-assets','premium-assets',true) on conflict(id) do update set public=true;
drop policy if exists "premium assets upload admin" on storage.objects;
DROP POLICY IF EXISTS "premium assets upload admin" ON storage.objects;
create policy "premium assets upload admin" on storage.objects for insert to authenticated with check(bucket_id='premium-assets' and exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin'));
drop policy if exists "premium assets update admin" on storage.objects;
DROP POLICY IF EXISTS "premium assets update admin" ON storage.objects;
create policy "premium assets update admin" on storage.objects for update to authenticated using(bucket_id='premium-assets' and exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin'));
drop policy if exists "premium assets delete admin" on storage.objects;
DROP POLICY IF EXISTS "premium assets delete admin" ON storage.objects;
create policy "premium assets delete admin" on storage.objects for delete to authenticated using(bucket_id='premium-assets' and exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin'));

-- ================================================================
-- 6. Mercado Pago continua OFF e a loja começa apenas com cosméticos.
-- Itens antigos não são apagados; ficam desativados para a nova loja poder ser
-- cadastrada pelo administrador sem misturar o catálogo antigo.
-- ================================================================
update public.premium_store_settings set payments_enabled=false where id=1;
update public.premium_items set active=false where active=true;

-- ================================================================
-- 7. Realtime para títulos e loja
-- ================================================================
do $$
begin
  begin alter publication supabase_realtime add table public.user_titles; exception when duplicate_object then null; end;
  begin alter publication supabase_realtime add table public.titles; exception when duplicate_object then null; end;
  begin alter publication supabase_realtime add table public.store_categories; exception when duplicate_object then null; end;
exception when undefined_object then null;
end $$;

-- Todos os jogadores autenticados podem visualizar os títulos conquistados de um perfil.
drop policy if exists "user titles own read" on public.user_titles;
DROP POLICY IF EXISTS "user titles public read" ON public.user_titles;
create policy "user titles public read" on public.user_titles for select to authenticated using(true);


-- ================================================================
-- INÍCIO: quizup_v38_4_MIGRATION_AVATARES_ARTES.sql
-- ================================================================
-- QuizUp v38.4 - artes de títulos/emblemas/conquistas, contas e avatar somente do inventário
-- Execute APÓS a migration v38. Não apaga partidas.

alter table if exists public.titles add column if not exists asset_url text;
alter table if exists public.titles add column if not exists asset_type text;
alter table if exists public.badges add column if not exists asset_url text;
alter table if exists public.badges add column if not exists asset_type text;
alter table if exists public.achievements add column if not exists asset_url text;
alter table if exists public.achievements add column if not exists asset_type text;

-- Usuários não podem mais usar foto própria como avatar. O avatar visual vem exclusivamente do inventário.
update public.profiles set avatar_url=null where avatar_url is not null;
create or replace function public.enforce_inventory_avatar()
returns trigger language plpgsql as $$
begin
  new.avatar_url := null;
  return new;
end $$;
drop trigger if exists trg_profiles_inventory_avatar on public.profiles;
DROP TRIGGER IF EXISTS trg_profiles_inventory_avatar ON public.profiles;
create trigger trg_profiles_inventory_avatar before insert or update on public.profiles
for each row execute function public.enforce_inventory_avatar();

-- Bucket público para artes administradas pelo painel. Escrita somente para administradores.
insert into storage.buckets(id,name,public)
values('admin-assets','admin-assets',true)
on conflict(id) do update set public=true;

drop policy if exists "quizup admin assets public read" on storage.objects;
DROP POLICY IF EXISTS "quizup admin assets public read" ON storage.objects;
create policy "quizup admin assets public read" on storage.objects for select to public using(bucket_id='admin-assets');
drop policy if exists "quizup admin assets admin insert" on storage.objects;
DROP POLICY IF EXISTS "quizup admin assets admin insert" ON storage.objects;
create policy "quizup admin assets admin insert" on storage.objects for insert to authenticated
with check(bucket_id='admin-assets' and exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin'));
drop policy if exists "quizup admin assets admin update" on storage.objects;
DROP POLICY IF EXISTS "quizup admin assets admin update" ON storage.objects;
create policy "quizup admin assets admin update" on storage.objects for update to authenticated
using(bucket_id='admin-assets' and exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin'))
with check(bucket_id='admin-assets' and exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin'));

-- RPC confiável para o painel listar todas as contas registradas, inclusive administradores.
drop function if exists public.admin_list_accounts();
create or replace function public.admin_list_accounts()
returns table(id uuid,username text,display_name text,email text,role text,created_at timestamptz)
language plpgsql security definer set search_path=public,auth as $$
begin
  if not exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin') then
    raise exception 'Acesso negado';
  end if;
  return query
    select p.id,p.username,p.display_name,u.email,p.role,u.created_at
    from public.profiles p
    left join auth.users u on u.id=p.id
    order by coalesce(u.created_at,p.created_at) desc;
end $$;
revoke all on function public.admin_list_accounts() from public;
grant execute on function public.admin_list_accounts() to authenticated;

-- Garantir que títulos/conquistas/emblemas podem ser vistos por jogadores autenticados.
alter table if exists public.badges enable row level security;
drop policy if exists "badges read active" on public.badges;
DROP POLICY IF EXISTS "badges read active" ON public.badges;
create policy "badges read active" on public.badges for select to authenticated
using(active=true or exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin'));
drop policy if exists "badges admin insert" on public.badges;
DROP POLICY IF EXISTS "badges admin insert" ON public.badges;
create policy "badges admin insert" on public.badges for insert to authenticated
with check(exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin'));
drop policy if exists "badges admin update" on public.badges;
DROP POLICY IF EXISTS "badges admin update" ON public.badges;
create policy "badges admin update" on public.badges for update to authenticated
using(exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin'))
with check(exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin'));

alter table if exists public.achievements enable row level security;
drop policy if exists "achievements read active" on public.achievements;
DROP POLICY IF EXISTS "achievements read active" ON public.achievements;
create policy "achievements read active" on public.achievements for select to authenticated
using(active=true or exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin'));
drop policy if exists "achievements admin insert" on public.achievements;
DROP POLICY IF EXISTS "achievements admin insert" ON public.achievements;
create policy "achievements admin insert" on public.achievements for insert to authenticated
with check(exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin'));
drop policy if exists "achievements admin update" on public.achievements;
DROP POLICY IF EXISTS "achievements admin update" ON public.achievements;
create policy "achievements admin update" on public.achievements for update to authenticated
using(exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin'))
with check(exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin'));


-- ================================================================
-- INÍCIO: quizup_v38_5_FIX_CONTAS_MOLDURAS.sql
-- ================================================================
-- QuizUp v38.5 - contas no painel + molduras com arte padronizada
-- Execute APÓS v38.4. Idempotente.

-- ================================================================
-- 1) Corrige a RPC das contas: não depende de profiles.created_at
-- ================================================================
drop function if exists public.admin_list_accounts();
create or replace function public.admin_list_accounts()
returns table(
  id uuid,
  username text,
  display_name text,
  email text,
  role text,
  created_at timestamptz
)
language plpgsql
security definer
set search_path=public,auth
as $$
begin
  if auth.uid() is null then raise exception 'Não autenticado'; end if;
  if not exists(select 1 from public.profiles p where p.id=auth.uid() and lower(coalesce(p.role,''))='admin') then
    raise exception 'Acesso negado';
  end if;
  return query
    select p.id,
           p.username::text,
           p.display_name::text,
           u.email::text,
           p.role::text,
           u.created_at
      from public.profiles p
      left join auth.users u on u.id=p.id
     order by u.created_at desc nulls last, p.username asc;
end $$;
revoke all on function public.admin_list_accounts() from public;
grant execute on function public.admin_list_accounts() to authenticated;

-- ================================================================
-- 2) Metadados padronizados das molduras
-- ================================================================
alter table if exists public.premium_items add column if not exists asset_width integer;
alter table if exists public.premium_items add column if not exists asset_height integer;
alter table if exists public.premium_items add column if not exists frame_inset_percent numeric(5,2);
alter table if exists public.premium_items add column if not exists frame_version text;

update public.premium_items
   set asset_width=coalesce(asset_width,256),
       asset_height=coalesce(asset_height,256),
       frame_inset_percent=coalesce(frame_inset_percent,0),
       frame_version=coalesce(frame_version,'v1')
 where kind='frame';

-- O arquivo da moldura é uma sobreposição transparente. O avatar fica por baixo.
-- Tamanho oficial do canvas: 256x256 px. A moldura deve deixar o centro transparente.



-- ================================================================
-- INÍCIO: quizup_v38_6_MIGRATION_TITULOS_MOLDURAS_CATEGORIAS.sql
-- ================================================================
-- QuizUp v38.6
-- Títulos: apenas nome/emoji/símbolo + efeito visual
-- Avatares: 256x256
-- Molduras: PNG 256x256 com transparência
-- Categorias: capa 800x500
-- Desafios/amigos e presença usam as estruturas existentes.

alter table if exists public.titles add column if not exists effect_style text not null default 'none';
update public.titles set effect_style='none' where effect_style is null;

alter table if exists public.categories add column if not exists cover_url text;

alter table if exists public.premium_items add column if not exists asset_width integer;
alter table if exists public.premium_items add column if not exists asset_height integer;
alter table if exists public.premium_items add column if not exists frame_inset_percent numeric(5,2);
alter table if exists public.premium_items add column if not exists frame_version text;

-- Metadados padrão para molduras já cadastradas.
update public.premium_items
set asset_width=coalesce(asset_width,256),
    asset_height=coalesce(asset_height,256),
    frame_inset_percent=coalesce(frame_inset_percent,0),
    frame_version=coalesce(frame_version,'v2')
where kind='frame';

-- Bucket usado pelo painel para capas e artes administrativas, caso ainda não exista.
insert into storage.buckets (id,name,public)
values ('admin-assets','admin-assets',true)
on conflict (id) do update set public=true;

-- Regras de efeitos permitidos nos títulos.
alter table public.titles drop constraint if exists titles_effect_style_check;
alter table public.titles add constraint titles_effect_style_check
check (effect_style in ('none','lightning','fire','gold','silver','goldmetal'));

-- Observação: resolução/formato do arquivo é validado no navegador antes do upload.
-- Isso evita aceitar molduras fora do padrão sem depender de processamento de imagem no Postgres.


-- ================================================================
-- INÍCIO: quizup_v38_7_MIGRATION_EFEITOS_MOLDURAS_TITULOS.sql
-- ================================================================
-- QuizUp v38.7 — efeitos animados para títulos e molduras
alter table if exists public.premium_items add column if not exists effect_style text not null default 'none';
update public.premium_items set effect_style='none' where effect_style is null;

alter table if exists public.titles add column if not exists effect_style text not null default 'none';
update public.titles set effect_style='none' where effect_style is null;

alter table if exists public.titles drop constraint if exists titles_effect_style_check;
alter table if exists public.titles add constraint titles_effect_style_check check (effect_style in ('none','fire','water','earth','air','lightning','darkness','light','gold','silver','bronze','vip','diamond','ruby','emerald'));

alter table if exists public.premium_items drop constraint if exists premium_items_effect_style_check;
alter table if exists public.premium_items add constraint premium_items_effect_style_check check (effect_style in ('none','fire','water','earth','air','lightning','darkness','light','gold','silver','bronze','vip','diamond','ruby','emerald'));


-- ================================================================
-- INÍCIO: quizup_v38_8_MIGRATION_FUNDOS_PERFIL.sql
-- ================================================================
-- QuizUp v38.8 - Fundos de Perfil (estáticos e animados)
-- Execute APÓS a migration v38.7. É idempotente.

alter table if exists public.premium_items add column if not exists asset_type text;
alter table if exists public.profiles add column if not exists premium_background text;

-- Categoria oficial da nova área da loja.
insert into public.store_categories(name,description,icon,sort_order,created_by)
values ('Fundos de Perfil','Fundos estáticos ou animados para o perfil do jogador.','🖼️',7,null)
on conflict(name) do update set description=excluded.description, icon=excluded.icon;

-- Regras do slot de fundo: somente o dono pode ativar um item que possui.
-- O fundo é salvo em profiles.premium_background para carregar também em perfis públicos.
do $$
declare r record;
begin
  for r in select oid::regprocedure::text as sig from pg_proc where pronamespace='public'::regnamespace and proname='activate_premium_item' loop
    execute 'drop function if exists '||r.sig||' cascade';
  end loop;
end $$;

create or replace function public.activate_premium_item(p_item_id text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare
  it public.premium_items;
  new_balance bigint;
begin
  if auth.uid() is null then raise exception 'Não autenticado'; end if;
  select * into it from public.premium_items where id::text=trim(p_item_id) and active=true limit 1;
  if it.id is null then raise exception 'Item não encontrado ou inativo'; end if;
  if not exists(select 1 from public.user_premium_items where user_id=auth.uid() and item_id=it.id) then
    raise exception 'Você ainda não possui este item';
  end if;

  -- Um item ativo por categoria/slot.
  update public.user_premium_items up
     set active=false
   where up.user_id=auth.uid()
     and exists(select 1 from public.premium_items x where x.id=up.item_id and x.kind=it.kind);
  update public.user_premium_items set active=true where user_id=auth.uid() and item_id=it.id;

  if it.kind='frame' then
    update public.profiles set premium_frame=it.id::text where id=auth.uid();
  elsif it.kind='avatar' then
    update public.profiles set premium_avatar=it.id::text where id=auth.uid();
  elsif it.kind='effect' then
    update public.profiles set premium_effect=it.id::text where id=auth.uid();
  elsif it.kind='theme' then
    update public.profiles set premium_theme=it.id::text where id=auth.uid();
  elsif it.kind='background' then
    update public.profiles set premium_background=it.id::text where id=auth.uid();
  elsif it.kind='title' then
    update public.profiles set premium_title=it.id::text where id=auth.uid();
  elsif it.kind='badge' then
    update public.profiles set premium_badge=it.id::text where id=auth.uid();
  elsif it.kind='vip' then
    update public.profiles set premium_vip=true where id=auth.uid();
  end if;

  select coins into new_balance from public.profiles where id=auth.uid();
  return jsonb_build_object('ok',true,'item_id',it.id,'kind',it.kind,'balance',coalesce(new_balance,0));
end $$;
revoke all on function public.activate_premium_item(text) from public;
grant execute on function public.activate_premium_item(text) to authenticated;

-- Mantém o comportamento para bases que ainda possuem a assinatura integer.
drop function if exists public.activate_premium_item(integer);
create or replace function public.activate_premium_item(p_item_id integer)
returns jsonb language sql security definer set search_path=public as $$
  select public.activate_premium_item(p_item_id::text);
$$;
revoke all on function public.activate_premium_item(integer) from public;
grant execute on function public.activate_premium_item(integer) to authenticated;


-- ================================================================
-- INÍCIO: quizup_v38_9_MIGRATION_VENDAS_TITULOS_EMBLEMAS_FUNDOS.sql
-- ================================================================
-- QuizUp v38.9
-- Sistema unificado de venda/posse/ativação de Títulos, Emblemas e Fundos de Perfil.
-- Execute APÓS v38.8. É idempotente.

alter table if exists public.premium_items add column if not exists source_type text;
alter table if exists public.premium_items add column if not exists source_id text;

-- Mantém as categorias oficiais da loja.
insert into public.store_categories(name,description,icon,sort_order,created_by)
values
 ('Títulos','Títulos que o jogador pode comprar e equipar no perfil.','🏷️',4,null),
 ('Emblemas','Emblemas colecionáveis para a identidade do jogador.','🏅',6,null),
 ('Fundos de Perfil','Fundos estáticos ou animados para o perfil do jogador.','🖼️',8,null)
on conflict(name) do update set description=excluded.description, icon=excluded.icon, sort_order=excluded.sort_order;

-- Converte itens antigos criados diretamente pela Loja em objetos reais.
-- Assim nenhum título antigo fica preso ao ID `custom-...` no perfil.
insert into public.titles(name,description,icon,effect_style,active,created_by)
select distinct pi.name, pi.description, coalesce(nullif(pi.icon,''),'🏷️'), coalesce(pi.effect_style,'none'), true, pi.created_by
from public.premium_items pi
where pi.category='Títulos'
  and not exists(select 1 from public.titles t where lower(trim(t.name))=lower(trim(pi.name)));

insert into public.badges(name,description,icon,active,created_by)
select distinct pi.name, pi.description, '', true, pi.created_by
from public.premium_items pi
where pi.category in ('Emblemas','Badges')
  and not exists(select 1 from public.badges b where lower(trim(b.name))=lower(trim(pi.name)));

-- Vincula itens antigos da categoria Títulos/Emblemas pelo nome quando possível.
update public.premium_items pi
set source_type='title', source_id=t.id::text
from public.titles t
where coalesce(pi.source_type,'')='' and pi.category='Títulos' and lower(trim(pi.name))=lower(trim(t.name));

update public.premium_items pi
set source_type='badge', source_id=b.id::text
from public.badges b
where coalesce(pi.source_type,'')='' and pi.category in ('Emblemas','Badges') and lower(trim(pi.name))=lower(trim(b.name));

-- Entrega aos jogadores os títulos que já haviam sido comprados em versões anteriores.
insert into public.user_titles(user_id,title_id,is_main)
select up.user_id, t.id, false
from public.user_premium_items up
join public.premium_items pi on pi.id=up.item_id
join public.titles t on t.id::text=pi.source_id
where pi.kind='title' and pi.source_type='title'
on conflict(user_id,title_id) do nothing;

-- Se um título comprado estava ativo, ele vira o título principal.
update public.user_titles ut
set is_main=true
from public.user_premium_items up
join public.premium_items pi on pi.id=up.item_id
where ut.user_id=up.user_id
  and ut.title_id::text=pi.source_id
  and pi.kind='title'
  and pi.source_type='title'
  and up.active=true;

-- RPC de compra: além de debitar Coins, entrega o objeto real (principalmente títulos).
do $$
declare r record;
begin
  for r in select oid::regprocedure::text as sig
          from pg_proc
          where pronamespace='public'::regnamespace
            and proname='purchase_premium_item'
  loop
    execute 'drop function if exists '||r.sig||' cascade';
  end loop;
end $$;

create or replace function public.purchase_premium_item(p_item_id text,p_expected_price bigint default null)
returns jsonb language plpgsql security definer set search_path=public as $$
declare
  it public.premium_items;
  charge bigint;
  bal bigint;
  promo_ok boolean;
  title_uuid uuid;
  already boolean;
begin
  if auth.uid() is null then raise exception 'Não autenticado'; end if;

  select * into it
  from public.premium_items
  where id::text=trim(p_item_id) and active=true
  limit 1;
  if it.id is null then raise exception 'Item não encontrado ou indisponível'; end if;

  if exists(select 1 from public.premium_store_settings where id=1 and (coalesce(enabled,false)=false or coalesce(cosmetics_enabled,false)=false)) then
    raise exception 'A loja de cosméticos está desativada';
  end if;

  promo_ok:=coalesce(it.promo_active,false)
    and coalesce(it.promo_price_coins,0)>0
    and coalesce(it.promo_price_coins,0)<coalesce(it.price_coins,0)
    and (it.promo_expires_at is null or it.promo_expires_at>now());
  charge:=case when promo_ok then it.promo_price_coins else coalesce(it.price_coins,it.price_cents,0) end;
  if charge is null or charge<0 then raise exception 'Preço do item inválido'; end if;
  if p_expected_price is not null and p_expected_price<>charge then raise exception 'O preço do item mudou. Atualize a loja e tente novamente.'; end if;

  select exists(select 1 from public.user_premium_items where user_id=auth.uid() and item_id=it.id) into already;

  if not already then
    update public.profiles
       set coins=coalesce(coins,0)-charge
     where id=auth.uid() and coalesce(coins,0)>=charge
     returning coins into bal;
    if bal is null then raise exception 'Você não possui QuizCoins suficientes'; end if;

    insert into public.user_premium_items(user_id,item_id,active,purchased_at)
    values(auth.uid(),it.id,true,now());

    insert into public.coin_ledger(user_id,amount,source_type,source_id,description)
    values(auth.uid(),-charge,'premium_purchase',gen_random_uuid()::text,'Compra: '||coalesce(it.name,'Item'));
  else
    select coins into bal from public.profiles where id=auth.uid();
  end if;

  -- Títulos são objetos reais em user_titles. Comprar já concede e equipa como principal.
  if it.kind='title' then
    title_uuid:=null;
    if coalesce(it.source_type,'')='title' and coalesce(it.source_id,'')<>'' then
      begin title_uuid:=it.source_id::uuid; exception when others then title_uuid:=null; end;
    end if;
    if title_uuid is null then
      select id into title_uuid from public.titles where lower(trim(name))=lower(trim(it.name)) and active=true limit 1;
    end if;
    if title_uuid is not null then
      insert into public.user_titles(user_id,title_id,is_main)
      values(auth.uid(),title_uuid,true)
      on conflict(user_id,title_id) do update set is_main=true;
      update public.user_titles set is_main=false where user_id=auth.uid() and title_id<>title_uuid;
      update public.profiles set main_title_id=title_uuid, premium_title=it.id::text where id=auth.uid();
    else
      update public.profiles set premium_title=it.id::text where id=auth.uid();
    end if;
  elsif it.kind='badge' then
    update public.profiles set premium_badge=it.id::text where id=auth.uid();
  elsif it.kind='background' then
    update public.profiles set premium_background=it.id::text where id=auth.uid();
  end if;

  return jsonb_build_object(
    'ok',true,
    'already_owned',already,
    'balance',coalesce(bal,0),
    'charge',case when already then 0 else charge end,
    'item_id',it.id,
    'kind',it.kind,
    'source_type',it.source_type,
    'source_id',it.source_id
  );
exception when unique_violation then
  select coins into bal from public.profiles where id=auth.uid();
  return jsonb_build_object('ok',true,'already_owned',true,'balance',coalesce(bal,0),'charge',0,'item_id',it.id,'kind',it.kind);
end $$;
revoke all on function public.purchase_premium_item(text,bigint) from public;
grant execute on function public.purchase_premium_item(text,bigint) to authenticated;

drop function if exists public.purchase_premium_item(integer);
create or replace function public.purchase_premium_item(p_item_id integer)
returns jsonb language sql security definer set search_path=public as $$
  select public.purchase_premium_item(p_item_id::text,null::bigint);
$$;
revoke all on function public.purchase_premium_item(integer) from public;
grant execute on function public.purchase_premium_item(integer) to authenticated;

-- Ativação também entende os vínculos oficiais.
do $$
declare r record;
begin
  for r in select oid::regprocedure::text as sig
          from pg_proc
          where pronamespace='public'::regnamespace
            and proname='activate_premium_item'
  loop
    execute 'drop function if exists '||r.sig||' cascade';
  end loop;
end $$;

create or replace function public.activate_premium_item(p_item_id text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare
  it public.premium_items;
  bal bigint;
  title_uuid uuid;
begin
  if auth.uid() is null then raise exception 'Não autenticado'; end if;
  select * into it from public.premium_items where id::text=trim(p_item_id) and active=true limit 1;
  if it.id is null then raise exception 'Item não encontrado ou inativo'; end if;
  if not exists(select 1 from public.user_premium_items where user_id=auth.uid() and item_id=it.id) then
    raise exception 'Você ainda não possui este item';
  end if;

  update public.user_premium_items up set active=false
   where up.user_id=auth.uid()
     and exists(select 1 from public.premium_items x where x.id=up.item_id and x.kind=it.kind);
  update public.user_premium_items set active=true where user_id=auth.uid() and item_id=it.id;

  if it.kind='frame' then
    update public.profiles set premium_frame=it.id::text where id=auth.uid();
  elsif it.kind='avatar' then
    update public.profiles set premium_avatar=it.id::text where id=auth.uid();
  elsif it.kind='effect' then
    update public.profiles set premium_effect=it.id::text where id=auth.uid();
  elsif it.kind='theme' then
    update public.profiles set premium_theme=it.id::text where id=auth.uid();
  elsif it.kind='background' then
    update public.profiles set premium_background=it.id::text where id=auth.uid();
  elsif it.kind='badge' then
    update public.profiles set premium_badge=it.id::text where id=auth.uid();
  elsif it.kind='title' then
    title_uuid:=null;
    if coalesce(it.source_type,'')='title' and coalesce(it.source_id,'')<>'' then
      begin title_uuid:=it.source_id::uuid; exception when others then title_uuid:=null; end;
    end if;
    if title_uuid is null then
      select id into title_uuid from public.titles where lower(trim(name))=lower(trim(it.name)) and active=true limit 1;
    end if;
    if title_uuid is not null then
      insert into public.user_titles(user_id,title_id,is_main) values(auth.uid(),title_uuid,true)
      on conflict(user_id,title_id) do update set is_main=true;
      update public.user_titles set is_main=false where user_id=auth.uid() and title_id<>title_uuid;
      update public.profiles set main_title_id=title_uuid,premium_title=it.id::text where id=auth.uid();
    else
      update public.profiles set premium_title=it.id::text where id=auth.uid();
    end if;
  elsif it.kind='vip' then
    update public.profiles set premium_vip=true where id=auth.uid();
  end if;

  select coins into bal from public.profiles where id=auth.uid();
  return jsonb_build_object('ok',true,'item_id',it.id,'kind',it.kind,'source_type',it.source_type,'source_id',it.source_id,'balance',coalesce(bal,0));
end $$;
revoke all on function public.activate_premium_item(text) from public;
grant execute on function public.activate_premium_item(text) to authenticated;

create or replace function public.activate_premium_item(p_item_id integer)
returns jsonb language sql security definer set search_path=public as $$
  select public.activate_premium_item(p_item_id::text);
$$;
revoke all on function public.activate_premium_item(integer) from public;
grant execute on function public.activate_premium_item(integer) to authenticated;


-- ================================================================
-- INÍCIO: quizup_v38_9_1_MIGRATION_CORRECOES_TITULO_ADMIN_MOLDURA.sql
-- ================================================================
-- QuizUp v38.9.1
-- Correções:
-- 1) Administrador sempre tem o título principal de sistema "Administrador".
-- 2) Administrador não pode trocar esse título principal por um título comprado.
-- 3) Remove estados antigos de título principal para contas admin sem apagar títulos adquiridos.
-- 4) A ativação de títulos continua individual por usuário.
-- 5) Limpa flags is_main duplicadas e deixa no máximo um título principal por usuário.

-- Corrige dados antigos de administradores: mantém títulos adquiridos, mas nenhum deles fica marcado como principal.
update public.user_titles ut
set is_main=false
where exists(select 1 from public.profiles p where p.id=ut.user_id and p.role='admin');

update public.profiles
set main_title_id=null,
    premium_title=null
where role='admin';

-- Reforça a função de seleção do título principal. Administradores ficam com título de sistema.
create or replace function public.set_main_title(p_title_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
begin
  if auth.uid() is null then raise exception 'Não autenticado'; end if;

  if exists(select 1 from public.profiles where id=auth.uid() and role='admin') then
    update public.user_titles set is_main=false where user_id=auth.uid();
    update public.profiles set main_title_id=null,premium_title=null where id=auth.uid();
    return jsonb_build_object('ok',true,'main_title_id',null,'system_title','Administrador');
  end if;

  if p_title_id is not null and not exists(
    select 1 from public.user_titles where user_id=auth.uid() and title_id=p_title_id
  ) then
    raise exception 'Você ainda não conquistou este título';
  end if;

  update public.user_titles set is_main=false where user_id=auth.uid();
  if p_title_id is not null then
    update public.user_titles set is_main=true
    where user_id=auth.uid() and title_id=p_title_id;
  end if;
  update public.profiles set main_title_id=p_title_id where id=auth.uid();
  return jsonb_build_object('ok',true,'main_title_id',p_title_id);
end $$;
revoke all on function public.set_main_title(uuid) from public;
grant execute on function public.set_main_title(uuid) to authenticated;

-- Corrige a RPC de ativação para impedir que admin equipe título comprado como principal.
create or replace function public.activate_premium_item(p_item_id text)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  it public.premium_items;
  bal bigint;
  title_uuid uuid;
  is_admin boolean:=false;
begin
  if auth.uid() is null then raise exception 'Não autenticado'; end if;
  select exists(select 1 from public.profiles where id=auth.uid() and role='admin') into is_admin;

  select * into it from public.premium_items
  where id::text=trim(p_item_id) and active=true limit 1;
  if it.id is null then raise exception 'Item não encontrado ou inativo'; end if;
  if not exists(select 1 from public.user_premium_items where user_id=auth.uid() and item_id=it.id) then
    raise exception 'Você ainda não possui este item';
  end if;

  if it.kind='title' and is_admin then
    update public.user_premium_items set active=false
    where user_id=auth.uid() and item_id=it.id;
    update public.user_titles set is_main=false where user_id=auth.uid();
    update public.profiles set main_title_id=null,premium_title=null where id=auth.uid();
    select coins into bal from public.profiles where id=auth.uid();
    return jsonb_build_object('ok',true,'item_id',it.id,'kind','title','system_title','Administrador','balance',coalesce(bal,0));
  end if;

  -- Apenas um item ativo por slot.
  update public.user_premium_items up set active=false
  where up.user_id=auth.uid()
    and exists(select 1 from public.premium_items x where x.id=up.item_id and x.kind=it.kind);
  update public.user_premium_items set active=true where user_id=auth.uid() and item_id=it.id;

  if it.kind='frame' then
    update public.profiles set premium_frame=it.id::text where id=auth.uid();
  elsif it.kind='avatar' then
    update public.profiles set premium_avatar=it.id::text where id=auth.uid();
  elsif it.kind='effect' then
    update public.profiles set premium_effect=it.id::text where id=auth.uid();
  elsif it.kind='theme' then
    update public.profiles set premium_theme=it.id::text where id=auth.uid();
  elsif it.kind='background' then
    update public.profiles set premium_background=it.id::text where id=auth.uid();
  elsif it.kind='badge' then
    update public.profiles set premium_badge=it.id::text where id=auth.uid();
  elsif it.kind='title' then
    title_uuid:=null;
    if coalesce(it.source_type,'')='title' and coalesce(it.source_id,'')<>'' then
      begin title_uuid:=it.source_id::uuid; exception when others then title_uuid:=null; end;
    end if;
    if title_uuid is null then
      select id into title_uuid from public.titles
      where lower(trim(name))=lower(trim(it.name)) and active=true limit 1;
    end if;
    if title_uuid is not null then
      update public.user_titles set is_main=false where user_id=auth.uid();
      insert into public.user_titles(user_id,title_id,is_main)
      values(auth.uid(),title_uuid,true)
      on conflict(user_id,title_id) do update set is_main=true;
      update public.profiles set main_title_id=title_uuid,premium_title=it.id::text where id=auth.uid();
    else
      update public.profiles set premium_title=it.id::text where id=auth.uid();
    end if;
  elsif it.kind='vip' then
    update public.profiles set premium_vip=true where id=auth.uid();
  end if;

  select coins into bal from public.profiles where id=auth.uid();
  return jsonb_build_object('ok',true,'item_id',it.id,'kind',it.kind,'source_type',it.source_type,'source_id',it.source_id,'balance',coalesce(bal,0));
end $$;
revoke all on function public.activate_premium_item(text) from public;
grant execute on function public.activate_premium_item(text) to authenticated;

create or replace function public.activate_premium_item(p_item_id integer)
returns jsonb language sql security definer set search_path=public as $$
  select public.activate_premium_item(p_item_id::text);
$$;
revoke all on function public.activate_premium_item(integer) from public;
grant execute on function public.activate_premium_item(integer) to authenticated;

-- Corrige eventuais duplicidades antigas antes de criar a regra de unicidade.
delete from public.user_titles a
using public.user_titles b
where a.user_id=b.user_id
  and a.is_main=true
  and b.is_main=true
  and a.id < b.id;

-- Reforça a integridade: não permite múltiplos títulos principais para o mesmo usuário.
create unique index if not exists user_titles_one_main_per_user
on public.user_titles(user_id)
where is_main=true;


-- ================================================================
-- INÍCIO: quizup_v39_0_MIGRATION_TITULOS_COR_FONTE.sql
-- ================================================================
-- QuizUp v39.0: títulos com cor e fonte escolhidas pelo administrador
alter table if exists public.titles add column if not exists title_color text not null default '#ffd21a';
alter table if exists public.titles add column if not exists title_font text not null default 'Inter';
alter table if exists public.premium_items add column if not exists title_color text not null default '#ffd21a';
alter table if exists public.premium_items add column if not exists title_font text not null default 'Inter';
update public.titles set title_color='#ffd21a' where title_color is null or title_color='';
update public.titles set title_font='Inter' where title_font is null or title_font='';
update public.premium_items pi set title_color=t.title_color,title_font=t.title_font from public.titles t where pi.source_type='title' and pi.source_id::text=t.id::text;
alter table if exists public.titles drop constraint if exists titles_title_color_check;
alter table if exists public.titles add constraint titles_title_color_check check (title_color ~ '^#[0-9A-Fa-f]{6}$');
alter table if exists public.titles drop constraint if exists titles_title_font_check;
alter table if exists public.titles add constraint titles_title_font_check check (title_font in ('Inter','Arial','Georgia','Trebuchet MS','Courier New','Impact','Verdana'));
alter table if exists public.premium_items drop constraint if exists premium_items_title_color_check;
alter table if exists public.premium_items add constraint premium_items_title_color_check check (title_color ~ '^#[0-9A-Fa-f]{6}$');
alter table if exists public.premium_items drop constraint if exists premium_items_title_font_check;
alter table if exists public.premium_items add constraint premium_items_title_font_check check (title_font in ('Inter','Arial','Georgia','Trebuchet MS','Courier New','Impact','Verdana'));

-- ================================================================
-- v39.0.1 - Loja totalmente administrada pelo painel
-- ================================================================
-- Somente administradores podem criar/editar/retirar itens da Loja.
-- Jogadores continuam podendo apenas visualizar e comprar itens ativos.
alter table if exists public.premium_items enable row level security;
drop policy if exists "premium items authenticated read" on public.premium_items;
create policy "premium items authenticated read" on public.premium_items
  for select to authenticated using(true);
drop policy if exists "premium items admin manage" on public.premium_items;
create policy "premium items admin manage" on public.premium_items
  for all to authenticated
  using(public.is_admin()) with check(public.is_admin());

-- Exclusão segura: títulos e emblemas são retirados da Loja sem apagar o
-- inventário de quem já comprou/conquistou.
drop policy if exists "titles admin delete" on public.titles;
create policy "titles admin delete" on public.titles
  for delete to authenticated
  using(public.is_admin());
drop policy if exists "badges admin delete" on public.badges;
create policy "badges admin delete" on public.badges
  for delete to authenticated
  using(public.is_admin());

-- Categorias que não foram solicitadas para esta versão ficam fora da Loja.
-- Elas não são apagadas do banco para não quebrar dados antigos.
update public.store_categories
set active=false
where name in ('Emojis','Temas','VIP','Passe','Moedas');

-- Itens antigos/fictícios dessas categorias não aparecem mais para compra.
update public.premium_items
set active=false
where category in ('Emojis','Temas','VIP','Passe','Moedas');

-- A Loja não recebe mais produtos padrão/fictícios pelo código do navegador.
-- Todos os itens vendidos devem ser cadastrados pelo painel administrativo.

-- ================================================================
-- v39.0.2 - CORREÇÕES TÍTULOS, EMBLEMAS, BACKGROUNDS E CAPAS
-- ================================================================
alter table if exists public.titles alter column icon set default '🏷️';
update public.titles set icon='🏷️' where icon is null;
alter table if exists public.badges alter column icon set default '🏅';
update public.badges set icon='🏅' where icon is null;
alter table if exists public.categories add column if not exists cover_url text;

-- Elimina a ambiguidade criada por versões antigas que tinham duas assinaturas.
drop function if exists public.active_premium_item(integer);
drop function if exists public.active_premium_item(text);
create or replace function public.active_premium_item(p_item_id text)
returns jsonb language sql security definer set search_path=public as $$
  select public.activate_premium_item(p_item_id::text);
$$;
revoke all on function public.active_premium_item(text) from public;
grant execute on function public.active_premium_item(text) to authenticated;

