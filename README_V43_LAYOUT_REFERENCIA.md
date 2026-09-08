# Q-Rival v44 — Janelas separadas no menu

Esta versão mantém a lógica da v42 de compras manuais e aplica o novo layout neon baseado na referência enviada.

## Alterações visuais
- Início/dashboard em painéis: perfil, amigos, ranking, notícias, início da partida, loja e resumo do perfil.
- Início da partida com VS, avatar/moldura, nível, título, XP, categoria, dificuldade, perguntas, tempo e estado de matchmaking.
- Lista de amigos com avatar/moldura, nome, nível, título principal, status online/offline, chat e desafio.
- Ranking com pódio e lista, nível, título principal e XP.
- Cor do XP acompanha a cor do emblema/moldura equipada (fogo, água, terra, ar, trevas ou luz).
- Loja redesenhada com categorias na lateral; ao clicar em uma categoria, aparecem somente os produtos daquela categoria.
- QuizCoins usa o fluxo de compra manual já implementado: solicitar → chat com administrador → link de pagamento → comprovante → aprovação → crédito.
- Layout responsivo para celular e desktop.

## Banco de dados
Nenhum SQL adicional é obrigatório apenas para o layout. As alterações de dados existentes continuam usando o SQL da v42.


## v44 — navegação corrigida
- A tela **Início** não exibe mais Perfil, Amigos, Ranking, Notícias, Início da partida ou Loja juntos.
- Cada área abre somente quando seu respectivo botão do menu é selecionado.
- O menu agora possui: **Início, Jogar, Ranking, Amigos, Notícias, Loja, Suporte e Perfil**.
- **Jogar** abre a seleção de categorias/início da partida.
- **Ranking** abre a tela completa de ranking.
- O layout desktop usa menu lateral e o celular usa menu horizontal.
