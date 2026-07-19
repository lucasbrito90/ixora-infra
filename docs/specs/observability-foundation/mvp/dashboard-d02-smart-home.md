# Dashboard D-02 — Smart Home Business Dashboard — Phase 8.4 (`ixora-infra`)

**Status:** Complete  
**Repo:** `ixora-infra`  
**Feature ID:** `observability-foundation/mvp`  
**Phase:** 8.4  
**Dashboard UID:** `ixora-smart-home`  
**Folder:** Business  
**Datasource:** `ixora-prometheus`  
**Refresh:** 1 minute  
**Default Time Range:** Last 1 hour  
**Prerequisite:** [dashboard-conventions.md](dashboard-conventions.md) (Phase 8.3) · [dashboard-requirements.md](dashboard-requirements.md) (Phase 8.0) · [backend-smart-home-business-metrics.md](../business-telemetry/backend-smart-home-business-metrics.md) (Phase 7B.4.6) · [backend-business-failure-semantics.md](../business-telemetry/backend-business-failure-semantics.md) (Phase 7B.4.5)

---

## 1. Purpose

D-02 is the first Business dashboard for the Ixora Observability Platform. It answers the question:

> **"Is the Smart Home automation pipeline healthy? Are actions succeeding? Are dispatches reaching the queue? Are providers responding?"**

Unlike the Application dashboards (D-04–D-06), which monitor generic runtime machinery, D-02 monitors **business outcomes** — the results of real user automations executing against the Home Assistant provider. It is scoped to the Smart Home domain and provides product-level visibility for engineers and on-call responders investigating a degraded automation experience.

---

## 2. Architecture Review

### 2.1 Documents read

| Document | Contribution |
| --- | --- |
| [backend-smart-home-business-metrics.md](../business-telemetry/backend-smart-home-business-metrics.md) | Phase 7B.4.6 — source of truth for all Smart Home metric names, label sets, outcome vocabularies, and cardinality analysis. Every metric used in this dashboard was implemented in this phase. |
| [backend-business-failure-semantics.md](../business-telemetry/backend-business-failure-semantics.md) | Phase 7B.4.5 — authoritative failure taxonomy: Business/Infrastructure classification per outcome, the Queue/Business orthogonality finding (§8.3) reflected in panel 501's description, the `unsupported` ≠ `failure` distinction documented in panels 102/303/303. |
| [backend-smart-home-dispatch-boundary.md](../business-telemetry/backend-smart-home-dispatch-boundary.md) | Phase 7B.4.2 — confirms `entry_point` labels (manual/scheduled/future) and that the Dispatch counter counts *actions* (not dispatch calls) except for `outcome=error`. |
| [backend-smart-home-action-execution.md](../business-telemetry/backend-smart-home-action-execution.md) | Phase 7B.4.3 — confirms `outcome` labels (success/failure/unsupported/unknown) and `provider` labels (home_assistant/future). |
| [backend-smart-home-provider-boundary.md](../business-telemetry/backend-smart-home-provider-boundary.md) | Phase 7B.4.4 — confirms no provider-level metric exists (rejected as 1:1 duplication). This dashboard therefore has no `ixora_smart_home_provider_total` panels. |
| [dashboard-conventions.md](dashboard-conventions.md) | Panel ID ranges, datasource convention, variable convention, refresh/time range defaults, JSON standards. |
| [dashboard-requirements.md](dashboard-requirements.md) | Phase 8.0 — original panel inventory for D-02; adjusted per implementation findings below. |

### 2.2 Implementation files verified directly

