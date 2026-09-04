-- QuizUp v38.6
-- Títulos: apenas nome/emoji/símbolo + efeito visual
-- Avatares: 256x256
-- Molduras: PNG 256x256 com transparência
-- Categorias: capa 800x500
-- Desafios/amigos e presença usam as estruturas existentes.

alter table if exists public.titles add column if not exists effect_style text not null default 'none';
update public.titles set effect_style='none' where effect_style is null;

alter table if exists public.categories add column if not exists cover_url text;

alter table if exists public.premium_items add column if not exists asset_width integer;
alter table if exists public.premium_items add column if not exists asset_height integer;
alter table if exists public.premium_items add column if not exists frame_inset_percent numeric(5,2);
alter table if exists public.premium_items add column if not exists frame_version text;

-- Metadados padrão para molduras já cadastradas.
update public.premium_items
set asset_width=coalesce(asset_width,256),
    asset_height=coalesce(asset_height,256),
    frame_inset_percent=coalesce(frame_inset_percent,0),
    frame_version=coalesce(frame_version,'v2')
where kind='frame';

-- Bucket usado pelo painel para capas e artes administrativas, caso ainda não exista.
insert into storage.buckets (id,name,public)
values ('admin-assets','admin-assets',true)
on conflict (id) do update set public=true;

-- Regras de efeitos permitidos nos títulos.
alter table public.titles drop constraint if exists titles_effect_style_check;
alter table public.titles add constraint titles_effect_style_check
check (effect_style in ('none','lightning','fire','gold','silver','goldmetal'));

-- Observação: resolução/formato do arquivo é validado no navegador antes do upload.
-- Isso evita aceitar molduras fora do padrão sem depender de processamento de imagem no Postgres.
