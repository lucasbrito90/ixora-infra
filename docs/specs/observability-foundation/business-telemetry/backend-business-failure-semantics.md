# Backend Business Failure Semantics — Phase 7B.4.5 (`back_vibes`)

**Status:** Complete
**Repo:** `back_vibes` (Laravel 13, PHP 8.3+)
**Feature ID:** `observability-foundation/mvp`
**Type:** Architecture review + one narrowly-scoped span-status correction it justified. No metrics, no logs, no dashboards, no behavior change.
**Prerequisite:** [domain-execution-review.md](domain-execution-review.md) (Phase 7B.4.1 — authoritative pipeline/failure-model reference) · [backend-smart-home-dispatch-boundary.md](backend-smart-home-dispatch-boundary.md) (Phase 7B.4.2) · [backend-smart-home-action-execution.md](backend-smart-home-action-execution.md) (Phase 7B.4.3) · [backend-smart-home-provider-boundary.md](backend-smart-home-provider-boundary.md) (Phase 7B.4.4) · [traces-philosophy.md](../../../architecture/traces-philosophy.md) · [logs-philosophy.md](../../../architecture/logs-philosophy.md) · [metrics-philosophy.md](../../../architecture/metrics-philosophy.md) · [telemetry-decision-guide.md](../../../architecture/telemetry-decision-guide.md)

---

## 1. Purpose

Phases 7B.4.2–7B.4.4 each instrumented one Business Telemetry boundary (`smart_home.dispatch`, `smart_home.action`, `smart_home.provider`) without pausing to ask, as a single cross-cutting question: **what does each of those spans' existing failure-handling code actually mean, and is it internally consistent?**

Phase 7B.4.5 answers that question. It is **not** an implementation phase — its deliverable is a formal semantic model (this document) that every later Business Telemetry phase (7B.4.6 Business Metrics, 7B.4.7 Business Logging, and any future dashboard/alerting work) must treat as the authoritative reference for:

- What every possible Smart Home execution outcome *is* (§3).
- Whether that outcome is a **Business** failure, an **Infrastructure** failure, or something else (§3).
- Whether the span carrying that outcome should be `ERROR` or stay `OK` (§4–§6).
- Whether the existing three-value `ixora.action.outcome` vocabulary is complete (§7).
- How a failure at one layer propagates — or explicitly does not propagate — to its parent span (§8).
- How retries relate to failure (§9).
- Which failures deserve a trace, a log, both, or neither (§10) — and, separately, a metric (§11) — **without implementing any of it**, since metrics and logs are out of this phase's boundary (§12).

| In scope | Out of scope (later phases / other boundaries) |
| --- | --- |
| Formal failure taxonomy across the whole Smart Home Action Execution pipeline (dispatch → queue → action → provider → HTTP client) | Business metrics (Phase 7B.4.6) |
| Business/Infrastructure/Platform classification for every discovered outcome | Business logging (Phase 7B.4.7) |
| Span status (`ERROR` vs `OK`) policy, and correcting the one place the existing code contradicted it | Dashboards, alerting |
| Documenting retry, propagation, logging-ownership, and metrics-ownership policy | Retry implementation, Provider implementation, HTTP instrumentation, Queue instrumentation (all pre-existing and unmodified) |
| One narrowly-scoped code change to `SmartHomeActionTelemetry` (§6.4), justified entirely by this review | Any change to `ActionResult`, `ProviderAdapter`, `SmartHomeActionJob`'s business logic, ownership/validation, or persistence |

---

## 2. Mandatory architecture review — sources read

Every class named in the brief was re-read in full for this phase, in addition to the four platform philosophy guides:

| Source | What it contributed to this review |
| --- | --- |
| `App\Jobs\SmartHome\SmartHomeActionJob` | The authoritative failure model — three early-return guard clauses (no span), one `try` block wrapping `SmartHomeActionTelemetry::wrap()`, two `catch` blocks (`UnsupportedSmartHomeActionException`, `Throwable`) that both **swallow** the exception and return normally |
| `App\Telemetry\SmartHome\SmartHomeActionTelemetry` | Found the one genuine inconsistency this phase corrects (§6.4) — every exception path unconditionally called `setError()`, including the `unsupported` classification |
| `App\Telemetry\SmartHome\SmartHomeProviderTelemetry` | Confirmed its own exception path is already correct — it has no "expected business exception" case to exempt (§6.5) |
| `App\Telemetry\SmartHome\SmartHomeDispatchTelemetry` | Confirmed its own exception path is already correct for the same reason (§6.6) |
| `App\SmartHome\Adapters\HomeAssistantAdapter` | Confirmed exactly one throw site (`UnsupportedSmartHomeActionException`, before any I/O) and exactly one internally-caught transport exception (`ConnectionException`, converted to `ActionResult`, never rethrown) |
| `App\SmartHome\Contracts\ProviderAdapter` | Confirmed the interface's own documented error-handling contract matches the concrete adapter exactly |
| `App\SmartHome\ProviderAdapterResolver` | Confirmed it throws a plain `InvalidArgumentException` for an unregistered provider slug — pure in-memory, no I/O, occurs **before** any Provider span can exist |
| `App\SmartHome\DTOs\ActionResult` | Confirmed its shape (`success`, `status_code`, `response`, `error_message`) and that it is never itself thrown — it is always a *returned* value |
| `App\SmartHome\Exceptions\UnsupportedSmartHomeActionException` | Confirmed it extends `InvalidArgumentException`, and that its message embeds the raw `action_type` string — traced to confirm that value is bounded (§13) |
| `App\SmartHome\Exceptions\ProviderConnectionException` | **Confirmed unreachable from this pipeline** (§2.1) — a finding in its own right |
| `App\Telemetry\Queue\QueueExecutionTelemetry` / `QueueOutcome` | Source of the cross-cutting propagation finding in §8.3 — the Queue layer's own success/failure classification is **orthogonal** to, and can silently disagree with, the Business layer's |
| `App\Telemetry\Contracts\{Tracer,Span}` | Confirmed `Span::setError()` and `Span::recordException()` are independent operations — recording an exception does not itself set status, and this phase's fix (§6.4) relies on that independence |
| [`traces-philosophy.md`](../../../architecture/traces-philosophy.md) §8 | Source of the platform-level rule this review formalizes for Smart Home: *"Do not set `ERROR` on parent spans unless the parent itself failed"* and the outcome/status/log table already distinguishing `success` / `expected skip` / `failure` |
| [`logs-philosophy.md`](../../../architecture/logs-philosophy.md) §12 | Source of the existing "Unsupported action type → ✅ `warning`" and "HA action succeeded → ❌ No log" precedents this document extends to the full taxonomy |
| [`metrics-philosophy.md`](../../../architecture/metrics-philosophy.md) §11 | Source of the reserved `ixora.smart_home.action.total{outcome=*,provider=*}` example this document's §11 builds on for Phase 7B.4.6 |
| [`telemetry-decision-guide.md`](../../../architecture/telemetry-decision-guide.md) §6–§8 | Source of the signal-choice decision rule this document applies mechanically in §10/§11 |
| [`domain-execution-review.md`](domain-execution-review.md) §7, §14 | The pre-existing, authoritative "Failure model" table (Part 7) and open questions (U-1 through U-9) this document treats as ground truth rather than re-deriving |

No source code was read that contradicted an assumption in the brief in a way that blocked the review — the one genuine surprise (§6.4) was found, not assumed, exactly as the brief anticipated might happen.