| Class | Finding |
| --- | --- |
| `SmartHomeDispatchTelemetry.php` | Metric: `ixora.smart_home.dispatch.total` (Counter). Labels: `environment`, `service_name`, `entry_point` (manual/scheduled/future), `outcome` (dispatched/skipped/error). Unit: `{action}`. Counting unit: one action (not one dispatch call) for dispatched/skipped outcomes; exactly 1 for error outcome. |
| `SmartHomeActionTelemetry.php` | Metrics: `ixora.smart_home.action.total` (Counter) + `ixora.smart_home.action.duration` (Histogram, unit: ms). Labels: `environment`, `service_name`, `outcome` (success/failure/unsupported/unknown), `provider` (home_assistant/future). |
| `SmartHomeProviderTelemetry.php` | **No metrics**. The Provider-level metric was rejected in Phase 7B.4.6 (§3.3) as a 1:1 duplication of the Action counter in today's single-provider-per-attempt pipeline. No `ixora_smart_home_provider_*` panels exist in this dashboard. |
| `SmartHomeActionOutcome.php` | Confirmed outcome values: `success`, `failure`, `unsupported`, `unknown`. |
| `SmartHomeActionProvider.php` | Confirmed provider values: `home_assistant`, `future`. |
| `SmartHomeDispatchEntryPoint.php` | Confirmed entry_point values: `manual`, `scheduled`, `future`. |

---

## 3. Metric Verification

**Every metric used in this dashboard was verified directly against the implementation before any panel was designed.**

| Prometheus metric | Source class | Labels verified | Notes |
| --- | --- | --- | --- |
| `ixora_smart_home_dispatch_total` | `SmartHomeDispatchTelemetry` | `environment`, `service_name`, `entry_point`, `outcome` | Outcomes: `dispatched`/`skipped`/`error`. Dispatched/skipped increment by action count; error increments by 1. |
| `ixora_smart_home_action_total` | `SmartHomeActionTelemetry` | `environment`, `service_name`, `outcome`, `provider` | Outcomes: `success`/`failure`/`unsupported`/`unknown`. |
| `ixora_smart_home_action_duration_bucket` | `SmartHomeActionTelemetry` | `environment`, `service_name`, `outcome`, `provider`, `le` | Prometheus histogram suffix. Unit: ms. |
| `ixora_queue_job_total` | `QueueExecutionTelemetry` | `environment`, `service_name`, `queue`, `connection`, `job_name`, `outcome` | Used in panel 501 with `job_name=~".*SmartHomeAction.*"` filter. Cross-reference only; not a primary Smart Home metric. |

**Metrics NOT present in this dashboard (documented explicitly):**

| Metric | Why absent |
| --- | --- |
| `ixora_smart_home_provider_total` | Rejected in Phase 7B.4.6 §3.3 — 1:1 duplication with `ixora_smart_home_action_total`. |
| `ixora_smart_home_provider_duration` | Never implemented — no Provider-level metrics exist in `SmartHomeProviderTelemetry`. |
| `action_type` label | Deliberately omitted in Phase 7B.4.6 (§3.2 scope decision); adding it requires a separate phase review. |
| `device_type` label | Does not exist in any Smart Home metric. |

---

## 4. Business Semantics

### 4.1 Outcome taxonomy (per Phase 7B.4.5)

| Outcome | What it means | Span status | Dashboard interpretation |
| --- | --- | --- | --- |
| `success` | Provider accepted the command (2xx) | OK | Success rate numerator |
| `failure` | Provider rejected (non-2xx) OR transport error (ConnectionException) | OK | Failure rate numerator. Cannot be split further at the metric layer — requires Tempo drill-down. |
| `unsupported` | `action_type` has no mapping in the provider's ACTION_SERVICE_MAP | OK | Product gap, not an infrastructure failure. A non-zero rate = users have actions the current MVP cannot execute. |
| `unknown` | Telemetry classifier degradation (fail-open) | ERROR | Should always be 0. Non-zero = telemetry bug. |

### 4.2 Queue/Business orthogonality (Phase 7B.4.5 §8.3)

**Critical:** `ixora_queue_job_total{outcome="success"}` for `SmartHomeActionJob` does **not** indicate a successful Smart Home action. `SmartHomeActionJob::handle()` swallows every exception — the queue always reports `success` unless the job process itself crashes. Dashboard panel 501 illustrates this explicitly.

### 4.3 Dispatch counting semantics

`ixora_smart_home_dispatch_total` counts **actions**, not dispatch calls:
- `outcome=dispatched`: number of actions enqueued per dispatch call
- `outcome=skipped`: number of actions skipped (device relation null at enqueue time — expected, not an error)
- `outcome=error`: exactly 1 (the dispatch call itself threw)

This means "dispatch rate" panels show action-throughput-at-enqueue, not call-rate.

