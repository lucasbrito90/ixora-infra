# Backend Smart Home Action Execution — Phase 7B.4.3 (`back_vibes`)

**Status:** Complete
**Repo:** `back_vibes` (Laravel 13, PHP 8.3+)
**Feature ID:** `observability-foundation/mvp`
**Prerequisite:** [domain-execution-review.md](domain-execution-review.md) (Phase 7B.4.1 — authoritative architectural reference) · [backend-smart-home-dispatch-boundary.md](backend-smart-home-dispatch-boundary.md) (Phase 7B.4.2) · [backend-queue-console-instrumentation.md](../mvp/backend-queue-console-instrumentation.md) (Phase 7B.2) · [traces-philosophy.md](../../../architecture/traces-philosophy.md) · [telemetry-naming-convention.md](../../../architecture/telemetry-naming-convention.md)

---

## 1. Purpose

Phase 7B.4.3 is the second **Business Telemetry** boundary implemented in `back_vibes`, immediately downstream of the Dispatch boundary (Phase 7B.4.2). It instruments **only** the execution of one Smart Home Action inside `App\Jobs\SmartHome\SmartHomeActionJob::handle()` — specifically the provider-resolution + provider-execution segment the mandatory architecture review (§2) identified as the natural Business Boundary, which is **narrower** than the entire `handle()` method.

| In scope | Out of scope (later phases) |
| --- | --- |
| One Business Span, `smart_home.action`, wrapping provider resolution (`ProviderAdapterResolver::forProvider()`) + provider execution (`ProviderAdapter::executeAction()`) | Provider communication internals, HTTP client calls, `HomeAssistantAdapter`'s own request/response handling (Phase 7B.4.4 — Provider Boundary) |
| `ixora.action.provider` / `.outcome` / `.retry` span attributes | Business metrics (Phase 7B.4.6) |
| | Business logging (Phase 7B.4.7) |

No change was made to `App\SmartHome\ProviderAdapterResolver.php`, `App\SmartHome\Adapters\HomeAssistantAdapter.php`, `App\SmartHome\Contracts\ProviderAdapter.php`, `App\SmartHome\DTOs\ActionResult.php`, `App\SmartHome\Exceptions\UnsupportedSmartHomeActionException.php`, any domain model, migration, database schema, API response shape, queue configuration (`tries`, `timeout`, `queue`), or retry behavior. `git diff --stat` for `back_vibes` in this phase touches only `app/Telemetry/SmartHome/**` (new: `SmartHomeActionTelemetry.php`, `SmartHomeActionProvider.php`, `SmartHomeActionOutcome.php`), `app/Telemetry/Providers/TelemetryServiceProvider.php` (registration only), `app/Jobs/SmartHome/SmartHomeActionJob.php` (wraps the existing provider-resolution + `executeAction()` call; the rest of `handle()`, including both surrounding `catch` blocks, is byte-for-byte unchanged), and `tests/**`.

This phase does not contradict any Phase 7B.4.1 or 7B.4.2 finding.

---

## 2. Mandatory architecture review

The brief required discovering the natural Business Boundary — not assuming it is the entire `handle()` method — **before** writing any span code.

### 2.1 `SmartHomeActionJob::handle()` structure, read in full

`handle(ProviderAdapterResolver $resolver, PushNotificationEvents $pushEvents)` executes, strictly in order:

1. Load `VibeDeviceAction` with `device`, `device.providerConnection`, `device.user` eager-loaded.
2. **Guard clause 1** — if the action row itself is `null` (deleted between enqueue and processing): `Log::warning(...)`, `return`.
3. **Guard clause 2** — if `$action->device` is `null`: `Log::warning(...)`, `return`.
4. **Guard clause 3** — if `$device->providerConnection` is `null`: `Log::warning(...)`, `return`.
5. Build a `$context` array (for logging only).
6. `try`: resolve the adapter (`$resolver->forProvider($connection->provider)`), call `$adapter->executeAction(...)`, log the result (`$this->logResult()`), and — only if the result failed — call `$this->notifyActionFailed()` (push notification).
7. `catch (UnsupportedSmartHomeActionException $e)`: log a warning, no push notification (ADR-026: log + skip + continue).
8. `catch (Throwable $e)`: log an error, call `$this->notifyActionFailed()`.

