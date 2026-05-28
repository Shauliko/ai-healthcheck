// Sitemap check. Supports sitemap-index (recurses one level).
function joinUrl(site, path) {
  try {
    return new URL(path, site).toString();
  } catch {
    return site.replace(/\/$/, '') + (path.startsWith('/') ? path : '/' + path);
  }
}

function countLocs(xml) {
  const m = xml.match(/<loc>[^<]+<\/loc>/g);
  return m ? m.length : 0;
}

function isSitemapIndex(xml) {
  return /<sitemapindex\b/i.test(xml);
}

function extractLocs(xml, limit = 5) {
  const out = [];
  const re = /<loc>\s*([^<]+?)\s*<\/loc>/g;
  let m; while ((m = re.exec(xml)) && out.length < limit) out.push(m[1]);
  return out;
}

export default {
  async run(check, { signal }) {
    const site = check.site || check.url;
    if (!site) return { status: 'fail', detail: 'sitemap check missing "site"', hint: 'Add site: https://example.com' };
    const sitemapUrl = check.path ? joinUrl(site, check.path) : joinUrl(site, '/sitemap.xml');

    let res;
    try {
      res = await fetch(sitemapUrl, { signal });
    } catch (e) {
      return { status: 'fail', detail: `fetch failed: ${e.message}`, hint: 'Sitemap not reachable.' };
    }
    if (res.status !== 200) {
      return { status: 'fail', detail: `HTTP ${res.status} at ${sitemapUrl}`, hint: 'No sitemap at the standard path.' };
    }
    const ct = res.headers.get('content-type') || '';
    const body = await res.text();
    const looksXml = body.trimStart().startsWith('<');
    if (!looksXml) {
      return { status: 'fail', detail: `Sitemap not XML (content-type: ${ct})`, hint: 'Server returned HTML — likely a misconfigured route.' };
    }
    if (isSitemapIndex(body)) {
      const children = extractLocs(body, 3);
      if (children.length === 0) {
        return { status: 'warn', detail: 'sitemap-index with zero child sitemaps', hint: 'Index is empty — nothing will be crawled.' };
      }
      // Lightly probe the first child to ensure it resolves.
      try {
        const childRes = await fetch(children[0], { signal });
        if (!childRes.ok) {
          return { status: 'warn', detail: `Index ok; first child ${children[0]} returned ${childRes.status}`, meta: { children } };
        }
        const childBody = await childRes.text();
        return {
          status: 'ok',
          detail: `sitemap-index ok (${children.length} child sitemap${children.length === 1 ? '' : 's'} sampled; first has ${countLocs(childBody)} URLs)`,
          meta: { children, sampled_child_url_count: countLocs(childBody) },
        };
      } catch (e) {
        return { status: 'warn', detail: `Index ok; child fetch failed: ${e.message}`, meta: { children } };
      }
    }
    const n = countLocs(body);
    if (n === 0) return { status: 'warn', detail: 'sitemap has zero <loc> entries', hint: 'Build step did not emit URLs.' };
    return { status: 'ok', detail: `sitemap ok (${n} URLs)`, meta: { url_count: n } };
  },
};
