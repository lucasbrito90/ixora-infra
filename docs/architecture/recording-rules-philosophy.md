# Recording Rules Philosophy

**Status:** Active architecture guide  
**ADRs:** [ADR-028](../decisions/ADR-028-observability-platform.md) · [ADR-029](../decisions/ADR-029-telemetry-data-model.md) · [ADR-030](../decisions/ADR-030-observability-security-and-privacy.md) · [ADR-031](../decisions/ADR-031-retention-storage-and-cost-control.md)  
**Complements:** [`metrics-philosophy.md`](metrics-philosophy.md) · [`alerting-philosophy.md`](alerting-philosophy.md) · [`slo-philosophy.md`](slo-philosophy.md) · [`telemetry-naming-convention.md`](telemetry-naming-convention.md) · [`specs/observability-foundation/mvp/recording-rules-foundation.md`](../specs/observability-foundation/mvp/recording-rules-foundation.md)  
**Established:** Phase 8.9 — Recording Rules & SLO Foundation

> **Rule of thumb:** A recording rule exists to **pre-compute an expression that is reused, expensive, or semantically important** — not to duplicate a metric that already exists as a raw counter or histogram.

---

## 1. Purpose

Recording rules are Prometheus rules that **evaluate a PromQL expression at a fixed interval** and store the result as a new time series. They sit between raw instrumentation metrics and the consumers that depend on them — dashboards, alert rules, and SLO calculations.

| Layer | Role | Example |
| --- | --- | --- |
| **Raw metrics** | Instrumentation output from `back_vibes` via Collector | `ixora_http_server_request_total{outcome="server_error"}` |
| **Recording rules** | Pre-computed aggregates, rates, ratios, percentiles | `ixora:http:error_rate:5m` |
| **Dashboards** | Visualization | D-05 panel queries `ixora:http:error_rate:5m` |
| **Alert rules** | Threshold evaluation | Alert on `ixora:http:error_rate:5m > 0.01` |
| **SLO rules** | Error budget burn rate | `ixora:slo:http:burn_rate:1h` (Phase 10+) |

### 1.1 Why recording rules exist

Without recording rules, every dashboard panel and alert rule independently evaluates the same expensive PromQL expression. At query time, Prometheus re-scans the TSDB for each request. With seven dashboards and future alert rules all computing `histogram_quantile(0.95, ...)`, query load multiplies.

Recording rules shift computation from **query time** to **evaluation time** (every 30 s, aligned with `evaluation_interval` in `prometheus.yml`).

---

## 2. Benefits

| Benefit | Description |
| --- | --- |
| **Performance** | Expensive expressions (`histogram_quantile`, multi-metric ratios) computed once per interval, not per dashboard refresh |
| **Reuse** | One canonical series consumed by D-01, D-05, and alert rules — no expression drift |
| **Maintainability** | Change the formula in one place; all consumers update automatically |
| **Consistency** | D-01 Platform Overview and D-05 HTTP API show the same error rate because they query the same recording rule |
| **SLO foundation** | SLI recording rules are prerequisites for error budget and burn-rate calculations |
| **Alert simplicity** | Alert rules compare a pre-computed ratio to a threshold — no nested PromQL |

---

## 3. Performance

### 3.1 Query-time vs evaluation-time cost

```
Without recording rules:
  Dashboard refresh (×7 dashboards × ~20 panels) → 140+ independent PromQL evaluations
  Alert evaluation (×N rules)                     → N more evaluations
  Each evaluation scans raw histogram buckets

With recording rules:
  Prometheus evaluation (every 30 s)              → 1 evaluation per rule
  Dashboard refresh                             → simple metric lookup
  Alert evaluation                              → simple threshold on pre-computed series
```

### 3.2 When performance gain matters

| Expression type | Performance impact | Recording rule priority |
| --- | --- | --- |
| Simple `rate()` on a counter | Low | Defer — query directly |
| Ratio of two `rate()` expressions | Medium | High — reused across dashboards |
| `histogram_quantile()` | High | High — always record |
| Multi-window burn rate | Very high | Critical — SLO only (Phase 10+) |
| `topk()` over histogram quantiles | Very high | Record base quantile; keep `topk` at query time |

---

## 4. Reuse

The primary driver for recording rules at Ixora is **expression reuse across consumers**.

