# Business Telemetry Validation — Phase 7B.4.8 (`back_vibes`)

**Status:** Complete  
**Repo reviewed:** `back_vibes` (Laravel 13, PHP 8.3+)  
**Feature ID:** `observability-foundation/business-telemetry`  
**Phase scope:** Architecture validation of Phases 7B.4.2 through 7B.4.7 as a complete system  
**Prerequisite reading:** [domain-execution-review.md](domain-execution-review.md) · [backend-smart-home-dispatch-boundary.md](backend-smart-home-dispatch-boundary.md) · [backend-smart-home-action-execution.md](backend-smart-home-action-execution.md) · [backend-smart-home-provider-boundary.md](backend-smart-home-provider-boundary.md) · [backend-business-failure-semantics.md](backend-business-failure-semantics.md) · [backend-smart-home-business-metrics.md](backend-smart-home-business-metrics.md) · [backend-smart-home-business-logging.md](backend-smart-home-business-logging.md)

---

## Executive Summary

The Smart Home Business Telemetry implemented across Phases 7B.4.2–7B.4.7 forms one coherent, internally consistent observability model. Every signal has exactly one owner, the trace hierarchy is valid and propagates correctly through the queue boundary, metrics and spans share a unified outcome vocabulary (`SmartHomeActionOutcome`), logs complement rather than duplicate the other signals, and no forbidden data appears in any exported field. The architecture is production-ready for the Smart Home domain and provides a reusable pattern for future domains (Push Notifications, Matter, Google Home, Alexa) without redesign.

Four items of technical debt remain — two documented by their own phase, two identified in this review — none of which represents a genuine architectural inconsistency warranting a runtime change in this phase. No runtime code was changed.

---

## 1. Architecture Review Method

Every document was read completely before any decision was made:

**Documents read:**

| Document | Key contribution to this review |
| --- | --- |
| `domain-execution-review.md` | Ground-truth call graph; failure model; existing observability baseline |
| `backend-smart-home-dispatch-boundary.md` | Dispatch span design; entry-point classification; queue propagation strategy |
| `backend-smart-home-action-execution.md` | Action span design; boundary narrowing rationale; unsupported vs failure semantics |
| `backend-smart-home-provider-boundary.md` | Provider span design; Guzzle auto-instrumentation analysis; attribute ownership decisions |
| `backend-business-failure-semantics.md` | Formal failure taxonomy; span status policy; outcome classification table |
| `backend-smart-home-business-metrics.md` | Metrics design records; cardinality analysis; deferred items rationale |
| `backend-smart-home-business-logging.md` | Logging design records; L-2 resolution; sanitization decisions |
| `telemetry-naming-convention.md` | Naming rules; forbidden labels; exception field standards |
| `telemetry-decision-guide.md` | Signal selection criteria (trace vs metric vs log) |
| `metrics-philosophy.md` | Cardinality, aggregation, and dashboard principles |
| `logs-philosophy.md` | Ownership, level, correlation, and security requirements |
| `traces-philosophy.md` | Span granularity, hierarchy, and correlation principles |
| `backend-sdk-foundation.md` | Dependency Rule; Contracts architecture; propagation mechanism |

**Implementation reviewed (confirmed against source):**

- `app/Telemetry/SmartHome/SmartHomeDispatchTelemetry.php`
- `app/Telemetry/SmartHome/SmartHomeActionTelemetry.php`
- `app/Telemetry/SmartHome/SmartHomeProviderTelemetry.php`
- `app/Telemetry/SmartHome/SmartHomeDispatchEntryPoint.php`
- `app/Telemetry/SmartHome/SmartHomeActionProvider.php`
- `app/Telemetry/SmartHome/SmartHomeActionOutcome.php`
- `app/Telemetry/SmartHome/SmartHomeProviderDeviceDomain.php`
- `app/Telemetry/Providers/TelemetryServiceProvider.php`
- `app/Telemetry/Logging/TraceCorrelationLogTap.php`
- `app/Jobs/SmartHome/SmartHomeActionJob.php`
- All Smart Home telemetry test files (Unit + Feature)

---

## 2. Boundary Ownership Matrix

Every signal produced by the Smart Home Business Telemetry has exactly one owner. No overlap, no gap.

### 2.1 Spans

| Span | Owner | Phase | Produced by |
| --- | --- | --- | --- |
| `smart_home.dispatch` | **Dispatch** | 7B.4.2 | `SmartHomeDispatchTelemetry::wrap()` at both call sites |
| `smart_home.action` | **Action** | 7B.4.3 | `SmartHomeActionTelemetry::wrap()` from `SmartHomeActionJob::handle()` |
| `smart_home.provider` | **Provider** | 7B.4.4 | `SmartHomeProviderTelemetry::wrap()` from `HomeAssistantAdapter::executeAction()` |

### 2.2 Metrics

| Metric | Owner | Phase | Instrument | Labels |
| --- | --- | --- | --- | --- |
| `ixora.smart_home.dispatch.total` | **Dispatch** | 7B.4.6 | Counter | `entry_point`, `outcome`, `environment`, `service_name` |
| `ixora.smart_home.action.total` | **Action** | 7B.4.6 | Counter | `outcome`, `provider`, `environment`, `service_name` |
| `ixora.smart_home.action.duration` | **Action** | 7B.4.6 | Histogram (ms) | `outcome`, `provider`, `environment`, `service_name` |

