# Backend Smart Home Business Metrics — Phase 7B.4.6 (`back_vibes`)

**Status:** Complete
**Repo:** `back_vibes` (Laravel 13, PHP 8.3+)
**Feature ID:** `observability-foundation/mvp`
**Type:** Metrics Design Review + implementation of the metrics it justified. No logs, no dashboards, no alerts, no behavior change.
**Prerequisite:** [backend-business-failure-semantics.md](backend-business-failure-semantics.md) (Phase 7B.4.5 — authoritative failure taxonomy and metrics-ownership groundwork, §11) · [backend-smart-home-dispatch-boundary.md](backend-smart-home-dispatch-boundary.md) (Phase 7B.4.2) · [backend-smart-home-action-execution.md](backend-smart-home-action-execution.md) (Phase 7B.4.3) · [backend-smart-home-provider-boundary.md](backend-smart-home-provider-boundary.md) (Phase 7B.4.4) · [metrics-philosophy.md](../../../architecture/metrics-philosophy.md) · [traces-philosophy.md](../../../architecture/traces-philosophy.md) · [logs-philosophy.md](../../../architecture/logs-philosophy.md) · [telemetry-naming-convention.md](../../../architecture/telemetry-naming-convention.md) · [telemetry-decision-guide.md](../../../architecture/telemetry-decision-guide.md)

---

## 1. Purpose

Phases 7B.4.2–7B.4.4 instrumented three Business spans (`smart_home.dispatch`, `smart_home.action`, `smart_home.provider`) with zero metrics, by design — metrics were explicitly deferred until Phase 7B.4.5 produced a formal failure taxonomy to build on. Phase 7B.4.5 delivered that taxonomy and, in its own §11 ("Metrics ownership"), already pre-classified every failure-taxonomy row's metric-worthiness — this phase's job is to turn that classification into a **Metrics Design Review** (this document) and then implement only what the review — not Phase 7B.4.5's preview, taken on faith — actually justifies.

| In scope | Out of scope (later phases) |
| --- | --- |
| Metrics Design Review for every candidate metric named in the brief, producing a Design Record each | Business Logging (Phase 7B.4.7) |
| Implementing the metrics the review decides "Implement" | Dashboards, alerts (Phase 9) |
| Cardinality, failure-alignment, duplication, dashboard-preview, and security review per metric | Modifying business/retry/queue/provider behavior, `ActionResult`, span ownership, or trace hierarchy |
| Unit/integration/dependency-rule tests for every implemented metric | The J1–J3 guard-clause-skip metric candidate (§2.9, Candidate 4 — Deferred) |

---

## 2. Mandatory Architecture Review

Every document and class named in the brief was re-read in full before any metric was designed.

### 2.1 Documents read

| Source | What it contributed to this review |
| --- | --- |
| [`backend-business-failure-semantics.md`](backend-business-failure-semantics.md) | The authoritative failure taxonomy (§3), Business/Infrastructure/Platform classification, Span Status policy (§6), outcome-vocabulary completeness finding (§7 — no new `ixora.action.outcome` value needed), the Queue/Business orthogonality warning (§8.3) this document's dashboard previews must respect, and — most directly — §11's own metrics-ownership pre-classification, which this phase's Design Records independently re-derive rather than copy verbatim (§2.9 below explains where this review's own conclusion differs from §11's preview, and why) |
| [`backend-smart-home-dispatch-boundary.md`](backend-smart-home-dispatch-boundary.md) | `smart_home.dispatch`'s exact boundary (before `VibeSmartHomeDispatchService::dispatch()` to after it returns/throws), its two call sites (HTTP controller, scheduled console command), and its existing `ixora.dispatch.entry_point`/`.dispatched_actions`/`.skipped_actions` attributes — the span attributes a Dispatch metric must stay consistent with |
| [`backend-smart-home-action-execution.md`](backend-smart-home-action-execution.md) | `smart_home.action`'s exact boundary, its `ixora.action.provider`/`.outcome`/`.retry` attributes, and the confirmed 1:1 relationship between one `wrap()` call and one provider-execution attempt (no internal loop, no internal retry) |
| [`backend-smart-home-provider-boundary.md`](backend-smart-home-provider-boundary.md) | `smart_home.provider`'s exact boundary, its `ixora.provider.device_domain` attribute, its own §6.5 finding that `ixora.action.provider` is owned by the Action boundary (not duplicated here), and its explicit prior rejection of a Provider-level metric on cardinality/duplication grounds — re-examined, not assumed, in §2.7/§3.3 below |
| [`metrics-philosophy.md`](../../../architecture/metrics-philosophy.md) | §5 instrument-type decision rules, §6 label allow/forbid lists, §9 review checklist (applied literally to every Design Record below), and §11's own reserved `ixora.smart_home.action.total`/`.duration` example — confirming those two names are already a platform-level contract, not a new invention |
| [`traces-philosophy.md`](../../../architecture/traces-philosophy.md) | §8's span-status rule, already formalized for Smart Home by Phase 7B.4.5 §6 — a metric's `outcome` label must never contradict a span's own status, checked per candidate in §3 below |
| [`logs-philosophy.md`](../../../architecture/logs-philosophy.md) | §12's Smart Home log-classification rows, confirming this phase adds no log and duplicates none |
| [`telemetry-naming-convention.md`](../../../architecture/telemetry-naming-convention.md) | §5 metric-naming format and the `ixora.<domain>.<entity>.<measure>` shape; confirms `ixora.smart_home.action.total`/`.duration` are already listed as **official examples** (§5, §14) — this phase implements a pre-reserved name, not a new one |
| [`telemetry-decision-guide.md`](../../../architecture/telemetry-decision-guide.md) | §6–§8's signal-choice decision tree, applied to every candidate in §2.1 below (Business Meaning) to confirm "metric" is the right signal before designing one |

