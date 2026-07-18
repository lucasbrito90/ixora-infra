# Backend Smart Home Dispatch Boundary — Phase 7B.4.2 (`back_vibes`)

**Status:** Complete
**Repo:** `back_vibes` (Laravel 13, PHP 8.3+)
**Feature ID:** `observability-foundation/mvp`
**Prerequisite:** [domain-execution-review.md](domain-execution-review.md) (Phase 7B.4.1 — authoritative architectural reference) · [backend-queue-console-instrumentation.md](../mvp/backend-queue-console-instrumentation.md) (Phase 7B.2) · [backend-generic-scheduler-instrumentation.md](../mvp/backend-generic-scheduler-instrumentation.md) (Phase 7B.3) · [traces-philosophy.md](../../../architecture/traces-philosophy.md) · [telemetry-naming-convention.md](../../../architecture/telemetry-naming-convention.md)

---

## 1. Scope

Phase 7B.4.2 is the first **Business Telemetry** boundary implemented in `back_vibes` (as opposed to the generic Laravel infrastructure telemetry of Phases 7A–7B.3). It instruments **only** the dispatch boundary of `App\SmartHome\Services\VibeSmartHomeDispatchService::dispatch()` — the single call documented as the convergence point of both real Smart Home entry points in the Phase 7B.4.1 Domain Execution Review.

| In scope | Out of scope (later 7B.4 sub-phases) |
| --- | --- |
| One Business Span, `smart_home.dispatch`, wrapping `VibeSmartHomeDispatchService::dispatch()` | `SmartHomeActionJob` execution (Phase 7B.4.3) |
| `ixora.dispatch.entry_point` / `.dispatched_actions` / `.skipped_actions` span attributes | `ProviderAdapterResolver` / `HomeAssistantAdapter` (Phase 7B.4.3+) |
| Entry-point classification (`manual` / `scheduled`) at the two real call sites | Business metrics (Phase 7B.4.6) |
| | Business logging (Phase 7B.4.7) |

No change was made to `App\SmartHome\Services\VibeSmartHomeDispatchService.php`, `App\SmartHome\DTOs\SmartHomeDispatchResult.php`, `App\Jobs\SmartHome\SmartHomeActionJob.php`, `App\SmartHome\Providers\*`, any domain model, migration, database schema, API response shape, or auth behavior. `git diff --stat` for `back_vibes` in this phase touches only `app/Telemetry/SmartHome/**` (new), `app/Telemetry/Providers/TelemetryServiceProvider.php` (registration only), `app/Http/Controllers/Api/VibeSmartHomeDispatchController.php` (wraps the existing `dispatch()` call), `app/Console/Commands/DispatchDueSchedulesCommand.php` (wraps the existing `dispatch()` call), and `tests/**`.

This phase does not contradict any Phase 7B.4.1 finding. Where this document and the Domain Execution Review disagree, the Domain Execution Review wins, per this phase's own brief.

---

## 2. Pre-implementation review

The brief mandated a review of existing OpenTelemetry auto-instrumentation, Queue instrumentation (Phase 7B.2), TraceContext propagation, and active-span reuse across the pipeline `VibeSmartHomeDispatchService::dispatch()` → `SmartHomeActionJob::dispatch()` → Queue → `SmartHomeActionJob::handle()`, **before** writing any span code, to determine whether custom correlation/propagation was needed.

