# Observability Playbook

**Status:** Active operational runbook  
**Scope:** Staging and production investigation using the Observability Foundation stack  
**Applies to:** On-call engineers, backend/mobile developers, infra operators

**Architecture references:** [ADR-028](../decisions/ADR-028-observability-platform.md) · [ADR-029](../decisions/ADR-029-telemetry-data-model.md) · [ADR-030](../decisions/ADR-030-observability-security-and-privacy.md) · [ADR-031](../decisions/ADR-031-retention-storage-and-cost-control.md) · [telemetry-naming-convention.md](../architecture/telemetry-naming-convention.md) · [telemetry-decision-guide.md](../architecture/telemetry-decision-guide.md) · [staging-digitalocean.md](../architecture/backend/staging-digitalocean.md) · [scheduler-smart-home-operational-checklist.md](scheduler-smart-home-operational-checklist.md)

> **Purpose:** Teach an engineer **how to investigate production problems** using dashboards, traces, logs, and product data. This is **not** architecture — it is an operational runbook. Signal **naming** is in [telemetry-naming-convention.md](../architecture/telemetry-naming-convention.md); signal **choice** is in [telemetry-decision-guide.md](../architecture/telemetry-decision-guide.md).

**Prerequisite:** Observability stack deployed (Phases 3–9). Until then, use App Platform runtime logs and [scheduler-smart-home-operational-checklist.md](scheduler-smart-home-operational-checklist.md) as fallback.

---

## 1. Purpose

When something breaks — scheduler silent, Smart Home action failed, push missing, Collector down — engineers need a **repeatable workflow**, not ad-hoc grep.

This playbook provides:

- Standard investigation flow (dashboard → trace → logs → product data)
- Per-incident checklists with expected outcomes
- Quick troubleshooting table
- Escalation and recovery steps

---

## 2. Observability workflow

```
Problem reported
    ↓
Dashboard (metrics — is there a spike or gap?)
    ↓
Trace (one failing workflow — Tempo)
    ↓
Logs (detail — Loki, filter by trace_id)
    ↓
Product / provider (DB rows, HA, FCM, App Platform)
    ↓
Resolution (fix, redeploy, scale, or escalate)
```

| Step | Tool | Question answered |
| --- | --- | --- |
| **Dashboard** | Grafana | Is the system unhealthy in aggregate? |
| **Trace** | Tempo | Which step in the workflow failed? |
| **Logs** | Loki | What error message and context? |
| **Provider** | Postgres, HA, FCM, DO console | Ground truth vs telemetry |
| **Resolution** | Runbook action | Restore service or fix root cause |

**Correlation:** Copy `trace_id` from Tempo → Loki query `{service.name="back_vibes-worker"} |= "<trace_id>"`.

**Environment:** Always filter `deployment.environment=staging` or `production` — never mix.

---

## 3. Incident: "The Scheduler didn't execute."

### Symptoms

- Schedule past `next_run_at` with no new `schedule_executions` row
- User reports automation never ran
- Dashboard shows flat `ixora.scheduler.execution.total`

### Checklist

| Step | Where | What to inspect | Expected if healthy |
| --- | --- | --- | --- |
| 1 | App Platform | Scheduler component logs: `[schedules:dispatch-loop] tick` | Tick every ~60 s |
| 2 | Grafana | **Ixora / Scheduler / Dispatch** — `ixora.scheduler.dispatch.duration`, execution counter | Recent dispatch activity |
| 3 | Loki | `{service.name="back_vibes-worker"} \|~ "dispatch-due"` | No sustained errors |
| 4 | Postgres | `SELECT id, next_run_at, enabled FROM schedules WHERE id = ?` | `enabled=true`, `next_run_at` in past |
| 5 | Postgres | `SELECT * FROM schedule_executions WHERE schedule_id = ? ORDER BY id DESC LIMIT 5` | New row after due time |
| 6 | Tempo | Trace `DispatchDueSchedulesCommand.handle` around due window | Span completes; child spans if jobs enqueued |

### Likely causes

