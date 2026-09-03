-- QuizUp v10: chat multimídia
alter table public.direct_messages add column if not exists message_type text not null default 'text' check(message_type in ('text','photo'));
alter table public.direct_messages add column if not exists media_url text;
create index if not exists direct_messages_media_idx on public.direct_messages(message_type,created_at);

-- Bucket público para fotos enviadas no chat. O caminho começa pelo UUID do usuário.
insert into storage.buckets (id,name,public)
values ('chat-media','chat-media',true)
on conflict (id) do update set public=true;

drop policy if exists chat_media_insert on storage.objects;
create policy chat_media_insert on storage.objects
for insert to authenticated
with check (
  bucket_id='chat-media'
  and (storage.foldername(name))[1]=(select auth.uid())::text
);

drop policy if exists chat_media_delete on storage.objects;
create policy chat_media_delete on storage.objects
for delete to authenticated
using (
  bucket_id='chat-media'
  and (storage.foldername(name))[1]=(select auth.uid())::text
);

-- Permite que o chat continue usando Realtime após a alteração da tabela.
do $$
begin
  begin alter publication supabase_realtime add table public.direct_messages; exception when duplicate_object then null; end;
end $$;
