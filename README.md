# QuizUp v36.2.5

## Publicação
Envie o conteúdo desta pasta para o repositório do QuizUp. O `index.html` usa `style-neo.css?v=36.2.5` para evitar cache antigo.

## Supabase
Execute **somente** `quizup_v36_2_5_MIGRATION.sql` depois de ter aplicado a migration v36.2.4. Esta migration é idempotente para as novas estruturas e adiciona:
- recusa de desafios com aviso único ao desafiante;
- histórico finalizado de vitórias/derrotas/empates contra cada amigo;
- pacotes de QuizCoins editáveis pelo administrador;
- lista de contas no painel;
- RPC segura para o administrador conceder/remover títulos.

## Retorno ao aplicativo
A rota atual fica salva em `sessionStorage`, inclusive loja, amigos, perfil e partida. Ao recarregar/voltar de outro aplicativo, o cliente tenta restaurar a tela anterior; se houver partida, consulta o estado atual no Supabase.

## Contas
O painel mostra nome/e-mail das contas por meio da RPC `admin_list_accounts`. O botão de redefinição usa o fluxo de recuperação de senha do Supabase.

### Alteração de e-mail pelo administrador
A pasta `supabase/functions/admin-account-action/index.ts` é uma Edge Function. Para ativar o botão **ALTERAR E-MAIL**, publique essa função no seu projeto Supabase e mantenha `SUPABASE_SERVICE_ROLE_KEY` somente como secret da função. Nunca coloque essa chave no `app.js`, `config.js` ou GitHub.


## v36.2.6 - segurança de cadastro
- Senha: mínimo de 6 caracteres, somente letras e números.
- Nome de usuário: 3 a 20 caracteres, letras/números/underscore, único sem diferenciar maiúsculas/minúsculas.
- E-mail: normalizado para minúsculas; a unicidade é garantida pelo Supabase Auth.
- Execute `quizup_v36_2_6_SECURITY_MIGRATION.sql` depois da migration v36.2.5.
