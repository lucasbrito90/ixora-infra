# ADR-034: Representação de execução e sucesso parcial

## Status

**Accepted** — governs the **execution outcome model** for Smart Home scene actions in v1.4.0. Consumed by T21 (retention command), T22 (API exposure), T26 (mobile client). Compatible with T23 (retry policy — future).

## Date

2026-09-03

---

## Context

`SceneDispatchResult` (and its vibe-scoped twin `SmartHomeDispatchResult`) describe **enqueue state only** — `dispatched` and `skipped` count how many jobs were placed on the queue at request/command time, not what happened when those jobs ran against the provider. The actual execution outcome lives today in two places:

1. **Log lines** (`Log::warning`, `Log::error`) inside `SceneActionJob::handle()` — unstructured, not queryable per user or per execution event.
2. **OpenTelemetry span** `smart_home.action` with attribute `ixora.action.outcome` and metric `ixora.smart_home.action.total` — emitted by `SmartHomeActionTelemetry::wrap()` and shipped to the Collector per ADR-028.

Neither surface supports the product requirement: *"show the user that Scene X ran and 2 actions succeeded, 1 timed out on Provider C."* This ADR decides where that truth is stored and how it is structured.

### Four exit paths of `SceneActionJob::handle()`

| Path | Current outcome classification | Telemetry span created? |
| --- | --- | --- |
| Guard exit (action/device/connection missing at job time) | `return` + warning log | **No** — boundary never reached |
| `ActionResult(success: true)` | `SmartHomeActionOutcome::Success` | Yes |
| `ActionResult(success: false)` | `SmartHomeActionOutcome::Failure` | Yes |
| `UnsupportedSmartHomeActionException` | `SmartHomeActionOutcome::Unsupported` | Yes |
| Generic `Throwable` | `SmartHomeActionOutcome::Failure` | Yes |

The `Unknown` case in `SmartHomeActionOutcome` is a telemetry fail-open fallback (emitted only if the classifier closure itself throws) — it is never emitted in normal operation.

**Note on `$tries = 3`:** T03 (adr-conformance.md) confirmed that `SceneActionJob::handle()` engulfs all exceptions, making `$tries = 3` inert in practice. T23 owns the fix. This ADR's schema must accommodate multiple attempts per action to avoid a schema migration when T23 lands.

---

## Decision

### 1 — Where the truth lives: new table `scene_action_executions`

**A dedicated relational table — not a telemetry backend query, not an aggregate field on `SceneAction`.**

#### Against option (c) — reading spans/metrics directly

ADR-028 establishes OpenTelemetry Collector as the sole ingestion endpoint for metrics, logs, and traces, with Grafana as the visualization layer. The observability backend (Prometheus, Loki, Tempo) is **not queryable from `back_vibes`** without adding a new read-path dependency that ADR-028 never authorized. Concretely:

- A product API call ("show user X their Scene Y executions from today") needs a relational filter on `user_id` + `scene_id` + time range and must return in < 100 ms. Prometheus PromQL and Loki LogQL do not support relational joins on user-owned entities.
- Span data in Tempo is indexed by `trace_id`, not by `(user_id, scene_id)`. Answering "give me all action spans for scene 42 in the last 24 hours" would require `back_vibes` to maintain a side-table of `scene_id → trace_id` mappings — which is the execution log itself.
- Coupling `back_vibes` to a Tempo/Loki read API would make API correctness dependent on observability stack availability, violating ADR-028's isolation principle and ADR-016's "provider failures do not surface as IXORA errors" model.

#### Against option (b) — aggregate field on `SceneAction` or `Scene`

A `last_execution_outcome` column loses history. The product requirement is "what happened at 14h32" — not "what was the last outcome ever." Multi-provider scenes require per-execution, per-action, per-provider granularity; a single aggregate field cannot represent "2 successes, 1 timeout on Provider C" without a full history.

#### For option (a) — table

- Relational, filterable by `user_id` (via scene/action join), `scene_id`, time, `provider`, `outcome`.
- `trace_id` column provides a one-way correlation link from execution row to span — operators can jump to Tempo from a row; `back_vibes` never reads from Tempo.
- The telemetry span remains the authoritative source for operational metrics and aggregation (p95 latency, failure rate by provider). The execution table is the authoritative source for per-user, per-scene, per-event product data. **No duplication of truth: the two surfaces serve different consumers** (operations dashboards vs. product API).
- ADR-016 anticipated this: *"A future `action_execution_logs` table…will record…"* — this ADR is the delivery of that promise, with a name updated to match the v1.3.0 Scene model.

