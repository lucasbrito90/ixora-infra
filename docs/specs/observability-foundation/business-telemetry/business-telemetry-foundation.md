# Business Telemetry Foundation — Phase 7B.4.9

**Status:** Active architecture baseline  
**Repo:** Platform-wide (`back_vibes` primary reference implementation)  
**Feature ID:** `observability-foundation/business-telemetry`  
**Type:** Documentation-only — no runtime code, telemetry, metrics, spans, logs, or tests  
**Prerequisite:** [backend-business-telemetry-validation.md](backend-business-telemetry-validation.md) (Phase 7B.4.8 — validated reference implementation) · [backend-sdk-foundation.md](../mvp/backend-sdk-foundation.md) (Phase 7A — Telemetry Abstraction Layer) · [telemetry-decision-guide.md](../../../architecture/telemetry-decision-guide.md) · [telemetry-naming-convention.md](../../../architecture/telemetry-naming-convention.md) · [metrics-philosophy.md](../../../architecture/metrics-philosophy.md) · [logs-philosophy.md](../../../architecture/logs-philosophy.md) · [traces-philosophy.md](../../../architecture/traces-philosophy.md)

> **Rule of thumb:** This document is the **single source of truth** for how every future Business Telemetry domain must be designed. The Smart Home implementation (Phases 7B.4.1–7B.4.8) is the validated reference — not a special case. Every new domain (Push Notifications, Marketplace, AI, Matter, Google Home, Alexa, additional providers) follows this foundation without redefining architecture.

---

## 1. Purpose

Business Telemetry instruments **Ixora's business pipelines** — the code paths between "a user or system triggered something" and "an external provider or downstream system received a call" — with spans, metrics, and logs that answer operational questions about **business outcomes**, not infrastructure health.

Infrastructure Telemetry (Phases 7A–7B.3) already covers HTTP requests, queue jobs, console commands, and scheduler ticks generically. Business Telemetry adds the **business-outcome dimension**: which domain, which boundary, which outcome, which provider — without re-emitting duration, HTTP status, queue name, or retry count that infrastructure signals already own.

This document answers:

> **How should every future Business Telemetry implementation be designed?**

It generalizes the architectural rules validated during Phase 7B.4.8 from the Smart Home reference implementation into platform-wide standards. No domain-specific assumptions remain — every rule is stated in domain-neutral terms.

---

## 2. Relationship to other guides

| Guide | Role relative to Business Telemetry |
| --- | --- |
| [telemetry-naming-convention.md](../../../architecture/telemetry-naming-convention.md) | **How** to name spans, metrics, labels, and log fields |
| [telemetry-decision-guide.md](../../../architecture/telemetry-decision-guide.md) | **Which signal** to emit (trace vs metric vs log) |
| [metrics-philosophy.md](../../../architecture/metrics-philosophy.md) | Metrics-first principles (cardinality, aggregation, trends) |
| [logs-philosophy.md](../../../architecture/logs-philosophy.md) | Logs-first principles (levels, structured fields, correlation) |
| [traces-philosophy.md](../../../architecture/traces-philosophy.md) | Traces-first principles (hierarchy, span scarcity, status policy) |
| [backend-sdk-foundation.md](../mvp/backend-sdk-foundation.md) | **Dependency Rule**, Contracts architecture, propagation mechanism |
| **This document** | **Business Telemetry architecture** — boundaries, ownership, lifecycle, design reviews, extension rules, anti-patterns |

Every Business Telemetry implementation phase must satisfy **all** of the above guides **and** this foundation. Deviations require an ADR amendment or explicit spec exception.

---

## 3. Platform rules

### 3.1 Business boundary ownership

A **Business Boundary** is the narrowest architectural seam where a measurable business decision or outcome occurs — not the entire method, not the entire job, not the entire service.

| Rule | Detail |
| --- | --- |
| **One boundary, one owner** | Every telemetry signal (span, metric, log) belongs to exactly one Business Boundary. No signal may be owned by two boundaries. |
| **Narrowest owner wins** | When a failure is observable at multiple layers, the boundary that owns the **outcome classification** owns the signal — not every layer that observed it. |
| **Precondition failures are not boundaries** | Guard clauses, authorization failures, and validation skips that occur *before* real business work begins do not create Business Spans. They may produce domain logs at the call site. |
| **Infrastructure owns infrastructure** | HTTP duration, queue job disposition, console command outcome, and scheduler tick outcome are owned by Infrastructure Telemetry — never re-emitted as Business signals. |
| **Discover, don't assume** | The natural Business Boundary must be discovered by reading the actual code before writing any span. The brief's suggested boundary names are candidates, not prescriptions. |

**Standard boundary types** (a domain may have a subset — not every domain needs all four):

