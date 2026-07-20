# Dashboard D-03 — Push Notifications

> **Phase:** 8.7 — D-03 Push Notifications Dashboard
> **Status:** Complete
> **UID:** `ixora-push`
> **Folder:** Business
> **Refresh:** 1 minute
> **Validation:** 57/57 PASS

---

## 1. Purpose

D-03 monitors the Push Notification delivery pipeline for the Ixora platform. It answers whether push notifications are reaching users and whether the delivery pipeline is healthy.

D-03 focuses on the **queue layer** — it surfaces `PushNotificationJob` execution metrics on the `push` queue (`ixora_queue_job_total{queue="push"}`). This is the available signal level until Phase 7B.5 ships `ixora.push.delivery.total`.

### 1.1 Audience

| Audience | Use case |
| --- | --- |
| On-call engineer | "Are push notifications delivering? What is the failure rate?" |
| Product team | "How many notifications were sent in the last hour?" |
| SRE | "Is the push queue healthy? Is there FCM latency?" |

### 1.2 Architecture context — Phase 7B.5 not yet complete

Phase 8.7 was implemented under the assumption that Phase 7B.5 (Push Notifications Telemetry — `ixora.push.delivery.total`) was complete. **Architecture review found this assumption to be false.** No `PushDeliveryTelemetry` class exists in `back_vibes/app/Telemetry/` and the `PushNotificationJob` emits only logs, not metrics.

**Resolution:** D-03 is built on top of the existing queue telemetry layer:
- `ixora_queue_job_total{queue="push"}` — throughput and outcome classification
- `ixora_queue_job_duration_bucket{queue="push"}` — latency percentiles
- `ixora_queue_job_active{queue="push"}` — active job concurrency

This provides **real, meaningful observability** for the push delivery pipeline. The dashboard is production-ready at the queue layer. Per-notification-type and per-provider breakdowns become available when Phase 7B.5 ships.

---

## 2. Business Questions Answered

| Question | Panel | Signal |
| --- | --- | --- |
| Are push notifications being delivered? | Push Success Rate | `ixora_queue_job_total{queue=push, outcome=success}` / total |
| What is the delivery failure rate? | Push Failure Rate | `outcome=failed` / total |
| How many notifications are sent per second? | Push Delivery Rate | `rate(ixora_queue_job_total{queue=push}[5m])` |
| Are there jobs waiting to be processed? | Active Push Jobs | `ixora_queue_job_active{queue=push}` |
| How long does delivery take? | P50/P95/P99 | `histogram_quantile(ixora_queue_job_duration_bucket{queue=push})` |
| Are jobs being retried? | Retry Rate | `outcome=~retried|released` / total |
| Are jobs timing out? | Timed-Out Rate | `outcome=timed_out` / total |
| Is FCM responding slowly? | Latency Percentiles over Time | P50/P95/P99 trend |
| How many failed permanently this window? | Delivery Pipeline Summary | `increase(outcome=failed[$__range])` |

---

## 3. Metrics Used

| Metric | Type | Filter Applied | Labels Used |
| --- | --- | --- | --- |
| `ixora_queue_job_total` | Counter | `queue="push"` | `environment`, `queue`, `outcome` |
| `ixora_queue_job_duration_bucket` | Histogram | `queue="push"` | `environment`, `queue`, `le` |
| `ixora_queue_job_duration_sum` | Histogram sum | `queue="push"` | `environment`, `queue` |
| `ixora_queue_job_duration_count` | Histogram count | `queue="push"` | `environment`, `queue` |
| `ixora_queue_job_active` | Gauge | `queue="push"` | `environment`, `queue` |

**Metric source:** `QueueExecutionTelemetry.php` (Phase 7B.2). The push queue name `"push"` is configured via `config/push_notifications.php`.

**Metrics NOT yet available (Phase 7B.5):**
- `ixora_push_delivery_total{notification_type, outcome}` — per-notification-type delivery metric
- Push delivery spans (`push.delivery` span name)

---

## 4. Panel Inventory

### Section 1: Platform Health (row id=1)

