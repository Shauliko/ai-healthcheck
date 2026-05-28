// Registry of all built-in check types.
import http from './http.js';
import jsonShape from './json_shape.js';
import sslExpiry from './ssl_expiry.js';
import envPresent from './env_present.js';
import postgres from './postgres.js';
import stripeKey from './stripe_key.js';
import webhookSecret from './webhook_secret.js';
import npmAudit from './npm_audit.js';
import sitemap from './sitemap.js';
import robots from './robots.js';

export const CHECKS = {
  http,
  json_shape: jsonShape,
  ssl_expiry: sslExpiry,
  env_present: envPresent,
  postgres,
  stripe_key: stripeKey,
  webhook_secret: webhookSecret,
  npm_audit: npmAudit,
  sitemap,
  robots,
};
