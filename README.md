# QuizUp Mobile v16

Versão baseada na v15 com:
- Login real via Supabase.
- Multiplayer 1x1 e 2x2.
- 7 rodadas, 10 segundos e pontuação estilo QuizUp clássico.
- Sons e controle de áudio.
- Matchmaking com presença real.
- Chat entre amigos com emoji e foto.
- Desafios entre amigos com seleção de categoria.
- **Abandono de partida:** se um jogador sair da aba/app durante match ou countdown, a partida é encerrada e os demais vencem.
- **Presença por heartbeat:** se beforeunload/pagehide não forem executados pelo navegador, o adversário detecta ausência após alguns segundos e encerra a partida.
- **Desafios sincronizados:** quando o amigo aceita, o desafiante recebe a partida em tempo real e ambos entram no countdown 3-2-1.

## Supabase
Execute, na ordem, somente as migrations que ainda não estiverem aplicadas. Para esta atualização, execute:

`supabase/upgrade-v16.sql`

A v16 pressupõe as estruturas das versões anteriores, incluindo v13/v15.
