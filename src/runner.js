// Parallel check runner with per-check timeout.
// Each check returns { name, category, status, detail, hint, duration_ms, type, target }.

import { CHECKS } from './checks/index.js';

const STATUSES = new Set(['ok', 'warn', 'fail', 'skip']);

function normalizeResult(check, raw, durationMs) {
  const base = {
    name: check.name || check.type,
    category: check.category || categoryFor(check.type),
    type: check.type,
    target: check.target || check.url || check.path || check.var || null,
    status: 'ok',
    detail: '',
    hint: '',
    duration_ms: durationMs,
  };
  if (!raw || typeof raw !== 'object') return { ...base, status: 'fail', detail: 'Check returned no result' };
  const status = STATUSES.has(raw.status) ? raw.status : 'fail';
  return {
    ...base,
    status,
    detail: typeof raw.detail === 'string' ? raw.detail : (raw.detail ? String(raw.detail) : ''),
    hint: typeof raw.hint === 'string' ? raw.hint : '',
    meta: raw.meta || undefined,
  };
}

function categoryFor(type) {
  if (!type) return 'other';
  if (type.startsWith('http') || type === 'json_shape' || type === 'ssl_expiry') return 'network';
  if (type === 'env_present') return 'config';
  if (type === 'postgres') return 'database';
  if (type === 'stripe_key' || type === 'webhook_secret') return 'integrations';
  if (type === 'npm_audit') return 'security';
  if (type === 'sitemap' || type === 'robots') return 'seo';
  return 'other';
}

function withTimeout(promise, ms, controller) {
  return new Promise((resolve, reject) => {
    const t = setTimeout(() => {
      try { controller.abort(); } catch {}
      reject(new Error(`timeout after ${ms}ms`));
    }, ms);
    promise.then(
      (v) => { clearTimeout(t); resolve(v); },
      (e) => { clearTimeout(t); reject(e); }
    );
  });
}

export async function runChecks(config, options = {}) {
  const {
    timeoutMs = 8000,
    withNetwork = false,
    onCheckStart,
    onCheckEnd,
  } = options;

  const checks = Array.isArray(config.checks) ? config.checks : [];

  const tasks = checks.map(async (check) => {
    const handler = CHECKS[check.type];
    const startedAt = Date.now();

    if (onCheckStart) onCheckStart(check);

    if (!handler) {
      const result = normalizeResult(check, {
        status: 'fail',
        detail: `Unknown check type: ${check.type}`,
        hint: `Valid types: ${Object.keys(CHECKS).join(', ')}`,
      }, 0);
      if (onCheckEnd) onCheckEnd(result);
      return result;
    }

    if (handler.requiresNetworkSecret && !withNetwork) {
      const result = normalizeResult(check, {
        status: 'skip',
        detail: 'Skipped: this check calls an external API with a secret. Re-run with --with-network to enable.',
        hint: '',
      }, 0);
      if (onCheckEnd) onCheckEnd(result);
      return result;
    }

    const controller = new AbortController();
    const perCheckTimeout = typeof check.timeout_ms === 'number' ? check.timeout_ms : timeoutMs;

    try {
      const raw = await withTimeout(
        Promise.resolve(handler.run(check, { signal: controller.signal, withNetwork })),
        perCheckTimeout,
        controller,
      );
      const result = normalizeResult(check, raw, Date.now() - startedAt);
      if (onCheckEnd) onCheckEnd(result);
      return result;
    } catch (err) {
      const result = normalizeResult(check, {
        status: 'fail',
        detail: err && err.message ? err.message : String(err),
        hint: err && err.message && err.message.startsWith('timeout')
          ? `Check exceeded ${perCheckTimeout}ms — slow upstream or network issue.`
          : '',
      }, Date.now() - startedAt);
      if (onCheckEnd) onCheckEnd(result);
      return result;
    }
  });

  const results = await Promise.all(tasks);

  const summary = {
    total: results.length,
    ok: results.filter((r) => r.status === 'ok').length,
    warn: results.filter((r) => r.status === 'warn').length,
    fail: results.filter((r) => r.status === 'fail').length,
    skip: results.filter((r) => r.status === 'skip').length,
  };
  summary.passed = summary.fail === 0;

  return { results, summary, started_at: new Date().toISOString() };
}