### 4.1 Duplicate patterns identified (Phase 8.9 architecture review)

| Pattern | Occurrences | Dashboards | Future recording rule |
| --- | --- | --- | --- |
| HTTP server error rate | 3+ | D-01, D-05 | `ixora:http:error_rate:5m` |
| HTTP availability (1 − error rate) | 1 | D-01 | `ixora:http:availability:5m` |
| Queue job success rate | 2+ | D-01, D-04 | `ixora:queue:success_rate:5m` |
| Smart Home action success rate | 5+ | D-01, D-02 | `ixora:smart_home:success_rate:5m` |
| Smart Home action failure rate | 3+ | D-01, D-02 | `ixora:smart_home:failure_rate:5m` |
| Push queue success rate | 1 | D-03 | `ixora:push:success_rate:5m` |
| Push queue failure rate | 2+ | D-03 | `ixora:push:failure_rate:5m` |
| Scheduler dispatch success rate | 1 | D-06 | `ixora:scheduler:success_rate:5m` |
| HTTP p95 latency | 4+ | D-01, D-05 | `ixora:http:p95_latency:5m` |
| Queue p95 latency | 4+ | D-04, D-03 | `ixora:queue:p95_latency:5m` |
| Smart Home p95 latency | 3+ | D-01, D-02 | `ixora:smart_home:p95_latency:5m` |
| Scheduler p95 latency | 3+ | D-06 | `ixora:scheduler:p95_latency:5m` |
| Collector availability | 1 | D-07 | `ixora:collector:availability` |

**Rule:** If an expression appears in more than one dashboard or is intended for alerting, it must become a recording rule before Phase 9 alert deployment.

---

## 5. Maintainability

Recording rules are **platform contracts** — the same stability requirements as metric names ([metrics-philosophy.md §8](metrics-philosophy.md)).

| Principle | Meaning |
| --- | --- |
| **Single source of truth** | The recording rule defines the canonical formula; dashboards and alerts reference it |
| **Documented in catalog** | Every rule has a REC-NNN identifier in [recording-rules-foundation.md](../specs/observability-foundation/mvp/recording-rules-foundation.md) |
| **Reviewed like metrics** | New recording rules require PR review with cardinality check |
| **Versioned via git** | All rules live in `collector/prometheus/rules/recording/` — no UI configuration |
| **Backward compatible** | Renaming a recording rule breaks dashboards and alerts — treat names as immutable |

---

## 6. When to create recording rules

Create a recording rule when **any** of these conditions is true:

| Condition | Example |
| --- | --- |
| Expression reused across 2+ dashboards | HTTP error rate in D-01 and D-05 |
| Expression used by alert rules | Queue failure rate threshold |
| Expression is expensive (`histogram_quantile`) | p95 latency across all services |
| Expression defines an SLI | HTTP success rate for SLO tracking |
| Expression combines multiple raw metrics | Availability = 1 − error rate |
| Expression has semantic meaning beyond raw data | `ixora:smart_home:success_rate:5m` is clearer than nested PromQL |

---

## 7. When NOT to create recording rules

Do not create a recording rule when:

| Condition | Why | Use instead |
| --- | --- | --- |
| Expression used in exactly one panel | No reuse benefit; adds series cost | Query raw metric directly |
| Raw counter already sufficient | `rate(ixora_queue_job_total[5m])` is cheap alone | Direct PromQL in panel |
| High-cardinality breakdown needed | Recording `topk(15, ...)` by `http_route` creates 15+ series per environment | Record aggregate; keep breakdown at query time |
| Label set differs per consumer | D-02 filters by `provider`; D-01 does not | Record environment-level aggregate; filter at query time for breakdowns |
| Metric does not exist yet | Phase 7B.5 push delivery metric pending | Defer until instrumentation ships |
| One-off debugging query | Ad-hoc investigation in Grafana Explore | No recording rule |

---

## 8. Ownership

Every recording rule group has a declared owner.

| Rule file | Owner team | Scope |
| --- | --- | --- |
| `application.rules.yml` | Backend | HTTP, Queue, Scheduler |
| `business.rules.yml` | Product / Backend | Smart Home, Push, Automation |
| `infrastructure.rules.yml` | SRE | Collector, Prometheus, backends |
| `slo.rules.yml` | SRE | SLI aggregates, error budget inputs (Phase 10+) |

