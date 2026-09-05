# QuizUp v40.1 — referência visual e cosméticos

## Publicação
1. Execute **somente** `QUIZUP_V40_FINAL.sql` no SQL Editor do Supabase.
2. Depois envie **todos os arquivos desta pasta** para o repositório do GitHub.
3. Não execute outros SQLs deste pacote.

## Resoluções oficiais
- **Avatar:** 256 × 256 px. Mantenha rosto/personagem centralizado em uma área segura circular de ~176 × 176 px.
- **Moldura:** 256 × 256 px, PNG transparente ou SVG. Arte estática, sem GIF/animação. Deixe o centro transparente para o avatar.
- **Fundo de perfil:** 800 × 500 px. Estático: PNG/JPG/WebP. Animado: GIF.
- **Título:** 600 × 160 px, PNG transparente.
- **Emoji:** 128 × 128 px.
- **Emblema legado:** 128 × 128 px.

## Molduras oficiais
As seis molduras oficiais estão em `assets/store/frames/` e são estáticas:
- Fogo
- Água
- Terra
- Ar
- Trevas
- Luz

O SQL grava os caminhos relativos dessas artes para que funcionem diretamente no GitHub Pages.

## Edição administrativa
Os botões **EDITAR** dos cosméticos abrem um editor completo. É possível alterar nome, descrição, preço, promoção, validade da promoção, disponibilidade na loja e, quando aplicável, efeito, cor/fonte do título, tipo do fundo e a própria imagem respeitando a resolução obrigatória.

## Mercado Pago
Continua desativado. As compras de cosméticos usam QuizCoins já existentes na conta.
