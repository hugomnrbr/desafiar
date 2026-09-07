-- QuizUp v41.13 - patch final
-- Execute no Supabase SQL Editor.
-- Inclui: reações da partida + cooldown server-side + criação/revisão de quizzes.

begin;

-- ============================================================
-- 1) REAÇÕES DURANTE A PARTIDA
-- ============================================================
create table if not exists public.match_reactions(
  id uuid primary key default gen_random_uuid(),
  match_id uuid not null references public.matches(id) on delete cascade,
  sender_id uuid not null references public.profiles(id) on delete cascade,
  emoji text not null check(char_length(emoji) between 1 and 120),
  created_at timestamptz not null default now()
);
create index if not exists match_reactions_match_created_idx on public.match_reactions(match_id,created_at desc);
create index if not exists match_reactions_sender_created_idx on public.match_reactions(sender_id,created_at desc);

alter table public.match_reactions enable row level security;
drop policy if exists "match reactions read authenticated" on public.match_reactions;
create policy "match reactions read authenticated" on public.match_reactions
for select to authenticated using (true);
drop policy if exists "match reactions insert own" on public.match_reactions;
create policy "match reactions insert own" on public.match_reactions
for insert to authenticated with check (sender_id=auth.uid());
drop policy if exists "match reactions delete own" on public.match_reactions;
create policy "match reactions delete own" on public.match_reactions
for delete to authenticated using (sender_id=auth.uid());

-- Mantém a tabela no Supabase Realtime quando permitido.
do $$
begin
  if exists(select 1 from pg_publication where pubname='supabase_realtime')
     and not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='match_reactions') then
    execute 'alter publication supabase_realtime add table public.match_reactions';
  end if;
exception when others then
  null;
end $$;

-- RPC opcional para envio server-side com intervalo mínimo de 3 segundos.
drop function if exists public.send_match_reaction(uuid,text);
create function public.send_match_reaction(p_match_id uuid,p_emoji text)
returns public.match_reactions
language plpgsql security definer set search_path=public
as $$
declare
  r public.match_reactions;
  participant boolean;
begin
  if auth.uid() is null then raise exception 'Não autenticado'; end if;
  if coalesce(trim(p_emoji),'')='' then raise exception 'Emoji inválido'; end if;
  select exists(select 1 from public.matches m where m.id=p_match_id and auth.uid()=any(m.player_ids) and m.status<>'finished') into participant;
  if not participant then raise exception 'Você não participa desta partida'; end if;
  if exists(select 1 from public.match_reactions where match_id=p_match_id and sender_id=auth.uid() and created_at>now()-interval '3 seconds') then
    raise exception 'Aguarde 3 segundos para enviar outro emoji.';
  end if;
  insert into public.match_reactions(match_id,sender_id,emoji)
  values(p_match_id,auth.uid(),trim(p_emoji))
  returning * into r;
  return r;
end;
$$;
revoke all on function public.send_match_reaction(uuid,text) from public;
grant execute on function public.send_match_reaction(uuid,text) to authenticated;

-- ============================================================
-- 2) CRIAÇÃO DE QUIZ PELO JOGADOR + REVISÃO DO ADMIN
-- ============================================================
create table if not exists public.category_submissions(
  id uuid primary key default gen_random_uuid(),
  name text not null,
  icon text not null default '🌐',
  description text,
  questions jsonb not null default '[]'::jsonb,
  created_by uuid not null references public.profiles(id) on delete cascade,
  status text not null default 'pending' check(status in ('pending','approved','rejected')),
  created_at timestamptz not null default now(),
  reviewed_at timestamptz,
  reviewed_by uuid references public.profiles(id) on delete set null
);
create index if not exists category_submissions_status_created_idx on public.category_submissions(status,created_at desc);
create index if not exists category_submissions_creator_idx on public.category_submissions(created_by,created_at desc);

