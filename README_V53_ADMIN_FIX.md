# Q-Rival V53 — Correção do acesso ao Painel Administrativo

Correção específica do botão "Painel do Administrador" no perfil.
- botão agora usa `data-go="admin"` como rota SPA;
- validação de administrador considera `profiles.role` sem diferença de maiúsculas/minúsculas;
- removido listener duplicado que podia conflitar com o handler de navegação;
- acesso continua protegido pelo painel e pelo banco.

Nenhuma alteração de SQL é necessária para esta correção se o perfil já possui `role = 'admin'`.
