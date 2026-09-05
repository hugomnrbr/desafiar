QuizUp v39.2 — correção do catálogo inicial

O catálogo anterior podia não aparecer porque a criação dos títulos encontrava a constraint antiga titles_effect_style_check e a transação era revertida.

Execute no Supabase:
QUIZUP_V39_2_CATALOGO_FIX.sql

Ele cria 12 produtos ativos e compráveis:
- 3 avatares
- 3 emblemas
- 3 títulos PNG 600x160
- 3 fundos 800x500

Também remove somente os cosméticos antigos e limpa os vínculos desses cosméticos dos perfis.
