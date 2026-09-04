QuizUp v39.2 — pacote final

CORREÇÕES PRINCIPAIS
- Perfil sem o avatar duplicado no cabeçalho da própria tela de perfil.
- Administradores mantêm o título de sistema 👑 Administrador e podem escolher 1 segundo título comprado.
- Os dois títulos aparecem no perfil, partida, contagem regressiva, resultado, ranking, amigos, tópicos, notícias e demais identidades que usam o componente de perfil.
- +18 removido da partida.
- Reações/emoji da partida com intervalo mínimo de 3 segundos por jogador.
- RPC activate_premium_item sem sobrecarga text/integer.
- RPC admin_remove_premium_item com assinaturas text e text,text,text para evitar 42883 em bases antigas.
- Constraint de notificações corrigida.
- Exclusão administrativa de cosméticos remove a posse e limpa o perfil.
- Catálogo inicial novo: 3 avatares, 3 emblemas animados, 3 títulos PNG e 3 fundos 800x500.
- Títulos seguem padrão PNG 600x160.

CATÁLOGO INICIAL
Avatares: Neon, Cósmico, Sombra.
Emblemas: Fogo, Água, Galáxia.
Títulos: Campeão, Mestre, Lendário.
Fundos: Aurora, Nebulosa, Cyber Night.

SUPABASE
1. Publique o conteúdo deste ZIP no GitHub Pages.
2. No Supabase SQL Editor, execute SOMENTE QUIZUP_V39_2_FINAL.sql depois das migrations anteriores.
3. O SQL final limpa os cosméticos antigos de avatar/emblema/título/fundo e cria o novo catálogo.
4. Não execute os arquivos SQL antigos de correção depois deste pacote.

TÍTULOS PERSONALIZADOS
No painel administrativo, envie um PNG exatamente em 600 x 160 px. O efeito é escolhido no painel e passa ao redor da arte.
