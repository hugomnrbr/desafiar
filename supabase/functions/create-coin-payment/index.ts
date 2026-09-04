import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
const cors={'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization, x-client-info, apikey, content-type'};
Deno.serve(async(req)=>{if(req.method==='OPTIONS')return new Response('ok',{headers:cors});try{
 if(req.method!=='POST')throw new Error('Método não permitido');
 const url=Deno.env.get('SUPABASE_URL')!,anon=Deno.env.get('SUPABASE_ANON_KEY')!,service=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,token=Deno.env.get('MERCADOPAGO_ACCESS_TOKEN'),app=(Deno.env.get('QUIZUP_APP_URL')||'').replace(/\/$/,'');
 if(!token)throw new Error('MERCADOPAGO_ACCESS_TOKEN não configurado');if(!app)throw new Error('QUIZUP_APP_URL não configurado');
 const auth=req.headers.get('Authorization')||'';const userClient=createClient(url,anon,{global:{headers:{Authorization:auth}}});const {data:{user},error:ue}=await userClient.auth.getUser();if(ue||!user)throw new Error('Não autenticado');
 const body=await req.json();const packageId=String(body?.coin_package_id||'');if(!packageId)throw new Error('Pacote não informado');
 const {data:order,error:oe}=await userClient.rpc('create_coin_order',{p_package_id:packageId});if(oe||!order)throw new Error(oe?.message||'Não foi possível criar o pedido');
 const webhook=`${url.replace(/\/$/,'')}/functions/v1/mercadopago-webhook`;
 const pref={items:[{id:String(order.package_id),title:`QuizUp • ${Number(order.coins).toLocaleString('pt-BR')} QuizCoins`,description:'Créditos virtuais para usar na loja QuizUp',quantity:1,currency_id:'BRL',unit_price:Number(order.amount_cents)/100}],external_reference:order.external_reference,notification_url:webhook,back_urls:{success:`${app}/?payment_status=approved&external_reference=${encodeURIComponent(order.external_reference)}`,pending:`${app}/?payment_status=pending&external_reference=${encodeURIComponent(order.external_reference)}`,failure:`${app}/?payment_status=rejected&external_reference=${encodeURIComponent(order.external_reference)}`},auto_return:'approved'};
 const mp=await fetch('https://api.mercadopago.com/checkout/preferences',{method:'POST',headers:{Authorization:`Bearer ${token}`,'Content-Type':'application/json'},body:JSON.stringify(pref)});const mj=await mp.json();if(!mp.ok||!mj?.id||!mj?.init_point)throw new Error(mj?.message||mj?.error||'Mercado Pago recusou o checkout');
 const admin=createClient(url,service);const {error:up}=await admin.from('coin_orders').update({provider_preference_id:mj.id,updated_at:new Date().toISOString()}).eq('id',order.id).eq('user_id',user.id);if(up)throw up;
 return new Response(JSON.stringify({ok:true,order_id:order.id,preference_id:mj.id,checkout_url:mj.init_point}),{headers:{...cors,'Content-Type':'application/json'}});
}catch(e){return new Response(JSON.stringify({ok:false,error:e?.message||String(e)}),{status:400,headers:{...cors,'Content-Type':'application/json'}})}});