### 2.2 `ProviderAdapterResolver::forProvider()`

Pure in-memory `match()` over a `ProviderType` slug — no I/O, no network, throws a plain `InvalidArgumentException` for an unrecognized provider. Never touches the network.

### 2.3 `HomeAssistantAdapter::executeAction()`

```php
public function executeAction(ProviderConnection $connection, string $deviceId, string $action, array $parameters = []): ActionResult
{
    $service = self::ACTION_SERVICE_MAP[$action] ?? null;
    if ($service === null) {
        throw UnsupportedSmartHomeActionException::forAction($action);   // ← thrown BEFORE any HTTP call
    }
    // ... HTTP POST to the provider, always caught internally ...
    return new ActionResult(success: ..., status_code: ..., response: ..., error_message: ...);
}
```

Two load-bearing facts, confirmed by reading this method in full:

- `UnsupportedSmartHomeActionException` is thrown **synchronously, before any HTTP call** — it is a pure business/configuration decision (the action type has no mapped HA service), not a provider-communication failure. This is exactly why Phase 7B.4.3's outcome vocabulary has a distinct `unsupported` value separate from `failure`.
- Every transport-level failure (`ConnectionException`, non-2xx response) is caught **inside** `executeAction()` and returned as a normal `ActionResult(success: false, ...)` — `executeAction()` itself never throws for a provider communication problem. The interface docblock (`App\SmartHome\Contracts\ProviderAdapter`) states this policy explicitly: *"executeAction(): never throws for transport/HTTP failures (returns failed ActionResult); throws UnsupportedSmartHomeActionException for unmappable actions."*

### 2.4 Findings — answering the brief's explicit questions

| Question | Finding |
| --- | --- |
| Is the natural Business Boundary the entire `handle()` method? | **No.** See §2.5. |
| Where does the Action Boundary naturally begin? | Immediately before `$resolver->forProvider($connection->provider)` — i.e. only once the three guard clauses have already confirmed a resolvable action, device, and provider connection exist. Not at the top of `handle()`. |
| Where does the Action Boundary naturally end? | Immediately after `$adapter->executeAction(...)` returns (or throws) — before `$this->logResult()` and before `$this->notifyActionFailed()`. |
| Where does Provider execution begin? | Inside `HomeAssistantAdapter::executeAction()`, specifically at the `Http::...->post(...)` call — after the unsupported-action check, which is pure business logic and happens first. Phase 7B.4.3 does not instrument this call; it is reserved for Phase 7B.4.4. |
| Do retries create independent executions? | **Structurally yes, but the question is moot today** — see §2.6: no exception ever escapes `handle()` in this codebase's current form, so the queue's retry mechanism (`tries = 3`) is never actually triggered. If it ever were, each retried attempt would be a completely separate `handle()` invocation with its own `smart_home.action` span — exactly like each Queue consumer attempt already gets its own auto-instrumented consumer span (Phase 7B.2). No cross-attempt correlation exists or is added by this phase. |
| Do multiple provider executions exist inside one action? | **No.** Exactly one call to `$adapter->executeAction()` happens per `handle()` invocation — no loop, no internal retry inside the wrapped segment. Confirmed by reading `SmartHomeActionJob::handle()` and `HomeAssistantAdapter::executeAction()` in full. "One action execution" and "one provider execution" are 1:1 today. |

### 2.5 Why the boundary is narrower than `handle()`

The three guard clauses (§2.1 steps 2–4) represent **"there is nothing to execute"**, not an attempted execution:

- None of them ever resolves a provider adapter or performs any I/O.
- None of them corresponds to a value in this phase's allowed `ixora.action.outcome` set (`success` / `failure` / `unsupported`) — inventing a fourth value (e.g. `not_found`) was considered and rejected, because the brief gives an exhaustive, closed list and because these guard clauses already have their own, unmodified logging (out of scope this phase).
- This mirrors the precedent Phase 7B.4.2 set at the Dispatch boundary: a precondition failure that occurs *before* the real boundary work (there, `ScheduleAutomationValidator::validate()`; here, the three `null` guards) never creates a span. "Business preparation" in the brief's Boundary Ownership section is read as *preparing the already-resolved action for execution* (i.e. resolving its provider adapter), not as *the SQL lookup that discovers whether an action still exists at all*.

Logging (`$this->logResult()`) and push notification (`$this->notifyActionFailed()`) are excluded from the boundary because:

- Logging changes are explicitly out of scope this phase (Phase 7B.4.7).
- The Domain Execution Review (Phase 7B.4.1) already found push notification to be a decoupled, fire-and-forget side effect that never affects — and is not part of — the action's own outcome; the brief's outcome vocabulary (`success`/`failure`/`unsupported`) describes the *provider call's* result, not whether a push was sent.

### 2.6 Retry behavior — a load-bearing, pre-existing fact this phase does not change

`SmartHomeActionJob` declares `public int $tries = 3;`, but **both** of `handle()`'s own `catch` blocks (`UnsupportedSmartHomeActionException` and the generic `Throwable` catch-all) unconditionally log and swallow — the job's docblock states this as deliberate policy: *"A failed ActionResult ... is NOT retried"*, *"Any unexpected Throwable is caught and logged so it never breaks the audio flow or floods the queue with retries."* No exception has ever escaped `handle()` in this codebase, meaning Laravel's queue retry mechanism (which activates only when `handle()` throws) has never actually been triggered by this job in production, regardless of the `tries = 3` configuration.

This phase's Failure Model (`recordException()`/`setError()`/`end()`/rethrow unchanged — §5) does not change this fact: `SmartHomeActionTelemetry::wrap()` rethrows only far enough for `handle()`'s own, pre-existing, byte-for-byte-unchanged `catch` blocks to catch it exactly as they always did. The exception still never escapes `handle()` itself. §7 verifies this explicitly.

---

## 3. Why the wrapped segment does not include `logResult()`/`notifyActionFailed()`, and why exception classification is caller-supplied

