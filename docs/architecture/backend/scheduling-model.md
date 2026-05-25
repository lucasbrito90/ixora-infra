# Scheduling model — future automation boundary (planning only)

**Status:** Future architecture — **NOT implemented**  
**Scope:** Time-based vibe automation, execution audit, optional device actions (`back_vibes` schema stubs exist; no runtime)  
**Applies to:** Future Laravel scheduler/workers, future mobile automation client — **nothing shipped today**

> **Planning-only.** This document defines a **future model and responsibility boundary**. It does **not** authorize implementation, prescribe tasks, or describe current product behaviour. Until an explicit delivery phase begins, treat all scheduling automation as **out of scope** for production.

---

## Purpose

Reserve a coherent architecture for **when** Ixora may automate vibe playback and related side effects: how **`schedules`**, **`schedule_executions`**, and **`vibe_device_actions`** relate; where **backend** vs **mobile** responsibility should fall; and how **timezone**, **recurrence**, **queues**, and **push** might integrate **without** conflating them with today’s **manual, client-only playback**.

This document states **boundaries and intent**. Feature specs, migrations beyond existing stubs, and code are **future work**.

---

## Context

### Shipped today

| Area | State |
| --- | --- |
| **Manual playback** | Mobile builds an **execution plan** locally and plays via **`player.store`** — no backend play endpoint ([`../../specs/vibes/playback-runtime/spec.md`](../../specs/vibes/playback-runtime/spec.md), [`../audio/playback-runtime.md`](../audio/playback-runtime.md)) |
| **Execution plan** | Pure client transform **`VibeSound[]` → `VibeExecutionLayer[]`** — not server-driven ([`../../specs/vibes/execution-plan/spec.md`](../../specs/vibes/execution-plan/spec.md)) |
| **Scheduler / cron / jobs for vibes** | **None** |
| **Schedule API** | **None** (no routes/controllers) |
| **Mobile schedule UI** | **None** |
| **Push-driven “play vibe now”** | **None** |
| **Smart-home integrations** | **None** (schema comments reference providers; no connectors) |

### Schema stubs (database only)

Migrations and Eloquent models exist as **structural placeholders** — cleared by content reset tooling, not exercised by app logic:

| Table | Role (intended future) |
| --- | --- |
| **`schedules`** | User-owned rule: which **vibe**, when, recurrence |
| **`schedule_executions`** | Audit row per fired attempt |
| **`devices`** | User-linked external device registry (provider + external id) |
| **`vibe_device_actions`** | Optional side effects tied to a **vibe** (not necessarily to a schedule row directly) |

**Do not infer** shipped behaviour from empty tables or model files alone.

---

## Current Decision (today)

1. **No automation runtime** — users start/stop vibes manually on device.
2. **Backend does not execute vibes** — Laravel stores composition and CDN URLs; it does **not** stream audio or drive layer timers.
3. **Existing schedule-related schema is provisional** — may change before any implementation phase; this doc describes **direction**, not a frozen contract.
4. **Smart-home platforms** (**Home Assistant**, **Tuya**, **Alexa**, **Google Home**) are **out of scope today** — no OAuth, webhooks, skill actions, or device sync ships.
5. **Planning docs must not be cited as implementation requirements** — no tasks, sprints, or “must ship” language until a dedicated spec + ADR phase.

---

## Future architecture (conceptual)

When scheduling is implemented, the intended **separation** is:

```
┌─────────────────────────────────────────────────────────────────────────┐
│  schedules (config)          — WHAT to run, WHEN (recurrence + TZ)       │
│  schedule_executions (audit) — WHETHER a tick ran, success/failure       │
│  vibe_device_actions (optional) — side effects bundled with a vibe       │
└───────────────────────────────┬─────────────────────────────────────────┘
                                │
                                ▼
              Future automation runtime (backend + mobile trigger path)
                                │
        ┌───────────────────────┼───────────────────────┐
        ▼                       ▼                       ▼
  Push / silent wake      Mobile local executor    Device action adapters
  (future boundary)       (playVibe + plan)        (future, out of scope today)
```

**Playback itself** should still reuse the **existing mobile execution plan + player stack** — not a new server-side audio engine.

---

## Domain model (future)

### `schedules`

**Intent:** A user-defined rule to **start** (and optionally **stop**) a **vibe** on a calendar/recurrence pattern.

**Stub columns today** (`back_vibes` migration):

