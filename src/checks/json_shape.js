// JSON shape check — GET a URL, parse as JSON, assert top-level keys and optional values.
export default {
  async run(check, { signal }) {
    if (!check.url) return { status: 'fail', detail: 'json_shape check missing "url"', hint: 'Add url: https://...' };
    const expectStatus = check.expect_status ?? 200;

    let res;
    try {
      res = await fetch(check.url, { signal });
    } catch (e) {
      return { status: 'fail', detail: `fetch failed: ${e.message}`, hint: 'Is the endpoint up?' };
    }

    if (res.status !== expectStatus) {
      return { status: 'fail', detail: `HTTP ${res.status} (expected ${expectStatus})`, meta: { actual_status: res.status } };
    }

    let body;
    try {
      body = await res.json();
    } catch (e) {
      return { status: 'fail', detail: 'Response was not valid JSON', hint: 'Endpoint returned HTML or malformed JSON.' };
    }

    const missing = [];
    if (Array.isArray(check.expect_keys)) {
      for (const k of check.expect_keys) {
        if (!(k in (body || {}))) missing.push(k);
      }
    }
    if (missing.length) {
      return {
        status: 'fail',
        detail: `Missing keys: ${missing.join(', ')}`,
        hint: 'Response shape changed — check the endpoint contract.',
        meta: { missing_keys: missing, got_keys: Object.keys(body || {}) },
      };
    }

    if (check.expect && typeof check.expect === 'object') {
      const mismatches = [];
      for (const [k, v] of Object.entries(check.expect)) {
        if (body?.[k] !== v) mismatches.push({ key: k, expected: v, got: body?.[k] });
      }
      if (mismatches.length) {
        return {
          status: 'fail',
          detail: `Value mismatch on: ${mismatches.map((m) => m.key).join(', ')}`,
          hint: 'Endpoint returned unexpected values — likely an env/feature flag drift.',
          meta: { mismatches },
        };
      }
    }

    return { status: 'ok', detail: 'shape ok' };
  },
};
