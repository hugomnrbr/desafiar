-- QuizUp v22 - criação de tópicos pelos jogadores com pacote mínimo de 10 perguntas
-- Execute DEPOIS do upgrade-v21.sql.
-- Não recrie o schema inteiro em um banco já existente.

create table if not exists public.category_submissions(
  id uuid primary key default gen_random_uuid(),
  created_by uuid not null references auth.users(id) on delete cascade,
  name text not null,
  icon text not null default '🌐',
  description text,
  questions jsonb not null default '[]'::jsonb,
  status text not null default 'pending' check(status in ('pending','approved','rejected')),
  admin_note text,
  reviewed_by uuid references auth.users(id) on delete set null,
  reviewed_at timestamptz,
  created_at timestamptz not null default now()
);

create unique index if not exists categories_name_lower_uidx on public.categories(lower(name));

create index if not exists category_submissions_status_idx on public.category_submissions(status,created_at desc);
create index if not exists category_submissions_creator_idx on public.category_submissions(created_by,created_at desc);

alter table public.category_submissions enable row level security;

drop policy if exists category_submissions_read on public.category_submissions;
drop policy if exists category_submissions_insert on public.category_submissions;

create policy category_submissions_read on public.category_submissions
for select to authenticated
using(
  created_by=(select auth.uid())
  or exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='admin')
);

create policy category_submissions_insert on public.category_submissions
for insert to authenticated
with check(created_by=(select auth.uid()));

-- O novo fluxo substitui o cadastro direto de categoria/pergunta pelo jogador.
drop policy if exists categories_user_insert on public.categories;
drop policy if exists questions_user_insert on public.questions;

-- Envia o pacote completo. A categoria e as perguntas ainda não entram no catálogo.
create or replace function public.submit_category_package(
  p_name text,
  p_icon text,
  p_description text,
  p_questions jsonb
)
returns uuid
language plpgsql
security definer
set search_path=''
as $$
declare
  uid uuid:=auth.uid();
  sid uuid;
  q jsonb;
  opts jsonb;
  i int;
  j int;
  txt text;
  val text;
  correct int;
  existing_id uuid;
  pending_count int;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  if length(trim(coalesce(p_name,'')))<2 then raise exception 'Nome da categoria inválido'; end if;
  if length(trim(coalesce(p_name,'')))>60 then raise exception 'Nome da categoria muito grande'; end if;
  if jsonb_typeof(p_questions)<>'array' then raise exception 'As perguntas devem ser uma lista'; end if;
  if jsonb_array_length(p_questions)<10 then raise exception 'A categoria precisa ter pelo menos 10 perguntas'; end if;

  select c.id into existing_id from public.categories c where lower(trim(c.name))=lower(trim(p_name)) limit 1;
  if existing_id is not null then raise exception 'Já existe uma categoria com esse nome'; end if;
  select s.id into sid from public.category_submissions s where lower(trim(s.name))=lower(trim(p_name)) and s.status='pending' limit 1;
  if sid is not null then raise exception 'Já existe uma solicitação pendente com esse nome'; end if;

  for i in 0..jsonb_array_length(p_questions)-1 loop
    q:=p_questions->i;
    txt:=trim(coalesce(q->>'question_text',''));
    opts:=q->'options';
    correct:=coalesce((q->>'correct_index')::int,-1);
    if length(txt)<3 then raise exception 'A pergunta % é inválida',i+1; end if;
    if jsonb_typeof(opts)<>'array' or jsonb_array_length(opts)<>4 then raise exception 'A pergunta % precisa ter exatamente 4 respostas',i+1; end if;
    if correct<0 or correct>3 then raise exception 'Escolha a resposta correta da pergunta %',i+1; end if;
    for j in 0..3 loop
      val:=trim(coalesce(opts->>j,''));
      if length(val)=0 then raise exception 'A resposta % da pergunta % está vazia',substring('ABCD' from j+1 for 1),i+1; end if;
    end loop;
    if lower(trim(opts->>0))=lower(trim(opts->>1)) or lower(trim(opts->>0))=lower(trim(opts->>2)) or lower(trim(opts->>0))=lower(trim(opts->>3)) or lower(trim(opts->>1))=lower(trim(opts->>2)) or lower(trim(opts->>1))=lower(trim(opts->>3)) or lower(trim(opts->>2))=lower(trim(opts->>3)) then
      raise exception 'A pergunta % precisa ter 4 respostas diferentes',i+1;
    end if;
  end loop;

  insert into public.category_submissions(created_by,name,icon,description,questions,status)
  values(uid,trim(p_name),coalesce(nullif(trim(p_icon),''),'🌐'),nullif(trim(coalesce(p_description,'')),''),p_questions,'pending')
  returning id into sid;
  return sid;