---

### 2 — Schema: `scene_action_executions`

One row per **action execution attempt**. The `attempt` column is always `1` today; T23 increments it on retry.

| Column | Type (PostgreSQL) | Nullable | Notes |
| --- | --- | --- | --- |
| `id` | `bigint` PK | NOT NULL | Auto-increment |
| `scene_execution_id` | `uuid` | NOT NULL | Groups all rows from one dispatch event (see §3) |
| `scene_id` | `bigint` | NOT NULL | Denormalized — stored at write time; row persists after scene is deleted |
| `scene_action_id` | `bigint` | NULLABLE | FK → `scene_actions.id` SET NULL on delete; nullable so the audit row survives action deletion |
| `device_id` | `bigint` | NOT NULL | Denormalized — stored at write time; no FK |
| `provider` | `varchar(32)` | NOT NULL | Provider slug at execution time (e.g. `home_assistant`). Not a FK — slug may lose its registered adapter in the future |
| `provider_connection_id` | `bigint` | NOT NULL | Denormalized — stored at write time; no FK |
| `action_type` | `varchar(32)` | NOT NULL | e.g. `turn_on` |
| `outcome` | `varchar(16)` | NOT NULL | `success \| failure \| unsupported \| unknown` — see §outcome below |
| `failure_category` | `varchar(32)` | NULLABLE | `transport \| provider_error \| unsupported_action \| unexpected` — null when `outcome = 'success'` |
| `http_status_code` | `smallint` | NULLABLE | Provider HTTP status from `ActionResult::$status_code`; null on transport failure |
| `duration_ms` | `integer` | NULLABLE | Wall-clock ms of `executeAction()` call from `SmartHomeProviderTelemetry` boundary; null if not measured |
| `trace_id` | `varchar(64)` | NULLABLE | OpenTelemetry `trace_id` of the `smart_home.action` span; null if telemetry unavailable |
| `attempt` | `smallint` | NOT NULL, default 1 | Attempt number (always 1 today; T23 increments on retry) |
| `executed_at` | `timestamp` | NOT NULL | `now()` at the start of job execution — not dispatch time |
| `created_at` | `timestamp` | NOT NULL | Row creation timestamp (same as `executed_at` for v1.4.0) |

**Indexes:**

| Name | Columns | Type | Purpose |
| --- | --- | --- | --- |
| `idx_sae_scene_execution` | `(scene_execution_id)` | B-tree | Aggregate all actions of one execution event |
| `idx_sae_scene_created` | `(scene_id, created_at DESC)` | B-tree | History query per scene (T22) |
| `idx_sae_created` | `(created_at)` | B-tree | Retention pruning (T21) |

No unique constraint on `(scene_action_id, scene_execution_id)` — a future retry (T23) writes a second row for the same action in the same execution event, distinguished only by `attempt`.

#### Outcome vocabulary

The `outcome` column uses exactly the same four values as `SmartHomeActionOutcome`:

| Value | Meaning in execution log |
| --- | --- |
| `success` | Provider returned 2xx; `ActionResult::$success = true` |
| `failure` | Provider returned non-2xx, transport failed, or generic `Throwable` |
| `unsupported` | `UnsupportedSmartHomeActionException` — action type not mappable for this provider |
| `unknown` | Telemetry classifier degradation (fail-open fallback) |

**Constatação — guard-path exits:** The three guard exits in `SceneActionJob::handle()` (action not found, device missing, connection missing at job runtime) currently produce **no** telemetry span and reach the execution boundary after dispatch. These represent an "attempt that could not even begin" — distinct from `failure`. They are **not written** to `scene_action_executions` in v1.4.0. Rationale: (a) the `SmartHomeActionOutcome` vocabulary has no `skipped` value and this ADR must not expand it silently; (b) `SceneDispatchResult::$skipped` already accounts for device-missing at dispatch time; (c) action-not-found at job runtime is a data consistency event, not an execution outcome — its log warning is the appropriate signal. T23 or a follow-up card may revisit if runtime guard-path observability becomes a product requirement.

