// Postgres connectivity check. Requires `pg` to be installed in the host project.
import { envGet } from '../env-util.js';

export default {
  async run(check, { signal }) {
    const connStr = check.connection_string || envGet(check.var || 'DATABASE_URL', process.cwd());
    if (!connStr) {
      return {
        status: 'fail',
        detail: `No connection string (env var: ${check.var || 'DATABASE_URL'} is not set)`,
        hint: 'Set DATABASE_URL or pass connection_string in the check config.',
      };
    }

    let pg;
    try {
      pg = await import('pg');
    } catch (e) {
      return {
        status: 'fail',
        detail: 'The "pg" package is not installed',
        hint: 'Run: npm install pg   (pg is an optional peer dep of ai-healthcheck)',
      };
    }

    const Client = pg.Client || pg.default?.Client;
    const client = new Client({ connectionString: connStr });
    let aborted = false;
    if (signal) signal.addEventListener('abort', () => { aborted = true; try { client.end(); } catch {} });

    try {
      await client.connect();
      const r = await client.query('SELECT 1 as ok');
      await client.end();
      if (aborted) return { status: 'fail', detail: 'aborted' };
      const ok = r.rows?.[0]?.ok === 1;
      return ok
        ? { status: 'ok', detail: 'SELECT 1 ok' }
        : { status: 'fail', detail: 'SELECT 1 returned unexpected result', meta: { rows: r.rows } };
    } catch (e) {
      try { await client.end(); } catch {}
      const msg = e?.message || String(e);
      return {
        status: 'fail',
        detail: `Postgres error: ${msg}`,
        hint: msg.includes('password') ? 'Auth failed - check DATABASE_URL credentials.'
              : msg.includes('ENOTFOUND') || msg.includes('ECONNREFUSED') ? 'Host unreachable - check network / pooler URL.'
              : 'DB returned an error - check server logs.',
      };
    }
  },
};