| Column | Future meaning |
| --- | --- |
| `user_id` | Owner — schedules are **user-scoped**, not shared |
| `vibe_id` | Target vibe (must belong to same user) |
| `name` | User-visible label |
| `start_time` | Anchor **local** or **UTC** instant — **timezone policy TBD at implementation** (see below) |
| `recurrence_type` | `none`, `daily`, `weekly`, `custom` (comment in migration) |
| `recurrence_config` | JSON — days-of-week, interval, end date, exceptions |
| `is_enabled` | Soft disable without delete |

**Not in stub schema yet (likely future additions):**

- Explicit **`timezone`** (IANA) per schedule or per user default
- **`end_time`** / max duration / “stop vibe after N minutes”
- **`last_run_at`** / **`next_run_at`** materialized fields for worker efficiency
- Link table **`schedule_device_actions`** if side effects must fire per schedule tick (today actions hang off **vibe** only)

### `schedule_executions`

**Intent:** **Append-only audit** of automation attempts — not the live playback session.

| Column | Future meaning |
| --- | --- |
| `schedule_id` | Parent rule |
| `executed_at` | When the runtime **attempted** the tick |
| `status` | `success` \| `failed` (stub comment) |
| `log` | Human/machine diagnostic (push id, device id, error message) |

**Boundary:** One execution row ≠ guaranteed audible playback. Mobile may ignore push, be offline, or fail prepare handshake — audit must reflect **delivery/attempt**, with optional later **`ack`** from device.

### `vibe_device_actions`

**Intent:** When a vibe runs (manual **or** scheduled), optionally trigger **external device** commands defined on the vibe.

| Column | Future meaning |
| --- | --- |
| `vibe_id` | Parent vibe |
| `device_id` | Row in **`devices`** |
| `action_type` | Provider-specific verb (e.g. `turn_on`, `set_brightness`) — **not standardized today** |
| `parameters` | JSON payload |
| `delay_seconds` | Offset after vibe start before invoking action |

**Relationship to schedules:** Actions attach to **vibe composition**, so the same vibe behaves consistently whether the user tapped Play or automation fired. Schedule-specific overrides would be a **future extension**, not assumed today.

### `devices` (related stub)

Registry of user-linked externals: `provider`, `external_id`, `type`, `metadata`. Provider comment lists **Home Assistant, Tuya, Alexa**, etc. — **documentation only**; no integration code.

---

## Future automation runtime

**Not implemented.** At a high level, a future runtime would:

1. **Evaluate** due schedules (cron/worker — see queue boundary below).
2. **Resolve** target user, vibe, and enabled state.
3. **Trigger** playback on a **registered mobile device** (primary path) and/or record failure.
4. **Optionally invoke** `vibe_device_actions` via future provider adapters.
5. **Insert** `schedule_executions` for traceability.

**Explicit non-goals for v1 planning:**

- Server-side audio mixing or “cloud play”
- Replacing **`buildVibeExecutionPlan`** with a backend planner
- Running automation **only** when the mobile app is in foreground (unless product later accepts that limitation explicitly)

---

## Timezone rules (future)

Timezone is **unsettled** — stub `start_time` is `dateTime` without a TZ column. Recommended **planning direction**:

| Topic | Planning direction |
| --- | --- |
| **Storage** | Persist instants in **UTC** in the database; store **IANA timezone** on schedule or user profile for display and recurrence expansion |
| **Recurrence expansion** | Expand “every Monday 07:00” in the schedule’s timezone, then convert to UTC for worker comparison |
| **DST** | Recurrence engine must use timezone-aware library semantics (spring forward / fall back — skip or clamp ambiguous local times; policy TBD at implementation) |
| **User travel** | Mobile local clock ≠ schedule timezone — automation should follow **schedule timezone**, not device offset, unless product defines “follow device” mode |
| **Backend `APP_TIMEZONE`** | Worker runs in UTC; never assume Laravel app timezone equals user intent |

**Today:** No timezone field ships; mobile playback uses **immediate** user action only.

---

## Recurrence model (future)

**Stub:** `recurrence_type` + nullable `recurrence_config` JSON.

| `recurrence_type` | Intended use |
| --- | --- |
| **`none`** | One-shot at `start_time` (or single fire then disable) |
| **`daily`** | Repeat every day at derived local time |
| **`weekly`** | Repeat on selected weekdays |
| **`custom`** | JSON-driven rules (interval, monthly nth weekday, etc.) — shape TBD |

