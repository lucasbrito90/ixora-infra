# SLO Philosophy

**Status:** Active architecture guide  
**ADRs:** [ADR-028](../decisions/ADR-028-observability-platform.md) · [ADR-029](../decisions/ADR-029-telemetry-data-model.md) · [ADR-030](../decisions/ADR-030-observability-security-and-privacy.md) · [ADR-031](../decisions/ADR-031-retention-storage-and-cost-control.md)  
**Complements:** [`metrics-philosophy.md`](metrics-philosophy.md) · [`alerting-philosophy.md`](alerting-philosophy.md) · [`recording-rules-philosophy.md`](recording-rules-philosophy.md) · [`specs/observability-foundation/mvp/recording-rules-foundation.md`](../specs/observability-foundation/mvp/recording-rules-foundation.md)  
**Established:** Phase 8.9 — Recording Rules & SLO Foundation

> **Rule of thumb:** An SLO is a **promise about reliability** backed by a measurable SLI and a finite error budget. If you cannot explain what happens when the budget is exhausted, the SLO is not ready.

---

## 1. Purpose

Service Level Objectives (SLOs) translate operational metrics into **agreed reliability targets** that balance user experience, engineering velocity, and infrastructure cost.

At Ixora, SLOs answer:

- How reliable must the HTTP API be for users to trust the product?
- What Smart Home automation failure rate is acceptable before users notice?
- How much push delivery failure can occur before it affects user retention?
- When should engineering pause feature work to fix reliability?

SLOs are **internal engineering commitments**. They are not customer-facing SLAs in the MVP phase.

---

## 2. Core concepts

### 2.1 SLI — Service Level Indicator

An SLI is a **quantitative measure** of service behaviour from the user's perspective.

| Property | Definition |
| --- | --- |
| **What it measures** | A specific aspect of reliability (availability, latency, correctness) |
| **How it is computed** | PromQL expression over raw metrics or recording rules |
| **Time window** | Rolling window (5m, 1h, 30d) |
| **Good events / Valid events** | Ratio that defines "success" |

**Examples at Ixora:**

| SLI | Good events | Valid events |
| --- | --- | --- |
| HTTP availability | Requests without `outcome=server_error` | All HTTP requests |
| HTTP latency | Requests completing under threshold | All HTTP requests with duration |
| Queue success rate | Jobs with `outcome=success` | Jobs excluding `retried`/`released` |
| Smart Home success rate | Actions with `outcome=success` | All Smart Home actions |
| Scheduler dispatch success | Events with `outcome=success` | Events excluding `overlap_prevented`/`skipped` |
| Collector availability | Time Collector pipeline is healthy | Total observation time |

### 2.2 SLO — Service Level Objective

An SLO is a **target value** for an SLI over a defined time period.

```
SLO = SLI ≥ target over evaluation period
```

| SLO example | SLI | Target | Period |
| --- | --- | --- | --- |
| HTTP API availability | HTTP success rate | 99.5% | 30 days |
| HTTP API latency | Requests under 2 s (p95) | 95% | 30 days |
| Queue reliability | Queue job success rate | 99% | 30 days |
| Smart Home automation | Action success rate | 99% | 30 days |
| Push delivery | Push queue success rate | 99% | 30 days |
| Collector pipeline | Collector availability | 99.9% | 30 days |

**Phase 8.9 scope:** SLO targets are **documented as examples only**. No targets are enforced in production.

### 2.3 SLA — Service Level Agreement

An SLA is a **contractual commitment** to customers with consequences for breach (credits, penalties).

| Dimension | SLO | SLA |
| --- | --- | --- |
| **Audience** | Internal engineering | External customers |
| **Consequence of miss** | Error budget policy, release pause | Financial penalty, contract breach |
| **Measurement** | Prometheus SLI recording rules | Same SLIs, externally audited |
| **Ixora MVP status** | Architecture defined (Phase 8.9) | Not applicable — no customer SLA |