| ID | Title | Type | Metric | Thresholds |
| --- | --- | --- | --- | --- |
| 100 | Push Delivery Rate | Stat | `rate(ixora_queue_job_total{queue=push}[5m])` | Blue (rate) |
| 101 | Push Success Rate | Stat | `outcome=success` / total | < 80% red, < 95% yellow, ≥ 95% green |
| 102 | Push Failure Rate | Stat | `outcome=failed` / total | < 5% green, < 10% yellow, ≥ 10% red |
| 103 | Active Push Jobs | Stat | `ixora_queue_job_active{queue=push}` | < 5 green, < 20 yellow, ≥ 20 red |
| 104 | Avg Delivery Latency | Stat | `duration_sum/duration_count` | < 2000 ms green, < 5000 ms yellow, ≥ 5000 ms red |
| 105 | Retry Rate | Stat | `outcome=~retried|released` / total | < 3% green, < 10% yellow, ≥ 10% red |
| 106 | Timed-Out Rate | Stat | `outcome=timed_out` / total | 0 green, < 1% yellow, ≥ 5% red |

### Section 2: Business Throughput (row id=2)

| ID | Title | Type | Metric |
| --- | --- | --- | --- |
| 200 | Delivery Volume over Time | Time series | Total delivery rate over time |
| 201 | Push Jobs by Outcome | Time series (stacked) | Rate by outcome |
| 202 | Delivery Pipeline Summary | Stat | `increase(total[$__range])` by outcome |

### Section 3: Failures (row id=3)

| ID | Title | Type | Metric |
| --- | --- | --- | --- |
| 300 | Failure Rate by Outcome | Bar gauge | Failure rate per non-success outcome |
| 301 | Permanent Failures over Time | Time series | `outcome=failed` rate |
| 302 | Transient Failures over Time | Time series | `outcome=~retried|released` rate |
| 303 | Timed-Out Jobs over Time | Time series | `outcome=timed_out` rate |

### Section 4: Performance (row id=4)

| ID | Title | Type | Metric |
| --- | --- | --- | --- |
| 400 | Delivery Latency P50 | Stat | `histogram_quantile(0.50, ...)` | < 1000 ms green |
| 401 | Delivery Latency P95 | Stat | `histogram_quantile(0.95, ...)` | < 3000 ms green |
| 402 | Delivery Latency P99 | Stat | `histogram_quantile(0.99, ...)` | < 5000 ms green |
| 403 | Delivery Latency Percentiles over Time | Time series | P50/P95/P99 multi-target |
| 404 | Job Processing Duration over Time | Time series | avg duration trend |

**Total: 4 row panels + 19 content panels = 23 panels**

---

## 5. Variables

| Variable | Type | Values | Used in queries |
| --- | --- | --- | --- |
| `$environment` | Custom static | development, staging (default), production | All panels |
| `$provider` | Custom static | All (default), fcm, noop | Phase 7B.5 ready — not in current queries |
| `$notification_type` | Custom static | All, smart_home_action_failed, schedule_execution_failed, smart_home_provider_unreachable, account_security_notice | Phase 7B.5 ready — not in current queries |
| `$outcome` | Custom static | All, success, failed, released, retried, timed_out | Available for manual filtering |

**Note:** `$provider` and `$notification_type` are defined as static custom variables. They will become `label_values()` queries against `ixora_push_delivery_total` when Phase 7B.5 ships. Their values are sourced from `PushNotificationEvents.php` (notification types) and `FcmPushProvider`/`NoopPushProvider` (providers).

---

## 6. Navigation

D-03 is integrated into the full bidirectional navigation mesh established in Phase 8.6. It appears at position 3 in the standard link order.

### Standard link order (updated in Phase 8.7)

| Position | Dashboard | URL |
| --- | --- | --- |
| 1 | D-01 Platform Overview | `/d/ixora-platform` |
| 2 | D-02 Smart Home | `/d/ixora-smart-home` |
| **3** | **D-03 Push Notifications** | `/d/ixora-push` |
| 4 | D-04 Queue Workers | `/d/ixora-queue` |
| 5 | D-05 HTTP API | `/d/ixora-http` |
| 6 | D-06 Scheduler | `/d/ixora-scheduler` |
| 7 | D-07 Infrastructure | `/d/ixora-collector` |

**D-03's own links (6 peers):** D-01, D-02, D-04, D-05, D-06, D-07.
**All 6 existing dashboards** were updated to include a D-03 link at position 3.

Total navigation links in the ecosystem: **42** (7 dashboards × 6 peers each).

---

## 7. Investigation Workflow

### Push Notification Failure Investigation

```
D-01 Platform Overview
  └─→ D-03 Push Notifications
        └─→ Section 1: Check Push Success Rate — below threshold?
              └─→ Section 3: Failure Rate by Outcome
                    ├─→ outcome=failed: permanent rejection
                    │     └─→ Loki: filter {app="ixora-backend"} | json | message=~"push failed"
                    │           → look for error_code: UNREGISTERED, NOT_FOUND, INVALID_ARGUMENT
                    ├─→ outcome=retried|released: transient error
                    │     └─→ Loki: look for provider=fcm + status_code=5xx
                    └─→ outcome=timed_out: FCM unresponsive
                          └─→ D-07 Infrastructure: check Collector export health
                                → Tempo: search queue consumer spans on push queue
```