**Constatação — `unknown` in practice:** `SmartHomeActionOutcome::Unknown` is a telemetry classifier fail-open and is never emitted by the current production path. The execution log reserves the column value for symmetry and forward compatibility but does not add new code paths that emit it.

No additional `outcome` value is introduced by this ADR.

---

### 3 — Execution event correlation: `scene_execution_id`

`SceneDispatchResult` and `SmartHomeDispatchResult` today return `action_ids` (the IDs of dispatched `scene_actions`) but provide no handle to group all resulting execution rows into one event. Without a correlation key, the only grouping heuristic is `(scene_id, time_window)` — fragile to concurrent executions of the same scene.

**Decision:** `SceneDispatchService` (and `VibeSmartHomeDispatchService`) generate a **UUID** at dispatch time and pass it to each `SceneActionJob` as an additional constructor parameter. The job writes this value as `scene_execution_id` in the execution row.

This is **additive** to `SceneActionJob` — a new nullable `?string $sceneExecutionId` parameter defaulting to `null` (for backward compatibility with any existing serialized jobs in the queue at deploy time). The business logic inside `handle()` is unchanged. ADR-032 D.1 protects `SceneActionJob.php` from *provider-specific* changes; adding an execution-correlation field is orthogonal to provider registration and does not violate D.1.

`SceneDispatchResult` and `SmartHomeDispatchResult` gain a `scene_execution_id: string` field so callers and T22 can reference the event by ID.

---

### 4 — Retention

**Keep records for 90 days. Delete older rows via a scheduled Artisan command.**

| Parameter | Value | Rationale |
| --- | --- | --- |
| Retention window | **90 days** | Covers typical user troubleshooting horizon; aligns with ADR-031 log retention baseline |
| Pruning mechanism | `php artisan smart-home:prune-executions` | Artisan command, not part of the write path — pruning never delays execution or API response |
| Schedule | **Daily, off-peak** (e.g. 03:00 UTC via `schedule()`) | One batch/day; `created_at < NOW() - 90 days` predicate, indexed by `idx_sae_created` |
| Batch size | 1 000 rows per command run, looping until none remain | Avoids lock contention on large tables |
| On failure | Log warning, continue — prune failure does not affect execution recording | Same isolation principle as ADR-023 |

T21 owns implementation. The command exists in `app/Console/Commands/SmartHome/PruneSceneActionExecutionsCommand.php` (new file — not in ADR-032 D.1 frozen list).

Volume estimate: A scene with 5 actions executed twice daily produces 10 rows/day × 90 days = 900 rows. Ten active scenes = 9 000 rows. At scale, `idx_sae_created` keeps DELETE efficient.

---

### 5 — Aggregated state per execution event

Given all `scene_action_executions` rows sharing a `scene_execution_id`, the aggregate state is computed deterministically as:

```
count_success      = COUNT(*) WHERE outcome = 'success'
count_non_success  = COUNT(*) WHERE outcome IN ('failure', 'unsupported', 'unknown')
count_total        = count_success + count_non_success

CASE
  WHEN count_total       = 0  → 'no_actions'
  WHEN count_non_success = 0  → 'success'         -- all actions succeeded
  WHEN count_success     = 0  → 'failure'          -- no action succeeded
  ELSE                          'partial_success'  -- at least one success AND at least one non-success
END
```

No other states exist. T22 implements this aggregation via a single query group-by over `scene_action_executions WHERE scene_execution_id = ?`.

**Provider breakdown in the aggregate:** The API response for an execution event (T22) includes a `by_provider` sub-array: for each distinct `provider` slug present in the event's rows, the count of `success` and non-success outcomes. This is exactly the "2 successes, 1 timeout on Provider C" requirement. The per-action detail (each row) is also available but is a separate, deeper endpoint. Deciding which level the mobile client renders is T22/T26 scope — this ADR declares both must be available.

---

### 6 — API contract impact

`SceneDispatchResult` (and `SmartHomeDispatchResult`) are **dispatch summaries**, not execution results. T22 must add a response note or rename the DTO description to make this boundary explicit. No field change is required in v1.4.0 — the addition of `scene_execution_id` to both DTOs (decision 3) is sufficient to anchor the link.

**New API surface (intent declaration for T22/T26 — not implemented now):**

| Endpoint | Purpose |
| --- | --- |
| `GET /api/scenes/{scene}/executions` | Paginated list of execution events for a scene (most recent first); returns aggregate state + `scene_execution_id` per event |
| `GET /api/scenes/{scene}/executions/{scene_execution_id}` | Detail: aggregate state, `by_provider` breakdown, per-action rows |

