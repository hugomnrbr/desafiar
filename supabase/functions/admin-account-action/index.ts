import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const cors = { 'Access-Control-Allow-Origin':'*', 'Access-Control-Allow-Headers':'authorization, x-client-info, apikey, content-type' };
Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok',{headers:cors});
  try {
    const supabaseUrl=Deno.env.get('SUPABASE_URL')!;
    const anon=Deno.env.get('SUPABASE_ANON_KEY')!;
    const service=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const auth=req.headers.get('Authorization')||'';
    const userClient=createClient(supabaseUrl,anon,{global:{headers:{Authorization:auth}}});
    const {data:{user},error:ue}=await userClient.auth.getUser();
    if(ue||!user) throw new Error('Não autenticado');
    const {data:admin}=await userClient.from('profiles').select('role').eq('id',user.id).single();
    if(admin?.role!=='admin') throw new Error('Acesso negado');
    const body=await req.json();
    const action=body.action;
    const adminClient=createClient(supabaseUrl,service);
    if(action==='change_email'){
      if(!body.user_id||!String(body.new_email||'').includes('@')) throw new Error('Novo e-mail inválido');
      const {data,error}=await adminClient.auth.admin.updateUserById(body.user_id,{email:String(body.new_email).trim(),email_confirm:false});
      if(error) throw error;
      return new Response(JSON.stringify({ok:true,user:data.user}),{headers:{...cors,'Content-Type':'application/json'}});
    }
    throw new Error('Ação inválida');
  } catch(e) {
    return new Response(JSON.stringify({error:e?.message||String(e)}),{status:400,headers:{...cors,'Content-Type':'application/json'}});
  }
});
