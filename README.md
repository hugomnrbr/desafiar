# QuizUp Mobile v20 — clássico

Esta versão parte do projeto **v19 (notificações)** e aproxima a experiência do QuizUp clássico mostrado no vídeo de referência enviado pelo usuário.

## Principais mudanças
- visual clássico: cabeçalho vermelho, áreas sociais claras e partida em tela preta;
- navegação inferior com botão central de jogo;
- Home inspirada no perfil/feed do QuizUp antigo;
- tópicos com ícones, nível individual e tela própria do tópico;
- progressão por tópico baseada nos pontos das partidas;
- ranking por tópico + ranking global;
- perfil com tópicos mais jogados e estatísticas;
- partida clássica 1x1, 7 rodadas, 10 segundos e pontuação até 160;
- respostas grandes com feedback visual;
- tela de resultados com gráfico de evolução da pontuação;
- bot continua disponível somente como alternativa depois da busca real;
- 2x2 e power-ups deixam de aparecer na interface principal para manter o modo clássico;
- amigos, desafios, chat, fotos, notificações e conquistas continuam funcionando;
- administração de perguntas/categorias/conquistas continua funcionando.

## Supabase — atualização obrigatória
A estrutura existente não deve ser apagada.

Execute as migrations na ordem que ainda não tiver executado. Para quem já estava no **v19**, execute apenas:

`supabase/upgrade-v20.sql`

A migration v20 cria a função `get_topic_ranking`, usada para o ranking de cada tópico.

## Partida clássica
- 7 rodadas;
- 10 segundos por rodada;
- rodadas 1–6: até 20 pontos;
- rodada 7: até 40 pontos;
- máximo: 160 pontos;
- velocidade de resposta influencia a pontuação;
- resultado mostra comparação e gráfico.

## Referência visual
O acabamento foi ajustado usando o vídeo de referência fornecido, especialmente:
- barra superior vermelha nas áreas sociais;
- perfil com capa, foto, números e atividade;
- grade de tópicos;
- tela preta durante o quiz;
- linhas amarelas laterais na área da pergunta;
- respostas claras em blocos;
- resultado com placar, XP e gráfico;
- ações de Jogar / Chat / Publicar.

Os elementos gráficos foram recriados em HTML/CSS/SVG; o projeto não depende de copiar os arquivos gráficos do aplicativo original.
