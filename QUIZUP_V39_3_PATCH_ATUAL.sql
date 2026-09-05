BEGIN;

-- Compatibilidade com o banco atual confirmado pelo projeto.
-- O frontend usa somente estas assinaturas.

GRANT EXECUTE ON FUNCTION public.admin_remove_premium_item(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.activate_premium_item(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.purchase_premium_item(text,bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_main_title(uuid) TO authenticated;

-- Recarrega o schema do PostgREST para evitar cache de RPC antiga.
NOTIFY pgrst, 'reload schema';

-- Campos de recompensa de conquista.
ALTER TABLE IF EXISTS public.achievements
  ADD COLUMN IF NOT EXISTS reward_type text;
ALTER TABLE IF EXISTS public.achievements
  ADD COLUMN IF NOT EXISTS reward_item_id text;

-- Entrega o produto escolhido quando a conquista é desbloqueada.
CREATE OR REPLACE FUNCTION public.quizup_notify_achievement()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=public
AS $$
DECLARE
  a record;
  it public.premium_items;
  title_uuid uuid;
BEGIN
  SELECT title,description,icon,title_id,reward_type,reward_item_id
    INTO a
    FROM public.achievements
   WHERE id=new.achievement_id;

  IF a.title_id IS NOT NULL THEN
    INSERT INTO public.user_titles(user_id,title_id,is_main)
    VALUES(new.user_id,a.title_id,false)
    ON CONFLICT(user_id,title_id) DO NOTHING;
  END IF;

  IF COALESCE(trim(a.reward_item_id),'')<>'' THEN
    SELECT * INTO it
      FROM public.premium_items
     WHERE id::text=trim(a.reward_item_id)
     LIMIT 1;

    IF it.id IS NOT NULL THEN
      INSERT INTO public.user_premium_items(user_id,item_id,active,purchased_at)
      VALUES(new.user_id,it.id,false,now())
      ON CONFLICT(user_id,item_id) DO NOTHING;

      IF it.kind='title'
         AND COALESCE(it.source_type,'')='title'
         AND COALESCE(it.source_id,'')<>'' THEN
        BEGIN
          title_uuid:=it.source_id::uuid;
          INSERT INTO public.user_titles(user_id,title_id,is_main)
          VALUES(new.user_id,title_uuid,false)
          ON CONFLICT(user_id,title_id) DO NOTHING;
        EXCEPTION WHEN others THEN
          NULL;
        END;
      END IF;
    END IF;
  END IF;

  IF to_regclass('public.notifications') IS NOT NULL THEN
    INSERT INTO public.notifications(recipient_id,actor_id,type,title,body,data)
    VALUES(
      new.user_id,NULL,'achievement',
      COALESCE(a.icon,'🏆')||' Conquista desbloqueada',
      CASE WHEN it.id IS NOT NULL
        THEN COALESCE(a.description,a.title)||' • 🎁 Recompensa: '||it.name
        ELSE COALESCE(a.description,a.title)
      END,
      jsonb_build_object(
        'achievement_id',new.achievement_id,
        'title_id',a.title_id,
        'reward_type',a.reward_type,
        'reward_item_id',a.reward_item_id,
        'reward_item_name',CASE WHEN it.id IS NOT NULL THEN it.name ELSE NULL END
      )
    );
  END IF;

  RETURN new;
END;
$$;

DROP TRIGGER IF EXISTS trg_quizup_notify_achievement ON public.user_achievements;
CREATE TRIGGER trg_quizup_notify_achievement
AFTER INSERT ON public.user_achievements
FOR EACH ROW EXECUTE FUNCTION public.quizup_notify_achievement();

GRANT EXECUTE ON FUNCTION public.quizup_notify_achievement() TO authenticated;

NOTIFY pgrst, 'reload schema';
COMMIT;

-- Conferência final.
SELECT n.nspname AS schema_name,
       p.proname AS function_name,
       pg_get_function_identity_arguments(p.oid) AS arguments
FROM pg_proc p
JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public'
  AND p.proname IN ('admin_remove_premium_item','activate_premium_item','purchase_premium_item','set_main_title')
ORDER BY p.proname,arguments;
