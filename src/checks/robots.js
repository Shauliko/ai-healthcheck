// robots.txt presence + sanity check.
function joinUrl(site, path) {
  try { return new URL(path, site).toString(); }
  catch { return site.replace(/\/$/, '') + (path.startsWith('/') ? path : '/' + path); }
}

export default {
  async run(check, { signal }) {
    const site = check.site || check.url;
    if (!site) return { status: 'fail', detail: 'robots check missing "site"', hint: 'Add site: https://example.com' };
    const url = joinUrl(site, '/robots.txt');

    let res;
    try {
      res = await fetch(url, { signal });
    } catch (e) {
      return { status: 'fail', detail: `fetch failed: ${e.message}`, hint: 'robots.txt not reachable.' };
    }
    if (res.status === 404) {
      return { status: 'warn', detail: 'robots.txt missing (404)', hint: 'Not required, but standard for SEO.' };
    }
    if (res.status !== 200) {
      return { status: 'fail', detail: `HTTP ${res.status} at ${url}` };
    }
    const body = (await res.text()).trim();
    if (!body) return { status: 'warn', detail: 'robots.txt is empty', hint: 'Empty robots.txt does nothing — add at least User-agent: *.' };

    // Soft warn if the entire file is "Disallow: /" — usually means a staging env that leaked into prod.
    if (/^\s*User-agent:\s*\*\s*\n\s*Disallow:\s*\/\s*$/im.test(body) && body.split('\n').length < 4) {
      return {
        status: 'warn',
        detail: 'robots.txt blocks all crawlers (Disallow: /)',
        hint: 'If this is production, you are invisible to Google. Staging robots probably leaked into prod.',
      };
    }
    return { status: 'ok', detail: `robots.txt ok (${body.length} bytes)` };
  },
};
