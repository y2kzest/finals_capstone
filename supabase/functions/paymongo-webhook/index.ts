// PayMongo webhook receiver. Verifies the signature (when configured),
// then handles:
//   - source.chargeable  → create Payment using the source, mark orders paid
//   - source.failed      → mark orders failed
//   - payment.paid       → mark orders paid (cards / payment-intent flow)
//   - payment.failed     → mark orders failed
//
// IMPORTANT: This function MUST be deployed with --no-verify-jwt so PayMongo
// can call it without a Supabase session:
//   supabase functions deploy paymongo-webhook --no-verify-jwt
//
// Signature verification is enforced when PAYMONGO_WEBHOOK_SECRET is set.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const PAYMONGO_BASE = 'https://api.paymongo.com/v1';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type, paymongo-signature',
};

function text(body: string, status = 200): Response {
  return new Response(body, {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'text/plain' },
  });
}

// PayMongo signature is "t=<ts>,te=<sig>,li=<sig>"; verify the live (li) sig
// in production, test (te) sig in test mode.
async function verifySignature(
  rawBody: string,
  signatureHeader: string,
  secret: string,
): Promise<boolean> {
  const parts = Object.fromEntries(
    signatureHeader.split(',').map((p) => {
      const [k, v] = p.split('=');
      return [k?.trim() ?? '', v?.trim() ?? ''];
    }),
  );
  const ts = parts['t'];
  const sig = parts['li'] || parts['te'];
  if (!ts || !sig) return false;

  const payload = `${ts}.${rawBody}`;
  const key = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const sigBytes = await crypto.subtle.sign(
    'HMAC',
    key,
    new TextEncoder().encode(payload),
  );
  const computed = Array.from(new Uint8Array(sigBytes))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');

  // Constant-time compare
  if (computed.length !== sig.length) return false;
  let diff = 0;
  for (let i = 0; i < computed.length; i++) {
    diff |= computed.charCodeAt(i) ^ sig.charCodeAt(i);
  }
  return diff === 0;
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (req.method !== 'POST') return text('method not allowed', 405);

  const PAYMONGO_SK = Deno.env.get('PAYMONGO_SECRET_KEY');
  const SUPABASE_URL = Deno.env.get('SUPABASE_URL');
  const SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  const WEBHOOK_SECRET = Deno.env.get('PAYMONGO_WEBHOOK_SECRET');
  if (!PAYMONGO_SK || !SUPABASE_URL || !SERVICE_KEY) {
    return text('server not configured', 500);
  }

  const rawBody = await req.text();

  // Signature check (only enforced when secret is configured)
  if (WEBHOOK_SECRET) {
    const sigHeader = req.headers.get('paymongo-signature') ?? '';
    const valid = await verifySignature(rawBody, sigHeader, WEBHOOK_SECRET);
    if (!valid) return text('invalid signature', 401);
  }

  let payload: any;
  try {
    payload = JSON.parse(rawBody);
  } catch {
    return text('invalid JSON', 400);
  }

  const event = payload?.data?.attributes;
  if (!event) return text('no event attributes', 400);

  const eventType = String(event.type ?? '');
  const resource = event.data;
  if (!resource) return text('no event data', 400);

  const admin = createClient(SUPABASE_URL, SERVICE_KEY, {
    auth: { persistSession: false },
  });

  try {
    if (eventType === 'source.chargeable') {
      const sourceId = String(resource.id ?? '');
      const amount = Number(resource.attributes?.amount ?? 0);
      if (!sourceId || amount < 100) return text('bad source payload', 400);

      // Find orders waiting on this source (full details for notifications)
      const { data: orders, error: ordErr } = await admin
        .from('orders')
        .select(
          'id, buyer_id, seller_id, product_name, qty, total_amount, order_type, payment_status',
        )
        .eq('paymongo_source_id', sourceId);
      if (ordErr) return text(`db error: ${ordErr.message}`, 500);
      if (!orders || orders.length === 0) {
        // Source we don't know about — acknowledge so PayMongo stops retrying
        return text('no orders for source (ack)', 200);
      }
      // Idempotency: if already paid, just acknowledge
      if (orders.every((o) => o.payment_status === 'paid')) {
        return text('already paid (ack)', 200);
      }

      // Create the Payment using the source
      const payRes = await fetch(`${PAYMONGO_BASE}/payments`, {
        method: 'POST',
        headers: {
          Authorization: `Basic ${btoa(`${PAYMONGO_SK}:`)}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          data: {
            attributes: {
              amount,
              currency: 'PHP',
              source: { id: sourceId, type: 'source' },
              description: `QuickCart order(s): ${orders.map((o) => o.id).join(',')}`,
            },
          },
        }),
      });

      if (!payRes.ok) {
        const errBody = await payRes.text();
        console.error('paymongo /payments failed', errBody);
        await admin
          .from('orders')
          .update({ payment_status: 'failed' })
          .eq('paymongo_source_id', sourceId);
        return text('payment creation failed', 500);
      }

      const payJson = await payRes.json();
      const paymentId = String(payJson?.data?.id ?? '');

      await admin
        .from('orders')
        .update({
          payment_status: 'paid',
          paymongo_payment_id: paymentId || null,
          paid_at: new Date().toISOString(),
        })
        .eq('paymongo_source_id', sourceId);

      // Notify sellers + buyers now that payment is confirmed.
      // (Seller notifications were intentionally skipped on order insert for
      // online-payment orders, so unpaid orders don't reach the seller.)
      for (const o of orders) {
        const qty = Number(o.qty ?? 1);
        const total = Number(o.total_amount ?? 0);
        const itemLine =
          `${o.product_name ?? 'Item'} x${qty} — ₱${total.toFixed(0)}` +
          (o.order_type === 'delivery' ? ' (Delivery)' : '');
        if (o.seller_id) {
          await admin.from('seller_notifications').insert({
            seller_id: o.seller_id,
            order_id: o.id,
            title: 'New Order — GCash Paid!',
            body: itemLine,
            type: 'new_order',
          });
          // Separate payment-receipt notification so the seller can see it
          // in the notification panel alongside the order notification.
          await admin.from('seller_notifications').insert({
            seller_id: o.seller_id,
            order_id: o.id,
            title: 'Payment Received',
            body: `GCash payment of ₱${total.toFixed(2)} confirmed for ${o.product_name ?? 'your order'}.`,
            type: 'payment_received',
          });
        }
        await admin.from('notifications').insert({
          user_id: o.buyer_id,
          type: 'payment_received',
          title: 'GCash Payment Confirmed',
          message: `Your GCash payment of ₱${total.toFixed(2)} for ${o.product_name ?? 'your order'} was received.`,
          is_read: false,
        });
      }

      return text('ok', 200);
    }

    if (eventType === 'checkout_session.payment.paid') {
      // Maya (and any future Checkout-Sessions-only methods) flow through here.
      // The order row stores the checkout session id in `paymongo_source_id`
      // (reusing the same column — it's just a string id from PayMongo).
      const csId = String(resource.id ?? '');
      if (!csId) return text('bad checkout session payload', 400);

      const { data: orders, error: ordErr } = await admin
        .from('orders')
        .select(
          'id, buyer_id, seller_id, product_name, qty, total_amount, order_type, payment_status',
        )
        .eq('paymongo_source_id', csId);
      if (ordErr) return text(`db error: ${ordErr.message}`, 500);
      if (!orders || orders.length === 0) {
        return text('no orders for checkout session (ack)', 200);
      }
      if (orders.every((o) => o.payment_status === 'paid')) {
        return text('already paid (ack)', 200);
      }

      // Checkout Session payloads include the underlying payment(s)
      const paymentId =
        String(resource.attributes?.payments?.[0]?.id ?? '') || null;

      await admin
        .from('orders')
        .update({
          payment_status: 'paid',
          paymongo_payment_id: paymentId,
          paid_at: new Date().toISOString(),
        })
        .eq('paymongo_source_id', csId);

      for (const o of orders) {
        const qty = Number(o.qty ?? 1);
        const total = Number(o.total_amount ?? 0);
        const itemLine =
          `${o.product_name ?? 'Item'} x${qty} — ₱${total.toFixed(0)}` +
          (o.order_type === 'delivery' ? ' (Delivery)' : '');
        if (o.seller_id) {
          await admin.from('seller_notifications').insert({
            seller_id: o.seller_id,
            order_id: o.id,
            title: 'New Order — Maya Paid!',
            body: itemLine,
            type: 'new_order',
          });
          // Separate payment-receipt notification so the seller can see it
          // in the notification panel alongside the order notification.
          await admin.from('seller_notifications').insert({
            seller_id: o.seller_id,
            order_id: o.id,
            title: 'Payment Received',
            body: `Maya payment of ₱${total.toFixed(2)} confirmed for ${o.product_name ?? 'your order'}.`,
            type: 'payment_received',
          });
        }
        await admin.from('notifications').insert({
          user_id: o.buyer_id,
          type: 'payment_received',
          title: 'Maya Payment Confirmed',
          message: `Your Maya payment of ₱${total.toFixed(2)} for ${o.product_name ?? 'your order'} was received.`,
          is_read: false,
        });
      }

      return text('ok', 200);
    }

    if (eventType === 'source.failed' || eventType === 'source.expired') {
      const sourceId = String(resource.id ?? '');
      if (!sourceId) return text('bad source payload', 400);
      await admin
        .from('orders')
        .update({ payment_status: 'failed' })
        .eq('paymongo_source_id', sourceId);
      return text('ok', 200);
    }

    if (eventType === 'payment.paid') {
      // Card / payment-intent path (Phase 3)
      const paymentId = String(resource.id ?? '');
      const intentId = String(resource.attributes?.payment_intent_id ?? '');
      const matchId = intentId || paymentId;
      if (!matchId) return text('bad payment payload', 400);
      await admin
        .from('orders')
        .update({
          payment_status: 'paid',
          paymongo_payment_id: paymentId,
          paid_at: new Date().toISOString(),
        })
        .eq('paymongo_payment_intent_id', matchId);
      return text('ok', 200);
    }

    if (eventType === 'payment.failed') {
      const paymentId = String(resource.id ?? '');
      const intentId = String(resource.attributes?.payment_intent_id ?? '');
      const matchId = intentId || paymentId;
      if (!matchId) return text('bad payment payload', 400);
      await admin
        .from('orders')
        .update({ payment_status: 'failed' })
        .eq('paymongo_payment_intent_id', matchId);
      return text('ok', 200);
    }

    // Unhandled event — acknowledge so PayMongo doesn't retry forever
    return text(`unhandled event: ${eventType}`, 200);
  } catch (e) {
    console.error('webhook error', e);
    return text(`error: ${e}`, 500);
  }
});
