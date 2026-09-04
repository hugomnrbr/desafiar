QuizUp Mobile v35 — GitHub Pages

# QuizUp Mobile v35 — GitHub Pages

Versão limpa para hospedagem estática no GitHub Pages.

## Estrutura

- `index.html` — entrada do aplicativo
- `app.js` — lógica do jogo
- `style.css` — layout/tema neon
- `config.js` — configuração do Supabase
- `assets/icon.svg` — ícone
- `.nojekyll` — evita processamento Jekyll no GitHub Pages

## Publicação no GitHub Pages

1. Coloque **o conteúdo desta pasta na raiz do repositório**. Não coloque a pasta `quizup-mobile-v35-github-pages` dentro de outra pasta do repositório.
2. Vá em **Settings → Pages**.
3. Em **Build and deployment**, selecione **Deploy from a branch**.
4. Escolha a branch que contém estes arquivos e a pasta `/ (root)`.
5. Salve e aguarde o GitHub Pages publicar.

Esta versão não contém workflows do GitHub Actions nem scripts de build. É um site estático e não precisa de processo de build.

## Supabase

Mantenha seu `config.js` atual se ele já estiver funcionando. As migrações SQL não são necessárias para publicar o frontend.

## v36 — 300 perguntas e perguntas com imagem
- 50 perguntas para cada categoria existente: Geral, Ciência, Entretenimento, Esportes, História e Geografia.
- Algumas perguntas demonstrativas incluem image_url.
- O criador de categoria pode escolher Somente texto ou Pergunta com imagem em cada pergunta.
- Perguntas com imagem usam image_url; nenhuma coluna nova é necessária porque o projeto já utiliza questions.image_url.
- Execute quizup_v36_300_perguntas.sql no Supabase uma única vez.

## v36.1 — Upload de imagens

Para permitir que jogadores enviem fotos nas perguntas de categorias novas:

1. Abra o Supabase → SQL Editor.
2. Execute `quizup_v36_1_storage.sql` uma única vez.
3. Isso cria o bucket público `question-images` e as políticas para usuários autenticados enviarem arquivos para a própria pasta.
4. No site, em "Criar novo tópico", escolha "Pergunta com imagem" e toque em "Escolher imagem do celular".
5. A foto é enviada automaticamente ao Supabase Storage e a URL pública é salva em `questions.image_url` através do pacote de perguntas.

Limite por imagem: 5 MB. Formatos aceitos: JPG, PNG, WEBP e GIF.