---

## 5. Panel Inventory

### Section 1 — Business Health (Row ID: 1, Panel IDs: 100–104)

| ID | Title | Type | Query summary |
| --- | --- | --- | --- |
| 100 | Action Success Rate | stat | `success / total` — green > 0.95, yellow > 0.80, red below. |
| 101 | Action Failure Rate | stat | `(failure + unknown) / total` — green < 0.05, red above 0.15. |
| 102 | Unsupported Action Rate | stat | `unsupported / total` — business gap indicator, not failure. |
| 103 | Action Execution Rate | stat | `sum rate(action_total)` — ops/s. |
| 104 | Business Health Over Time | timeseries | success rate + failure rate on same time axis. |

### Section 2 — Business Throughput (Row ID: 2, Panel IDs: 200–203)

| ID | Title | Type | Query summary |
| --- | --- | --- | --- |
| 200 | Dispatch Rate by Entry Point | timeseries | `rate(dispatch_total)` by `entry_point` — manual vs scheduled. |
| 201 | Dispatched vs Skipped Actions | timeseries | `rate(dispatch_total{outcome=~"dispatched|skipped"})` by outcome. |
| 202 | Action Rate by Provider | timeseries | `rate(action_total{provider=~"$provider"})` by provider. |
| 203 | Action Rate by Outcome | timeseries | `rate(action_total{provider=~"$provider"})` by outcome — all four values. |

### Section 3 — Failures (Row ID: 3, Panel IDs: 300–303)

| ID | Title | Type | Query summary |
| --- | --- | --- | --- |
| 300 | Failed Actions Rate (by Provider) | timeseries | `rate(action_total{outcome="failure"})` by provider + `unknown` series. |
| 301 | Dispatch Errors (by Entry Point) | timeseries | `rate(dispatch_total{outcome="error"})` by entry_point. |
| 302 | Failure Rate by Provider | timeseries | `rate(failure) / rate(total)` by provider — percentage. |
| 303 | Unsupported Actions by Provider | timeseries | `rate(action_total{outcome="unsupported"})` by provider. |

### Section 4 — Performance (Row ID: 4, Panel IDs: 400–403)

| ID | Title | Type | Query summary |
| --- | --- | --- | --- |
| 400 | Action Latency Percentiles (p50/p95/p99) | timeseries | `histogram_quantile(0.50/0.95/0.99, rate(duration_bucket))` aggregate. |
| 401 | P95 Latency by Provider | timeseries | `histogram_quantile(0.95, sum by(le, provider))` — isolates provider latency. |
| 402 | P95 Latency by Outcome | timeseries | `histogram_quantile(0.95, sum by(le, outcome))` — compares success vs failure latency. |
| 403 | Action Duration Heatmap | heatmap | `rate(duration_bucket)` as heatmap — distribution visualization. |

### Section 5 — Business Relationships (Row ID: 5, Panel IDs: 500–503)

| ID | Title | Type | Query summary |
| --- | --- | --- | --- |
| 500 | Dispatch Flow — Scheduled vs Manual | timeseries | `rate(dispatch_total)` by `entry_point` — links to D-06 (scheduled), D-05 (manual). |
| 501 | Queue Workers → Smart Home (Orthogonality) | timeseries | `rate(queue_job_total{job_name=~".*SmartHomeAction.*"})` alongside `rate(action_total)` — illustrates Phase 7B.4.5 §8.3. |
| 502 | Provider Distribution | stat | `increase(action_total[$__range])` by provider — volume in time window. |
| 503 | Business Pipeline Summary | stat | `increase(action_total[$__range])` by outcome — all four outcomes in time window. |

**Total:** 5 row panels + 18 content panels = **23 panels**

---

## 6. Variables

| Variable | Type | Query | Default | Purpose |
| --- | --- | --- | --- | --- |
| `$environment` | custom | `development,staging,production` | `staging` | Mandatory — applied to every panel query. |
| `$provider` | query | `label_values(ixora_smart_home_action_total{environment="$environment"}, provider)` | All | Optional filter — isolates metrics to a specific provider. `includeAll=true`. |

Variables NOT implemented (reasons documented):

