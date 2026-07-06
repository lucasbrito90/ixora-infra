# Telemetry Availability Policy

**Status:** Active architecture policy  
**ADRs:** [ADR-028](../decisions/ADR-028-observability-platform.md) · [ADR-029](../decisions/ADR-029-telemetry-data-model.md)  
**Complements:** [`telemetry-decision-guide.md`](telemetry-decision-guide.md) · [`security-review.md`](../specs/observability-foundation/mvp/security-review.md) · [`observability-playbook.md`](../operations/observability-playbook.md)  
**Applies to:** `back_vibes`, `front_vibes`, OpenTelemetry SDK integration (Phases 7–8)

> **Rule of thumb:** If telemetry export fails, the user must never notice. Schedules still run, pushes still attempt, Smart Home jobs still execute.

---

## 1. Core principle

**Telemetry must NEVER block business logic.**

Observability is **best-effort**. Product correctness — HTTP responses, queue jobs, scheduler ticks, Smart Home actions, push delivery, mobile UX — takes absolute priority over exporting spans, logs, or metrics.

This policy extends:

- Push best-effort ([ADR-020](../decisions/ADR-020-push-delivery-and-fallback-strategy.md))
- Automation failure isolation ([ADR-023](../decisions/ADR-023-automation-execution-order-and-failure-policy.md))
- Collector-only platform ([ADR-028](../decisions/ADR-028-observability-platform.md))

---

## 2. Non-blocking requirements

Applications **must never wait** for telemetry export on the critical path.

| Path | Forbidden | Required |
| --- | --- | --- |
| **HTTP request** | Await OTLP export before returning response | Export async / background batch |
| **Queue job** | Block `handle()` on span flush | Flush in `finally` with timeout cap |
| **Scheduler tick** | Delay dispatch loop on Collector ACK | Drop export if slow |
| **Smart Home job** | Delay HA call on telemetry | Provider call first priority |
| **Push job** | Delay FCM on trace export | Same as Smart Home |
| **Mobile UI** | Block navigation on OTLP | Export on idle / background timer |

### Latency impact — zero tolerance

Collector failures **must never increase**:

| Surface | Requirement |
| --- | --- |
| HTTP latency | No additional p95 from OTel |
| Queue latency | Job duration excludes export wait |
| Scheduler latency | `dispatch-loop` tick budget unchanged |
| Smart Home latency | HA timeout independent of Tempo |
| Push latency | FCM send independent of Loki |
| Mobile UX latency | No main-thread export |

---

## 3. Best-effort delivery

| Rule | Detail |
| --- | --- |
| **Fire and forget** | SDK export runs outside request/job critical section |
| **Timeout cap** | Export attempt bounded (e.g. ≤ 2 s) — then abandon |
| **No retry storm** | Exponential backoff; max retries capped |
| **Drop on pressure** | Prefer dropping telemetry over slowing app |
| **No user-visible errors** | Never surface "telemetry failed" to end users |
| **Local counter optional** | `ixora.telemetry.export.failed.total` when instrumented |

---

## 4. Retry and backoff

| Parameter | Architectural intent | Implementation (Phase 7–8) |
| --- | --- | --- |
| **Initial retry delay** | Short (ms–s) | SDK default tuned down if needed |
| **Max backoff** | ≤ 60 s | Prevent unbounded queue growth |
| **Max retries** | Finite (e.g. 3–5 per batch) | Then drop batch |
| **Jitter** | Required | Avoid synchronized retry spikes |
| **Queue saturation** | Drop oldest telemetry batches | Never block Laravel queue |

**Laravel queue saturation:** OTel export must not consume worker threads indefinitely. If worker is busy, skip export for that job — log locally only if already instrumented.

---

## 5. Failure isolation

```
Product path          Telemetry path
     │                      │
     ▼                      ▼
 Business logic        OTel SDK export
     │                      │
     ▼                      ▼ (failure OK)
 User outcome          Silent drop + metric
```

| Isolation | Detail |
| --- | --- |
| **Process** | Observability VM crash ≠ App Platform crash |
| **Network** | Collector unreachable ≠ API 503 |
| **Disk** | Observability disk full ≠ Postgres write failure |
| **Credentials** | Invalid OTEL key ≠ invalid Firebase token |

---

## 6. Graceful degradation

When telemetry is impaired, applications **continue** with degraded observability only:

| Condition | Product behaviour | Telemetry behaviour |
| --- | --- | --- |
| Collector down | Normal | Gap in Tempo/Loki/Prometheus |
| Collector slow | Normal | Drop batches exceeding timeout |
| Backend unavailable | Normal | Collector drops per memory limiter |
| Disk full (obs VM) | Normal | Collector stops accepting — apps unaffected |
| High export latency | Normal | Reduce batch frequency; drop |
| Network interruption | Normal | Buffer briefly; then drop |
| VM crash | Normal | Use App Platform logs ([observability-playbook.md](../operations/observability-playbook.md)) |
| Mobile offline | Normal | Queue locally ≤ N batches; drop when full |
| Laravel queue saturated | Jobs process | Skip export for lower-priority spans |

---

## 7. Expected behaviour by scenario

### Collector down

- API returns 200/4xx/5xx based on business logic only
- Scheduler creates `schedule_executions` rows
- Smart Home jobs call Home Assistant
- Push jobs call FCM
- SDK logs export error internally; optional metric increment

### Collector slow

- Export times out; batch discarded
- No thread pool exhaustion in PHP worker
- Mobile skips pending export on next screen if backlog > threshold

### Backend unavailable (Prometheus/Loki/Tempo)

- Collector internal retry then drop
- Health endpoint may report degraded
- Apps unaware

### Disk full (observability VM)

- Backends may crash; Collector may reject ingest
- **Product staging on App Platform unaffected**
- Operators follow [observability-playbook.md](../operations/observability-playbook.md) §12

### High latency (network)

- Mobile: batch less frequently on metered connection (future tuning)
- Backend: async export only

### Network interruption (App → Collector)

- Transient gap; no request retry from HTTP middleware for telemetry

### VM crash

- Total telemetry outage until restore
- Product continues via App Platform

### Mobile offline

- No blocking UI
- Drop mobile telemetry after local buffer limit

### Laravel queue saturation

- Worker prioritizes job completion over OTLP flush
- `SmartHomeActionJob` and `PushNotificationJob` timeouts unchanged ([scheduler-smart-home-operational-checklist.md](../operations/scheduler-smart-home-operational-checklist.md))

---

## 8. Mandatory engineering rules

Every instrumentation PR **must** satisfy:

| # | Rule |
| --- | --- |
| R1 | No `await` / blocking flush on HTTP response path |
| R2 | No synchronous OTLP in `SmartHomeActionJob`, `PushNotificationJob`, or scheduler command |
| R3 | Export timeout ≤ 2 s per attempt (configurable; never unbounded) |
| R4 | Collector unreachable → no exception propagated to user |
| R5 | No retry loop without max attempts |
| R6 | Mobile export off main thread |
| R7 | Phase 11 QA includes **Collector stopped → API still 200** test ([spec.md](../specs/observability-foundation/mvp/spec.md)) |
| R8 | Telemetry failure must not fail queue job unless job purpose is telemetry (never) |
| R9 | Aligns with [telemetry-decision-guide.md](telemetry-decision-guide.md) — metrics for SLOs, not blocking logs |

### Anti-patterns

| Anti-pattern | Fix |
| --- | --- |
| `flush()` before every `return` in controller | Batch processor; shutdown hook only |
| Throw if OTel init fails | Log warning; app boots without telemetry |
| Infinite export retry | Cap retries; drop |
| Sync mobile export on button tap | Background batch |
| Increase job timeout for telemetry | Keep job timeout for domain work only |

---

## 9. Relationship with other documents

| Document | Alignment |
| --- | --- |
| [ADR-029](../decisions/ADR-029-telemetry-data-model.md) | Failure policy for export |
| [ADR-028](../decisions/ADR-028-observability-platform.md) | Collector optional for correctness |
| [infrastructure-review.md](../specs/observability-foundation/mvp/infrastructure-review.md) | Failure analysis §8 |
| [security-review.md](../specs/observability-foundation/mvp/security-review.md) | Under attack, drop telemetry not product |
| [notification-architecture.md](notification-architecture.md) | Push remains best-effort |
| [asynchronous-orchestration.md](asynchronous-orchestration.md) | Job/provider spans must not delay layers |

---

## Review checklist

- [ ] Critical paths tested with Collector stopped
- [ ] No new blocking calls in HTTP middleware
- [ ] Queue jobs complete within existing timeouts
- [ ] Mobile manual test: airplane mode → app usable
