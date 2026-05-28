// THE differentiator. JSON specifically engineered to be pasted into Claude/ChatGPT/Cursor.
//
// Design decisions:
//  - `instructions_for_ai` is FIRST so the LLM reads it before the data.
//  - `questions_to_investigate` is a checklist tailored to the failures seen.
//  - `schema_notes` explains every field so the model never guesses.
//  - Checks sorted: fail > warn > skip > ok, so the most important findings are read first.
//  - `summary.headline` is a one-sentence triage the LLM can quote back to the user.

const STATUS_RANK = { fail: 0, warn: 1, skip: 2, ok: 3 };

function buildQuestions({ results, summary }) {
  const qs = [];
  const fails = results.filter((r) => r.status === 'fail');
  const warns = results.filter((r) => r.status === 'warn');

  if (summary.fail === 0 && summary.warn === 0) {
    return [
      'All checks passed. Is there anything in the `meta` fields that suggests upcoming risk (e.g. SSL cert getting close to renewal, audit warnings just under threshold)?',
      'Are there obvious checks missing for this stack that I should add to my config?',
    ];
  }

  if (fails.length) {
    if (fails.length === 1) {
      qs.push('Triage this 1 failed check. What is the most likely root cause and the fastest fix?');
    } else {
      qs.push(`Triage these ${fails.length} failed checks in order of likely user impact. Which one is breaking production right now?`);
    }
    qs.push('For each failed check, give me the single highest-leverage fix I can ship in the next 15 minutes.');
  }

  const byCategory = new Set(results.map((r) => r.category));
  if (byCategory.has('network') && fails.some((f) => f.category === 'network')) {
    qs.push('Multiple network checks are failing - is this a DNS issue, a deploy that broke routes, or an outage at the upstream provider?');
  }
  if (byCategory.has('database') && fails.some((f) => f.category === 'database')) {
    qs.push('The DB connectivity check failed. Walk me through the most likely root causes (credentials rotated, IP allowlist, pooler URL vs direct URL, region drift).');
  }
  if (byCategory.has('config') && fails.some((f) => f.category === 'config')) {
    qs.push('Env var checks failed. Could these be set in Vercel/Netlify/Railway but missing from my local .env? Or vice versa?');
  }
  if (byCategory.has('security') && (fails.some((f) => f.category === 'security') || warns.some((w) => w.category === 'security'))) {
    qs.push('What is the actual exploit risk of the npm audit findings, and which dependency upgrades carry breaking-change risk?');
  }
  if (byCategory.has('integrations') && fails.some((f) => f.category === 'integrations')) {
    qs.push('Integration/key checks failed. Is the wrong environment (test vs live) likely loaded?');
  }

  if (warns.length) {
    const word = warns.length === 1 ? '1 warning' : `${warns.length} warnings`;
    const verb = warns.length === 1 ? 'is' : 'are';
    qs.push(`There ${verb} ${word} - should any be promoted to a failing check based on the meta fields?`);
  }

  qs.push('Are there patterns across these results (timing, region, dependency) that suggest a single underlying root cause?');

  return qs.slice(0, 8);
}

function buildHeadline({ results, summary }) {
  if (summary.fail === 0 && summary.warn === 0) return 'All checks passing.';
  if (summary.fail === 0) {
    return summary.warn === 1 ? '1 warning; no failures.' : `${summary.warn} warnings; no failures.`;
  }
  const firstFail = results.find((r) => r.status === 'fail');
  const failPart = summary.fail === 1 ? '1 failure' : `${summary.fail} failures`;
  const warnPart = summary.warn === 0 ? '' :
                   summary.warn === 1 ? ', 1 warning' : `, ${summary.warn} warnings`;
  return `${failPart}${warnPart}. First failure: ${firstFail.name} - ${firstFail.detail}`;
}

function sortForLlm(results) {
  return [...results].sort((a, b) => {
    const rs = STATUS_RANK[a.status] - STATUS_RANK[b.status];
    if (rs !== 0) return rs;
    return (a.category || '').localeCompare(b.category || '');
  });
}

export function toAiJson({ results, summary, started_at }, { configSource, toolVersion }) {
  const sorted = sortForLlm(results);
  return {
    schema: 'ai-healthcheck.v1.ai',
    tool: 'ai-healthcheck',
    tool_version: toolVersion,

    instructions_for_ai: [
      "You are reading the output of ai-healthcheck, a smoke-test runner for a developer's stack.",
      'Your job: triage what is broken, in plain language, with concrete next steps.',
      'Use the `questions_to_investigate` below as a checklist - answer each one that applies.',
      'Quote the `name` of failing checks verbatim so the user can map answers back.',
      'Do NOT invent fixes; if a check has a `hint`, prefer that as your starting point.',
      'Failed checks come first in the `checks` array. Within each check, `meta` carries the structured evidence.',
    ],

    questions_to_investigate: buildQuestions({ results, summary }),

    summary: {
      ...summary,
      headline: buildHeadline({ results, summary }),
    },

    schema_notes: {
      'checks[].status': 'one of: ok | warn | fail | skip',
      'checks[].category': 'network | config | database | integrations | security | seo | other',
      'checks[].detail': 'human-readable result of this check',
      'checks[].hint': 'suggested fix or first-thing-to-investigate. Trust this before guessing.',
      'checks[].duration_ms': 'how long the check took to execute',
      'checks[].target': 'what the check was pointed at (URL, env var, host) - useful for grouping',
      'checks[].meta': 'optional structured evidence specific to the check type',
      'summary.passed': 'true if there are zero failures (warnings are allowed)',
      sorting: 'checks are sorted failures-first, then warnings, then skipped, then ok',
    },

    started_at,
    config_source: configSource,
    checks: sorted,
  };
}