| Variable | Why absent |
| --- | --- |
| `$device_type` | No `device_type` label exists on any Smart Home metric (not implemented in Phase 7B.4.6). |
| `$action_type` | No `action_type` label exists (deliberately deferred in Phase 7B.4.6 §3.2). |
| `$entry_point` | Low value — entry_point has only 2 active values (manual, scheduled); all panels already break down by entry_point where relevant. |

---

## 7. Navigation

Dashboard-level navigation links (all with `keepTime: true`):

| Link | Target | Rationale |
| --- | --- | --- |
| D-04 Queue Workers | `/d/ixora-queue` | Smart Home actions execute as queue jobs — D-04 shows queue depth and job latency. |
| D-05 HTTP API | `/d/ixora-http` | `entry_point=manual` dispatches originate from the HTTP API — D-05 shows the request that triggered them. |
| D-06 Scheduler | `/d/ixora-scheduler` | `entry_point=scheduled` dispatches originate from `DispatchDueSchedulesCommand` — D-06 shows scheduler event health. |
| D-07 Infrastructure | `/d/ixora-collector` | Platform health baseline — verify Collector/Prometheus are healthy before concluding a metric drop is real. |

Panel-level drill-down links:

| Panel | Drill-down target | When to use |
| --- | --- | --- |
| 100 (Action Success Rate) | Tempo explore | Find traces with `smart_home.action` + `outcome=failure` for a failing action. |
| 300 (Failed Actions Rate) | Tempo explore | Drill from failure rate spike into the specific trace. |
| 500 (Dispatch Flow) | D-06 (scheduled), D-05 (manual) | Follow the entry point upstream. |
| 501 (Queue Orthogonality) | D-04 Queue Workers | Check queue depth and job latency when action outcomes diverge from queue outcomes. |

---

## 8. Cross-Signal Drill-down Workflow

Business dashboards are **metric-based only** (per dashboard-conventions.md §12). Tempo and Loki are used for investigation, never as primary panel datasources.

**Recommended investigation workflow for a Smart Home failure incident:**

```
1. D-02 panel 101 (Failure Rate) spikes → note time window + provider
2. Drill: panel 300 (by provider) — isolate provider-specific failure
3. Navigate to Tempo (panel 300 link or Explore):
   - Filter: service.name=back_vibes-worker, span.name=smart_home.action
   - Filter: ixora.action.outcome=failure (or unsupported)
   - Find affected trace_id
4. In Tempo trace:
   - smart_home.action span → smart_home.provider span → Guzzle CLIENT span
   - CLIENT span: http.response.status_code (P2) or recorded exception (P3)
5. Navigate to Loki:
   - Filter: trace_id=<from Tempo> OR job=laravel-worker + outcome=failure
   - Find SmartHomeActionJob warning log for provider context
6. If failure is infrastructure-adjacent (P3 transport):
   - Check D-07 Infrastructure for Collector/network health
```

**Limitation:** `failure` conflates provider rejection (P2: non-2xx) and transport failure (P3: ConnectionException). The distinction requires Tempo drill-down — the metric layer cannot separate them (Phase 7B.4.5 §5).

---

## 9. Security Review

| Prohibited category | Present in D-02 panels? | Evidence |
| --- | --- | --- |
| PII (user IDs, names, emails) | No | All queries aggregate over bounded label sets (environment, provider, outcome, entry_point). No user-identifying labels exist on any Smart Home metric (confirmed: Phase 7B.4.6 §7, "label set for both metrics is environment, service_name, entry_point, outcome, provider — none is an identifier"). |
| Device identifiers | No | No `device_id`, `entity_id`, or `provider_device_id` label exists on any metric. (`ixora.provider.device_domain` is a span attribute on traces, not a metric label.) |
| Credentials, tokens | No | No query touches HTTP headers, credentials, or request/response bodies. |
| Payloads | No | No payload data is exposed. All values are counters/histograms of discrete, bounded outcomes. |
| IDs in labels | No | Metric labels are closed enums: `outcome`, `provider`, `entry_point`, `service_name`, `environment` — all reviewed and bounded. |

Security review: **PASS**

---

## 10. Known Limitations

