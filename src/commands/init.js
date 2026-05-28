// `ai-healthcheck init` — scaffold a healthcheck.config.yaml in cwd.
import { writeFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { STARTER_CONFIG, DEFAULT_CONFIG_FILENAME } from '../config.js';

export async function init({ cwd }) {
  const path = join(cwd, DEFAULT_CONFIG_FILENAME);
  if (existsSync(path)) {
    console.error(`ai-healthcheck: ${DEFAULT_CONFIG_FILENAME} already exists at ${path}`);
    console.error('  Delete it first if you want to regenerate.');
    process.exit(1);
  }
  writeFileSync(path, STARTER_CONFIG);
  console.log(`✓ Wrote ${DEFAULT_CONFIG_FILENAME}`);
  console.log('');
  console.log('Next steps:');
  console.log(`  1. Edit ${DEFAULT_CONFIG_FILENAME} — replace example.com with your URLs.`);
  console.log('  2. Run: npx ai-healthcheck run --ai-json');
  console.log('  3. Drag the .ai.json into Claude/ChatGPT and ask "what\'s broken?"');
}