Unlike Phase 7B.4.2 (which could wrap the entire `dispatch()` call because that call's return value alone described the outcome), this boundary's "action outcome" depends on distinguishing three cases that only the caller can classify without pulling Smart Home domain types into the Telemetry layer:

- A returned `ActionResult` with `success === true` → `success`.
- A returned `ActionResult` with `success === false` → `failure`.
- A thrown `UnsupportedSmartHomeActionException` → `unsupported`.
- Any other thrown `Throwable` (e.g. `ProviderAdapterResolver` rejecting an unknown provider) → `failure`.

`SmartHomeActionTelemetry::wrap()` therefore takes two caller-supplied classifier closures — `classifyResult` and `classifyException` — instead of importing `App\SmartHome\Exceptions\UnsupportedSmartHomeActionException` or `App\SmartHome\DTOs\ActionResult` itself. This is the same technique Phase 7B.4.2's `SmartHomeDispatchTelemetry::wrap()` used with its `extractCounts` closure to avoid importing `SmartHomeDispatchResult` — generalized here to exception classification as well as result classification. `SmartHomeActionJob` (which already imports both domain types) supplies the classification logic; the Telemetry layer never needs to know either type exists.

---

## 4. Boundary

| Aspect | Definition |
| --- | --- |
| **Owns** | Provider resolution (`ProviderAdapterResolver::forProvider()`) + provider execution (`ProviderAdapter::executeAction()`) + outcome classification, for one `SmartHomeActionJob::handle()` invocation. |
| **Begins** | Immediately before `$resolver->forProvider($connection->provider)` — only once all three guard clauses have already passed. |
| **Ends** | Immediately after `executeAction()` returns (success or a failed `ActionResult`) or throws (`unsupported` or `failure`) — always before `$this->logResult()` and `$this->notifyActionFailed()` run. |
| **Never includes** | The three guard-clause early returns (§2.5), `$this->logResult()`, `$this->notifyActionFailed()`/`PushNotificationEvents`, or any Provider-communication detail inside `executeAction()` (HTTP method, URL, status code, response body — reserved for Phase 7B.4.4). |

### Parent span

`App\Telemetry\SmartHome\SmartHomeActionTelemetry` calls `Tracer::startSpan()`, never `Tracer::activeSpan()` — exactly like `SmartHomeDispatchTelemetry`. Per the `Tracer` contract, `startSpan()` always creates a **child** of whatever span is currently active and activates the new span as current for its own duration. When `SmartHomeActionJob::handle()` runs inside a real Worker (async, production `database` queue driver) or the `sync` queue driver's own internal "process" span (Phase 7B.2 §2), that Queue Consumer span is the active span `smart_home.action` nests under — satisfying "reuse the existing Queue Consumer span" and "never create duplicate root spans" structurally, with no code in this class needing to inspect what kind of span is active.

Because that Queue Consumer span is itself already parented under `smart_home.dispatch` via the existing TraceContext propagation Phase 7B.4.2 documented and reused (its §2), the full expected hierarchy assembles for free:

```
HTTP / Console
  └─ smart_home.dispatch
       └─ Queue Consumer ("process {destination}" / sync "process")
            └─ smart_home.action
```

No correlation ID, context object, or custom propagation was added to produce this — identical in spirit to Phase 7B.4.2 §2's conclusion.

### Relationship with the future Provider Boundary (Phase 7B.4.4)

`smart_home.action`'s own span remains open for the entire duration of the wrapped `executeAction()` call (§5) — including while any future `smart_home.provider` span (Phase 7B.4.4) would be created and closed inside that same call. This is a structural consequence of `executeAction()` being a single synchronous PHP call: the Action span cannot "finish" before a provider span nested *inside* that call begins, because ending a span requires knowing the call's outcome, which is only available after it returns. When Phase 7B.4.4 is implemented, its span will call `Tracer::startSpan()` from inside `HomeAssistantAdapter::executeAction()` (or a thin wrapper around it) while `smart_home.action` is still the active span — nesting `smart_home.provider` as its child for free, via the exact same activation mechanism this phase itself relies on to nest under the Queue Consumer span. This phase adds no code to make that possible or to prevent it; it is a natural consequence of `Tracer::startSpan()`'s existing contract.

---

## 5. Span

| Property | Value |
| --- | --- |
| Name | `smart_home.action` |
| Count per `handle()` invocation that reaches the boundary | Exactly one — verified by `SmartHomeActionTelemetryTest` ("never creates more than one span per call") and `SmartHomeActionBoundaryIntegrationTest` (one span per successful/failed/unsupported execution). |
| Attributes | `ixora.action.provider` (`home_assistant` \| `future`, reserved), `ixora.action.outcome` (`success` \| `failure` \| `unsupported`), `ixora.action.retry` (`true` \| `false`) — nothing else. |
| On success | `setAttribute('ixora.action.outcome', ...)` from `classifyResult($result)`, then `end()`. |
| On failure | `setAttribute('ixora.action.outcome', ...)` from `classifyException($exception)`, `recordException()`, `setError()`, then `end()` — the original exception is always rethrown unchanged. |
| Never contains | `action_id`, `device_id`, `entity_id`, `provider_device_id`, `schedule_id`, `vibe_id`, `user_id`, any database ID, provider URLs, IP addresses, headers, tokens, credentials, payloads, JSON, request/response bodies, or trace/span IDs — verified directly by `SmartHomeActionTelemetryTest`'s "never sets a forbidden attribute" assertion, which enumerates exactly the three allowed attribute keys and scans every key for forbidden substrings. |

`ixora.action.provider=future` and the reserved `SmartHomeActionOutcome::Unknown` case are currently-unused enum cases — mirror the enum-reservation convention already used elsewhere in this Telemetry layer (e.g. `SmartHomeDispatchEntryPoint::Future`, `SchedulerOutcome::Unknown`). `Unknown` is reachable only as a fail-open fallback if a caller-supplied classifier closure itself throws (§6) — it never reflects a real business outcome.

`ixora.action.retry` reflects `$this->attempts() > 1`, i.e. Laravel's own `InteractsWithQueue::attempts()` job-attempt counter (which returns `1` when the job has no underlying queue `Job` instance, e.g. when invoked directly as in most of this repository's existing tests) — not a custom counter. Because no exception currently escapes `handle()` (§2.6), this attribute is `false` in every real execution today; it remains a correct, forward-compatible attribute if that ever changes.