| Boundary type | Typical responsibility | Span name pattern |
| --- | --- | --- |
| **Dispatch** | Enqueueing work, counting dispatched/skipped units | `{domain}.dispatch` |
| **Execution** | Orchestrating one unit of business work | `{domain}.{unit}` (e.g. `{domain}.action`) |
| **Provider** | Provider-specific translation and external call | `{domain}.provider` |
| **Validation** | Pre-execution ownership/authorization checks (optional, path-specific) | `{domain}.validation` |

### 3.2 Signal ownership

Each signal type has a distinct purpose. No signal type replaces another.

| Signal | Answers | Owned by | Emitted from |
| --- | --- | --- | --- |
| **Business Span** | What happened in this one execution, step by step? | The Business Boundary that wraps the work | `App\Telemetry\{Domain}\*` Telemetry class via `wrap()` |
| **Business Counter** | How often did this business outcome occur? | The same Business Boundary that owns the span | Inside the Telemetry class's `safely()` guard |
| **Business Histogram** | How long did this business operation take? | The same Business Boundary that owns the span | Inside the Telemetry class's `safely()` guard |
| **Business Log** | Why did this specific failure occur? What context is needed for investigation? | The domain class at the narrowest level where all failure paths converge | Domain job/service — not the Telemetry layer |
| **Infrastructure Span/Metric** | How is the platform performing? | HTTP / Queue / Console / Scheduler / HTTP-client auto-instrumentation | Pre-existing, never duplicated |

**Complementarity rule:** Metrics answer "how often?" Traces answer "what happened?" Logs answer "why?" — in that order of aggregation granularity. A signal that merely repeats what another signal already says at the same granularity is duplication and must be rejected.

### 3.3 Failure taxonomy

Every Business Telemetry domain must define a formal failure taxonomy **before** implementing metrics or logging. The taxonomy classifies every reachable outcome into one of five categories:

| Category | Meaning | Span status | Example |
| --- | --- | --- | --- |
| **Business — success** | The operation completed; the business answer was positive | OK | Provider accepted the command |
| **Business — expected negative** | The operation completed; the business answer was negative but deterministic and designed | OK (not ERROR) | Unsupported action type; skip due to missing reference |
| **Business — failure** | The operation completed; the business result was negative (returned failure value, not thrown exception) | OK on the boundary that received the value; ERROR on boundaries where an exception escaped | Provider returned non-2xx; returned failure DTO |
| **Infrastructure** | A dependency failed to complete an operation under normal conditions | ERROR | Database error, unregistered provider slug, credential decryption failure |
| **Platform** | Queue timeout, worker crash, process kill | ERROR (on infrastructure span) | Job timed out after 30s |
| **Telemetry** | The telemetry code itself misbehaved | Degrades to reserved `unknown` outcome; must never affect business execution | Broken classifier closure, broken Tracer |

**Span status policy (mandatory):**

- `setError()` means "this operation failed to complete" — not "the business answer was negative."
- A recognized, expected business outcome (analogous to HTTP 4xx) must **never** mark a span as ERROR.
- `recordException()` and `setError()` are independent — recording an exception for investigation context does not require setting ERROR status.
- Parent spans must not inherit ERROR status from child spans unless the parent itself failed.

### 3.4 Business outcome vocabulary

Every domain that classifies execution outcomes must define a **bounded outcome enum** in the Telemetry layer (`App\Telemetry\{Domain}\{Domain}Outcome`).

| Rule | Detail |
| --- | --- |
| **Closed vocabulary** | The enum must list every outcome the domain can produce. No free-form strings. |
| **Reserved cases** | Include `Unknown` (fail-open degradation) and domain-specific reserved cases (e.g. `Future` for not-yet-implemented providers). |
| **Shared across signals** | The same enum value must drive the span attribute, the metric label, and the log field — one classification, reused everywhere. |
| **Never merge outcomes** | `unsupported`, `skipped`, and `failure` are distinct values. Silently folding one into another is forbidden. |
| **Telemetry-layer only** | The enum lives in `App\Telemetry\{Domain}\`, never in `App\{Domain}\` domain code. Domain code supplies classification via caller-supplied closures. |

**Standard outcome values** (domains may add domain-specific values; these are the platform baseline):

| Value | Meaning |
| --- | --- |
| `success` | Operation completed; business answer positive |
| `failure` | Operation completed or failed; business answer negative or unexpected error |
| `unsupported` | Operation determined to be unmappable/unsupported before external work |
| `skipped` | Operation deliberately not attempted (precondition failure, guard clause) |
| `unknown` | Fail-open fallback when classification itself fails |

### 3.5 Cross-signal consistency

For every business outcome, all three signal types must agree:

```
Business Outcome
      ↓
Business Span (ixora.{unit}.outcome attribute)
      ↓
Business Metric (outcome label on ixora.{domain}.{unit}.total)
      ↓
