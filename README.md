# ai-healthcheck

**Monitoring designed for your AI to read, not for you.**

Every uptime monitor -- UptimeRobot, Pingdom, BetterStack, Checkly -- outputs dashboards for humans. But you're not staring at a dashboard. You're in a chat with Claude, ChatGPT, or Cursor.

`ai-healthcheck` runs smoke tests on your stack and emits a JSON file engineered to be dragged into an LLM. Paste the file, ask "what's broken?", get a triaged answer in seconds.

```bash
npx ai-healthcheck init
npx ai-healthcheck run --ai-json
```

Drop the resulting `ai-healthcheck.ai.json` into your AI chat. Done.

---

## The 60-second demo

```text
$ npx ai-healthcheck init
[OK] Wrote healthcheck.config.yaml

$ npx ai-healthcheck run --ai-json

ai-healthcheck -- 8 checks

network
   FAIL  Homepage loads (412ms)
         -> HTTP 503 (expected 200)
         hint: Upstream is erroring -- check server logs.
   OK    SSL cert valid (180ms)

database
   FAIL  Supabase connectivity (94ms)
         -> Postgres error: password authentication failed
         hint: Auth failed -- check DATABASE_URL credentials.

config
   OK    NEXT_PUBLIC_SUPABASE_URL set (1ms)
   OK    STRIPE_SECRET_KEY set (1ms)

security
   OK    npm audit (high+) (1820ms)

seo
   OK    robots.txt (218ms)
   OK    sitemap (191ms)

Summary: 6 ok   2 fail
Tip: re-run with --ai-json to get a file you can paste into Claude/ChatGPT.

Wrote AI-optimized JSON to /Users/you/myapp/ai-healthcheck.ai.json
  -> Drag this into Claude/ChatGPT and ask: "what's broken?"
```

Now paste `ai-healthcheck.ai.json` into Claude:

> **You:** what's broken?
>
> **Claude:** Two failures, both production-impacting.
>
> 1. **Homepage loads** is returning HTTP 503 -- the site itself is down or the upstream (Vercel build, edge function) is erroring. Check your deploy logs first.
> 2. **Supabase connectivity** is failing with "password authentication failed" -- your `DATABASE_URL` credentials have either rotated, been edited, or the pooler URL changed. These are likely independent; the 503 isn't caused by the DB if your homepage doesn't touch Postgres.
>
> Fix order: ship the deploy/rollback to get the page back, then rotate the DB credential and update env vars.

That answer didn't come from a clever prompt. It came from the JSON, which has:

- `instructions_for_ai` at the top, telling the LLM how to read the file
- `questions_to_investigate` -- a checklist the LLM works through
- `schema_notes` so it never guesses what a field means
- Failures sorted to the top

---

## Why this exists

The audience: indie hackers, side-project shippers, people building real software with Cursor, Claude, Bolt, v0 -- who already paste error messages into AI all day.

The traditional monitoring stack assumes you're going to look at a dashboard. You're not. You're going to ask your AI. This tool meets you where you actually live.

It is **not** a replacement for a real observability platform if you have one. It's a 60-second drop-in for the gap between "I have nothing" and "I'm spending $50/mo on a tool whose dashboard I'll never open."

---

## Install

No install needed:

```bash
npx ai-healthcheck run
```

Or pin it:

```bash
npm install --save-dev ai-healthcheck
```

---

## Configuration

`ai-healthcheck init` scaffolds `healthcheck.config.yaml`. The structure:

```yaml
site: https://example.com

checks:
  - name: Homepage loads
    type: http
    url: https://example.com
    expect_status: 200
    expect_contains: "Welcome"

  - name: SSL cert valid
    type: ssl_expiry
    host: example.com
    warn_days: 30
    fail_days: 7
```

If no config file exists, `ai-healthcheck` auto-detects checks from `package.json` and `.env.example`. Better than nothing; not as good as a real config.

See [`examples/`](./examples/) for full configs:

- [Next.js + Supabase + Stripe](./examples/nextjs-supabase-stripe.yaml)
- [Static site on Vercel](./examples/vercel-static.yaml)

---

## Built-in checks

| Type | What it does |
|---|---|
| `http` | GETs a URL, asserts status code, optional `expect_contains` body marker |
| `json_shape` | GETs JSON, asserts `expect_keys` exist + optional `expect` exact-value match |
| `ssl_expiry` | TLS handshake, reports days until cert expires (`warn_days`/`fail_days`) |
| `env_present` | Asserts an env var is set and meets `min_length`. Never logs the value. |
| `postgres` | `SELECT 1` against `DATABASE_URL` (any Postgres: Supabase, Neon, RDS) |
| `stripe_key` | Validates Stripe key prefix and mode. `--with-network` actually hits `/v1/balance`. |
| `webhook_secret` | Asserts a webhook signing secret is set with the expected prefix |
| `npm_audit` | Runs `npm audit --json`, fails on vulns at or above `level` |
| `sitemap` | Fetches `/sitemap.xml`, handles sitemap-index, counts URLs |
| `robots` | Fetches `/robots.txt`, warns on accidental `Disallow: /` (the classic prod leak) |

---

## CLI flags

```text
--config <path>      ./healthcheck.config.yaml by default
--json [path]        Write plain JSON (default: ./ai-healthcheck.out.json)
--ai-json [path]     Write AI-optimized JSON (default: ./ai-healthcheck.ai.json)
--with-network       Allow checks that call third-party APIs with your secrets
--timeout <ms>       Per-check timeout (default: 8000)
--quiet              Suppress per-check output; print summary only
--no-color           Disable ANSI colors
```

Exit codes: `0` all passed, `1` one or more failed, `2` bad config / runtime error.

---

## Security: secrets

- `env_present`, `webhook_secret`, `stripe_key` (format mode), and `postgres` (uses connection string) **never log secret values**. They report only presence, length, and prefix.
- Network-secret checks like `stripe_key --with-network` are **opt-in**. They do not run by default, because we don't want your live key crossing the wire on every CI run unless you choose it.
- The tool reads `.env` and `.env.local` from the cwd; it never writes them.

---

## Use in CI

```yaml
# .github/workflows/healthcheck.yml
on: [push, pull_request]
jobs:
  healthcheck:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with: { node-version: '20' }
      - run: npx ai-healthcheck run --ai-json
      - uses: actions/upload-artifact@v4
        if: always()
        with:
          name: healthcheck
          path: ai-healthcheck.ai.json
```

Now when CI fails, you have an artifact you can drop into Claude.

---

## What's coming (not in v1)

- Hosted version with scheduled runs and email/Slack alerts
- Diff detection (don't spam on the same chronic warning)
- A library of community check types

If you want any of these, open an issue and tell me.

---

## License

MIT.