### 2.1 A finding worth stating up front: `ProviderConnectionException` does not apply to this pipeline

The brief's own example list (§1.3 of the task) asks this review to classify `ProviderConnectionException` alongside `UnsupportedSmartHomeActionException`/`ConnectionException`/`ActionResult(success=false)`. Reading `ProviderAdapter`'s docblock and `HomeAssistantAdapter::executeAction()` in full confirms it is thrown **only** by `listDevices()` (and used internally by `testConnection()`'s sibling logic) — never by `executeAction()`. Per `domain-execution-review.md` §1.3, `listDevices()`/`testConnection()` belong to the **Provider Device Sync** pipeline, an adjacent, explicitly out-of-scope pipeline for all of Phase 7B.4's Business Telemetry work. `ProviderConnectionException` is therefore **not part of the Smart Home Action Execution failure taxonomy** — it is listed here, once, precisely so a future reader does not re-discover this gap and assume it was overlooked.

---

## 3. Failure taxonomy (§1.1) and Business/Infrastructure classification (§1.2)

Every row below is a **verified, currently-reachable-or-explicitly-noted-as-unreachable** execution outcome for one `SmartHomeActionJob::handle()` invocation, ordered by pipeline position (dispatch → queue → job guard clauses → action → provider → HTTP client). This table **is** the exhaustive list the brief asked for — cross-checked twice against `domain-execution-review.md` §7's own failure-model table and against every `catch`/`if (...=== null)`/return-early branch in the five files read in §2.

**Classification key** — Business / Infrastructure / Platform / Telemetry / Unknown, per the brief's own five categories:

- **Business** — an outcome the domain's own rules produce or expect, even when undesirable (e.g. "this action type isn't supported", "the provider rejected the command"). The system worked correctly; the *answer* was negative.
- **Infrastructure** — the system (network, database, process) failed to complete an operation it was capable of completing under normal conditions. Nothing about the domain's rules produced this; a dependency did.
- **Platform** — a queue/worker/runtime-level event (timeout, crash, restart) that is about the *execution environment*, not about Ixora's or the provider's domain logic.
- **Telemetry** — the telemetry code itself misbehaving (a broken `Tracer`, a throwing classifier closure). Must never be confused with a business or infrastructure outcome, and must never affect one (fail-open, §6.4's `Unknown` case).
- **Unknown** — reachable in principle but not narrowly attributable to one of the above without more information than the code path itself provides.

### 3.1 Dispatch boundary (`smart_home.dispatch`, Phase 7B.4.2)

| # | Outcome | Reachable how | Classification | Reasoning |
| --- | --- | --- | --- | --- |
| D1 | `VibeSmartHomeDispatchService::dispatch()` returns normally — N actions enqueued, M skipped (device relation null at enqueue time) | Every call, including the zero-actions case | **Business** | `skipped_actions` here is a designed, expected outcome (`domain-execution-review.md` §4) — the dispatch service itself never treats a skip as a failure; it counts and continues |
| D2 | `dispatch()` throws (e.g. a database error querying `VibeDeviceAction`) | Rare — requires an actual DB/connection fault during the query, not a business condition | **Infrastructure** | Nothing in `VibeSmartHomeDispatchService`'s own code path produces a domain-level throw (confirmed by `domain-execution-review.md` §7 — this service has no validator, no ownership check, no business rule that can fail here); anything reaching this `catch` is a dependency failure |

### 3.2 Queue consumer boundary (pre-existing, Phase 7B.2 — not owned by this phase, listed for propagation completeness only, §8.3)

| # | Outcome | Reachable how | Classification | Reasoning |
| --- | --- | --- | --- | --- |
| Q1 | `JobProcessed` fires (`QueueOutcome::Success`) | **Every single invocation of this job today**, regardless of the Business outcome inside `handle()` — because `handle()` always returns normally (§3.3–§3.5 all return void without throwing) | **Business outcome is orthogonal to this** | This is the single most important propagation fact in this document — see §8.3 |
| Q2 | `JobFailed` (`QueueOutcome::Failed`) | Only if something throws **outside** `handle()`'s own `try` block — i.e. during `VibeDeviceAction::with([...])->find()` or the null-check block before the `try` (e.g. the database connection itself is down) | **Infrastructure** | This is the one path where a Smart Home job can actually reach Laravel's `failed_jobs` table; per `domain-execution-review.md` §7/§14 (QA-003) this is understood to be rare in practice |
| Q3 | `JobReleasedAfterException` (`QueueOutcome::Retried`) | Same pre-condition as Q2, combined with Laravel's own automatic retry-after-exception (attempts remaining under `tries=3`) | **Platform** (queue mechanics) — see §9 | Not a business decision; Laravel's generic retry policy, unrelated to any domain rule |
| Q4 | `JobTimedOut` (`QueueOutcome::TimedOut`) | The 30s job timeout (`SmartHomeActionJob->timeout`) fires mid-execution | **Platform** | Infra/runtime-level SIGALRM, not a domain concept (`domain-execution-review.md` §8) |

### 3.3 Job guard clauses (before any span exists — Phase 7B.4.3's boundary decision)

| # | Outcome | Reachable how | Classification | Reasoning |
| --- | --- | --- | --- | --- |
| J1 | `VibeDeviceAction::find()` returns `null` ("action not found or deleted") | The row was deleted between enqueue and job execution | **Business** | An expected consequence of async execution racing a user-driven delete — not a bug, not an infra fault (`domain-execution-review.md` §4's "Device Action Resolution" duplication finding) |
| J2 | `$action->device` is `null` ("device missing") | Same race, one level deeper | **Business** | Same reasoning as J1 |
| J3 | `$device->providerConnection` is `null` ("provider connection missing") | Same race, one level deeper | **Business** | Same reasoning as J1 |

None of J1–J3 ever create a `smart_home.action` span — this was Phase 7B.4.3's own boundary-discovery finding, re-confirmed unchanged by this review (§6.1).

### 3.4 Action boundary (`smart_home.action`, Phase 7B.4.3) — only reached once J1–J3 all pass

| # | Outcome | Reachable how | Classification | Reasoning |
| --- | --- | --- | --- | --- |
| A1 | `executeAction()` returns `ActionResult(success: true)` | The provider accepted the command (2xx) | **Business** — successful | See §5 for the full `ActionResult` semantics discussion |
| A2 | `executeAction()` returns `ActionResult(success: false)` | The provider rejected the command (non-2xx) or a transport failure was internally caught (§3.5, P3) | **Business** (with an Infrastructure-flavored sub-cause, unresolvable from `ActionResult` alone — §5) | The *operation completed*; the *business result* was negative. See §5 for why this is deliberately not split into two outcomes |
| A3 | `executeAction()` throws `UnsupportedSmartHomeActionException` | `action_type` has no `ACTION_SERVICE_MAP` entry | **Business** | A deterministic, provider-agnostic configuration fact the adapter *correctly* detected — not a failed operation (§4, §6.4) |
| A4 | `ProviderAdapterResolver::forProvider()` throws `InvalidArgumentException` (unregistered provider slug) | `connection->provider` does not match any registered `ProviderType` case with an adapter | **Infrastructure** (data-integrity-adjacent) | Unlike A3, this is not a designed, expected branch of the pipeline — every `VibeDeviceAction` that reaches this point is expected to have a connection whose provider *is* registered; reaching this branch signals a configuration/data-integrity gap, not a recognized business decision (§4) |
| A5 | Any other unexpected `Throwable` escapes `$execute` (e.g. `$connection->decryptedCredentials()` throwing) | Not observed in practice; not structurally impossible | **Infrastructure/Unknown** | Genuinely unanticipated — the fail-open `Unknown` classification exists for exactly this kind of case if a caller-supplied classifier cannot identify it (§7) |

### 3.5 Provider boundary (`smart_home.provider`, Phase 7B.4.4) — only reached once A3/A4 have already **not** occurred

| # | Outcome | Reachable how | Classification | Reasoning |
| --- | --- | --- | --- | --- |
| P1 | HTTP call succeeds (2xx) | Normal success | **Business** — successful | Mirrors A1 one layer down |
| P2 | HTTP call returns non-2xx | Provider-side rejection (4xx/5xx) | **Business** | The HTTP round-trip *completed*; the provider's answer was negative — already correctly modeled as non-error by the existing code (§6.5) |
| P3 | `ConnectionException` (timeout, DNS failure, connection refused) caught inside `executeAction()`, converted to `ActionResult(success: false, status_code: null)` | Transport-level failure | **Infrastructure**, deliberately re-surfaced as a **Business** outcome | This is the one row in this table where the *cause* is infrastructure but the *code's own contract* (never throws for transport failures, §2.2) intentionally converts it into the same Business-outcome shape as P2 — see §5 |
| P4 | An unexpected `Throwable` escapes the wrapped segment entirely (e.g. credential decryption failure) | Not observed in practice; not structurally impossible | **Infrastructure** | Nothing about this path is a designed provider-response case — it means the segment could not even *attempt* the provider call |

### 3.6 HTTP client layer (pre-existing `opentelemetry-auto-guzzle`, Phase 7B.4.4's own review — not re-litigated here)

Every one of P1–P4 that involves an actual (attempted) HTTP call already has its own `SpanKind::CLIENT` span with `http.response.status_code`/exception recording, confirmed by Phase 7B.4.4's own pre-implementation review (`backend-smart-home-provider-boundary.md` §2.7). This document does not re-derive that finding; §8.5 states the propagation rule it implies.

---

## 4. Exception ownership — ERROR vs OK (§1.3)

For every exception this pipeline can produce, the question is not "did an exception occur" but "does this exception represent an operation that *failed to complete*, or an operation that *completed and correctly determined a negative business answer*?" Only the former deserves `StatusCode::ERROR`.

| Exception | Where it is caught (relative to a span) | Decision | Reasoning |
| --- | --- | --- | --- |
| `UnsupportedSmartHomeActionException` (A3) | Inside `smart_home.action`'s `$execute` closure | **Span stays OK.** `recordException()` still runs (context is always cheap and safe here — §13); `setError()` does not. | The adapter *correctly* determined the action cannot be mapped — a deterministic function of `(action_type, provider)`, not a failure of the attempt. This is the platform's own HTTP-4xx analogy (`traces-philosophy.md` §8) applied to a non-HTTP boundary |
| `InvalidArgumentException` from `ProviderAdapterResolver::forProvider()` (A4) | Inside `smart_home.action`'s `$execute` closure | **Span becomes ERROR.** | Classified `failure`, not `unsupported` — this is not a recognized business branch; it signals a data-integrity gap (a `VibeDeviceAction`/`ProviderConnection` referencing an unregistered provider) |
| Any other `Throwable` inside `$execute` (A5) | Same | **Span becomes ERROR.** | Genuinely unanticipated; the fail-open default must be to signal a problem, not silently downgrade it |
| `ConnectionException` inside `HomeAssistantAdapter::executeAction()` | **Never reaches `smart_home.provider`'s own `catch`** — caught one level deeper, inside the wrapped closure itself, and converted to a returned `ActionResult(success: false)` | **Not applicable to span status directly — see `ActionResult` semantics (§5).** No `Span::setError()` call exists for this path at all today | The code's own contract (§2.2) already decided this is not an escaping exception; by the time telemetry can see it, it is data, not a `Throwable` |
| `ProviderConnectionException` | N/A | **Not applicable** | Confirmed unreachable from this pipeline (§2.1) |
| Any `Throwable` escaping `smart_home.provider`'s wrapped closure (P4) | Inside `smart_home.provider`'s `$execute` closure | **Span becomes ERROR.** (Already correct, unchanged by this phase.) | Nothing about this path is a designed provider-response case |
| Any `Throwable` escaping `smart_home.dispatch`'s wrapped closure (D2) | Inside `smart_home.dispatch`'s `$dispatch` closure | **Span becomes ERROR.** (Already correct, unchanged by this phase.) | `VibeSmartHomeDispatchService::dispatch()` has no business-exception branch to exempt (§2, §6.6) |

**The one correction this phase makes:** `SmartHomeActionTelemetry::wrap()`'s exception-handling branch previously called `setError()` unconditionally for every `Throwable`, including one already classified as `unsupported`. That contradicted the platform's own rule and its own classification in the same line of code — the span carried `ixora.action.outcome=unsupported` (a recognized business outcome) *and* `ERROR` status (reserved, per `traces-philosophy.md` §8, for genuine failures) simultaneously. §6.4 details the fix.

---

## 5. `ActionResult` semantics (§1.4)

**Decision: `ActionResult(success: false)` is (C) — a successful execution with an unsuccessful business outcome — for every reachable path today**, with one documented nuance below.

Reasoning, addressing the three options the brief poses directly:

- **Not (A) "Business Failure" in the sense of "the business logic itself is broken."** The adapter ran exactly as designed: it built the correct HA service call, sent it, and faithfully reported what the provider said. There is no domain rule this violates.
- **Not (B) "Infrastructure Failure" as a blanket answer**, because `ActionResult(success: false)` is produced by **two structurally different causes that the DTO deliberately does not distinguish**:
  - P2 (provider returned non-2xx) — the HTTP round-trip itself succeeded; the *provider's answer* was negative. This is unambiguously (C).
  - P3 (`ConnectionException` caught and converted) — the HTTP round-trip itself did *not* complete; the cause genuinely is infrastructure (network/DNS/timeout). Yet `HomeAssistantAdapter::executeAction()`'s own contract (§2.2, confirmed unchanged since Phase 7B.4.1) converts this into the exact same `ActionResult` shape as P2 — `success: false`, `status_code: null` (the only field distinguishing it from a "provider returned a body-less error" case).
- **(C) is correct as the *span-status* and *outcome-attribute* answer for both**, because:
  1. Neither path ever throws past `executeAction()` — from `smart_home.action`'s perspective, the *operation completed*. Its own contract was honored (a result was produced, no exception propagated).
  2. This is exactly the "successful execution with unsuccessful business outcome" language `traces-philosophy.md` §8 uses for a validation-style failure surfaced as a 4xx — the pattern generalizes cleanly to a provider round-trip that completed and returned a negative result.
  3. Splitting P2 from P3 into two different `ixora.action.outcome` values (e.g. `failure` vs. `infra_failure`) was considered and rejected (§7) — the *Provider* span already carries the necessary detail one level deeper (the nested Guzzle `CLIENT` span's own `http.response.status_code` for P2, its own recorded exception for P3, per Phase 7B.4.4's own review), so `smart_home.action`'s single `failure` value does not need to re-derive that distinction to remain useful; it would only add cardinality without adding investigable detail that is not already one span away.

**The documented nuance:** because `ActionResult` itself carries no field distinguishing "provider rejected it" from "the provider was unreachable," a Business Metric built directly from `ixora.action.outcome=failure` (Phase 7B.4.6) will **conflate P2 and P3**. This is an accepted limitation (§13), not a defect this phase fixes — resolving it would require either enriching `ActionResult` (forbidden — §5 of the brief, "do not change `ActionResult` behavior") or reading the nested Provider/HTTP-client span's own attributes, which is exactly what a trace-first (not metric-first) investigation already does correctly today.

---

## 6. Span status policy (§1.5)

### 6.1 The platform's own recommendation, and whether Ixora follows it

`traces-philosophy.md` §8 already states, for the platform as a whole: *"Do not set `ERROR` on parent spans unless the parent itself failed... A failed child provider span may leave the HTTP root span as `OK` with `http.status_code=502` — the error detail lives on the child."* This is the same principle OpenTelemetry's own guidance expresses as "business failures are usually not span errors" — reserve `ERROR` for the operation *itself* failing to do what it was asked, not for it succeeding at determining a negative answer.

**Ixora follows this recommendation without exception for the Smart Home Action Execution pipeline.** This review found exactly one place the *code* did not yet follow it (§6.4) — the *policy* was never in question.

### 6.2 The rule, stated once, for reuse in future phases

> **A span becomes `StatusCode::ERROR` only when the operation it represents did not complete as designed** — an unhandled dependency failure, an unrecognized/unclassifiable exception, or an operation that could not even attempt its designed work. **A span stays `OK` (unset) when the operation completed and produced a designed, recognized outcome** — even a negative one (a rejection, an unsupported request, a validation failure) — because the *operation* succeeded at doing exactly what it was built to do: determine and report that answer.

### 6.3 Applying the rule across the three Business spans

| Span | Stays `OK` for | Becomes `ERROR` for |
| --- | --- | --- |
| `smart_home.dispatch` | Every normal return (D1) — including a batch with `skipped_actions > 0` | D2 only — `dispatch()` throwing |
| `smart_home.action` | A1 (success), A2 (failure — including the P3 sub-case), **A3 (unsupported — corrected by this phase, §6.4)** | A4, A5 |
| `smart_home.provider` | P1, P2, P3 (never throws for these — no `Span::setError()` call exists for them at all) | P4 only |

### 6.4 The fix this phase makes

Before this phase, `SmartHomeActionTelemetry::wrap()`'s `catch (Throwable $exception)` branch called `$span->setError()` unconditionally — for A3 (`unsupported`) exactly as for A4/A5 (`failure`/`unknown`). This contradicted §6.1–§6.3's own rule using the *same class's own classification* as proof: the span simultaneously carried `ixora.action.outcome=unsupported` (§6.2's "designed, recognized outcome" definition, verbatim) and `ERROR` status (reserved for the opposite case).

The fix, applied to `app/Telemetry/SmartHome/SmartHomeActionTelemetry.php`:

```php
$this->safely(function () use ($span, $outcome, $exception) {
    $span->setAttribute('ixora.action.outcome', $outcome->value);
    $span->recordException($exception);

    // Business Failure Semantics (Phase 7B.4.5): `unsupported` is a
    // recognized, expected business outcome — analogous to an HTTP 4xx —
    // never a span error. Every other exception path still errors the span.
    if ($outcome !== SmartHomeActionOutcome::Unsupported) {
        $span->setError();
    }
});
```

`recordException()` still runs unconditionally, regardless of outcome — it is a context-attaching operation, independent of span status (confirmed against the `Span` contract, §2), and full exception context is cheap, safe (§13), and useful for investigation even when the span itself is not an error. Only `setError()` is now conditional. Every other exception classification (`failure`, and the fail-open `unknown` classifier-degradation case) is unaffected — both still mark the span `ERROR`, exactly as before, because neither is a recognized business branch (§4).

No other class needed a change:

### 6.5 Why `SmartHomeProviderTelemetry` needed no change

Its `catch (Throwable $exception)` block has no classifier at all — by design (Phase 7B.4.4's own review: "No outcome attribute is recorded here"). Everything reaching that block is, by construction, P4 — an unexpected `Throwable` escaping the segment entirely, since P1–P3 never throw past `executeAction()`'s own internal handling (§3.5). There is no "expected business exception" case to exempt, because none reaches this boundary; `UnsupportedSmartHomeActionException` (the one case that would need exempting) is thrown and caught one layer up, before `smart_home.provider` is ever created (§2, `HomeAssistantAdapter::executeAction()`'s own ordering).

### 6.6 Why `SmartHomeDispatchTelemetry` needed no change

Same reasoning: `VibeSmartHomeDispatchService::dispatch()` has no business-exception branch (confirmed by `domain-execution-review.md` §7 — the dispatch service has no validator, no ownership check, nothing that can produce a recognized negative outcome via an exception; its only "negative" outcome, `skipped_actions`, is a plain counted value, never a thrown exception). Anything reaching `SmartHomeDispatchTelemetry::wrap()`'s `catch` block is D2 by definition — always ERROR-worthy.

---

## 7. Outcome ownership (§1.6)

**Decision: no new `ixora.action.outcome` value is added.** The existing three-value vocabulary (`success`, `failure`, `unsupported`, plus the reserved fail-open `unknown`) is re-verified against the full taxonomy in §3 and found complete for what this attribute needs to express:

| Taxonomy row(s) | Existing outcome | Why no new value is needed |
| --- | --- | --- |
| A1, P1 | `success` | Unambiguous |
| A2 (both P2 and P3 sub-causes) | `failure` | §5 already explains why P2/P3 deliberately share one outcome value — splitting them would add cardinality without adding information not already available one span deeper |
| A3 | `unsupported` | Unambiguous, and now correctly non-`ERROR` (§6.4) |
| A4, A5 | `failure` | Considered whether A4 ("unregistered provider") deserves its own value (e.g. `misconfigured`) — **rejected**: it is not a recognized business branch with its own product meaning the way `unsupported` is; it is an unexpected/data-integrity condition, and the existing `failure` value together with `ERROR` status and `recordException()` already fully conveys "something unexpected happened here" without inventing a fourth outcome for what is, from the product's perspective, indistinguishable from any other unclassified failure |
| Fail-open classifier degradation | `unknown` | Already reserved for exactly this (mirrors `QueueOutcome::Unknown`, `SchedulerOutcome::Unknown`) — confirmed still the right, and only, use for it |
| D1 (dispatched/skipped counts) | *(no single `outcome` attribute — `ixora.dispatch.dispatched_actions`/`ixora.dispatch.skipped_actions` counts instead)* | Unchanged from Phase 7B.4.2's own design; a dispatch is not a single pass/fail answer, it is a batch of them, so a scalar `outcome` attribute was never the right shape here and this review found no reason to add one |
| J1–J3 (guard-clause skips) | *(no span, no outcome attribute — Log only, §10)* | Confirmed still correct — these never reach a span at all (§3.3), so there is no attribute to own |
| Q1–Q4 (Queue-level) | `QueueOutcome::{Success,Failed,Released,Retried,TimedOut,Unknown}` | Owned by Phase 7B.2, not this phase — listed in §3.2 for propagation completeness only, not reopened here |

No `ixora.provider.outcome` attribute is introduced either — Phase 7B.4.4's own decision to omit one (confirmed unchanged by this review, §6.5) stands: `smart_home.provider`'s status (`OK` for P1–P3, `ERROR` for P4 only) already conveys everything the span itself is responsible for; the Guzzle `CLIENT` span one level deeper carries the transport-level detail.

---

## 8. Failure propagation (§1.7)

The brief's own hierarchy sketch — `HTTP/Console/Scheduler → smart_home.dispatch → Queue Consumer → smart_home.action → smart_home.provider → HTTP Client` — is confirmed accurate (§2, and re-confirmed against Phases 7B.4.2–7B.4.4's own review documents) with one addition: `smart_home.dispatch` and the `Queue Consumer` span do **not** actually share a trace in the common case (§8.2).

### 8.1 Rule, stated once for reuse: a child's failure never auto-promotes a parent's status

Per §6.1/§6.2, each span's status reflects **only whether that span's own operation completed as designed** — never whether a descendant failed. A failed `smart_home.provider` span (P4, `ERROR`) does not, and must not, cause `smart_home.action` to also become `ERROR` "because its child failed" — `smart_home.action`'s own status is decided purely by whether *its own* operation (provider resolution + `executeAction()` call) completed as designed, which is exactly what already happens today: `SmartHomeProviderTelemetry::wrap()` rethrows P4 unchanged, `SmartHomeActionTelemetry::wrap()`'s own `catch` block classifies *that same rethrown exception* independently (via its own `$classifyException` closure) and decides `smart_home.action`'s status on its own terms (§4, A5 in this case). The two spans' statuses can, and structurally must be allowed to, disagree.

### 8.2 Where each failure originates and stops

| Failure | Originates at | Stops at (span-status boundary) | Do ancestors inherit `ERROR`? |
| --- | --- | --- | --- |
| D2 (dispatch throws) | `smart_home.dispatch` | `smart_home.dispatch` itself | No — the HTTP/Console/Scheduler root span reflects only its *own* outcome (e.g. HTTP 500 if the controller lets the exception become one); it is never force-marked `ERROR` merely because a child span was |
| Q2/Q3/Q4 (Queue-level) | The Queue Consumer span (pre-existing auto-instrumentation + `QueueExecutionTelemetry`) | The Queue Consumer span | Not applicable to Business spans — no `smart_home.action` span exists yet at this point (§3.3) |
| J1–J3 (guard-clause skip) | Nowhere near a span — a plain `return` inside `handle()` | N/A — no span, no status to set | N/A |
| A3 (unsupported) | `smart_home.action` (thrown one layer down, inside `HomeAssistantAdapter`, but caught by `smart_home.action`'s own `wrap()`) | `smart_home.action` — stays `OK` (§6.4) | No ancestor marked `ERROR` — correct, since nothing failed |
| A4/A5 (failure/unknown) | `smart_home.action` | `smart_home.action` — becomes `ERROR` | No — the Queue Consumer span still reports `Success` (§8.3) because `SmartHomeActionJob::handle()` itself never lets this exception escape (it is caught by the job's own generic `catch (Throwable $e)` and swallowed, §2) |
| P2/P3 (business-negative `ActionResult`) | `smart_home.provider` | `smart_home.provider` — stays `OK` (never even reaches a `catch` block — it is a returned value, §5) | No ancestor sees an exception at all for this path |
| P4 (unexpected throw) | `smart_home.provider` | `smart_home.provider` — becomes `ERROR`; rethrown | `smart_home.action` independently classifies the *same* rethrown exception (typically `failure`/A5) and becomes `ERROR` on its own terms (§8.1) — this is the one case where two adjacent spans legitimately agree, because both are reacting to a genuinely unexpected condition, not because one mechanically inherited the other's status |

### 8.3 The load-bearing cross-cutting fact: Queue-level "success" and Business-level "failure" routinely coexist

Because `SmartHomeActionJob::handle()` never lets **any** outcome inside its own `try` block escape uncaught (§2 — both its `catch` blocks swallow and return normally), `JobProcessed`/`QueueOutcome::Success` fires for **every** business outcome in §3.4/§3.5 except the pre-`try` guard-clause paths (which also complete normally) and the near-unreachable pre-`try` DB-failure case (Q2–Q4). In other words: **`ixora.queue.outcome=success` on the Queue Consumer span means only "the job process did not crash" — it carries zero information about whether the Smart Home action itself succeeded.** An on-call engineer who filters Tempo by `ixora.queue.outcome=failed` looking for failed Smart Home actions will find **none** of them (§3.2, Q1) — they must instead filter by `smart_home.action`'s own `ixora.action.outcome=failure` (or, once Phase 7B.4.6 ships, the corresponding metric). This document names this fact explicitly so no future dashboard or alert conflates the two.

### 8.4 Dispatch-to-Action propagation is enqueue-only, not outcome-aware (unchanged, re-confirmed)

`smart_home.dispatch` ends (and reports its own status/counts) the moment `SmartHomeActionJob::dispatch()` calls return — before any job has actually executed (Phase 7B.4.2's own documented design, `domain-execution-review.md` U-5). No business failure inside any enqueued job's later execution can ever propagate back to an already-ended `smart_home.dispatch` span. This is not a gap this phase can close (it would require a fan-in mechanism — explicitly out of scope, `domain-execution-review.md` §15.3) — it is documented here as a propagation boundary, not a defect.

### 8.5 Provider-to-HTTP-client propagation

`smart_home.provider` nests the Guzzle `CLIENT` span for free (Phase 7B.4.4's own finding, §3.6). A P2 (non-2xx) or P4-adjacent HTTP-level failure is fully visible on that nested span (`http.response.status_code`, or a recorded exception) without `smart_home.provider` needing to duplicate it — and, per §6.3, `smart_home.provider` itself stays `OK` for P2 regardless of what the Guzzle span's own status convention is for that status code, because per §8.1 a parent's status is never mechanically inherited from a child's.

---

## 9. Retry semantics (§1.8)

The brief asks whether retries should be considered failures, temporary failures, or independent events. **Decision: independent events — a retry is never itself a failure signal; it is a fact about *how many times* an operation has been attempted, orthogonal to whether any given attempt succeeded.**

| Retry mechanism | Reviewed status | Classification | Reasoning |
| --- | --- | --- | --- |
| **Queue retries** (`SmartHomeActionJob->tries = 3`) | Confirmed, again, structurally inert in the common case — `handle()`'s own two `catch` blocks swallow every business/infra failure it can produce inside its `try`, so Laravel's retry mechanism only ever triggers for the rare pre-`try` DB-failure case (Q2/Q3, §3.2) | **Platform-level, independent event** | A retried attempt is a *new* execution, not a continuation of a failed one — Laravel enqueues a fresh job message; `SmartHomeActionTelemetry::wrap()` is called again from scratch on the next attempt, producing an entirely new `smart_home.action` span (`ixora.action.retry=true`, Phase 7B.4.3) with its own independent outcome. Nothing about "this is attempt 2" makes attempt 2's own classified outcome any more or less a failure than attempt 1's would have been |
| **Provider retries** | Confirmed, again, that `HomeAssistantAdapter::executeAction()` performs exactly one HTTP call per invocation — no internal loop, no built-in backoff (§2, re-confirmed from Phase 7B.4.3's own review) | **Not applicable — does not exist** | There is nothing to classify; documented here only to close the brief's own question explicitly rather than leave it silently unanswered |
| **Future retry strategies** | None implemented anywhere in this pipeline (`domain-execution-review.md` §8) | **Not applicable — reserved for a future phase** | Any future retry design (e.g. a provider-level exponential backoff) would need its own review at that time; this document takes no position on a mechanism that does not exist |

**Consequence for span design:** because each retry attempt gets a fresh, independent `smart_home.action` span rather than reopening or amending a prior one, no cross-attempt aggregation (e.g. "this action ultimately succeeded after 2 retries") is visible from any single span — it can only be reconstructed post-hoc by correlating multiple spans/logs for the same `vibe_device_action_id` (which, per §13, never appears on a span attribute — it would have to come from a log field). This is an accepted limitation (§13), not something this phase's scope permits changing (introducing a cross-attempt correlation ID is explicitly forbidden by the brief, §5 — "introduce correlation IDs").

**Consequence for metrics (preview of §11, not implemented here):** a future `ixora.smart_home.action.total` counter (Phase 7B.4.6) will, by construction, count every attempt independently — a job retried twice that eventually succeeds contributes one `failure`-or-similar-labeled increment per failed attempt plus one `success`-labeled increment for the final attempt, never a single "eventually succeeded after N tries" data point. This mirrors how `ixora.queue.job.total` already behaves (`metrics-philosophy.md` §11) and requires no new design.

---

## 10. Logging ownership (§1.9)

Classification only — **no log statement is added, changed, or removed by this phase.** The table below classifies every taxonomy row against the brief's four buckets (Trace only / Log only / Trace + Log / No telemetry) and cross-checks each decision against what `SmartHomeActionJob` already does today (§2, `domain-execution-review.md` §11).

| Row(s) | Trace? | Log? | Classification | Already matches existing code? |
| --- | --- | --- | --- | --- |
| D1 (dispatch success, incl. `skipped_actions>0`) | Yes (`smart_home.dispatch`, counts) | No | **Trace only** | Yes — no log exists for a normal dispatch today, consistent with `logs-philosophy.md` §4 ("routine success → metric/trace, not log") |
| D2 (dispatch throws) | Yes (`ERROR`) | Yes (`Log::warning`, in `dispatchSmartHomeAfterSchedule()`'s own catch, scheduled path only — the manual path's controller has no equivalent catch and lets the exception surface as an HTTP 500, per `domain-execution-review.md` §7) | **Trace + Log** (scheduled path); **Trace only, HTTP 5xx implied** (manual path) | Yes — pre-existing, asymmetric-but-correct per §4's own manual/scheduled asymmetry finding |
| J1–J3 (guard-clause skip) | No — no span exists (§3.3) | Yes (`Log::warning`, already present) | **Log only** | Yes — exactly matches `logs-philosophy.md` §12's "Domain rule rejected processing → ✅ warning" row |
| A1 (action success) | Yes (`OK`, `outcome=success`) | No (`logResult()` only logs `Log::info` on success — see note below) | **Trace only, in principle** | **Partial mismatch, not fixed by this phase (§13):** `SmartHomeActionJob::logResult()` currently logs `Log::info` on every success too — `logs-philosophy.md` §5's own rule ("Never `info` on hot paths... job success → metric only") argues this should eventually be removed. This is a **pre-existing logging-volume question**, not a Business Failure Semantics question — flagged here as input to Phase 7B.4.7, not resolved by this phase (forbidden: "create new logs" cuts both ways — removing one is also a logging change, out of scope) |
| A2 (action failure — `ActionResult(success:false)`) | Yes (`OK`, `outcome=failure`) | Yes (`Log::warning`, already present) | **Trace + Log** | Yes |
| A3 (unsupported) | Yes (`OK` as of §6.4, `outcome=unsupported`) | Yes (`Log::warning`, already present) | **Trace + Log** | Yes — and now internally consistent (previously Trace(`ERROR`) + Log, an odd pairing of "logged as a mere warning" next to "traced as an error") |
| A4/A5 (failure/unknown, unexpected) | Yes (`ERROR`, `outcome=failure`) | Yes (`Log::error`, already present — the job's generic catch-all) | **Trace + Log** | Yes |
| P1 (provider success) | Yes (`OK`, no dedicated outcome attribute — §7) | No | **Trace only** | Yes — no per-provider-call log exists, consistent with `logs-philosophy.md` §12's "HA action succeeded → ❌ No log" |
| P2/P3 (provider failure) | Yes (`OK`, per §6.3 — the failure is visible one span deeper) | Covered by A2's `Log::warning` one layer up (no separate provider-level log exists) | **Trace only at this boundary; Trace + Log at the Action boundary** | Yes — no duplicate log exists at the Provider layer, consistent with "one log at the boundary that owns the outcome" (`logs-philosophy.md` §13) |
| P4 (unexpected provider-layer throw) | Yes (`ERROR`) | Covered by A5's `Log::error` one layer up | **Trace only at this boundary; Trace + Log at the Action boundary** | Yes |
| Q1–Q4 (Queue-level) | Owned by Phase 7B.2 | Owned by Phase 7B.2 | *(not this phase's boundary)* | N/A |

**No change recommended to any existing log statement in this phase** — every mismatch found (the A1/`Log::info` volume question) is a pre-existing logging *volume* concern for Phase 7B.4.7 to weigh, not a Business Failure Semantics *classification* error; the classification itself (which failures deserve investigation-grade text) already matches this document's own conclusions everywhere else.

---

## 11. Metrics ownership (§1.10)

Classification only — **no metric is created, and none of this section is implemented; this phase forbids it explicitly (§5 of the brief).** This is guidance for Phase 7B.4.6.

| Row(s) | Deserves a metric? | Reasoning |
| --- | --- | --- |
| A1/A2/A3 (`smart_home.action`'s own three outcomes) | **Yes** | This is exactly the reserved example `traces-philosophy.md` §11 and `metrics-philosophy.md` §11 already anticipate: `ixora.smart_home.action.total{outcome=success\|failure\|unsupported,provider=home_assistant\|...}` — a Counter, bounded labels, answers "what is the Smart Home failure rate by provider" without per-device cardinality. `ixora.smart_home.action.duration` (Histogram, same labels) is the natural latency companion, per `metrics-philosophy.md` §11's own reserved row |
| A4/A5 (unexpected failure) | **Yes — folded into the same counter's `failure` label value**, not a separate metric | Per §7, these already share the `failure` outcome value; a separate metric would fragment one operational question ("is the Smart Home pipeline healthy") into two dashboards for no benefit |
| J1–J3 (guard-clause skip) | **Worth considering, not decided here** | These never reach a span (§3.3), so they cannot piggyback on the trace-derived metric the way A1–A5 can. A dedicated Counter (e.g. `ixora.smart_home.action.total{outcome=skipped}`, sourced from the job's own code, not a span) is a reasonable Phase 7B.4.6 candidate given `domain-execution-review.md` U-4/U-5's finding that this is currently invisible in aggregate — but deciding the exact label/metric name is explicitly deferred, not resolved, here |
| P1/P2/P3/P4 (`smart_home.provider`'s own outcomes) | **No — already covered by A1–A5's counter one layer up, and duplication was already explicitly rejected once (Phase 7B.4.4, §6.5).** A separate per-provider-call metric would double-count the same event the Action-level counter already counts, since today's single-provider-per-attempt pipeline makes the two 1:1 | Confirmed by re-reading Phase 7B.4.4's own review; this phase found no new reason to revisit that conclusion |
| D1 (dispatch enqueue outcome) | **Optional, lower priority** | `ixora.smart_home.dispatch.total{outcome=...}` (dispatched/skipped counts) would answer "how many actions do we lose to skip conditions at enqueue time" — a real, distinct operational question from the Action-level failure rate (§8.4 — dispatch never knows execution outcomes), but not urgent given the low volume this pipeline runs at today |
| D2 (dispatch throw) | **Yes, folded into the dispatch counter above as an `outcome=error`-style label**, mirroring the Scheduler's own precedent (`ixora.scheduler.execution.total{outcome=failed}`) | Consistent with the existing Scheduler/Queue metric pattern already established in Phases 7B.2–7B.3 |
| Q1–Q4 (Queue-level) | Already exists (`ixora.queue.job.total{outcome=*}`, Phase 7B.2) | Not this phase's or Phase 7B.4.6's concern — but §8.3's finding must be documented wherever this metric is surfaced on a dashboard, so nobody mistakes `ixora.queue.job.total{outcome=success}` for a Smart-Home-success signal |

**Cardinality check (forward-looking only):** `provider` is already bounded (`home_assistant`, `future` — `SmartHomeActionProvider`); `outcome` is bounded (§7's table). Neither introduces a cardinality risk under `metrics-philosophy.md` §6's rules. This observation is provided as a head start for Phase 7B.4.6's own required review checklist — it does not substitute for that phase performing its own.

---

## 12. Implementation gate (§2 of the brief)

The Architecture Review (§2–§9) concluded that **the existing telemetry already models failure correctly in every respect except one** (§6.4/§4 — `smart_home.action`'s span status for the `unsupported` classification). Per the brief's own Implementation Gate: *"If code changes are necessary, justify every one."*

**One code change was made, and is justified as follows:**

| Change | File | Justification |
| --- | --- | --- |
| `SmartHomeActionTelemetry::wrap()`'s exception-handling branch now calls `Span::setError()` conditionally — skipped only when the classified outcome is `SmartHomeActionOutcome::Unsupported` | `app/Telemetry/SmartHome/SmartHomeActionTelemetry.php` | Directly required by §4/§6 of this review, which found the *existing* code's own two facts (the classification `unsupported` and the unconditional `setError()` call) in direct contradiction with the platform's own documented span-status rule (`traces-philosophy.md` §8). This is exactly the brief's own allowed category: **"improve span status assignment."** It is the single narrowest change that resolves the contradiction — it touches no other outcome, no other span, no attribute, no business/queue/provider/HTTP behavior, and no test's assertion about *business* behavior (only telemetry-internal `spanErrorCalls` assertions, which exist specifically to verify telemetry behavior, needed updating) |

**No other code change was made.** Every other class reviewed (`SmartHomeProviderTelemetry`, `SmartHomeDispatchTelemetry`, `SmartHomeActionJob`, `HomeAssistantAdapter`, `ProviderAdapterResolver`, `ActionResult`, both exception classes, `QueueExecutionTelemetry`) was found, on inspection, to already conform to §4–§9's own policy (§6.5, §6.6, §7 explain why for each). Per the brief's own instruction — *"If the Architecture Review concludes that the current telemetry already models failures correctly: Do NOT force additional instrumentation"* — no enrichment, no new outcome value, no new attribute, and no metric/log was added anywhere else, even where §11/§13 identify a plausible future candidate (e.g. a `skipped` outcome, an A2-splitting attribute) — those are documented as **recommendations for later phases** (§15), not implemented now, per the brief's explicit forbidding of "create new metrics/logs" and "redesign existing boundaries" in this phase.

---

## 13. Security review (§7 of the brief)

| Forbidden item | Present in this phase's one code change or its tests? |
| --- | --- |
| Credentials, tokens, headers | No — the change touches only a boolean branch on an already-existing, already-reviewed `SmartHomeActionOutcome` enum value; it introduces no new attribute, no new data source |
| Payloads, request/response bodies | No — unchanged |
| Entity IDs, provider device IDs | No — unchanged |
| URLs with credentials | No — unchanged; this phase's diff is entirely inside `App\Telemetry\SmartHome`, which never imports `Illuminate\Http\Client`/`GuzzleHttp` (unchanged dependency-rule enforcement, §2, `SmartHomeActionTelemetryDependencyRuleTest`) |

**One item specifically re-examined per this review's own findings (§2, `UnsupportedSmartHomeActionException`):** `recordException()` still runs for the `unsupported` case (§6.4), attaching the exception's class and message to the span. `UnsupportedSmartHomeActionException::forAction($action)`'s message embeds the raw `action_type` string (`"Unsupported smart home action [{$action}]."`). Traced this value to its source: `StoreVibeDeviceActionRequest`/`UpdateVibeDeviceActionRequest` validate `action_type` against `Rule::in(ActionType::mvpAllowed())` at creation time (`App\SmartHome\ActionType`, currently exactly `turn_on`/`turn_off`/`toggle` — all three of which **are** mapped in `HomeAssistantAdapter::ACTION_SERVICE_MAP`, meaning `UnsupportedSmartHomeActionException` is **not reachable today via any validated API path** — only via a pre-existing row whose `action_type` predates a schema/enum change, direct DB manipulation, or a test fixture, per `database/migrations/2026_05_01_000006_create_vibe_device_actions_table.php`'s plain `$table->string('action_type')` column with no DB-level enum constraint). This value contains no credential, no PII, and no unbounded user text — it is, at most, a short identifier string constrained by the same `ActionType` enum the validated path enforces. **No change to the exception class or its message is made** (forbidden — §5 of the brief, "change business logic"); this finding is recorded as an accepted, low-severity limitation (§14) rather than acted on.

Every attribute this pipeline's three Business spans emit was already verified safe by Phases 7B.4.2–7B.4.4's own security reviews (`ixora.dispatch.*`, `ixora.action.*`, `ixora.provider.device_domain` — no IDs, no credentials, no payloads); this phase adds zero new attributes, so those reviews are re-affirmed, not superseded.

---

## 14. Accepted limitations

| # | Limitation | Why it is accepted, not fixed, in this phase |
| --- | --- | --- |
| L-1 | `ActionResult(success: false)` conflates a provider-side rejection (P2) with an internally-caught transport failure (P3) — a future Business Metric built from `ixora.action.outcome=failure` alone cannot distinguish them (§5) | Resolving it would require changing `ActionResult`'s shape — explicitly forbidden this phase (§5 of the brief). The detail is not lost, only one span-hop deeper (the Provider/HTTP-client spans) |
| L-2 | `SmartHomeActionJob::logResult()` logs `Log::info` on every successful action — a hot-path log the platform's own `logs-philosophy.md` §5 discourages | Pre-existing, unrelated to Business Failure *Semantics* (it is a volume question, not a classification error) — flagged for Phase 7B.4.7, not touched here (removing a log is itself a logging change, out of scope §5 of the brief) |
| L-3 | `UnsupportedSmartHomeActionException`'s message embeds the raw `action_type` string, and the `action_type` column has no DB-level enum constraint (only application-level validation at creation time) | Currently unreachable via any validated path (§13) and bounded to a short, non-sensitive string even in the unreachable case; changing the exception class or adding a DB constraint is a domain-layer change, out of scope for a telemetry phase |
| L-4 | No cross-attempt correlation exists — a retried action's N attempts appear as N independent `smart_home.action` spans with no shared identifier beyond `trace_id`/`span_id` propagation limits already documented in `domain-execution-review.md` U-1/U-2 (§9) | Introducing a correlation ID is explicitly forbidden this phase (§5 of the brief); the underlying gap was already known before this phase and is unchanged by it |
| L-5 | J1–J3 (guard-clause skips) remain invisible to any span or metric — Log only (§10) — meaning "how often do we lose actions to stale references" cannot be dashboarded without a new Log-derived signal or a new Counter | Documented as a Phase 7B.4.6 candidate (§11), not implemented — adding either is a new metric, forbidden this phase |
| L-6 | §8.3's Queue/Business orthogonality is a **conceptual** trap, not a code defect — nothing in this phase (or any prior phase) mislabels anything; the risk is purely in how a future dashboard-builder or on-call engineer might misread two correctly-independent signals as one | Cannot be "fixed" by code — mitigated by this document itself being the recommended reading before any Phase 7B.4.6 dashboard is built (§15) |

---

## 15. Tests

No business, retry, queue, or provider behavior changed (§12) — the only functional change is a span-status branch inside one Telemetry class. Per the brief's own testing requirement ("if code changes occur"), the following were added/updated, all passing:

| Test file | Change |
| --- | --- |
| `tests/Feature/Telemetry/SmartHome/SmartHomeActionTelemetryTest.php` | Added: *"wrap() records the exception but does NOT mark the span as errored when the classifier reports an unsupported outcome"* — proves `recordException()` still fires, `spanErrorCalls` stays `0`, the span still ends exactly once, and `ixora.action.outcome` is still `unsupported`. Added: *"wrap() still marks the span as errored when the classifier reports failure or the fail-open unknown outcome"* — proves the fix is scoped to `Unsupported` only; `failure` and a throwing classifier (which degrades to `unknown`) both still set `spanErrorCalls` to `1` |
| `tests/Feature/Telemetry/SmartHome/SmartHomeActionBoundaryIntegrationTest.php` | Updated *"an unsupported action type..."* to assert `spanErrorCalls` is now `0` (previously asserted `1`) through the real `SmartHomeActionJob::handle()` → `HomeAssistantAdapter::executeAction()` path, with a real `UnsupportedSmartHomeActionException` (not a stand-in), proving the fix holds end-to-end, not just at the unit level. Added a `spanErrorCalls->toBe(1)` assertion to the pre-existing *"an unexpected resolver error..."* test, proving A4 is unaffected by the fix |
| `tests/Unit/Telemetry/SmartHome/SmartHomeActionTelemetryDependencyRuleTest.php` | No change needed — the fix references only `SmartHomeActionOutcome` (same namespace, already an allowed implicit dependency per Phase 7B.4.3's own precedent) and the existing `Span`/`Tracer` contracts; the dependency-rule scan still passes unmodified |

No dependency-rule test needed a new entry (no new import was introduced) and no new test file was created — every assertion needed to prove this phase's one change fits naturally into the existing three files above, exactly mirroring how Phase 7B.4.4 updated pre-existing tests rather than writing a parallel suite for a one-line-scoped change.

**Full verification run for this phase:**

| Command | Result |
| --- | --- |
| `php artisan test --filter=SmartHomeAction` | 65/65 passed |
| `php artisan test --filter=Telemetry` | 252/252 passed |
| `php artisan test` (full suite) | 962/962 passed (960 pre-existing + 2 new) |
| `vendor/bin/pint --test` | Clean |

---

## 16. Recommendations for Phase 7B.4.6 (Business Metrics)

1. **Read §11 before designing any metric.** It is the authoritative ownership table — implement `ixora.smart_home.action.total{outcome=success\|failure\|unsupported,provider=...}` and its Histogram companion first; they answer the highest-value operational question with the least design ambiguity, exactly mirroring the reserved example already sitting in `traces-philosophy.md` §11 and `metrics-philosophy.md` §11.
2. **Do not attempt to split `failure` into a provider-rejection/transport-failure pair at the metric layer** (§5, L-1) — that distinction lives one span deeper by design; a metric cannot recover it without either changing `ActionResult` (a different phase's decision to make, if ever) or adding a second, more granular Provider-level metric that Phase 7B.4.4 already explicitly rejected once (§6.5).
3. **Explicitly document §8.3's Queue/Business orthogonality on whatever dashboard first plots both `ixora.queue.job.total` and the new `ixora.smart_home.action.total` side by side** — this is the single highest-risk misreading this review identified, and it costs nothing to prevent with one caption.
4. **Decide the J1–J3 skip-visibility question (§11, L-5) as its own explicit design step**, not an afterthought — it is a real, previously-undocumented gap (`domain-execution-review.md` U-4/U-5) that this phase surfaced but does not have the mandate to close.
5. **Reuse the bounded `SmartHomeActionProvider`/`SmartHomeActionOutcome` enums directly as metric label sources** — both are already `metrics-philosophy.md` §6-compliant (low-cardinality, stable) and already exist; no new enum is needed for the metric label set this document's §11 recommends.

## 17. Recommendations for Phase 7B.4.7 (Business Logging)

1. **Resolve L-2 (`Log::info` on every successful action) as an explicit decision**, not a silent carry-over — `logs-philosophy.md` §5's own rule argues for removing it; if kept, document why the general "no info on hot paths" rule does not apply here (e.g. a low-enough Smart Home action volume that the platform accepts the log cost).
2. **§10's table is a ready-made checklist** for confirming no new log duplicates a fact this document already classifies as Trace-only or Trace+Log — use it directly rather than re-deriving log ownership per outcome from scratch.
3. **Do not add a log for A1 (action success) or P1/P2/P3 (provider outcomes)** — §10 already confirms these are correctly Trace-only (or covered one layer up) today; adding one would contradict this document's own findings without a new architectural reason to revisit them.

---

## 18. Cross-references

| Document | Relationship |
| --- | --- |
| [domain-execution-review.md](domain-execution-review.md) | Phase 7B.4.1 — the authoritative pipeline map and pre-existing failure-model table (§7) this document classifies against, not re-derives |
| [backend-smart-home-dispatch-boundary.md](backend-smart-home-dispatch-boundary.md) | Phase 7B.4.2 — `smart_home.dispatch`'s own design; §6.6/§8.4 of this document re-confirm it needed no change |
| [backend-smart-home-action-execution.md](backend-smart-home-action-execution.md) | Phase 7B.4.3 — `smart_home.action`'s own design and boundary-discovery rationale; §6.4 of this document is the one place this phase changes its behavior |
| [backend-smart-home-provider-boundary.md](backend-smart-home-provider-boundary.md) | Phase 7B.4.4 — `smart_home.provider`'s own design; §6.5/§7/§11 of this document re-confirm several of its attribute-ownership decisions rather than reopening them |
| [traces-philosophy.md](../../../architecture/traces-philosophy.md) | §8's exception/status table is the platform-level rule this document formalizes for Smart Home specifically (§6) |
| [logs-philosophy.md](../../../architecture/logs-philosophy.md) | §12's existing Smart Home log-classification rows are the precedent §10 extends to the full taxonomy |
| [metrics-philosophy.md](../../../architecture/metrics-philosophy.md) | §11's reserved Smart Home metric example is the target §11 of this document points Phase 7B.4.6 toward |
| [telemetry-decision-guide.md](../../../architecture/telemetry-decision-guide.md) | §6–§8's signal-choice rule is applied mechanically throughout §10/§11 |
| [telemetry-availability-policy.md](../../../architecture/telemetry-availability-policy.md) | Fail-open policy this document's one code change continues to honor (unchanged `safely()` wrapping, §12) |

---

*This document is the Business Failure Semantics reference for `back_vibes`'s Smart Home Action Execution pipeline. Phase 7B.4.6 (Business Metrics) and Phase 7B.4.7 (Business Logging) must treat §7 (outcome ownership), §10 (logging ownership), and §11 (metrics ownership) as their respective starting briefs, exactly as Phase 7B.4.2 treated `domain-execution-review.md`'s own §14/§15.*