end;
$$;

grant execute on function public.submit_category_package(text,text,text,jsonb) to authenticated;

-- Lista as solicitações completas para o painel do administrador.
create or replace function public.admin_list_category_submissions()
returns table(
  id uuid,
  created_by uuid,
  name text,
  icon text,
  description text,
  questions jsonb,
  status text,
  created_at timestamptz,
  creator_username text
)
language plpgsql
security definer
set search_path=''
as $$
begin
  if not exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin') then
    raise exception 'admin only';
  end if;
  return query
  select s.id,s.created_by,s.name,s.icon,s.description,s.questions,s.status,s.created_at,
         coalesce(nullif(p.display_name,''),'Jogador')
  from public.category_submissions s
  left join public.profiles p on p.id=s.created_by
  where s.status='pending'
  order by s.created_at desc;
end;
$$;

grant execute on function public.admin_list_category_submissions() to authenticated;

-- Aprovação atômica: publica a categoria e todas as perguntas do pacote.
create or replace function public.admin_review_category_submission(
  p_submission_id uuid,
  p_approve boolean
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  uid uuid:=auth.uid();
  s public.category_submissions;
  cid uuid;
  q jsonb;
  inserted_count int:=0;
  existing_id uuid;
begin
  if not exists(select 1 from public.profiles p where p.id=uid and p.role='admin') then raise exception 'admin only'; end if;
  select * into s from public.category_submissions where id=p_submission_id for update;
  if s.id is null then raise exception 'Solicitação não encontrada'; end if;
  if s.status<>'pending' then raise exception 'Esta solicitação já foi revisada'; end if;

  if not p_approve then
    update public.category_submissions set status='rejected',reviewed_by=uid,reviewed_at=now() where id=s.id;
    return jsonb_build_object('ok',true,'status','rejected');
  end if;

  select c.id into existing_id from public.categories c where lower(trim(c.name))=lower(trim(s.name)) limit 1;
  if existing_id is not null then raise exception 'Já existe uma categoria com esse nome'; end if;
  if jsonb_array_length(s.questions)<10 then raise exception 'Pacote inválido: menos de 10 perguntas'; end if;

  insert into public.categories(name,icon,description,approved,created_by)
  values(s.name,coalesce(s.icon,'🌐'),s.description,true,s.created_by)
  returning id into cid;

  for q in select value from jsonb_array_elements(s.questions) loop
    insert into public.questions(category_id,category_name,question_text,options,correct_index,image_url,active,created_by,approval_status)
    values(cid,s.name,trim(q->>'question_text'),q->'options',(q->>'correct_index')::int,null,true,s.created_by,'approved');
    inserted_count:=inserted_count+1;
  end loop;

  update public.category_submissions set status='approved',reviewed_by=uid,reviewed_at=now() where id=s.id;
  return jsonb_build_object('ok',true,'status','approved','category_id',cid,'questions',inserted_count);
end;
$$;

grant execute on function public.admin_review_category_submission(uuid,boolean) to authenticated;

-- Notifica os administradores quando um jogador envia um novo pacote.
create or replace function public.notify_category_submission()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
declare
  actor_name text;
begin
  select coalesce(nullif(display_name,''),'Jogador') into actor_name from public.profiles where id=new.created_by;
  insert into public.notifications(recipient_id,actor_id,type,title,body,data)
  select p.id,new.created_by,'system','Novo tópico para aprovação',actor_name||' enviou o tópico "'||new.name||'" com '||jsonb_array_length(new.questions)||' perguntas.',jsonb_build_object('submission_id',new.id)
  from public.profiles p where p.role='admin';
  return new;
end;
$$;

drop trigger if exists category_submission_notification on public.category_submissions;
create trigger category_submission_notification
after insert on public.category_submissions
for each row execute procedure public.notify_category_submission();

-- Permissões necessárias ao fluxo administrativo.
grant select on public.category_submissions to authenticated;
