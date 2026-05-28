// `ai-healthcheck run` command.
import { writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { loadConfig } from '../config.js';
import { runChecks } from '../runner.js';
import { renderTerminal } from '../output/terminal.js';
import { toAiJson } from '../output/ai-json.js';
import { toPlainJson } from '../output/json.js';

const __dirname = dirname(fileURLToPath(import.meta.url));
const pkg = JSON.parse(readFileSync(join(__dirname, '..', '..', 'package.json'), 'utf8'));

export async function run(opts) {
  const { cwd, configPath, jsonOut, aiJsonOut, withNetwork, timeoutMs, quiet, noColor } = opts;

  let config, source, autoDetected;
  try {
    ({ config, source, autoDetected } = loadConfig({ cwd, configPath }));
  } catch (e) {
    console.error(`ai-healthcheck: ${e.message}`);
    return 2;
  }

  if (autoDetected) {
    console.error(`ai-healthcheck: no config file found — auto-detected ${config.checks.length} check(s) from project files.`);
    console.error('  Run `npx ai-healthcheck init` to scaffold a real config.');
  }

  if (!config.checks.length) {
    console.error('ai-healthcheck: no checks to run. Add some to healthcheck.config.yaml.');
    return 2;
  }

  const result = await runChecks(config, { timeoutMs, withNetwork });

  const useColor = !noColor && process.stdout.isTTY !== false;
  process.stdout.write(renderTerminal(result, { quiet, useColor }));

  if (jsonOut) {
    const outPath = resolve(cwd, typeof jsonOut === 'string' ? jsonOut : 'ai-healthcheck.out.json');
    const payload = toPlainJson(result, { config, configSource: source });
    writeFileSync(outPath, JSON.stringify(payload, null, 2));
    console.log(`Wrote JSON to ${outPath}`);
  }

  if (aiJsonOut) {
    const outPath = resolve(cwd, typeof aiJsonOut === 'string' ? aiJsonOut : 'ai-healthcheck.ai.json');
    const payload = toAiJson(result, { configSource: source, toolVersion: pkg.version });
    writeFileSync(outPath, JSON.stringify(payload, null, 2));
    console.log(`Wrote AI-optimized JSON to ${outPath}`);
    console.log(`  → Drag this into Claude/ChatGPT and ask: "what's broken?"`);
  }

  return result.summary.fail > 0 ? 1 : 0;
}
