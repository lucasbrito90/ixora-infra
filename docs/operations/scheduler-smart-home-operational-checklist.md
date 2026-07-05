# Scheduler + Smart Home — Operational Checklist

**Status:** Active operational runbook  
**Scope:** Staging and production readiness for Scheduler + Smart Home Automations  
**Applies to:** `back_vibes` workers, queue, push pipeline, and mobile local notifications (client-side)

**Architecture references:** [ADR-022](../decisions/ADR-022-scheduler-smart-home-automation-model.md) · [ADR-023](../decisions/ADR-023-automation-execution-order-and-failure-policy.md) · [ADR-024](../decisions/ADR-024-automation-notifications-and-observability.md) · [ADR-026](../decisions/ADR-026-automation-execution-security.md) · [ADR-027](../decisions/ADR-027-asynchronous-orchestration-pattern.md) · [asynchronous-orchestration.md](../architecture/asynchronous-orchestration.md) · [notification-architecture.md](../architecture/notification-architecture.md) · [staging-digitalocean.md](../architecture/backend/staging-digitalocean.md)

> **Purpose:** Verify that Scheduler + Smart Home Automations are **operationally ready** — workers running, failures isolated, logs diagnosable, and recovery paths understood. This is **not** a feature spec.

---

## 1. Runtime topology

```
Scheduler worker (schedules:dispatch-loop ~60s)
    ↓
schedules:dispatch-due
    ↓  DB transaction
ScheduleExecution + next_run_at advance
    ↓  post-commit (dispatched only)
ScheduleAutomationValidator
    ↓
VibeSmartHomeDispatchService → jobs table (smart-home queue)
    ↓
Queue worker (queue:work)
    ↓
SmartHomeActionJob
    ↓
HomeAssistantAdapter → Home Assistant REST API
    ↓  on failure
PushNotificationEvents → jobs table (push queue)
    ↓
PushNotificationJob → FCM

Mobile (parallel, device-local):
Schedule SQLite mirror → local OS reminders (Capacitor)
```

| Component | Process | Queue / cadence |
| --- | --- | --- |
| **Scheduler worker** | `php artisan schedules:dispatch-loop` | ~60 s tick |
| **Queue worker** | `php artisan queue:work --queue=push,smart-home,default …` | Continuous |
| **Push delivery** | `PushNotificationJob` on `push` queue | Async, best-effort |
| **Smart Home execution** | `SmartHomeActionJob` on `smart-home` queue | Async, best-effort |
| **Local reminders** | Mobile app after schedule sync | Device OS alarms — no server |

**Staging IaC:** [`opentofu/staging/app-api.tf`](../../opentofu/staging/app-api.tf) — three App Platform components: `api`, `queue`, `scheduler`.

---

## 2. Pre-flight checklist

Run before declaring automation ops-ready or after any deploy touching scheduler, Smart Home, or push.

### Workers

| # | Check | Pass criteria |
| --- | --- | --- |
| 2.1 | **Scheduler worker running** | Runtime logs show `[schedules:dispatch-loop] tick #N` ~every 60 s |
| 2.2 | **Queue worker running** | Component `queue` healthy; no sustained crash loop |
| 2.3 | **Queue command correct** | Includes `--queue=push,smart-home,default` |
| 2.4 | **Worker timeout** | `--timeout=90` ≥ job timeout (30 s) + headroom |
| 2.5 | **API service healthy** | HTTP health/responds; migrations applied if schema changed |

### Environment

| Variable | Expected (staging) | Purpose |
| --- | --- | --- |
| `QUEUE_CONNECTION` | `database` | Job persistence |
| `PUSH_PROVIDER` | `fcm` (or `noop` in dev) | Push transport |
| `FIREBASE_*` / `FIREBASE_CREDENTIALS` | Set in App Platform secrets | FCM OAuth |
| `PUSH_NOTIFICATIONS_QUEUE` | `push` (default) | Push job queue name |
| `SMART_HOME_QUEUE_NAME` | `smart-home` (default) | SH job queue name |
| `SMART_HOME_HA_TIMEOUT` | `10` (default) | HA HTTP timeout (seconds) |
| `SMART_HOME_ALLOW_HTTP` | `false` (production/staging) | HTTPS-only HA URLs |
| `LOG_CHANNEL` | `stderr` (App Platform) | Logs in component stream |

