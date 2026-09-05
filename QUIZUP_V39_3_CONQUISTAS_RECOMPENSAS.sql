-- QuizUp v39.3 — Conquistas com recompensa da Loja
-- Execute no Supabase SQL Editor depois das migrations atuais.
-- Esta correção é idempotente e pode ser executada novamente.

begin;

-- Campos usados pelo painel para escolher qualquer produto da Loja.
alter table if exists public.achievements add column if not exists reward_type text;
alter table if exists public.achievements add column if not exists reward_item_id text;

-- Recompensa automática: ao desbloquear uma conquista, entrega o produto
-- escolhido no inventário do jogador. O produto NÃO precisa estar ativo na Loja
-- para ser entregue como prêmio; ele só precisa existir no catálogo.
create or replace function public.quizup_notify_achievement()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare
  a record;
  it public.premium_items;
  title_uuid uuid;
begin
  select title, description, icon, title_id, reward_type, reward_item_id
    into a
    from public.achievements
   where id=new.achievement_id;

  -- Título configurado diretamente na conquista.
  if a.title_id is not null then
    insert into public.user_titles(user_id,title_id,is_main)
    values(new.user_id,a.title_id,false)
    on conflict(user_id,title_id) do nothing;
  end if;

  -- Produto escolhido no catálogo da Loja.
  if coalesce(trim(a.reward_item_id),'')<>'' then
    select * into it
      from public.premium_items
     where id::text=trim(a.reward_item_id)
     limit 1;

    if it.id is not null then
      insert into public.user_premium_items(user_id,item_id,active,purchased_at)
      values(new.user_id,it.id,false,now())
      on conflict(user_id,item_id) do nothing;

      -- Se o prêmio for um título baseado na tabela titles, ele também passa
      -- a constar como título disponível no inventário de títulos.
      if it.kind='title'
         and coalesce(it.source_type,'')='title'
         and coalesce(it.source_id,'')<>'' then
        begin
          title_uuid:=it.source_id::uuid;
          insert into public.user_titles(user_id,title_id,is_main)
          values(new.user_id,title_uuid,false)
          on conflict(user_id,title_id) do nothing;
        exception when others then
          -- Um item de título pode existir sem uma origem UUID válida.
          null;
        end;
      end if;
    end if;
  end if;

  insert into public.notifications(recipient_id,actor_id,type,title,body,data)
  values(
    new.user_id,
    null,
    'achievement',
    coalesce(a.icon,'🏆')||' Conquista desbloqueada',
    case
      when coalesce(trim(a.reward_item_id),'')<>'' and it.id is not null
        then coalesce(a.description,a.title)||' • 🎁 Recompensa: '||it.name
      else coalesce(a.description,a.title)
    end,
    jsonb_build_object(
      'achievement_id',new.achievement_id,
      'title_id',a.title_id,
      'reward_type',a.reward_type,
      'reward_item_id',a.reward_item_id,
      'reward_item_name',case when it.id is not null then it.name else null end
    )
  );

  return new;
end $$;

-- Garante que toda conquista desbloqueada passe pelo mecanismo acima.
drop trigger if exists trg_quizup_notify_achievement on public.user_achievements;
create trigger trg_quizup_notify_achievement
after insert on public.user_achievements
for each row execute function public.quizup_notify_achievement();

-- Reavalia conquistas após uma partida e quando Coins/vitórias/sequência mudam.
create or replace function public.quizup_check_achievements(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  a record;
  value bigint;
begin
  for a in
    select id, code, criteria_type, threshold
      from public.achievements
     where active=true and code is not null
  loop
    value:=0;

    if a.criteria_type in ('games','first_game') then
      select count(*) into value
        from public.game_results
       where user_id=p_user_id;
    elsif a.criteria_type='wins' then
      select count(*) into value
        from public.game_results
       where user_id=p_user_id and won=true;
    elsif a.criteria_type='streak' then
      select coalesce(streak,0) into value
        from public.profiles where id=p_user_id;
    elsif a.criteria_type='coins' then
      select coalesce(coins,0) into value
        from public.profiles where id=p_user_id;
    end if;

    if value >= coalesce(a.threshold,1) then
      insert into public.user_achievements(user_id,achievement_id)
      values(p_user_id,a.id)
      on conflict(user_id,achievement_id) do nothing;
    end if;
  end loop;
end $$;

revoke all on function public.quizup_check_achievements(uuid) from public;
grant execute on function public.quizup_check_achievements(uuid) to authenticated;

-- Entrega manual de uma conquista pelo painel administrativo.
create or replace function public.admin_grant_player_achievement(
  p_user_id uuid,
  p_achievement_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
begin
  if not exists(select 1 from public.profiles where id=auth.uid() and role='admin') then
    raise exception 'Acesso negado';
  end if;

  if not exists(select 1 from public.profiles where id=p_user_id) then
    raise exception 'Jogador não encontrado';
  end if;

  if not exists(select 1 from public.achievements where id=p_achievement_id) then
    raise exception 'Conquista não encontrada';
  end if;

  insert into public.user_achievements(user_id,achievement_id)
  values(p_user_id,p_achievement_id)
  on conflict(user_id,achievement_id) do nothing;

  return jsonb_build_object('ok',true,'user_id',p_user_id,'achievement_id',p_achievement_id);
end $$;
revoke all on function public.admin_grant_player_achievement(uuid,uuid) from public;
grant execute on function public.admin_grant_player_achievement(uuid,uuid) to authenticated;

-- Entrega manual de qualquer produto do catálogo pelo painel.
create or replace function public.admin_grant_player_item(
  p_user_id uuid,
  p_item_id text
)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  item_id_value text:=trim(p_item_id);
  found_item public.premium_items;
begin
  if not exists(select 1 from public.profiles where id=auth.uid() and role='admin') then
    raise exception 'Acesso negado';
  end if;

  select * into found_item
    from public.premium_items
   where id::text=item_id_value
   limit 1;

  if found_item.id is null then
    raise exception 'Item da Loja não encontrado';
  end if;

  if not exists(select 1 from public.profiles where id=p_user_id) then
    raise exception 'Jogador não encontrado';
  end if;

  insert into public.user_premium_items(user_id,item_id,active,purchased_at)
  values(p_user_id,found_item.id,false,now())
  on conflict(user_id,item_id) do nothing;

  return jsonb_build_object('ok',true,'user_id',p_user_id,'item_id',found_item.id,'item_name',found_item.name);
end $$;
revoke all on function public.admin_grant_player_item(uuid,text) from public;
grant execute on function public.admin_grant_player_item(uuid,text) to authenticated;

commit;

-- Conferência:
select id,title,criteria_type,threshold,reward_type,reward_item_id,active
from public.achievements
order by created_at desc;
