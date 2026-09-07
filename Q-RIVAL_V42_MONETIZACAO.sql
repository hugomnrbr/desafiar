-- Q-Rival v42 — monetização sem anúncios
-- Execute DEPOIS do QUIZUP_V41_13_FINAL_PATCH.sql e do QUIZUP_V40_FINAL_LIMPO.sql

begin;

alter table public.profiles add column if not exists premium_pass_until timestamptz;
alter table public.user_premium_items add column if not exists expires_at timestamptz;

-- Ativa a camada de pagamentos, mas continua sem publicidade.
insert into public.premium_store_settings(id,enabled,cosmetics_enabled,vip_enabled,coins_enabled,pass_enabled,payments_enabled)
values(1,true,true,true,true,true,true)
on conflict(id) do update set
 enabled=true, cosmetics_enabled=true, vip_enabled=true, coins_enabled=true, pass_enabled=true, payments_enabled=true;

-- Categorias comerciais.
insert into public.store_categories(name,description,icon,sort_order,active)
values
 ('VIP','Benefícios permanentes e identidade VIP.','👑',10,true),
 ('Passe','Passe de temporada com benefícios por 30 dias.','🎟️',11,true),
 ('Moedas','Pacotes de QuizCoins pagos com dinheiro real.','⚡',12,true)
on conflict(name) do update set active=true,description=excluded.description,icon=excluded.icon,sort_order=excluded.sort_order;

-- Produtos iniciais. O administrador poderá editar/remover depois.
insert into public.premium_items(
 id,name,category,description,price_cents,price_coins,promo_active,icon,effect_style,kind,source_type,source_id,active
) values
 ('qrvip-permanente','Q-Rival VIP','VIP','VIP permanente: +25% de XP nas vitórias, identificação VIP e acesso aos benefícios VIP.',2490,2490,false,'👑','vip','vip','vip','qrvip-permanente',true),
 ('qrpass-s1','Passe de Temporada — S1','Passe','Passe da temporada: +10% de XP e benefícios exclusivos durante 30 dias.',1490,1490,false,'🎟️','gold','pass','pass','qrpass-s1',true),
 ('qrtitle-champion','Título Campeão','Títulos','Título exclusivo para destacar seu perfil.',790,790,false,'🏆','gold','title','title',null,true)
on conflict(id) do update set
 name=excluded.name,category=excluded.category,description=excluded.description,
 price_cents=excluded.price_cents,price_coins=excluded.price_coins,icon=excluded.icon,
 effect_style=excluded.effect_style,kind=excluded.kind,source_type=excluded.source_type,active=true;

-- Compra segura: Pass recebe validade de 30 dias.
drop function if exists public.purchase_premium_item(text,bigint);
create function public.purchase_premium_item(p_item_id text,p_expected_price bigint default null)
returns jsonb language plpgsql security definer set search_path=public as $$
declare
  it public.premium_items; charge bigint; bal bigint; promo_ok boolean; already boolean; category_on boolean:=true;
  expires timestamptz;