**Secrets never in git.** HA access tokens live in `provider_connections` (encrypted), not env vars.

### Database

| # | Check | Pass criteria |
| --- | --- | --- |
| 2.6 | **Migrations current** | `schedule_executions`, `schedules`, `vibe_device_actions`, `jobs` tables exist |
| 2.7 | **Unique index** | `(schedule_id, occurrence_key)` on `schedule_executions` (ADR-010) |
| 2.8 | **No runaway backlog** | `jobs` queue depth for `smart-home` and `push` not growing unbounded |

---

## 3. Health checks

### Scheduler tick

```bash
# One bounded tick (container console — API or scheduler component)
php artisan schedules:dispatch-loop --once

# Inspect without writes
php artisan schedules:dispatch-due --dry-run
```

**Log signals (stdout + stderr):**
- `schedules:dispatch-due summary` with `dispatched`, `skipped_duplicate`, `failed`
- `[schedules:dispatch-loop] tick #N @ …`

### Queue health

```bash
php artisan queue:monitor push,smart-home,default
```

Inspect `jobs` table:

```sql
SELECT queue, COUNT(*) AS pending
FROM jobs
GROUP BY queue
ORDER BY pending DESC;
```

### Smart Home connectivity (manual)

1. User has active `provider_connections` row with valid encrypted credentials.
2. `POST /api/smart-home/connections/{id}/sync` returns 200 or expected error — not persistent 502 without logs.

### Push pipeline (manual)

See [staging-digitalocean.md § Push Notifications](../architecture/backend/staging-digitalocean.md) and [qa/push-notifications-e2e/scripts/staging-push-send.tinker.md](../../qa/push-notifications-e2e/scripts/staging-push-send.tinker.md).

---

## 4. Observability — log catalog

All logs must remain **privacy-safe**: no FCM tokens, HA access tokens, encrypted credentials, raw push payloads, or PII.

### Scheduler + Smart Home hook

| Message | Level | Key context | Meaning |
| --- | --- | --- | --- |
| `Schedule Smart Home dispatch skipped: validation failed.` | warning | `schedule_id`, `vibe_id`, `user_id`, `validator_failed: true` | Validator returned false — **no SH jobs, no push** (ADR-026) |
| `Schedule Smart Home dispatch failed.` | warning | `schedule_id`, `vibe_id`, `user_id`, `exception_class`, `error` | Enqueue/dispatch exception — recurrence **already committed**, batch continues |

**Stdout only (not structured Log):** `Schedule [id] failed: …` on transaction/recurrence failure → triggers `schedule_execution_failed` push.

### SmartHomeActionJob

| Message | Level | Push? |
| --- | --- | --- |
| `action not found or deleted — skipping.` | warning | No |
| `device missing` / `provider connection missing` | warning | No |
| `unsupported action — skipping.` | warning | No |
| `action execution failed (provider returned failure).` | warning | `smart_home_action_failed` |
| `unexpected error executing action.` | error | `smart_home_action_failed` |
| `action executed successfully.` | info | No |

**Context keys:** `vibe_device_action_id`, `vibe_id`, `device_id`, `provider_connection_id`, `provider`, `provider_device_id`, `action_type`, `success`, `status_code`, `error_message`.

### Push pipeline

| Message | Level |
| --- | --- |
| `PushNotificationService: dispatching push for user.` | info |
| `PushNotificationEvents: notification queued.` | info |
| `PushNotificationEvents: failed to queue notification.` | error |
| `PushNotificationJob: push delivered.` / `push failed.` | info / warning |
| `PushNotificationJob: user has no active push tokens — skipping.` | info |

**Grep patterns (Runtime Logs):**

```
Schedule Smart Home dispatch skipped
Schedule Smart Home dispatch failed
SmartHomeActionJob: action execution failed
SmartHomeActionJob: unexpected error
PushNotificationEvents: failed to queue
PushNotificationJob: push failed
```

### Diagnosis flow