| Cause | Evidence | Resolution |
| --- | --- | --- |
| Scheduler worker down | No tick logs | Restart scheduler component ([scheduler-smart-home-operational-checklist.md §2](scheduler-smart-home-operational-checklist.md)) |
| Schedule disabled | `enabled=false` | User/API re-enable |
| Clock / timezone bug | `next_run_at` wrong | Fix recurrence; see product logs |
| DB transaction failure | Error in dispatch logs | Fix schema/migration; check Postgres |
| Validator skipped dispatch | Log "validation failed" | Expected — not a scheduler bug |

### Expected outcome

Identify whether failure is **worker**, **data**, **validator**, or **telemetry gap**. Restore scheduler worker or fix schedule row.

---

## 4. Incident: "Smart Home action failed."

### Symptoms

- Push: `smart_home_action_failed` received
- Dashboard: `ixora.smart_home.action.total{outcome=failure}` elevated
- Execution row shows failure in product DB

### Checklist

| Step | Where | What to inspect |
| --- | --- | --- |
| 1 | Grafana | **Ixora / Smart Home / Actions** — failure rate by `action_type`, `provider` |
| 2 | Tempo | Trace `SmartHomeActionJob.handle` → child `HomeAssistantAdapter.executeAction` |
| 3 | Loki | Filter by `trace_id`; search `SmartHomeActionJob` + `device_id` |
| 4 | Postgres | `provider_connections`, `devices`, `vibe_smart_home_actions` for user |
| 5 | Home Assistant | HA logs / UI — entity state, API reachability |
| 6 | App Platform | Queue worker processing `smart-home` queue |

### Likely causes

| Cause | Resolution |
| --- | --- |
| HA unreachable / timeout | Check HA URL, TLS, `SMART_HOME_HA_TIMEOUT`; see [scheduler-smart-home-operational-checklist.md](scheduler-smart-home-operational-checklist.md) |
| Invalid token | Re-sync provider connection |
| Entity removed in HA | Re-sync devices |
| Queue worker stuck | Restart queue component |

### Expected outcome

Root cause classified: **provider**, **config**, **network**, or **job infrastructure**. User may need to re-link HA.

---

## 5. Incident: "Push notification never arrived."

### Symptoms

- Smart Home or schedule failure occurred but no push on device
- Dashboard: `ixora.push.delivery.total{outcome=failure}` or zero sends

### Checklist

| Step | Where | What to inspect |
| --- | --- | --- |
| 1 | Grafana | **Ixora / Push / Delivery** by `notification_type`, `outcome` |
| 2 | Tempo | `PushNotificationJob.handle` → `FcmPushProvider.send` |
| 3 | Loki | `PushNotificationJob`, FCM errors, invalid token messages |
| 4 | Postgres | `device_push_tokens` for user — active token? |
| 5 | App Platform | Queue worker includes `push` queue |
| 6 | Firebase console | Delivery stats, credential errors |
| 7 | Mobile | FCM token registered; app notification permission |

### Likely causes

| Cause | Resolution |
| --- | --- |
| `PUSH_PROVIDER=noop` | Set `fcm` in staging |
| Missing/expired FCM token | Re-register on app launch |
| Push job not processed | Queue worker down or missing `push` queue |
| FCM credential misconfigured | Fix `FIREBASE_*` secrets |
| Success path — no push by design | [ADR-024](../decisions/ADR-024-automation-notifications-and-observability.md) — failures only |

### Expected outcome

Determine if failure is **token**, **FCM**, **queue**, or **expected silence** (success path).

---

## 6. Incident: "Collector stopped receiving telemetry."

### Symptoms

- All Grafana product dashboards flat
- `ixora.telemetry.export.failed.total` rising in apps (when instrumented)
- Collector health endpoint fails

### Checklist

| Step | Where | What to inspect |
| --- | --- | --- |
| 1 | Grafana | **Ixora / Observability / Collector Health** |
| 2 | VM / DO | Collector process running, disk space |
| 3 | Collector logs | OTLP receiver errors, processor failures |
| 4 | App Platform | API/worker env `OTEL_EXPORTER_OTLP_ENDPOINT` correct |
| 5 | Firewall | OTLP port open from App Platform egress |
| 6 | Apps | Business still healthy? (telemetry is best-effort — [ADR-028](../decisions/ADR-028-observability-platform.md)) |

