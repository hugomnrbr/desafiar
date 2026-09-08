# Q-Rival v51 — Modos e Engajamento

Esta versão parte da base v50 e adiciona os modos e sistemas pedidos, mantendo as correções anteriores.

## Sistemas do jogador
- Liga semanal
- Rivais/revanche (mantido)
- Missões diárias
- Sequência/recompensa diária
- Baú gratuito diário
- Itens com raridade: comum, incomum, raro, épico, lendário e mítico
- Criador de quiz com avaliação de 1 a 5 estrelas e comentário
- Ranking de criadores
- Eventos especiais administráveis
- Morte Súbita para até 8 jogadores, com sala por código ou busca de adversários
- Reações/emoji durante partidas
- Resultado e compartilhamento voluntário (mantido)
- Conquistas (mantido)
- Perfil público (mantido)
- Loja rotativa programável
- Passe/temporada e recompensas por nível
- Torneios com máximo de 18 jogadores e quatro entradas: 100, 200, 500 e 1000 QuizCoins
- Pote do torneio acumula as entradas e o administrador define o vencedor; a função SQL transfere o pote integral ao vencedor uma única vez
- Desafio impossível com pergunta e recompensa configuráveis

## Painel Administrativo
O painel recebeu uma Central de Modos e Regras para:
- ligar/desligar cada sistema;
- configurar Morte Súbita (jogadores, perguntas, tempo);
- configurar recompensa diária e baú (incluindo chance de item raro);
- criar/publicar desafios impossíveis;
- programar itens da Loja rotativa;
- criar temporadas e recompensas por nível;
- criar eventos e missões;
- criar torneios, escolher a faixa de entrada e limitar a 18 jogadores;
- encerrar torneios e pagar o pote ao vencedor;
- administrar perguntas, categorias, conquistas e cosméticos como antes.

## Banco de dados
Execute `SUPABASE_V51_MODOS.sql` depois do SQL da versão atualmente instalada. O script usa `IF NOT EXISTS`/migrações compatíveis sempre que possível e não apaga os dados existentes.

## Observação importante
O pagamento do pote de torneio é atômico no banco. O fluxo de chave eliminatória automática de 18 jogadores não é inventado: esta versão fornece a sala/inscrição/pote e a função segura de encerramento pelo administrador. O motor de chave eliminatória automática ainda deve ser uma etapa específica antes de tratar o torneio como campeonato totalmente automático.