Business Log (outcome field in structured context — failures only)
```

| Rule | Detail |
| --- | --- |
| **Single classification source** | The Telemetry class classifies the outcome once and reuses that value for span attribute, metric label, and (indirectly, via domain log) log field. Two independent classifications of the same execution are forbidden. |
| **Success is silent in logs** | Routine success is covered by metric + trace. No `Log::info` on hot-path success. |
| **Failure always has a log** | Every failure/unsupported/unexpected path that reaches a domain log site must include `outcome` and appropriate context fields. |
| **No contradictions** | A metric `{outcome=failure}` must never coexist in the same execution with a span `{outcome=success}`. Structural impossibility is enforced by sharing the enum. |

### 3.6 Correlation model

| Rule | Detail |
| --- | --- |
| **OTel trace_id is the sole correlation key** | No custom correlation IDs, business correlation IDs, or domain-specific trace identifiers. |
| **W3C traceparent propagation** | Cross-process boundaries (queue dispatch → worker) rely on the existing `opentelemetry-auto-laravel` queue payload injection — never custom propagation. |
| **TraceCorrelationLogTap** | All log channels receive `trace_id`/`span_id` via the global Monolog tap — domain code never injects correlation manually. |
| **Metric → Trace pivot** | Shared labels (`outcome`, `provider`, `entry_point`) exist on both metric and span — enabling Tempo search from a metric alert. |
| **Trace → Log pivot** | Copy `trace_id` from span → Loki query. No additional keys needed. |

### 3.7 Security model

Business Telemetry must never export data that reveals user identity, home layout, credentials, or unbounded identifiers.

| Forbidden on spans, metric labels, and structured log fields | Allowed in log body fields only (never as metric labels or span attributes) |
| --- | --- |
| Credentials, tokens, API keys | — |
| Raw exception messages (`$e->getMessage()`) | — |
| URLs containing credentials | — |
| Request/response bodies, payloads | — |
| HTTP headers (especially `Authorization`) | — |
| Provider-side entity/device identifiers that reveal layout | Internal database IDs for investigation (`device_id`, `vibe_id`) — log body only |
| User IDs, emails, names | — |
| Unbounded identifiers as metric labels (`user_id`, `device_id`, `schedule_id`, `vibe_id`) | — |

**Exception field standard:** use `exception_class` (bounded PHP FQCN), never raw exception text.

**Provider classification standard:** use bounded semantic categories (e.g. device type category, provider slug normalized to enum), never raw provider-side identifiers.

### 3.8 Fail-open policy

Telemetry must never affect business execution. Every Telemetry class must implement:

1. **`startSpan()` failure** → fall back to a local anonymous inert `Span` implementation. Business code still runs.
2. **Attribute/metric/exception/span-end failures** → caught and swallowed by `safely()`. Never propagate.
3. **Business exception from wrapped code** → recorded on span, then **always rethrown unmodified**. Telemetry observes; it never converts, swallows, or masks business failures.
4. **Classifier closure failure** → degrade span/metric outcome to reserved `Unknown`. Business result unchanged.

This policy is non-negotiable and must be tested in every Telemetry class.

### 3.9 Cardinality policy

| Rule | Detail |
| --- | --- |
| **Bounded labels only** | Every metric label must have a finite, predictable value set. Estimate total time series before implementing. |
| **Enum normalization** | Unknown values normalize to a reserved case (`Future`, `Other`, `Unknown`) — never pass through raw unbounded strings. |
| **No IDs as labels** | `user_id`, `device_id`, `schedule_id`, `vibe_id`, `entity_id`, `trace_id` are forbidden as metric labels. |
| **Platform labels** | `environment` and `service_name` are allowed on every business metric (platform convention). |
| **Reject high-cardinality candidates** | If a label's value set grows with product data (number of users, devices, schedules), reject it as a metric label. Use span attributes or log fields instead. |

### 3.10 Logging policy

| Rule | Detail |
| --- | --- |
| **Domain layer owns logs** | Business logs are emitted from domain jobs/services, not from Telemetry classes. Telemetry classes never import `Log::`. |
| **Failures and unexpected paths only** | No routine success logs on hot paths. |
| **Structured fields mandatory** | Every log uses a structured context array. Free-form concatenated messages are not the primary information source. |
| **Complement, don't duplicate** | A log must provide investigation value unavailable from metrics or traces alone. |
| **One log per failure path** | Do not add a Telemetry-layer log when a domain-layer log already covers the same path. Improve the existing log instead. |
| **Standard fields on failure logs** | `outcome`, `exception_class` (for exceptions), domain-appropriate context IDs (log body only). |

### 3.11 Metrics policy

| Rule | Detail |
| --- | --- |
| **Design Record required** | Every candidate metric must complete a Design Record before implementation (see §6). |
| **Counter for outcomes** | Business outcomes are counted with `ixora.{domain}.{unit}.total` Counter, labeled `outcome` + domain-specific bounded labels. |
| **Histogram for duration** | Business operation latency uses `ixora.{domain}.{unit}.duration` Histogram (unit: `ms`), sharing the Counter's label set. |
| **Reject duplication** | Compare every candidate against existing infrastructure metrics (`ixora.http.*`, `ixora.queue.*`, `ixora.console.*`, `ixora.scheduler.*`) and sibling business metrics before implementing. |
| **Single classification** | Metric labels reuse the same classified outcome the span attribute uses — never a second independent derivation. |
| **Defer when no clean owner** | If a failure path never reaches a Telemetry boundary (guard clause before span starts), defer the metric until a clean owner exists — do not force-fit. |

### 3.12 Tracing policy

| Rule | Detail |
| --- | --- |
| **One span per boundary per execution** | Exactly one Business Span per boundary invocation. Verified by test. |
| **`Tracer::startSpan()`, never `activeSpan()`** | Business spans are additive children of whatever infrastructure span is active — never replacements. |
| **Wrap at the call site when possible** | Prefer wrapping at the caller (controller, command, job) over editing the domain service — keeps domain code unaware of telemetry. Exception: provider adapters where the boundary knowledge lives inside the adapter. |
| **Caller-supplied classifiers** | Telemetry classes must not import domain types. Callers supply closures for outcome classification and count extraction. |
| **No URL/method/status on business spans** | HTTP transport details belong to auto-instrumented CLIENT spans — never duplicated on business spans. |
| **Nest, don't overlap** | Child spans (Provider, HTTP CLIENT) nest inside parent spans (Execution, Dispatch) via `Tracer::startSpan()` activation — never parallel competing spans for the same work. |

---

## 4. Business boundary pattern

### 4.1 Standard lifecycle

Every business pipeline follows this layered model. Not every domain implements every layer — but every layer that exists must respect this ordering and ownership.

```
Entrypoint (HTTP / Console / Scheduler / Event)
      ↓
  [Infrastructure Span — auto-instrumented, Phase 7B.1–7B.3]
      ↓
