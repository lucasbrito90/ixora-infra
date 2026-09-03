# Alerting Philosophy

**Status:** Active architecture guide  
**ADRs:** [ADR-028](../decisions/ADR-028-observability-platform.md) · [ADR-029](../decisions/ADR-029-telemetry-data-model.md) · [ADR-030](../decisions/ADR-030-observability-security-and-privacy.md) · [ADR-031](../decisions/ADR-031-retention-storage-and-cost-control.md)  
**Complements:** [`metrics-philosophy.md`](metrics-philosophy.md) · [`logs-philosophy.md`](logs-philosophy.md) · [`traces-philosophy.md`](traces-philosophy.md) · [`telemetry-decision-guide.md`](telemetry-decision-guide.md) · [`specs/observability-foundation/mvp/alerting-foundation.md`](../specs/observability-foundation/mvp/alerting-foundation.md)  
**Established:** Phase 8.8 — Alerting Foundation

> **Rule of thumb:** An alert exists to create an **action**, not awareness. If you cannot describe what an on-call engineer must do within 5 minutes of receiving an alert, that alert does not belong in production.

---

## 1. Purpose of alerts

Alerts exist to **interrupt humans** when the system requires immediate human attention.

This is the most disruptive action observability can take. Interrupted engineers lose context, context switches cost time and cognitive load, and false alarms destroy trust in the entire observability platform. Every alert must justify that cost.

| Signal | What it captures | Primary consumer |
| --- | --- | --- |
| **Metrics** | Aggregated measurements over time | Dashboards, SLOs, alerts |
| **Logs** | Discrete events with context | Investigation, audit |
| **Traces** | Workflow structure per execution | Debug, performance root cause |
| **Alerts** | **Metric thresholds requiring human action** | On-call engineer, SRE |

Alerts consume metrics. They do not consume individual logs or traces directly. An alert fires when a metric crosses a threshold that represents a **business or operational problem the system cannot self-correct**.

### 1.1 The alerting contract

> Every alert creates an implicit contract with the team: **"A human must act on this within the defined response window."**

Breaking that contract — through false alarms, under-specified alerts, or over-alerting — degrades team responsiveness and engineering culture. An ignored alert is worse than no alert.

---

## 2. Dashboards vs Alerts

Dashboards and alerts are **complementary, not interchangeable**. They serve different roles.

| Dimension | Dashboard | Alert |
| --- | --- | --- |
| **Purpose** | Situational awareness; exploration; investigation | Immediate human action trigger |
| **Consumer** | Engineer browsing; on-call post-alert | On-call engineer mid-incident |
| **Trigger** | Human intent | Automatic threshold breach |
| **Time sensitivity** | Asynchronous | Synchronous |
| **Signal fidelity** | Full trend, context, history | Binary: firing or not |
| **Correct response to a metric anomaly** | Explore and understand | Page and respond |

**Rules:**
- A dashboard does **not** replace an alert for critical conditions. An anomaly visible on D-01 Platform Overview but without an alert will be missed at 3 AM.
- An alert does **not** replace a dashboard for investigation. Alerts tell you **something is wrong**; dashboards tell you **what, where, and why**.
- Every alert **must reference a dashboard** via `dashboard_uid` label and annotation. This is non-negotiable.
- Every dashboard should have **at most one alert trigger** per section — not one per panel.

---

## 3. Metrics vs Alerts

Not every metric warrants an alert. Metrics are the **raw material** for alerts, not alerts themselves.

| Metric state | Alert warranted? | Rationale |
| --- | --- | --- |
| Rate is zero (no traffic) | Probably not | System may be idle; need business context |
| Rate is high | No | High throughput is usually good |
| Error rate > threshold | **Yes** | Actionable: investigate source of errors |
| Latency p95 > threshold | **Yes** | Actionable: investigate bottleneck |
| Latency p50 rising gradually | Maybe | Consider a warning alert; trend is actionable |
| Queue depth > threshold | **Yes** | Actionable: workers may be saturated or stopped |
| Active jobs = 0 for extended period | **Yes** (context-dependent) | Actionable: workers stopped? Queue drained legitimately? |
| Push success rate < threshold | **Yes** | Actionable: FCM issue or token expiry wave |