These endpoints require `scene_id` → `user_id` authorization (via `ScenePolicy::view`). They never expose `trace_id` to mobile — that field is for operator correlation only.

---

## Out of scope

| Topic | Owner |
| --- | --- |
| Retry policy (`$tries = 3` inertia fix) | T23 |
| Device capabilities | T05 |
| Cross-provider deduplication | T07 |
| Analytics / aggregation beyond 90-day window | v1.5.0 |
| `ActionExecutionLog` on `vibe_device_actions` (historical ADR-016 name) | Superseded by this ADR's `scene_action_executions` model |
| Guard-path exits as execution log entries | Future card if product requires observability of "jobs that couldn't start" |
| Admin Smart Home UI | No admin surface for execution outcomes in v1.4.0 |

---

## Consequences

### Positive

| Outcome | Why it matters |
| --- | --- |
| **Product requirement met** | "2 successes, 1 timeout on Provider C" is computable from `by_provider` group-by on execution rows |
| **No telemetry coupling** | `back_vibes` never reads from Tempo/Loki/Prometheus; telemetry remains write-only from the app tier |
| **T23-compatible** | `attempt` column and nullable `scene_action_id` FK survive retry-enabled execution without schema migration |
| **Outcome vocabulary stable** | No new `SmartHomeActionOutcome` values introduced; execution table reuses exact same four strings |
| **Retention bounded** | 90-day window with indexed pruning keeps table from growing unbounded |

### Negative / tradeoffs

| Tradeoff | Impact |
| --- | --- |
| **Dual write: span + row** | Each successful execution writes both an OTel span and a DB row — two writes per action. Acceptable: the DB write is a simple INSERT on a non-critical-path worker; failure is logged and does not affect the provider call |
| **Guard-path exits not recorded** | "Action not found at job time" events are invisible in the execution log; covered by log warning only. Acceptable for v1.4.0 |
| **`scene_execution_id` must propagate** | New UUID parameter threads through dispatch service → job constructor → execution row. One-time additive change; no business logic branch |

---

## Alternatives considered

| Alternative | Why not chosen |
| --- | --- |
| **Read outcomes from OTel spans (Tempo)** | Requires `back_vibes` to read from observability backend — violates ADR-028 isolation; Tempo is not queryable by user-owned entity ID |
| **`last_outcome` field on `SceneAction`** | Loses history; cannot represent per-execution, per-provider breakdown |
| **`outcome` field on `scenes`** | Even coarser than per-action aggregate; no per-action or per-provider detail |
| **Use `schedule_executions.log` JSON column** | Only covers scheduled dispatch, not manual scene execution; conflates recurrence audit with action outcome |
| **New `SmartHomeActionOutcome::Skipped` value** | Would require coordinating a vocabulary change across telemetry class dependency rules, tests, and span attributes — disproportionate cost for guard-path coverage not yet required by product |

---

## Related docs

| Document | Relationship |
| --- | --- |
| [`ADR-032`](ADR-032-multi-provider-scope.md) | Multi-provider scope — D.1 (files protected from provider-specific changes); execution recording is additive, orthogonal to D.1 |
| [`specs/smart-home/multi-provider/current-state.md`](../specs/smart-home/multi-provider/current-state.md) | T01 — confirms `SceneDispatchResult` is enqueue-only; no execution outcome table exists today |
| [`specs/smart-home/multi-provider/adr-conformance.md`](../specs/smart-home/multi-provider/adr-conformance.md) | T03 — confirms `$tries = 3` inert; schema must accommodate future retry attempts |
| [`ADR-016`](ADR-016-smart-home-async-execution.md) | Anticipated `ActionExecutionLog`; this ADR delivers it under the v1.3.0 Scene model name |
| [`ADR-023`](ADR-023-automation-execution-order-and-failure-policy.md) | Execution isolation policy — failure of one action must not block others; preserved by per-row independent writes |
| [`ADR-028`](ADR-028-observability-platform.md) | Observability platform — `back_vibes` writes to Collector only; never reads from Tempo/Loki |

---

When T23 ships retry policy, amend this ADR or add a follow-up note documenting how `attempt > 1` rows affect the aggregate state rule (e.g. whether the aggregate considers only the final attempt per action or all attempts).
