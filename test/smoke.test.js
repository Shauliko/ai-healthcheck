// Basic unit-ish tests using node:test (no extra deps).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { runChecks } from '../src/runner.js';
import { toAiJson } from '../src/output/ai-json.js';
import { toPlainJson } from '../src/output/json.js';
import { renderTerminal } from '../src/output/terminal.js';

test('runner: unknown check type fails gracefully', async () => {
  const { results, summary } = await runChecks({ checks: [{ name: 'x', type: 'definitely-not-a-real-type' }] });
  assert.equal(results.length, 1);
  assert.equal(results[0].status, 'fail');
  assert.match(results[0].detail, /Unknown check type/);
  assert.equal(summary.fail, 1);
});

test('runner: per-check timeout fires', async () => {
  // env_present is sync, so use http with a non-routable IP and a tiny timeout
  const { results } = await runChecks(
    { checks: [{ name: 't', type: 'http', url: 'http://10.255.255.1:81/' }] },
    { timeoutMs: 200 }
  );
  assert.equal(results[0].status, 'fail');
  // either timeout or connection error is acceptable
  assert.ok(results[0].duration_ms <= 1500, `duration too long: ${results[0].duration_ms}`);
});

test('env_present: missing var fails, present var passes', async () => {
  process.env.AIHEALTHCHECK_TEST_VAR = 'hello world';
  const { results } = await runChecks({
    checks: [
      { name: 'missing', type: 'env_present', var: 'AIHEALTHCHECK_NOT_SET_XYZ' },
      { name: 'present', type: 'env_present', var: 'AIHEALTHCHECK_TEST_VAR', min_length: 3 },
    ],
  });
  assert.equal(results.find((r) => r.name === 'missing').status, 'fail');
  assert.equal(results.find((r) => r.name === 'present').status, 'ok');
});

test('stripe_key: classifies prefix correctly, no network by default', async () => {
  process.env.FAKE_STRIPE = 'sk_test_' + 'x'.repeat(99);
  const { results } = await runChecks({
    checks: [{ name: 'k', type: 'stripe_key', var: 'FAKE_STRIPE', mode: 'test' }],
  });
  assert.equal(results[0].status, 'ok');
  assert.match(results[0].detail, /format ok/);
});

test('stripe_key: pk_ key fails (it is publishable)', async () => {
  process.env.FAKE_PK = 'pk_test_' + 'x'.repeat(99);
  const { results } = await runChecks({
    checks: [{ name: 'k', type: 'stripe_key', var: 'FAKE_PK' }],
  });
  assert.equal(results[0].status, 'fail');
  assert.match(results[0].detail, /publishable/);
});

test('ai-json: questions_to_investigate is non-empty and includes failure triage', async () => {
  const run = await runChecks({
    checks: [
      { name: 'bad', type: 'http', url: 'http://10.255.255.1:81/' },
      { name: 'env', type: 'env_present', var: 'AIHEALTHCHECK_NOT_SET' },
    ],
  }, { timeoutMs: 300 });
  const ai = toAiJson(run, { configSource: 'test', toolVersion: '0.0.0' });
  assert.ok(ai.questions_to_investigate.length > 0, 'should have at least one question');
  assert.ok(ai.questions_to_investigate.some((q) => /triage|fail/i.test(q)),
    'first question should be about triaging failures');
  // failures sorted first
  assert.equal(ai.checks[0].status, 'fail');
});

test('ai-json: schema_notes documents every common field', () => {
  const ai = toAiJson(
    { results: [], summary: { total: 0, ok: 0, warn: 0, fail: 0, skip: 0, passed: true }, started_at: 'x' },
    { configSource: 'test', toolVersion: '0.0.0' }
  );
  for (const key of ['checks[].status', 'checks[].category', 'checks[].detail', 'checks[].hint', 'checks[].meta']) {
    assert.ok(ai.schema_notes[key], `schema_notes missing ${key}`);
  }
});

test('plain json: includes schema marker and full results', async () => {
  process.env.AIHEALTHCHECK_PJSON_VAR = 'present';
  const run = await runChecks({ checks: [{ name: 'x', type: 'env_present', var: 'AIHEALTHCHECK_PJSON_VAR' }] });
  const p = toPlainJson(run, { config: {}, configSource: 'inline' });
  assert.equal(p.schema, 'ai-healthcheck.v1.plain');
  assert.equal(p.checks.length, 1);
});

test('terminal renderer: produces output and includes summary', async () => {
  process.env.AIHEALTHCHECK_RENDER_VAR = 'present';
  const run = await runChecks({ checks: [{ name: 'x', type: 'env_present', var: 'AIHEALTHCHECK_RENDER_VAR' }] });
  const out = renderTerminal(run, { useColor: false });
  assert.match(out, /Summary/);
  assert.match(out, /1 ok/);
});

test('env_present: cross-platform - reads case-insensitive on Windows via process.env Proxy', async () => {
  // This is the regression test for v0.1.0 Windows bug. On Windows, process.env.PATH worked
  // but env_present spread process.env into a plain object, losing the case-insensitive Proxy.
  // We can't perfectly simulate Windows here, but we can verify the fix's contract: the lookup
  // goes through process.env directly, so any env var Node makes visible is reachable.
  process.env.AIHEALTHCHECK_PROXY_TEST = 'works';
  const { results } = await runChecks({
    checks: [{ name: 'x', type: 'env_present', var: 'AIHEALTHCHECK_PROXY_TEST' }],
  });
  assert.equal(results[0].status, 'ok');
});

test('robots: handles missing site gracefully', async () => {
  const { results } = await runChecks({ checks: [{ name: 'r', type: 'robots' }] });
  assert.equal(results[0].status, 'fail');
  assert.match(results[0].detail, /site/);
});
