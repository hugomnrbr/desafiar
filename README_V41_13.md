# Q-Rival v41.13 — correções finais

## O que foi corrigido
- Partida voltou a usar o layout clássico da referência enviada.
- Avatar fica recortado dentro da abertura central da moldura.
- PNG da moldura fica sempre na frente do avatar.
- Removidos os painéis/fundos extras atrás de avatar + moldura.
- Reação/emoji aparece sobre o avatar do jogador que usou.
- A reação some automaticamente após 2 segundos.
- Intervalo de 3 segundos entre reações, com validação também no banco.
- Todos os jogadores recebem a reação via Supabase Realtime.
- Tela **Criar novo Quiz** foi restaurada e o botão CRIAR agora abre o formulário.
- Criação de quiz aceita 10 perguntas, 4 alternativas e pergunta com imagem.
- Incluído fluxo de revisão pelo administrador.
- Botão **DESISTIR** da partida permanece funcionando.

## SQL
Execute no Supabase:

`Q-RIVAL_V41_13_FINAL_PATCH.sql`

Esse patch cria/garante as tabelas e RPCs usadas pelas novas funções. Ele não exige executar novamente todos os SQL antigos.

Depois, publique a pasta `quizup_latest` no GitHub Pages.