| # | Limitation | Impact | Resolution |
| --- | --- | --- | --- |
| KL-1 | `failure` outcome conflates P2 (provider rejection) and P3 (transport error, ConnectionException). | Cannot distinguish "Home Assistant returned 4xx" from "Home Assistant was unreachable" at the metric layer. | Requires Tempo drill-down: smart_home.provider span → Guzzle CLIENT span. Documented in panel 300 description. |
| KL-2 | No `action_type` label on `ixora_smart_home_action_total`. | Cannot break down failures by action type (e.g., "turn_off failing more than turn_on"). | Deferred in Phase 7B.4.6 §3.2. Requires a separate metric label addition phase. Tempo provides per-type visibility via the `UnsupportedSmartHomeActionException` message. |
| KL-3 | J1–J3 guard-clause skips (action-not-found, device-missing, connection-missing) are not visible in any metric. | Lost actions before the `smart_home.action` boundary are invisible at the metric layer. | Deferred in Phase 7B.4.6 §3.4. Visible in Loki (SmartHomeActionJob warning logs) and counted indirectly via the dispatch `skipped` outcome for J1-type races at enqueue time. |
| KL-4 | Grafana 11.3 auto-generates folder UIDs. | Business folder UID is not stable across data volume recreations. | Validated by folder **name** ("Business"), not UID. Known limitation from Phase 8.2. |
| KL-5 | `ixora_queue_job_total{job_name=~".*SmartHomeAction.*"}` filter (panel 501) depends on the job class name as registered by Laravel Queue. | If the job is renamed or namespace changes, the filter breaks silently. | Documented in panel 501 description. Filter is `.*SmartHomeAction.*` (partial match) to tolerate namespace variation. |

---

## 11. Files Created

| File | Description |
| --- | --- |
| `collector/grafana/provisioning/dashboards/business/d02-smart-home.json` | D-02 Smart Home Business Dashboard JSON (23 panels: 5 rows + 18 content panels). |
| `docs/specs/observability-foundation/mvp/dashboard-d02-smart-home.md` | This document. |

## 12. Files Modified

| File | Change |
| --- | --- |
| `collector/grafana/validate.sh` | Updated header; added checks 13–16 for D-02. Total checks: 33/33 PASS (idempotent). |
| `docs/specs/observability-foundation/mvp/tasks.md` | Phase 8.4 marked complete. |
| `docs/specs/observability-foundation/mvp/plan.md` | Phase 8.4 section added. |
| `docs/README.md` | Observability row + doc list updated with Phase 8.4 entries. |

---

## 13. Related Documents

| Document | Relationship |
| --- | --- |
| [backend-smart-home-business-metrics.md](../business-telemetry/backend-smart-home-business-metrics.md) | Phase 7B.4.6 — the authoritative metric design record for every metric in this dashboard. |
| [backend-business-failure-semantics.md](../business-telemetry/backend-business-failure-semantics.md) | Phase 7B.4.5 — failure taxonomy, Queue/Business orthogonality (§8.3), outcome ownership (§7). |
| [backend-business-telemetry-validation.md](../business-telemetry/backend-business-telemetry-validation.md) | Phase 7B.4.8 — platform-wide architecture validation confirming Smart Home telemetry is production-ready. |
| [dashboard-conventions.md](dashboard-conventions.md) | Phase 8.3 — permanent Grafana standards this dashboard complies with. |
| [dashboard-requirements.md](dashboard-requirements.md) | Phase 8.0 — original panel inventory (adjusted based on implementation findings). |
| [dashboard-d07-infrastructure.md](dashboard-d07-infrastructure.md) | Phase 8.2 — D-07, linked for infrastructure health correlation. |
| [dashboard-d04-queue.md](dashboard-d04-queue.md) | Phase 8.3 — D-04, linked in panel 501 (Queue Orthogonality). |
| [dashboard-d06-scheduler.md](dashboard-d06-scheduler.md) | Phase 8.3 — D-06, linked in panel 500 (Scheduled dispatch entry point). |
| [dashboard-d05-http.md](dashboard-d05-http.md) | Phase 8.3 — D-05, linked in panel 500 (Manual dispatch entry point). |
