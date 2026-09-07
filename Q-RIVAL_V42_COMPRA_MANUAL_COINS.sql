-- Q-Rival: compra manual de QuizCoins enquanto o gateway automático não está disponível.
-- O jogador solicita o pacote, conversa com o administrador, recebe o link de pagamento,
-- envia o comprovante e somente o administrador pode aprovar e creditar as Coins.

create table if not exists public.manual_coin_orders (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  coin_package_id uuid references public.coin_packages(id) on delete set null,
  coins bigint not null check (coins > 0),
  amount_cents bigint not null check (amount_cents > 0),
  status text not null default 'pending' check (status in ('pending','payment_link_sent','payment_submitted','approved','rejected','cancelled')),
  payment_link text,
  proof_path text,
  admin_note text,
  rejection_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  approved_at timestamptz,
  approved_by uuid references auth.users(id)
);

create table if not exists public.manual_coin_messages (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.manual_coin_orders(id) on delete cascade,
  sender_id uuid not null references auth.users(id) on delete cascade,
  message text not null check (length(trim(message)) > 0),
  message_type text not null default 'text' check (message_type in ('text','payment_link','proof','system')),
  media_path text,
  created_at timestamptz not null default now()
);

create index if not exists manual_coin_orders_user_idx on public.manual_coin_orders(user_id,created_at desc);
create index if not exists manual_coin_orders_status_idx on public.manual_coin_orders(status,updated_at desc);
create index if not exists manual_coin_messages_order_idx on public.manual_coin_messages(order_id,created_at);

alter table public.manual_coin_orders enable row level security;
alter table public.manual_coin_messages enable row level security;

drop policy if exists "manual coin orders own read" on public.manual_coin_orders;
create policy "manual coin orders own read" on public.manual_coin_orders
for select to authenticated using (user_id=auth.uid() or public.is_admin());

drop policy if exists "manual coin messages participant read" on public.manual_coin_messages;
create policy "manual coin messages participant read" on public.manual_coin_messages
for select to authenticated using (
  public.is_admin() or exists(select 1 from public.manual_coin_orders o where o.id=order_id and o.user_id=auth.uid())
);

drop policy if exists "manual coin messages own insert" on public.manual_coin_messages;
create policy "manual coin messages own insert" on public.manual_coin_messages
for insert to authenticated with check (
  sender_id=auth.uid() and (
    public.is_admin() or exists(select 1 from public.manual_coin_orders o where o.id=order_id and o.user_id=auth.uid())
  )
);

drop policy if exists "manual coin orders admin update" on public.manual_coin_orders;
create policy "manual coin orders admin update" on public.manual_coin_orders
for update to authenticated using(public.is_admin()) with check(public.is_admin());

-- O bucket é privado: comprovantes de pagamento não ficam publicamente acessíveis.
insert into storage.buckets(id,name,public)
values('purchase-proofs','purchase-proofs',false)
on conflict (id) do update set public=false;

drop policy if exists "purchase proofs user upload" on storage.objects;
create policy "purchase proofs user upload" on storage.objects
for insert to authenticated with check (
  bucket_id='purchase-proofs' and (storage.foldername(name))[1]=auth.uid()::text
);

drop policy if exists "purchase proofs owner or admin read" on storage.objects;
create policy "purchase proofs owner or admin read" on storage.objects
for select to authenticated using (
  bucket_id='purchase-proofs' and ((storage.foldername(name))[1]=auth.uid()::text or public.is_admin())
);

drop policy if exists "purchase proofs owner delete" on storage.objects;
create policy "purchase proofs owner delete" on storage.objects
for delete to authenticated using (
  bucket_id='purchase-proofs' and ((storage.foldername(name))[1]=auth.uid()::text or public.is_admin())
);

-- Realtime para o bate-papo de compra.
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname='supabase_realtime' and schemaname='public' and tablename='manual_coin_messages'
  ) then
    execute 'alter publication supabase_realtime add table public.manual_coin_messages';
  end if;
end $$;