alter table public.category_submissions enable row level security;
drop policy if exists "category submissions own insert" on public.category_submissions;
create policy "category submissions own insert" on public.category_submissions
for insert to authenticated with check(created_by=auth.uid());
drop policy if exists "category submissions own read" on public.category_submissions;
create policy "category submissions own read" on public.category_submissions
for select to authenticated using(created_by=auth.uid() or exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin'));

-- Remove/recria as RPCs para evitar conflitos de assinatura antigos.
drop function if exists public.submit_category_package(text,text,text,jsonb);
create function public.submit_category_package(p_name text,p_icon text,p_description text,p_questions jsonb)
returns jsonb
language plpgsql security definer set search_path=public
as $$
declare sid uuid;
begin
  if auth.uid() is null then raise exception 'Não autenticado'; end if;
  if length(trim(coalesce(p_name,'')))<2 then raise exception 'Informe um nome válido para o quiz'; end if;
  if jsonb_typeof(coalesce(p_questions,'[]'::jsonb))<>'array' or jsonb_array_length(p_questions)<>10 then raise exception 'O quiz precisa ter exatamente 10 perguntas'; end if;
  if exists(select 1 from public.category_submissions where created_by=auth.uid() and lower(name)=lower(trim(p_name)) and status='pending') then raise exception 'Você já possui um quiz com este nome aguardando revisão'; end if;
  insert into public.category_submissions(name,icon,description,questions,created_by)
  values(trim(p_name),left(coalesce(trim(p_icon),'🌐'),8),nullif(trim(coalesce(p_description,'')),''),p_questions,auth.uid())
  returning id into sid;
  return jsonb_build_object('ok',true,'id',sid);
end;
$$;
revoke all on function public.submit_category_package(text,text,text,jsonb) from public;
grant execute on function public.submit_category_package(text,text,text,jsonb) to authenticated;

drop function if exists public.admin_list_category_submissions();
create function public.admin_list_category_submissions()
returns table(id uuid,name text,icon text,description text,questions jsonb,created_at timestamptz,creator_username text)
language plpgsql security definer set search_path=public
as $$
begin
  if not exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin') then raise exception 'Acesso negado'; end if;
  return query
  select s.id,s.name,s.icon,s.description,s.questions,s.created_at,coalesce(p.username,p.display_name,'Jogador')
  from public.category_submissions s
  left join public.profiles p on p.id=s.created_by
  where s.status='pending'
  order by s.created_at desc;
end;
$$;
revoke all on function public.admin_list_category_submissions() from public;
grant execute on function public.admin_list_category_submissions() to authenticated;

drop function if exists public.admin_review_category_submission(uuid,boolean);
create function public.admin_review_category_submission(p_submission_id uuid,p_approve boolean)
returns jsonb
language plpgsql security definer set search_path=public
as $$
declare
  s public.category_submissions;
  q jsonb;
  category_id uuid;
begin
  if not exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin') then raise exception 'Acesso negado'; end if;
  select * into s from public.category_submissions where id=p_submission_id and status='pending' for update;
  if s.id is null then raise exception 'Solicitação não encontrada ou já revisada'; end if;
  if not p_approve then
    update public.category_submissions set status='rejected',reviewed_at=now(),reviewed_by=auth.uid() where id=s.id;
    return jsonb_build_object('ok',true,'status','rejected');
  end if;
  if exists(select 1 from public.categories where lower(name)=lower(s.name)) then raise exception 'Já existe uma categoria com o nome "%"',s.name; end if;
  insert into public.categories(name,icon,description,approved,created_by)
  values(s.name,coalesce(s.icon,'🌐'),s.description,true,s.created_by)
  returning id into category_id;
  for q in select value from jsonb_array_elements(s.questions) loop
    insert into public.questions(category_name,question_text,options,correct_index,image_url,created_by,approval_status,active)
    values(s.name,
           q->>'question_text',
           q->'options',
           greatest(0,least(3,coalesce((q->>'correct_index')::integer,0))),
           nullif(q->>'image_url',''),
           s.created_by,
           'approved',true);
  end loop;
  update public.category_submissions set status='approved',reviewed_at=now(),reviewed_by=auth.uid() where id=s.id;
  return jsonb_build_object('ok',true,'status','approved','category_id',category_id);
end;
$$;
revoke all on function public.admin_review_category_submission(uuid,boolean) from public;
grant execute on function public.admin_review_category_submission(uuid,boolean) to authenticated;

commit;
