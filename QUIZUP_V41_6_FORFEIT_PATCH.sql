-- QuizUp v41.6 — botão DESISTIR durante a partida
-- Execute este pequeno patch no Supabase SQL Editor.
-- Não apaga contas, partidas, amizades, notícias ou histórico.

begin;

-- O Supabase já possui uma versão desta função com outro tipo de retorno.
-- PostgreSQL não permite ALTERAR o tipo de retorno via CREATE OR REPLACE,
-- então removemos somente a função e recriamos com o retorno usado pelo QuizUp.
drop function if exists public.forfeit_match(uuid);

create function public.forfeit_match(p_match_id uuid)
returns public.matches
language plpgsql
security definer
set search_path=public
as $$
declare
  m public.matches;
  new_state jsonb;
begin
  select * into m
  from public.matches
  where id=p_match_id
  for update;

  if not found then
    raise exception 'Partida não encontrada';
  end if;

  if not (auth.uid() = any(m.player_ids)) then
    raise exception 'Você não participa desta partida';
  end if;

  if m.status = 'finished' then
    return m;
  end if;

  new_state := coalesce(m.state,'{}'::jsonb)
    || jsonb_build_object(
      'forfeit_user_id', auth.uid()::text,
      'forfeit_at', now()
    );

  update public.matches
  set status='finished',
      state=new_state
  where id=p_match_id
  returning * into m;

  return m;
end;
$$;

revoke all on function public.forfeit_match(uuid) from public;
grant execute on function public.forfeit_match(uuid) to authenticated;

commit;