### Step-by-step procedure

| Step | Location | Signal | Action |
| --- | --- | --- | --- |
| 1 | D-01 Business Summary | Push success rate stat card red | Confirm elevated failure rate; note time range |
| 2 | D-03 Platform Health | Push Failure Rate + Retry Rate | Identify outcome type (permanent vs transient) |
| 3 | D-03 Failures | Failure Rate by Outcome bar gauge | Confirm which outcome is dominant |
| 4 | D-03 Performance | P99 Latency | If elevated → likely FCM timeout or large token fan-out |
| 5 | Loki Explore | `{app="ixora-backend"} |= "PushNotificationJob"` | Find structured log entries with error_code, provider |
| 6 | D-07 Infrastructure | Collector export health | Rule out telemetry pipeline issues |
| 7 | Tempo Explore | Queue consumer spans, `messaging.destination=push` | Find trace IDs for errored push jobs |
| 8 | Loki (trace_id filter) | Filter by trace_id from step 7 | Correlate all log lines for the specific delivery attempt |

### Failure diagnosis guide

| Symptom | Likely cause | Next step |
| --- | --- | --- |
| `outcome=failed` spike | Expired/deactivated tokens (UNREGISTERED/NOT_FOUND) | Check Loki for `error_code=UNREGISTERED` — token deactivation is automatic |
| `outcome=retried` spike | FCM API transient error (5xx, network) | Check D-07 Infrastructure; FCM status page |
| `outcome=timed_out` spike | FCM unresponsive; large token fan-out | Check job timeout (30s default); investigate token count per user |
| Success rate 0% | Queue worker stopped or push queue drained | Check D-04 Queue Workers; check push worker process |
| Delivery rate 0 | No push notifications triggered upstream | Check D-02 Smart Home (smart_home_action_failed) and D-06 Scheduler (schedule_execution_failed) |

---

## 8. Architecture Review

### 8.1 Dashboard responsibilities

D-03 owns the push notification delivery layer exclusively:
- Queue-level delivery success/failure rates
- Processing latency (P50/P95/P99)
- Outcome breakdown (permanent vs transient failures)

D-03 does NOT own:
- Queue infrastructure health (→ D-04 Queue Workers, D-07 Infrastructure)
- Business event triggers (→ D-02 Smart Home, D-06 Scheduler)
- HTTP API health (→ D-05 HTTP API)

### 8.2 Metric source decision

**Why queue metrics and not `ixora.push.delivery.total`?**

Phase 7B.5 has not been implemented. `PushNotificationJob` emits only logs, not custom metrics. The queue telemetry (`QueueExecutionTelemetry`) automatically captures all `PushNotificationJob` executions because the job implements `ShouldQueue` and runs on the `push` queue.

**What this means:**
- `outcome=success` = the entire fan-out job completed (all tokens processed, no exceptions propagated)
- `outcome=failed` = the job itself failed (exceptional case)
- Per-token delivery success/failure is only in Loki logs

**When Phase 7B.5 ships:**
- Add `ixora_push_delivery_total` panels (per-notification-type, per-provider breakdowns)
- Convert `$provider` and `$notification_type` variables to `label_values()` queries
- D-01 Platform Overview Business Summary can be extended with per-notification-type breakdown

### 8.3 Convention compliance

| Convention | Status |
| --- | --- |
| UID starts with `ixora-` | ✅ `ixora-push` |
| Folder: Business | ✅ |
| Refresh: 1m (Business dashboards) | ✅ |
| Default time range: now-1h | ✅ |
| `editable: false` | ✅ |
| `$environment` variable mandatory | ✅ |
| All panels have description | ✅ 19/19 |
| All panels have datasource UID | ✅ `ixora-prometheus` |
| Panel IDs in reserved ranges | ✅ rows 1–4, content 100–404 |
| No duplicate panel IDs | ✅ |
| Navigation mesh (6 peers) | ✅ |
| All links: `keepTime=true`, `targetBlank=false` | ✅ |
| Standard link order | ✅ D-01→D-02→D-04→D-05→D-06→D-07 |

---

## 9. Security Review