**Alert creation checklist:**
1. Is there a metric that reliably captures the condition?
2. Is there a threshold that separates normal from abnormal?
3. Does an engineer know exactly what to do when it fires?
4. Does a runbook exist or can it be written?
5. Can the condition be confirmed and resolved within the response window?

If any answer is "no", the alert is not ready.

---

## 4. Logs vs Alerts

Logs capture **individual events**. Alerts capture **rates and thresholds** over many events.

| Use case | Correct approach |
| --- | --- |
| A specific FCM error_code appeared in logs | **Not alertable directly** — instrument as a metric first; alert on the rate |
| FCM delivery failure rate > 10% | Alert on `ixora_queue_job_total{queue=push,outcome=failed}` rate |
| A specific stack trace was logged | Not alertable directly — the **symptom** (HTTP 500, job failure) should be a metric |
| Error count per 5 minutes > threshold | Alert on metric derived from log-based recording rule (Phase 9+) |
| Log volume spike | Alert on log ingestion rate metric from Collector |

**Loki alert rules** are permitted in future phases (Grafana supports LogQL-based alerts) but introduce operational complexity and cost. Prefer Prometheus metric-based alerts for operational thresholds. Reserve Loki alerts for security event detection (future Phase 9+).

---

## 5. Traces vs Alerts

Traces are **sampled** (ADR-031). An alert built on trace data will miss events at sampling rates below 100%.

**Alerts must be built on metrics**, not traces.

| Pattern | Correct? | Why |
| --- | --- | --- |
| Alert when trace count for a route drops to zero | No | Sampling drops traces; metric rate is the reliable signal |
| Alert when error rate from `ixora_http_server_*` > threshold | Yes | All requests counted regardless of sampling |
| Alert when a specific span name disappears | No | Sampling artifacts; use job count metric instead |
| Use Tempo to investigate after alert fires | Yes | Correct use — traces for investigation, not trigger |

---

## 6. Golden Signals

The **Four Golden Signals** (SRE Book, Google) define what to alert on for any service.

| Signal | Definition | Ixora metric example | Alert example |
| --- | --- | --- | --- |
| **Latency** | Time to serve a request | `histogram_quantile(0.95, rate(ixora_http_server_duration_bucket[5m]))` | P95 > 2 s for 5 min |
| **Traffic** | Demand on the system | `sum(rate(ixora_http_server_duration_count[5m]))` | Usually informational (high traffic is good) |
| **Errors** | Rate of failing requests | `rate(ixora_queue_job_total{outcome="failed"}[5m])` | Failure rate > 5% for 5 min |
| **Saturation** | How full the service is | `ixora_queue_job_active`, queue depth metrics | Active jobs sustained above threshold |

At minimum, every critical service must have alerts for **Errors** and **Latency**. Traffic and Saturation alerts are context-dependent.

---

## 7. USE Method

The **USE Method** (Brendan Gregg) applies to **resources** — infrastructure, workers, queues.

| Component | Utilization | Saturation | Errors |
| --- | --- | --- | --- |
| Queue workers | Active jobs / worker capacity | Job queue depth growing | `outcome=failed` rate |
| Scheduler | Dispatch loop duration | Missed executions | Execution failures |
| HTTP API | Request rate | Response time approaching timeout | 5xx rate |
| Push queue | Active push jobs | Push queue depth | FCM failure rate |
| Collector VM | CPU/memory % | Export queue depth | `ixora_telemetry_export_failed_total` |

USE alerts prevent capacity exhaustion before it manifests as errors. They are **Warning** or **Critical** depending on urgency.

---

## 8. RED Method

The **RED Method** (Tom Wilkie) applies to **services** from the external perspective.

| Signal | Definition | Alert threshold example |
| --- | --- | --- |
| **Rate** | Requests per second | Usually not alerted (informational) |
| **Errors** | Requests that fail | HTTP 5xx > 1% sustained |
| **Duration** | Request response time | p95 > 2 s sustained |

