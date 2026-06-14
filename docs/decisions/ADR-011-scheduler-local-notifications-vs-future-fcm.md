# ADR-011: Scheduler local notifications vs future FCM

## Status

**Accepted** — governs **Scheduler MVP** mobile reminder strategy ([`specs/scheduler/mvp/spec.md`](../specs/scheduler/mvp/spec.md)).

## Date

2026-06-12

## Context

The Scheduler MVP must remind users when a vibe is due without shipping **FCM wake-to-play**, **queue workers per tick**, **iOS scheduling**, or **Smart Home** side effects.

Constraints from existing platform docs:

- **Playback stays client-only** — **`buildVibeExecutionPlan` → `playVibe`** ([ADR-007](ADR-007-execution-plan-runtime-contract.md))
- **Backend does not execute audio** ([`scheduling-model.md`](../architecture/backend/scheduling-model.md))
- **Offline vibe bytes** require explicit download ([ADR-004](ADR-004-offline-audio-strategy.md))
- **Android background process** is fragile — task removal kills playback ([`android-native-customizations.md`](../architecture/mobile/android-native-customizations.md))

The MVP strategy ([`spec.md`](../specs/scheduler/mvp/spec.md)) establishes:

- **Backend = source of truth** for schedule CRUD and **`next_run_at`**
- **SQLite mirror = read-only offline cache**
- **Offline cannot create/edit/delete schedules**
- **Scheduler worker** runs backend dispatcher loop for **audit + recurrence advance** — not push
- **Local notifications** are the **first offline-capable reminder path**

The team needed a clear decision on **what reminders guarantee** vs **what future FCM might add**.

---

## Decision

**Scheduler MVP uses Android local notifications as the sole automated reminder mechanism. Backend remains authoritative; SQLite mirror is read-only offline; notifications are reminders only — not guaranteed auto-play. FCM, queue dispatch jobs, iOS scheduling, and Smart Home are deferred.**

### MVP reminder stack

| Layer | Role |
| --- | --- |
| **Laravel API** | Schedule CRUD, **`next_run_at`**, execution audit ([ADR-009](ADR-009-scheduler-timezone-utc-storage.md), [ADR-010](ADR-010-scheduler-idempotency-occurrence-key.md)) |
| **Dispatcher (scheduler worker)** | Idempotent ticks via `schedules:dispatch-loop` — **does not send FCM** in MVP |
| **SQLite mirror (Android)** | Read-only offline copy — updated **only** on successful online sync |
| **Local Notifications (Android)** | OS-scheduled alarms from mirror data — **rebuilt after every sync** |

### Offline mutations — forbidden

| Action | Online | Offline |
| --- | --- | --- |
| Create schedule | ✅ API | ❌ Block UI + service |
| Edit schedule | ✅ API | ❌ |
| Delete schedule | ✅ API | ❌ |
| List / view schedules | ✅ API | ✅ SQLite mirror read-only |

**No offline outbox.** Server wins on conflict.

### Local notification behaviour

| Topic | Rule |
| --- | --- |
| **Purpose** | **Remind** user at due time — not silent auto-play |
| **Due time source** | **`next_run_at`** from mirror (server-computed) — primary alarm anchor |
| **Registration** | After sync: **cancel all** schedule notification ids for user → **re-register** from enabled mirror rows |
| **Notification id** | Stable per schedule + occurrence (derive from **`schedule_id`** + **`occurrence_key`** or **`next_run_at`**) |
| **Payload** | **`schedule_id`**, **`vibe_id`**, schedule name — deep link to player |
| **Tap action** | Open **`VibePlayerPage`** / app flow — user **Play** or explicit in-app “Start now” |
| **Auto-play** | **Not invoked** on cold start without user action |
| **Killed / force-stopped app** | **No guarantee** notification fires or playback starts — hard product boundary |
| **Offline at due time** | Previously scheduled OS alarms **may** still fire; no new schedules offline |
| **Rebuild trigger** | Every successful schedule pull + after each CRUD mutation sync |

### Playback path (unchanged)

```
Notification tap (or user opens app)
  → load vibe + sounds (API or offline snapshot)
  → buildVibeExecutionPlan(vibeSounds)
  → user initiates playVibe (or in-app CTA)
```

Scheduled reminder **does not** bypass offline download requirements — undownloaded vibes may show player without guaranteed offline audio.

### Android notification permission

| Topic | Rule |
| --- | --- |
| **Android 13+ (`POST_NOTIFICATIONS`)** | Request before scheduling; explain value prop |
| **Denied permission** | Schedules still CRUD online; **no local reminders** — degrade gracefully |
| **Channels** | Dedicated channel for schedule reminders (implementation detail) |

### Explicit MVP exclusions

| Capability | MVP |
| --- | --- |
| **FCM / push wake-to-play** | ❌ Future phase |
| **Laravel queue `DispatchVibeSchedule` jobs** | ❌ Future phase |
| **iOS local notification scheduling** | ❌ Future phase — Android first |
| **Smart Home (`devices`, `vibe_device_actions`)** | ❌ Out of MVP |
| **Guaranteed background auto-play** | ❌ Rejected |
| **Offline schedule edit** | ❌ Rejected |