Business Dispatch Boundary          ← optional; present when one trigger fans out to N units
  `{domain}.dispatch`
      ↓
  [Queue Consumer Span — auto-instrumented, Phase 7B.2]
  [W3C traceparent propagation — automatic]
      ↓
Business Execution Boundary         ← one unit of business work
  `{domain}.{unit}` (e.g. `{domain}.action`)
      ↓
Business Provider Boundary          ← optional; present when external provider I/O occurs
  `{domain}.provider`
      ↓
  [HTTP CLIENT Span — auto-instrumented, opentelemetry-auto-guzzle]
      ↓
External Provider / Downstream System
```

### 4.2 Layer responsibilities

| Layer | Owns | Never owns |
| --- | --- | --- |
| **Entrypoint** | Triggering the pipeline; authorization at HTTP boundary | Business outcome classification |
| **Dispatch** | How many units were enqueued/skipped; entry-point classification | Execution outcomes; provider details |
| **Execution** | One unit's outcome (`success`/`failure`/`unsupported`); provider classification | HTTP transport; queue disposition; notification delivery |
| **Provider** | Provider-specific semantic attributes (e.g. device category); provider-internal work duration | Outcome classification (owned by Execution boundary above); HTTP url/method/status |
| **Infrastructure** | HTTP status, queue job disposition, command duration, CLIENT span url/method/status | Business semantics of any kind |
| **Domain logs** | Failure investigation context at the narrowest convergence point | Routine success; duplicated metric/trace data |

### 4.3 Boundary discovery method

Before implementing any Business Span, perform this discovery — in order:

1. **Read the full call graph** — entry points, services, jobs, adapters, failure paths.
2. **Identify natural seams** — where does real business work begin and end? Where do guard clauses return early without I/O?
3. **Map failure paths** — every `catch`, every early return, every returned failure DTO.
4. **Check infrastructure overlap** — what do existing HTTP/Queue/Console/Scheduler/HTTP-client signals already capture?
5. **Choose the narrowest boundary** — the span wraps only the business decision + external call, not logging, notification, or guard-clause load.
6. **Document the boundary** — write a boundary spec (see Smart Home boundary docs as template) before writing code.

---

## 5. Required Business Telemetry components

Every Business Telemetry domain must deliver the following components. A domain may defer metrics or logging to a later sub-phase, but the architecture must account for all of them from the start.

| Component | Required | Location | Purpose |
| --- | --- | --- | --- |
| **Domain Execution Review** | ✅ Mandatory (discovery phase) | `ixora-infra` doc | Read-only architecture review of the pipeline before any telemetry |
| **Boundary spec(s)** | ✅ One per boundary | `ixora-infra` doc | Formal boundary definition, span attributes, exclusion rationale |
| **Failure Semantics doc** | ✅ Mandatory before metrics/logging | `ixora-infra` doc | Formal failure taxonomy, span status policy, outcome vocabulary |
| **Telemetry class(es)** | ✅ One per boundary | `app/Telemetry/{Domain}/` | `{Domain}{Boundary}Telemetry.php` with `wrap()` method |
| **Outcome enum(s)** | ✅ At least one | `app/Telemetry/{Domain}/` | Bounded outcome vocabulary shared across signals |
| **Domain-specific enums** | As needed | `app/Telemetry/{Domain}/` | Entry point, provider, category enums — all with `Future`/`Other` fallbacks |
| **TelemetryServiceProvider registration** | ✅ Mandatory | `app/Telemetry/Providers/` | Singleton registration with Tracer/Meter/environment/serviceName injection |
| **Dependency rule tests** | ✅ One per Telemetry class | `tests/Unit/Telemetry/{Domain}/` | Contracts-only imports; no domain/HTTP/Queue/Log imports |
| **Telemetry unit/feature tests** | ✅ One per Telemetry class | `tests/Feature/Telemetry/{Domain}/` | Span creation, attributes, fail-open, forbidden fields, no duplicate spans |
| **Boundary integration tests** | ✅ One per boundary | `tests/Feature/Telemetry/{Domain}/` | Real wiring through domain code; hierarchy validation |
| **Metrics Design Records** | ✅ Before any metric | `ixora-infra` doc | One Design Record per candidate metric with cardinality analysis |
| **Business metrics** | Per phase plan | Inside Telemetry class | Counter + optional Histogram, recorded in `safely()` |
| **Logging Design Records** | ✅ Before any log change | `ixora-infra` doc | One Design Record per candidate log |
| **Business log improvements** | Per phase plan | Domain job/service | Structured failure logs with `outcome`, `exception_class` |
| **Architecture validation** | ✅ After all signals shipped | `ixora-infra` doc | Cross-signal consistency, security, correlation, dashboard readiness |

### 5.1 Standard Telemetry class pattern

Every Business Telemetry class follows this structure (validated by Smart Home reference implementation):

```php
final class {Domain}{Boundary}Telemetry
{
    private const SPAN_NAME = '{domain}.{unit}';

