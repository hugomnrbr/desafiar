# Q-Rival V52 — correções

Correções incluídas nesta versão:

- Painel do Administrador: abertura reforçada pelo perfil e prevenção de conflito de eventos.
- Conquistas: botão do perfil volta a abrir a tela de conquistas.
- Loja: categorias agora são derivadas também do catálogo real e, em telas pequenas, ficam visíveis em grade para não depender de rolagem horizontal.
- Torneios: tela não fica mais presa em “Carregando”; mostra carregamento, erro ou “nenhum torneio aberto” de forma distinta.
- Temporada: formulário de criação no painel passou a ter o listener de envio.
- Recompensa diária + Baú: a chave primária agora permite uma recompensa diária e um baú no mesmo dia.
- Morte Súbita: criação do código da sala não depende de `gen_random_bytes()`.

## Banco

Se você já executou o SQL V51 e está vendo os erros das telas, execute **somente** `SUPABASE_V52_CORRECOES.sql`.

Se ainda estiver fazendo instalação limpa, use o SQL completo V51 corrigido e depois não execute os patches históricos.
