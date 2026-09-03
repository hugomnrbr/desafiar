-- QuizUp v7 - categorias/subcategorias, conteúdo enviado por usuários e conquistas
-- Execute DEPOIS do schema-v6.sql no SQL Editor do Supabase.

-- =========================================================
-- 1. CATEGORIAS: subcategorias, aprovação e autor
-- =========================================================
alter table public.categories add column if not exists parent_id uuid references public.categories(id) on delete set null;
alter table public.categories add column if not exists approved boolean not null default true;
alter table public.categories add column if not exists created_by uuid references auth.users(id) on delete set null;

update public.categories set approved=true where approved is null;
create index if not exists categories_parent_idx on public.categories(parent_id);
create index if not exists categories_approved_idx on public.categories(approved,name);

-- =========================================================
-- 2. PERGUNTAS: aprovação
-- =========================================================
alter table public.questions add column if not exists approval_status text not null default 'approved';
update public.questions set approval_status='approved' where approval_status is null or approval_status='';
alter table public.questions drop constraint if exists questions_approval_status_check;
alter table public.questions add constraint questions_approval_status_check check(approval_status in ('pending','approved','rejected'));
create index if not exists questions_approval_idx on public.questions(approval_status,active,category_name);
create index if not exists questions_created_by_idx on public.questions(created_by);

-- =========================================================
-- 3. CONQUISTAS
-- =========================================================
create table if not exists public.achievements(
  id uuid primary key default gen_random_uuid(),
  title text not null unique,
  description text,
  icon text default '🏆',
  active boolean not null default true,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);
create index if not exists achievements_active_idx on public.achievements(active,created_at);

-- Conquistas iniciais do jogo, sem duplicar as existentes.
insert into public.achievements(title,description,icon,active)
values
('Primeira Vitória','Vença sua primeira partida.','🏆',true),
('Sequência de 3','Vença 3 partidas seguidas.','🔥',true),
('Rápido no Gatilho','Responda perguntas rapidamente.','⚡',true)
on conflict(title) do nothing;

-- =========================================================
-- 4. RLS / PERMISSÕES
-- =========================================================
alter table public.categories enable row level security;
alter table public.questions enable row level security;
alter table public.achievements enable row level security;

-- Categorias: todos autenticados veem apenas aprovadas; admin vê todas.
drop policy if exists categories_read on public.categories;
drop policy if exists categories_admin_insert on public.categories;
drop policy if exists categories_admin_update on public.categories;
drop policy if exists categories_admin_delete on public.categories;
drop policy if exists categories_user_insert on public.categories;

create policy categories_read on public.categories
for select to authenticated
using(
  approved=true
  or created_by=(select auth.uid())
  or exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='admin')
);

create policy categories_admin_insert on public.categories
for insert to authenticated
with check(
  approved=true
  and exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='admin')
);

create policy categories_user_insert on public.categories
for insert to authenticated
with check(
  approved=false
  and created_by=(select auth.uid())
);

create policy categories_admin_update on public.categories
for update to authenticated
using(exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='admin'))
with check(exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='admin'));

create policy categories_admin_delete on public.categories
for delete to authenticated
using(exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='admin'));

-- Perguntas: jogadores só veem aprovadas/ativas, ou suas próprias pendentes; admin vê tudo.
drop policy if exists questions_read on public.questions;
drop policy if exists questions_admin_insert on public.questions;
drop policy if exists questions_admin_update on public.questions;
drop policy if exists questions_admin_delete on public.questions;
drop policy if exists questions_user_insert on public.questions;

create policy questions_read on public.questions
for select to authenticated
using(
  (active=true and approval_status='approved')
  or created_by=(select auth.uid())
  or exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='admin')
);

create policy questions_admin_insert on public.questions
for insert to authenticated
with check(
  approval_status='approved'
  and active=true
  and exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='admin')
);

create policy questions_user_insert on public.questions
for insert to authenticated
with check(
  approval_status='pending'
  and active=false
  and created_by=(select auth.uid())
);

create policy questions_admin_update on public.questions
for update to authenticated
using(exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='admin'))
with check(exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='admin'));

create policy questions_admin_delete on public.questions
for delete to authenticated
using(exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='admin'));

-- Conquistas: usuários veem apenas publicadas/ativas; somente admin cria/edita/exclui.
drop policy if exists achievements_read on public.achievements;
drop policy if exists achievements_admin_insert on public.achievements;
drop policy if exists achievements_admin_update on public.achievements;
drop policy if exists achievements_admin_delete on public.achievements;

create policy achievements_read on public.achievements
for select to authenticated
using(active=true or exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='admin'));

create policy achievements_admin_insert on public.achievements
for insert to authenticated
with check(exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='admin'));

create policy achievements_admin_update on public.achievements
for update to authenticated
using(exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='admin'))
with check(exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='admin'));

create policy achievements_admin_delete on public.achievements
for delete to authenticated
using(exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='admin'));

-- Permissões necessárias ao cliente.
grant select on public.achievements to authenticated;
grant insert on public.achievements to authenticated;
grant update,delete on public.achievements to authenticated;
grant select,insert on public.categories to authenticated;
grant update,delete on public.categories to authenticated;
grant select,insert on public.questions to authenticated;
grant update,delete on public.questions to authenticated;

notify pgrst, 'reload schema';