create or replace function public.create_manual_coin_order(p_coin_package_id uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare p public.coin_packages; o public.manual_coin_orders;
begin
  if auth.uid() is null then raise exception 'Não autenticado'; end if;
  select * into p from public.coin_packages where id=p_coin_package_id and active=true limit 1;
  if p.id is null then raise exception 'Pacote de QuizCoins indisponível'; end if;
  insert into public.manual_coin_orders(user_id,coin_package_id,coins,amount_cents,status)
  values(auth.uid(),p.id,p.coins,p.price_cents,'pending') returning * into o;
  insert into public.manual_coin_messages(order_id,sender_id,message,message_type)
  values(o.id,auth.uid(),'Olá! Quero comprar '||p.coins||' QuizCoins por R$ '||to_char(p.price_cents/100.0,'FM999999990D00')||'. Aguardo o link de pagamento.','system');
  return jsonb_build_object('id',o.id,'coins',o.coins,'amount_cents',o.amount_cents,'status',o.status);
end $$;
revoke all on function public.create_manual_coin_order(uuid) from public;
grant execute on function public.create_manual_coin_order(uuid) to authenticated;

create or replace function public.admin_set_manual_coin_payment_link(p_order_id uuid,p_link text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare o public.manual_coin_orders;
begin
  if not public.is_admin() then raise exception 'Acesso negado'; end if;
  if coalesce(trim(p_link),'')='' then raise exception 'Informe o link de pagamento'; end if;
  update public.manual_coin_orders
     set payment_link=trim(p_link),status=case when status in ('approved','rejected','cancelled') then status else 'payment_link_sent' end,updated_at=now()
   where id=p_order_id returning * into o;
  if o.id is null then raise exception 'Pedido não encontrado'; end if;
  insert into public.manual_coin_messages(order_id,sender_id,message,message_type)
  values(o.id,auth.uid(),'🔗 Link de pagamento: '||trim(p_link),'payment_link');
  return jsonb_build_object('ok',true,'id',o.id,'status',o.status);
end $$;
revoke all on function public.admin_set_manual_coin_payment_link(uuid,text) from public;
grant execute on function public.admin_set_manual_coin_payment_link(uuid,text) to authenticated;

create or replace function public.submit_manual_coin_proof(p_order_id uuid,p_proof_path text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare o public.manual_coin_orders;
begin
  if auth.uid() is null then raise exception 'Não autenticado'; end if;
  update public.manual_coin_orders
     set proof_path=trim(p_proof_path),status=case when status='approved' then status else 'payment_submitted' end,updated_at=now()
   where id=p_order_id and user_id=auth.uid() and status not in ('approved','rejected','cancelled')
   returning * into o;
  if o.id is null then raise exception 'Pedido não encontrado ou já finalizado'; end if;
  insert into public.manual_coin_messages(order_id,sender_id,message,message_type,media_path)
  values(o.id,auth.uid(),'📎 Comprovante de pagamento enviado. Aguardo a confirmação do administrador.','proof',trim(p_proof_path));
  return jsonb_build_object('ok',true,'id',o.id,'status',o.status);
end $$;
revoke all on function public.submit_manual_coin_proof(uuid,text) from public;
grant execute on function public.submit_manual_coin_proof(uuid,text) to authenticated;

create or replace function public.admin_approve_manual_coin_order(p_order_id uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare o public.manual_coin_orders; new_balance bigint;
begin
  if not public.is_admin() then raise exception 'Acesso negado'; end if;
  select * into o from public.manual_coin_orders where id=p_order_id for update;
  if o.id is null then raise exception 'Pedido não encontrado'; end if;
  if o.status='approved' then
    select coins into new_balance from public.profiles where id=o.user_id;
    return jsonb_build_object('ok',true,'already_approved',true,'coins',o.coins,'balance',coalesce(new_balance,0));
  end if;
  if o.status not in ('payment_submitted','payment_link_sent','pending') then raise exception 'Este pedido não pode ser aprovado no status atual'; end if;
  update public.profiles set coins=coalesce(coins,0)+o.coins where id=o.user_id returning coins into new_balance;
  if new_balance is null then raise exception 'Jogador não encontrado'; end if;
  insert into public.coin_ledger(user_id,amount,source_type,source_id,description)
  values(o.user_id,o.coins,'manual_purchase',o.id::text,'Compra manual de '||o.coins||' QuizCoins');
  update public.manual_coin_orders set status='approved',approved_at=now(),approved_by=auth.uid(),updated_at=now() where id=o.id;
  insert into public.manual_coin_messages(order_id,sender_id,message,message_type)
  values(o.id,auth.uid(),'✅ Pagamento confirmado! As '||o.coins||' QuizCoins foram liberadas na sua conta.','system');
  return jsonb_build_object('ok',true,'already_approved',false,'coins',o.coins,'balance',new_balance);
end $$;
revoke all on function public.admin_approve_manual_coin_order(uuid) from public;
grant execute on function public.admin_approve_manual_coin_order(uuid) to authenticated;

create or replace function public.admin_reject_manual_coin_order(p_order_id uuid,p_reason text default 'Pagamento não confirmado')
returns jsonb language plpgsql security definer set search_path=public as $$
declare o public.manual_coin_orders;
begin
  if not public.is_admin() then raise exception 'Acesso negado'; end if;
  update public.manual_coin_orders set status='rejected',rejection_reason=coalesce(nullif(trim(p_reason),''),'Pagamento não confirmado'),updated_at=now()
   where id=p_order_id and status<>'approved' returning * into o;
  if o.id is null then raise exception 'Pedido não encontrado ou já aprovado'; end if;
  insert into public.manual_coin_messages(order_id,sender_id,message,message_type)
  values(o.id,auth.uid(),'❌ Pedido recusado: '||o.rejection_reason,'system');
  return jsonb_build_object('ok',true,'id',o.id,'status',o.status);
end $$;
revoke all on function public.admin_reject_manual_coin_order(uuid,text) from public;
grant execute on function public.admin_reject_manual_coin_order(uuid,text) to authenticated;

-- Mantém a venda manual de Coins disponível mesmo sem o gateway automático.
update public.premium_store_settings
set coins_enabled=true, payments_enabled=true
where id=1;