| Symptom | Check first | Then |
| --- | --- | --- |
| Schedules not advancing | Scheduler worker logs / ticks | `schedules.next_run_at`, transaction errors in stdout |
| No device actions | Validator skip log? | `vibe_device_actions`, ownership chain |
| Jobs stuck | `jobs` table backlog | Queue worker running? |
| HA errors | `SmartHomeActionJob` warning lines | Connection credentials, `SMART_HOME_HA_TIMEOUT` |
| No push received | `PushNotificationJob: no active push tokens` | Mobile token registration; `PUSH_PROVIDER=fcm` |
| User got wrong push | `PushNotificationEvents: notification queued` type | ADR-019 taxonomy — not duplicate local reminder |

---

## 5. Failure matrix

| Failure | Recurrence advances? | SH jobs enqueued? | Push type | Batch continues? |
| --- | --- | --- | --- | --- |
| **Scheduler transaction failure** | No | No | `schedule_execution_failed` | Yes (other schedules in batch) |
| **Duplicate occurrence** | N/A (skipped) | No | No | Yes |
| **Validator skip** | Yes (already committed) | No | **No** | Yes |
| **SH dispatch exception** | Yes | No (failed enqueue) | **No** | Yes |
| **Provider HTTP failure** | N/A (async job) | N/A | `smart_home_action_failed` | N/A |
| **Unsupported action** | N/A | N/A | **No** | N/A |
| **Provider sync unreachable** | N/A | N/A | `smart_home_provider_unreachable` | N/A |
| **Push queue/delivery failure** | N/A | N/A | Best-effort — logged | Never blocks scheduler/SH |

**Important:** `SmartHomeActionJob` catches provider failures internally — jobs **complete successfully** and rarely land in `failed_jobs`. `$tries=3` applies mainly to worker kills/timeouts, not HA 500 responses.

**Local notification failure (mobile):** Permission denied → silent skip of OS scheduling; user sees in-app banner. Does not affect backend recurrence or Smart Home. See [ADR-011](../decisions/ADR-011-scheduler-local-notifications-vs-future-fcm.md).

---

## 6. Deployment checklist

Use when promoting `develop` → `staging` or preparing production.

| # | Step | Owner |
| --- | --- | --- |
| 6.1 | Merge feature branches → `develop` → `staging` per [git-flow.md](../standards/git-flow.md) | Engineering |
| 6.2 | App Platform auto-deploy from `staging` branch (`back_vibes`) | CI |
| 6.3 | Run migrations if schema changed: `php artisan migrate --force` | Operator |
| 6.4 | Confirm **three** workers restarted: `api`, `queue`, `scheduler` | Operator |
| 6.5 | Verify scheduler ticks (~60 s) in Runtime Logs | Operator |
| 6.6 | Verify `queue:monitor push,smart-home,default` — no stuck queues | Operator |
| 6.7 | Smoke: create due schedule with device action → execution row + job drained | QA |
| 6.8 | Smoke: mobile schedule sync → local reminder registered (Android) | QA |
| 6.9 | If push changed: manual FCM send harness | QA |

**OpenTofu:** only when infra env vars change — [`opentofu/staging/README.md`](../../opentofu/staging/README.md).

---

## 7. Manual verification checklist

End-to-end staging validation (Phase 8 E2E complements this).

| # | Scenario | Expected |
| --- | --- | --- |
| 7.1 | Due schedule, no device actions | `schedule_executions` row; `next_run_at` advanced; no SH jobs |
| 7.2 | Due schedule + device actions | Execution + N `SmartHomeActionJob`s processed; HA called |
| 7.3 | Duplicate tick (same occurrence) | Second tick `skipped_duplicate`; no duplicate executions |
| 7.4 | Validator fail (foreign vibe owner) | Execution committed; warning log; no SH job; **no** `schedule_execution_failed` |
| 7.5 | Invalid recurrence (forced bad config) | Transaction fails; `schedule_execution_failed` push |
| 7.6 | HA returns 500 | Job completes; warning log; `smart_home_action_failed` push |
| 7.7 | Provider sync timeout | 502 API; connection `unreachable`; `smart_home_provider_unreachable` push |
| 7.8 | Push token missing | Job logs "no active push tokens"; scheduler unaffected |
| 7.9 | Mobile local reminder | OS notification at due time; tap → vibe player (no auto-play) |
| 7.10 | Offline mobile | Cached schedules; local reminders from mirror; sync when online |