---

## 6. Fail-open

Every public path through `SmartHomeActionTelemetry::wrap()` is safe:

- `startSpan()` failure (a broken `Tracer`) falls back to a local inert `Span` implementation (mirrors `SmartHomeDispatchTelemetry::inertSpan()`/`SchedulerExecutionTelemetry::inertSpan()` exactly) — `execute()` still runs, and its result (or thrown exception) is still returned/rethrown unchanged.
- A caller-supplied classifier closure (`classifyResult`/`classifyException`) that itself throws never affects the real result — it is caught internally and degrades only the span's own `ixora.action.outcome` attribute to the reserved `Unknown` value.
- Attribute-setting, exception-recording, and span-ending failures are caught and swallowed (`safely()`) — never propagate.
- A genuine business exception from `execute()` (provider resolution or `executeAction()` throwing) is recorded on the span (`recordException()`/`setError()`) and then **always rethrown unmodified** — telemetry observes the failure, it never converts, swallows, or masks it, and it never alters which of `handle()`'s own two `catch` blocks receives it.

Verified directly by `SmartHomeActionTelemetryTest`: "a broken Tracer never prevents `wrap()` from running `execute()` or returning its result", "a broken Tracer combined with a business failure still rethrows the original exception unchanged", and "a classifyResult callback that throws never affects the returned result — outcome degrades to unknown". Verified end-to-end by `SmartHomeActionBoundaryIntegrationTest`'s "a broken Tracer never prevents the job from executing the action or notifying on failure".

---

## 7. Retry and failure model — explicitly unchanged

- `SmartHomeActionJob::$tries = 3` and `$timeout = 30` are unmodified.
- Both of `handle()`'s pre-existing `catch` blocks are byte-for-byte unchanged — same log messages, same log levels, same push-notification behavior (only on the generic `Throwable` path, never on `UnsupportedSmartHomeActionException`, per ADR-026).
- `SmartHomeActionTelemetry::wrap()` only ever rethrows the *same* exception object it caught (never wraps, converts, or replaces it) — verified by `SmartHomeActionTelemetryTest`'s exception-identity assertions (`->toBe($exception)`).
- `tests/Feature/SmartHome/SmartHomeActionJobTest.php` (pre-existing, 18 tests) passes unmodified after this phase's changes (only its `runJob()` test helper was updated to pass the new `SmartHomeActionTelemetry` constructor argument `handle()` now requires — no assertion in that file changed).

---

## 8. What was intentionally excluded

Per the brief, this phase adds none of the following (all reserved for later phases):

