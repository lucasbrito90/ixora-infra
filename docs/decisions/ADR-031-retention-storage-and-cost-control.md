# ADR-031: Retention, storage, and cost control

## Status

**Accepted** — governs **MVP retention, sampling, cardinality limits, and storage predictability** on a single DigitalOcean VM ([ADR-028](ADR-028-observability-platform.md), [`specs/observability-foundation/mvp/spec.md`](../specs/observability-foundation/mvp/spec.md)).

## Date

2026-07-05

---

## Context

Observability backends grow without bound unless retention, cardinality, and ingestion rate are **explicitly capped**. A single DigitalOcean VM running Prometheus, Loki, Tempo, and Grafana has finite disk and memory. Unlimited retention or high-cardinality metrics can **fill disk silently** and take down the observability stack — or force emergency deletes with data loss.

Ixora MVP observability targets:

- **One DO VM** for staging homologation first
- **Predictable monthly cost** — no surprise storage bills
- **Sufficient retention for debugging** — not long-term archive

---

## Decision

### MVP retention (staging)

| Signal | Retention | Rationale |
| --- | --- | --- |
| **Metrics (Prometheus)** | **30 days** | SLO trends, weekly comparison, incident lookback |
| **Logs (Loki)** | **14 days** | Recent debugging; aligns with typical staging incident window |
| **Traces (Tempo)** | **7 days** | Trace volume is highest; shortest retention |

Production retention **must be defined in a future ADR amendment** before production VM deploy — do not copy staging values blindly.

### Why unlimited retention is forbidden

| Risk | Impact |
| --- | --- |
| **Disk exhaustion** | VM crash; loss of **all** signals — worse than bounded retention |
| **Unpredictable cost** | Block storage upgrades without budget approval |
| **Compliance drift** | Old logs may retain IDs longer than product policy intends |
| **Query performance** | Loki/Grafana queries degrade as index grows |
| **False confidence** | Teams assume "we can always look it up" — archive is not backup |

Long-term archive belongs in **object storage with lifecycle policies** — explicitly **out of MVP scope**.

### Compression

| Backend | MVP approach |
| --- | --- |
| **Loki** | Enable chunk compression (gzip/snappy per Loki config); structured JSON logs compress well |
| **Tempo** | Block compression enabled by default in Tempo storage backend |
| **Prometheus** | WAL + block compression; `--storage.tsdb.retention.time=30d` |

Collector may batch and compress OTLP before export — reduces egress from App Platform to observability VM.

### Storage limits (single VM guidance)

| Resource | MVP target | Action when exceeded |
| --- | --- | --- |
| **Total VM disk** | 80–160 GB block storage (size TBD in Phase 2 infra review) | Alert at 70% usage; never exceed 85% sustained |
| **Prometheus TSDB** | ≤ 40% of disk budget | Reduce retention or cardinality before expanding disk |
| **Loki chunks** | ≤ 35% of disk budget | Verify log volume; increase sampling |
| **Tempo blocks** | ≤ 25% of disk budget | Reduce trace sampling rate |

**Rule:** If projected growth exceeds limits, **reduce retention or sampling first** — do not silently expand disk without review.

### Sampling

| Signal | MVP sampling policy |
| --- | --- |
| **Traces** | **Head sampling: 10%** default for successful HTTP requests; **100%** for errors (`http.status_code >= 500`) and failed jobs |
| **Logs** | No sampling for `error` / `warning` levels; **optional 50%** for verbose `info` debug logs in high-traffic routes (post-MVP tuning) |
| **Metrics** | No sampling — aggregates are already compressed; control via cardinality limits |

Mobile client traces: **5%** default success sampling; **100%** on app crash / unhandled error spans.

Sampling configured in **Collector** (`probabilistic_sampler` processor) — adjustable without app redeploy.

### Cardinality control

High-cardinality labels destroy Prometheus performance and disk.

| Forbidden as metric labels | Use instead |
| --- | --- |
| `user_id` | Log/trace attribute; aggregate counter without label |
| `schedule_id`, `vibe_id`, `device_id` | Trace attributes; event counters with bounded `outcome` label |
| `trace_id` | Never a metric label |
| `http.url` with query params | `http.route` template: `/api/schedules/{id}` |
| Unbounded `exception.message` | `exception_class` label only |

**Collector enforcement:** `attributes` processor drops labels not on allowlist before Prometheus exporter.

**Target:** < 10 000 active series per `service.name` in MVP staging.

### Cost control checklist

- [ ] Retention flags set in Prometheus, Loki, Tempo configs
- [ ] Disk usage alert at 70%
- [ ] Cardinality review before adding new `ixora.*` metrics
- [ ] No debug `info` logs in hot paths without TTL
- [ ] Mobile telemetry batch size capped (OTLP batch processor)
- [ ] Staging-only MVP — no production traffic until Phase 10 sign-off

### Future scaling

| Stage | Change |
| --- | --- |
| **MVP** | Single VM; retentions above; manual disk monitoring |
| **Growth** | Loki/Tempo to object storage (S3-compatible); Prometheus remote write to long-term store |
| **HA** | Separate read/write paths — post-MVP; not before cost model validated |
| **Production** | Dedicated VM sizing; possibly managed Grafana Cloud — requires new ADR |

---

## Consequences

### Positive

- Storage usage remains predictable on one DO server.
- Forced discipline on metric labels and log volume.
- Clear upgrade path documented without MVP over-engineering.

### Negative

- Traces older than 7 days unavailable — incidents must be investigated promptly.
- Sampling means not every successful request has a trace — logs + metrics compensate.

### Related ADRs

- [ADR-028](ADR-028-observability-platform.md) — single VM topology
- [ADR-029](ADR-029-telemetry-data-model.md) — naming and correlation
- [ADR-030](ADR-030-observability-security-and-privacy.md) — no PII driving retention risk

---

## References

- [Prometheus storage retention](https://prometheus.io/docs/prometheus/latest/storage/)
- [Grafana Loki retention](https://grafana.com/docs/loki/latest/operations/storage/retention/)
- [Grafana Tempo retention](https://grafana.com/docs/tempo/latest/operations/manifesting/)
