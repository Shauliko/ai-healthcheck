// Cross-platform env var lookup.
//
// Why this exists: on Windows, process.env is exposed through a case-insensitive
// Proxy, so process.env.PATH and process.env.Path both work. If you spread it
// into a plain object (`{ ...process.env }`), you LOSE that Proxy and reads
// become case-sensitive against whatever case Windows actually stored. This
// caused PATH lookups to fail on Windows in v0.1.0.
//
// Fix: check process.env directly first (Proxy intact), fall back to .env files.

import { readFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';

let dotenvCache = null;

export function loadDotenvFiles(cwd) {
  if (dotenvCache) return dotenvCache;
  const map = {};
  for (const name of ['.env.local', '.env']) {
    const p = join(cwd || process.cwd(), name);
    if (!existsSync(p)) continue;
    try {
      const text = readFileSync(p, 'utf8');
      for (const line of text.split('\n')) {
        const t = line.trim();
        if (!t || t.startsWith('#')) continue;
        const eq = t.indexOf('=');
        if (eq < 0) continue;
        const k = t.slice(0, eq).trim();
        let v = t.slice(eq + 1).trim();
        if ((v.startsWith('"') && v.endsWith('"')) || (v.startsWith("'") && v.endsWith("'"))) {
          v = v.slice(1, -1);
        }
        if (!(k in map)) map[k] = v;
      }
    } catch {}
  }
  dotenvCache = map;
  return dotenvCache;
}

export function envGet(varName, cwd) {
  // process.env first - on Windows this hits Node's case-insensitive Proxy
  const v = process.env[varName];
  if (v !== undefined && v !== '') return v;
  // .env / .env.local fallback (case-sensitive, but at least consistent)
  return loadDotenvFiles(cwd || process.cwd())[varName];
}

// For tests
export function _resetCache() { dotenvCache = null; }
