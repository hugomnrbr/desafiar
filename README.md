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


## v36.2.9 — correções e melhorias
- Loja movida para a navegação inferior; removido o botão de loja do topo.
- Topo reduzido a Início, avatar/perfil, saldo de QuizCoins e Sair.
- Logout passou a executar diretamente o encerramento da sessão e liberar a sessão única.
- Corrigida a compra de cosméticos por QuizCoins com RPC `purchase_premium_item`. Mercado Pago continua OFF.
- Feed social Notícias com publicações de texto/foto, filtros Global/Amigos/Categoria, curtidas e comentários.
- Upload de fotos/prints usa o bucket `social-posts`.
- Painel administrativo ganhou moderação da comunidade.
- Contas com `role=admin` exibem publicamente o título `👑 Administrador`.
- No duelo, +18, pontuação acumulada e ganho da rodada ficam abaixo do avatar.
- Reações da partida usam realtime e aparecem sobre o avatar dos dois jogadores.
- Campo de suporte ampliado para textarea.

### Supabase
Execute a migration consolidada `quizup_v36_2_7_MIGRATION_COMPLETA.sql` no SQL Editor. Ela é cumulativa e cria/atualiza as funções, RLS, feed social, bucket de mídia e compra por Coins.

### Próximas melhorias recomendadas
1. Denúncia de publicação/comentário pelos jogadores e fila de denúncias no admin.
2. Bloquear/mutar jogadores.
3. Compressão automática de imagens antes do upload.
4. Paginação/infinite scroll do feed para não carregar 40 posts de uma vez.
5. Histórico de Coins no perfil e extrato detalhado no admin.
6. Presença online/offline de amigos e indicador de “digitando…”.
7. Proteção adicional contra spam de comentários, curtidas e reações via rate limit no banco.
8. Testes de ponta a ponta para login, logout, compra, partida 1v1 e sessão única.


## QuizUp v37

- Feed social com paginação/carregamento automático, Global/Amigos/Categoria.
- Curtidas, comentários, denúncias, bloqueio e silenciamento.
- Notificações persistentes no topo com contador e sincronização em tempo real.
- Presença online simples e indicador de amigo online.
- Chat com indicador "digitando...".
- Conquistas desbloqueáveis por partidas, vitórias, sequência e Coins.
- Histórico de movimentações de QuizCoins.
- Publicação automática do resultado de partidas no feed.
- Mercado Pago permanece OFF.
- Administradores continuam identificados publicamente como "Título: Administrador".

### SQL
Execute `quizup_v37_MIGRATION_COMPLETA.sql` no Supabase SQL Editor depois de aplicar a estrutura anterior.


## QuizUp v38
- Painel administrativo modular: Dashboard, perguntas, categorias/aprovação, loja, Coins, conquistas, títulos, emblemas, contas, suporte, moderação e comunidade.
- Loja reconstruída para cosméticos comprados com QuizCoins; Mercado Pago permanece OFF.
- Categorias da loja são administradas separadamente.
- Avatares personalizados usam imagem cadastrada pelo administrador e padronização circular no perfil/partida.
- Títulos conquistados ficam no perfil público; o jogador escolhe um título principal para aparecer na partida.
- Conquistas podem ter meta e entregar automaticamente um título associado.
- Corrigida compatibilidade da RPC `purchase_premium_item` com bancos antigos e colunas promocionais ausentes.
- Sessão atualizada para não reinicializar o app em `TOKEN_REFRESHED`; partida recente pode ser restaurada por até 60 segundos após retorno/reload.

## v38.4 — Artes personalizadas e avatares
- Títulos, emblemas e conquistas aceitam PNG/JPG/WebP/SVG/GIF enviados pelo administrador.
- GIFs são exibidos como imagens animadas no perfil/listas quando o navegador suporta.
- O jogador não possui mais upload de foto própria: o avatar vem exclusivamente dos itens do inventário.
- O jogador pode ativar ou desativar um avatar/item do inventário.
- O painel de contas usa uma RPC administrativa mais robusta para listar contas registradas.
- Execute `quizup_v38_4_MIGRATION_AVATARES_ARTES.sql` após a migration v38.


## v38.5 — Contas e molduras
- A RPC `admin_list_accounts` foi corrigida para não depender de uma coluna `created_at` inexistente em `profiles`.
- O painel atualiza automaticamente depois de carregar as contas.
- Molduras usam canvas oficial 256×256 px e são renderizadas como camada sobre o avatar.
- Para criar uma moldura, envie PNG/WebP/GIF quadrado com centro transparente; o avatar fica por baixo.
- O jogador continua sem upload de foto própria: o avatar vem exclusivamente do inventário.

## v38.8 — Fundos de Perfil
- Nova categoria **Fundos de Perfil** na Loja.
- Jogador pode comprar fundo com QuizCoins e ativar/desativar pelo próprio inventário.
- Um único fundo pode ficar ativo por vez.
- Fundo ativo é salvo no perfil e aparece também quando outro jogador abre o perfil público.
- Resolução padrão obrigatória: **800 × 500 px**.
- Fundo estático: PNG, JPG/JPEG ou WebP.
- Fundo animado: **GIF 800 × 500 px**; o GIF continua animado no fundo do perfil.
- Administrador escolhe no painel se o fundo é Estático ou Animado, envia a arte, define preço, promoção, descrição e ativa/desativa o item.
- A ativação usa a RPC `activate_premium_item`, que também corrige a compatibilidade de bancos que não tinham essa função criada pela versão anterior.

### Supabase — v38.8
Depois de aplicar a v38.7, execute **somente** `quizup_v38_8_MIGRATION_FUNDOS_PERFIL.sql`.
Não é necessário repetir as migrations antigas.


### v38.9 — Vendas de Títulos, Emblemas e Fundos
Execute `quizup_v38_9_MIGRATION_VENDAS_TITULOS_EMBLEMAS_FUNDOS.sql` após a v38.8. Títulos vendidos agora entregam `user_titles` e ativam o título real com nome + efeito; emblemas e fundos possuem fluxo próprio de venda/ativação no painel administrativo.

## v38.9.1 — Correções de títulos e molduras
- Administradores usam sempre o título principal de sistema `👑 Administrador`.
- Títulos comprados continuam individuais por usuário; listas de títulos de um jogador nunca são reutilizadas para outro perfil.
- IDs internos como `custom-...` não são exibidos como título público.
- Molduras PNG transparentes são renderizadas como uma única camada sobre o avatar, sem segunda borda CSS.
- Execute `quizup_v38_9_1_MIGRATION_CORRECOES_TITULO_ADMIN_MOLDURA.sql` após a v38.9.
