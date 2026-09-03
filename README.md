# QuizUp Mobile v23 — Clássico

Versão baseada na v22, com desafios de amigos assíncronos.

## Novo na v23 — Desafio assíncrono

- Ao desafiar um amigo, a partida e as 7 perguntas são reservadas imediatamente.
- O criador pode jogar na hora, mesmo que o amigo esteja offline.
- O amigo recebe o desafio e pode jogar quando abrir o aplicativo.
- Os dois respondem as mesmas 7 perguntas na mesma ordem.
- Cada jogador tem seu próprio cronômetro de 10 segundos por pergunta.
- O cronômetro de cada jogador é baseado no horário oficial do Supabase.
- Se o tempo chegar a zero, a resposta é registrada como timeout e vale 0 pontos.
- O progresso de um jogador não muda a pergunta do outro.
- A pontuação de um jogador não é revelada como resultado final até os dois terminarem.
- O resultado só é liberado quando ambos concluírem as 7 perguntas.
- Depois da conclusão, cada jogador recebe sua vitória/derrota, XP e estatísticas uma única vez.
- A tela Amigos mostra desafios recebidos e desafios enviados.

## Supabase

Execute somente:

`supabase/upgrade-v23.sql`

Depois das migrações anteriores (v20, v21 e v22). Não execute novamente o schema inteiro em um banco já existente.

## Partida rápida

A partida rápida continua sendo o modo 1x1 online, com 7 rodadas, 10 segundos por rodada e sincronização pelo servidor.

## Categorias criadas por jogadores

A v22 continua exigindo pacote mínimo de 10 perguntas, cada uma com 4 alternativas e 1 correta, antes do envio para aprovação do administrador.
