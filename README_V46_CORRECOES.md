# Q-Rival v46 — correções finais

## Corrigido
- Modal **Nova publicação** fica acima do menu inferior no celular e possui área segura para o botão PUBLICAR.
- Perfil e adversário na partida usam cards simétricos e o mesmo tamanho de avatar.
- Botão/bolinha discreta **QUIZ** fica disponível no computador e celular e abre diretamente **Categorias**.
- Rodadas da partida agora usam **20 segundos**.
- Pontuação correta por tempo restante:
  - 20–18s = 20 pontos
  - 17–15s = 18 pontos
  - 14–12s = 16 pontos
  - 11–9s = 14 pontos
  - 8–6s = 12 pontos
  - 5–3s = 10 pontos
  - 2–1s = 8 pontos
  - 0s = 0 pontos
- Conquistas passaram a ser verificadas depois da atualização do resultado e existe uma rotina v2 para liberar conquistas por vitórias, partidas, sequência, Coins e primeira partida.

## Supabase
Execute `SUPABASE_V46_CONQUISTAS.sql` no SQL Editor. A função de pontuação é disponibilizada para o backend existente sem substituir a RPC de partida atual.