| Question | Finding | Evidence |
| --- | --- | --- |
| Does an active span already exist when `dispatch()` runs? | Yes, for both real call sites. The manual path runs inside the HTTP server span `opentelemetry-auto-laravel` starts for every request (Phase 7B.1). The scheduled path runs inside the `"Command schedules:dispatch-due"` span `opentelemetry-auto-laravel`'s `Illuminate\Console\Command::execute()` hook starts unconditionally for every Artisan invocation (Phase 7B.2 §3) — **not** a Scheduler boundary span, because Phase 7B.4.1 and Phase 7B.3 both confirm `back_vibes` bypasses the native `Illuminate\Console\Scheduling\Schedule` facade for its own domain scheduling (custom `schedules:dispatch-loop`/`schedules:dispatch-due` commands instead). | backend-http-routing-instrumentation.md; backend-queue-console-instrumentation.md §3; backend-generic-scheduler-instrumentation.md §4; domain-execution-review.md §1–§2 |
| Does Queue instrumentation already propagate TraceContext across the dispatch → worker boundary? | Yes, already implemented, unconditionally, for every dispatch style (`push`/`bulk`/`later`/`pushRaw`). `Illuminate\Queue\Queue`'s `createPayloadArray()` post-hook calls `TraceContextPropagator::inject($payload)`, adding a W3C `traceparent` to every job payload at creation time. `Illuminate\Queue\Worker::process()`'s pre-hook extracts it back via `TraceContextPropagator::extract($job->payload())` and sets it as the consumer span's parent context. | backend-queue-console-instrumentation.md §2, row "Context propagation, dispatch → worker" |
| Are producer and consumer spans already linked? | Yes, by the same mechanism — the consumer span (`"process {destination}"`, `Illuminate\Queue\Worker::process()`) is parented to whatever span was active in the *producer* process at the moment `SmartHomeActionJob::dispatch()` (→ `push()` → `createPayloadArray()`) ran, via the injected `traceparent`. | backend-queue-console-instrumentation.md §2 |
| Does `Tracer::startSpan()` make a newly-created span the one whose context gets propagated into the queue payload? | Yes — verified directly in this phase, not merely inferred. `App\Telemetry\OpenTelemetry\OpenTelemetryTracer::startSpan()` calls `$span->activate()` before returning, which pushes the new span onto the OTel SDK's ambient Context — the exact mechanism `createPayloadArray()`'s `TraceContextPropagator::inject()` reads from. Any `SmartHomeActionJob::dispatch()` call made while a `Tracer::startSpan()`-created span is still open therefore has that span injected as its parent automatically. | `app/Telemetry/OpenTelemetry/OpenTelemetryTracer.php`; `App\Telemetry\Contracts\Tracer::startSpan()` docblock ("activate it as the current span") |
| Would additional custom propagation duplicate existing behavior? | Yes — a custom correlation ID, a custom context object, or any change to `SmartHomeActionJob` to carry propagated context would duplicate a mechanism that already works correctly and unconditionally for every job dispatched inside this phase's span. | — |
| Does `SmartHomeActionJob` already receive propagated context? | Yes, transparently, once the dispatch call happens inside an active span (real today via the HTTP/Console spans above; will include `smart_home.dispatch` as an intermediate parent once this phase ships) — with **zero** change to `SmartHomeActionJob` itself. | — |

**Conclusion — the Implementation Gate is satisfied by "reuse it".** OpenTelemetry already propagates TraceContext correctly across the queue boundary for every job this pipeline dispatches. This phase therefore implements **no custom correlation ID, no custom trace propagation, and no custom parent tracking** — `SmartHomeActionJob` is untouched, and the one new span this phase adds becomes an automatic parent of each dispatched job's consumer span purely by being the active span at `dispatch()`-call time, exactly like `HttpRequestTelemetry`/`SchedulerExecutionTelemetry` nest under (or, here, sit between) the layers above and below them.

---

## 3. Why this is instrumented at the two call sites, not inside `VibeSmartHomeDispatchService`

Phases 7B.2 and 7B.3 both instrument via a Laravel-native lifecycle **event** (`JobProcessing`/`CommandStarting`/`ScheduledTaskStarting`/etc.) — the business file being observed (`Worker::process()`, `Command::execute()`, `ScheduleRunCommand::runEvent()`) is never edited by this codebase's own telemetry.

The Domain Execution Review (Phase 7B.4.1 §11) found that `VibeSmartHomeDispatchService::dispatch()` fires **no** Laravel event of any kind — there is nothing to listen to. Two options remained:

1. Edit `dispatch()` itself to add span creation/teardown inline.
2. Wrap the call at its two call sites, leaving `VibeSmartHomeDispatchService.php` untouched.

This phase chose **option 2**, for three reasons:

