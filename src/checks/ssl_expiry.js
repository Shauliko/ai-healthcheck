// SSL cert expiry check — TLS handshake to host:port, read peer cert valid_to.
import tls from 'node:tls';

function daysUntil(dateStr) {
  const d = new Date(dateStr);
  if (isNaN(d.getTime())) return null;
  return Math.floor((d.getTime() - Date.now()) / (24 * 60 * 60 * 1000));
}

export default {
  async run(check, { signal }) {
    const host = check.host || (check.url ? new URL(check.url).hostname : null);
    if (!host) return { status: 'fail', detail: 'ssl_expiry check missing "host"', hint: 'Add host: example.com' };
    const port = check.port || 443;
    const warnDays = check.warn_days ?? 30;
    const failDays = check.fail_days ?? 7;

    const cert = await new Promise((resolve, reject) => {
      const socket = tls.connect({ host, port, servername: host, rejectUnauthorized: false }, () => {
        const peer = socket.getPeerCertificate();
        socket.end();
        resolve(peer);
      });
      socket.on('error', reject);
      if (signal) signal.addEventListener('abort', () => { try { socket.destroy(); } catch {} reject(new Error('aborted')); });
    });

    if (!cert || !cert.valid_to) {
      return { status: 'fail', detail: 'Could not read peer certificate', hint: 'Host may not serve TLS.' };
    }

    const days = daysUntil(cert.valid_to);
    if (days === null) return { status: 'fail', detail: `Cert expiry unreadable: ${cert.valid_to}` };

    if (days < failDays) {
      return {
        status: 'fail',
        detail: `Cert expires in ${days} day(s) (valid_to: ${cert.valid_to})`,
        hint: 'Renew the cert NOW. If using Let\'s Encrypt, check the renewal cron.',
        meta: { days, valid_to: cert.valid_to, issuer: cert.issuer?.O || cert.issuer?.CN || null },
      };
    }
    if (days < warnDays) {
      return {
        status: 'warn',
        detail: `Cert expires in ${days} days (valid_to: ${cert.valid_to})`,
        hint: 'Renewal is approaching — confirm auto-renewal is healthy.',
        meta: { days, valid_to: cert.valid_to },
      };
    }
    return { status: 'ok', detail: `${days} days until expiry`, meta: { days, valid_to: cert.valid_to } };
  },
};
