-- QuizUp v20 - progressão e ranking por tópico, inspirado no QuizUp clássico
-- Execute DEPOIS do upgrade-v19.sql. Não precisa recriar o schema.

create or replace function public.get_topic_ranking(p_category text, p_limit int default 100)
returns table(
  id uuid,
  username text,
  display_name text,
  avatar_url text,
  topic_xp bigint,
  games bigint,
  wins bigint,
  losses bigint,
  level int,
  win_rate int
)
language sql
security definer
set search_path=''
as $$
  select
    p.id,
    p.username,
    p.display_name,
    p.avatar_url,
    coalesce(sum(g.score),0)::bigint as topic_xp,
    count(g.id)::bigint as games,
    count(*) filter (where g.won)::bigint as wins,
    count(*) filter (where not g.won)::bigint as losses,
    greatest(1,1+floor(coalesce(sum(g.score),0)/1000)::int) as level,
    case when count(g.id)=0 then 0 else round((count(*) filter(where g.won)::numeric/count(g.id))*100)::int end as win_rate
  from public.profiles p
  join public.game_results g on g.user_id=p.id and g.category=p_category
  group by p.id,p.display_name,p.avatar_url
  order by topic_xp desc, wins desc, games desc, p.display_name asc
  limit greatest(1,least(coalesce(p_limit,100),100));
$$;

grant execute on function public.get_topic_ranking(text,int) to authenticated;

-- Permite ao usuário autenticado consultar seu próprio histórico para montar
-- a progressão por tópico no cliente, sem criar uma segunda fonte de verdade.
create index if not exists game_results_user_category_idx
on public.game_results(user_id,category,created_at desc);