| Check | Status |
| --- | --- |
| No PII in metric labels | ✅ Queue metrics use `queue`, `outcome`, `connection` — no user_id, device_id |
| No device tokens exposed | ✅ `PushNotificationJob` logs use `token_preview` (truncated) — not in metrics |
| No FCM credentials in dashboard JSON | ✅ No external URLs or credentials |
| No sensitive notification content | ✅ Dashboard shows rates and durations only — no payload content |
| `targetBlank: false` on all nav links | ✅ |

ADR-021 (notification security + privacy) is satisfied: the dashboard surfaces only aggregated operational metrics with no PII or device-identifying information.

---

## 10. Known Limitations

| ID | Limitation | Impact | Phase 7B.5 resolution |
| --- | --- | --- | --- |
| KL-D03-1 | No per-notification-type breakdown | Cannot distinguish smart_home_action_failed vs schedule_execution_failed delivery rates | Add panels using `ixora_push_delivery_total{notification_type}` |
| KL-D03-2 | No per-provider breakdown | Cannot compare FCM vs Noop delivery rates | Add panels using `ixora_push_delivery_total{provider}` |
| KL-D03-3 | `outcome=success` at job level, not token level | A job succeeds even if some tokens fail (fan-out model — one token failure doesn't abort the batch) | Phase 7B.5 should record per-token outcome |
| KL-D03-4 | No dead-letter queue count | Cannot observe permanently abandoned jobs waiting in DLQ | Requires queue driver DLQ metric (not currently instrumented) |
| KL-D03-5 | `$provider` and `$notification_type` variables are static | Values cannot be dynamically loaded until `ixora_push_delivery_total` exists | Convert to `label_values()` in Phase 7B.5 |

---

## 11. Future Improvements

### Phase 7B.5 (Push Notifications Telemetry)

When `ixora.push.delivery.total{environment, notification_type, outcome}` ships:

1. Add **Notifications by Type** time series panel (Section 2, id=203):
   `sum by (notification_type) (rate(ixora_push_delivery_total{environment=~"$environment"}[5m]))`

2. Add **Failures by Notification Type** panel (Section 3, id=304):
   `sum by (notification_type) (rate(ixora_push_delivery_total{environment=~"$environment", outcome!="success"}[5m]))`

3. Add **Failures by Provider** panel (Section 3, id=305):
   `sum by (provider) (rate(ixora_push_delivery_total{environment=~"$environment", outcome!="success"}[5m]))`

4. Convert `$provider` variable to `label_values(ixora_push_delivery_total{environment="$environment"}, provider)`.

5. Convert `$notification_type` variable to `label_values(ixora_push_delivery_total{environment="$environment"}, notification_type)`.

6. Update D-01 Platform Overview Business Summary to include push delivery rate by notification type.

### Phase 9+

- Add SLO stat panel (e.g., "Push delivery success rate last 7 days: 99.X%").
- Add FCM token lifecycle panel (tokens registered / deactivated per day — requires new metric).
- Add Loki Explore data links on error panels for one-click investigation.

---

## Related Documents

| Document | Relationship |
| --- | --- |
| [dashboard-conventions.md](dashboard-conventions.md) | Navigation conventions §12; §8 Panel ID Convention; §6 Variable Convention |
| [dashboard-d04-queue.md](dashboard-d04-queue.md) | D-04 Queue Workers — same queue telemetry layer, different queue filter |
| [dashboard-d02-smart-home.md](dashboard-d02-smart-home.md) | D-02 Smart Home — primary upstream trigger for `smart_home_action_failed` push |
| [dashboard-d06-scheduler.md](dashboard-d06-scheduler.md) | D-06 Scheduler — upstream trigger for `schedule_execution_failed` push |
| [dashboard-operational-validation.md](dashboard-operational-validation.md) | Phase 8.6 navigation mesh; D-03 extends the mesh in Phase 8.7 |
| [dashboard-d01-platform-overview.md](dashboard-d01-platform-overview.md) | D-01 overview tier; extends to include D-03 push summary in Phase 7B.5+ |
| [specs/push-notifications/mvp/spec.md](../../push-notifications/mvp/spec.md) | Push Notifications MVP spec; PushNotificationJob, PushProvider, fan-out model |
| [decisions/ADR-017-push-notification-provider-strategy.md](../../../decisions/ADR-017-push-notification-provider-strategy.md) | FCM as transport; provider abstraction |
| [decisions/ADR-019-notification-event-taxonomy.md](../../../decisions/ADR-019-notification-event-taxonomy.md) | Notification type taxonomy |
| [decisions/ADR-021-notification-security-and-privacy.md](../../../decisions/ADR-021-notification-security-and-privacy.md) | Privacy rules for push telemetry |