- Any instrumentation of `HomeAssistantAdapter`'s HTTP call, request/response bodies, status codes, or provider URLs (Phase 7B.4.4 — Provider Boundary).
- Any `Counter`/`Histogram`/`UpDownCounter`/observable instrument — no metric of any kind (Phase 7B.4.6). Verified by `SmartHomeActionTelemetryTest`'s "never records a counter, histogram, or up-down counter" and the dependency-rule tests' ban on importing `Counter`/`Histogram`/`UpDownCounter`/`Meter`.
- Any `LogTap`, structured log enrichment, or logging change of any kind (Phase 7B.4.7). Verified by the dependency-rule tests' ban on any `Log::` usage inside the three new files.
- Any new domain abstraction — no `SmartHomeExecution`, `ActionExecution`, `ExecutionAggregate`, `ExecutionHistory`, `ExecutionManager`, `ExecutionContext`, `ExecutionPipeline`, `ExecutionLifecycle`, `BusinessExecution`, or `ActionContext` exists anywhere in this diff. `SmartHomeActionProvider` and `SmartHomeActionOutcome` are plain, Telemetry-layer-only enums used solely as span-attribute value types.
- Any database, API, or frontend change. `App\SmartHome\DTOs\ActionResult`'s shape, `SmartHomeActionJob`'s public properties (`$vibeDeviceActionId`, `$timeout`, `$tries`, `$queue`), and every log message/context key are byte-for-byte unchanged.

---

## 9. Accepted limitations

- **The Action span cannot structurally "finish before Provider execution begins"** in the literal sequential sense the brief's Boundary Isolation section describes, because `executeAction()` is one synchronous PHP call — see §4, "Relationship with the future Provider Boundary". The Action span *does* end before `logResult()`/`notifyActionFailed()` run, and *will* nest (not overlap) a future `smart_home.provider` span as its child rather than merging the two boundaries into one span — which is the isolation property that is actually achievable and testable today, and the one `SmartHomeActionBoundaryIntegrationTest` verifies ("wraps exactly the single provider HTTP call — no extra calls, no duplicate spans").
- **The three guard-clause skip paths remain unobserved** — by design (§2.5); they were already, and remain, visible only via their own unmodified `Log::warning()` calls.
- **`ixora.action.provider=future` and `SmartHomeActionOutcome::Unknown` are currently unreachable** in real traffic — reserved for a provider that does not yet exist (`future`) and a classifier failure that fail-open prevents from ever surfacing as a real business signal (`Unknown`).
- **Retry behavior investigated but not exercised end-to-end via a real queue attempt ≥ 2** — because no exception escapes `handle()` today (§2.6), `SmartHomeActionBoundaryIntegrationTest`'s retry-attribute test constructs a stand-in `job` object reporting `attempts() === 2` directly, rather than driving an actual Laravel queue retry (which would require an exception to escape `handle()`, contradicting the job's own, unmodified failure policy).
- **No fan-in visibility yet across multiple actions of one dispatch** — this span reports one action's own outcome; aggregating success/failure counts across a `Vibe`'s actions remains outside this phase's scope (the Dispatch boundary's `dispatched_actions`/`skipped_actions` count *dispatch* decisions, not post-execution outcomes, per Phase 7B.4.2 §10).

---

## 10. Future phases

- **Phase 7B.4.4 — Provider Boundary:** instruments `HomeAssistantAdapter::executeAction()`'s actual HTTP call as its own `smart_home.provider` span, nested under `smart_home.action` for free via the same `Tracer::startSpan()` activation mechanism this phase relies on (§4). No correlation work is needed to make that nesting happen.
- **Phase 7B.4.6 — Business metrics:** first `ixora.action.*`-style metrics; this phase's `ixora.action.outcome`/`.provider` attribute vocabulary is a natural label set for that phase's counters.
- **Phase 7B.4.7 — Business logging:** first structured log enrichment for Smart Home action execution; may reuse `SmartHomeActionProvider`/`SmartHomeActionOutcome` for consistent classification once a log tap is introduced.
- **Phase 7B.5 — Push Notifications**, **Phase 7B.6 — External Providers:** unaffected by, and independent of, this phase.

---

## 11. Tests