---

## 8. Recovery checklist

| Situation | Recovery action |
| --- | --- |
| **Scheduler worker stopped** | Restart `scheduler` component; loop resumes — idempotent ticks (ADR-010) |
| **Queue worker stopped** | Restart `queue` component; drain backlog — jobs retain order per queue |
| **Stuck `jobs` rows** | Investigate payload/exceptions; after fix, worker drains; avoid manual delete unless corrupt |
| **HA token revoked** | User re-authenticates connection in app; re-sync devices |
| **FCM credentials invalid** | Fix `FIREBASE_*` secrets; restart workers; OAuth cache refreshes |
| **Recurrence stuck (bad config)** | Fix schedule via API; or disable schedule; past failures in `schedule_executions` |
| **False-positive push storm** | Check for recurring provider outage; disable noisy connection; no success-push by design (ADR-024) |

**Do not:** force-push scheduler state, delete `schedule_executions` to “fix” recurrence, or run HA calls from the scheduler command directly.

---

## 9. Troubleshooting guide

### Schedules never fire

1. Is `is_enabled = true` and `next_run_at <= now()` UTC?
2. Is scheduler worker ticking?
3. Any `failed` count in dispatch summary?
4. Check DB timezone: stored UTC ([ADR-009](../decisions/ADR-009-scheduler-timezone-utc-storage.md)).

### Smart Home never runs after schedule

1. Was tick `dispatched` (not `skipped_duplicate`)?
2. Any `validation failed` log? → ownership/device/connection chain broken.
3. Any `Schedule Smart Home dispatch failed` log? → queue/enqueue issue.
4. Are jobs in `jobs` where `queue = 'smart-home'`?
5. Is queue worker consuming `smart-home`?

### Push not received (failure expected)

1. Confirm failure path actually ran (see §5 matrix — validator skip sends **no** push).
2. User has active row in `push_tokens`?
3. `PushNotificationJob` logs — delivered vs failed vs no tokens?
4. Mobile tap handler registered — separate from delivery.

### Local reminder missing (mobile)

1. Notification permission granted?
2. Schedule sync completed online after change?
3. `next_run_at` in future when mirror rebuilt?
4. Android channel `schedule_reminders` created?

---

## 10. Architecture compliance (Phase 7 sign-off)

Confirm these ADRs remain respected in production behaviour:

| ADR | Ops sign-off question | Expected |
| --- | --- | --- |
| **ADR-022** | Automation composed from Schedule→Vibe→VibeDeviceAction? | No separate automation engine |
| **ADR-023** | SH/push failures block recurrence? | **Never** — best-effort async |
| **ADR-024** | Success push sent by default? | **No** — failure alerts only |
| **ADR-026** | Validator skip emits `schedule_execution_failed`? | **No** — log + continue |
| **ADR-027** | Command calls HA/FCM directly? | **No** — jobs + providers only |

---

## 11. Related documents

| Document | Use when |
| --- | --- |
| [staging-digitalocean.md](../architecture/backend/staging-digitalocean.md) | Staging topology, worker commands, scheduler runbook |
| [deploy-pipeline.md](../architecture/backend/deploy-pipeline.md) | Cross-repo promotion |
| [scheduler-smart-home-automations/mvp/spec.md](../specs/scheduler-smart-home-automations/mvp/spec.md) | Feature acceptance criteria |
| [scheduler-smart-home-automations/mvp/tasks.md](../specs/scheduler-smart-home-automations/mvp/tasks.md) | Implementation phase status |
| [notification-architecture.md](../architecture/notification-architecture.md) | Push taxonomy and failure policy |
| [user-experience-principles.md](../architecture/user-experience-principles.md) | User-facing copy and notification UX |

---

*Last updated: 2026-07-03 — Phase 7 operational readiness (Scheduler + Smart Home Automations).*
