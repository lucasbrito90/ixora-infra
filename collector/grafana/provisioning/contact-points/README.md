# Contact points — moved

Grafana's file-based alerting provisioning only scans the single
`provisioning/alerting/` directory (resource type is read from each YAML
file's top-level key — `contactPoints`, `policies`, `muteTimes`,
`templates`, `groups` — not from which subdirectory it lives in). This
directory is kept only as a documentation anchor; the real file is:

`../alerting/contact-points.yaml`

Verified empirically in Phase 9 (`docs/specs/observability-foundation/mvp/alerting-strategy.md` §6, KL-S-6):
a file left in this directory is silently never read, and a provisioning
error in a file placed in the correct `alerting/` directory can crash
the whole Grafana container — see that document before changing SMTP/env
var defaults.