### 2.2 Code reviewed

| Class | Finding relevant to this phase |
| --- | --- |
| `App\Telemetry\SmartHome\SmartHomeDispatchTelemetry` | Before this phase: zero metric contract imports (`SmartHomeDispatchTelemetryDependencyRuleTest` enforced this). `wrap()`'s existing shape — one span per call, but a *batch* result (`[dispatchedActions, skippedActions]`) plus a rethrow-on-exception path — determines the Dispatch metric's own shape (§3.1) |
| `App\Telemetry\SmartHome\SmartHomeActionTelemetry` | Before this phase: zero metric contract imports. `wrap()`'s existing shape — one span per call, one classified `SmartHomeActionOutcome` per call (never a batch) — is structurally simpler than Dispatch's and maps 1:1 onto a single counter increment (§3.2) |
| `App\Telemetry\SmartHome\SmartHomeProviderTelemetry` | Confirmed (again, independently of Phase 7B.4.4's own prior conclusion) that exactly one `SmartHomeProviderTelemetry::wrap()` call happens per `SmartHomeActionTelemetry::wrap()` call in every reachable code path today (`HomeAssistantAdapter::executeAction()` — the only concrete `ProviderAdapter` — calls the provider-wrap exactly once, with no internal loop) — the load-bearing fact behind rejecting Candidate 3 (§2.9, §3.3) |
| `App\Telemetry\Queue\QueueExecutionTelemetry` | Reviewed as the platform's own precedent for "a Telemetry class that owns both a span-adjacent Counter and a Histogram, sharing one label set, recorded inside the same `safely()` fail-open guard used for span operations." This phase's `SmartHomeActionTelemetry`/`SmartHomeDispatchTelemetry` changes mirror this class's constructor-injection pattern (`Meter $meter, string $environment, string $serviceName`) exactly — no new wiring pattern was invented |
| `App\Telemetry\Contracts\{Meter,Counter,Histogram,UpDownCounter}` | Confirmed the exact method signatures (`Meter::counter()`/`histogram()`/`upDownCounter()` each return a bound instrument; `Counter::add()`, `Histogram::record()` take `(int|float, array $attributes = [])`) and that no OpenTelemetry SDK type ever needs to be imported outside `App\Telemetry\OpenTelemetry` |
| `TelemetryServiceProvider` | Confirmed the existing wiring pattern for every other Meter-consuming class (`HttpRequestTelemetry`, `QueueExecutionTelemetry`, `ConsoleCommandTelemetry`, `SchedulerExecutionTelemetry`) — `environment`/`serviceName` read from `config('telemetry.*')`, `Meter` resolved from the container — and applied that exact pattern to the two singleton definitions this phase touches |
| OpenTelemetry metric conventions | Confirmed `Meter::counter()`/`histogram()` map 1:1 onto `MeterInterface::createCounter()`/`createHistogram()` in `open-telemetry/sdk`, and that `unit` strings follow UCUM (`{action}`, `{job}`, `ms`) already used by every other Ixora metric (`ixora.queue.job.total` uses `{job}`; this phase's two Counters use `{action}` for the same reason — one increment represents one countable unit of Smart Home domain work, never a byte or a ratio) |

**No source contradicted an assumption in the brief.** The one place this review's own conclusion (§2.9, §3.3) differs from Phase 7B.4.5 §11's *preview* is treated as expected, not a defect — §11 explicitly says its own metrics-ownership table is "not decided [t]here" and is input to, not a substitute for, this phase's own Design Review.

---

## 3. Metrics Design Review

Four candidates were evaluated: the three named in the brief (Dispatch, Action, Provider) plus one the brief explicitly flags as "possible candidates only, do not assume all should exist" — the J1–J3 guard-clause-skip candidate Phase 7B.4.5 §11 surfaced as "worth considering, not decided there." Each gets a full Design Record.

### 3.1 Design Record — `ixora.smart_home.dispatch.total`

| Field | Value |
| --- | --- |
| **Metric name** | `ixora.smart_home.dispatch.total` |
| **Metric type** | Counter |
| **Business question** | "How many Smart Home actions are we dispatching vs. losing to a skip condition vs. losing to a dispatch-level failure, per entry point?" — **Operational throughput**, with one **Business outcome** sub-question (skip rate) folded in |
| **Boundary owner** | Dispatch (`smart_home.dispatch`, `SmartHomeDispatchTelemetry::wrap()`) — narrowest owner; this is the only class that ever observes a `VibeSmartHomeDispatchService::dispatch()` call, and its own span already carries the exact two counts (`ixora.dispatch.dispatched_actions`/`.skipped_actions`) this metric aggregates |
| **Counting unit** | Not one dispatch — **one dispatched action, one skipped action, or (only on the rare throw path) one dispatch-level failure.** A single `wrap()` call increments the counter by the batch's own `dispatchedActions` count under `outcome=dispatched`, by its own `skippedActions` count under `outcome=skipped` (both always recorded, even when zero — a batch that skips 0 actions still produces a real, countable "zero this time" data point, exactly like `metrics-philosophy.md` §5's "one metric, many outcomes" guidance), and by exactly `1` under `outcome=error` only when `dispatch()` itself throws (D2) — never by an action count on that path, because the batch itself never completed and no per-action counts exist. Retries are not a Dispatch-level concept — `VibeSmartHomeDispatchService::dispatch()` has no retry of its own (confirmed §2.2); each `SmartHomeActionJob` retry is counted independently, one layer down, by the Action metric (§3.2) |
| **Label set** | `environment`, `service_name` (platform-mandatory, every Ixora metric), `entry_point` (`manual`/`scheduled`/`future` — `SmartHomeDispatchEntryPoint`, already bounded and already a span attribute), `outcome` (`dispatched`/`skipped`/`error`) |
| **Cardinality analysis** | `environment` (3) × `service_name` (2, though only `back_vibes-api`/`back_vibes-worker` are realistic for this call site — the HTTP controller and the scheduled console command both run in the `api`/`worker` processes, never a third service) × `entry_point` (3) × `outcome` (3) = **54 series maximum**, far inside the < 10 000/service budget (`metrics-philosophy.md` §9). No label is unbounded, growing, or sensitive — every value is drawn from a closed, already-reviewed enum (`SmartHomeDispatchEntryPoint`, `metrics-philosophy.md`/`telemetry-naming-convention.md` §6/§8 bounded-label allowlists) |
| **Failure-semantics alignment** | Per Phase 7B.4.5 §3.1: D1 (normal return, any skip count) is **Business** and keeps the span `OK` — mapped here to `outcome=dispatched`/`outcome=skipped`, both success-rate-adjacent (neither is a failure; `skipped` is a distinct, expected outcome, never merged into `dispatched` or counted against a "failure rate"). D2 (throw) is **Infrastructure** and marks the span `ERROR` (§6.3) — mapped here to `outcome=error`, the only value that should ever be read as a failure-rate numerator for this metric. No outcome is silently merged into another; the metric's three values are a strict, order-preserving projection of the span's own two attributes plus its own status, never a second, independently-derived classification |
| **Duplication analysis** | Not a duplicate of `ixora.queue.job.total` (Queue owns job-attempt outcomes, entirely orthogonal per Phase 7B.4.5 §8.3 — a dispatch is enqueuing, not executing), `ixora.console.command.total`/`ixora.http.server.*` (those own the HTTP/console *request* outcome, not the domain batch outcome nested inside it), `ixora.scheduler.event.*` (owns the Scheduler tick, not the Smart Home dispatch call the tick happens to trigger), or `smart_home.action`/`smart_home.provider` (those are one layer down and per-action, never per-batch) |
| **Dashboard preview** | "Dispatch Throughput" — dispatched-vs-skipped rate by `entry_point`, answering "are we losing an unusual fraction of actions to skip conditions on the scheduled path vs. the manual path?" "Dispatch Failure Rate" — `outcome=error` rate, expected to be ~0 in steady state per Phase 7B.4.5 §3.1's own finding that `dispatch()` has no business-exception branch |
| **Decision** | **Implement** |

### 3.2 Design Record — `ixora.smart_home.action.total` + `ixora.smart_home.action.duration`

| Field | Value |
| --- | --- |
| **Metric name** | `ixora.smart_home.action.total` (Counter) and `ixora.smart_home.action.duration` (Histogram) — evaluated together because both share one label set and one classification, recorded from the same call site (§6, `metrics-philosophy.md` §11's own reserved pairing) |
| **Metric type** | Counter (`.total`) + Histogram (`.duration`) — a Gauge/UpDownCounter was considered and rejected: nothing about one action attempt is a "current value that rises and falls" (`metrics-philosophy.md` §5); it is a discrete, terminal event, exactly the Counter/Histogram use case |
| **Business question** | "What is the Smart Home action failure rate, and how long do action attempts take, broken down by outcome and provider?" — **Business outcome** (failure rate) + **Operational throughput/latency** (duration) |
| **Boundary owner** | Action (`smart_home.action`, `SmartHomeActionTelemetry::wrap()`) — narrowest owner. Not Provider: §2.2/§3.3 below confirm today's pipeline makes "one provider call" and "one action attempt" the exact same event, but *Action* is still the correct owner because it is the boundary that already performs the full `SmartHomeActionOutcome` classification (`success`/`failure`/`unsupported`/`unknown`) a Provider-level class deliberately does not attempt (Phase 7B.4.4 §6.5 — no outcome attribute exists at the Provider layer at all) |
| **Counting unit** | **One action-execution attempt that reaches this boundary** — i.e., one `wrap()` call, which itself is one provider-resolution + `executeAction()` attempt (confirmed 1:1, no internal loop, §2.2). **Retries count independently**: `ixora.action.retry` already distinguishes a retried span from a first attempt (Phase 7B.4.3), and this phase's counter increments once per attempt regardless of `$isRetryAttempt` — a job retried twice that eventually succeeds contributes two `failure`-or-similar increments plus one `success` increment, never a single "eventually succeeded" data point, exactly matching Phase 7B.4.5 §9's own forward-looking note and `ixora.queue.job.total`'s existing precedent. The J1–J3 guard-clause skips (before this boundary even exists, §3.3 of Phase 7B.4.5) are **not** counted here — see Candidate 4 (§3.4) for why that is a separate, deferred decision rather than a silent omission |
| **Label set** | `environment`, `service_name`, `outcome` (`success`/`failure`/`unsupported`/`unknown` — the exact `SmartHomeActionOutcome` vocabulary, reused verbatim, never re-derived), `provider` (`home_assistant`/`future` — `SmartHomeActionProvider`) |
| **Cardinality analysis** | `environment` (3) × `service_name` (2) × `outcome` (4) × `provider` (2, growing by exactly one value per future provider integration — a controlled, code-reviewed growth, not unbounded) = **48 series per instrument, 96 total for the pair** — well inside budget. Every label is a closed enum already reviewed and already emitted as a span attribute; none is an ID, a URL, a payload, or an exception message |
| **Failure-semantics alignment** | Direct, unmodified reuse of `SmartHomeActionOutcome` — the exact same value the span's own `ixora.action.outcome` attribute already carries (§6 below: computed once, in `classify()`, never twice). Per Phase 7B.4.5 §6.3/§7: `success` (A1/P1) is success-rate-eligible; `failure` (A2/A4/A5, including both the P2 provider-rejection and P3 transport-failure sub-causes `ActionResult` conflates — §5 of that document) is failure-rate-eligible and span-`ERROR`-aligned for A4/A5 only; `unsupported` (A3) is **never** merged into `failure` — it is its own label value, aligned with the span staying `OK` for that one classification (Phase 7B.4.5 §6.4's own fix); `unknown` is the fail-open classifier-degradation value, aligned with the span becoming `ERROR` (nothing about a classifier failure is a recognized business branch). No metric value ever asserts something the span's own status does not already assert, because both are sourced from one shared `$outcome` variable per call (§6) |
| **Duplication analysis** | Not a duplicate of `ixora.queue.job.total` (§8.3 of Phase 7B.4.5 — Queue-level success is orthogonal to, and routinely coexists with, Action-level failure, since `SmartHomeActionJob::handle()` never lets a Business/Infrastructure failure escape it) or `ixora.smart_home.provider.*` (rejected, §3.3 — would 1:1 duplicate this exact metric today). Not a duplicate of the auto-instrumented Guzzle `CLIENT` span's own metrics (OTel HTTP client auto-instrumentation in this SDK emits spans, not metrics, by default — confirmed no `http.client.*` metric exists in this codebase) |
| **Dashboard preview** | "Action Success Rate" (`success` / total, by `provider`) — the single highest-value Smart Home dashboard panel, exactly the one `metrics-philosophy.md` §11 already reserves this name for. "Unsupported Rate" (`unsupported` / total) — distinct from failure rate, answers "are users configuring actions our current provider integration cannot map" rather than "is the provider degraded." "Action Latency p95" (Histogram, by `outcome`/`provider`) — answers "is Home Assistant responding slowly" without needing per-device Gauge sampling |
| **Decision** | **Implement** |

**A deliberate scope decision, stated once:** `metrics-philosophy.md` §11 and `telemetry-naming-convention.md` §14 both show a *reserved, illustrative* label set for this metric that includes `action_type` (e.g. `outcome=failure,action_type=turn_off`). This phase's own brief (§5, "Labels" — "Action: outcome, provider") explicitly does **not** list `action_type`, and — independently confirmed by re-reading `backend-smart-home-action-execution.md` in full (§2.2 above) — `action_type` is **not** an existing `smart_home.action` span attribute today; adding it would mean introducing a brand-new value into this class for the first time, which this phase's own Architecture Review gate (§12 of the brief, "if code changes are necessary, justify every one") does not clearly justify against the risk of quietly exceeding this phase's narrow mandate. **Decision: omit `action_type` from this phase's label set**, exactly matching the brief's own explicit list, and record it as a **Recommendation for Phase 7B.4.7** (§9) rather than adding it silently now — it is a low-cardinality, already-bounded (`ActionType::mvpAllowed()` — 3 values today) label a future phase can add to an *existing* metric without a breaking rename, per `metrics-philosophy.md` §8's own lifecycle rule ("Add labels... do not rename in place").

### 3.3 Design Record — `ixora.smart_home.provider.total` (candidate)

| Field | Value |
| --- | --- |
| **Metric name** | `ixora.smart_home.provider.total` (candidate — never implemented) |
| **Metric type** | Would have been a Counter |
| **Business question** | "What is the success rate of calls to a specific Smart Home provider integration?" — nominally a distinct **Business outcome** question from the Action metric's "what is the failure rate of Smart Home actions" |
| **Boundary owner** | Would have been Provider (`smart_home.provider`, `SmartHomeProviderTelemetry::wrap()`) |
| **Counting unit** | Would have been one provider-execution attempt — but §2.2 confirms this is, in every reachable code path today, the **exact same event** as one Action-execution attempt: `HomeAssistantAdapter::executeAction()` (the only concrete `ProviderAdapter`) calls into the wrapped Provider segment exactly once per `SmartHomeActionTelemetry::wrap()` call, with no internal loop, no internal retry, and no case where one Action attempt fans out to more than one Provider call |
| **Label set** | Would have been `provider` (and, per the brief's own §5, `device_domain`) |
| **Cardinality analysis** | Not unsafe in isolation (`provider` × `device_domain` is small), but cardinality safety does not rescue a metric from failing the duplication test below |
| **Failure-semantics alignment** | `SmartHomeProviderTelemetry` deliberately records **no outcome attribute at all** (Phase 7B.4.4 §6.5, re-confirmed by Phase 7B.4.5 §6.5/§7) — there is no existing, reviewed classification this metric could reuse without inventing a brand-new one, which this phase's own Architecture Review gate does not permit doing casually for a metric §2.2/duplication analysis is about to reject anyway |
| **Duplication analysis** | **Rejected on this basis alone.** Because one Provider attempt and one Action attempt are 1:1 today (§2.2), `ixora.smart_home.provider.total{outcome=X,provider=Y}` would be, for every currently reachable row, the *exact same count* as `ixora.smart_home.action.total{outcome=X,provider=Y}` — two metric names for one fact, the precise anti-pattern `metrics-philosophy.md` §10 names explicitly ("Duplicated metrics... One counter + outcome label"). This is not a new finding — Phase 7B.4.4 §6.5 already rejected a Provider-level *attribute* on the same 1:1-duplication reasoning, and Phase 7B.4.5 §11 already previewed rejecting a Provider-level *metric* for the same reason; this review independently re-derives the same conclusion from the current code rather than taking either prior phase's word for it |
| **Dashboard preview** | Would have been "Provider Success Rate" — but this question is already fully answered by filtering the Action dashboard's existing `provider` label (§3.2) to one value; a second panel sourced from a second metric would show identical numbers under a different name |
| **Decision** | **Reject.** If a second provider adapter is ever added with its own internal retry loop or its own multi-call fan-out (neither exists today), this decision must be revisited — at that point "one Action attempt" and "one Provider call" would no longer be 1:1, and a Provider-level metric would start answering a genuinely different question. Recorded as a **Recommendation for Phase 7B.4.7** (§9) to re-open only if that architectural fact changes |

### 3.4 Design Record — guard-clause-skip metric (candidate, J1–J3)

| Field | Value |
| --- | --- |
| **Metric name** | Not named — no candidate name was proposed in the brief for this row; a plausible name would be `ixora.smart_home.action.total{outcome=skipped}` on the *existing* Action counter, or a wholly new metric |
| **Metric type** | Would have been a Counter |
| **Business question** | "How often do we lose a queued Smart Home action to a stale reference (deleted action/device/provider-connection) before it ever reaches provider execution?" — a real **Business outcome** question, per Phase 7B.4.5 §14 (L-5) and `domain-execution-review.md` U-4/U-5, both of which flag this as a currently-invisible-in-aggregate gap |
| **Boundary owner** | Would be none of the six owners this review's own brief lists (Dispatch/Action/Provider/Queue/HTTP/Scheduler) cleanly — J1–J3 are three early `return` statements *inside* `SmartHomeActionJob::handle()`, **before** `SmartHomeActionTelemetry::wrap()` is ever called (confirmed by re-reading `backend-smart-home-action-execution.md`'s own boundary-discovery finding, §2.2 above) — no span exists at this point today (Phase 7B.4.5 §3.3), so there is no existing boundary class to attach a metric to without creating one |
| **Counting unit** | Would be one guard-clause skip |
| **Label set** | Would need at least a "which guard clause" label (action-not-found / device-missing / connection-missing) to be useful — not yet designed |
| **Cardinality analysis** | Not evaluated — no label set was designed |
| **Failure-semantics alignment** | J1–J3 are classified **Business** by Phase 7B.4.5 §3.3 (an expected consequence of async execution racing a user-driven delete, not a bug) — would need its own `outcome` value, distinct from anything `ixora.smart_home.action.total` currently carries, since it occurs *before* any `SmartHomeActionOutcome` classification exists |
| **Duplication analysis** | Not a duplicate of anything existing today — this is precisely why Phase 7B.4.5 flagged it as a real, previously undocumented gap rather than an already-covered fact |
| **Dashboard preview** | Would answer "how often do stale references cost us an action" — a real, distinct panel from "Action Success Rate" |
| **Decision** | **Defer.** Implementing this requires either (a) adding a new instrumentation point inside `SmartHomeActionJob::handle()` itself — a heavier, first-time-for-this-class change this phase's own brief does not name as a candidate and did not budget an Architecture Review for (three new guard-clause instrumentation sites is materially different in scope from "add a Counter/Histogram to an existing `wrap()` call"), or (b) inventing a brand-new label/outcome value on an existing metric without the boundary-ownership clarity this review requires ("one metric must have exactly one owner" — no owner cleanly exists yet). Per the brief's own §3 instruction — "these are candidates only... reject any unnecessary metric" — this candidate is not named in the brief's own candidate list at all; it surfaces only via Phase 7B.4.5's forward-looking note. Deferring it, rather than implementing it opportunistically, keeps this phase's diff scoped to exactly the three metrics the brief itself names as candidates. Recorded as a **Recommendation for Phase 7B.4.7** (§9), ideally paired with that phase's own Business Logging work, since J1–J3 already produce a `Log::warning` today (Phase 7B.4.5 §10) that a future phase could source a label from directly |

---

## 4. Decisions summary

| Candidate | Decision | Reasoning (short) |
| --- | --- | --- |
| `ixora.smart_home.dispatch.total` | **Implement** | Answers a real, distinct throughput/skip-rate question; narrowest owner (Dispatch); safe cardinality; no duplication |
| `ixora.smart_home.action.total` + `.duration` | **Implement** | Answers the platform's own pre-reserved, highest-value Smart Home operational question (failure rate + latency); narrowest owner (Action); safe cardinality; every outcome value preserved distinctly, never merged |
| `ixora.smart_home.provider.total` | **Reject** | 1:1 duplication with the Action counter in today's single-provider-per-attempt pipeline; no outcome classification exists at this boundary to build on |
| Guard-clause-skip metric (J1–J3) | **Defer** | Real gap, but no clean boundary owner exists yet and it is not named in the brief's own candidate list; needs its own future instrumentation decision, not an opportunistic addition here |

---

## 5. Metric types

Both implemented metrics use **Counter** as the default per the brief's own §4 preference. **Histogram** is introduced exactly once (`ixora.smart_home.action.duration`) and justified by §3.2's Design Record — it is the platform's own pre-reserved latency companion for this exact metric (`metrics-philosophy.md` §11), and a Histogram is the only instrument type that can answer a "how long" question across every attempt without per-request Gauge sampling (`metrics-philosophy.md` §5). **No UpDownCounter and no Gauge are introduced anywhere in this phase** — nothing in either Design Record describes a value that needs to both rise and fall (a dispatch/action attempt is a discrete, terminal event, not a current in-flight count), so neither instrument type would be justified. Dependency-rule tests assert this explicitly (§8).

---

## 6. Implementation

### 6.1 `SmartHomeDispatchTelemetry`

`app/Telemetry/SmartHome/SmartHomeDispatchTelemetry.php` gained one `Counter` (`ixora.smart_home.dispatch.total`), registered once in the constructor via the injected `Meter`. `wrap()`'s existing three call sites (the success path's `dispatched`/`skipped` pair, and the exception path's single `error` increment) each call a new private `recordCounter(SmartHomeDispatchEntryPoint $entryPoint, string $outcome, int $amount)` helper, itself called from inside the class's own pre-existing `safely()` fail-open guard — never from a new, separate guard. No span, no existing attribute, no exception-handling branch, and no method signature changed.

```php
private function recordCounter(SmartHomeDispatchEntryPoint $entryPoint, string $outcome, int $amount): void
{
    $this->dispatchTotal->add($amount, [
        'environment' => $this->environment,
        'service_name' => $this->serviceName,
        'entry_point' => $entryPoint->value,
        'outcome' => $outcome,
    ]);
}
```

### 6.2 `SmartHomeActionTelemetry`

`app/Telemetry/SmartHome/SmartHomeActionTelemetry.php` gained one `Counter` (`ixora.smart_home.action.total`) and one `Histogram` (`ixora.smart_home.action.duration`), both registered once in the constructor. `wrap()` now records `$startedAt = hrtime(true)` immediately after starting the span, and both the exception path and the success path call a new private `recordMetrics(SmartHomeActionOutcome $outcome, SmartHomeActionProvider $provider, int $startedAt)` helper — again from inside the pre-existing `safely()` guard — using the **exact same already-classified `$outcome` variable** the span's own `ixora.action.outcome` attribute is set from, never a second, independently-computed classification:

```php
private function recordMetrics(SmartHomeActionOutcome $outcome, SmartHomeActionProvider $provider, int $startedAt): void
{
    $durationMs = (hrtime(true) - $startedAt) / 1_000_000;

    $labels = [
        'environment' => $this->environment,
        'service_name' => $this->serviceName,
        'outcome' => $outcome->value,
        'provider' => $provider->value,
    ];

    $this->actionTotal->add(1, $labels);
    $this->duration->record($durationMs, $labels);
}
```

### 6.3 `TelemetryServiceProvider`

Both singleton factory closures for `SmartHomeDispatchTelemetry::class` and `SmartHomeActionTelemetry::class` were updated to resolve `Meter::class` from the container and pass `environment`/`serviceName` from `config('telemetry.*')` — the exact same pattern every other Meter-consuming Telemetry class in this codebase already uses (`HttpRequestTelemetry`, `QueueExecutionTelemetry`, `ConsoleCommandTelemetry`, `SchedulerExecutionTelemetry`). No new wiring pattern was invented; no other singleton definition changed.

### 6.4 `SmartHomeProviderTelemetry`

**Unchanged.** No `Meter`, `Counter`, `Histogram`, or `UpDownCounter` import was added — the Design Record (§3.3) rejected a metric at this boundary.

---

## 7. Security review

| Forbidden item | Present in either implemented metric's labels? |
| --- | --- |
| IDs (`user_id`, `vibe_id`, `schedule_id`, `device_id`, `provider_device_id`, `entity_id`, `action_id`) | No — the complete label set for both metrics is `environment`, `service_name`, `entry_point`, `outcome`, `provider`; none is an identifier |
| Payloads, credentials, tokens, headers, URLs | No — neither metric's implementation touches `Illuminate\Http\Client`, `GuzzleHttp`, credentials, or request/response bodies (unchanged from Phases 7B.4.2–7B.4.4's own dependency-rule enforcement, re-verified by `SmartHomeDispatchTelemetryDependencyRuleTest`/`SmartHomeActionTelemetryDependencyRuleTest`) |
| Device identifiers | No — `provider` identifies the *integration* (`home_assistant`/`future`), never a specific device, connection, or entity |
| Exception messages | No — `outcome` is a closed enum value (`SmartHomeActionOutcome`/a fixed string set for Dispatch), never derived from `Throwable::getMessage()` |

