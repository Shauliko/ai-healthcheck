// Generic webhook signing secret presence + optional prefix check.
import { envGet } from '../env-util.js';

export default {
  async run(check) {
    if (!check.var) return { status: 'fail', detail: 'webhook_secret check missing "var"', hint: 'Add var: STRIPE_WEBHOOK_SECRET' };
    const v = envGet(check.var, process.cwd());
    const minLength = check.min_length ?? 20;

    if (!v) {
      return {
        status: 'fail',
        detail: `${check.var} is not set`,
        hint: 'Webhooks will fail signature verification - set this in your env.',
      };
    }
    if (check.expect_prefix && !v.startsWith(check.expect_prefix)) {
      return {
        status: 'fail',
        detail: `${check.var} does not start with "${check.expect_prefix}"`,
        hint: 'Wrong kind of secret? Stripe uses whsec_, GitHub uses arbitrary, etc.',
        meta: { var: check.var, length: v.length, expected_prefix: check.expect_prefix },
      };
    }
    if (v.length < minLength) {
      return {
        status: 'fail',
        detail: `${check.var} too short (${v.length}, expected >= ${minLength})`,
        hint: 'Probably a placeholder.',
      };
    }
    return { status: 'ok', detail: `set (length=${v.length})` };
  },
};
