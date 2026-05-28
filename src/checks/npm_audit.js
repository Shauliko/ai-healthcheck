// npm audit summary. Runs `npm audit --json` in cwd, parses metadata.vulnerabilities.
import { spawn } from 'node:child_process';

const SEVERITY_ORDER = ['info', 'low', 'moderate', 'high', 'critical'];

function runNpmAudit(cwd, signal) {
  return new Promise((resolve) => {
    const child = spawn('npm', ['audit', '--json'], { cwd, shell: true });
    let stdout = ''; let stderr = '';
    child.stdout.on('data', (d) => stdout += d);
    child.stderr.on('data', (d) => stderr += d);
    if (signal) signal.addEventListener('abort', () => { try { child.kill(); } catch {} });
    child.on('close', (code) => resolve({ code, stdout, stderr }));
    child.on('error', (e) => resolve({ code: -1, stdout, stderr: e.message }));
  });
}

export default {
  async run(check, { signal }) {
    const threshold = (check.level || 'high').toLowerCase();
    const thresholdIdx = SEVERITY_ORDER.indexOf(threshold);
    if (thresholdIdx < 0) {
      return { status: 'fail', detail: `Unknown level "${threshold}"`, hint: `Use one of: ${SEVERITY_ORDER.join(', ')}` };
    }

    const { code, stdout, stderr } = await runNpmAudit(process.cwd(), signal);
    let parsed;
    try {
      parsed = JSON.parse(stdout);
    } catch {
      return {
        status: 'warn',
        detail: `npm audit failed to produce JSON (exit ${code})`,
        hint: 'Is this an npm project? Run "npm audit" manually to see the error.',
        meta: { stderr: stderr.slice(0, 400) },
      };
    }

    const vulns = parsed.metadata?.vulnerabilities || {};
    const overThreshold = SEVERITY_ORDER
      .slice(thresholdIdx)
      .reduce((sum, k) => sum + (vulns[k] || 0), 0);

    const total = SEVERITY_ORDER.reduce((sum, k) => sum + (vulns[k] || 0), 0);

    if (overThreshold > 0) {
      const breakdown = SEVERITY_ORDER.slice(thresholdIdx)
        .map((k) => `${vulns[k] || 0} ${k}`)
        .join(', ');
      return {
        status: 'fail',
        detail: `${overThreshold} vulnerabilit${overThreshold === 1 ? 'y' : 'ies'} at "${threshold}" or above (${breakdown})`,
        hint: 'Run `npm audit fix`, or `npm audit fix --force` for breaking upgrades.',
        meta: { vulnerabilities: vulns, threshold },
      };
    }
    return { status: 'ok', detail: total === 0 ? 'no known vulnerabilities' : `${total} below "${threshold}" threshold`, meta: { vulnerabilities: vulns } };
  },
};