RED is the user-facing complement to USE. Use RED for HTTP API, Push Notifications, and external provider calls. Use USE for queue workers, scheduler, and infrastructure.

---

## 9. Business Alerts

Business alerts are triggered by **product-level failure rates** that affect user experience, not infrastructure health.

| Category | Description | Example |
| --- | --- | --- |
| **Automation Failure** | Smart Home action success rate drops below threshold | `ixora.smart_home.action.total{outcome=failure}` rate > 20% |
| **Push Delivery Failure** | Push notification delivery success drops | Push delivery rate < 90% (after Phase 7B.5) |
| **Scheduler Miss** | Scheduled automations stop executing | Zero `ixora.scheduler.execution.total{outcome=dispatched}` for 10+ min |
| **Elevated Business Failure** | Cross-domain failure spike | Combined failure rate across Smart Home + Push > threshold |

Business alerts fire in production when users are **actively affected**. They require immediate response and clear ownership by the product team.

**Business alert rules:**
- Business alerts must reference D-02 Smart Home, D-03 Push Notifications, or D-01 Platform Overview.
- Business alerts must have a product owner (not just SRE).
- Business alerts trigger during business hours unless severity is Emergency.

---

## 10. Application Alerts

Application alerts are triggered by **backend service failures** that may not yet affect all users but indicate degradation.

| Category | Alert condition | Dashboard |
| --- | --- | --- |
| HTTP elevated error rate | 5xx rate > 1% for 5 minutes | D-05 HTTP API |
| HTTP high latency | p95 > 2 s for 5 minutes | D-05 HTTP API |
| Queue failure rate | Job failure rate > 5% for 5 minutes | D-04 Queue Workers |
| Queue saturation | Active jobs > threshold for 10 minutes | D-04 Queue Workers |
| Scheduler missed | Zero dispatches for unexpected interval | D-06 Scheduler |
| Push queue failure | Push job failure rate > 10% for 5 minutes | D-03 Push Notifications |

---

## 11. Infrastructure Alerts

Infrastructure alerts are triggered by **platform health conditions** — Collector, Prometheus, Loki, Tempo, VM.

| Category | Alert condition | Dashboard |
| --- | --- | --- |
| Collector export failure | `ixora_telemetry_export_failed_total` rate > 0 for 5 minutes | D-07 Infrastructure |
| Prometheus unreachable | Prometheus scrape target down | D-07 Infrastructure |
| Loki unavailable | Loki ingest failures | D-07 Infrastructure |
| Tempo unavailable | Tempo push failures | D-07 Infrastructure |
| Disk saturation | VM disk > 70% | D-07 Infrastructure |
| Grafana unavailable | Grafana health check fails | D-07 Infrastructure |

Infrastructure alerts are typically **Warning** unless they cause data loss (Critical).

---

## 12. Security Alerts

Security alerts are triggered by **anomalous operational patterns** that indicate attack or compromise.

> **Phase 8.8 scope note:** Security alert rules are out of scope. This section documents the philosophy for future phases.

| Category | Alert condition | ADR |
| --- | --- | --- |
| Authentication spike | Unusually high 401/403 rate on POST /api/login | ADR-030 |
| Token registration spike | Abnormally high push token registrations per minute | ADR-021 |
| Telemetry credential exposure | Collector receiving auth failures from unexpected sources | ADR-030 |
| Export volume spike | OTLP ingest rate 10× baseline | ADR-031 |

Security alerts must **never expose PII** in labels or annotations. Alert labels must comply with ADR-030.

---

## 13. Severity Model

Severity defines **how urgently a human must respond** and **what the business impact is**.

### 13.1 Info

| Field | Definition |
| --- | --- |
| **Purpose** | Trend notification; awareness only |
| **Operator expectation** | Review during working hours; no page required |
| **Business impact** | None currently; potential future impact |
| **Response priority** | Next working day |
| **Escalation** | None |
| **Examples** | Scheduler overlap_prevented rate rising; push retry rate above baseline; disk usage > 50% |

Info alerts do not page. They appear in Grafana UI as notifications only.

### 13.2 Warning

