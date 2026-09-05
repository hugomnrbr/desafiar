-- QuizUp v39.2 — CORREÇÃO DO CATÁLOGO DE EXEMPLO
-- Execute este arquivo no Supabase DEPOIS das migrations anteriores.
-- Corrige a constraint de efeito dos títulos e cria 3 itens de cada tipo:
-- 3 avatares + 3 emblemas + 3 títulos + 3 fundos.
-- Todos ficam ativos, compráveis e utilizáveis.

begin;

-- 1) Garantir colunas usadas pelo catálogo
alter table if exists public.titles add column if not exists asset_url text;
alter table if exists public.titles add column if not exists asset_type text;
alter table if exists public.titles add column if not exists effect_style text;
alter table if exists public.titles add column if not exists title_color text not null default '#ffd21a';
alter table if exists public.titles add column if not exists title_font text not null default 'Inter';
alter table if exists public.titles add column if not exists asset_width integer;
alter table if exists public.titles add column if not exists asset_height integer;

alter table if exists public.badges add column if not exists asset_url text;
alter table if exists public.badges add column if not exists asset_type text;

alter table if exists public.premium_items add column if not exists description text;
alter table if exists public.premium_items add column if not exists price_cents bigint;
alter table if exists public.premium_items add column if not exists price_coins bigint;
alter table if exists public.premium_items add column if not exists promo_price_cents bigint;
alter table if exists public.premium_items add column if not exists promo_price_coins bigint;
alter table if exists public.premium_items add column if not exists promo_active boolean not null default false;
alter table if exists public.premium_items add column if not exists promo_expires_at timestamptz;
alter table if exists public.premium_items add column if not exists icon text;
alter table if exists public.premium_items add column if not exists asset_url text;
alter table if exists public.premium_items add column if not exists asset_type text;
alter table if exists public.premium_items add column if not exists effect_style text;
alter table if exists public.premium_items add column if not exists kind text;
alter table if exists public.premium_items add column if not exists source_type text;
alter table if exists public.premium_items add column if not exists source_id text;
alter table if exists public.premium_items add column if not exists active boolean not null default true;
alter table if exists public.premium_items add column if not exists created_by uuid;

-- 2) Corrigir de forma segura a constraint que causou o erro 23514.
alter table if exists public.titles drop constraint if exists titles_effect_style_check;
alter table if exists public.titles add constraint titles_effect_style_check
check (effect_style is null or effect_style in
('none','fire','water','earth','air','lightning','darkness','light','gold','silver','bronze','vip','diamond','ruby','emerald'));

alter table if exists public.premium_items drop constraint if exists premium_items_effect_style_check;
alter table if exists public.premium_items add constraint premium_items_effect_style_check
check (effect_style is null or effect_style in
('none','fire','water','earth','air','lightning','darkness','light','gold','silver','bronze','vip','diamond','ruby','emerald'));

-- 3) Garantir categorias novas/limpas.
insert into public.store_categories(name,description,icon,sort_order,active)
values
('Avatares','Avatares oficiais do novo estilo QuizUp.','👤',1,true),
('Emblemas','Emblemas animados que acompanham o perfil.','🏅',2,true),
('Títulos','Títulos PNG 600 × 160 com efeito configurável.','🏷️',3,true),
('Fundos de Perfil','Fundos 800 × 500 para o perfil.','🖼️',4,true)
on conflict(name) do update set description=excluded.description,icon=excluded.icon,sort_order=excluded.sort_order,active=true;

-- 4) Remover SOMENTE os cosméticos antigos.
-- Não remove conquistas, partidas, perguntas ou contas.
delete from public.user_premium_items
where item_id in (select id from public.premium_items where kind in ('avatar','badge','title','background'));

update public.profiles set premium_avatar=null where premium_avatar is not null;
update public.profiles set premium_badge=null where premium_badge is not null;
update public.profiles set premium_background=null where premium_background is not null;
update public.profiles set premium_title=null where premium_title is not null;

