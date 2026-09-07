# QuizUp V41.5

Versão visual baseada na referência fornecida: perfil, ranking, amigos, fila, início da partida e partida usam a mesma composição de avatar e moldura.

## Molduras
As seis molduras em `assets/store/frames/` são PNG RGBA de 256x256 e estáticas: Fogo, Água, Terra, Ar, Trevas e Luz. O avatar fica dentro da abertura da moldura.

## Uso
Substitua os arquivos do projeto no GitHub. Não é necessário SQL para a correção visual.
## v41.6 — correções visuais mobile e desistência

Esta versão corrige proporção/overflow de avatares e molduras em perfil, amigos, notícias, fila e partida; melhora o painel de reações/emoji para toque no iPhone; remove IDs de títulos inválidos da apresentação do perfil; e adiciona o botão **DESISTIR** durante partidas.

### SQL adicional

Execute `QUIZUP_V41_6_FORFEIT_PATCH.sql` no Supabase SQL Editor para habilitar a desistência online com a RPC `forfeit_match`.