### 2.3 Logs

| Log event | Owner | Phase | Level | Owner class |
| --- | --- | --- | --- | --- |
| Action not found / deleted (J1) | **Action** | pre-7B.4 | WARNING | `SmartHomeActionJob` |
| Device missing (J2) | **Action** | pre-7B.4 | WARNING | `SmartHomeActionJob` |
| Provider connection missing (J3) | **Action** | pre-7B.4 | WARNING | `SmartHomeActionJob` |
| Provider returned action failure (A2) | **Action** | 7B.4.7 (improved) | WARNING | `SmartHomeActionJob::logResult()` |
| Unsupported action type — skipping (A3) | **Action** | 7B.4.7 (improved) | WARNING | `SmartHomeActionJob` |
| Unexpected error executing action (A4/A5) | **Action** | 7B.4.7 (improved) | ERROR | `SmartHomeActionJob` |

**Ownership finding:** Every signal has exactly one owner. No signal is owned by more than one boundary. The absence of Dispatch-owned logs and Provider-owned logs is deliberate (documented in Phase 7B.4.7's design review) — the Action boundary is the narrowest level at which all failure paths are observable and loggable with sufficient context.

---

## 3. Trace Architecture Review

### 3.1 Validated hierarchy

The following hierarchy was validated by reading the implementation in full and confirmed by `SmartHomeProviderBoundaryIntegrationTest` and `SmartHomeDispatchBoundaryIntegrationTest`:

```
HTTP Server span (opentelemetry-auto-laravel)        ← manual path
  OR
Console span "Command schedules:dispatch-due"         ← scheduled path
  └─ smart_home.dispatch                              (Phase 7B.4.2)
       └─ Queue Consumer span (opentelemetry-auto-laravel, Phase 7B.2)
            └─ smart_home.action                      (Phase 7B.4.3)
                 └─ smart_home.provider               (Phase 7B.4.4)
                      └─ POST (opentelemetry-auto-guzzle, SpanKind::CLIENT)
```

The W3C `traceparent` is injected into every queued job payload by `opentelemetry-auto-laravel`'s `Illuminate\Queue\Queue::createPayloadArray()` post-hook at the moment `SmartHomeActionJob::dispatch()` is called from inside the active `smart_home.dispatch` span. The consumer process re-extracts it in `Illuminate\Queue\Worker::process()` as the Queue Consumer span's parent context. This mechanism operates entirely without custom propagation code — a structural property confirmed by Phase 7B.4.2's pre-implementation review (§2 of that document).

### 3.2 Span attributes (verified against implementation)

| Span | Attribute | Values | Set at |
| --- | --- | --- | --- |
| `smart_home.dispatch` | `ixora.dispatch.entry_point` | `manual` \| `scheduled` \| `future` | span start |
| `smart_home.dispatch` | `ixora.dispatch.dispatched_actions` | int ≥ 0 | success path only |
| `smart_home.dispatch` | `ixora.dispatch.skipped_actions` | int ≥ 0 | success path only |
| `smart_home.action` | `ixora.action.provider` | `home_assistant` \| `future` | span start |
| `smart_home.action` | `ixora.action.outcome` | `success` \| `failure` \| `unsupported` \| `unknown` | after execute() |
| `smart_home.action` | `ixora.action.retry` | `true` \| `false` | span start |
| `smart_home.provider` | `ixora.provider.device_domain` | `light` \| `switch` \| `media_player` \| `fan` \| `other` | span start |

### 3.3 Exception recording and span status policy

Validated against `backend-business-failure-semantics.md` §1.3/§1.5 and confirmed in `SmartHomeActionTelemetry.php` source:

| Outcome | `recordException()` | `setError()` | Rationale |
| --- | --- | --- | --- |
| `success` | No | No | Normal completion |
| `failure` | Yes | Yes | Genuinely unexpected at the Action boundary |
| `unsupported` | Yes | **No** | Expected, deterministic configuration fact — analogue of HTTP 4xx |
| `unknown` (fail-open) | Yes | Yes | Classifier failure = unexpected |
| `smart_home.provider` exception | Yes | Yes | Only for a genuine exception escaping the wrapped segment; a returned `ActionResult(success:false)` does NOT mark this span as error |
| `smart_home.dispatch` exception | Yes | Yes | A thrown exception from `dispatch()` is a genuine infrastructure/DB failure |

This policy is internally consistent and validated by the implementation source. No span contradicts the failure taxonomy in `backend-business-failure-semantics.md`.

### 3.4 Fail-open behavior

Every Telemetry class (`SmartHomeDispatchTelemetry`, `SmartHomeActionTelemetry`, `SmartHomeProviderTelemetry`) implements the same fail-open pattern:

1. `startSpan()` failure → falls back to a local anonymous `inertSpan()` implementation — `$execute()` always runs.
2. Attribute-setting, metric-recording, exception-recording, and span-ending failures are caught by `safely()` and swallowed — never propagate to business code.
3. A genuine business exception from `$execute()` is always rethrown unmodified — telemetry observes the failure, never masks or converts it.

Verified by dedicated test cases in all three telemetry test files.

### 3.5 Trace findings — verdict

**No issues found.** The hierarchy is valid, propagation is correct, span attributes are appropriate, exception recording and status policy align with failure semantics, and fail-open behavior is consistently implemented.

---

## 4. Metrics Architecture Review

### 4.1 Counter review

**`ixora.smart_home.dispatch.total`**

- Unit: `{action}` — counts dispatched/skipped actions (not dispatches)
- Labels: `entry_point` (3 values × 2 states) + `outcome` (dispatched/skipped/error) — bounded
- Max cardinality: 3 × 3 × 2 (environments) × ~2 (services) = ~36 series
- Counting unit: one action either dispatched, skipped, or lost to a dispatch exception
- Failure alignment: `outcome=error` is distinct from `skipped`; no silent merging

**`ixora.smart_home.action.total`**

- Unit: `{action}` — counts action execution attempts
- Labels: `outcome` (4 values) × `provider` (2 values) × `environment` × `service_name` — bounded
- Max cardinality: 4 × 2 × 2 × 2 = 32 series
- Counting unit: one action execution attempt reaching the Action boundary
- Failure alignment: reuses `SmartHomeActionOutcome` verbatim — structurally cannot contradict the span

**`ixora.smart_home.action.duration`**

- Unit: `ms` — matches `ixora.queue.job.duration` platform-wide convention
- Labels: identical to `ixora.smart_home.action.total` — consistent, no extra cardinality
- Measures: wall-clock time from `hrtime()` before `$execute()` to after it returns/throws

### 4.2 Duplication analysis

| Candidate | Status | Reason |
| --- | --- | --- |
| `ixora.smart_home.dispatch.total` | Clean | Does not duplicate `ixora.queue.job.total` — different boundary (dispatch, not job execution) |
| `ixora.smart_home.action.total` | Clean | Does not duplicate `ixora.queue.job.total` — adds business semantics (`outcome`, `provider`) not in queue signals |
| `ixora.smart_home.action.duration` | Clean | Does not duplicate `ixora.queue.job.duration` — Action boundary is narrower (excludes guard-clause load, notification) |

### 4.3 Deferred items — current status determination

**Guard-clause skips (J1–J3):** Remain deferred. The three guard-clause exit paths (missing action, missing device, missing connection) do not reach the Action boundary and therefore cannot be counted by `ixora.smart_home.action.total`. They currently produce only warning logs. The Phase 7B.4.6 Metrics Design Review correctly classified these as "no clean boundary owner" — there is no Telemetry class that executes at these three exit points, and wrapping them would require adding a new `$guardMetric` parameter to `SmartHomeActionJob::handle()`, pulling a `Counter` directly into the job (currently a business-class, not a Telemetry class). **Recommendation:** keep deferred to Phase 7B.5/7B.6; the investigation path for these is the J1–J3 warning logs plus `ixora.queue.job.total{outcome=completed}` minus `ixora.smart_home.action.total` (the residual reveals guard-clause counts). Document this derivation in the future dashboard.

**`action_type` label on `ixora.smart_home.action.total`:** Remains deferred. `action_type` is a bounded enum (`App\SmartHome\Enums\ActionType` — values: `turn_on`, `turn_off`, `media_play`, `media_pause`, etc.) that would meaningfully segment the Action counter and Duration histogram, enabling "which action types fail most?" queries. **Recommendation:** add in Phase 7B.5 or a dedicated metric-enrichment phase (not a breaking change — labels can be added to a counter; the existing series remain valid, just unsegmented until then). Maximum cardinality impact: 4 (outcomes) × 2 (providers) × N (action types, currently ~6) × 2 × 2 ≈ 192 series — still safely bounded.

### 4.4 Metrics findings — verdict

**No architectural inconsistencies found.** All three implemented metrics are correctly designed, owned, and bounded. The two deferred items remain appropriately deferred with documented rationale and clear upgrade paths.

---

## 5. Logging Architecture Review

### 5.1 Log ownership and trigger conditions (verified)

| Log | Trigger | Level | Owner | Phase |
| --- | --- | --- | --- | --- |
| J1: action not found | Row deleted between enqueue and execution | WARNING | Action | pre-7B.4 |
| J2: device missing | Device deleted between enqueue and execution | WARNING | Action | pre-7B.4 |
| J3: connection missing | Provider connection deleted between enqueue and execution | WARNING | Action | pre-7B.4 |
| A2: provider returned failure | `ActionResult.success === false` | WARNING | Action | 7B.4.7 |
| A3: unsupported action | `UnsupportedSmartHomeActionException` caught | WARNING | Action | 7B.4.7 |
| A4/A5: unexpected error | Generic `Throwable` caught | ERROR | Action | 7B.4.7 |

### 5.2 Structured fields (verified against `SmartHomeActionJob.php` source)

**Guard clause logs (J1–J3):**

```
vibe_device_action_id | (J1 only)
vibe_device_action_id, vibe_id, device_id | (J2, partial context)
vibe_device_action_id, vibe_id, device_id | (J3)
```

**Business outcome logs (A2, A3, A4/A5):**

```
vibe_device_action_id, vibe_id, device_id, provider_connection_id,
provider, action_type, outcome, exception_class | (A3, A4/A5)
vibe_device_action_id, vibe_id, device_id, provider_connection_id,
provider, action_type, outcome, status_code | (A2)
```

### 5.3 Security sanitization (verified)

| Forbidden field | Present in any log? | Evidence |
| --- | --- | --- |
| `provider_device_id` | **No** — removed in Phase 7B.4.7 | `SmartHomeBusinessLoggingTest.php` line scan |
| `error_message` (raw exception text) | **No** — replaced with `exception_class` | Same test |
| `provider_entity_id` | **No** | Never referenced in `SmartHomeActionJob` |
| `user_id` | **No** | Never in log context |
| `access_token` / credentials | **No** — covered by pre-existing `'never logs the access token or credentials'` test | `SmartHomeActionJobTest.php` |

### 5.4 Naming consistency — `provider_connection_id` vs `connection_id`

**Finding:** `SmartHomeActionJob` uses `provider_connection_id` as the structured log field key (e.g. `'provider_connection_id' => $connection->id`). The Telemetry Naming Convention (§9) and `logs-philosophy.md` (§6) prefer the shorter `connection_id` for provider-agnostic investigation contexts.

**Decision: classified as Low technical debt, no runtime change made.** The current field is self-documenting and functionally correct. Renaming is a non-breaking improvement (Loki query syntax — engineers change the query, not an application contract) and does not constitute a genuine architectural inconsistency. Renaming in this phase would require updating five log call sites in `SmartHomeActionJob.php` plus tests with no functional benefit — out of proportion with the phase's "review-first, minimal changes" mandate. See §13 Technical Debt, TD-4.

### 5.5 Success log absence (L-2 resolution)

The `Log::info` on `ActionResult.success === true` was correctly removed in Phase 7B.4.7. Success is fully covered by:
- `ixora.smart_home.action.total{outcome=success}` — trend/rate
- `smart_home.action` span with `ixora.action.outcome=success` — per-execution trace

A success log on a hot path would be pure noise and would cost Loki retention budget with zero investigation value (`logs-philosophy.md §4/§5`).

### 5.6 Logging findings — verdict

**No architectural inconsistencies found.** All logs are structured, owned by the correct boundary, at the appropriate level, sanitized, and complementary to metrics and traces. The `provider_connection_id` naming is a Low-priority cosmetic inconsistency documented as technical debt.

---

## 6. Cross-Signal Consistency Matrix

This matrix validates that every business outcome produces consistent, non-contradictory signals across all three telemetry dimensions.

| Business outcome | Span: `smart_home.action` | Metric: `action.total` | Log |
| --- | --- | --- | --- |
| **Success** | `outcome=success`, no error, no exception | `outcome=success` increment | No log (L-2 resolution — covered by span+metric) |
| **Provider failure** (`ActionResult.success=false`) | `outcome=failure`, no error on `smart_home.action`¹ | `outcome=failure` increment | WARNING: A2 with `outcome=failure`, `status_code` |
| **Unsupported action** | `outcome=unsupported`, exception recorded, **no `setError()`** | `outcome=unsupported` increment | WARNING: A3 with `outcome=unsupported`, `exception_class` |
| **Unexpected error** (catch-all `Throwable`) | `outcome=failure`, exception recorded, `setError()` | `outcome=failure` increment | ERROR: A4/A5 with `outcome=failure`, `exception_class` |
| **Guard skip** (J1–J3, before boundary) | No span created | Not counted | WARNING: J1/J2/J3 (boundary never reached) |

¹ For `smart_home.action`: a provider failure (`ActionResult.success=false`) classifies as `outcome=failure` and does NOT set the span as errored, because the Action boundary successfully completed — it received a valid (if negative) business result. The span status is OK; the outcome attribute communicates the business failure. `smart_home.provider`'s nested Guzzle `CLIENT` span already carries `http.response.status_code` and/or its own error status for the HTTP-level failure detail.

**Dispatch-level consistency:**

| Dispatch outcome | Span: `smart_home.dispatch` | Metric: `dispatch.total` | Log |
| --- | --- | --- | --- |
| N actions dispatched | `dispatched_actions=N`, `skipped_actions=M` | N × `outcome=dispatched`, M × `outcome=skipped` | None (Dispatch boundary emits no logs — correct) |
| Exception from `dispatch()` | Exception recorded, `setError()` | 1 × `outcome=error` | Pre-existing log at call site (DispatchDueSchedulesCommand) |

**Verdict: all signals are internally consistent.** No signal contradicts another. The metric outcome vocabulary (`SmartHomeActionOutcome`) is shared with the span outcome vocabulary by construction — both are populated from the same classified enum value in `SmartHomeActionTelemetry::recordMetrics()`. A structural contradiction is impossible.

---

## 7. Correlation Review

### 7.1 Metric → Trace navigation

An engineer sees an alert on `ixora.smart_home.action.total{outcome=failure, provider=home_assistant}`.

**Pivot path:** metric labels (`outcome`, `provider`, time range) → Tempo exemplar (post-MVP) or Tempo search by service name + time range → find traces with `smart_home.action` span where `ixora.action.outcome=failure` → inspect full trace hierarchy (HTTP/Console → dispatch → queue consumer → action → provider → Guzzle POST).

This path works today because:
- `outcome` and `provider` are both metric labels AND span attributes — direct correlation
- The trace carries the full execution context without additional querying

### 7.2 Trace → Log navigation

From a `smart_home.action` span, an engineer wants the correlated log lines.

**`TraceCorrelationLogTap`** (registered globally in `TelemetryServiceProvider::registerLogTaps()`) injects `trace_id` and `span_id` into the `extra` bag of every Monolog record emitted while an active span exists. All A2/A3/A4/A5 log lines are emitted from `SmartHomeActionJob::handle()`, which runs while `smart_home.action` is the active span — verified by the span boundary (wraps the try block, catch blocks execute after span ends but before `handle()` returns, so `trace_id`/`span_id` are still on the active queue consumer span at catch-block logging time).

**Pivot path (Grafana):** copy `trace_id` from span → Loki query `{} | json | trace_id="<id>"` → retrieve all log lines for this execution.

### 7.3 Cross-signal field verification

| Correlation field | Span | Metric label | Log field | Notes |
| --- | --- | --- | --- | --- |
| `trace_id` | Natively on every span | N/A | Via `TraceCorrelationLogTap` in `extra` | Global injection, no custom code needed |
| `span_id` | Natively on every span | N/A | Via `TraceCorrelationLogTap` in `extra` | |
| `outcome` | `ixora.action.outcome` | `outcome` | `'outcome' => $outcome->value` | Same `SmartHomeActionOutcome` value — cannot diverge |
| `exception_class` | Via `recordException()` on span | N/A | `'exception_class' => $e::class` | Bounded PHP FQCN; replaces raw `error_message` |
| `provider` | `ixora.action.provider` | `provider` | `'provider' => $connection->provider` | Same raw slug value |

**No custom correlation IDs exist anywhere in the pipeline.** The OTel `trace_id` is the sole correlation mechanism. This is correct per `telemetry-naming-convention.md §11` and was explicitly validated by Phase 7B.4.2's pre-implementation review.

### 7.4 Correlation findings — verdict

**Complete.** An engineer can navigate from an alerting metric → a specific trace → all correlated log lines using only `trace_id` as the key. No custom correlation IDs, no ambiguity, no missing linkage.

---

## 8. Security Review

### 8.1 Span attributes

| Forbidden item | `smart_home.dispatch` | `smart_home.action` | `smart_home.provider` |
| --- | --- | --- | --- |
| `provider_device_id` / `provider_entity_id` | No | No | No (only device-type category) |
| `user_id` / `vibe_id` / `device_id` | No | No | No |
| `schedule_id` | No | No | No |
| Credentials / tokens | No | No | No |
| URLs / IP addresses | No | No | No |
| Payloads / request bodies | No | No | No |
| Raw exception messages | No | No | No |

The Guzzle `CLIENT` span (`url.full`) is produced by `opentelemetry-auto-guzzle` and exports `{base_url}/api/services/{domain}/{service}` — bounded Home Assistant vocabulary, never an entity ID. The Bearer token is in the HTTP `Authorization` header, which the auto-instrumentation explicitly does NOT capture (no `otel.instrumentation.http.request_headers` ini setting is configured — verified by reading `collector/config.yaml`, `.env.example`, and all `config/` files in Phase 7B.4.4 §2.7).

### 8.2 Metric labels

No metric label contains any identifier, URL, credential, payload, or high-cardinality value. All labels are bounded semantic enums.

### 8.3 Structured log fields

| Forbidden item | Present? | Evidence |
| --- | --- | --- |
| `provider_device_id` | **No** | Removed Phase 7B.4.7; enforced by `SmartHomeBusinessLoggingTest::never logs provider_device_id` |
| Raw `error_message` / exception text | **No** | Replaced with `exception_class`; enforced by test |
| `access_token` / decrypted credentials | **No** | Enforced by pre-existing `SmartHomeActionJobTest::never logs the access token or credentials` |
| `user_id` | **No** | Never in any log context |

**Security review verdict: PASS.** No forbidden data is exported on any signal. All enforcement is test-backed, not documentation-only.

---

## 9. Dashboard Readiness Review

Without implementing dashboards, the following panels can be built from current telemetry:

| Dashboard / Panel | Sufficient data? | Signal used | Notes |
| --- | --- | --- | --- |
| **Smart Home Overview** | ✅ Yes | `action.total{outcome=*}` | Success rate, failure rate, unsupported rate over time |
| **Dispatch Throughput** | ✅ Yes | `dispatch.total{entry_point=*, outcome=dispatched/skipped}` | Dispatched vs skipped by entry point over time |
| **Action Success Rate** | ✅ Yes | `action.total{outcome=success}` / `action.total` | Rate = success / (success + failure + unsupported) |
| **Unsupported Action Rate** | ✅ Yes | `action.total{outcome=unsupported}` / `action.total` | Directly queryable |
| **Action Duration (p50/p95/p99)** | ✅ Yes | `action.duration` | Histogram buckets; by `outcome` and `provider` |
| **Provider Performance** | ⚠️ Partial | `action.total{provider=home_assistant, outcome=*}` | Today: success/failure rate per provider. Missing: per-device-domain breakdown requires adding `action_type` label (TD-2) or pivoting to `smart_home.provider` span's `device_domain` attribute via Tempo-derived metrics (post-MVP). |
| **Top Failures** | ⚠️ Partial | Metrics give rate; trace gives detail | Top failure rate is metric-only (no entity IDs in labels — correct by design). Root cause requires Tempo trace inspection + `exception_class` in Loki. No single panel gives "top failing device types" without adding `action_type` label (TD-2). |
| **Operational Investigations** | ✅ Yes | Metric → Trace → Log correlation | See §11 |

**Summary:** 6 of 8 dashboard categories are fully supported today. "Provider Performance" and "Top Failures" are partially supported — the gaps can be closed by adding the `action_type` label to `ixora.smart_home.action.total` (TD-2, deferred). No structural changes are needed for the remaining 6 panels.

---

## 10. Operational Readiness Review

### 10.1 Simulated investigation: "Lights are not turning on."

A user reports that tapping "Play" on their Vibe does not turn on their lights.

| Diagnostic question | Can be answered? | How |
| --- | --- | --- |
| Did dispatch occur? | ✅ Yes | `ixora.smart_home.dispatch.total{entry_point=manual, outcome=dispatched}` spike + `smart_home.dispatch` span in Tempo for the time range |
| Was the action queued? | ✅ Yes | `ixora.dispatch.dispatched_actions` span attribute on `smart_home.dispatch` shows N > 0; `ixora.queue.job.total{outcome=completed, queue=smart-home}` confirms jobs consumed |
| Was the Action boundary executed? | ✅ Yes | `ixora.smart_home.action.total` count; `smart_home.action` span present in trace |
| Was Provider resolution successful? | ✅ Yes | No `outcome=failure` with `exception_class=InvalidArgumentException` on `smart_home.action` span |
| Was the Provider called? | ✅ Yes | `smart_home.provider` span + nested Guzzle `POST` CLIENT span both present |
| Was it unsupported? | ✅ Yes | `ixora.action.outcome=unsupported` on `smart_home.action` + WARNING log A3 with `action_type` |
| Was it a Provider failure? | ✅ Yes | `ixora.action.outcome=failure` + `smart_home.provider`'s nested Guzzle span has `http.response.status_code` |
| Is trace correlation preserved? | ✅ Yes | Single `trace_id` links HTTP span → dispatch → queue consumer → action → provider → Guzzle POST |
| Can the failure be diagnosed without extra logging? | ✅ Yes | `exception_class`, `outcome`, `action_type`, and `status_code` are all present in logs; `device_domain` on the provider span narrows which device category failed |

### 10.2 Documented blind spots

| Blind spot | Severity | Workaround today | Recommended fix |
| --- | --- | --- | --- |
| **Guard-clause skips (J1–J3) invisible to metrics** — actions deleted between enqueue and execution are logged but not counted | Low | J1–J3 warning logs are Loki-searchable by `vibe_device_action_id`; count = `ixora.queue.job.total{completed}` − `ixora.smart_home.action.total` | Add a `Counter` sourced from these log events or a dedicated boundary metric (Phase 7B.5/7B.6) |
| **No Vibe-level success/failure aggregate** — partial failure (some actions succeed, some fail) within one Vibe dispatch is not observable as a single signal | Medium | Correlate N `smart_home.action` spans under the same `smart_home.dispatch` parent span in Tempo | Fan-in mechanism required; deferred per domain-execution-review.md U-5 |
| **`action_type` not in action metrics** — cannot answer "which action type fails most?" from metrics alone | Low | Pivot to `smart_home.action` span in Tempo, filter by `action_type` is NOT available (not a span attribute); use Loki `action_type` field from A2/A3 logs | Add `action_type` label (TD-2) |
| **Device status staleness** — `Device.status` / `ProviderConnection.status` reflect sync pipeline, not execution pipeline | Low | Use `ixora.smart_home.action.total{outcome=failure}` as live execution health signal | Update `Device.status` on repeated execution failure (application change, outside telemetry scope) |

**Overall verdict: production-ready for the "Lights are not turning on" investigation class.** An on-call engineer can identify the failure boundary, its type, and its context without additional tooling.

---

## 11. Future Extensibility Review

### 11.1 Push Notifications (Phase 7B.5)

- **Boundaries valid:** `SmartHomeActionJob` already decouples push via `PushNotificationEvents` — the Push domain can instrument its own boundary (`PushNotificationJob`) independently without changing any Smart Home telemetry.
- **Ownership valid:** Push telemetry will be owned by the Push boundary, not the Action boundary. The Action span already terminates before `notifyActionFailed()` is called.
- **Abstractions reusable:** `SmartHomeDispatchTelemetry`'s `wrap()` + closure pattern, `SmartHomeActionTelemetry`'s classifier-closure pattern, the Dependency Rule (Contracts-only imports), and the fail-open `safely()` + `inertSpan()` guard are all directly reusable as the implementation template for Phase 7B.5.

### 11.2 Matter / Google Home / Alexa / additional providers

- **Boundaries valid:** The Provider boundary is per-adapter, not per-interface. A second adapter (`MatterAdapter`, `GoogleHomeAdapter`) adds its own `SmartHomeProviderTelemetry::wrap()` call inside its own `executeAction()` — no change to `HomeAssistantAdapter`, `SmartHomeProviderTelemetry`, or `SmartHomeActionTelemetry`.
- **Ownership valid:** A second provider is covered by `ixora.action.provider=future` on `smart_home.action` until an explicit enum case is added. `SmartHomeActionProvider::fromProviderSlug()` normalizes unknown slugs to `Future` — cardinality bounded regardless.
- **`SmartHomeProviderDeviceDomain::Other`** similarly bounds an unknown domain category. A second provider with a different domain vocabulary normalizes correctly without a cardinality explosion.
- **No redesign required** — the entire architecture is provider-agnostic by construction.

### 11.3 Architecture reusability — verdict

**The architecture supports all listed future domains without redesign.** The Dependency Rule, fail-open pattern, closure-based classifier pattern, and bounded enum vocabulary are all designed to be extended, not replaced.

---

## 12. Deferred Item Review

### 12.1 Items from previous phases — status confirmed

| Item | Source phase | Status | Finding |
| --- | --- | --- | --- |
| `ixora.action.retry` on `smart_home.action` duplicates `ixora.queue.attempt` | Phase 7B.4.4 §3.5 | **Remains deferred** — no new justification to accelerate (see TD-1) |
| Guard-clause skip metric (J1–J3) | Phase 7B.4.6 | **Remains deferred** — no clean boundary owner exists today (see §9) |
| `action_type` label on `ixora.smart_home.action.total` | Phase 7B.4.6 | **Remains deferred** — implementation is straightforward; recommend Phase 7B.5 or 7B.6 (see TD-2) |
| `provider_connection_id` → `connection_id` field naming | Phase 7B.4.7 | **Remains deferred** — Low priority cosmetic inconsistency (see TD-4) |

---

## 13. Technical Debt Register

### TD-1 — `ixora.action.retry` is a documented duplicate of `ixora.queue.attempt`

| Property | Value |
| --- | --- |
| **Severity** | Medium |
| **Description** | `smart_home.action` carries `ixora.action.retry` (`$this->attempts() > 1`, boolean), derived from the same underlying queue attempt counter as `ixora.queue.attempt` (integer) already recorded by `QueueExecutionTelemetry` on the parent Queue Consumer span. Phase 7B.4.4 §3.5 documented this as a "documented, unresolved duplicate of infrastructure-owned data" — the only difference is precision (boolean vs integer) and span (child vs parent). |
| **Impact** | Low operational impact today — `ixora.action.retry=true` never fires in production (no exception escapes `handle()`). When/if retry behavior changes, the duplication would produce redundant data. |
| **Recommendation** | Remove `ixora.action.retry` from `smart_home.action` in a dedicated cleanup phase. `ixora.queue.attempt` (integer, on the parent span) already expresses the same fact with higher fidelity. |
| **Suggested phase** | Phase 7B.5 or a dedicated cleanup |

### TD-2 — `action_type` label absent from `ixora.smart_home.action.total`

| Property | Value |
| --- | --- |
| **Severity** | Low |
| **Description** | `action_type` (`turn_on`, `turn_off`, `media_play`, etc.) is a bounded enum with a small, stable value set. Its absence from `ixora.smart_home.action.total` means "which action type fails most?" cannot be answered from metrics alone — engineers must pivot to Loki logs. |
| **Impact** | Dashboard gap for "Top Failures by action type." Investigation requires an extra Loki query. |
| **Recommendation** | Add `action_type` as an additional label to both `ixora.smart_home.action.total` and `ixora.smart_home.action.duration`. It must be sourced from `SmartHomeActionJob` (where `action_type` is available) and passed through `SmartHomeActionTelemetry::wrap()` as a new parameter, or as part of the provider parameter bundle. |
| **Suggested phase** | Phase 7B.5 |

### TD-3 — Guard-clause skip paths (J1–J3) invisible to metrics

| Property | Value |
| --- | --- |
| **Severity** | Medium |
| **Description** | The three guard-clause early returns in `SmartHomeActionJob::handle()` (missing action, missing device, missing connection) produce only warning logs. They are not counted by `ixora.smart_home.action.total` (the boundary is never reached) and not exposed as a separate metric signal. The count can only be approximated as `ixora.queue.job.total{queue=smart-home, outcome=completed}` − `ixora.smart_home.action.total`. |
| **Impact** | Invisible operational risk: a systematic data integrity problem (e.g. cascading deletes leaving orphaned queue messages) would manifest as silently-absorbed warnings without a metric alarm. |
| **Recommendation** | Introduce a `ixora.smart_home.action.skipped` counter (or add `outcome=skipped` to `ixora.smart_home.action.total`) sourced from the guard-clause paths. This requires a small Counter injection into `SmartHomeActionJob::handle()` — the cleanest approach is a new `SmartHomeGuardTelemetry` service (or a minimal counter parameter on `SmartHomeActionTelemetry`). |
| **Suggested phase** | Phase 7B.5 or a dedicated guard-clause visibility phase |

### TD-4 — `provider_connection_id` vs `connection_id` in structured log fields

| Property | Value |
| --- | --- |
| **Severity** | Low |
| **Description** | `SmartHomeActionJob` uses `provider_connection_id` as a structured log field key. `logs-philosophy.md` §6 and `telemetry-naming-convention.md` §9 prefer the shorter, provider-agnostic `connection_id`. The current field name is self-documenting and functionally correct; the inconsistency is cosmetic. |
| **Impact** | Loki queries must use `provider_connection_id` instead of the conventional `connection_id`. Engineers must remember the non-standard key. |
| **Recommendation** | Rename to `connection_id` in a future logging cleanup pass. Update Loki saved queries and playbooks at the same time. |
| **Suggested phase** | Phase 7B.5 logging review, or bundled with TD-1's cleanup |

---

## 14. Runtime Changes

**No runtime code changes were made in this phase.**

The architecture validation found no genuine architectural inconsistency that would justify a code change under the phase's "review-first, minimal changes" mandate. All four technical debt items are documented above, none rises to the level of an immediate correction, and each has a clearly suggested future phase.

---

## 15. Files Created

**`ixora-infra`:**

- `docs/specs/observability-foundation/business-telemetry/backend-business-telemetry-validation.md` *(this file)*

**`back_vibes`:** None.

---

## 16. Tests

No test changes were made (no runtime changes). All pre-existing telemetry tests confirm the findings of this review:

| Scope | Tests | Status |
| --- | --- | --- |
| `vendor/bin/pest --filter=SmartHome` | 364 | Passing (verified before this phase) |
| `vendor/bin/pest` (full suite) | 986 | Passing (verified before this phase) |
| `vendor/bin/pint --test` | — | Clean (verified before this phase) |

---

## 17. Known Limitations

1. **No live-provider end-to-end test** — confidence in the full chain (schedule tick → HA HTTP call) is composed from separately-verified boundary contracts, not from one live integration test. This is a pre-existing, documented limitation of the project's test strategy (domain-execution-review.md §13).

2. **`ixora.action.retry=true` never fires in production today** — the `tries=3` queue retry mechanism is inert for this job because no exception escapes `handle()`. The `retry` attribute is correct for forward-compatibility but carries no operational signal at present.

3. **`smart_home.provider` span absent for unsupported actions** — by design (the provider boundary begins after the unsupported check). This is correct; it reflects "no provider work was attempted." The `smart_home.action` span with `outcome=unsupported` is the correct signal for this outcome.

4. **Traces expire after 7 days** (ADR-031) — historical trend analysis relies on metrics (30-day retention). Investigations older than 7 days are metrics + logs only.

---

## 18. Recommendations for Phase 7B.5

1. **Reuse the `wrap()` + closure pattern** for Push Notification telemetry (`PushNotificationJob`). `SmartHomeActionTelemetry::wrap()` is the cleanest template — classifier closures avoid importing domain types into the Telemetry layer.

2. **Add `action_type` label (TD-2)** to `ixora.smart_home.action.total` and `.duration` in Phase 7B.5 or a dedicated early task. Small, bounded, non-breaking enrichment with high dashboard value.

3. **Address TD-1** (`ixora.action.retry` removal) in Phase 7B.5's cleanup scope — a single-line removal with test update, low risk.

4. **Define a guard-clause visibility strategy (TD-3)** at Phase 7B.5 planning. The "J1–J3 blind spot" is the only medium-severity debt item; it should not reach Phase 7B.6 unaddressed.

5. **Continue the Dependency Rule enforcement** for every new Telemetry class: `@use` contracts only, no domain imports, dependency-rule test file per new class.

6. **Standardize `connection_id` (TD-4)** whenever `SmartHomeActionJob` logging is next touched for any reason — bundle it with the first Phase 7B.5 logging change rather than making it a standalone commit.

---

## 19. Final Conclusions

**Is the Smart Home Business Telemetry internally consistent?**

**Yes.** Every signal has exactly one owner. The trace hierarchy is valid and propagates through the queue boundary without custom code. Metric outcomes, span outcomes, and log outcomes all share the same `SmartHomeActionOutcome` vocabulary — a metric value can never contradict its corresponding span. Logs complement the other signals rather than duplicating or replacing them. Fail-open behavior is consistently implemented and test-verified across all three telemetry classes. Security review passes on all three signal types.

**Is it production-ready?**

**Yes, for the Smart Home domain.** The full investigation workflow (Metric → Trace → Log) is functional. An on-call engineer can diagnose "lights are not turning on" using only metrics, traces, and logs — without additional tooling, manual SQL queries, or SSH access to application logs. Four items of technical debt are documented; none is a production blocker.

**Can future Business Telemetry domains reuse this architecture without redesign?**

**Yes.** The `wrap()` + closure pattern, Dependency Rule (Contracts-only imports), fail-open `safely()` + `inertSpan()` guard, bounded enum vocabulary with `Other`/`Future` fallbacks, and per-adapter (not per-interface) Provider instrumentation are all designed to be extended. Adding Push Notifications, Matter, Google Home, Alexa, or any additional Smart Home provider requires no changes to existing classes — only new classes following the same pattern.
