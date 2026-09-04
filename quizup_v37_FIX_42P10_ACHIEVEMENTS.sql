-- QuizUp v37 - correção do erro PostgreSQL 42P10 na carga inicial de conquistas.
-- Se a migration v37 falhou exatamente em "table \"v\" has 5 columns available but 6 columns specified",
-- execute a migration v37 corrigida do ZIP. Este arquivo é apenas uma correção segura caso as colunas/tabelas já existam.

alter table public.achievements add column if not exists code text;
alter table public.achievements add column if not exists criteria_type text;
alter table public.achievements add column if not exists threshold bigint default 1;

insert into public.achievements(title,description,icon,active,code,criteria_type,threshold)
select v.title,v.description,v.icon,true,v.code,v.criteria_type,v.threshold
from (values
 ('Primeira partida','Jogue sua primeira partida no QuizUp.','🎮','first_game','first_game',1),
 ('Primeira vitória','Vença sua primeira partida.','🥇','wins','wins',1),
 ('Veterano','Complete 10 partidas.','🎯','games','games',10),
 ('Campeão','Consiga 10 vitórias.','🏆','wins_10','wins',10),
 ('Sequência de fogo','Alcance uma sequência de 5 vitórias.','🔥','streak','streak',5),
 ('Milionário de Coins','Acumule 1.000 QuizCoins.','⚡','coins_1000','coins',1000)
) v(title,description,icon,code,criteria_type,threshold)
where not exists(select 1 from public.achievements a where a.code=v.code);

create unique index if not exists achievements_code_uidx on public.achievements(code) where code is not null;