**Rules:**
- Recording rules without a documented owner must not be deployed.
- Changes to `slo.rules.yml` require SRE review — SLO formulas affect release decisions.

---

## 9. Lifecycle

| Stage | Activity |
| --- | --- |
| **Proposal** | Identify duplicate PromQL pattern; assign REC-NNN ID; document in catalog |
| **Design** | Define `record` name, source expression, labels, evaluation interval |
| **Review** | PR review: cardinality, ADR-030 compliance, naming convention, catalog entry |
| **Deploy** | Uncomment `rule_files` in `prometheus.yml`; mount rules volume; reload Prometheus |
| **Migrate consumers** | Update dashboard panels and alert rules to query recording rule |
| **Validate** | Confirm recording rule output matches previous raw PromQL (staging comparison) |
| **Deprecate** | Mark catalog entry deprecated; migrate all consumers; remove rule after grace period |

---

## 10. Naming convention

Recording rule output names follow the **Google SRE recording rule convention**, adapted for Ixora:

```
ixora:<domain>:<metric>:<aggregation_window>
```

| Component | Rule | Example |
| --- | --- | --- |
| Prefix | Always `ixora:` | `ixora:` |
| Domain | Service or layer | `http`, `queue`, `scheduler`, `smart_home`, `push`, `collector` |
| Metric | Semantic name (snake_case) | `error_rate`, `success_rate`, `p95_latency`, `availability` |
| Window | Rate/aggregation window | `5m`, `15m`, `1h`, `30d` |

### 10.1 Standard names

| Recording rule name | Meaning |
| --- | --- |
| `ixora:http:error_rate:5m` | HTTP 5xx rate over 5 minutes |
| `ixora:http:availability:5m` | HTTP availability (1 − error rate) |
| `ixora:http:p95_latency:5m` | HTTP request p95 latency |
| `ixora:queue:success_rate:5m` | Queue job success rate |
| `ixora:queue:failure_rate:5m` | Queue job failure rate |
| `ixora:queue:p95_latency:5m` | Queue job p95 latency |
| `ixora:scheduler:dispatch_rate:5m` | Scheduler event dispatch rate |
| `ixora:scheduler:success_rate:5m` | Scheduler event success rate |
| `ixora:smart_home:success_rate:5m` | Smart Home action success rate |
| `ixora:smart_home:failure_rate:5m` | Smart Home action failure rate |
| `ixora:push:success_rate:5m` | Push queue job success rate |
| `ixora:collector:availability` | Collector pipeline availability |

### 10.2 Naming rules

- Use **colons** as separators — not dots or underscores (Prometheus recording rule convention).
- Raw instrumentation metrics use dots/underscores (`ixora_http_server_request_total`); recording rules use colons (`ixora:http:error_rate:5m`).
- Include the aggregation window in the name when the window is part of the semantic meaning.
- SLO rules add `:slo` suffix: `ixora:slo:http:success_rate:30d` (Phase 10+).
- Do not embed threshold values in names — thresholds belong in alert rules.

---

## 11. Versioning

Recording rules are version-controlled YAML files. There is no runtime versioning.

| Change type | Procedure |
| --- | --- |
| **New rule** | Add to appropriate `.rules.yml`; assign REC-NNN; update catalog |
| **Formula change** | PR with staging validation; compare old vs new output for 24 h |
| **Rename rule** | Treat as breaking change — migrate all consumers first |
| **Remove rule** | Deprecate in catalog; verify zero consumers; remove in next release |

Prometheus reloads rules on config reload (`POST /-/reload`) or container restart. Rule changes take effect within one `evaluation_interval` (30 s).

---

## 12. Review process

Before merging a recording rule PR:

| # | Question |
| --- | --- |
| 1 | Is the expression reused or expensive enough to justify a recording rule? |
| 2 | Does a recording rule with this semantic meaning already exist? |
| 3 | Is the `record` name consistent with the naming convention (§10)? |
| 4 | Is the REC-NNN catalog entry updated? |
| 5 | Does the rule preserve low-cardinality labels only (ADR-030)? |
| 6 | Are source metrics in the existing instrumentation inventory? |
| 7 | Will dashboards/alerts be migrated to consume this rule (Phase 9)? |
| 8 | Does the rule file belong in the correct category (application/business/infrastructure/slo)? |