-- Títulos de loja antigos também deixam de existir.
delete from public.user_titles;
update public.profiles set main_title_id=null where main_title_id is not null;

-- Limpar vínculos de conquistas antes de apagar títulos antigos.
update public.achievements set title_id=null where title_id is not null;

delete from public.premium_items where kind in ('avatar','badge','title','background');
delete from public.badges;
delete from public.titles;

-- 5) Criar os 3 TÍTULOS de exemplo.
-- PNG padrão: 600 × 160.
insert into public.titles
(id,name,description,icon,active,effect_style,asset_url,asset_type,title_color,title_font,asset_width,asset_height)
values
('11111111-1111-4111-8111-111111111111','Campeão','Título personalizado de exemplo.','',true,'fire','assets/store/titles/campeao.png','png','#ffd21a','Inter',600,160),
('22222222-2222-4222-8222-222222222222','Mestre','Título personalizado de exemplo.','',true,'water','assets/store/titles/mestre.png','png','#ffd21a','Inter',600,160),
('33333333-3333-4333-8333-333333333333','Lendário','Título personalizado de exemplo.','',true,'darkness','assets/store/titles/lenda.png','png','#ffd21a','Inter',600,160);

insert into public.premium_items
(id,name,category,description,price_cents,price_coins,promo_active,icon,effect_style,asset_url,asset_type,kind,source_type,source_id,active,created_by)
values
('title-11111111-1111-4111-8111-111111111111','Campeão','Títulos','PNG 600 × 160 com efeito de fogo ao redor.',750,750,false,'','fire','assets/store/titles/campeao.png','png','title','title','11111111-1111-4111-8111-111111111111',true,null),
('title-22222222-2222-4222-8222-222222222222','Mestre','Títulos','PNG 600 × 160 com efeito de água ao redor.',750,750,false,'','water','assets/store/titles/mestre.png','png','title','title','22222222-2222-4222-8222-222222222222',true,null),
('title-33333333-3333-4333-8333-333333333333','Lendário','Títulos','PNG 600 × 160 com efeito das trevas ao redor.',900,900,false,'','darkness','assets/store/titles/lenda.png','png','title','title','33333333-3333-4333-8333-333333333333',true,null);

-- 6) Criar os 3 EMBLEMAS de exemplo.
insert into public.badges
(id,name,description,icon,asset_url,asset_type,active)
values
('44444444-4444-4444-8444-444444444444','Emblema de Fogo','Efeito animado de fogo ao redor do avatar.','🔥','assets/store/emblems/fire.svg','svg',true),
('55555555-5555-4555-8555-555555555555','Emblema de Água','Efeito animado de água ao redor do avatar.','💧','assets/store/emblems/water.svg','svg',true),
('66666666-6666-4666-8666-666666666666','Emblema Galáxia','Efeito animado de energia/galáxia ao redor do avatar.','🌌','assets/store/emblems/galaxy.svg','svg',true);

insert into public.premium_items
(id,name,category,description,price_cents,price_coins,promo_active,icon,effect_style,asset_url,asset_type,kind,source_type,source_id,active,created_by)
values
('badge-44444444-4444-4444-8444-444444444444','Emblema de Fogo','Emblemas','Animação de fogo ao redor do perfil do jogador.',650,650,false,'🔥','fire','assets/store/emblems/fire.svg','svg','badge','badge','44444444-4444-4444-8444-444444444444',true,null),
('badge-55555555-5555-4555-8555-555555555555','Emblema de Água','Emblemas','Animação de água ao redor do perfil do jogador.',650,650,false,'💧','water','assets/store/emblems/water.svg','svg','badge','badge','55555555-5555-4555-8555-555555555555',true,null),
('badge-66666666-6666-4666-8666-666666666666','Emblema Galáxia','Emblemas','Animação de energia/galáxia ao redor do perfil do jogador.',750,750,false,'🌌','darkness','assets/store/emblems/galaxy.svg','svg','badge','badge','66666666-6666-4666-8666-666666666666',true,null);

