# QuizUp v17

Correções principais:
- cronômetro multiplayer oficial de 10 segundos por rodada, usando timestamp do servidor;
- uma pergunta só avança quando todos os jogadores respondem ou o tempo acaba;
- feedback visual da resposta: verde para acerto e vermelho para erro;
- sincronização mais robusta entre Realtime, polling e estado do servidor;
- correção do abandono prematuro logo após criar um match, com janela de preparação;
- desafio entre amigos continua sincronizado para os dois jogadores;
- sons da versão anterior continuam incluídos;
- rodada clássica: 7 perguntas, sendo a 7ª bônus, máximo de 160 pontos.

## Supabase
Execute `supabase/upgrade-v17.sql` depois do `upgrade-v16.sql`.
Não é necessário apagar as tabelas existentes.
