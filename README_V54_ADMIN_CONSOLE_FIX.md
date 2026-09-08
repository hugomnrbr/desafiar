# Q-Rival V54 — correção do Painel Administrativo

Correções baseadas no console do navegador:
- Corrigida a função touchPresence: PostgREST/Supabase query builder não usa `.catch()` dessa forma; agora usa await + try/catch.
- Reintroduzido `coinGrantAdminHtml`, que estava sendo referenciado pela view `admin()` sem declaração e interrompia a renderização do painel com `ReferenceError`.
- Mantidos os demais recursos da V53.

Para esta correção de interface, publique os arquivos no GitHub. Não é necessário SQL para os dois erros mostrados no console, desde que as tabelas/funções já criadas pela V51/V52 existam.
