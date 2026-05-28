// Env var presence + min length. NEVER logs the value.
import { envGet } from '../env-util.js';

export default {
  async run(check) {
    if (!check.var) return { status: 'fail', detail: 'env_present check missing "var"', hint: 'Add var: MY_ENV_VAR' };
    const value = envGet(check.var, process.cwd());
    const minLength = check.min_length ?? 1;

    if (value === undefined || value === '') {
      return {
        status: 'fail',
        detail: `${check.var} is not set`,
        hint: `Add ${check.var}=... to your .env or hosting env vars.`,
        meta: { var: check.var, set: false },
      };
    }
    if (value.length < minLength) {
      return {
        status: 'fail',
        detail: `${check.var} too short (${value.length} chars, expected >= ${minLength})`,
        hint: 'Likely a placeholder value (e.g., "your-key-here").',
        meta: { var: check.var, length: value.length, min_length: minLength },
      };
    }
    return { status: 'ok', detail: `set (length=${value.length})`, meta: { var: check.var, length: value.length } };
  },
};
