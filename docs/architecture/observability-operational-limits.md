# Observability Operational Limits

**Status:** Active architecture limits  
**ADRs:** [ADR-031](../decisions/ADR-031-retention-storage-and-cost-control.md) · [ADR-028](../decisions/ADR-028-observability-platform.md)  
**Complements:** [`infrastructure-review.md`](../specs/observability-foundation/mvp/infrastructure-review.md) · [`security-review.md`](../specs/observability-foundation/mvp/security-review.md) · [`telemetry-availability-policy.md`](telemetry-availability-policy.md)  
**Applies to:** Observability VM stack — architectural bounds only

> **Rule of thumb:** These are **policy limits**, not tuned values. Exact numbers are set in Phase 3–9 implementation configs. When limits are hit, **reduce sampling/retention before scaling hardware** ([ADR-031](../decisions/ADR-031-retention-storage-and-cost-control.md)).

---

## 1. Collector

| Limit area | Architectural intent | Phase 3 sets |
| --- | --- | --- |
| **Maximum queue size** | Bound memory under ingest spike; drop when full — never OOM VM | `queued_retry` / memory limiter queue cap |
| **Maximum batch size** | Balance latency vs efficiency | `batch` processor `send_batch_size` |
| **Retry policy** | Retry backend export briefly; drop after cap | Exponential backoff max |
| **Timeout policy** | Export to Prometheus/Loki/Tempo ≤ few seconds | Per-exporter timeout |
| **Backpressure** | When backends slow, drop incoming telemetry before blocking apps | `memory_limiter` refuse / drop |
| **Memory limiter** | Hard cap Collector RSS (% of VM RAM) | `limit_mib` |
| **Batch processor** | Group spans/logs before export | Interval + size |

**Principle:** Collector protects the VM and backends — apps already non-blocking ([telemetry-availability-policy.md](telemetry-availability-policy.md)).

---

## 2. Prometheus

| Limit area | Architectural intent | Reference |
| --- | --- | --- |
| **Series growth** | Monotonic with bad labels — must be bounded | [ADR-031](../decisions/ADR-031-retention-storage-and-cost-control.md) |
| **Target active series** | < 10 000 per `service.name` staging | Label allowlist at Collector |
| **Scrape intervals** | Default 15–60 s for self-scrape; avoid sub-5 s | Disk + CPU |
| **Retention** | 30 days max staging | `--storage.tsdb.retention.time=30d` |
| **Query load** | Grafana dashboards only — no ad-hoc heavy queries in MVP | Query timeout in Grafana |

**Forbidden:** `user_id`, `trace_id`, raw URLs as labels ([telemetry-naming-convention.md](telemetry-naming-convention.md) §8).

---

## 3. Loki

| Limit area | Architectural intent |
| --- | --- |
| **Chunk sizing** | Default Loki chunk targets — tune if ingest rate high |
| **Index growth** | Structured labels only — low cardinality stream labels |
| **Retention** | 14 days staging |
| **Ingest rate** | If chunk disk > budget, reduce log verbosity at app — not unlimited retention |
| **Query scope** | Time-bounded Explore queries; avoid unbounded `{service.name=~".+"}` without time filter |

**Stream labels (allowlist intent):** `service.name`, `deployment.environment`, `level` — not `user_id`.

---

## 4. Tempo

| Limit area | Architectural intent | ADR-031 |
| --- | --- | --- |
| **Trace volume** | Highest storage consumer | Head sampling 10% success HTTP |
| **Error traces** | 100% retention for 5xx and failed jobs | Required |
| **Mobile traces** | 5% success sampling | Required |
| **Retention** | 7 days | Shortest window |
| **Span count per trace** | Keep async depth reasonable ([asynchronous-orchestration.md](asynchronous-orchestration.md)) | Avoid 100+ span traces |

---

## 5. Grafana

| Limit area | Architectural intent |
| --- | --- |
| **Dashboard complexity** | ≤ 20 panels per MVP dashboard; prefer recording rules post-MVP |
| **Query timeout** | ≤ 60 s; fail fast |
| **Refresh interval** | ≥ 30 s on operational dashboards — not 5 s on heavy queries |
| **Concurrent queries** | Limit per user to protect Loki/Tempo |
| **Variables** | `deployment.environment` required — prevent cross-env leaks |

Dashboard naming: [telemetry-naming-convention.md](telemetry-naming-convention.md) §11.

---

## 6. General limits

| Limit | Architectural bound |
| --- | --- |
| **Maximum metric labels per series** | Minimal allowlist — typically ≤ 6 |
| **Maximum cardinality** | < 10k series / service staging |
| **Maximum OTLP payload size** | Reject oversized batches at Collector (DoS protection) |
| **Maximum log line size** | Truncate > N KB at Collector (Phase 3) |
| **Maximum span attribute count** | Drop unknown high-count attributes |

### Alert thresholds (architectural — alerts post-MVP)

| Resource | Warning | Critical | Action |
| --- | --- | --- | --- |
| **Disk** | 70% | 85% | Enforce retention; expand disk only after tuning |
| **Memory** | 75% VM RAM | 90% | Reduce ingest; restart backends |
| **CPU** | 70% sustained 15 min | 85% | Review scrape interval; cardinality |

Aligns with [infrastructure-review.md](../specs/observability-foundation/mvp/infrastructure-review.md) §6 disk budget.

---

## 7. Implementation note

| Phase | Delivers concrete values |
| --- | --- |
| **Phase 3** | Collector batch, memory limiter, queue, timeouts |
| **Phase 4–6** | Prometheus retention, Loki chunk, Tempo sampling wiring |
| **Phase 9** | Grafana query timeout, refresh |
| **Phase 10** | Disk/memory alert runbook numbers |

**This document does not contain final config values** — only limits engineering must respect.

---

## Related documents

| Document | Relationship |
| --- | --- |
| [collector-hardening-checklist.md](../operations/collector-hardening-checklist.md) | Phase 3 apply limits |
| [observability-playbook.md](../operations/observability-playbook.md) | Incidents when limits exceeded |
| [telemetry-decision-guide.md](telemetry-decision-guide.md) | Avoid cardinality at source |