---

## 13. Deprecation

| Condition | Action |
| --- | --- |
| Source metric renamed or removed | Update or remove recording rule in same PR as metric migration |
| Formula superseded by better approach | Deprecate old rule; migrate consumers; remove after 30 days |
| Rule produces series with zero queries for 90 days | Review: is the consumer missing or is the rule unnecessary? |
| Cardinality exceeds ADR-031 budget | Reduce label set or remove breakdown dimensions |

---

## 14. Relationship with dashboards

Dashboards are the **primary consumers** of recording rules.

### 14.1 Migration strategy

```
Phase 8.9 (current):  Dashboards query raw metrics directly (complex PromQL)
         ↓
Phase 9:              Recording rules activated; dashboards migrated panel-by-panel
         ↓
Phase 10:             All shared expressions consume recording rules; raw PromQL only for breakdowns
```

**Migration rules:**
- Migrate high-reuse panels first (D-01 Platform Overview — 5+ duplicate expressions).
- Keep variable-filtered breakdowns (`by (provider)`, `by (queue)`) as query-time PromQL until a dedicated breakdown recording rule is justified.
- Panel descriptions should note the recording rule name once migrated: `Source: ixora:http:error_rate:5m`.

---

## 15. Relationship with alerts

Alert rules should **prefer recording rules** over raw PromQL ([alerting-philosophy.md §3](alerting-philosophy.md)).

| Alert pattern | Without recording rule | With recording rule |
| --- | --- | --- |
| HTTP error rate > 1% | `sum(rate(...{outcome="server_error"}[5m])) / sum(rate(...[5m])) > 0.01` | `ixora:http:error_rate:5m > 0.01` |
| Queue failure rate > 5% | Nested ratio with label filters | `ixora:queue:failure_rate:5m{queue="push"} > 0.05` |
| Smart Home failure > 20% | 5-line PromQL in alert rule | `ixora:smart_home:failure_rate:5m > 0.20` |

**Benefits for alerting:**
- Alert evaluation is faster (simple threshold on pre-computed series).
- Alert and dashboard show identical values — no formula drift.
- Alert rule YAML is readable and auditable.

---

## 16. Relationship with SLOs

Recording rules are the **computation layer** for SLIs. SLO targets and error budgets are defined in [slo-philosophy.md](slo-philosophy.md) and [recording-rules-foundation.md](../specs/observability-foundation/mvp/recording-rules-foundation.md).

```
Raw metrics → Recording rules (SLI) → SLO rules (error budget) → Burn rate alerts (Phase 10+)
```

| SLI recording rule | SLO consumer | Alert consumer (Phase 10+) |
| --- | --- | --- |
| `ixora:slo:http:success_rate:30d` | HTTP availability SLO | Multi-window burn rate |
| `ixora:slo:queue:success_rate:30d` | Queue reliability SLO | Burn rate alert |
| `ixora:slo:smart_home:success_rate:30d` | Business automation SLO | Business burn rate |

SLO recording rules live in `slo.rules.yml` and are **not activated** until Phase 10.

---

## 17. Anti-patterns

| Anti-pattern | Why it fails | Correct approach |
| --- | --- | --- |
| Recording rule for every panel | Series explosion; no reuse benefit | Record only shared or expensive expressions |
| High-cardinality labels on recording rules | `by (http_route)` creates hundreds of series | Record aggregate; breakdown at query time |
| Duplicating raw counter as recording rule | `record: ixora:http:requests:5m` = `rate(...)` adds no value | Query `rate()` directly unless reused |
| Different formulas in dashboard vs alert | Operator sees 2.1% on dashboard, alert fires at 1.8% | Both consume same recording rule |
| Recording rule without catalog entry | Undocumented platform contract | Assign REC-NNN before merge |
| Alert rule with 10-line PromQL | Unmaintainable; slow evaluation | Pre-compute via recording rule |
| SLO burn rate without SLI recording rule | Burn rate formula duplicated and inconsistent | SLI rule first, then burn rate rule |
| Using recording rule names in instrumentation | Recording rules are computed, not emitted | Emit raw metrics; record in Prometheus |

---

## 18. Examples

### 18.1 HTTP error rate (REC-001)