| File | Covers |
| --- | --- |
| `tests/Unit/Telemetry/SmartHome/SmartHomeActionTelemetryDependencyRuleTest.php` | The three new files exist; no OpenTelemetry SDK/API import; no concrete Telemetry implementation import; no `App\Models`/`App\SmartHome`/`App\Jobs`/`App\Http\Controllers`/`App\Console\Commands`/`App\PushNotifications` import; `SmartHomeActionTelemetry` depends only on `Tracer`/`Span`/`Throwable`; the two enums have zero imports; no metric-contract import; no `Log::` usage. |
| `tests/Feature/Telemetry/SmartHome/SmartHomeActionTelemetryTest.php` | Span creation/naming/`provider`/`retry` attributes; outcome sourced from the caller-supplied `classifyResult`/`classifyException` closures; forbidden-attribute exhaustiveness (key allow-list + substring scan); span ends exactly once; `execute()` runs strictly before `end()`; no duplicate spans across repeated calls; `startSpan()` used (never `activeSpan()`); exception path records + errors + ends + rethrows unchanged (identity-checked); `classifyResult` never called on the failure path; fail-open under a broken `Tracer` (success and failure sub-cases) and under a throwing classifier; zero metrics recorded; `SmartHomeActionProvider::fromProviderSlug()` normalization (known slug + reserved domain slugs + unknown slug, all → `Future` except `home_assistant`). |
| `tests/Feature/Telemetry/SmartHome/SmartHomeActionBoundaryIntegrationTest.php` | Real wiring through `SmartHomeActionJob::handle()`: success/failure/unsupported/unexpected-resolver-error each produce exactly one correctly-tagged span; the three guard-clause skip paths (missing action, deleted device) create **no** span at all; exactly one provider HTTP call per span with no duplication; `ixora.action.retry` reflects a real vs. stand-in `attempts()` value; fail-open under a broken `Tracer` combined with `Bus::fake()`/`Http::fake()`. |
| `tests/Feature/SmartHome/SmartHomeActionJobTest.php` (pre-existing, 18 tests, unmodified assertions) | Still fully green — proves this phase changed no observable job behavior, logging, or push-notification behavior. |

Full suite: **929/929 passing** (869 pre-existing at the start of Phase 7B.4.2 + 25 from Phase 7B.4.2 + 35 new in this phase), 2 pre-existing risky tests unrelated to this phase (`HttpRequestTelemetryMiddlewareTest`, Phase 7B.1), `pint --test` clean.

---

## 12. Files touched

**New:**

- `app/Telemetry/SmartHome/SmartHomeActionTelemetry.php`
- `app/Telemetry/SmartHome/SmartHomeActionProvider.php`
- `app/Telemetry/SmartHome/SmartHomeActionOutcome.php`
- `tests/Unit/Telemetry/SmartHome/SmartHomeActionTelemetryDependencyRuleTest.php`
- `tests/Feature/Telemetry/SmartHome/SmartHomeActionTelemetryTest.php`
- `tests/Feature/Telemetry/SmartHome/SmartHomeActionBoundaryIntegrationTest.php`

**Modified (registration/wiring only, no business-logic change):**

- `app/Telemetry/Providers/TelemetryServiceProvider.php` — registers the `SmartHomeActionTelemetry` singleton.
- `app/Jobs/SmartHome/SmartHomeActionJob.php` — wraps the existing provider-resolution + `executeAction()` call; threads the new `SmartHomeActionTelemetry $actionTelemetry` dependency through `handle()`'s signature; both `catch` blocks and every log message are unchanged.
- `tests/Feature/SmartHome/SmartHomeActionJobTest.php` — `runJob()` test helper updated to pass the new constructor argument `handle()` now requires; no assertion changed.

**Untouched:**

- `app/SmartHome/ProviderAdapterResolver.php`
- `app/SmartHome/Adapters/HomeAssistantAdapter.php`
- `app/SmartHome/Contracts/ProviderAdapter.php`
- `app/SmartHome/DTOs/ActionResult.php`
- `app/SmartHome/Exceptions/UnsupportedSmartHomeActionException.php`
- `app/PushNotifications/Services/PushNotificationEvents.php`
- `app/Telemetry/SmartHome/SmartHomeDispatchEntryPoint.php`
- `app/Telemetry/SmartHome/SmartHomeDispatchTelemetry.php`
- Every domain model and migration.