-- 7) Criar os 3 AVATARES de exemplo.
insert into public.premium_items
(id,name,category,description,price_cents,price_coins,promo_active,icon,effect_style,asset_url,asset_type,kind,source_type,source_id,active,created_by)
values
('avatar-77777777-7777-4777-8777-777777777777','Avatar Neon','Avatares','Avatar oficial Neon.',500,500,false,'👤','none','assets/store/avatars/neon.png','png','avatar','avatar','77777777-7777-4777-8777-777777777777',true,null),
('avatar-88888888-8888-4888-8888-888888888888','Avatar Cósmico','Avatares','Avatar oficial Cósmico.',500,500,false,'👤','none','assets/store/avatars/cosmic.png','png','avatar','avatar','88888888-8888-4888-8888-888888888888',true,null),
('avatar-99999999-9999-4999-8999-999999999999','Avatar Sombra','Avatares','Avatar oficial Sombra.',600,600,false,'👤','none','assets/store/avatars/shadow.png','png','avatar','avatar','99999999-9999-4999-8999-999999999999',true,null);

-- 8) Criar os 3 FUNDOS de exemplo.
insert into public.premium_items
(id,name,category,description,price_cents,price_coins,promo_active,icon,effect_style,asset_url,asset_type,kind,source_type,source_id,active,created_by)
values
('background-aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','Aurora','Fundos de Perfil','Fundo de perfil oficial 800 × 500.',400,400,false,'🖼️','none','assets/store/backgrounds/aurora.png','png','background','background','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',true,null),
('background-bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','Nebulosa','Fundos de Perfil','Fundo de perfil oficial 800 × 500.',400,400,false,'🖼️','none','assets/store/backgrounds/nebula.png','png','background','background','bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',true,null),
('background-cccccccc-cccc-4ccc-8ccc-cccccccccccc','Cyber Night','Fundos de Perfil','Fundo de perfil oficial 800 × 500.',450,450,false,'🖼️','none','assets/store/backgrounds/cyber.png','png','background','background','cccccccc-cccc-4ccc-8ccc-cccccccccccc',true,null);

-- 9) Garantir que os 12 exemplos estejam ativos.
update public.premium_items set active=true
where id in (
 'title-11111111-1111-4111-8111-111111111111','title-22222222-2222-4222-8222-222222222222','title-33333333-3333-4333-8333-333333333333',
 'badge-44444444-4444-4444-8444-444444444444','badge-55555555-5555-4555-8555-555555555555','badge-66666666-6666-4666-8666-666666666666',
 'avatar-77777777-7777-4777-8777-777777777777','avatar-88888888-8888-4888-8888-888888888888','avatar-99999999-9999-4999-8999-999999999999',
 'background-aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','background-bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','background-cccccccc-cccc-4ccc-8ccc-cccccccccccc'
);
update public.badges set active=true where id in ('44444444-4444-4444-8444-444444444444','55555555-5555-4555-8555-555555555555','66666666-6666-4666-8666-666666666666');
update public.titles set active=true where id in ('11111111-1111-4111-8111-111111111111','22222222-2222-4222-8222-222222222222','33333333-3333-4333-8333-333333333333');

commit;

-- VERIFICAÇÃO: deve retornar exatamente 12 itens.
select id,name,category,kind,price_coins,asset_url,active
from public.premium_items
where id in (
 'title-11111111-1111-4111-8111-111111111111','title-22222222-2222-4222-8222-222222222222','title-33333333-3333-4333-8333-333333333333',
 'badge-44444444-4444-4444-8444-444444444444','badge-55555555-5555-4555-8555-555555555555','badge-66666666-6666-4666-8666-666666666666',
 'avatar-77777777-7777-4777-8777-777777777777','avatar-88888888-8888-4888-8888-888888888888','avatar-99999999-9999-4999-8999-999999999999',
 'background-aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','background-bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','background-cccccccc-cccc-4ccc-8ccc-cccccccccccc'
)
order by category,name;
