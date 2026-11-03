# Claude Code config

`~/.claude` is a symlink to this directory. `settings.json` is gitignored, so
each machine keeps its own copy.

## Telemetry

Claude Code pushes OTLP metrics straight to Prometheus in the home cluster.
They show up on the "Claude Code" Grafana dashboard. To turn it on for a
machine, add this to that machine's `settings.json`:

```json
"env": {
  "CLAUDE_CODE_ENABLE_TELEMETRY": "1",
  "OTEL_METRICS_EXPORTER": "otlp",
  "OTEL_EXPORTER_OTLP_METRICS_PROTOCOL": "http/protobuf",
  "OTEL_EXPORTER_OTLP_METRICS_ENDPOINT": "https://<prometheus-host>/api/v1/otlp/v1/metrics",
  "OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE": "cumulative",
  "OTEL_RESOURCE_ATTRIBUTES": "host.name=<hostname>"
}
```

- The temporality has to be `cumulative`. Prometheus rejects delta with a 500,
  and the exporter doesn't report the failure.
- `host.name` becomes the `host_name` label that the dashboard's Host variable
  filters on. Sessions without it still count, but show up as `unknown` in
  "Estimated cost by host".
- Only sessions started after the change push metrics.

To check that it works, run a session and confirm that
`claude_code_token_usage_tokens_total{host_name="<hostname>"}` exists in
Prometheus. Set `OTEL_METRIC_EXPORT_INTERVAL=5000` to skip the default
one-minute wait.
