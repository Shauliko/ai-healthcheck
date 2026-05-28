#!/usr/bin/env node
import { run } from '../src/commands/run.js';
import { init } from '../src/commands/init.js';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const __dirname = dirname(fileURLToPath(import.meta.url));
const pkg = JSON.parse(readFileSync(join(__dirname, '..', 'package.json'), 'utf8'));

const HELP = `ai-healthcheck v${pkg.version}
Monitoring designed for your AI to read.

USAGE
  npx ai-healthcheck <command> [options]

COMMANDS
  init                  Scaffold a healthcheck.config.yaml in the current dir
  run                   Run all checks (uses ./healthcheck.config.yaml; auto-detects if missing)
  help                  Show this help

RUN OPTIONS
  --config <path>       Path to config file (default: ./healthcheck.config.yaml)
  --json [path]         Write plain JSON results (default path: ./ai-healthcheck.out.json)
  --ai-json [path]      Write AI-optimized JSON with questions_to_investigate
                        (default path: ./ai-healthcheck.ai.json)
  --with-network        Allow checks that make outbound API calls with user secrets
                        (Stripe balance fetch, etc). Off by default.
  --timeout <ms>        Per-check timeout in milliseconds (default: 8000)
  --quiet               Suppress per-check terminal output; print summary only
  --no-color            Disable ANSI colors

EXIT CODES
  0   all checks ok (or only warnings)
  1   one or more checks failed
  2   bad config or runtime error

EXAMPLES
  npx ai-healthcheck init
  npx ai-healthcheck run
  npx ai-healthcheck run --ai-json
  npx ai-healthcheck run --config ./my-config.yaml --ai-json health.json

Then drag the JSON into Claude/ChatGPT and ask "what's broken?".
`;

function parseArgs(argv) {
  const args = { _: [], flags: {} };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a.startsWith('--')) {
      const key = a.slice(2);
      if (['quiet', 'no-color', 'with-network', 'help', 'version'].includes(key)) {
        args.flags[key] = true;
      } else {
        const next = argv[i + 1];
        if (next === undefined || next.startsWith('--')) {
          args.flags[key] = true;
        } else {
          args.flags[key] = next;
          i++;
        }
      }
    } else {
      args._.push(a);
    }
  }
  return args;
}

async function main() {
  const args = parseArgs(process.argv.slice(2));

  if (args.flags.version) {
    console.log(pkg.version);
    process.exit(0);
  }

  const cmd = args._[0] || 'help';

  if (cmd === 'help' || args.flags.help) {
    console.log(HELP);
    process.exit(0);
  }

  if (cmd === 'init') {
    await init({ cwd: process.cwd() });
    process.exit(0);
  }

  if (cmd === 'run') {
    const code = await run({
      cwd: process.cwd(),
      configPath: typeof args.flags.config === 'string' ? args.flags.config : undefined,
      jsonOut: args.flags.json,
      aiJsonOut: args.flags['ai-json'],
      withNetwork: !!args.flags['with-network'],
      timeoutMs: args.flags.timeout ? parseInt(args.flags.timeout, 10) : 8000,
      quiet: !!args.flags.quiet,
      noColor: !!args.flags['no-color'],
    });
    process.exit(code);
  }

  console.error(`Unknown command: ${cmd}`);
  console.error('Run "ai-healthcheck help" for usage.');
  process.exit(2);
}

main().catch((err) => {
  console.error('ai-healthcheck crashed:', err && err.stack ? err.stack : err);
  process.exit(2);
});