**Planning principles:**

- **Deterministic expansion** — same schedule + timezone → same next occurrences (testable).
- **Idempotent ticks** — duplicate worker runs must not double-play without explicit product allowance; use execution ids or dedupe keys.
- **Disabled schedules** — `is_enabled = false` skips evaluation entirely.
- **Deleted vibe** — FK cascade on stub schema removes schedules; product may prefer soft-disable instead (TBD).

**Not planned in this doc:** iCal RRULE import, natural-language scheduling, snooze chains.

---

## Local vs backend responsibility (future boundary)

| Concern | Backend (future) | Mobile (future) |
| --- | --- | --- |
| **Schedule CRUD & ownership** | Authoritative store, policies, validation | Cache/read-only mirror optional |
| **“Is it time to run?”** | Cron/queue worker evaluates due schedules | May supplement with **local alarms** only if product explicitly adds offline-first scheduling (conflicts with push model — TBD) |
| **Execution plan** | Does **not** build layer timers | **`buildVibeExecutionPlan`** + **`playVibe`** — same as manual play |
| **Audio bytes** | CDN URLs via existing API | Download/offline per [`../audio/audio-cache.md`](../audio/audio-cache.md) |
| **Playback state** | Does **not** own `playbackState` | **`player.store`** remains source of truth |
| **Audit** | Writes **`schedule_executions`** | May POST **ack** / failure reason (future API) |
| **Device actions** | May invoke server-side adapters (if secrets stay off mobile) | Unlikely to hold Home Assistant tokens in v1 planning — prefer backend broker |

**Today:** entire playback column is mobile-only manual; backend column for schedules is **empty**.

---

## Queues, jobs, and cron (future boundary)

**Not implemented.** Intended split:

| Mechanism | Future role |
| --- | --- |
| **Laravel scheduler (`schedule:run`)** | Periodic **tick** — e.g. every minute — to enqueue due work |
| **Queue jobs** | Per-schedule or batched **DispatchVibeSchedule** work units — retry, backoff, dead-letter |
| **Horizon / worker pool** | Process dispatch jobs — **not** play audio |
| **Idempotency** | Job payload includes `schedule_id` + occurrence key to avoid duplicate pushes |

**Boundary rules (planning):**

- Cron evaluates **UTC instants**; jobs **do not** call ExoPlayer or NativeAudio.
- Long-running playback stays on device; backend jobs should finish in **seconds** (dispatch + audit + optional device HTTP).
- Failed jobs write **`schedule_executions.status = failed`** with `log` — no silent drops.

**Explicitly not chosen yet:** exact queue driver, batching strategy, or “run missed ticks on reconnect” policy.

---

## Push notification (future boundary)

**Not implemented.** Likely direction for **waking mobile** to play a scheduled vibe:

| Topic | Planning direction |
| --- | --- |
| **Transport** | FCM (Android) / APNs (iOS) — platform tokens stored per user/device row (schema TBD) |
| **Payload** | Minimal: `vibe_id`, schedule occurrence id, optional “play” action — **not** full `VibeSound[]` |
| **Handler** | Native push → Capacitor → JS invokes same **`playVibe`** path after fetching sounds (online) or snapshot (offline) |
| **Foreground service** | Scheduled play still needs existing Android FGS + prepare handshake constraints |
| **User opt-in** | Automation without notification permission may fail on Android 13+ — product/policy TBD |

**Boundary:** Push is a **trigger**, not a playback engine. Media notification remains NativeAudio’s **manual/session** notification unless product merges channels (TBD).

**Not in scope today:** silent push abuse, background fetch replacing push, server-initiated stream URLs.

---

## Mobile offline limitations (future interaction)

Today’s offline model ([`../audio/audio-cache.md`](../audio/audio-cache.md), [`../../specs/vibes/offline-download/spec.md`](../../specs/vibes/offline-download/spec.md)) constrains **future** automation:

| Limitation | Impact on future scheduling |
| --- | --- |
| **Plan requires `VibeSound[]`** | Scheduled play needs API or **`offline_vibe_manifest_v1`** snapshot |
| **Stale snapshot** | Layer edits after download → wrong plan until re-download |
| **URL exact match** | CDN URL change breaks offline audio until re-download |
| **No background JS guarantee** | Push + native wake required; pure local cron in WebView is **unreliable** on Android |
| **Task removal kills process** | Swipe from recents stops audio — scheduled session may end unexpectedly ([`../mobile/android-native-customizations.md`](../mobile/android-native-customizations.md)) |
| **Prepare timeout / partial layers** | Automation must tolerate same failure modes as manual play |

