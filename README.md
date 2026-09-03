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
