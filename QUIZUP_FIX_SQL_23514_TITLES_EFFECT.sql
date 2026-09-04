-- QuizUp v39.0.3 — correção do erro 23514 em titles_effect_style_check
-- Execute este SQL ANTES de executar a migration completa, caso a migration
-- tenha parado no constraint titles_effect_style_check.

alter table if exists public.titles add column if not exists effect_style text not null default 'none';

update public.titles
set effect_style = lower(trim(coalesce(effect_style,'none')));

update public.titles
set effect_style = 'none'
where effect_style not in ('none','fire','water','earth','air','lightning','darkness','light','gold','silver','bronze','vip','diamond','ruby','emerald');

alter table if exists public.titles drop constraint if exists titles_effect_style_check;
alter table if exists public.titles add constraint titles_effect_style_check
check (effect_style in ('none','fire','water','earth','air','lightning','darkness','light','gold','silver','bronze','vip','diamond','ruby','emerald'));

alter table if exists public.premium_items add column if not exists effect_style text not null default 'none';
update public.premium_items set effect_style = lower(trim(coalesce(effect_style,'none')));
update public.premium_items
set effect_style = 'none'
where effect_style not in ('none','fire','water','earth','air','lightning','darkness','light','gold','silver','bronze','vip','diamond','ruby','emerald');
alter table if exists public.premium_items drop constraint if exists premium_items_effect_style_check;
alter table if exists public.premium_items add constraint premium_items_effect_style_check
check (effect_style in ('none','fire','water','earth','air','lightning','darkness','light','gold','silver','bronze','vip','diamond','ruby','emerald'));

-- Conferência rápida:
select effect_style, count(*) from public.titles group by effect_style order by effect_style;
