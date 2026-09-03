# QuizUp Mobile v6 — Supabase + Multiplayer

Esta versão continua o projeto v5 e adiciona:

- 50 perguntas iniciais em cada categoria (300 perguntas no total).
- 10 perguntas sorteadas aleatoriamente por partida.
- Painel administrativo com todas as perguntas, pesquisa, filtro por categoria, editar, excluir e ativar/inativar.
- Cadastro com nome de usuário único + e-mail + senha.
- Login usando nome de usuário **ou** e-mail + senha.
- Amizades por nome de usuário, com solicitação e aceite.
- Perfil público de cada jogador: foto, rank global, nível, XP, vitórias, derrotas e categoria mais jogada.
- Upload de foto de perfil pelo próprio jogador.
- Matchmaking 1x1 e 2x2.

## Configuração do Supabase

### Opção recomendada: um único SQL
No SQL Editor do Supabase, execute o arquivo:

`supabase/schema-v6.sql`

Ele contém o schema do v5, as alterações do v6 e as 300 perguntas iniciais.

### Se você já executou o schema v5
Também é possível executar separadamente:

1. `supabase/upgrade-v6.sql`
2. `supabase/seed-300-questions.sql`

## Configuração do navegador

Edite `config.js` e coloque apenas a Project URL e a **Publishable key** do Supabase. Nunca coloque a Secret/service_role key no navegador.

## Admin

Depois de criar sua conta, no SQL Editor execute:

```sql
update public.profiles
set role='admin'
where username='SEU_USUARIO';
```

Depois saia e entre novamente. O botão ⚙ aparecerá no topo.

## GitHub Pages

Envie os arquivos para a raiz do repositório. O `index.html` deve ficar na raiz. Em GitHub → Settings → Pages, publique a branch `main` e a pasta `/ (root)`.

Depois configure no Supabase Authentication → URL Configuration a URL do GitHub Pages como Site URL.

## v7 — categorias, conteúdo da comunidade e conquistas

Depois de instalar a versão v6, execute `supabase/upgrade-v7.sql` no SQL Editor do Supabase.

### Novidades
- Administrador pode criar categorias e subcategorias.
- Jogadores podem pesquisar categorias/subcategorias na tela de escolha de categoria.
- Jogadores podem enviar novas categorias e perguntas para aprovação.
- Conteúdo enviado por jogador começa como `pending`/não publicado e só fica disponível após aprovação do administrador.
- Administrador possui fila de aprovação para categorias e perguntas.
- Painel do administrador tem botão para voltar à página inicial.
- Administrador pode criar, ativar, inativar e excluir conquistas.
- Conquistas ativas aparecem na área pública de Conquistas.

### Ordem recomendada no Supabase
1. Se o projeto já está na v6, execute somente `supabase/upgrade-v7.sql`.
2. Se for uma instalação nova, execute `supabase/schema-v6.sql` e depois `supabase/upgrade-v7.sql`.
3. Não coloque a `service_role`/Secret key no `config.js`.