### Expected outcome

Collector restarted or network fixed. **Apps must remain healthy** when Collector is down.

---

## 7. Incident: "Prometheus has no metrics."

### Checklist

| Step | Action |
| --- | --- |
| 1 | Confirm Collector → Prometheus exporter configured |
| 2 | `up{job="prometheus"}` and `up{job="otel-collector"}` in Prometheus UI |
| 3 | Collector logs — export errors to Prometheus |
| 4 | Retention / disk — Prometheus TSDB path writable |
| 5 | Grafana datasource points to correct Prometheus URL |

### Expected outcome

Metrics flowing; dashboards populate after scrape interval (~15–60 s).

---

## 8. Incident: "Loki has no logs."

### Checklist

| Step | Action |
| --- | --- |
| 1 | Collector → Loki exporter enabled |
| 2 | Loki ingester healthy; ring status OK |
| 3 | Query Loki directly: `{service_name="back_vibes-api"}` (label names may vary by pipeline) |
| 4 | App logs still in App Platform runtime? — confirms app logging works |
| 5 | Check ADR-031 retention — logs older than 14 days expired |

### Expected outcome

Log pipeline restored; correlate with `trace_id` in Explore.

---

## 9. Incident: "Tempo has no traces."

### Checklist

| Step | Action |
| --- | --- |
| 1 | Collector → Tempo exporter; sampling not 0% |
| 2 | Search Tempo by known `trace_id` from Loki |
| 3 | Verify apps export traces (Phase 7/8 complete) |
| 4 | Head sampling — trace may be dropped ([ADR-031](../decisions/ADR-031-retention-storage-and-cost-control.md)) |
| 5 | Retention — traces older than 7 days gone |

### Expected outcome

Traces visible for recent instrumented requests; sampling explains gaps.

---

## 10. Incident: "Grafana dashboard is empty."

### Checklist

| Step | Action |
| --- | --- |
| 1 | Time range — expand to Last 24 h |
| 2 | `deployment.environment` variable matches staging/production |
| 3 | Datasource health: Prometheus, Loki, Tempo |
| 4 | Metric names match [telemetry-naming-convention.md](../architecture/telemetry-naming-convention.md) |
| 5 | No data yet — SDK phases 7/8 incomplete? |

### Expected outcome

Dashboard variables and datasources corrected; or acknowledged pre-instrumentation state.

---

## 11. Incident: "High CPU"

### Checklist

| Step | Where | Action |
| --- | --- | --- |
| 1 | DO monitoring / VM | Identify component: Collector, Prometheus, Loki, Tempo, Grafana |
| 2 | Prometheus | Scrape interval, cardinality explosion |
| 3 | Collector | Batch size, too many processors |
| 4 | Loki | Query load in Grafana |
| 5 | Apps | Abnormal trace/log export volume |

### Resolution

Reduce scrape frequency; fix high-cardinality metrics; increase VM size per ADR-031 review; enable sampling.

---

## 12. Incident: "Disk almost full"

### Checklist

| Step | Action |
| --- | --- |
| 1 | `df -h` on observability VM |
| 2 | Prometheus TSDB, Loki chunks, Tempo blocks — largest dirs |
| 3 | Verify retention flags match [ADR-031](../decisions/ADR-031-retention-storage-and-cost-control.md) |
| 4 | Compaction running? |
| 5 | Emergency: shorten retention temporarily — document deviation |

### Resolution

Free space via retention enforcement; expand disk; delete orphaned data only with runbook approval.

---

## 13. Incident: "Too many time series"

### Symptoms

- Prometheus slow; memory high
- `prometheus_tsdb_head_series` elevated

### Checklist

| Step | Action |
| --- | --- |
| 1 | Find top labels: `topk(20, count by (__name__)({__name__=~"ixora.*"}))` |
| 2 | Inspect forbidden labels ([telemetry-naming-convention.md §8](../architecture/telemetry-naming-convention.md)) |
| 3 | Collector label drop processor |
| 4 | Fix app instrumentation per [telemetry-decision-guide.md](../architecture/telemetry-decision-guide.md) |

### Resolution

Remove high-cardinality labels at source; redeploy apps; restart Prometheus if needed.