    public function __construct(
        private readonly Tracer $tracer,
        // Meter + environment + serviceName when metrics are implemented
    ) {}

    /**
     * @template TResult
     * @param  callable(): TResult  $execute
     * @param  callable(TResult): {Domain}Outcome  $classifyResult
     * @param  callable(Throwable): {Domain}Outcome  $classifyException
     * @return TResult
     */
    public function wrap(/* domain-specific params */, callable $execute, ...): mixed
    {
        $span = $this->startSpan(/* params */);
        $startedAt = hrtime(true);

        try {
            $result = $execute();
        } catch (Throwable $exception) {
            $outcome = $this->classify($classifyException, $exception);
            $this->safely(function () use ($span, $outcome, $exception) {
                $span->setAttribute('ixora.{unit}.outcome', $outcome->value);
                $span->recordException($exception);
                if ($outcome !== {Domain}Outcome::ExpectedNegative) {
                    $span->setError();
                }
            });
            $this->safely(fn () => $this->recordMetrics($outcome, $startedAt));
            $this->safely(fn () => $span->end());
            throw $exception;
        }

        $outcome = $this->classify($classifyResult, $result);
        $this->safely(fn () => $span->setAttribute('ixora.{unit}.outcome', $outcome->value));
        $this->safely(fn () => $this->recordMetrics($outcome, $startedAt));
        $this->safely(fn () => $span->end());

        return $result;
    }