- The brief's "boundary begins immediately before `dispatch()` / ends immediately before returning `SmartHomeDispatchResult`" describes a *temporal* window around the call, which is equally true whether the span-creation code sits one line inside the method or one line outside it at the call site — but only the call-site approach leaves the business method's own source completely unmodified, honoring "observe the domain, never redesign it" literally.
- The entry point (`manual` vs. `scheduled`) is naturally known at each call site and nowhere else — wrapping at the call site means `VibeSmartHomeDispatchService` never needs a new parameter, and neither the Controller's nor the Scheduler's vocabulary ever has to leak into the service (the brief's explicit "do not leak controller/scheduler knowledge into the service" requirement).
- It generalizes the same pattern Phases 7B.2/7B.3 already use — an external, Contracts-only Telemetry class the business code has zero awareness of — to a call site instead of an event.

`App\Telemetry\SmartHome\SmartHomeDispatchTelemetry::wrap()` is the one new abstraction this introduces. It is a **Telemetry-layer** helper (like `QueueExecutionTelemetry`/`SchedulerExecutionTelemetry`), not a domain concept — it has no name, meaning, or existence inside `App\SmartHome`, is not a `SmartHomeExecution`/`ExecutionContext`/`DispatchContext`/`BusinessCorrelationId`, and does not appear in `App\SmartHome\**`, `App\Models\**`, or any migration.

---

## 4. Boundary

| Aspect | Definition |
| --- | --- |
| **Owns** | Exactly one call: `VibeSmartHomeDispatchService::dispatch()` — loading ordered `VibeDeviceAction` rows, ordering by `sort_order`, calling `SmartHomeActionJob::dispatch()` once per resolvable action, counting dispatched/skipped actions, and returning `SmartHomeDispatchResult`. |
| **Begins** | Immediately before the call to `dispatch()`, at each of the two call sites. |
| **Ends** | Immediately after `dispatch()` returns (success) or throws (failure) — always before the caller does anything else with the result (JSON response building in the controller; nothing further in the command). |
| **Never includes** | `SmartHomeActionJob::handle()` execution, `ProviderAdapterResolver`, `HomeAssistantAdapter`, any provider HTTP call, `ScheduleAutomationValidator::validate()` (runs *before* the span starts — validation failures never create a span, verified by `SmartHomeDispatchBoundaryIntegrationTest`), or any push-notification dispatch. |

### Boundary lifetime under the two Laravel queue drivers

| Driver | Effect on the boundary |
| --- | --- |
| `database` (production, per Phase 7B.2 §2) | `SmartHomeActionJob::dispatch()` only enqueues a row; the span (ended right after `dispatch()` returns) structurally cannot overlap real job/provider execution — the boundary is clean by construction. |
| `sync` (this repository's own `phpunit.xml` test-suite override) | A dispatched job runs **inline**, synchronously, inside the same `push()` call — an already-documented, accepted asymmetry from Phase 7B.2 (§2, "Sync queue behavior"), not something this phase's code special-cases. This phase's own tests use `Bus::fake()` throughout specifically so span-lifetime assertions never depend on which queue driver is configured — see §8. |

### Parent span

| Entry point | Real parent in production |
| --- | --- |
| Manual (`VibeSmartHomeDispatchController::__invoke()`) | The HTTP server span `opentelemetry-auto-laravel` starts for the request (Phase 7B.1). |
| Scheduled (`DispatchDueSchedulesCommand::handle()` → `dispatchSmartHomeAfterSchedule()`) | The `"Command schedules:dispatch-due"` span `opentelemetry-auto-laravel` starts unconditionally for the Artisan invocation (Phase 7B.2 §3) — **not** a Scheduler boundary span; `back_vibes` never registers a native `Schedule::` entry (§2 above; domain-execution-review.md §1). |

`App\Telemetry\SmartHome\SmartHomeDispatchTelemetry` calls `Tracer::startSpan()`, never `Tracer::activeSpan()` — per the `Tracer` contract, `startSpan()` always creates a **child** of whatever span is currently active (or a new root only if nothing is active) and activates the new span as current for its own duration. This satisfies "reuse the current active infrastructure span as parent" and "never create duplicate root spans" structurally, without this class needing to inspect or special-case what kind of span is active.

### Queue boundary

`SmartHomeActionJob::dispatch()` calls made from inside the still-open `smart_home.dispatch` span automatically have that span injected as their trace parent (§2) — with no code in this phase touching `SmartHomeActionJob`. The consumer-side span for each dispatched job (whenever Phase 7B.4.3 adds one, or the bare auto-instrumented consumer span in the meantime) will therefore already be correctly parented under `smart_home.dispatch`, which itself sits under the HTTP/Console span above it — a clean three (or more)-level hierarchy assembled entirely from infrastructure propagation this phase reused rather than duplicated.

---

## 5. Span

| Property | Value |
| --- | --- |
| Name | `smart_home.dispatch` |
| Count per `dispatch()` call | Exactly one — verified by `SmartHomeDispatchTelemetryTest` ("never creates more than one span per call") and `SmartHomeDispatchBoundaryIntegrationTest` ("each due schedule … creates its own separate dispatch span — never merged or duplicated"). |
| Attributes | `ixora.dispatch.entry_point` (`manual` \| `scheduled` \| `future`, reserved), `ixora.dispatch.dispatched_actions` (int), `ixora.dispatch.skipped_actions` (int) — nothing else. |
| On success | `setAttributes()` with the two count attributes, then `end()`. |
| On failure | `recordException()` + `setError()` (no description text, matching `SchedulerExecutionTelemetry`'s precedent), then `end()` — the original exception is always rethrown unchanged; telemetry never alters control flow. |
| Never contains | action IDs, device IDs, provider IDs, user IDs, schedule IDs, queue IDs, entity IDs, trace/span IDs, payloads, credentials, tokens, URLs, or request bodies — verified directly by `SmartHomeDispatchTelemetryTest`'s "never sets a forbidden attribute" assertion, which enumerates exactly the three allowed attribute keys and nothing more. |

`ixora.dispatch.entry_point=future` is a reserved, currently-unused enum case (`App\Telemetry\SmartHome\SmartHomeDispatchEntryPoint::Future`) — mirrors the enum-reservation convention already used elsewhere in this Telemetry layer (e.g. `SchedulerOutcome::Cancelled`/`Unknown`) so a later entry point (a voice-assistant trigger, a webhook, etc.) can be added without a breaking enum change.

---

## 6. Correlation strategy

Business Telemetry (this phase) owns exactly one thing: the business semantics of the `ixora.dispatch.*` attributes. Infrastructure Telemetry (Phases 7A–7B.3, and `opentelemetry-auto-laravel`) owns trace propagation, and this phase reuses it exclusively:

- No correlation ID of any kind is introduced (`BusinessCorrelationId` and equivalents remain explicitly absent, matching the Domain Execution Review's finding that none exists today).
- No context object is introduced (`ExecutionContext`/`DispatchContext` and equivalents remain explicitly absent).
- `SmartHomeActionJob`'s payload is completely unmodified — it still carries only the integer `vibe_device_action_id`, exactly as Phase 7B.4.1 documented.
- The only mechanism linking a dispatch to the jobs it enqueues is the OTel trace itself (`smart_home.dispatch` as the jobs' common ancestor span), assembled for free by the existing W3C `traceparent` propagation §2 already provides.

---

## 7. Entry point

Determined exclusively by the caller, never by `VibeSmartHomeDispatchService` or `SmartHomeDispatchTelemetry`:

| Call site | Entry point passed |
| --- | --- |
| `App\Http\Controllers\Api\VibeSmartHomeDispatchController::__invoke()` | `SmartHomeDispatchEntryPoint::Manual` |
| `App\Console\Commands\DispatchDueSchedulesCommand::dispatchSmartHomeAfterSchedule()` | `SmartHomeDispatchEntryPoint::Scheduled` |

Neither the enum nor `SmartHomeDispatchTelemetry` imports `App\Http\**` or `App\Console\Commands\**` — enforced by `tests/Unit/Telemetry/SmartHome/SmartHomeDispatchTelemetryDependencyRuleTest.php`. `VibeSmartHomeDispatchService::dispatch()`'s signature is unchanged — `Vibe $vibe` in, `SmartHomeDispatchResult` out — it has no parameter, property, or return value that carries entry-point information; a caller wraps the call with `SmartHomeDispatchTelemetry::wrap()` entirely outside the service's own knowledge.

---

## 8. Fail-open

Every public path through `SmartHomeDispatchTelemetry::wrap()` is safe:

- `startSpan()` failure (a broken `Tracer`) falls back to a local inert `Span` implementation (mirrors `SchedulerExecutionTelemetry::inertSpan()` exactly) — the dispatch callable still runs, and its result is still returned unchanged.
- Attribute-setting and span-ending failures are caught and swallowed (`safely()`) — never propagate.
- A genuine business exception from `dispatch()` (e.g. a database error) is recorded on the span (`recordException()`/`setError()`) and then **always rethrown unmodified** — telemetry observes the failure, it never converts, swallows, or masks it.

Verified directly by `SmartHomeDispatchTelemetryTest`: "a broken Tracer never prevents `wrap()` from running the dispatch callable or returning its result", and "a broken Tracer combined with a dispatch failure still rethrows the original business exception".

---

## 9. What was intentionally excluded

Per the brief, this phase adds none of the following (all reserved for later Phase 7B.4 sub-phases):

- Instrumentation of `SmartHomeActionJob`, `ProviderAdapterResolver`, or `HomeAssistantAdapter` (Phase 7B.4.3).
- Any `Counter`/`Histogram`/`UpDownCounter`/observable instrument — no metric of any kind (Phase 7B.4.6). Verified by `SmartHomeDispatchTelemetryTest`'s "never records a counter, histogram, or up-down counter" and the dependency-rule test's ban on importing `Counter`/`Histogram`/`UpDownCounter`/`Meter`.
- Any `LogTap`, structured log enrichment, or logging change of any kind (Phase 7B.4.7). Verified by the dependency-rule test's ban on any `Log::` usage or `Illuminate\Support\Facades\Log` import inside `app/Telemetry/SmartHome`.
- Any new domain abstraction — no `SmartHomeExecution`, `ExecutionContext`, `ExecutionAggregate`, `ExecutionHistory`, `ExecutionManager`, `ExecutionPipeline`, `ExecutionLifecycle`, `DispatchContext`, or `BusinessCorrelationId` exists anywhere in this diff.
- Any database, API, or frontend change. `App\SmartHome\DTOs\SmartHomeDispatchResult`'s shape, the `POST /api/vibes/{vibe}/smart-home/dispatch` response body, and `schedules:dispatch-due`'s console output are all byte-for-byte unchanged — verified by the pre-existing `VibeSmartHomeDispatchApiTest.php` and `DispatchDueSchedulesCommandTest.php` suites, both still passing unmodified.

---

## 10. Accepted limitations

- **`sync` queue driver test/dev overlap (§4):** under `QUEUE_CONNECTION=sync`, a span technically *could* wrap real inline job execution if a future caller dispatched actions without `Bus::fake()`. This is identical to Phase 7B.2's own accepted sync/async asymmetry and is not fixed here — fixing it would require detecting the queue driver at runtime, which is out of scope and reintroduces exactly the kind of queue-aware complexity this phase was told to avoid.
- **`ixora.dispatch.entry_point=future` is unreachable today** — reserved for a caller that does not yet exist, per §5.
- **No fan-in visibility yet:** this span reports how many actions were *dispatched*, not how many later *succeeded* — that remains Phase 7B.4.3's responsibility (per the Domain Execution Review's finding that no persisted per-action execution outcome exists anywhere today).
- **The scheduled path's validator/vibe-lookup steps remain unobserved** — `ScheduleAutomationValidator::validate()` and the null-vibe guard in `DispatchDueSchedulesCommand::dispatchSmartHomeAfterSchedule()` run *before* the span starts (by design — they are not part of the dispatch boundary) and therefore never appear in any span attribute; a validation failure is silently telemetry-invisible today, exactly as it was before this phase (still only a `Log::warning()` call, unmodified).

---

## 11. Future phases

- **Phase 7B.4.3 — Smart Home Action Execution:** instruments `SmartHomeActionJob::handle()`, `ProviderAdapterResolver`, and `HomeAssistantAdapter` as their own Business Telemetry boundary, downstream of the queue this phase deliberately stops at. Its span(s) will automatically nest under `smart_home.dispatch` for free (§2, §4) — no correlation work is needed to make that happen.
- **Phase 7B.4.6 — Business metrics:** first `ixora.smart_home.*`/`ixora.dispatch.*`-style metrics; this phase's span attributes (`dispatched_actions`, `skipped_actions`) are natural candidates for that phase's counters.
- **Phase 7B.4.7 — Business logging:** first structured log enrichment for the Smart Home domain; may reuse `SmartHomeDispatchEntryPoint` for consistent classification once a log tap is introduced.
- **Phase 7B.5 — Push Notifications**, **Phase 7B.6 — External Providers:** unaffected by, and independent of, this phase.

---

## 12. Tests

| File | Covers |
| --- | --- |
| `tests/Unit/Telemetry/SmartHome/SmartHomeDispatchTelemetryDependencyRuleTest.php` | No OpenTelemetry SDK import; Contracts-only; no `App\Models`/`App\SmartHome`/`App\Http`/`App\Console\Commands`/`App\PushNotifications`/`App\Jobs`/`App\Services\Scheduling` import; no metric-contract import; no logging facade/`Log::` usage. |
| `tests/Feature/Telemetry/SmartHome/SmartHomeDispatchTelemetryTest.php` | Span creation/naming/entry_point attribute (manual and scheduled); count attributes sourced from the caller-supplied `extractCounts` closure; forbidden-attribute exhaustiveness; span ends exactly once; span ends *before* `wrap()` returns to its caller (proxy for "before queue execution"); no duplicate spans across repeated calls; `startSpan()` used (never `activeSpan()`) so the active span is never replaced; exception path records + errors + ends + rethrows unchanged; `extractCounts` never called on the failure path; fail-open under a broken `Tracer` (success and failure sub-cases); zero metrics recorded. |
| `tests/Feature/Telemetry/SmartHome/SmartHomeDispatchBoundaryIntegrationTest.php` | Real wiring through `VibeSmartHomeDispatchController` (manual) and `DispatchDueSchedulesCommand` (scheduled): correct entry-point tagging, correct counts including a zero-action schedule, no span for an unauthorized (403) request, no span for a validator failure, multiple due schedules each get their own non-duplicated span, and — combined with `Bus::fake()`/`Http::fake()`/`Http::assertNothingSent()` — no action or provider execution is ever observed inside the request/command lifecycle the span covers. |
| `tests/Feature/SmartHome/VibeSmartHomeDispatchApiTest.php` (pre-existing, unmodified) | Still fully green — proves this phase changed no observable HTTP behavior. |
| `tests/Feature/Scheduling/DispatchDueSchedulesCommandTest.php` (pre-existing, unmodified) | Still fully green — proves this phase changed no observable command behavior. |

Full suite: **894/894 passing** (869 pre-existing + 25 new), 2 pre-existing risky tests unrelated to this phase (`HttpRequestTelemetryMiddlewareTest`, Phase 7B.1), `pint --test` clean.

---

## 13. Files touched

**New:**

- `app/Telemetry/SmartHome/SmartHomeDispatchEntryPoint.php`
- `app/Telemetry/SmartHome/SmartHomeDispatchTelemetry.php`
- `tests/Unit/Telemetry/SmartHome/SmartHomeDispatchTelemetryDependencyRuleTest.php`
- `tests/Feature/Telemetry/SmartHome/SmartHomeDispatchTelemetryTest.php`
- `tests/Feature/Telemetry/SmartHome/SmartHomeDispatchBoundaryIntegrationTest.php`

**Modified (registration/wiring only, no business-logic change):**

- `app/Telemetry/Providers/TelemetryServiceProvider.php` — registers the `SmartHomeDispatchTelemetry` singleton.
- `app/Http/Controllers/Api/VibeSmartHomeDispatchController.php` — wraps the existing `dispatch()` call.
- `app/Console/Commands/DispatchDueSchedulesCommand.php` — wraps the existing `dispatch()` call; threads the new dependency through `handle()` and `dispatchSmartHomeAfterSchedule()`.

**Untouched:**

- `app/SmartHome/Services/VibeSmartHomeDispatchService.php`
- `app/SmartHome/DTOs/SmartHomeDispatchResult.php`
- `app/Jobs/SmartHome/SmartHomeActionJob.php`
- `app/SmartHome/Validation/ScheduleAutomationValidator.php`
- Every domain model and migration.