| Field | Definition |
| --- | --- |
| **Purpose** | Early signal of developing problem; human review required within hours |
| **Operator expectation** | Investigate within 4 hours; no emergency wake-up |
| **Business impact** | Degraded performance; no user-visible impact yet |
| **Response priority** | Within current working day |
| **Escalation** | No escalation if resolved within business hours |
| **Examples** | HTTP p95 latency between 1–2 s; push retry rate > 5%; queue failure rate 2–5%; disk usage > 70% |

### 13.3 Critical

| Field | Definition |
| --- | --- |
| **Purpose** | Active service degradation; users are affected or will be imminently |
| **Operator expectation** | Respond within 15–30 minutes; on-call paged |
| **Business impact** | Subset of users experiencing failures; core feature degraded |
| **Response priority** | Immediate (any time of day) |
| **Escalation** | To tech lead if unresolved within 30 minutes |
| **Examples** | HTTP 5xx > 1% sustained; push delivery failure rate > 10%; Smart Home action failure rate > 20%; queue worker completely stopped |

### 13.4 Emergency

| Field | Definition |
| --- | --- |
| **Purpose** | Total service failure; all users affected |
| **Operator expectation** | Respond immediately; all hands |
| **Business impact** | Complete service outage or data loss risk |
| **Response priority** | Immediate, highest priority |
| **Escalation** | Immediate escalation to tech lead + product lead |
| **Examples** | API returning 0 successful requests; Collector completely down (>15 min, data loss window); scheduler dispatching 0 jobs for >30 min; complete queue processing halt |

---

## 14. Alert States and Lifecycle

### 14.1 States

| State | Definition | Who sees it |
| --- | --- | --- |
| **Pending** | Condition met but not yet for full `for` duration | Grafana UI only; no notification |
| **Firing** | Condition met for full `for` duration; notification sent | On-call receiver |
| **Acknowledged** | Engineer confirmed receipt; actively investigating | Visible to team |
| **Silenced** | Manually suppressed for a time window | Visible with silence reason |
| **Suppressed** | Inhibited by a higher-priority alert (e.g., Collector down suppresses all downstream alerts) | Visible |
| **Resolved** | Condition no longer met; recovery notification sent | On-call receiver |
| **Expired** | Evaluation period ended; no data received | Grafana UI |

### 14.2 State transitions

```
                    condition met
                    for < for-duration
New data → Inactive ─────────────────→ Pending
                                            │
                                    for-duration met
                                            │
                                            ▼
                    condition clears ──── Firing ──→ Notification sent
                            │                            │
                            ▼                            ▼
                         Resolved               Acknowledged (engineer)
                            │                            │
                     recovery notif               continues investigation
                            │                            │
                            ▼                            ▼
                         Inactive             Resolved when condition clears

Silenced: Any state → Silenced (manual, time-bounded) → Returns to prior state
Suppressed: Firing → Suppressed (inhibition rule active) → Returns to Firing when inhibition cleared
Expired: Pending or Firing → Expired (evaluation gap) → Treated as Resolved for notifications
```

### 14.3 The `for` duration

The `for` field in an alert rule specifies how long the condition must be continuously met before firing. This is the **primary noise reduction tool**.

| Severity | Recommended `for` range | Rationale |
| --- | --- | --- |
| Info | 15–30 min | Long enough to ignore transients |
| Warning | 5–15 min | Developing problem; some urgency |
| Critical | 2–5 min | Active problem; but avoid spikes |
| Emergency | 0–2 min | Immediate; do not wait for transients |

**Never set `for: 0s` for non-emergency alerts.** Brief spikes (deploy restarts, GC pauses) will cause false alarms.

---

## 15. Alert Maturity Model

Alerting evolves from reactive to proactive. The Ixora maturity model tracks this evolution.

### Level 0 — No alerts (current state after Phase 8.7)

The platform has dashboards, metrics, logs, and traces but no automated alerting. All operational detection is reactive (engineer checks dashboards).

- **Risk:** Incidents discovered only when users complain.
- **Action:** Implement Phase 8.8 Foundation, then Phase 9 production rules.

### Level 1 — Threshold alerts (Phase 9 target)