**Planning stance:** Backend should assume **best-effort delivery** — audit failures honestly; optional “only run if offline-ready” flag on schedule (future field).

---

## Smart-home integrations — out of scope today

The **`devices.provider`** migration comment names **Home Assistant, Tuya, Alexa**, and similar. **None of these are implemented.**

| Platform | Status today | Notes for future boundary |
| --- | --- | --- |
| **Home Assistant** | Out of scope | Would need server-side broker or user-supplied base URL + token — secrets not on mobile |
| **Tuya** | Out of scope | Cloud API credentials, device pairing — separate product |
| **Alexa** | Out of scope | Skill / account linking — not ambient app playback |
| **Google Home** | Out of scope | Cast / Assistant actions — different stack from Capacitor player |

**`vibe_device_actions`** is a **future hook** only. Do not build schedule UI or worker logic assuming any provider works until a dedicated integration ADR exists per provider.

---

## Relationship to playback stack

Scheduled automation **must not** invent a parallel audio pipeline:

```
Future tick
  → (push or local trigger)
  → fetch vibe + sounds OR offline snapshot
  → buildVibeExecutionPlan
  → player.store.playVibe
  → existing audio-player.service / NativeAudio / FGS path
```

Layer timing (`start_offset_seconds`, interval gaps, etc.) remains defined in [`../../specs/vibes/execution-plan/spec.md`](../../specs/vibes/execution-plan/spec.md) — schedule fires **vibe start**, not per-layer cron on the server.

---

## Risks (if implemented without boundaries)

| Risk | Mitigation (future design) |
| --- | --- |
| Double playback | Idempotent dispatch + occurrence keys |
| TZ/DST bugs | IANA timezone + explicit test matrix |
| Offline false success | Separate **dispatched** vs **played** audit states |
| Secret leakage to mobile | Device actions via backend adapters |
| Scope creep into smart home | Provider-specific ADRs; keep schedule MVP playback-only |
| Confusion with manual play | Reuse `playVibe`; no backend “play API” |

---

## What this document does not contain

- Implementation tasks, story points, or sprint plans
- API endpoint definitions or OpenAPI
- Exact JSON schema for `recurrence_config`
- Commitments to Home Assistant / Tuya / Alexa / Google Home timelines
- Changes to current mobile or Laravel **shipped** behaviour

When scheduling moves from planning to delivery, expect: dedicated **feature spec(s)**, **ADR(s)** for timezone + push + queue, and updates to this file’s **Status** — not the reverse.

---

## Related docs

| Document | Relationship |
| --- | --- |
| [`../../specs/vibes/playback-runtime/spec.md`](../../specs/vibes/playback-runtime/spec.md) | Shipped manual playback — automation must align |
| [`../../specs/vibes/execution-plan/spec.md`](../../specs/vibes/execution-plan/spec.md) | Client plan — no backend execution engine |
| [`../audio/playback-runtime.md`](../audio/playback-runtime.md) | Player state machine, FGS, focus — scheduled play inherits constraints |
| [`../audio/audio-cache.md`](../audio/audio-cache.md) | Offline bytes + snapshot — automation offline limits |
| [`../mobile/android-native-customizations.md`](../mobile/android-native-customizations.md) | Background process, task removal |
| [`../../specs/vibes/offline-download/spec.md`](../../specs/vibes/offline-download/spec.md) | Offline snapshot semantics |

### Schema reference (stubs only)

| Artifact | Path |
| --- | --- |
| `schedules` migration | `back_vibes/database/migrations/2026_05_01_000007_create_schedules_table.php` |
| `schedule_executions` migration | `back_vibes/database/migrations/2026_05_01_000008_create_schedule_executions_table.php` |
| `vibe_device_actions` migration | `back_vibes/database/migrations/2026_05_01_000006_create_vibe_device_actions_table.php` |
| `devices` migration | `back_vibes/database/migrations/2026_05_01_000005_create_devices_table.php` |
| Models | `back_vibes/app/Models/Schedule.php`, `ScheduleExecution.php`, `VibeDeviceAction.php`, `Device.php` |

---

**Reminder:** Scheduler automation is **not implemented**. This file is **planning-only** until explicitly superseded by an active delivery spec and ADR.