**Rule:** SLOs must exist and be measured before any SLA is offered. Never publish an SLA without 90+ days of SLO data.

### 2.4 Error Budget

The error budget is the **allowable unreliability** within an SLO period.

```
Error budget = 100% − SLO target

Example: 99.5% SLO → 0.5% error budget per 30 days
         = 0.005 × 30 × 24 × 60 = 216 minutes of allowed downtime/errors per month
```

| SLO target | Error budget (30 days) | Meaning |
| --- | --- | --- |
| 99% | 7.2 hours | Lenient — suitable for non-critical internal services |
| 99.5% | 3.6 hours | Standard — suitable for HTTP API, Queue |
| 99.9% | 43.2 minutes | Strict — suitable for Collector, critical path |
| 99.95% | 21.6 minutes | Very strict — reserved for future production SLA |

---

## 3. Availability

Availability measures the proportion of time (or requests) a service is **correctly operational**.

### 3.1 Request-based availability

```
availability = good_requests / total_requests
```

Used for: HTTP API, Queue jobs, Smart Home actions, Push deliveries.

### 3.2 Time-based availability

```
availability = uptime_seconds / total_seconds
```

Used for: Collector pipeline, Prometheus, Grafana, Loki, Tempo.

### 3.3 Ixora availability SLIs

| Service | SLI formula (via recording rule) | SLO target (example) |
| --- | --- | --- |
| HTTP API | `ixora:http:availability:5m` | 99.5% / 30d |
| Queue Workers | `ixora:queue:success_rate:5m` | 99% / 30d |
| Smart Home | `ixora:smart_home:success_rate:5m` | 99% / 30d |
| Push Queue | `ixora:push:success_rate:5m` | 99% / 30d |
| Scheduler | `ixora:scheduler:success_rate:5m` | 99.5% / 30d |
| Collector | `ixora:collector:availability` | 99.9% / 30d |

---

## 4. Latency

Latency measures how quickly a service responds to requests.

### 4.1 Latency SLI patterns

| Pattern | Definition | Ixora example |
| --- | --- | --- |
| **Percentile threshold** | Proportion of requests completing under N ms | 95% of HTTP requests < 2000 ms |
| **Percentile value** | The p95/p99 latency value itself | HTTP p95 < 2 s (monitored, not ratio-based) |

Latency SLOs at Ixora use **percentile threshold** pattern:

```
latency_sli = count(requests where duration < threshold) / count(all requests)
```

Recording rules provide the percentile values (`ixora:http:p95_latency:5m`); SLO rules compute the proportion under threshold (Phase 10+).

### 4.2 Ixora latency SLIs

| Service | Threshold | SLI target (example) | Recording rule |
| --- | --- | --- | --- |
| HTTP API | 2000 ms (p95) | 95% under threshold / 30d | `ixora:http:p95_latency:5m` |
| Queue Workers | 30000 ms (p95) | 99% under threshold / 30d | `ixora:queue:p95_latency:5m` |
| Smart Home actions | 10000 ms (p95) | 95% under threshold / 30d | `ixora:smart_home:p95_latency:5m` |
| Scheduler events | 5000 ms (p95) | 99% under threshold / 30d | `ixora:scheduler:p95_latency:5m` |

---

## 5. Reliability

Reliability encompasses both availability and latency — a service that is "up" but slow is unreliable.

### 5.1 Composite reliability

At Ixora, reliability is measured per-domain, not as a single platform-wide number:

| Domain | Primary reliability signal | Secondary signal |
| --- | --- | --- |
| HTTP API | Availability (error rate) | Latency (p95) |
| Queue Workers | Success rate | Processing latency |
| Smart Home | Action success rate | Provider latency |
| Push Notifications | Delivery success rate | Queue processing latency |
| Scheduler | Dispatch success rate | Event duration |
| Collector | Pipeline availability | Export failure rate |

D-01 Platform Overview aggregates these into a platform health view but does not define a single platform-wide SLO. Each domain has its own SLO.

---

## 6. Expectations framework

