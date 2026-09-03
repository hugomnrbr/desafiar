# QuizUp Mobile v5 — Supabase

Versão baseada nas telas de referência, agora com estrutura para contas, administrador, perguntas com imagem, amizades, fila multiplayer, modo 2x2 e ranking.

## Configuração
1. Crie/abra seu projeto no Supabase.
2. Execute `supabase/schema.sql` no SQL Editor.
3. Edite `config.js` e coloque a URL do projeto e a publishable key.
4. Publique no GitHub Pages ou outro host HTTPS.

## Administrador
Crie uma conta pela tela de cadastro. Depois, no Table Editor > `profiles`, altere `role` dessa conta para `admin`. O botão do painel aparecerá no perfil.

## Pontuação
A pontuação solicitada foi aplicada: 10 segundos = 10 pontos; 9 = 9; ...; 1 = 1. Errada e pulada = 0.

## Recursos
- login/cadastro com Supabase Auth;
- perfil, XP, vitórias, derrotas e sequência;
- categorias;
- perguntas com 4 alternativas e imagem;
- painel administrador;
- busca de amigos pelo nome;
- solicitações de amizade;
- fila 1x1 e 2x2;
- ranking global por XP;
- histórico de resultados por categoria;
- Realtime preparado nas tabelas de fila, partidas e amizades.

### Multiplayer real-time
A versão v5 já possui matchmaking transacional por RPC, fila 1x1 e 2x2, criação de partida com 10 perguntas, sincronização por Supabase Realtime e validação da pontuação no banco. Para um MVP, isso permite testar partidas reais com várias contas/navegadores.

### Segurança
Não coloque `service_role`/secret key no navegador. O projeto usa RLS e a chave pública/publicável. O Supabase recomenda RLS nas tabelas expostas e políticas por operação.


## Multiplayer real-time (v5)

Esta versão implementa a partida online de verdade com Supabase: fila 1x1, fila 2x2 com 4 jogadores, criação transacional da partida, 10 perguntas vindas do banco, pontuação calculada no servidor pelo tempo restante, sincronização da pergunta/placar via Realtime e resultado salvo por jogador. O navegador não recebe a resposta correta para decidir a pontuação.

### Para ativar
1. No Supabase, abra **SQL Editor** e execute novamente `supabase/schema.sql` completo.
2. Confirme que há pelo menos **10 perguntas ativas em cada categoria** que você quer disponibilizar.
3. Em `config.js`, coloque a URL do projeto e a chave **publishable**.
4. Crie duas ou mais contas para testar 1x1; para 2x2, use quatro contas/janelas.
5. Publique em HTTPS/GitHub Pages.

O Realtime usa as mudanças da tabela `matches`; o Supabase documenta Postgres Changes como a opção simples e Broadcast como a opção recomendada para maior escala. Para este MVP, Postgres Changes deixa a implantação mais simples.
