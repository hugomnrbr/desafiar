# QuizUp v36.2.7 — Mercado Pago

Esta versão parte da base funcional v36.2.4 e adiciona pagamento real preparado via Mercado Pago + Supabase Edge Functions.

## O que foi adicionado
- Compra de QuizCoins com pacotes definidos pelo administrador.
- Pedido criado no servidor com preço/quantidade vindos do banco.
- Checkout Pro do Mercado Pago.
- Webhook assinado e validado.
- Consulta server-side do pagamento.
- Conferência do valor pago contra o pedido.
- Crédito atômico das Coins.
- Ledger idempotente contra crédito duplicado.
- Histórico de compras do jogador.
- Painel administrativo com pacotes, vendas e controle Mercado Pago.
- Proteção de cadastro: senha mínima 6, somente letras/números; username único.

## Supabase — ordem
1. Execute `quizup_v36_2_7_MIGRATION_COMPLETA.sql`.
2. Publique `supabase/functions/create-coin-payment/index.ts` como função `create-coin-payment`.
3. Publique `supabase/functions/mercadopago-webhook/index.ts` como função `mercadopago-webhook`. O `supabase/config.toml` deste ZIP deixa o webhook sem JWT porque ele é chamado pelo Mercado Pago; a função valida a assinatura HMAC.
4. Configure os Secrets: `MERCADOPAGO_ACCESS_TOKEN`, `MERCADOPAGO_WEBHOOK_SECRET`, `QUIZUP_APP_URL`. As variáveis `SUPABASE_URL`, `SUPABASE_ANON_KEY` e `SUPABASE_SERVICE_ROLE_KEY` são fornecidas pelo ambiente das Edge Functions; não copie a service role para o frontend.
5. No Mercado Pago, abra Sua aplicação > Webhooks > Configurar notificações. Informe a URL HTTPS `https://SEU-PROJETO.supabase.co/functions/v1/mercadopago-webhook` e ative o evento de Pagamentos.
6. Salve a configuração e use a opção Simular para verificar a entrega do webhook.
7. No QuizUp, entre como administrador e ative `Mercado Pago` em Controle de compras.

## Teste
Comece com as credenciais de teste do Mercado Pago. Crie/obtenha uma conta compradora de teste. O Checkout Pro redireciona o jogador para o Mercado Pago. As credenciais de teste não movimentam dinheiro real. Para testar a recepção do webhook, use a simulação do painel do Mercado Pago; a documentação oficial informa que pagamentos de teste não enviam notificações reais.

## Produção
Depois de validar, troque o `MERCADOPAGO_ACCESS_TOKEN` para o token de produção e configure a aplicação/webhook de produção. Nunca publique o Access Token ou a chave secreta do webhook no GitHub.


## Recursos desta versão
- Mercado Pago fica **OFF** por padrão e não pode ser ativado pelo painel enquanto esta versão estiver desativada. A estrutura de Checkout/Webhook permanece no projeto para ativação futura.
- QuizCoins são concedidas automaticamente ao finalizar partidas online por `award_match_coins`.
- Administrador pode enviar Coins manualmente pelo painel; o crédito passa por `admin_grant_coins` e entra no ledger.
- Loja usa QuizCoins para cosméticos, VIP e outros itens; compra com dinheiro fica bloqueada enquanto Mercado Pago estiver OFF.
- Área de Suporte com conversa jogador ↔ administrador.
- Reações de partida passaram a usar o INSERT do banco como fonte de sincronização, evitando duplicação entre Broadcast e Postgres.
- Sessão única por conta: o último aparelho conectado assume a conta e o aparelho anterior é desconectado pela verificação de sessão.
- Ao trocar de aplicativo/janela, a tela da partida não é abandonada; ao retornar, o estado autoritativo é sincronizado novamente.
- Indicador `+18` aparece logo abaixo dos avatares durante a partida e possui animação de desaparecimento.

## SQL adicional
Execute o arquivo `quizup_v36_2_7_MIGRATION_COMPLETA.sql` completo. A parte final cria as tabelas/RPCs de Coins administrativas, suporte e sessão única. 
