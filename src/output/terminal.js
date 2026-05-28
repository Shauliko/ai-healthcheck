// Color-coded terminal renderer. Groups by category, failures sorted to top within each group.
import pc from 'picocolors';

const STATUS_RANK = { fail: 0, warn: 1, skip: 2, ok: 3 };

function badge(status, useColor) {
  const txt = status.toUpperCase().padEnd(4);
  if (!useColor) return `[${txt}]`;
  if (status === 'ok')   return pc.bgGreen(pc.black(` ${txt} `));
  if (status === 'warn') return pc.bgYellow(pc.black(` ${txt} `));
  if (status === 'fail') return pc.bgRed(pc.white(` ${txt} `));
  if (status === 'skip') return pc.bgBlue(pc.white(` ${txt} `));
  return `[${txt}]`;
}

function dim(s, useColor) { return useColor ? pc.dim(s) : s; }
function bold(s, useColor) { return useColor ? pc.bold(s) : s; }

export function renderTerminal({ results, summary }, { quiet = false, useColor = true } = {}) {
  const lines = [];
  lines.push('');
  lines.push(bold('ai-healthcheck', useColor) + dim(` — ${summary.total} checks`, useColor));
  lines.push('');

  if (!quiet) {
    const byCategory = new Map();
    for (const r of results) {
      const arr = byCategory.get(r.category) || [];
      arr.push(r);
      byCategory.set(r.category, arr);
    }

    // Order categories so any with failures float to top
    const catOrder = [...byCategory.keys()].sort((a, b) => {
      const aHasFail = byCategory.get(a).some((r) => r.status === 'fail') ? 0 : 1;
      const bHasFail = byCategory.get(b).some((r) => r.status === 'fail') ? 0 : 1;
      if (aHasFail !== bHasFail) return aHasFail - bHasFail;
      return a.localeCompare(b);
    });

    for (const cat of catOrder) {
      lines.push(bold(cat, useColor));
      const items = [...byCategory.get(cat)].sort((a, b) => STATUS_RANK[a.status] - STATUS_RANK[b.status]);
      for (const r of items) {
        const dur = dim(`(${r.duration_ms}ms)`, useColor);
        lines.push(`  ${badge(r.status, useColor)} ${r.name} ${dur}`);
        if (r.detail && r.status !== 'ok') {
          lines.push(`         ${dim('→', useColor)} ${r.detail}`);
        }
        if (r.hint && (r.status === 'fail' || r.status === 'warn')) {
          lines.push(`         ${dim('💡', useColor)} ${dim(r.hint, useColor)}`);
        }
      }
      lines.push('');
    }
  }

  // Summary
  const parts = [];
  parts.push(useColor ? pc.green(`${summary.ok} ok`)   : `${summary.ok} ok`);
  if (summary.warn) parts.push(useColor ? pc.yellow(`${summary.warn} warn`) : `${summary.warn} warn`);
  if (summary.fail) parts.push(useColor ? pc.red(`${summary.fail} fail`)    : `${summary.fail} fail`);
  if (summary.skip) parts.push(useColor ? pc.blue(`${summary.skip} skip`)   : `${summary.skip} skip`);

  lines.push(bold('Summary: ', useColor) + parts.join('  '));
  if (summary.fail > 0) {
    lines.push(dim('Tip: re-run with --ai-json to get a file you can paste into Claude/ChatGPT and ask "what\'s broken?"', useColor));
  }
  lines.push('');

  return lines.join('\n');
}
