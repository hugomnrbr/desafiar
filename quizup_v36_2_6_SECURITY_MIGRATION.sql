-- QuizUp v36.2.6 - segurança de cadastro
-- Execute DEPOIS da migration v36.2.5.

-- Nome de usuário único, sem diferenciar maiúsculas/minúsculas.
-- Se já existirem duplicados, o índice abaixo vai informar quais precisam ser corrigidos.
create unique index if not exists profiles_username_lower_unique
on public.profiles (lower(username))
where username is not null;

-- Função usada pela tela de cadastro para impedir nomes já utilizados.
create or replace function public.is_username_available(p_username text)
returns boolean
language sql
security definer
set search_path=public
as $$
  select not exists (
    select 1 from public.profiles
    where lower(username)=lower(trim(p_username))
  );
$$;

revoke all on function public.is_username_available(text) from public;
grant execute on function public.is_username_available(text) to anon, authenticated;

-- E-mail: a tabela auth.users do Supabase já mantém o e-mail como identificador único.
-- A aplicação normaliza o e-mail para minúsculas e trata respostas de cadastro duplicado.
-- Não exponha auth.users ao navegador para fazer consultas de disponibilidade.

comment on function public.is_username_available(text) is
'Consulta segura para cadastro: retorna false quando o username já existe.';
