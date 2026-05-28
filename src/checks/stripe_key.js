// Stripe secret key validation.
// Default: format/prefix check (no network). Opt-in --with-network: fetch /v1/balance.
import { envGet } from '../env-util.js';

function classify(key) {
  if (!key) return { kind: 'missing' };
  if (key.startsWith('sk_live_')) return { kind: 'live' };
  if (key.startsWith('sk_test_')) return { kind: 'test' };
  if (key.startsWith('rk_live_')) return { kind: 'restricted_live' };
  if (key.startsWith('rk_test_')) return { kind: 'restricted_test' };
  if (key.startsWith('pk_')) return { kind: 'publishable' };
  return { kind: 'unknown' };
}

export default {
  requiresNetworkSecret: false,
  async run(check, { signal, withNetwork }) {
    const key = envGet(check.var || 'STRIPE_SECRET_KEY', process.cwd());
    const mode = check.mode || 'any';
    const wantNetwork = check.with_network === true || (check.with_network !== false && withNetwork);

    if (!key) {
      return { status: 'fail', detail: `${check.var || 'STRIPE_SECRET_KEY'} is not set`,
               hint: 'Add the key to your env. Use sk_test_ in dev, sk_live_ in prod.' };
    }
    const { kind } = classify(key);
    if (kind === 'publishable') {
      return { status: 'fail', detail: 'Got a publishable key (pk_...) instead of a secret key',
               hint: 'Use sk_live_ or sk_test_ - pk_ is for client-side only.' };
    }
    if (kind === 'unknown') {
      return { status: 'fail', detail: 'Key does not look like a Stripe key (expected sk_live_/sk_test_/rk_)',
               hint: 'Double-check the env var maps to the Stripe secret key.' };
    }
    if (mode === 'live' && !kind.includes('live')) {
      return { status: 'fail', detail: `Expected live key, got ${kind}`,
               hint: "Production should use sk_live_ - sk_test_ won't charge real cards." };
    }
    if (mode === 'test' && !kind.includes('test')) {
      return { status: 'warn', detail: `Expected test key, got ${kind}`,
               hint: 'Dev/CI should use sk_test_ to avoid touching real customers.' };
    }
    if (key.length < 30) {
      return { status: 'fail', detail: `Key is suspiciously short (${key.length} chars)`,
               hint: 'Probably a placeholder, not a real key.' };
    }

    if (!wantNetwork) {
      return { status: 'ok', detail: `format ok (${kind}, length=${key.length})` };
    }

    try {
      const res = await fetch('https://api.stripe.com/v1/balance', {
        headers: { Authorization: `Bearer ${key}` },
        signal,
      });
      if (res.status === 401) {
        return { status: 'fail', detail: 'Stripe rejected the key (401)',
                 hint: 'Key is revoked, rotated, or for a different account.' };
      }
      if (!res.ok) {
        return { status: 'warn', detail: `Stripe /v1/balance returned ${res.status}`,
                 hint: 'Non-401 error - check Stripe status page.' };
      }
      return { status: 'ok', detail: `live API call ok (${kind})` };
    } catch (e) {
      return { status: 'warn', detail: `Network call failed: ${e.message}`, hint: 'Outbound to api.stripe.com blocked?' };
    }
  },
};
