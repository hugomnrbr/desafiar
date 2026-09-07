import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

Deno.serve(async (req) => {
  try {
    if (req.method !== 'POST') return new Response('ok');
    const url = new URL(req.url);
    const body = await req.json().catch(() => ({}));
    const type = body?.type || url.searchParams.get('type');
    const paymentId = body?.data?.id || url.searchParams.get('data.id') || url.searchParams.get('id');
    if (type !== 'payment' || !paymentId) return new Response('ignored', { status: 200 });

    const token = Deno.env.get('MERCADOPAGO_ACCESS_TOKEN')!;
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const admin = createClient(supabaseUrl, serviceKey);
    const mp = await fetch(`https://api.mercadopago.com/v1/payments/${encodeURIComponent(paymentId)}`, {
      headers: { Authorization: `Bearer ${token}` },
    });
    const payment = await mp.json();
    if (!mp.ok) throw new Error(payment?.message || 'Falha ao consultar pagamento.');

    const external = payment?.external_reference;
    if (!external) return new Response('no reference', { status: 200 });
    const { data: order } = await admin.from('coin_orders').select('id,amount_cents').eq('external_reference', external).maybeSingle();
    if (!order) return new Response('order not found', { status: 200 });

    const { error } = await admin.rpc('finalize_coin_payment', {
      p_order_id: order.id,
      p_payment_id: String(payment.id),
      p_status: payment.status,
      p_amount_cents: Math.round(Number(payment.transaction_amount || 0) * 100),
      p_raw: payment,
    });
    if (error) throw error;
    return new Response('ok', { status: 200 });
  } catch (e) {
    console.error(e);
    return new Response('error', { status: 500 });
  }
});