Basic metric threshold rules on Golden Signals for critical services (HTTP, Queue, Push, Smart Home, Infrastructure).

- Error rate, latency, availability.
- Contact points provisioned (Slack/email).
- Runbooks written for every rule.

### Level 2 — Tuned alerts (Phase 10 target)

False positive rate < 5%. Alerts tuned based on production observations.

- `for` durations adjusted from real incident data.
- Inhibition rules in place (Collector down → suppress downstream).
- Mute timings for maintenance windows.
- SLO-based alerts (error budget burn rate).

### Level 3 — Predictive alerts (Phase 11+)

Trend-based alerting on gradual degradation.

- Disk growth rate extrapolated to predict full-disk.
- Memory leak detection from growing baseline.
- Queue depth trend analysis (growing despite constant traffic).

### Level 4 — Business SLO alerts (Phase 12+)

Multi-window burn rate alerts aligned to business commitments.

- Push delivery SLO: 99% success rate over 24h.
- Scheduler SLO: zero missed dispatches over 1h window.
- Burn rate multi-window: 1h + 6h burn rates.

---

## 16. Alert Fatigue

Alert fatigue is the leading cause of missed critical alerts. Engineers who receive too many alerts — especially false positives — learn to ignore them.

### 16.1 Causes

| Cause | Example | Prevention |
| --- | --- | --- |
| Too-short `for` duration | Alert fires on every deploy restart | Increase `for` to 2–5 min minimum |
| Threshold too tight | Warning at 5% failure rate when 4.8% is normal | Baseline from production; add 2× margin |
| Alerting on noise | Alert on every single retried job | Alert on rate, not single events |
| Missing inhibition | Collector down causes 20 downstream alerts | Inhibit downstream when Collector alert fires |
| Missing mute timings | Alerts fire during scheduled maintenance | Provision mute_timings.yaml |
| Under-specified runbooks | Engineer receives alert, no idea what to do | Runbook required before alert is deployed |
| No ownership | Alert fires; no one knows whose job it is | `team` label required on every alert |

### 16.2 Alert budget

Every team operates under an **alert budget** — the number of pages that can be absorbed without degrading engineering effectiveness.

| Budget | Action if exceeded |
| --- | --- |
| > 5 pages/day (all alerts) | Immediate alert review and pruning |
| > 3 pages/week for any single alert | Tune or silence the alert |
| > 0 false positives for Critical/Emergency | Tune immediately |

---

## 17. Noise Reduction

### 17.1 Deduplication

Grafana Alerting deduplicates alerts within the same alert rule. Multiple evaluations of the same firing condition produce **one** notification, not many.

Configure `group_wait` and `group_interval` on notification policies to control deduplication timing:

```yaml
group_wait: 30s       # Wait before sending first notification (allows grouping)
group_interval: 5m    # Wait between subsequent notifications for an ongoing alert
repeat_interval: 4h   # Resend if still firing and not acknowledged
```

### 17.2 Grouping

Group related alerts into a single notification:

| Strategy | When to use |
| --- | --- |
| Group by `service` | All failing queue workers fire as one notification |
| Group by `category` | All infrastructure alerts combined |
| Group by `severity` | Critical alerts grouped together |
| Group by `environment` | Staging alerts never mixed with production |

### 17.3 Inhibition rules

Inhibition prevents **cascade notifications** when a root cause alert is already firing.

| Root cause alert | Inhibited alert | Rationale |
| --- | --- | --- |
| Collector down (Emergency) | All downstream metric-based alerts | No data → false firing |
| Prometheus unavailable (Critical) | All metric-based alerts | Query fails → no data |
| Queue worker stopped (Critical) | Queue job failure rate (Warning) | Root cause already paged |
| Grafana unavailable | Dashboard availability checks | Expected consequence |

Inhibition rules are provisioned in `grafana/provisioning/alerting/` (Phase 9).

---

## 18. Escalation

Define clear escalation paths before deploying production alerts.