    // startSpan(), classify(), recordMetrics(), inertSpan(), safely()
}
```

**Dependency Rule (mandatory):** Telemetry classes consume only `App\Telemetry\Contracts\*`. No imports from `App\Models\*`, `App\{Domain}\*`, `App\Jobs\*`, `App\Http\*`, `Illuminate\Support\Facades\Log`, or OpenTelemetry SDK classes.

---

## 6. Standard design reviews

Every Business Telemetry domain must complete these reviews **before** writing runtime code. Each review produces a documented decision (Implement / Defer / Reject) for every candidate.

### 6.1 Architecture Review (mandatory first step)

**When:** Before any span, metric, or log code.  
**Reads:** Domain execution review, all platform philosophy guides, existing infrastructure telemetry docs, actual source code.  
**Produces:** Boundary map, call graph, failure path inventory, infrastructure overlap analysis, boundary ownership decisions.  
**Gate:** No implementation begins until boundaries are discovered and documented — not assumed.

### 6.2 Failure Semantics Review (mandatory before metrics and logging)

**When:** After spans are implemented, before metrics or logging.  
**Reads:** All Telemetry classes, domain failure paths, platform traces/logs philosophy.  
**Produces:** Formal failure taxonomy, Business/Infrastructure classification per outcome, span status policy, outcome vocabulary confirmation, propagation rules.  
**Gate:** No metric label or log field may contradict the failure taxonomy.

### 6.3 Metrics Design Review (mandatory before any metric)

**When:** Before registering any Counter or Histogram.  
**For each candidate metric, produce a Design Record containing:**

| Field | Required content |
| --- | --- |
| Metric name | `ixora.{domain}.{unit}.{metric}` per naming convention |
| Metric type | Counter / Histogram / UpDownCounter / Gauge |
| Business question | What operational question does this answer? |
| Boundary owner | Which Business Boundary owns this metric |
| Counting unit | What one increment represents |
| Label set | Every label with bounded/unbounded/sensitive classification |
| Cardinality analysis | Estimated total time series |
| Failure-semantics alignment | How every outcome appears in the metric |
| Duplication analysis | Comparison against infrastructure and sibling business metrics |
| Dashboard preview | How this metric will be used in a future dashboard |
| Decision | Implement / Defer / Reject |

### 6.4 Logging Design Review (mandatory before any log change)

**When:** Before adding or modifying any Business Log.  
**For each candidate log, produce a Design Record containing:**

| Field | Required content |
| --- | --- |
| Log name / trigger | When this log fires |
| Business question | Why does this log exist? |
| Boundary owner | Which boundary owns this log |
| Log level | DEBUG / INFO / WARNING / ERROR — with reasoning |
| Structured fields | Every field with allowed/forbidden classification |
| Failure-semantics alignment | How every outcome appears |
| Duplication analysis | Comparison against metrics, spans, existing domain logs |
| Security review | Confirmation no forbidden fields |
| Correlation | How it links to trace/metric (via TraceCorrelationLogTap) |
| Decision | Implement / Defer / Reject / Improve existing |

### 6.5 Security Review (mandatory before merge)

**When:** Before any Business Telemetry phase is marked complete.  
**Checks:** Every span attribute, metric label, and structured log field against the forbidden list (§3.7).  
**Enforcement:** Automated tests (static source scan + forbidden-attribute assertions), not documentation alone.

### 6.6 Validation Review (mandatory after all signals shipped)

**When:** After spans, metrics, and logging are all implemented for a domain.  
**Produces:** Ownership matrix, cross-signal consistency matrix, correlation workflow validation, dashboard readiness assessment, operational readiness simulation, technical debt register.  
**Reference:** [backend-business-telemetry-validation.md](backend-business-telemetry-validation.md) (Smart Home Phase 7B.4.8 template).

---

## 7. Extension rules

### 7.1 Adding a new business domain

Every new domain follows this sequence — no step may be skipped or reordered:

```
1. Domain Execution Review        (discovery only — read code, map pipeline)
2. Boundary spec(s)               (one doc per boundary — span design)
3. Failure Semantics doc          (taxonomy before metrics/logging)
4. Implement boundary span(s)     (Telemetry class + tests)
5. Metrics Design Review + impl   (Design Record per metric)
6. Logging Design Review + impl   (improve existing domain logs)
7. Architecture Validation        (cross-signal consistency check)
```

Each step produces an `ixora-infra` document and (where applicable) `back_vibes` code + tests on a dedicated feature branch per git-flow.

### 7.2 Adding a new boundary to an existing domain

- Write a new boundary spec before code.
- The new Telemetry class follows the same `wrap()` pattern and Dependency Rule.
- Verify nesting: new span must be a child of the correct parent span via `Tracer::startSpan()`.
- Update the domain's validation doc (or create a delta validation section).

### 7.3 Adding a new provider to an existing domain

- Provider boundary instrumentation is **per-adapter**, not per-interface.
- Each concrete adapter adds its own `{Domain}ProviderTelemetry::wrap()` call inside its execution method.
- No shared base class or interface change required.
- Unknown provider slugs normalize to `Future` on the Execution boundary's provider attribute.
- Unknown domain categories normalize to `Other` on the Provider boundary's category attribute.

### 7.4 Domain-specific extension examples

| Future domain | Expected boundaries | Notes |
| --- | --- | --- |
| **Push Notifications** | `push.delivery` (Execution) | Stop at `PushNotificationEvents` call boundary — do not instrument inside Push pipeline from Smart Home spans. Reuse `wrap()` pattern. |
| **Marketplace** | `marketplace.order`, `marketplace.payment` | New outcome vocabulary (`OrderOutcome`). Payment provider boundary mirrors Provider pattern. |
| **AI** | `ai.inference`, `ai.provider` | Provider boundary wraps LLM API call; HTTP CLIENT span from Guzzle auto-instrumentation nests inside. Never log prompts/responses. |
| **Matter / Google Home / Alexa** | Per-adapter Provider boundary | Same as §7.3 — independent `wrap()` per adapter. Execution boundary unchanged. |
| **Additional Smart Home providers** | Per-adapter Provider boundary | Already validated extensible in Phase 7B.4.8 §11. |

### 7.5 What future domains must NOT redefine

| Already defined platform-wide | Do not recreate per domain |
| --- | --- |
| W3C traceparent queue propagation | Custom correlation IDs |
| TraceCorrelationLogTap | Manual trace_id injection in domain code |
| Fail-open policy | Domain-specific error handling in Telemetry |
| Dependency Rule | Importing domain types into Telemetry classes |
| Span status policy (expected negative ≠ ERROR) | Domain-specific ERROR rules |
| Cardinality policy | Unbounded labels "because useful" |
| Naming convention | Ad-hoc span/metric names outside `ixora.{domain}.*` |

---

## 8. Anti-patterns

The following patterns are **prohibited** in every Business Telemetry implementation. Each was either rejected during the Smart Home design reviews or identified as technical debt during Phase 7B.4.8 validation.

### 8.1 Signal duplication

| Anti-pattern | Why forbidden | Correct approach |
| --- | --- | --- |
| Business span re-recording HTTP duration/status | Infrastructure CLIENT span already owns this | Add only business attributes to business span |
| Business metric re-recording queue job disposition | `ixora.queue.job.total` already owns this | Add only business labels (`outcome`, `provider`) |
| Provider metric duplicating Execution metric 1:1 | Same counting unit, same outcome | One metric at the Execution boundary; Provider span adds semantic attributes only |
| Business log on every success | Metrics + traces cover routine success | Log failures and unexpected paths only |
| Telemetry-layer log duplicating domain-layer log | Violates single-boundary-ownership | Improve the existing domain log instead |
| Second outcome attribute on Provider span identical to Execution span | Same fact, two spans | Outcome on Execution boundary; Provider adds only provider-specific semantics |

### 8.2 Ownership violations

| Anti-pattern | Why forbidden | Correct approach |
| --- | --- | --- |
| Two boundaries recording the same metric | Ambiguous ownership, double counting | One metric, one owner |
| Telemetry class emitting logs | Telemetry layer must not import `Log::` | Domain job/service owns logs |
| Guard-clause path creating a Business Span | No business work occurred | Log at call site; no span |
| Dispatch span recording execution outcomes | Different boundaries, different questions | Dispatch counts enqueued/skipped; Execution records outcome |

### 8.3 Security violations

| Anti-pattern | Why forbidden | Correct approach |
| --- | --- | --- |
| Provider device/entity ID on span or metric label | Reveals home layout / user environment | Bounded category enum only |
| Raw exception message in log field | Unbounded; may contain provider response text | `exception_class` (bounded FQCN) |
| Credentials/tokens in any telemetry field | ADR-030 violation | Never read credential fields in Telemetry code |
| User/device/schedule/vibe ID as metric label | Unbounded cardinality + PII risk | Log body field for investigation only |

### 8.4 Correlation violations

| Anti-pattern | Why forbidden | Correct approach |
| --- | --- | --- |
| Custom business correlation ID | Duplicates OTel trace_id; maintenance burden | Rely on W3C traceparent propagation |
| Manual trace_id injection in domain logs | TraceCorrelationLogTap handles this globally | Register tap; never inject manually |
| Custom queue payload fields for trace context | Duplicates existing OTel queue hook | Reuse `opentelemetry-auto-laravel` propagation |

### 8.5 Design violations

| Anti-pattern | Why forbidden | Correct approach |
| --- | --- | --- |
| Importing domain types into Telemetry classes | Breaks Dependency Rule; couples layers | Caller-supplied classifier closures |
| Span wrapping entire job `handle()` including guards | Conflates "nothing to do" with "attempted and failed" | Narrow boundary to business work only |
| Skipping Architecture Review and assuming brief's boundaries | Boundaries must be discovered from code | Read code first; document boundary spec |
| Implementing metrics before Failure Semantics | Labels may contradict taxonomy | Failure Semantics doc is a mandatory gate |
| Over-engineering: decorator pipelines, execution managers, correlation services | Violates minimal-scope principle | One Telemetry class per boundary with `wrap()` |

---

## 9. Naming conventions (Business Telemetry specific)

Business Telemetry follows [telemetry-naming-convention.md](../../../architecture/telemetry-naming-convention.md) with these domain-specific patterns:

| Artifact | Pattern | Example |
| --- | --- | --- |
| Business span | `{domain}.{unit}` | `smart_home.dispatch`, `push.delivery` |
| Span attribute | `ixora.{unit}.{attribute}` | `ixora.action.outcome`, `ixora.dispatch.entry_point` |
| Business counter | `ixora.{domain}.{unit}.total` | `ixora.smart_home.action.total` |
| Business histogram | `ixora.{domain}.{unit}.duration` | `ixora.smart_home.action.duration` |
| Outcome enum | `{Domain}{Unit}Outcome` | `SmartHomeActionOutcome` |
| Telemetry class | `{Domain}{Boundary}Telemetry` | `SmartHomeActionTelemetry` |
| Telemetry namespace | `App\Telemetry\{Domain}\` | `App\Telemetry\SmartHome\` |
| Metric unit (counter) | `{unit}` (counting unit) | `{action}`, `{dispatch}`, `{delivery}` |
| Metric unit (histogram) | `ms` | Platform-wide convention |

---

## 10. Reference implementation

The Smart Home domain (Phases 7B.4.1–7B.4.8) is the validated reference implementation of this foundation. When implementing a new domain, use these documents as templates:

| Phase | Document | Template for |
| --- | --- | --- |
| 7B.4.1 | [domain-execution-review.md](domain-execution-review.md) | Domain Execution Review |
| 7B.4.2–7B.4.4 | [backend-smart-home-*-boundary.md](backend-smart-home-dispatch-boundary.md) | Boundary specs |
| 7B.4.5 | [backend-business-failure-semantics.md](backend-business-failure-semantics.md) | Failure Semantics (adapt taxonomy rows) |
| 7B.4.6 | [backend-smart-home-business-metrics.md](backend-smart-home-business-metrics.md) | Metrics Design Records |
| 7B.4.7 | [backend-smart-home-business-logging.md](backend-smart-home-business-logging.md) | Logging Design Records |
| 7B.4.8 | [backend-business-telemetry-validation.md](backend-business-telemetry-validation.md) | Architecture Validation |

Code reference:

| Component | Reference file |
| --- | --- |
| Dispatch Telemetry | `app/Telemetry/SmartHome/SmartHomeDispatchTelemetry.php` |
| Execution Telemetry | `app/Telemetry/SmartHome/SmartHomeActionTelemetry.php` |
| Provider Telemetry | `app/Telemetry/SmartHome/SmartHomeProviderTelemetry.php` |
| Outcome enum | `app/Telemetry/SmartHome/SmartHomeActionOutcome.php` |
| Provider registration | `app/Telemetry/Providers/TelemetryServiceProvider.php` |
| Dependency rule test | `tests/Unit/Telemetry/SmartHome/SmartHomeActionTelemetryDependencyRuleTest.php` |
| Fail-open test | `tests/Feature/Telemetry/SmartHome/SmartHomeActionTelemetryTest.php` |
| Integration test | `tests/Feature/Telemetry/SmartHome/SmartHomeActionBoundaryIntegrationTest.php` |

---

## 11. Acceptance criteria (for future domain phases)

A Business Telemetry domain phase is complete only when:

- [ ] Domain Execution Review completed and documented.
- [ ] Every Business Boundary has a boundary spec with discovered (not assumed) begin/end points.
- [ ] Failure Semantics documented with formal taxonomy and span status policy.
- [ ] Every Business Span has exactly one owner; Dependency Rule enforced by test.
- [ ] Every implemented metric has a Design Record with cardinality analysis.
- [ ] Every log change has a Design Record; no routine success logs on hot paths.
- [ ] Cross-signal consistency verified — shared outcome enum, no contradictions.
- [ ] Correlation workflow verified — Metric → Trace → Log via `trace_id` only.
- [ ] Security review passes — automated tests, not documentation alone.
- [ ] Fail-open behavior tested for every Telemetry class.
- [ ] Architecture Validation documented (may be a separate phase).
- [ ] No infrastructure signal duplication introduced.
- [ ] Business behavior unchanged — telemetry is strictly observational.

---

## Related documents

| Document | Relationship |
| --- | --- |
| [backend-business-telemetry-validation.md](backend-business-telemetry-validation.md) | Phase 7B.4.8 — validated the Smart Home architecture this foundation generalizes |
| [domain-execution-review.md](domain-execution-review.md) | Phase 7B.4.1 — Smart Home discovery review (reference template) |
| [backend-sdk-foundation.md](../mvp/backend-sdk-foundation.md) | Phase 7A — Telemetry Abstraction Layer that Business Telemetry builds on |
| [backend-queue-console-instrumentation.md](../mvp/backend-queue-console-instrumentation.md) | Phase 7B.2 — Queue trace-context propagation Business Telemetry reuses |
| [telemetry-decision-guide.md](../../../architecture/telemetry-decision-guide.md) | Signal selection — complements this document's architecture rules |
| [asynchronous-orchestration.md](../../../architecture/asynchronous-orchestration.md) | Entrypoint → validator → service → job → provider layering model |

---

*This document is the official Business Telemetry baseline for Ixora. Established Phase 7B.4.9 from the validated Smart Home reference implementation (Phases 7B.4.1–7B.4.8). Every future Business Telemetry domain must follow this foundation without redefining architecture.*
