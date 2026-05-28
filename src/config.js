// Config loader. Reads healthcheck.config.yaml if present, otherwise auto-detects
// reasonable checks from package.json, vercel.json, .env.example.

import { readFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import YAML from 'yaml';

const DEFAULT_CONFIG_NAMES = [
  'healthcheck.config.yaml',
  'healthcheck.config.yml',
  '.healthcheck.yaml',
  '.healthcheck.yml',
];

export function loadConfig({ cwd, configPath }) {
  if (configPath) {
    if (!existsSync(configPath)) {
      throw new Error(`Config not found at ${configPath}`);
    }
    return { config: parseConfigFile(configPath), source: configPath, autoDetected: false };
  }

  for (const name of DEFAULT_CONFIG_NAMES) {
    const p = join(cwd, name);
    if (existsSync(p)) {
      return { config: parseConfigFile(p), source: p, autoDetected: false };
    }
  }

  return { config: autoDetect(cwd), source: '<auto-detected>', autoDetected: true };
}

function parseConfigFile(path) {
  const raw = readFileSync(path, 'utf8');
  const parsed = YAML.parse(raw) || {};
  if (!parsed.checks || !Array.isArray(parsed.checks)) {
    throw new Error(`Config at ${path} must have a top-level "checks:" list`);
  }
  return parsed;
}

function autoDetect(cwd) {
  const checks = [];
  const meta = { source: 'auto' };

  // package.json
  const pkgPath = join(cwd, 'package.json');
  if (existsSync(pkgPath)) {
    try {
      const pkg = JSON.parse(readFileSync(pkgPath, 'utf8'));
      meta.project = pkg.name || null;
      // npm audit always relevant if there's a package.json
      checks.push({ name: 'npm audit (high+)', type: 'npm_audit', level: 'high' });
    } catch {}
  }

  // vercel.json — site URL not stored here usually, but presence signals web app
  // .env.example — auto-add env_present checks for non-secret-looking vars
  const envExamplePath = join(cwd, '.env.example');
  if (existsSync(envExamplePath)) {
    try {
      const text = readFileSync(envExamplePath, 'utf8');
      const vars = text
        .split('\n')
        .map((l) => l.trim())
        .filter((l) => l && !l.startsWith('#') && l.includes('='))
        .map((l) => l.split('=')[0].trim())
        .filter(Boolean);
      for (const v of vars) {
        checks.push({ name: `env: ${v}`, type: 'env_present', var: v, min_length: 1 });
      }
    } catch {}
  }

  // robots / sitemap — only if user can give a URL; in auto mode skip
  return { checks, _auto: true, _meta: meta };
}

export const DEFAULT_CONFIG_FILENAME = 'healthcheck.config.yaml';

export const STARTER_CONFIG = `# ai-healthcheck config
# Run: npx ai-healthcheck run --ai-json
# Drag the resulting .ai.json into Claude/ChatGPT and ask "what's broken?"

site: https://example.com

checks:
  # --- HTTP / pages -------------------------------------------------
  - name: Homepage loads
    type: http
    url: https://example.com
    expect_status: 200
    expect_contains: "Welcome"        # optional content assertion

  - name: API /health returns ok
    type: json_shape
    url: https://example.com/api/health
    expect_status: 200
    expect_keys: [status, version]    # must exist in the JSON response
    expect:                            # optional exact-value assertions
      status: ok

  - name: SSL cert valid for 14+ days
    type: ssl_expiry
    host: example.com
    warn_days: 30
    fail_days: 14

  # --- Config / env -------------------------------------------------
  - name: Database URL set
    type: env_present
    var: DATABASE_URL
    min_length: 20                     # never logs the value, only the length

  - name: Webhook signing secret set
    type: webhook_secret
    var: STRIPE_WEBHOOK_SECRET
    expect_prefix: whsec_

  # --- Integrations -------------------------------------------------
  - name: Stripe key shape
    type: stripe_key
    var: STRIPE_SECRET_KEY
    mode: live                         # live | test | any

  # --- Database -----------------------------------------------------
  # Reads connection string from env. Postgres / Supabase / Neon compatible.
  # Uncomment if you have a DATABASE_URL in your env:
  # - name: Postgres connectivity
  #   type: postgres
  #   var: DATABASE_URL

  # --- SEO ----------------------------------------------------------
  - name: robots.txt reachable
    type: robots
    site: https://example.com

  - name: sitemap reachable
    type: sitemap
    site: https://example.com

  # --- Security -----------------------------------------------------
  - name: npm audit (high+)
    type: npm_audit
    level: high                        # low | moderate | high | critical
`;
