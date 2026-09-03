# QuizUp Mobile v26

Correção definitiva do cronômetro e feedback das respostas.

## O que foi corrigido
- Partida online: cronômetro oficial 10→9→...→0 sem reinicialização pelo polling/realtime.
- Partida online: a próxima pergunta começa imediatamente depois que os dois jogadores respondem ou atingem 0.
- Partida assíncrona: cada jogador usa seu próprio `player_started_at`; o relógio do outro jogador nunca interfere.
- Não há mais substituição do relógio assíncrono pelo `question_started_at` da partida online.
- Resposta correta fica verde e errada fica vermelha, com proteção contra eventos Realtime que poderiam apagar o feedback.
- O countdown 3→2→1 permanece apenas na entrada da partida; não é usado entre rodadas.

## Supabase
Execute `supabase/upgrade-v26.sql` depois das migrações anteriores.
Não execute `schema.sql` novamente.