begin
  if auth.uid() is null then raise exception 'Não autenticado'; end if;
  select * into it from public.premium_items where id::text=trim(p_item_id) and active=true limit 1;
  if it.id is null then raise exception 'Item não encontrado ou indisponível'; end if;
  if it.category='VIP' then category_on:=coalesce((select vip_enabled from public.premium_store_settings where id=1),true);
  elsif it.category='Moedas' then category_on:=coalesce((select coins_enabled and payments_enabled from public.premium_store_settings where id=1),false);
  elsif it.category='Passe' then category_on:=coalesce((select pass_enabled from public.premium_store_settings where id=1),true);
  else category_on:=coalesce((select cosmetics_enabled from public.premium_store_settings where id=1),true);
  end if;
  if not coalesce((select enabled from public.premium_store_settings where id=1),true) or not category_on then raise exception 'As compras desta categoria estão desativadas'; end if;
  promo_ok:=coalesce(it.promo_active,false) and coalesce(it.promo_price_coins,0)>0 and coalesce(it.promo_price_coins,0)<coalesce(it.price_coins,0) and (it.promo_expires_at is null or it.promo_expires_at>now());
  charge:=case when promo_ok then it.promo_price_coins else coalesce(it.price_coins,it.price_cents,0) end;
  if p_expected_price is not null and p_expected_price<>charge then raise exception 'O preço do item mudou. Atualize a loja e tente novamente.'; end if;
  select exists(select 1 from public.user_premium_items where user_id=auth.uid() and item_id=it.id and (expires_at is null or expires_at>now())) into already;
  if not already then
    update public.profiles set coins=coalesce(coins,0)-charge where id=auth.uid() and coalesce(coins,0)>=charge returning coins into bal;
    if bal is null then raise exception 'Você não possui QuizCoins suficientes'; end if;
    expires:=case when it.kind='pass' then now()+interval '30 days' else null end;
    if exists(select 1 from public.user_premium_items where user_id=auth.uid() and item_id=it.id) then
      update public.user_premium_items set purchased_at=now(),expires_at=expires,active=false where user_id=auth.uid() and item_id=it.id;
    else
      insert into public.user_premium_items(user_id,item_id,active,purchased_at,expires_at) values(auth.uid(),it.id,false,now(),expires);
    end if;
    insert into public.coin_ledger(user_id,amount,source_type,source_id,description) values(auth.uid(),-charge,'premium_purchase',gen_random_uuid()::text,'Compra: '||coalesce(it.name,'Item'));
    if it.kind='pass' then update public.profiles set premium_pass_until=expires where id=auth.uid(); end if;
  else
    select coins into bal from public.profiles where id=auth.uid();
  end if;
  return jsonb_build_object('ok',true,'already_owned',already,'balance',coalesce(bal,0),'charge',case when already then 0 else charge end,'item_id',it.id,'kind',it.kind,'expires_at',case when it.kind='pass' then coalesce(expires,(select expires_at from public.user_premium_items where user_id=auth.uid() and item_id=it.id)) else null end);
end $$;
revoke all on function public.purchase_premium_item(text,bigint) from public;
grant execute on function public.purchase_premium_item(text,bigint) to authenticated;

-- Ativação com validade para o Passe.
drop function if exists public.activate_premium_item(text);
create function public.activate_premium_item(p_item_id text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare it public.premium_items; bal bigint; title_uuid uuid; expires timestamptz;
begin
  if auth.uid() is null then raise exception 'Não autenticado'; end if;
  select * into it from public.premium_items where id::text=trim(p_item_id) limit 1;
  if it.id is null then raise exception 'Item não encontrado'; end if;
  select expires_at into expires from public.user_premium_items where user_id=auth.uid() and item_id=it.id and (expires_at is null or expires_at>now());
  if not exists(select 1 from public.user_premium_items where user_id=auth.uid() and item_id=it.id and (expires_at is null or expires_at>now())) then raise exception 'Você ainda não possui este item ativo'; end if;
  if it.kind='pass' then
    update public.profiles set premium_pass_until=coalesce(expires,now()+interval '30 days') where id=auth.uid();
  elsif it.kind='vip' then
    update public.profiles set premium_vip=true where id=auth.uid();
  elsif it.kind='frame' then update public.profiles set premium_frame=it.id::text where id=auth.uid();
  elsif it.kind='avatar' then update public.profiles set premium_avatar=it.id::text where id=auth.uid();
  elsif it.kind='effect' then update public.profiles set premium_effect=it.id::text where id=auth.uid();
  elsif it.kind='theme' then update public.profiles set premium_theme=it.id::text where id=auth.uid();
  elsif it.kind='background' then update public.profiles set premium_background=it.id::text where id=auth.uid();
  elsif it.kind='badge' then update public.profiles set premium_badge=it.id::text where id=auth.uid();
  elsif it.kind='title' then
    update public.profiles set premium_title=it.id::text where id=auth.uid();
  end if;
  update public.user_premium_items set active=true where user_id=auth.uid() and item_id=it.id;
  select coins into bal from public.profiles where id=auth.uid();
  return jsonb_build_object('ok',true,'item_id',it.id,'kind',it.kind,'balance',coalesce(bal,0),'expires_at',expires);
end $$;
revoke all on function public.activate_premium_item(text) from public;
grant execute on function public.activate_premium_item(text) to authenticated;

-- Reforça os pacotes comerciais padrão.
insert into public.coin_packages(name,coins,price_cents,active,sort_order)
select v.name,v.coins,v.price_cents,true,v.sort_order from (values
 ('1.000 QuizCoins',1000,499,1),
 ('2.500 QuizCoins',2500,999,2),
 ('6.000 QuizCoins',6000,1999,3),
 ('15.000 QuizCoins',15000,3999,4)
) v(name,coins,price_cents,sort_order)
where not exists(select 1 from public.coin_packages cp where cp.coins=v.coins and cp.price_cents=v.price_cents);

commit;