### Future FCM phase (boundary only — not implemented)

When added post-MVP:

| Topic | Direction |
| --- | --- |
| **Transport** | FCM (Android), APNs (iOS) |
| **Payload** | Minimal: **`vibe_id`**, **`schedule_id`**, **`occurrence_key`** |
| **Handler** | Native → Capacitor → fetch sounds / offline snapshot → optional auto **`playVibe`** (new ADR required) |
| **Queue** | Per-tick jobs on existing **`queue`** worker ([`staging-digitalocean.md`](../architecture/backend/staging-digitalocean.md)) |
| **Dedupe** | Reuse **`occurrence_key`** ([ADR-010](ADR-010-scheduler-idempotency-occurrence-key.md)) |
| **Audit** | Extend execution **`status`** — e.g. **`acknowledged`**, **`failed`** |

Local notifications may remain as **fallback** when push permission denied — product decision in future spec.

### Relationship to backend dispatcher

Backend tick (**`dispatched`**) and local notification are **parallel**:

- Dispatcher advances **`next_run_at`** and writes audit **even if device offline**
- Local notification fires from **prior sync** — may drift until next online sync
- **Online sync after tick** refreshes mirror and **rebuilds** notification schedule

---

## Consequences

### Positive

| Outcome | Why it matters |
| --- | --- |
| **No FCM infra for MVP** | Faster delivery; no device token schema |
| **Works offline for viewing** | Mirror + previously scheduled alarms |
| **Honest UX** | No false “auto-play” promise |
| **Aligns with playback ADR** | Same **`playVibe`** path as manual play |
| **Clear upgrade path** | FCM reuses **`occurrence_key`** and audit table |

### Negative / tradeoffs

| Tradeoff | Impact |
| --- | --- |
| **Android-only MVP** | iOS users get no schedule reminders until follow-up |
| **Reminder ≠ playback** | Extra tap to start vibe — friction by design |
| **OS alarm reliability** | OEM battery savers may delay notifications |
| **Mirror drift offline** | Long offline periods may show stale **`next_run_at`** until sync |
| **Dual paths to maintain** | Backend recurrence + notification rebuild logic |

### Implementation expectations (Phases 7–9)

- Platform guard: scheduling UI + notifications **Android native** first
- **`schedule-notification.service.ts`**: cancel + register after mirror write
- Block mutations when **`!navigator.onLine`**
- QA on **installable build** without live reload ([`offline-download/spec.md`](../specs/vibes/offline-download/spec.md) pattern)

---

## Alternatives Considered

| Alternative | Why not chosen (MVP) |
| --- | --- |
| **FCM-only reminders (no local notifications)** | Fails offline reminder story; requires token infra now |
| **WebView `setTimeout` / JS cron** | Unreliable on Android background |
| **Backend sends SMS/email** | Out of product scope |
| **Auto `playVibe` on notification without user action** | Violates killed-app boundary; FGS/prepare constraints |
| **Offline schedule edit with sync queue** | Rejected — complexity; server wins simpler |
| **iOS + Android simultaneous MVP** | Doubles QA; iOS deferred explicitly |
| **Smart Home trigger on tick** | No provider integrations — stubs only |

---

## Related Docs

| Document | Relationship |
| --- | --- |
| [`../specs/scheduler/mvp/spec.md`](../specs/scheduler/mvp/spec.md) | Local notification strategy, hard boundaries |
| [`../specs/scheduler/mvp/plan.md`](../specs/scheduler/mvp/plan.md) | Phases 7–9 |
| [`../specs/scheduler/mvp/tasks.md`](../specs/scheduler/mvp/tasks.md) | Checklist |
| [`ADR-009`](ADR-009-scheduler-timezone-utc-storage.md) | Mirror uses server **`next_run_at`** |
| [`ADR-010`](ADR-010-scheduler-idempotency-occurrence-key.md) | Future FCM dedupe key |
| [`ADR-007`](ADR-007-execution-plan-runtime-contract.md) | Playback contract |
| [`ADR-004`](ADR-004-offline-audio-strategy.md) | Offline bytes separate from reminders |
| [`../specs/vibes/offline-download/spec.md`](../specs/vibes/offline-download/spec.md) | Player offline snapshot |
| [`../specs/vibes/execution-plan/spec.md`](../specs/vibes/execution-plan/spec.md) | Plan rebuild on play |
| [`../standards/front-vibes-auth-core.md`](../standards/front-vibes-auth-core.md) | Online CRUD auth |
| [`../architecture/mobile/android-native-customizations.md`](../architecture/mobile/android-native-customizations.md) | Process / background limits |
| [`../architecture/backend/scheduling-model.md`](../architecture/backend/scheduling-model.md) | Future FCM boundary |

---

When reminder or push strategy changes, supersede this ADR before implementing FCM or iOS scheduling.
