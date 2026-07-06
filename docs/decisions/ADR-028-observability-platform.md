# ADR-028: Observability platform

## Status

**Accepted** — governs **platform-wide observability architecture** for Ixora ([`specs/observability-foundation/mvp/spec.md`](../specs/observability-foundation/mvp/spec.md)).

## Date

2026-07-05

---

## Context

Ixora has shipped Scheduler, Smart Home, Push Notifications, and Scheduler + Smart Home Automations. Operational troubleshooting today relies on **DigitalOcean App Platform runtime logs**, **Laravel `Log::` calls**, and **manual `adb logcat`** on mobile — without unified metrics, traces, or searchable log correlation.

The next platform capability is **Observability Foundation**: a single telemetry pipeline that supports backend API, queue workers, scheduler, and mobile client — without becoming a data leak or an unbounded cost sink.

Constraints:

1. **MVP targets a single DigitalOcean VM** — not Kubernetes, not multi-region.
2. **Applications must not depend on observability for correctness** — same principle as push best-effort ([ADR-020](ADR-020-push-delivery-and-fallback-strategy.md)).
3. **Collector as sole ingestion point** — applications must not talk directly to Prometheus, Loki, or Tempo.
4. **OpenTelemetry (OTel) as the standard** — vendor-neutral SDK and Collector; Grafana as visualization layer.

---

## Decision

### Target MVP topology

```
DigitalOcean VM (observability stack)
├── OpenTelemetry Collector   ← sole ingestion endpoint
├── Prometheus                ← metrics backend
├── Loki                      ← logs backend
├── Tempo                     ← traces backend
└── Grafana                   ← reads all three; no direct app access

back_vibes (API + workers)
    ↓ OTLP (HTTP/gRPC)
OpenTelemetry Collector
    ├── metrics  → Prometheus (remote write or scrape exporter)
    ├── logs     → Loki
    └── traces   → Tempo

front_vibes (Android)
    ↓ OTLP (HTTP)
OpenTelemetry Collector
    ├── logs     → Loki
    └── traces   → Tempo
    (metrics optional — mobile cardinality controlled)
```

### Mandatory rules

| Rule | Detail |
| --- | --- |
| **Single Collector** | One OpenTelemetry Collector deployment per environment (staging MVP: one VM). All app telemetry exports to Collector only. |
| **Collector is mandatory** | Applications **must not** bypass Collector to write Prometheus, Loki, or Tempo directly. |
| **No direct backend access from apps** | `back_vibes` and `front_vibes` never hold Prometheus/Loki/Tempo credentials. |
| **Grafana reads backends only** | Grafana queries Prometheus, Loki, Tempo — not application databases or Firebase. |
| **Failure isolation** | If Collector is unreachable, applications **continue** business logic. Telemetry export is best-effort ([ADR-029](ADR-029-telemetry-data-model.md) failure policy). |
| **Staging first** | MVP deploys on staging/homologation before any production observability VM. |

### Why applications must never talk directly to Prometheus, Loki, or Tempo

| Reason | Explanation |
| --- | --- |
| **Security boundary** | Backends hold long-lived credentials and broad query access. Apps should hold only Collector endpoint + optional API key scoped to ingest. |
| **Schema enforcement** | Collector processors enforce attribute naming, redaction, sampling, and cardinality limits **before** data hits storage ([ADR-030](ADR-030-observability-security-and-privacy.md), [ADR-031](ADR-031-retention-storage-and-cost-control.md)). |
| **Single configuration surface** | Retention, routing, and fan-out change in Collector config — not in every app repo. |
| **Vendor swap** | Replacing Loki with another log backend affects Collector exporters only — not Laravel or mobile SDK init. |
| **No accidental coupling** | Direct Prometheus push from Laravel invites high-cardinality labels (`user_id`, `request_body`) that explode storage cost. |
| **Correlation consistency** | Collector injects or validates `trace_id` / `service.name` / `deployment.environment` across signals. |

Direct ingestion anti-pattern (forbidden):

```
back_vibes → Loki push API          ❌
back_vibes → Prometheus remote_write ❌ (without Collector processors)
front_vibes → Tempo OTLP direct     ❌ (bypasses redaction processor)
```

Allowed:

```
back_vibes  → OTLP → Collector → { Prometheus, Loki, Tempo }  ✅
front_vibes → OTLP → Collector → { Loki, Tempo }                ✅
Grafana     → query → { Prometheus, Loki, Tempo }               ✅
```

### Future scalability

| Stage | Evolution |
| --- | --- |
| **MVP** | Single DO VM; Collector + Prometheus + Loki + Tempo + Grafana co-located; staging only |
| **Growth** | Split backends onto separate VMs or managed services; Collector remains ingestion hub |
| **Multi-env** | One Collector per environment (`staging`, `production`) — never mix signals |
| **HA (post-MVP)** | Collector replica set behind load balancer; Prometheus/Loki/Tempo HA — **explicitly out of MVP** ([spec](../specs/observability-foundation/mvp/spec.md) non-goals) |
| **Multi-region** | Regional Collectors with centralized long-term store — deferred |

The Collector pattern scales **horizontally** by adding Collector instances; applications only need the endpoint URL to change via env var.

---

## Consequences

### Positive

- Unified troubleshooting across API, scheduler, Smart Home jobs, push pipeline, and mobile.
- Security and retention policies enforced once at Collector boundary.
- OTel SDK investment portable across backend and frontend.

### Negative

- Additional VM cost and operational ownership ([ADR-031](ADR-031-retention-storage-and-cost-control.md)).
- Collector downtime means telemetry gap — acceptable per failure policy; business logic unaffected.
- Mobile OTLP over cellular requires payload discipline and sampling.

### Related ADRs

- [ADR-024](ADR-024-automation-notifications-and-observability.md) — product observability today is logs + execution rows; this ADR adds platform telemetry.
- [ADR-026](ADR-026-automation-execution-security.md) — no secrets in logs; extends to telemetry via [ADR-030](ADR-030-observability-security-and-privacy.md).
- [ADR-027](ADR-027-asynchronous-orchestration-pattern.md) — async layers (scheduler, jobs) are primary trace spans.
- [ADR-029](ADR-029-telemetry-data-model.md) — data model and naming.
- [ADR-030](ADR-030-observability-security-and-privacy.md) — redaction and PII.
- [ADR-031](ADR-031-retention-storage-and-cost-control.md) — retention and cost.

---

## References

- [OpenTelemetry Collector](https://opentelemetry.io/docs/collector/)
- [Observability Foundation spec](../specs/observability-foundation/mvp/spec.md)
- [Staging DigitalOcean topology](../architecture/backend/staging-digitalocean.md)