| Severity | Escalation path | Time before escalation |
| --- | --- | --- |
| Info | No escalation | — |
| Warning | Slack channel notification | No escalation unless unresolved 8h |
| Critical | On-call engineer | 30 min if unresolved → tech lead |
| Emergency | On-call + tech lead simultaneously | 15 min if unresolved → product lead |

---

## 19. Ownership

Every alert must have a declared owner.

| Label | Description |
| --- | --- |
| `team` | Team responsible for response and remediation |
| `service` | Service emitting the alerting metric |
| `owner` | Optional: individual primary contact |

**Rules:**
- Alerts without a `team` label must not be deployed.
- Ownership must be agreed before alert deployment, not after.
- Ownership review is part of alert rule PR review.

---

## 20. Review Cycle

Alerts are **operational contracts** and degrade in accuracy over time as the system evolves. They require a regular review cycle.

| Frequency | Activity |
| --- | --- |
| **Weekly** (on-call rotation) | Review firing alert history; flag noisy alerts |
| **Monthly** | Review false positive count; adjust thresholds |
| **Quarterly** | Full alert inventory review; remove stale alerts; update runbooks |
| **After every incident** | Review: did the right alert fire? Was it actionable? |
| **After every deploy** | Check: did the deploy cause spurious alert fires? |

---

## 21. Retirement Strategy

An alert that is no longer relevant is more dangerous than no alert — it trains engineers to ignore notifications.

| Condition | Action |
| --- | --- |
| Alert consistently false-positive | Tune threshold or increase `for`; if unfixable, retire |
| Feature the alert monitors is removed | Delete alert rule immediately |
| Metric the alert references is renamed/deprecated | Update alert rule to new name as part of metric migration |
| Alert never fires in 90 days (production) | Review: is the threshold wrong or is the system genuinely healthy? |
| Alert is superseded by a better rule | Retire old rule; document in PR commit message |

---

## 22. Documentation Strategy

Every alert rule must have a complete **runbook** before it is deployed to production.

### 22.1 Runbook minimum requirements

| Section | Content |
| --- | --- |
| **Symptoms** | What the engineer sees: alert name, dashboard, metric values |
| **Likely causes** | 3–5 ordered root causes from most to least common |
| **Validation steps** | Specific PromQL/LogQL/Tempo queries to confirm diagnosis |
| **Dashboard** | Link to relevant Grafana dashboard (always by UID) |
| **Recovery steps** | Ordered remediation procedure |
| **Rollback** | How to rollback if recovery causes regression |
| **Escalation** | Who to escalate to and when |
| **Postmortem checklist** | Questions to answer after resolution |

### 22.2 Runbook location

Runbooks live in `docs/runbooks/` (Phase 9 deliverable). They are linked from:
- Alert rule annotation: `runbook: /runbooks/<alert-name>.md`
- Dashboard panel description (investigation hint)
- Incident response checklist

---

## 23. Label Conventions

All alert rules, regardless of category or severity, must include the following labels.

### 23.1 Required labels

| Label | Description | Example values |
| --- | --- | --- |
| `environment` | Deployment environment | `staging`, `production` |
| `severity` | Alert severity | `info`, `warning`, `critical`, `emergency` |
| `service` | Service emitting the metric | `back_vibes-api`, `back_vibes-worker`, `ixora-collector` |
| `team` | Team responsible for response | `backend`, `sre`, `product` |
| `category` | Alert category | `infrastructure`, `application`, `business`, `security` |
| `dashboard_uid` | Grafana dashboard UID to navigate to | `ixora-platform`, `ixora-http`, `ixora-push` |
| `runbook` | Relative path to runbook document | `/runbooks/http-error-rate.md` |

### 23.2 Optional labels

| Label | Description | When to use |
| --- | --- | --- |
| `component` | Sub-component of a service | `queue`, `scheduler`, `http`, `push` |
| `slo` | SLO this alert contributes to | `availability`, `latency` |
| `owner` | Named primary contact | Individual engineer or team alias |

### 23.3 Forbidden labels

| Label | Why forbidden |
| --- | --- |
| `user_id` | PII + unbounded cardinality (ADR-030) |
| `email` | PII + unbounded |
| `trace_id` | Unique per request |
| `schedule_id`, `device_id` | Unbounded product IDs |
| Any label with unbounded values | Explodes Grafana alert index |

