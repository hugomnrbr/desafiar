# QuizUp Mobile v24

Correção do cronômetro nas partidas online e nos desafios assíncronos.

- Sincronização do relógio uma vez por rodada.
- Usa `performance.now()` depois da calibração para evitar saltos causados por polling/realtime.
- Mantém 10 segundos reais por pergunta.
- Timeout continua valendo 0 ponto.
- No modo online, a próxima pergunta continua condicionada às respostas/timeout dos dois jogadores.
- No modo assíncrono, cada jogador tem seu próprio cronômetro de 10 segundos.

Não é necessário executar nova migração do Supabase para esta correção.
