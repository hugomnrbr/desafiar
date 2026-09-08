# Q-Rival v49 — Sistema de Engajamento Administrável

Esta versão adiciona uma camada de progressão e retenção controlada pelo Painel Administrativo.

## Novos módulos

- Eventos semanais/especiais
- Missões diárias configuráveis
- Liga semanal com ranking automático
- Sequência de vitórias
- Torneios com inscrições e limite de jogadores
- Compartilhamento manual do resultado
- Área de engajamento na tela inicial
- Recompensas de XP/QuizCoins configuráveis por missão/evento

## Administração

No Painel Administrativo → **Engajamento**, o administrador pode criar, ativar, desativar e excluir:

1. Eventos
2. Missões
3. Torneios

Nada disso exige alteração no `app.js`.

## Banco

Execute `SUPABASE_V49_ENGAJAMENTO.sql` no SQL Editor do mesmo projeto Supabase usado pelo Q-Rival.

O SQL é incremental e usa `IF NOT EXISTS`/políticas idempotentes para não apagar os dados existentes.

## Observação sobre torneios

A v49 implementa a agenda, inscrições, limite de participantes e base de classificação do torneio. A formação automática de chave eliminatória e a execução das partidas como uma fila própria devem ser conectadas ao mesmo motor de partidas antes de serem tratadas como torneio eliminatório oficial.

## Importante

A v49 mantém os sistemas existentes do v47 e adiciona os módulos de engajamento. O compartilhamento de resultados é voluntário: a partida termina e somente o botão **Compartilhar** publica/compartilha o texto.

### Recompensas de eventos

Quando uma partida termina durante um evento ativo compatível com a categoria, o multiplicador de XP e o bônus de Coins configurados no evento são aplicados. A recompensa de item do evento também é adicionada ao inventário, sem depender de alteração no código.