### 6.1 Customer expectations

What users experience and care about:

| User-facing capability | Reliability expectation | Measured by |
| --- | --- | --- |
| API responds to requests | Fast, no 500 errors | HTTP availability + latency SLO |
| Schedules execute on time | Automations run when scheduled | Scheduler dispatch SLO |
| Smart Home actions work | Devices respond to commands | Smart Home success SLO |
| Push notifications arrive | Notifications delivered promptly | Push success SLO |

### 6.2 Business expectations

What the product team needs for confidence:

| Business concern | SLO | Decision it enables |
| --- | --- | --- |
| Can we ship this feature? | Error budget remaining > 50% | Yes — budget available |
| Should we pause releases? | Error budget exhausted | Yes — fix reliability first |
| Is automation trustworthy? | Smart Home SLO ≥ 99% | Product marketing claim |
| Are pushes reliable enough? | Push SLO ≥ 99% | Feature launch readiness |

### 6.3 Operational expectations

What on-call engineers need:

| Operational concern | SLI | Alert (Phase 9) |
| --- | --- | --- |
| API degrading | `ixora:http:error_rate:5m` rising | HTTP error rate alert |
| Queue backing up | `ixora:queue:failure_rate:5m` rising | Queue failure alert |
| Collector failing | `ixora:collector:availability` dropping | Collector down alert |
| Smart Home failing | `ixora:smart_home:failure_rate:5m` rising | Smart Home failure alert |

---

## 7. Golden Signals as SLO foundation

The Four Golden Signals map directly to SLI categories:

| Golden Signal | SLI type | Ixora SLI |
| --- | --- | --- |
| **Latency** | Percentile threshold | HTTP/Queue/Smart Home p95 latency |
| **Traffic** | Rate (informational, not SLO) | Request rate, dispatch rate |
| **Errors** | Availability / success rate | Error rate, failure rate |
| **Saturation** | Gauge (capacity, not SLO) | Queue depth, active jobs |

SLOs focus on **Errors** and **Latency**. Traffic and Saturation inform capacity planning but are not SLO targets in MVP.

---

## 8. RED method for service SLOs

| RED signal | SLI | SLO example |
| --- | --- | --- |
| **Rate** | Not an SLO (informational) | — |
| **Errors** | Error rate / failure rate | HTTP availability ≥ 99.5% |
| **Duration** | Latency percentile | HTTP p95 < 2 s for 95% of requests |

Apply RED to: HTTP API, Push queue, Smart Home actions.

---

## 9. USE method for resource SLOs

| USE signal | SLI | SLO example |
| --- | --- | --- |
| **Utilization** | Not an SLO (capacity planning) | — |
| **Saturation** | Queue depth, export queue size | Warning alert, not SLO |
| **Errors** | Export failures, scrape failures | Collector availability ≥ 99.9% |

Apply USE to: Collector, Prometheus, Queue workers, Scheduler.

---

## 10. Multi-window concepts

Multi-window SLO evaluation compares SLI performance across **different time windows** to detect both fast and slow burns of error budget.

### 10.1 Why multi-window matters

A 5-minute error spike might consume a small fraction of the monthly budget (recoverable). A sustained 1-hour elevation might consume a significant portion (action required). A 6-hour gradual degradation might consume the entire budget (release pause).

Single-window alerting misses slow burns. Multi-window catches both.

### 10.2 Standard windows (Phase 10+ design)

| Window | Purpose | Detects |
| --- | --- | --- |
| **5 minutes** | Fast burn | Sudden outage, deploy regression |
| **1 hour** | Medium burn | Sustained degradation |
| **6 hours** | Slow burn | Gradual reliability decline |
| **30 days** | Budget tracking | Overall SLO compliance |

### 10.3 Multi-window burn rate (conceptual)

```
burn_rate = (error_rate_in_window / error_budget) × window_duration

Alert when:
  burn_rate_5m > 14.4  AND  burn_rate_1h > 14.4   → page immediately (fast burn)
  burn_rate_1h > 6     AND  burn_rate_6h > 6       → ticket (slow burn)
```

