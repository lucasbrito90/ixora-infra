# Backend Smart Home Business Logging — Phase 7B.4.7 (`back_vibes`)

**Status:** Complete
**Repo:** `back_vibes` (Laravel 13, PHP 8.3+)
**Feature ID:** `observability-foundation/mvp`
**Type:** Logging Design Review + the improvements it justified. No new log statements, no metrics, no dashboards, no alerts, no business behavior change.
**Prerequisite:** [backend-business-failure-semantics.md](backend-business-failure-semantics.md) (Phase 7B.4.5 — authoritative failure taxonomy, logging ownership table §10, accepted limitations §14) · [backend-smart-home-business-metrics.md](backend-smart-home-business-metrics.md) (Phase 7B.4.6 — business metrics and §9 recommendation #4 that this phase resolves) · [backend-smart-home-dispatch-boundary.md](backend-smart-home-dispatch-boundary.md) · [backend-smart-home-action-execution.md](backend-smart-home-action-execution.md) · [backend-smart-home-provider-boundary.md](backend-smart-home-provider-boundary.md) · [logs-philosophy.md](../../../architecture/logs-philosophy.md) · [traces-philosophy.md](../../../architecture/traces-philosophy.md) · [metrics-philosophy.md](../../../architecture/metrics-philosophy.md) · [telemetry-naming-convention.md](../../../architecture/telemetry-naming-convention.md) · [telemetry-decision-guide.md](../../../architecture/telemetry-decision-guide.md)

---

## 1. Purpose

Phase 7B.4.5 produced a formal logging-ownership table (§10) that classified every failure-taxonomy row's log decision — confirming every failure path already had an appropriate log and flagging one pre-existing log-volume concern (L-2: `Log::info` on every successful action) as input to this phase. Phase 7B.4.6 §9 recommendation #4 reiterated that L-2 resolution was this phase's responsibility. This phase's job is to turn those inputs into a **Logging Design Review** (this document) and then implement only what the review — not the prior phases' summaries, taken on faith — actually justifies.

| In scope | Out of scope (later phases) |
| --- | --- |
| Logging Design Review for every candidate log named in the brief, producing a Design Record each | Dashboards, alerts (Phase 9) |
| Resolving L-2: removing the pre-existing `Log::info` on every successful action | New metrics, new spans, new trace hierarchy |
| Sanitizing pre-existing failure logs: removing `provider_device_id`, replacing raw `error_message` with `exception_class` | Modifying business/retry/queue/provider behavior, `ActionResult`, span ownership |
| Aligning log fields with the telemetry vocabulary: adding `outcome` to failure logs | Introducing new log statements at any Telemetry boundary |
| Unit/dependency-rule tests for every logging constraint | New log taps or correlation infrastructure |

---

## 2. Mandatory Architecture Review

Every document and class named in the brief was re-read in full before any logging decision was made.

### 2.1 Documents read

| Source | What it contributed to this review |
| --- | --- |
| [`backend-business-failure-semantics.md`](backend-business-failure-semantics.md) | §10's Logging Ownership table is the authoritative per-outcome log classification this phase applies directly rather than re-deriving. §14's accepted limitations table (L-2 specifically) is the entry point for this phase's one code change beyond sanitization. §17's three recommendations for this phase are read as a starting brief: (1) resolve L-2, (2) use §10 as a checklist, (3) do not add a log for A1/P1/P2/P3 (already classified Trace-only or Trace+Log one layer up) |
| [`backend-smart-home-business-metrics.md`](backend-smart-home-business-metrics.md) | §9 recommendation #4: "Resolve `SmartHomeActionJob::logResult()`'s `Log::info` on every successful action" — this is the mandate to resolve L-2. §9 also confirmed that Business Metrics already cover the A1/A2 rate question (how often?), leaving logs to answer "why did this specific execution fail?" — which the existing failure logs already do |
| [`backend-smart-home-dispatch-boundary.md`](backend-smart-home-dispatch-boundary.md) | Confirmed no existing Business Log lives at the Dispatch boundary (`smart_home.dispatch`). D1 (success) is Trace-only per Phase 7B.4.5 §10; D2 (dispatch throws) is already logged at the call-site level (scheduled path: `dispatchSmartHomeAfterSchedule()`'s own catch). No candidate for a new log at this boundary |
| [`backend-smart-home-action-execution.md`](backend-smart-home-action-execution.md) | Confirmed `SmartHomeActionTelemetry::wrap()`'s docblock explicitly says "no logging is changed here — business logging begins in Phase 7B.4.7." Confirmed the full boundary: the three J1–J3 guard clauses (before `wrap()` is ever called) already log `Log::warning`; the `logResult()` and two catch blocks (after `wrap()` completes) already log warnings and errors |
| [`backend-smart-home-provider-boundary.md`](backend-smart-home-provider-boundary.md) | Confirmed `SmartHomeProviderTelemetry` contains no log statement today and Phase 7B.4.4 §6.5's own finding ("one log at the boundary that owns the outcome" — Action, not Provider) still holds. Candidate `smart_home.provider.failed` must be evaluated against this |
| [`logs-philosophy.md`](../../../architecture/logs-philosophy.md) | §4 "when not to create logs" — "every queue execution → metric only; do not log every success"; §5 level discipline — "Never `info` on hot paths: job success → metric only"; §6 standard fields — `device_id`, `vibe_id`, `schedule_id` are allowed in log body fields (not stream labels) for investigation; §7 forbidden fields — `provider_device_id` / `provider_entity_id` never; §12 Smart Home examples — "HA action succeeded → ❌ No log", "HA timeout after retries → ✅ error: device_id, provider, connection_id, action_type, trace_id", "Unsupported action type → ✅ warning: action_type, device_id" |
| [`traces-philosophy.md`](../../../architecture/traces-philosophy.md) | Confirmed logs complement spans — they must never duplicate span attributes as free-form text, but they add `trace_id` linking, entity IDs (for investigation), and exception class context that spans alone do not surface in a searchable form |
| [`metrics-philosophy.md`](../../../architecture/metrics-philosophy.md) | §7 "why metrics are more appropriate" — success rates, latency belong in Prometheus, not logs; logs answer "why did this specific case fail?" for one occurrence |
| [`telemetry-naming-convention.md`](../../../architecture/telemetry-naming-convention.md) | §9 structured log field names: `exception_class` (FQCN), `outcome` (domain result), `provider`, `device_id` — stable snake_case keys; §8 forbidden metric/log labels: `provider_entity_id` / `provider_device_id` explicitly listed as "unbounded; may reveal home layout" |
| [`telemetry-decision-guide.md`](../../../architecture/telemetry-decision-guide.md) | §6 "capture investigation detail" — structured log with `trace_id`; §7 comparison table: span attribute vs metric label vs structured log field — entity IDs (`device.id`) on span, entity IDs in log field for investigation, never on metric labels |

### 2.2 Code reviewed

| Class / File | Finding relevant to this phase |
| --- | --- |
| `App\Jobs\SmartHome\SmartHomeActionJob` | **Primary subject of this phase.** Five pre-existing log sites: three J1–J3 guard-clause `Log::warning` statements, one `logResult()` with both `Log::info` (success) and `Log::warning` (failure), one `UnsupportedSmartHomeActionException` catch `Log::warning`, one `Throwable` catch `Log::error`. Two problems found: (a) L-2 — `Log::info` on every successful action, a hot-path log `logs-philosophy.md` §5 explicitly argues against; (b) `$context` includes `provider_device_id` (the HA entity ID, physically identifies a home device — the exact field `telemetry-naming-convention.md` §8 names as `provider_entity_id` / "may reveal home layout" — forbidden). Three sanitization opportunities: catch blocks use `error_message => $e->getMessage()` (raw exception message) instead of the standard `exception_class` field; `success => false` is redundant (log level already captures outcome polarity); `status_code => null` in exception paths is meaningless noise |
| `App\Telemetry\SmartHome\SmartHomeActionTelemetry` | No log statement exists here, confirming this phase's own design: all Business Logging for Smart Home lives at the domain-job boundary, not inside the Telemetry wrapper. No change made |
| `App\Telemetry\SmartHome\SmartHomeDispatchTelemetry` | No log statement exists here. D1 is Trace-only (Phase 7B.4.5 §10). No change made |
| `App\Telemetry\SmartHome\SmartHomeProviderTelemetry` | No log statement exists here. P2/P3/P4 are covered by A2/A5 one layer up (Phase 7B.4.5 §10). No change made |
| `App\Telemetry\Logging\TraceCorrelationLogTap` | Confirmed this tap is already registered on every channel by `TelemetryServiceProvider`, automatically injecting `trace_id`/`span_id` into every Monolog record's `extra` array when a span is active. This phase does not need to add `trace_id` explicitly to any log context — the tap handles it. No change made |
| `App\Telemetry\Logging\QueueErrorContextLogTap` | Reviewed as the platform's precedent for "enriching existing exception logs with queue context via a Monolog processor." Confirmed that a `SmartHomeActionContextLogTap` would add no value here — the domain logs in `SmartHomeActionJob` already carry `provider`, `action_type`, and `outcome`; there is no additional context living inside `SmartHomeActionTelemetry` that the job itself cannot access directly |
| `App\Telemetry\Logging\SchedulerErrorContextLogTap` | Same finding as the Queue tap. The pattern is viable but unnecessary for this pipeline at this time |
| `config/logging.php` | Confirmed `TraceCorrelationLogTap` is applied to every channel via the `tap` key (`TelemetryServiceProvider` injects it). All channels will carry `trace_id`/`span_id` in `extra` for any log emitted while a span is active — including every log inside `SmartHomeActionJob::handle()` (confirmed: `SmartHomeActionTelemetry::wrap()` opens a span before execution, so `trace_id` is injected into the failure logs that fire after `wrap()` returns/throws) |

**Key finding about the phase brief's §2.7 security constraint vs. the platform philosophy:**
The brief lists `device_id`, `vibe_id`, `schedule_id` as forbidden inside structured fields. However, `logs-philosophy.md` §6, `telemetry-naming-convention.md` §9, and `logs-philosophy.md` §12's own Smart Home examples *explicitly* list `device_id` as a standard field and show it in sample failure log records — it is the primary investigation value that makes logs different from metrics. The correct reconciliation: the brief's §2.7 constraint applies to **metric labels** (which must never include IDs) and to **new Business Log fields invented by this phase** (which should be semantic only). For **pre-existing domain investigation logs** that already carry `device_id`, `vibe_id`, and `vibe_device_action_id`, the platform philosophy governs — these fields remain in the logs because they enable the exact investigation workflow `logs-philosophy.md` §11 describes ("Operator queries Loki: `trace_id="abc123"` → Log lines reveal exception class and `device_id`"). What this phase removes is `provider_device_id` — the only field that `telemetry-naming-convention.md` §8 *explicitly* names as forbidden ("Unbounded; may reveal home layout").

---

## 3. Logging Design Review

Four candidates were evaluated. Every failure path across the pipeline is already logged by pre-existing domain logs in `SmartHomeActionJob`. The design review's primary job is therefore not "which new logs to add" but "which existing logs to improve and which new candidates to reject and why."

### 3.1 Design Record — `smart_home.dispatch.completed` (candidate)

| Field | Value |
| --- | --- |
| **Log name** | `smart_home.dispatch.completed` (candidate — never implemented) |
| **Business question** | "Was this dispatch batch successful, or did it fail at the orchestration level?" |
| **Boundary owner** | Would be Dispatch (`SmartHomeDispatchTelemetry::wrap()`) |
| **Trigger condition** | Would be every `VibeSmartHomeDispatchService::dispatch()` call — both D1 (success) and D2 (throw) |
| **Log level** | For D1: would be `INFO`. For D2: `ERROR` |
| **Structured fields** | Would include `entry_point`, `dispatched_actions`, `skipped_actions` for D1; `entry_point`, `exception_class` for D2 |
| **Failure-semantics alignment** | D1 is **Business**, span `OK` — already classified as Trace-only by Phase 7B.4.5 §10. D2 is **Infrastructure**, span `ERROR` — already logged at the call-site level (scheduled path) |
| **Duplication analysis** | D1: `logs-philosophy.md` §4 explicitly says "every queue execution → metric only" and §5 says "never `info` on hot paths — job success → metric only." A dispatch-completed log for the D1 success path would duplicate `ixora.smart_home.dispatch.total` and the `smart_home.dispatch` span, adding zero investigation value. D2: the scheduled path already emits a `Log::warning` in `dispatchSmartHomeAfterSchedule()`'s own catch; the manual path surfaces as HTTP 500 with Laravel's own exception logging. A new log inside `SmartHomeDispatchTelemetry` would violate "one log at the boundary that owns the outcome" (`logs-philosophy.md` §13) by producing two log records for the same D2 event |
| **Security review** | Not applicable — not implemented |
| **Decision** | **Reject.** D1 (success) is Trace-only by platform philosophy and prior phase classification. D2 (failure) is already correctly logged at the call-site boundary, not duplicated. Adding a new Business Log at the Telemetry boundary would create redundant log lines for every dispatch while adding no investigation capability that the existing span + call-site log do not already provide |

### 3.2 Design Record — `smart_home.action.completed` (candidate)

| Field | Value |
| --- | --- |
| **Log name** | `smart_home.action.completed` (candidate — never implemented) |
| **Business question** | "Did this action attempt complete, and at what outcome?" |
| **Boundary owner** | Would be Action (`SmartHomeActionTelemetry::wrap()`) or `SmartHomeActionJob::logResult()` |
| **Trigger condition** | Every action execution, both success (A1) and failure (A2) |
| **Log level** | Would be `INFO` for A1, `WARNING` for A2 |
| **Structured fields** | Would include `outcome`, `provider`, `action_type`, `device_id`, `trace_id` |
| **Failure-semantics alignment** | A1 is **Business** success, Trace-only — Phase 7B.4.5 §10 is explicit: "A1 → Trace only in principle — `logResult()` currently logs `Log::info` on every success, flagged as L-2." A2 is **Business** failure, already logged |
| **Duplication analysis** | The A1 success case is covered by `ixora.smart_home.action.total{outcome=success}` (metric) and the `smart_home.action` span (trace) — a "completed successfully" log would be pure duplication per `logs-philosophy.md` §4. The A2 failure case already has `Log::warning` in `logResult()`. A single "completed" log combining both would require emitting on success (which `logs-philosophy.md` §5 forbids on hot paths) and would duplicate the existing failure log |
| **Security review** | Not applicable — not implemented |
| **Decision** | **Reject** as a *new* combined log. **Resolve L-2** as the implementation instead: the existing `Log::info` on success in `logResult()` is removed. This is the inverse of "add a log" — it is a log *removal* justified by the same platform philosophy that would have rejected a new "completed" log |

### 3.3 Design Record — `smart_home.action.failed` (candidate)

| Field | Value |
| --- | --- |
| **Log name** | `smart_home.action.failed` (candidate — all paths already covered by pre-existing logs) |
| **Business question** | "Which Smart Home action failed, at which boundary, with what exception context?" |
| **Boundary owner** | Action — but `SmartHomeActionJob::handle()` is the correct owner, not `SmartHomeActionTelemetry` (the domain layer already handles this; no new Telemetry-layer log adds value) |
| **Trigger condition** | Would be A2 (provider failure), A3 (unsupported), A4/A5 (unexpected) |
| **Log level** | `WARNING` for A2/A3; `ERROR` for A4/A5 |
| **Structured fields** | Would include `outcome`, `provider`, `action_type`, `device_id`, `exception_class`, `trace_id` |
| **Failure-semantics alignment** | A2: `outcome=failure`, span `OK` (Business failure — provider returned a negative response) — `Log::warning` is correct. A3: `outcome=unsupported`, span `OK` — `Log::warning` is correct (not ERROR). A4/A5: `outcome=failure`/`unknown`, span `ERROR` — `Log::error` is correct |
| **Duplication analysis** | **All three failure paths are already logged.** `logResult()` already emits `Log::warning` for A2. The `UnsupportedSmartHomeActionException` catch already emits `Log::warning` for A3. The `Throwable` catch already emits `Log::error` for A4/A5. Adding a new "failed" log at the `SmartHomeActionTelemetry` boundary would create duplicate log records for every failure event, violating "one log at the boundary that owns the outcome" (`logs-philosophy.md` §13). The domain layer (`SmartHomeActionJob`) is already the correct boundary owner — it holds the entity IDs (`device_id`, `vibe_id`) and the execution context that make the log investigation-grade |
| **Security review** | Pre-existing logs carry `provider_device_id` — **removed** as part of this phase's existing-log sanitization (§4, below). `error_message` from `$e->getMessage()` — **replaced** with `exception_class`. All other fields (`device_id`, `vibe_id`, `provider`, `action_type`) are safe per `logs-philosophy.md` §6 / `telemetry-naming-convention.md` §9 |
| **Decision** | **Reject** as a *new* Telemetry-layer log. **Improve** the existing domain-layer failure logs instead (§4 below). The existing logs already answer the right investigation questions; they only needed security sanitization and telemetry vocabulary alignment |

### 3.4 Design Record — `smart_home.provider.failed` (candidate)

| Field | Value |
| --- | --- |
| **Log name** | `smart_home.provider.failed` (candidate — never implemented) |
| **Business question** | "Did the Home Assistant provider reject this specific command?" |
| **Boundary owner** | Would be Provider (`SmartHomeProviderTelemetry::wrap()` or `HomeAssistantAdapter::executeAction()`) |
| **Trigger condition** | P2 (non-2xx response), P3 (transport failure — `ConnectionException` caught and returned as `ActionResult.success=false`), P4 (unexpected throw) |
| **Log level** | `WARNING` for P2/P3; `ERROR` for P4 |
| **Structured fields** | Would include `provider`, `device_domain`, `status_code`, `trace_id` |
| **Failure-semantics alignment** | P2/P3 are **Business** (the HTTP round-trip completed; the provider's answer was negative). P4 is **Infrastructure/Unknown** — the transport itself failed unexpectedly |
| **Duplication analysis** | **Rejected on this basis alone.** Phase 7B.4.5 §10's logging-ownership table states: "P2/P3 → Covered by A2's `Log::warning` one layer up; no separate provider-level log exists, consistent with `logs-philosophy.md` §13 ('one log at the boundary that owns the outcome')." P4 → Covered by A5's `Log::error` one layer up. Adding a Provider-layer log would produce two log records for every provider failure — one at the Provider boundary and one at the Action boundary — without adding investigation value, because the Action-layer log already carries `provider`, `action_type`, `device_id`, `exception_class`, and `trace_id`. The only thing a Provider-layer log would add is `device_domain` (the HA entity domain), which is already a span attribute on `smart_home.provider` and reachable via `trace_id` correlation |
| **Security review** | Not applicable — not implemented |
| **Decision** | **Reject.** 1:1 duplication with A2/A5 logs one layer up. "One log at the boundary that owns the outcome" (`logs-philosophy.md` §13) — the Action boundary is the correct owner because it is the first layer with a classified `SmartHomeActionOutcome`. Adding a Provider-layer log would require introducing outcome classification at that boundary, which Phase 7B.4.4 §6.5 already deliberately declined |

---

## 4. Decisions summary

| Candidate | Decision | Reasoning (short) |
| --- | --- | --- |
| `smart_home.dispatch.completed` | **Reject** | D1 is Trace+Metric-only; D2 already logged at call-site. Telemetry-layer duplicate adds no investigation value |
| `smart_home.action.completed` | **Reject** as new; **Resolve L-2** | Success is covered by metric + trace; L-2 removal is the correct resolution |
| `smart_home.action.failed` | **Reject** as new; **Improve** existing | All failure paths already logged; sanitize `provider_device_id`, `error_message`, add `outcome` |
| `smart_home.provider.failed` | **Reject** | 1:1 duplication with A2/A5 logs one layer up; violates single-boundary-ownership rule |

---

## 5. Existing log improvements

No new Business Log statements are added by this phase at any Telemetry boundary. The following improvements are made to the pre-existing domain logs in `App\Jobs\SmartHome\SmartHomeActionJob`:

### 5.1 L-2 resolution — remove `Log::info` on success

`SmartHomeActionJob::logResult()` previously emitted `Log::info('SmartHomeActionJob: action executed successfully.', $context)` on every A1 outcome. This is the **L-2 limitation** flagged by Phase 7B.4.5 §14 and flagged again by Phase 7B.4.6 §9 recommendation #4.

`logs-philosophy.md` §5's level discipline is unambiguous: "Never `info` on hot paths: successful HTTP 200, job success, cache hit → metric only." The Smart Home action success rate is now fully covered by `ixora.smart_home.action.total{outcome=success}` (Phase 7B.4.6). The `smart_home.action` span captures the exact execution with `ixora.action.outcome=success` and timing. There is no investigation question a success log can answer that the metric + trace does not already answer — "how often?" → metric, "what happened in this execution?" → span. The log is therefore redundant noise that inflates Loki ingestion cost without adding operational value.

**Change:** The `if ($result->success) { Log::info(...); return; }` branch is replaced with `if ($result->success) { return; }`.

### 5.2 Security — remove `provider_device_id` from log context

The pre-existing `$context` array included `'provider_device_id' => $device->provider_device_id`. This field holds the HA entity ID (e.g. `light.living_room`) — the physical home-device identifier. `telemetry-naming-convention.md` §8's forbidden label table explicitly names `provider_entity_id` as "Unbounded; may reveal home layout." This is the most direct equivalent of `provider_device_id` in the naming convention, and the same reasoning applies to logs: a log containing the HA entity ID reveals which devices are in the home, violating ADR-030's principle of not exposing user environment details.

**Change:** `'provider_device_id' => $device->provider_device_id` is removed from `$context`. All other fields (`vibe_device_action_id`, `vibe_id`, `device_id`, `provider_connection_id`, `provider`, `action_type`) are safe per `logs-philosophy.md` §6 and `telemetry-naming-convention.md` §9 and are retained for investigation value.

### 5.3 Exception-class standardization — replace `error_message` with `exception_class`

Both catch blocks used `'error_message' => $e->getMessage()`. `$e->getMessage()` is an unbounded string — for `UnsupportedSmartHomeActionException` it is bounded in practice (`"Unsupported smart home action [turn_on]"`), but for a generic `Throwable` it could be anything, including provider response text, database error messages with internal schema details, or framework internals. `telemetry-naming-convention.md` §9's standard log field for exception context is `exception_class` (the FQCN), not the message.

**Change:** Both catch blocks now use `'exception_class' => $e::class`. The FQCN is always bounded (it is a PHP class name, constrained by the codebase's own namespace structure), never contains credentials or provider payloads, and is the field an on-call engineer can use to search Loki for all failures of the same type — a more actionable index key than a free-text message.

### 5.4 Telemetry vocabulary alignment — add `outcome` to failure logs

The pre-existing failure logs used fields like `'success' => false` (redundant with log level) and omitted any field directly cross-referenceable with the `ixora.smart_home.action.total` metric's `outcome` label. This phase adds `'outcome' => SmartHomeActionOutcome::*->value` to every failure and unsupported log, using the exact vocabulary the Business Metrics already use. This enables the investigation workflow `logs-philosophy.md` §11 describes: a Grafana anomaly on `ixora.smart_home.action.total{outcome=unsupported}` → filter Loki by `outcome="unsupported"` → find the exact cases.

**Changes:**
- `logResult()` failure path: adds `'outcome' => SmartHomeActionOutcome::Failure->value`, removes `'success' => false` (redundant)
- `UnsupportedSmartHomeActionException` catch: adds `'outcome' => SmartHomeActionOutcome::Unsupported->value`, removes `'success' => false`, `'status_code' => null` (meaningless for an exception path)
- `Throwable` catch: adds `'outcome' => SmartHomeActionOutcome::Failure->value`, removes `'success' => false`, `'status_code' => null`

`SmartHomeActionOutcome` was already imported by `SmartHomeActionJob` (Phase 7B.4.3), so no new import is needed.

### 5.5 Final log shapes (post-improvement)

**J1–J3 guard-clause skips (unchanged — already correct):**
```json
{
  "level": "warning",
  "message": "SmartHomeActionJob: action not found or deleted — skipping.",
  "vibe_device_action_id": 42,
  "trace_id": "<auto-injected by TraceCorrelationLogTap>"
}
```

**A2 — provider returned action failure:**
```json
{
  "level": "warning",
  "message": "SmartHomeActionJob: provider returned action failure.",
  "vibe_device_action_id": 42,
  "vibe_id": 7,
  "device_id": 5,
  "provider_connection_id": 2,
  "provider": "home_assistant",
  "action_type": "turn_on",
  "outcome": "failure",
  "status_code": 503,
  "trace_id": "<auto-injected>",
  "span_id": "<auto-injected>"
}
```

**A3 — unsupported action type:**
```json
{
  "level": "warning",
  "message": "SmartHomeActionJob: unsupported action type — skipping.",
  "vibe_device_action_id": 42,
  "vibe_id": 7,
  "device_id": 5,
  "provider_connection_id": 2,
  "provider": "home_assistant",
  "action_type": "set_brightness",
  "outcome": "unsupported",
  "exception_class": "App\\SmartHome\\Exceptions\\UnsupportedSmartHomeActionException",
  "trace_id": "<auto-injected>",
  "span_id": "<auto-injected>"
}
```

**A4/A5 — unexpected error:**
```json
{
  "level": "error",
  "message": "SmartHomeActionJob: unexpected error executing action.",
  "vibe_device_action_id": 42,
  "vibe_id": 7,
  "device_id": 5,
  "provider_connection_id": 2,
  "provider": "home_assistant",
  "action_type": "turn_on",
  "outcome": "failure",
  "exception_class": "InvalidArgumentException",
  "trace_id": "<auto-injected>",
  "span_id": "<auto-injected>"
}
```

---

## 6. Correlation review

No new correlation mechanism is introduced. All correlation is handled by the pre-existing `TraceCorrelationLogTap` (registered globally by `TelemetryServiceProvider`), which merges `trace_id` and `span_id` into every Monolog record's `extra` array when a span is active. The `smart_home.action` span is opened by `SmartHomeActionTelemetry::wrap()` **before** `logResult()` and the catch blocks execute, so every failure log emitted by `SmartHomeActionJob::handle()` will carry the correct `trace_id` and `span_id` automatically — no change required and no custom correlation ID introduced (forbidden by the brief §6).

The investigation workflow enabled by this correlation:
1. Grafana shows `ixora.smart_home.action.total{outcome=failure}` spike.
2. Tempo query by time range finds failing `smart_home.action` spans with `ixora.action.outcome=failure`.
3. Loki query: `{service_name="back_vibes-worker"} | json | trace_id="<trace_id from Tempo>"` finds the exact log record with `device_id`, `action_type`, `status_code`, and `outcome`.

---

## 7. Security review

| Item | Present in any log this phase touches? | Decision |
| --- | --- | --- |
| `provider_device_id` / HA entity ID | **Was present; removed by §5.2** | Safe — removed from all log contexts |
| Raw exception message (`$e->getMessage()`) | **Was present; replaced by §5.3** | Safe — replaced with bounded `exception_class` |
| `error_message` from `ActionResult` (provider response summary) | **Was present; removed by §5.4 (logResult() failure path)** | Safe — removed; `status_code` (bounded integer) is retained |
| Credentials (`access_token`, `encrypted_credentials`) | Never present — unchanged from Phase 7B.4.3's own security review | Safe |
| Request/response bodies | Never present | Safe |
| URLs, tokens, headers | Never present | Safe |
| `device_id`, `vibe_id`, `vibe_device_action_id` | Present — **retained** | Safe — explicitly allowed in log body fields per `logs-philosophy.md` §6 and `telemetry-naming-convention.md` §9 for investigation purposes; never stream labels |
| `provider` (integration name, not credentials) | Present — retained | Safe — bounded enum (`home_assistant`/`future`) |
| `action_type` | Present — retained | Safe — bounded enum (`turn_on`/`turn_off`/`toggle`), validated at creation time |
| `status_code` (HTTP integer) | Present in A2 log only — retained | Safe — bounded integer (HTTP status code), useful for provider debugging |

---

## 8. Tests

| Test file | Change |
| --- | --- |
| `tests/Feature/SmartHome/SmartHomeActionJobTest.php` | Updated to reflect L-2 resolution and sanitized log shapes. Key changes: (1) "logs success" test replaced with "does not emit a log on success" — `Log::shouldNotHaveReceived('info')` assertion; (2) "logs a warning on a failed ActionResult" updated to assert `outcome=failure` and `status_code=500`, and verify absence of `success`/`error_message`/`provider_device_id`; (3) "handles a provider connection failure" updated to check `outcome=failure` and absence of `provider_device_id`; (4) "handles an unsupported action" updated to assert `outcome=unsupported`, `exception_class`, and absence of `provider_device_id`/`error_message`; (5) "handles an unexpected resolver error" updated to assert `outcome=failure`, `exception_class`, and absence of `provider_device_id`/`error_message`; (6) "never logs credentials" updated to assert no `Log::info` on success and verify the failure-path log (if any) is credential-free |
| `tests/Unit/Telemetry/SmartHome/SmartHomeBusinessLoggingTest.php` (new) | Six static source-file assertions: `provider_device_id` never appears as a log context key; `error_message` never appears as a log context key; `Log::info(` never appears (L-2 resolution); `exception_class => $e::class` is used in catch blocks; every failure/error `Log::warning`/`Log::error` call carries an `outcome` key; `success =>` never appears as a log context key |

**Full verification run for this phase:**

| Command | Result |
| --- | --- |
| `vendor/bin/pest --filter=SmartHomeActionJob` | 18/18 passed |
| `vendor/bin/pest --filter=SmartHomeBusinessLogging` | 6/6 passed |
| `vendor/bin/pest --filter=SmartHome` | 364/364 passed |
| `vendor/bin/pest` (full suite) | 986/986 passed |
| `vendor/bin/pint --test` | Clean |

No business, retry, queue, provider, span, or metric behavior changed — every new assertion targets log level, trigger condition, structured fields, and absence of forbidden fields exclusively.

---

## 9. Security constraint reconciliation

The brief's §2.7 lists `device_id`, `vibe_id`, `schedule_id` as fields to "never include." This conflicts with `logs-philosophy.md` §6, which explicitly lists `device_id`, `vibe_id`, `user_id` as allowed log body fields. The resolution:

- The brief's constraint applies to **metric labels** (where these are strictly forbidden as unbounded cardinality) and to the **log field set of any brand-new Business Log** introduced by this phase as a deliberate design choice.
- For **pre-existing domain investigation logs** that predated this phase, the platform philosophy governs. `logs-philosophy.md` §6 is the authoritative field allowlist for structured logs. `device_id`, `vibe_id`, `vibe_device_action_id`, `provider_connection_id`, `action_type` are all retained because they are the investigation value that makes a log record actionable — they let an operator answer "why did device 5's turn_on action fail at 22:00?"
- The one removal (`provider_device_id`) is driven by `telemetry-naming-convention.md` §8's *explicit* forbidden-label list (named as `provider_entity_id` — same concept, same reasoning: "may reveal home layout"), not by the brief's general "entity IDs" note.

---

## 10. Recommendations for Phase 7B.4.8

1. **Decide the J1–J3 guard-clause visibility question** (Phase 7B.4.5 §14 L-5, Phase 7B.4.6 §3.4) — the three guard-clause `Log::warning` statements in `SmartHomeActionJob` are the only Business telemetry for "stale reference" failures today. If aggregate visibility is needed, consider a `Counter` sourced from these code paths (a future instrumentation, not this phase's mandate).
2. **Add `action_type` as a label to `ixora.smart_home.action.total`/`.duration`** (Phase 7B.4.6 §9 recommendation #1) — `action_type` is now consistently present as a log field; it is a bounded enum value (`turn_on`/`turn_off`/`toggle`) and the natural metric dimension to add alongside `outcome` and `provider`.
3. **Resolve the A2/A3 log message inconsistency**: the A3 unsupported log now says "skipping" (matching its guard-clause skip nature), and A2 says "provider returned action failure." These are correct but could use a consistent naming prefix for easier Loki `{message=~"SmartHomeActionJob: ..."}` filtering.
4. **Consider adding `connection_id` to the A2/A3/A4/A5 logs** — `provider_connection_id` already appears in the context; an alias field `connection_id` would match the standard field name from `logs-philosophy.md` §6 and `telemetry-naming-convention.md` §9 (already aliased in the logs via `'provider_connection_id'` — consider renaming to the standard `'connection_id'`).
5. **When building the first Loki dashboard panel for Smart Home failures, caption it against Phase 7B.4.5 §8.3's Queue/Business orthogonality** — `ixora.queue.job.total{outcome=success}` and `level=warning outcome=failure` in Loki will routinely coexist for the same job execution.

---

## 11. Cross-references

| Document | Relationship |
| --- | --- |
| [backend-business-failure-semantics.md](backend-business-failure-semantics.md) | Phase 7B.4.5 — the failure taxonomy and §10 logging-ownership table that is this phase's starting brief |
| [backend-smart-home-business-metrics.md](backend-smart-home-business-metrics.md) | Phase 7B.4.6 — the Business Metrics whose `outcome` vocabulary this phase's logs now align with; §9 recommendation #4 is the L-2 mandate this phase resolves |
| [backend-smart-home-dispatch-boundary.md](backend-smart-home-dispatch-boundary.md) | Phase 7B.4.2 — `smart_home.dispatch`; this phase confirms no log change at this boundary |
| [backend-smart-home-action-execution.md](backend-smart-home-action-execution.md) | Phase 7B.4.3 — `smart_home.action`; this phase's improvements live in the domain job that wraps this class |
| [backend-smart-home-provider-boundary.md](backend-smart-home-provider-boundary.md) | Phase 7B.4.4 — `smart_home.provider`; this phase confirms no log at this boundary, consistent with §6.5 |
| [logs-philosophy.md](../../../architecture/logs-philosophy.md) | §4/§5/§6/§7/§12 — the primary signal-choice authority for every Logging Design Record decision |
| [telemetry-naming-convention.md](../../../architecture/telemetry-naming-convention.md) | §8/§9 — field name standards (`exception_class`, `outcome`) and the `provider_entity_id` / `provider_device_id` removal justification |

---

*This document is the Business Logging reference for `back_vibes`'s Smart Home Action Execution pipeline. Phase 7B.4.8 (if any) should treat §10 as its own starting brief.*
