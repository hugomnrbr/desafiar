# Q-Rival v42 — monetização sem anúncios

Base: Q-Rival v41.13 Final.

## O que foi adicionado
- Loja comercial com QuizCoins.
- Compra de QuizCoins com Mercado Pago Checkout Pro.
- Webhook server-side para confirmar pagamentos e creditar moedas somente após validação do pagamento.
- VIP permanente vendido na Loja.
- Passe de Temporada com validade de 30 dias.
- Passe concede +10% de XP; VIP continua com +25% de XP nas vitórias.
- Produtos/cosméticos continuam sendo comprados com QuizCoins.
- Área administrativa para ativar/desativar Mercado Pago, VIP, Passe, Coins e cosméticos.
- Pacotes iniciais de QuizCoins: 1.000 por R$ 4,99; 2.500 por R$ 9,99; 6.000 por R$ 19,99; 15.000 por R$ 39,99.
- Nenhum anúncio foi adicionado.

## Supabase SQL
Execute somente:
`Q-RIVAL_V42_SQL_DEFINITIVO.sql`

## Mercado Pago
As Edge Functions ficam em:
- `supabase/functions/create-coin-payment/index.ts`
- `supabase/functions/mercadopago-webhook/index.ts`

Configure no projeto Supabase:
- `MERCADOPAGO_ACCESS_TOKEN`
- `SITE_URL`

Depois publique as duas funções. O webhook do Mercado Pago precisa estar acessível por HTTPS.

## Importante
Nunca coloque o Access Token do Mercado Pago em `config.js`, `app.js` ou em arquivos públicos do GitHub Pages. Ele deve permanecer somente nos secrets das Edge Functions.
