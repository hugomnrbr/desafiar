# QuizUp v18

Atualização do multiplayer:
- matchmaking serializado por usuário para impedir partidas duplicadas;
- fila mostra somente avatares, sem nomes, com no máximo 5 avatares + `...`;
- rematch direto na tela final se o adversário ainda estiver presente;
- se o adversário saiu da sala final, aparece opção para procurar outro;
- próxima pergunta agora tem uma transição de 3 segundos antes dos 10 segundos de resposta;
- pontuação perfeita ao atingir 160 pontos;
- partidas contra robô não geram XP, vitória ou derrota no ranking;
- robô espera um tempo variável antes de responder e só avança quando a resposta humana e a do robô estiverem concluídas;
- sons continuam incluídos.

## Supabase
Execute `supabase/upgrade-v18.sql` depois do `upgrade-v17.sql`.
Não apague as tabelas existentes.

## v19 - Notificações

A v19 adiciona notificações em tempo real para:
- pedido de amizade;
- desafio recebido;
- nova mensagem de amigo.

O sino no topo mostra a quantidade não lida e a página inicial também possui um atalho de notificações.

No Supabase, execute `supabase/upgrade-v19.sql` depois das migrations anteriores.
