// HTTP check — GET a URL, assert status code, optional content marker.
export default {
  async run(check, { signal }) {
    if (!check.url) return { status: 'fail', detail: 'http check missing "url"', hint: 'Add url: https://...' };
    const expectStatus = check.expect_status ?? 200;
    const method = (check.method || 'GET').toUpperCase();

    let res;
    try {
      res = await fetch(check.url, { method, signal, redirect: check.follow_redirects === false ? 'manual' : 'follow' });
    } catch (e) {
      return { status: 'fail', detail: `fetch failed: ${e.message}`, hint: 'Is the URL reachable? Check DNS, firewall, and that the service is up.' };
    }

    if (res.status !== expectStatus) {
      return {
        status: 'fail',
        detail: `HTTP ${res.status} (expected ${expectStatus})`,
        hint: res.status >= 500 ? 'Upstream is erroring — check server logs.' :
              res.status === 404 ? 'Route not deployed or path is wrong.' :
              res.status === 401 || res.status === 403 ? 'Auth failing — check tokens/cookies.' :
              `Got ${res.status}, expected ${expectStatus}.`,
        meta: { actual_status: res.status, expected_status: expectStatus },
      };
    }

    if (check.expect_contains) {
      const body = await res.text();
      const needle = check.expect_contains;
      if (!body.includes(needle)) {
        return {
          status: 'fail',
          detail: `Response body did not contain "${needle}"`,
          hint: 'Page is loading but rendering empty/wrong content — check build output and SSR.',
          meta: { body_length: body.length, body_preview: body.slice(0, 200) },
        };
      }
    }

    return { status: 'ok', detail: `HTTP ${res.status}` };
  },
};