> **Phase 8.9 scope:** Multi-window burn rate is documented as architecture only. Implementation is Phase 10+.

---

## 11. Burn rate concepts

Burn rate measures **how fast the error budget is being consumed** relative to the sustainable rate.

### 11.1 Sustainable burn rate

```
sustainable_burn_rate = 1.0  (consumes exactly the budget over the SLO period)

Example: 99.5% SLO over 30 days
  budget = 0.5% of requests can fail
  sustainable rate = 0.5% / 30 days = 0.0167% per day
  burn_rate = 1.0 means consuming budget at exactly this rate
  burn_rate = 14.4 means budget exhausted in ~2 days instead of 30
```

### 11.2 Burn rate alert tiers (Phase 10+ design)

| Burn rate | Budget exhaustion time | Response |
| --- | --- | --- |
| 1× | 30 days (sustainable) | No alert |
| 6× | 5 days | Warning — investigate within hours |
| 14.4× | ~2 days | Critical — page on-call |
| 100× | ~7 hours | Emergency — all hands |

### 11.3 Relationship with alerting

| Alert type | Phase | Based on |
| --- | --- | --- |
| Threshold alert | Phase 9 | Recording rule > fixed threshold |
| Burn rate alert | Phase 10+ | Multi-window burn rate > tier |
| Budget exhaustion alert | Phase 10+ | Remaining budget < 10% |

Threshold alerts (Phase 9) catch acute problems. Burn rate alerts (Phase 10+) catch both acute and chronic reliability degradation while respecting error budget context.

---

## 12. Error budget policy

### 12.1 Budget consumption

Error budget is consumed when SLI performance drops below the SLO target:

| Event | Budget impact |
| --- | --- |
| HTTP 500 errors | Consumes HTTP availability budget |
| Smart Home action failures | Consumes Smart Home reliability budget |
| Queue job failures | Consumes Queue reliability budget |
| Planned maintenance (Collector) | May consume Collector availability budget — use mute timings |
| Deploy-induced transient errors | Consumes budget — tune `for` duration to minimize |

### 12.2 Budget influences on releases

| Budget remaining | Policy |
| --- | --- |
| > 50% | Normal development velocity; features and fixes ship freely |
| 25–50% | Increased caution; reliability fixes prioritized; feature flags for risky changes |
| 10–25% | Release freeze for non-critical features; focus on reliability |
| < 10% | Full release pause; all engineering on reliability until budget recovers |
| Exhausted (0%) | Postmortem required; SLO target review; no releases until recovery plan approved |

> **Phase 8.9 scope:** Budget policy is documented only. No automated enforcement.

### 12.3 Budget influences on alerting

| Budget state | Alerting behaviour (Phase 10+) |
| --- | --- |
| Healthy (> 50%) | Standard threshold alerts only |
| Degraded (25–50%) | Lower burn rate alert thresholds |
| Critical (< 10%) | All reliability alerts escalate to Critical |
| Exhausted | Automatic release pause notification to team |

---

## 13. Monthly and quarterly budgets

### 13.1 Monthly budget (primary)

The 30-day rolling window is the **primary SLO evaluation period** for Ixora MVP.

| SLO | Monthly budget | Allowed errors (approx.) |
| --- | --- | --- |
| 99% availability | 1% | ~7.2 hours downtime equivalent |
| 99.5% availability | 0.5% | ~3.6 hours |
| 99.9% availability | 0.1% | ~43 minutes |

### 13.2 Quarterly budget (strategic)

Quarterly review aggregates three monthly periods for strategic decisions:

| Quarterly metric | Use |
| --- | --- |
| Average SLO compliance | Trend analysis — improving or degrading? |
| Total budget consumed | Capacity planning — do SLO targets need adjustment? |
| Incidents vs budget | Postmortem correlation — did incidents match budget consumption? |
| Feature velocity vs reliability | Balance assessment — are we shipping too fast? |

