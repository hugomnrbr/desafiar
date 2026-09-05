# QuizUp v40 — Referência Visual

Versão preparada para o visual do modelo enviado: fundo escuro, painéis grafite, bordas finas, dourado elétrico e azul/ciano, com o mesmo padrão aplicado ao perfil, loja, ranking, amigos, notícias, partida e painel administrativo.

## Publicação

1. Execute **somente** `QUIZUP_V40_FINAL.sql` no SQL Editor do Supabase.
2. Envie o conteúdo desta pasta para o repositório GitHub Pages.
3. Mantenha `config.js` com a URL e a chave publicável do seu projeto Supabase.
4. Não coloque `service_role`/secret key no navegador.

## Catálogo visual

- Avatares: **256 × 256 px** — PNG/JPG/WebP — até 5 MB.
- Molduras: **256 × 256 px** — SVG ou PNG transparente — até 5 MB.
- Títulos: **600 × 160 px** — PNG transparente — até 5 MB.
- Fundos de perfil: **800 × 500 px** — PNG/JPG/WebP; GIF para animado — até 8 MB.
- Emojis: **128 × 128 px** — PNG/WebP/GIF — até 3 MB.

O painel administrativo valida a resolução antes de salvar a arte. O administrador pode criar, editar, ativar/desativar, colocar/retirar da loja e excluir os cosméticos.

## Loja

As compras usam QuizCoins. Comprar um item entrega o produto ao inventário; o jogador escolhe depois o que usar. Molduras, avatares, títulos e fundos possuem ativação independente por slot.

Mercado Pago permanece **OFF** nesta versão, conforme solicitado.

## Molduras da referência

A loja inicial contém: **Fogo, Água, Terra, Ar, Trevas e Luz**, todas em 256 × 256 px e 500 QuizCoins.