Labels on alert rules propagate to notifications. **Never allow a label value that contains user-identifying information** to appear in a Slack message, email, or PagerDuty page.

---

## 24. Annotation Conventions

Annotations provide **human-readable context** for alert notifications. They appear in notification messages and alert detail views.

### 24.1 Standard annotations

| Annotation | Description | Required |
| --- | --- | --- |
| `summary` | One-line description of the alert condition | Yes |
| `description` | Full description: what is firing, why, and immediate action | Yes |
| `dashboard` | Full Grafana URL to the relevant dashboard | Yes |
| `runbook` | Full URL or path to the runbook | Yes |
| `business_impact` | What users or business processes are affected | Yes for Critical/Emergency |
| `expected_action` | First action the on-call engineer must take | Yes for Critical/Emergency |
| `owner` | Team or individual responsible | Recommended |

### 24.2 Summary pattern

```
[severity] service: condition — value (threshold)
```

Examples:
```
[critical] back_vibes-api: HTTP 5xx error rate elevated — 2.3% (threshold: 1%)
[warning] back_vibes-worker: Push queue failure rate rising — 6.1% (threshold: 5%)
[emergency] ixora-collector: Telemetry export failing — 100% failure rate
```

---

## 25. Naming Convention

Alert names follow the pattern: **`<Category> / <Service> — <Condition>`**

### 25.1 Standard names

| Category | Service | Condition | Full name |
| --- | --- | --- | --- |
| Infrastructure | Collector | Collector Down | `Infrastructure / Collector — Collector Down` |
| Infrastructure | Prometheus | Target Missing | `Infrastructure / Prometheus — Target Missing` |
| Infrastructure | Grafana | Unavailable | `Infrastructure / Grafana — Unavailable` |
| Infrastructure | VM | Disk Saturation | `Infrastructure / VM — Disk Saturation` |
| Application | HTTP API | Elevated Error Rate | `Application / HTTP API — Elevated Error Rate` |
| Application | HTTP API | High Latency | `Application / HTTP API — High Latency` |
| Application | Queue Workers | Failure Rate | `Application / Queue Workers — Failure Rate` |
| Application | Queue Workers | Worker Saturation | `Application / Queue Workers — Worker Saturation` |
| Application | Scheduler | Missed Executions | `Application / Scheduler — Missed Executions` |
| Application | Push Queue | Delivery Failure | `Application / Push Queue — Delivery Failure` |
| Application | Push Queue | Queue Saturation | `Application / Push Queue — Queue Saturation` |
| Business | Smart Home | Provider Failure | `Business / Smart Home — Provider Failure` |
| Business | Smart Home | Elevated Failure Rate | `Business / Smart Home — Elevated Failure Rate` |
| Business | Push Notifications | Delivery Failure | `Business / Push Notifications — Delivery Failure` |
| Business | Automation | Pipeline Failure | `Business / Automation — Pipeline Failure` |

### 25.2 Naming rules

- Names are **always human-readable** — no abbreviations, no codes.
- Category is always capitalized; separated from service by ` / `.
- Condition describes the **user-visible symptom**, not the metric name.
- Do not embed metric names in alert names.
- Do not embed threshold values in alert names (thresholds change; names should not).

---

## 26. Investigation Workflow Standard

The standard investigation workflow for any alert:

```
Alert fires
    │
    ▼
1. Acknowledge the alert (prevent escalation timer)
    │
    ▼
2. Navigate to referenced dashboard (dashboard_uid annotation)
    │
    ▼
3. Confirm the condition on the dashboard
    │    ├─ Not visible on dashboard → Possible false alarm; check evaluation state
    │    └─ Visible → Continue
    ▼
4. Identify time range and affected component(s)
    │
    ▼
5. Open runbook (runbook annotation)
    │
    ▼
6. Execute validation steps (PromQL / LogQL / Tempo)
    │    ├─ Metrics: confirm failure rate / latency
    │    ├─ Logs: find error context via Loki
    │    └─ Traces: find trace for individual failing request
    ▼
7. Identify root cause
    │    ├─ Infrastructure (Collector, VM, network)
    │    ├─ Application (code bug, config, deploy regression)
    │    ├─ External (FCM, Home Assistant, DigitalOcean)
    │    └─ Data (bad input, expired tokens)
    ▼
8. Execute recovery steps per runbook
    │
    ▼
9. Verify resolution on dashboard
    │    ├─ Alert transitions to Resolved
    │    └─ Metric returns to healthy range
    ▼
10. Write incident note (even if brief)
    │
    ▼
11. If severity Critical/Emergency: trigger postmortem checklist
```