Quarterly budgets do not trigger automated alerts. They inform SLO target reviews.

---

## 14. Business tradeoffs

SLO targets involve explicit tradeoffs:

| Higher target (99.9%) | Lower target (99%) |
| --- | --- |
| Less allowed downtime | More allowed downtime |
| More engineering time on reliability | More engineering time on features |
| Higher infrastructure cost (redundancy) | Lower infrastructure cost |
| Stricter release criteria | Faster iteration |
| Required for customer SLA | Internal-only commitment |

**Ixora MVP recommendation (examples, not enforced):**

| Service | Recommended SLO | Rationale |
| --- | --- | --- |
| HTTP API | 99.5% | User-facing; balance reliability and velocity |
| Smart Home | 99% | External provider dependency (Home Assistant) limits control |
| Push Notifications | 99% | Best-effort delivery (ADR-020); FCM dependency |
| Queue Workers | 99% | Internal; retries absorb transient failures |
| Scheduler | 99.5% | Core product function; users depend on timely execution |
| Collector | 99.9% | Observability must not fail silently |

---

## 15. SLO maturity model

| Level | Description | Ixora status |
| --- | --- | --- |
| **Level 0 — No SLOs** | Dashboards only; reactive detection | Before Phase 8.9 |
| **Level 1 — SLI definitions** | SLIs documented; recording rules scaffolded | **Phase 8.9 (current target)** |
| **Level 2 — SLO targets set** | Targets agreed; SLI recording rules active | Phase 9–10 |
| **Level 3 — Error budget tracking** | Budget computed; influences release decisions | Phase 10 |
| **Level 4 — Burn rate alerting** | Multi-window burn rate alerts; automated policy | Phase 11+ |
| **Level 5 — Customer SLA** | External SLA backed by measured SLO data | Post-MVP |

---

## 16. Relationship with other documents

| Document | Role relative to this guide |
| --- | --- |
| [recording-rules-philosophy.md](recording-rules-philosophy.md) | SLI computation via recording rules |
| [recording-rules-foundation.md](../specs/observability-foundation/mvp/recording-rules-foundation.md) | SLI/SLO definitions, catalog, provisioning |
| [alerting-philosophy.md](alerting-philosophy.md) | Threshold alerts (Phase 9) and burn rate alerts (Phase 10+) |
| [alerting-foundation.md](../specs/observability-foundation/mvp/alerting-foundation.md) | Alert rule inventory references SLI recording rules |
| [metrics-philosophy.md](metrics-philosophy.md) | Raw metrics that SLIs aggregate |
| [telemetry-availability-policy.md](telemetry-availability-policy.md) | Best-effort export — SLI data may have gaps during Collector downtime |
| [ADR-031](../decisions/ADR-031-retention-storage-and-cost-control.md) | 30-day metric retention governs max SLO lookback window |

### Document boundaries

| Topic | Owner document |
| --- | --- |
| SLO **thinking**, error budget policy, burn rate concepts | **This document** |
| SLI **formulas**, recording rule catalog, provisioning | [recording-rules-foundation.md](../specs/observability-foundation/mvp/recording-rules-foundation.md) |
| Recording rule lifecycle and naming | [recording-rules-philosophy.md](recording-rules-philosophy.md) |
| Alert thresholds and severity | [alerting-philosophy.md](alerting-philosophy.md) |

---

## Review checklist

Before activating any SLO in production:

- [ ] SLI formula validated against 30+ days of staging data
- [ ] SLO target agreed by engineering and product teams
- [ ] Error budget policy documented and communicated
- [ ] SLI recording rules deployed and producing data
- [ ] Dashboard panels show SLI and remaining budget
- [ ] Burn rate alert tiers defined (Phase 10+)
- [ ] Release policy tied to budget remaining
- [ ] Postmortem process defined for budget exhaustion
- [ ] SLO does not include PII in labels (ADR-030)
- [ ] Collector downtime handled (gaps in SLI data documented)
