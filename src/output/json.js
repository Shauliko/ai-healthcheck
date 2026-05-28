// Plain machine-readable JSON output.
export function toPlainJson({ results, summary, started_at }, { config, configSource }) {
  return {
    schema: 'ai-healthcheck.v1.plain',
    tool: 'ai-healthcheck',
    started_at,
    config_source: configSource,
    summary,
    checks: results,
  };
}