---

## 27. Relationship with other documents

| Document | Role relative to this guide |
| --- | --- |
| [ADR-028](../decisions/ADR-028-observability-platform.md) | Platform architecture — Collector as sole ingest; Grafana as visualization |
| [ADR-029](../decisions/ADR-029-telemetry-data-model.md) | Signal model — metrics, logs, traces; how they relate |
| [ADR-030](../decisions/ADR-030-observability-security-and-privacy.md) | Security — forbidden labels in alerts; no PII in notifications |
| [ADR-031](../decisions/ADR-031-retention-storage-and-cost-control.md) | Retention — alerts depend on metrics (30-day retention); traces sampled (7 days) |
| [metrics-philosophy.md](metrics-philosophy.md) | Source signals for all alerts; cardinality rules; label allowlist |
| [logs-philosophy.md](logs-philosophy.md) | Investigation tool after alert fires; Loki query patterns |
| [traces-philosophy.md](traces-philosophy.md) | Investigation tool after alert fires; Tempo drill-down |
| [telemetry-decision-guide.md](telemetry-decision-guide.md) | Deciding whether a condition warrants a metric (prerequisite for an alert) |
| [telemetry-naming-convention.md](telemetry-naming-convention.md) | Canonical metric names referenced in alert PromQL expressions |
| [telemetry-availability-policy.md](telemetry-availability-policy.md) | Best-effort export — alerts may have data gaps during Collector downtime |
| [alerting-foundation.md](../specs/observability-foundation/mvp/alerting-foundation.md) | Implementation spec — provisioning, categories, runbook standard, validation |
| [dashboard-conventions.md](../specs/observability-foundation/mvp/dashboard-conventions.md) | Every alert must reference a dashboard UID |
| [incident-response-policy.md](../operations/incident-response-policy.md) | Roles, communication, evidence collection, and postmortem for real incident response — this guide defines severity and alert model; that document defines the response process |

### Document boundaries

| Topic | Owner document |
| --- | --- |
| Alert **philosophy**: when to alert, severity, lifecycle, fatigue | **This document** |
| Alert **implementation**: provisioning files, YAML structure, check inventory | [alerting-foundation.md](../specs/observability-foundation/mvp/alerting-foundation.md) |
| Signal choice (metric vs log vs trace) | [telemetry-decision-guide.md](telemetry-decision-guide.md) |
| Metric names and label spelling | [telemetry-naming-convention.md](telemetry-naming-convention.md) |
| Dashboard UID registry | [dashboard-conventions.md](../specs/observability-foundation/mvp/dashboard-conventions.md) §1.2 |
| Individual runbooks | `docs/runbooks/<alert-name>.md` (Phase 9) |

---

## Review checklist

Before deploying any alert rule:

- [ ] Alert answers a clear operational question
- [ ] There is a metric that reliably captures the condition
- [ ] Threshold is based on observed baseline (not guessed)
- [ ] `for` duration set appropriately for severity
- [ ] Runbook exists before alert is deployed
- [ ] All required labels present (`environment`, `severity`, `service`, `team`, `category`, `dashboard_uid`, `runbook`)
- [ ] No PII or high-cardinality values in labels or annotations (ADR-030)
- [ ] Dashboard referenced by UID exists and the panel is visible
- [ ] Alert has a declared owner
- [ ] Inhibition rules considered (does Collector-down make this alert noisy?)
- [ ] Mute timing configured for any known maintenance window
- [ ] Alert reviewed by a second engineer before merge