Every attribute this phase's two metrics emit is a value already reviewed and already emitted as a span attribute by Phases 7B.4.2/7B.4.3 (`ixora.dispatch.entry_point`, `ixora.action.outcome`, `ixora.action.provider`) plus the two platform-mandatory resource labels (`environment`, `service_name`) every other Ixora metric already carries — this phase introduces zero new label *values*, only a new place two already-safe values are aggregated.

---

## 8. Tests

| Test file | Change |
| --- | --- |
| `tests/Feature/Telemetry/SmartHome/SmartHomeDispatchTelemetryTest.php` | Bound a `RecordingMeter` alongside the existing `RecordingTracer`; replaced the old "never records a counter/histogram/up-down counter" assertion (no longer true) with: `dispatched`/`skipped` recorded as two separate increments including the zero-count case, `error` recorded as exactly one increment of `1` on the exception path, the metric's label set is exactly `{environment, service_name, entry_point, outcome}`, and a broken `Counter::add()` (registration succeeds, the call itself throws) never prevents `wrap()` from returning the dispatch callable's real result — metrics recording is fail-open |
| `tests/Feature/Telemetry/SmartHome/SmartHomeActionTelemetryTest.php` | Same pattern: `outcome=success`/`failure`/`unsupported`/`unknown` each produce exactly one counter increment with the correct label, never merged into another value; exactly one Histogram observation per call, as a non-negative float, sharing the counter's labels; the label set is exactly `{environment, service_name, outcome, provider}`; two calls never double-count; a broken Counter/Histogram is fail-open |
| `tests/Unit/Telemetry/SmartHome/SmartHomeDispatchTelemetryDependencyRuleTest.php` | The old blanket "creates no metrics" assertion was narrowed to exempt exactly the two files this phase justifies (`SmartHomeActionTelemetry.php`, `SmartHomeDispatchTelemetry.php`) — every other file under `app/Telemetry/SmartHome` (including `SmartHomeProviderTelemetry.php` and every enum) is still asserted metric-free |
| `tests/Unit/Telemetry/SmartHome/SmartHomeBusinessMetricsDependencyRuleTest.php` (new) | Phase-specific restatement: `SmartHomeDispatchTelemetry` depends only on `{Tracer, Span, Meter, Counter}` (no `Histogram`, no `UpDownCounter` — not justified by this phase's own Design Record); every metric name recorded by either file exactly matches this document's own approved names (no undocumented `ixora.smart_home.*` metric); every metric label recorded is drawn from this document's own approved label set, with no forbidden fragment (`*_id`, `url`, `token`, `credential`, `payload`, `header`, `body`, `json`, `action_type`); `SmartHomeProviderTelemetry.php` and every enum remain completely metric-free, guarding the §3.3 Reject decision against silent regression |
| `tests/Unit/Telemetry/SmartHome/SmartHomeActionTelemetryDependencyRuleTest.php` | Updated the allowed-imports list to include `Meter`, `Counter`, `Histogram`; added an explicit assertion that `UpDownCounter` is still **not** imported |

**Full verification run for this phase:**

| Command | Result |
| --- | --- |
| `vendor/bin/pest --filter=SmartHome` | 358/358 passed |
| `vendor/bin/pest` (full suite) | 980/980 passed |
| `vendor/bin/pint --test` | Clean |

No business, retry, queue, provider, or trace-hierarchy behavior changed — every new assertion targets metric registration, counter/histogram recording, label correctness, and fail-open behavior exclusively.

---

## 9. Recommendations for Phase 7B.4.7 (Business Logging)

1. **Revisit `action_type` as a label on `ixora.smart_home.action.total`/`.duration`** (§3.2's deliberate scope decision) — `metrics-philosophy.md` §11 and `telemetry-naming-convention.md` §14 both already anticipate it, and `ActionType::mvpAllowed()` is a small, bounded enum. Add it as a **new label on the existing metric**, never a rename, per `metrics-philosophy.md` §8's lifecycle rule.
2. **Decide the J1–J3 guard-clause-skip visibility question** (§3.4) as its own explicit design step, ideally alongside this phase's own Business Logging work — the three guard clauses already log a `Log::warning` today, which could plausibly be tapped for a Counter without adding a new span.
3. **Re-open the Provider-level metric rejection (§3.3) only if a second provider adapter introduces its own internal retry loop or multi-call fan-out** — until then, `ixora.smart_home.action.total` already fully answers "what is the success rate by provider."
4. **Resolve `SmartHomeActionJob::logResult()`'s `Log::info` on every successful action** (Phase 7B.4.5 §14, L-2) — unrelated to this phase's metrics work, but still open.
5. **When building the first Grafana dashboard panel for either new metric, caption it against Phase 7B.4.5 §8.3's own Queue/Business orthogonality warning** — `ixora.queue.job.total{outcome=success}` and `ixora.smart_home.action.total{outcome=failure}` will routinely coexist for the same underlying job, and a dashboard that plots both without that caption risks being misread.

---

## 10. Cross-references

| Document | Relationship |
| --- | --- |
| [backend-business-failure-semantics.md](backend-business-failure-semantics.md) | Phase 7B.4.5 — the failure taxonomy and metrics-ownership preview (§11) this phase's own Design Review independently re-derives, confirms, and in one case (Provider, §3.3) reaches the same conclusion as, and in another (`action_type`, §3.2) deliberately narrows relative to |
| [backend-smart-home-dispatch-boundary.md](backend-smart-home-dispatch-boundary.md) | Phase 7B.4.2 — `smart_home.dispatch`'s own design; this phase adds a Counter to its existing `wrap()` call without touching the span |
| [backend-smart-home-action-execution.md](backend-smart-home-action-execution.md) | Phase 7B.4.3 — `smart_home.action`'s own design; this phase adds a Counter + Histogram to its existing `wrap()` call without touching the span |
| [backend-smart-home-provider-boundary.md](backend-smart-home-provider-boundary.md) | Phase 7B.4.4 — `smart_home.provider`'s own design and its own prior rejection of a Provider-level *attribute* (§6.5), which this phase's own rejection of a Provider-level *metric* (§3.3) extends |
| [metrics-philosophy.md](../../../architecture/metrics-philosophy.md) | §5/§6/§9/§11 applied directly throughout §3's Design Records |
| [telemetry-naming-convention.md](../../../architecture/telemetry-naming-convention.md) | §5/§14 — confirms both implemented metric names are pre-reserved platform contracts |

---

*This document is the Business Metrics reference for `back_vibes`'s Smart Home Action Execution pipeline. Phase 7B.4.7 (Business Logging) should treat §9 as its own starting brief, exactly as Phase 7B.4.6 treated Phase 7B.4.5's §16.*