**Source expression (current — D-01, D-05):**
```promql
sum(rate(ixora_http_server_request_total{outcome="server_error"}[5m]))
/ sum(rate(ixora_http_server_request_total[5m]))
```

**Recording rule (Phase 9):**
```yaml
- record: ixora:http:error_rate:5m
  expr: |
    sum by (environment) (rate(ixora_http_server_request_total{outcome="server_error"}[5m]))
    / sum by (environment) (rate(ixora_http_server_request_total[5m]))
```

**Consumers:** D-01 panel 1185, D-05 panel 213, alert `Application / HTTP API — Elevated Error Rate`.

### 18.2 Smart Home success rate (REC-005)

**Source expression (current — D-01 × 3, D-02 × 2):**
```promql
sum(rate(ixora_smart_home_action_total{outcome="success"}[5m]))
/ sum(rate(ixora_smart_home_action_total[5m]))
```

**Recording rule (Phase 9):**
```yaml
- record: ixora:smart_home:success_rate:5m
  expr: |
    sum by (environment) (rate(ixora_smart_home_action_total{outcome="success"}[5m]))
    / sum by (environment) (rate(ixora_smart_home_action_total[5m]))
```

**Consumers:** D-01 panels 400/739/1007, D-02 panels 158/472, alert `Business / Smart Home — Elevated Failure Rate`.

### 18.3 Queue p95 latency (REC-007)

**Source expression (current — D-04 × 3, D-03 × 3):**
```promql
histogram_quantile(0.95, sum by (le) (rate(ixora_queue_job_duration_bucket[5m])))
```

**Recording rule (Phase 9):**
```yaml
- record: ixora:queue:p95_latency:5m
  expr: |
    histogram_quantile(0.95,
      sum by (le, environment, queue) (rate(ixora_queue_job_duration_bucket[5m]))
    )
```

**Consumers:** D-04 latency section, D-03 performance section, future latency alert.

---

## 19. Relationship with other documents

| Document | Role relative to this guide |
| --- | --- |
| [metrics-philosophy.md](metrics-philosophy.md) | Source metrics that recording rules aggregate |
| [alerting-philosophy.md](alerting-philosophy.md) | Alert rules consume recording rules for threshold evaluation |
| [slo-philosophy.md](slo-philosophy.md) | SLO architecture built on SLI recording rules |
| [telemetry-naming-convention.md](telemetry-naming-convention.md) | Raw metric names (`ixora.*`); recording rules use `ixora:*` colon convention |
| [recording-rules-foundation.md](../specs/observability-foundation/mvp/recording-rules-foundation.md) | Catalog, SLI definitions, provisioning, migration strategy |
| [alerting-foundation.md](../specs/observability-foundation/mvp/alerting-foundation.md) | Alert rules reference recording rules (Phase 9 integration) |
| [dashboard-conventions.md](../specs/observability-foundation/mvp/dashboard-conventions.md) | Dashboard panels migrate to recording rule queries |

### Document boundaries

| Topic | Owner document |
| --- | --- |
| Recording rule **thinking**, lifecycle, anti-patterns | **This document** |
| Recording rule **catalog**, SLI formulas, provisioning files | [recording-rules-foundation.md](../specs/observability-foundation/mvp/recording-rules-foundation.md) |
| SLO targets, error budgets, burn rate concepts | [slo-philosophy.md](slo-philosophy.md) |
| Raw metric names and label allowlist | [telemetry-naming-convention.md](telemetry-naming-convention.md) |
| Alert threshold and severity decisions | [alerting-philosophy.md](alerting-philosophy.md) |

---

## Review checklist

Before deploying any recording rule:

- [ ] Expression is reused across 2+ consumers or is expensive (`histogram_quantile`)
- [ ] REC-NNN catalog entry exists and is accurate
- [ ] `record` name follows `ixora:<domain>:<metric>:<window>` convention
- [ ] Labels preserve only low-cardinality dimensions (ADR-030)
- [ ] Source metrics exist in instrumentation inventory
- [ ] Rule file is in the correct category (application/business/infrastructure/slo)
- [ ] Dashboard and alert migration plan documented
- [ ] Staging validation: recording rule output matches raw PromQL for 24 h
- [ ] Cardinality estimate within ADR-031 budget
