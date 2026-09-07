import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Content-Type': 'application/json',
};

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  try {
    const auth = req.headers.get('Authorization') || '';
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    const anonKey = Deno.env.get('SUPABASE_ANON_KEY')!;
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const mpToken = Deno.env.get('MERCADOPAGO_ACCESS_TOKEN')!;
    const siteUrl = Deno.env.get('SITE_URL')!;
    if (!mpToken || !siteUrl) throw new Error('Mercado Pago/SITE_URL não configurados.');

    const userClient = createClient(supabaseUrl, anonKey, { global: { headers: { Authorization: auth } } });
    const { data: { user } } = await userClient.auth.getUser();
    if (!user) throw new Error('Não autenticado.');

    const body = await req.json();
    const packageId = String(body?.coin_package_id || '');
    if (!packageId) throw new Error('Pacote de QuizCoins inválido.');

    const admin = createClient(supabaseUrl, serviceKey);
    const { data: order, error: orderError } = await admin.rpc('create_coin_order', { p_package_id: packageId });
    if (orderError) throw orderError;
    if (!order?.id || !order?.amount_cents) throw new Error('Não foi possível criar o pedido.');

    const preference = {
      external_reference: order.external_reference,
      items: [{
        id: packageId,
        title: `Q-Rival — ${Number(order.coins).toLocaleString('pt-BR')} QuizCoins`,
        quantity: 1,
        currency_id: 'BRL',
        unit_price: Number(order.amount_cents) / 100,
      }],
      payer: { email: user.email },
      back_urls: {
        success: `${siteUrl}/?payment_status=approved&external_reference=${encodeURIComponent(order.external_reference)}`,
        pending: `${siteUrl}/?payment_status=pending&external_reference=${encodeURIComponent(order.external_reference)}`,
        failure: `${siteUrl}/?payment_status=failure&external_reference=${encodeURIComponent(order.external_reference)}`,
      },
      auto_return: 'approved',
      notification_url: `${supabaseUrl}/functions/v1/mercadopago-webhook`,
      metadata: { q_rival_order_id: order.id, user_id: user.id, coins: order.coins },
    };

    const mp = await fetch('https://api.mercadopago.com/checkout/preferences', {
      method: 'POST',
      headers: { Authorization: `Bearer ${mpToken}`, 'Content-Type': 'application/json' },
      body: JSON.stringify(preference),
    });
    const mpJson = await mp.json();
    if (!mp.ok) throw new Error(mpJson?.message || 'Mercado Pago recusou a preferência.');

    await admin.from('coin_orders').update({ provider_preference_id: mpJson.id }).eq('id', order.id);
    return new Response(JSON.stringify({ ok: true, checkout_url: mpJson.init_point, order_id: order.id }), { headers: cors });
  } catch (e) {
    return new Response(JSON.stringify({ ok: false, error: e?.message || 'Erro interno.' }), { status: 400, headers: cors });
  }
});
