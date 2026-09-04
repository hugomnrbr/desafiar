-- QuizUp v36.1 — Supabase Storage para imagens das perguntas
-- Execute este arquivo UMA vez no SQL Editor do Supabase.

insert into storage.buckets (id, name, public)
values ('question-images', 'question-images', true)
on conflict (id) do update set public = true;

-- Usuários autenticados podem enviar imagens apenas para a própria pasta.
drop policy if exists "QuizUp question images upload own folder" on storage.objects;
create policy "QuizUp question images upload own folder"
on storage.objects for insert
to authenticated
with check (
  bucket_id = 'question-images'
  and (storage.foldername(name))[1] = auth.uid()::text
);

-- Usuários autenticados podem substituir/excluir apenas seus próprios arquivos.
drop policy if exists "QuizUp question images update own folder" on storage.objects;
create policy "QuizUp question images update own folder"
on storage.objects for update
to authenticated
using (
  bucket_id = 'question-images'
  and (storage.foldername(name))[1] = auth.uid()::text
)
with check (
  bucket_id = 'question-images'
  and (storage.foldername(name))[1] = auth.uid()::text
);

drop policy if exists "QuizUp question images delete own folder" on storage.objects;
create policy "QuizUp question images delete own folder"
on storage.objects for delete
to authenticated
using (
  bucket_id = 'question-images'
  and (storage.foldername(name))[1] = auth.uid()::text
);

-- O bucket é público para que as imagens possam aparecer no quiz.
-- Não é necessário criar policy SELECT para downloads públicos do bucket.
