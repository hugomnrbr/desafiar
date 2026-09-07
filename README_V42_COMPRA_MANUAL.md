# Q-Rival v42 — Compra manual de QuizCoins

Enquanto o Mercado Pago não estiver disponível, o Q-Rival usa compra manual administrada pela equipe.

## Fluxo do jogador
1. Abre **Loja → Comprar QuizCoins**.
2. Escolhe um pacote, por exemplo **100 Coins — R$ 4,99**.
3. O Q-Rival cria uma solicitação e abre o bate-papo da compra.
4. O administrador entra na solicitação e envia o link de pagamento.
5. O jogador realiza o pagamento fora do Q-Rival.
6. O jogador envia o comprovante pelo próprio bate-papo.
7. O administrador confere o comprovante.
8. Somente depois da confirmação o administrador clica em **LIBERAR COINS**.
9. O banco credita as Coins e registra a entrada no histórico.

## Segurança
- O jogador não consegue aprovar a própria compra.
- A aprovação é feita por RPC protegida por `public.is_admin()`.
- Uma compra já aprovada não pode ser creditada novamente.
- Comprovantes ficam no bucket privado `purchase-proofs`.
- O administrador abre o comprovante por URL assinada.
- O link de pagamento é enviado pelo chat da solicitação.

## SQL
Execute o arquivo:

`Q-RIVAL_V42_SQL_DEFINITIVO.sql`

Ele já contém o patch da compra manual.

Se você preferir executar somente o patch da nova funcionalidade:

`Q-RIVAL_V42_COMPRA_MANUAL_COINS.sql`

## Importante
O Mercado Pago não é necessário para esse modo. Não configure Access Token nem Edge Function para as compras manuais.

Quando o gateway automático estiver funcionando no futuro, o sistema pode ser reativado sem remover o histórico das compras manuais.