---

## 14. Incident: "Mobile telemetry missing"

### Checklist

| Step | Action |
| --- | --- |
| 1 | Confirm Phase 8 SDK shipped in staging APK |
| 2 | `OTEL_EXPORTER_OTLP_ENDPOINT` in mobile build config |
| 3 | Tempo: `service.name="front_vibes-android"` |
| 4 | Sampling — mobile heavily sampled |
| 5 | Network — device reaches Collector URL |
| 6 | [mobile-e2e-testing.md](../testing/mobile-e2e-testing.md) Phase 11.5 validation |

### Expected outcome

Mobile traces appear for sampled sessions; gaps expected by design.

---

## 15. Quick troubleshooting table

| Symptom | Likely cause | First inspect | Second inspect | Resolution |
| --- | --- | --- | --- | --- |
| Scheduler silent | Worker down | App Platform scheduler logs | Postgres `schedules` | Restart worker |
| SH action fails | HA unreachable | Tempo provider span | HA logs / URL | Fix HA connectivity |
| No push | noop provider or queue | `PUSH_PROVIDER` env | Push queue worker | Enable FCM; fix queue |
| Flat dashboards | Collector down | Collector health | App OTLP endpoint | Restart Collector |
| No metrics | Prometheus scrape | `up` metric | Collector export | Fix exporter wiring |
| No logs | Loki pipeline | Loki health | Collector logs exporter | Fix Loki ingest |
| No traces | Sampling / SDK | Tempo ingest | App trace export | Fix SDK / sampling |
| Empty Grafana panel | Wrong env variable | Dashboard variables | Datasource test | Fix template vars |
| High CPU | Cardinality / scrape | Prometheus targets | Top metric series | Drop bad labels |
| Disk full | Retention | `df -h` | TSDB/Loki size | Enforce retention |
| Time series explosion | ID as label | Top ixora metrics | App PR diff | Fix instrumentation |
| Mobile gaps | Sampling | APK version | OTLP endpoint | Expected / fix config |

---

## 16. Escalation checklist

Escalate when:

- [ ] Business impact confirmed (users cannot use automations, API down)
- [ ] Root cause not found within 30 minutes using this playbook
- [ ] Data loss suspected (Postgres, not telemetry)
- [ ] Security incident (PII in logs/traces — [ADR-030](../decisions/ADR-030-observability-security-and-privacy.md))
- [ ] Observability VM unrecoverable without rebuild
- [ ] Production environment affected (requires explicit approval for prod observability changes)

**Include in escalation:** environment, time range, `trace_id` samples, dashboard screenshots, relevant log lines (redacted).

---

## 17. Recovery checklist

After incident resolution:

- [ ] Confirm dashboards show normal rates
- [ ] Spot-check Tempo trace for fixed workflow
- [ ] Verify Loki logs include `trace_id` on instrumented paths
- [ ] Document root cause in incident notes
- [ ] If instrumentation bug — fix per [telemetry-decision-guide.md](../architecture/telemetry-decision-guide.md)
- [ ] If infra — update Phase 10 operational checklist when published
- [ ] No secrets pasted in tickets or Slack

---

## 18. Related documents

| Document | Use when |
| --- | --- |
| [telemetry-decision-guide.md](../architecture/telemetry-decision-guide.md) | Fixing bad instrumentation |
| [telemetry-naming-convention.md](../architecture/telemetry-naming-convention.md) | Metric/log/query naming |
| [scheduler-smart-home-operational-checklist.md](scheduler-smart-home-operational-checklist.md) | Product ops without full observability stack |
| [asynchronous-orchestration.md](../architecture/asynchronous-orchestration.md) | Understanding expected span hierarchy |
| [notification-architecture.md](../architecture/notification-architecture.md) | Push event types and failure policy |
| [observability-foundation/mvp/spec.md](../specs/observability-foundation/mvp/spec.md) | MVP scope and acceptance criteria |
| [observability-foundation/mvp/plan.md](../specs/observability-foundation/mvp/plan.md) | Phase dependencies |
| [staging-digitalocean.md](../architecture/backend/staging-digitalocean.md) | App Platform components and URLs |
