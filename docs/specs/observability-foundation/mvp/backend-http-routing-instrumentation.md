# Backend HTTP + Routing Instrumentation — Phase 7B.1 (`back_vibes`)

**Status:** Complete
**Repo:** `back_vibes` (Laravel 13, PHP 8.3+)
**Feature ID:** `observability-foundation/mvp`
**Prerequisite:** [backend-sdk-foundation.md](backend-sdk-foundation.md) (Phase 7A) · [metrics-philosophy.md](../../../architecture/metrics-philosophy.md) · [logs-philosophy.md](../../../architecture/logs-philosophy.md) · [traces-philosophy.md](../../../architecture/traces-philosophy.md) · [telemetry-naming-convention.md](../../../architecture/telemetry-naming-convention.md)

---

## 1. Scope

Phase 7B.1 is the first domain-instrumentation subphase and instruments **only** the HTTP and routing boundary of `back_vibes`. It builds exclusively on the Phase 7A Telemetry Contracts (`Tracer`, `Meter`, `Span`, `Counter`, `Histogram`, `LoggerCorrelation`) — no contract was redesigned, and only one additive method was introduced (§4.1).

| In scope | Out of scope (Phase 7B.2+) |
| --- | --- |
| HTTP request/response lifecycle (web, API, framework `/up` health route) | Queue workers, console commands (Phase 7B.2) |
| Route normalization, bounded status/outcome classification | Scheduler dispatch (Phase 7B.3) |
| `ixora.http.server.request.total` / `ixora.http.server.duration` metrics | Smart Home provider calls (Phase 7B.4) |
| Enrichment of the existing auto-instrumented HTTP server span | Push delivery (Phase 7B.5) |
| Safe HTTP context on existing exception logs | External providers (Phase 7B.6) |

No controller business logic, Form Request, Policy, Model, Resource, Scheduler, queue job, console command, Smart Home code, Push Notification code, provider integration, database schema, API response structure, authentication behavior, or route definition was modified. `git diff --stat` for `back_vibes` in this phase touches only `app/Telemetry/**`, `app/Http/Middleware/HttpTelemetryMiddleware.php`, `bootstrap/app.php`, and `tests/**`.

---

## 2. Existing auto-instrumentation review (Part 1)

Reviewed `open-telemetry/opentelemetry-auto-laravel`'s `Hooks\Illuminate\Contracts\Http\Kernel` hook (the pre/post hook wrapped around `Illuminate\Contracts\Http\Kernel::handle()`) and `Watchers\ExceptionWatcher`.

| Question | Finding |
| --- | --- |
| Root span naming | Pre-hook starts the span named by HTTP method alone (e.g. `GET`). The post-hook renames it to `"{method} /{route->uri}"` **only if** `$request->route()` resolved to a `Route` instance by the time the Kernel returns. |
| Route attribute availability | `http.route` (`TraceAttributes::HTTP_ROUTE`) is set in the post-hook to the route's URI **template** (e.g. `api/vibes/{vibe}`) — but only when a route resolved. Unset for 404/405. |
| HTTP method attribute | `http.request.method` set in the pre-hook from `$request->method()`. Always present. |
| Status-code attribute | `http.response.status_code` set in the post-hook from the final `Response` object. Always present (the Kernel always returns a `Response`, even for errors — see §5.1). |
| Exception recording | Two independent paths: (a) the post-hook's own `endSpan($exception)` calls `recordException()` + `setStatus(ERROR)`, but only if `Kernel::handle()` itself threw past the hook — which it does not for standard Laravel apps (the Kernel's own try/catch always renders a `Response`); (b) `ExceptionWatcher` listens for the `MessageLogged` event and calls `recordException()` whenever an exception is actually **logged** via `report()`. In practice, (b) is what fires for real 5xx errors. |
| 404 (no matching URI) | `Illuminate\Routing\Router::findRoute()` throws `NotFoundHttpException` before any route is bound to the request. `$request->route()` stays `null`; the auto-instrumented span keeps its method-only name and never gets an `http.route` attribute. `NotFoundHttpException` extends `HttpException`, which is in Laravel's default `$internalDontReport` list, so it is **never logged** and `ExceptionWatcher` never fires for it either. |
| 405 (method not allowed) | Same code path as 404 (`findRoute()`), same result: no route attribute, not reported/logged. |
| Unauthenticated requests | Depends entirely on *how* the app rejects the request. `back_vibes`'s own `App\Http\Middleware\FirebaseAuthenticate` returns a `401` JSON response directly — it never throws. Laravel's built-in `AuthenticationException` (not used by this app's routes, but relevant for completeness) is also in `$internalDontReport` and would not be logged either way. |
| Validation failures | `Illuminate\Validation\ValidationException` is also in `$internalDontReport` — never reported/logged, so `ExceptionWatcher` never records it onto the span either. The response status (422) still lands on `http.response.status_code` via the post-hook, since that reads the final `Response`, not the exception. |
| Before a route is resolved | Same as 404/405 — the span exists (started in the pre-hook, before routing), but carries no route information. |

**Conclusion — the auto-instrumented span already carries `http.request.method` and `http.response.status_code` for every request, and `http.route` for every request that resolved a route.** The only genuinely missing pieces are: (1) a **stable, bounded** classification of the outcome (`ixora.http.outcome`), (2) a **route value for the unmatched case** (auto-instrumentation leaves it unset entirely), and (3) the two `ixora.*` metrics, which do not exist anywhere today. Phase 7B.1 therefore **enriches the existing span** (§4) rather than starting a second one, and adds exactly those two metrics (§3).

---

## 3. HTTP telemetry component (Part 2)

`app/Telemetry/Http/`:

| Class | Responsibility |
| --- | --- |
| `HttpOutcome` (enum) | Maps a status code to one of `success` / `client_error` / `server_error` / `cancelled` / `unknown`, and a status code to its bounded family (`2xx`…`5xx`, `unknown`). `Cancelled` is reserved for future domains (queue/console cancellation) — HTTP status codes alone never produce it. |
| `HttpRouteNormalizer` | Returns the resolved route's URI template with a leading slash (e.g. `/api/vibes/{vibe}`), or the bounded constant `HttpRouteNormalizer::UNMATCHED` (`"unmatched"`) when no route resolved. Mirrors the exact value opentelemetry-auto-laravel itself uses for `http.route`, so the Ixora metric label and the enriched span attribute always agree. |
| `HttpExceptionStatus` | Best-effort status-code estimation for a raw exception observed before Laravel has rendered it (used by `HttpRequestTelemetry`'s defensive exception path and by `HttpErrorContextLogTap`). Mirrors a bounded subset of Illuminate's own exception→status mapping (`HttpExceptionInterface`, `ValidationException::$status`, `AuthenticationException`→401, `AuthorizationException`→403, default 500). |
| `HttpRequestTelemetry` | The only class that touches `Tracer`/`Meter`. Records both metrics (§5) and enriches the active span (§6) for every request, via two entry points — `recordResponse()` (the common path — see §5.1) and `recordException()` (a defensive path, kept for correctness but not reachable through a normal HTTP request in this application — see §5.1). Every internal failure is caught and swallowed. |

None of these classes contain domain knowledge (no Scheduler/Smart Home/Push concepts) and none import anything under the `OpenTelemetry\` namespace — enforced by `tests/Unit/Telemetry/Http/HttpTelemetryDependencyRuleTest.php` in addition to the pre-existing generic `tests/Unit/Telemetry/DependencyRuleTest.php`.

---

## 4. Tracer::activeSpan() — a documented, additive contract change (Part 4)

**The blocker.** Part 4's goal is to enrich the *existing* auto-instrumented HTTP span, not create a second one. The Phase 7A `Tracer` contract, however, only exposed `startSpan()` (always creates a **new** span) and `currentTraceId()`/`currentSpanId()`/`currentContext()` (read-only raw identifiers — no way to attach an attribute to whatever span is already active). There was no way to satisfy Part 4 through the contract as it stood.

**The fix — one additive method:**

```php
interface Tracer
{
    public function startSpan(string $name, array $attributes = []): Span; // unchanged
    public function activeSpan(): Span; // new in Phase 7B.1
    public function currentContext(): ?TraceContext; // unchanged
    public function currentTraceId(): ?string; // unchanged
    public function currentSpanId(): ?string; // unchanged
}
```

- No existing method signature changed; every existing caller and implementation continues to compile and behave identically.
- `activeSpan()` never returns `null` — like `startSpan()`, it falls back to a safe no-op `Span` when no span is active or telemetry is disabled.
- **The caller never owns the returned span's lifecycle.** `end()` on the handle `activeSpan()` returns is guaranteed to be a no-op — only the code that originally started the span (auto-instrumentation, or a prior `startSpan()` call) may end it. This is enforced by construction, not just by convention:
  - `App\Telemetry\OpenTelemetry\OpenTelemetryActiveSpan` wraps only the SDK's `SpanInterface` (no `ScopeInterface`) and its `end()` method is a literal no-op — it has no scope to detach and no ownership to release.
  - `NoopTracer::activeSpan()` and the invalid-context fallback both return the existing `NoopSpan`, whose `end()` was already a no-op.
- `OpenTelemetryTracer::activeSpan()` resolves the ambient span via `OpenTelemetry\API\Trace\Span::getCurrent()` — the same API auto-instrumentation itself uses internally — so it is guaranteed to observe the auto-instrumented HTTP span when one is active, with zero coupling to *how* that span was started.

This is the **only** contract change in Phase 7B.1. Every other contract (`Meter`, `Counter`, `Histogram`, `Span`, `LoggerCorrelation`, `TelemetryManager`) is consumed exactly as Phase 7A left it.

---

## 5. Middleware / request lifecycle (Part 5)

### 5.1 Chosen integration point, and a verified finding about Laravel's Pipeline

`App\Http\Middleware\HttpTelemetryMiddleware` is registered **once, globally**, via `bootstrap/app.php`'s `$middleware->append(HttpTelemetryMiddleware::class)` — not on the `web` or `api` route middleware group. `append()` (rather than `prepend()`) places it as the **innermost** global middleware: the narrowest framework boundary that still wraps routing itself, so a single registration point covers web, API, and the framework's `/up` health route, with no risk of double-counting from being attached to more than one group.

```php
public function handle(Request $request, Closure $next): Response
{
    $startedAt = hrtime(true);

    try {
        $response = $next($request);
    } catch (Throwable $exception) {
        $this->telemetry->recordException($request, $exception, $this->elapsedMs($startedAt));
        throw $exception;
    }

    $this->telemetry->recordResponse($request, $response, $this->elapsedMs($startedAt));

    return $response;
}
```

**Verified finding (empirical, via a debug trace against a real 404 request in the test suite, then confirmed by reading the framework source):** `Illuminate\Foundation\Http\Kernel` builds its *global* middleware pipeline with `Illuminate\Routing\Pipeline` — the same exception-catching Pipeline class normally associated only with route-level middleware — not the base `Illuminate\Pipeline\Pipeline`. `Illuminate\Routing\Pipeline::carry()` and `::prepareDestination()` both wrap every pipe (and the final destination) in their own `try`/`catch`, converting any exception into a rendered `Response` via `ExceptionHandler::render()` at the **nearest enclosing frame** — before control ever returns to an outer pipe.

The practical consequence: **every** request outcome — 404, 405, a validation failure (422), an auth failure, or an unhandled controller exception rendered to a 5xx — is already an ordinary `Response` object with the real, final status code by the time it reaches *any* global middleware's `$next()` call, including this one. None of them throw here. This was not the original assumption during implementation (see the two "recordResponse vs recordException" iterations in the test history) — it was corrected against real Kernel behavior rather than left as an unverified assumption.

Consequently:

- `HttpRequestTelemetry::recordResponse()` is the path taken by **every** request in practice, always with the real status code — no estimation needed, ever.
- `HttpRequestTelemetry::recordException()` — and this middleware's own `try`/`catch` — is a **defensive fallback**, kept because Part 5 explicitly asks for "handles thrown exceptions safely" and because it is correct, cheap insurance against a hypothetical future global middleware, or a different invocation context, that does not route through `Illuminate\Routing\Pipeline`. It is exercised directly in `HttpRequestTelemetryMiddlewareTest` (calling `HttpRequestTelemetry::recordException()` directly) rather than through a real HTTP request, since no real HTTP request in this application reaches it.
- The middleware **never** converts an exception into a response, never swallows one, and never changes what would have been returned or thrown without it — confirmed by the full existing HTTP test suite (785 tests, §9) passing unchanged with this middleware active.

### 5.2 Why a middleware, not an event listener

A middleware was chosen over a `RequestHandled`/routing event listener because a middleware alone can (a) measure elapsed time bracketing the *entire* request including any earlier global middleware, (b) guarantee single registration/single execution via one `append()` call, and (c) keep the integration point colocated with, and as simple as, the rest of the HTTP stack (`app/Http/Middleware/`) rather than split across a `EventServiceProvider` listener plus a separate timing mechanism.

### 5.3 Failure isolation

Every telemetry operation inside `HttpRequestTelemetry` — labels, counter, histogram, span attributes — runs inside one `try`/`catch` (`HttpRequestTelemetry::safely()`) that swallows any `Throwable` and returns silently. The middleware itself performs no telemetry work directly, so a broken Tracer/Meter binding (verified in tests via a deliberately-throwing fake `Tracer`) can never surface as an HTTP error (telemetry-availability-policy.md).

---

## 6. Metrics (Part 3)

| Metric | Type | Unit | Labels | Purpose |
| --- | --- | --- | --- | --- |
| `ixora.http.server.request.total` | Counter | `{request}` | `environment`, `service_name`, `http_method`, `http_route`, `status_code_class`, `outcome` | Total HTTP requests — answers "which routes receive traffic" and "which status-code groups are increasing". |
| `ixora.http.server.duration` | Histogram | `ms` (milliseconds) | same as above | HTTP request duration — answers "how long do requests take" and "which routes return errors slowly vs. quickly". |

**Unit choice:** `ms`, matching the unit already documented for this exact metric name in [telemetry-naming-convention.md §"Official examples"](../../../architecture/telemetry-naming-convention.md) ("`ixora.http.server.duration` | Histogram | HTTP request latency (ms)"), chosen platform-wide so future `ixora.*.duration` histograms across Phase 7B.2+ stay consistent without re-deciding the unit per domain.

**Label naming:** underscored (`http_method`, `http_route`, `status_code_class`) rather than the dotted OTel-semconv style (`http.method`) shown as an illustrative example elsewhere in telemetry-naming-convention.md — matching the exact label set specified for this phase. Span attributes (§7) use the dotted OTel-semconv style instead, since those follow `TraceAttributes` naming directly. This is an intentional, phase-scoped distinction between the two signal types, not an inconsistency.

**Forbidden labels — none of the following ever become a label on either metric:** `user_id`, `request_id`, `trace_id`, `span_id`, `email`, `firebase_uid`, full URL, query string, route parameter *values*, raw status code, exception message. Verified by:

- `HttpRouteNormalizer` only ever returns a route's URI **template** or the bounded constant `unmatched` — never `$request->path()` or `$request->fullUrl()`.
- `HttpOutcome::statusCodeClass()` only ever returns `1xx`…`5xx` or `unknown` — the raw integer status code is never assigned to a label (it *is* set as a span attribute, §7, which is bounded and low-cardinality by nature at the trace level, not a Prometheus label).
- `environment` and `service_name` come from `config('telemetry.*')` (Phase 7A, itself sourced from `OTEL_SERVICE_NAME`/`APP_ENV`), never from request data.
- `http_method` comes from `$request->method()` — one of a fixed, small set of HTTP verbs.
- Cardinality-safety tests (`tests/Feature/Telemetry/Http/HttpRequestTelemetryMiddlewareTest.php`, "dynamic route values, query strings, and identifiers never appear...") assert this directly against a route with a dynamic segment plus a query string carrying a fake token and user id.

**No duplication with auto-instrumentation:** opentelemetry-auto-laravel produces spans, not metrics — it emits no `http.server.*` metrics at all in this configuration (its `MeterProvider` usage is limited to what `ClientRequestWatcher`/`QueryWatcher`/`CacheWatcher` instrument, none of which cover inbound HTTP server metrics). These two `ixora.*` metrics are therefore net-new, not a duplicate of anything already emitted.

---

## 7. Span enrichment (Part 4)

Via `Tracer::activeSpan()` (§4), `HttpRequestTelemetry` adds exactly these attributes to the existing auto-instrumented span, for every request:

| Attribute | Source | Example |
| --- | --- | --- |
| `http.request.method` | `$request->method()` | `GET` |
| `http.route` | `HttpRouteNormalizer::normalize()` | `/api/vibes/{vibe}` or `unmatched` |
| `http.response.status_code` | Final response / estimated (defensive path only) | `200`, `404`, `500` |
| `ixora.http.outcome` | `HttpOutcome::fromStatusCode()->value` | `success`, `client_error`, `server_error` |
| `url.scheme` | `$request->getScheme()` | `https` |
| `server.address` | `$request->getHost()` | `api.ixora.example` |

Additionally, `Span::setError()` is called (no description — no message text is ever attached) when the outcome is `server_error`, and `Span::recordException()` is called only on the defensive exception path (§5.1) — for the common path, the exception itself is already recorded onto the span by the existing `ExceptionWatcher` auto-instrumentation (§2), not duplicated here.

**Never added:** full URL, query string, request body, `Authorization` header, cookies, email, Firebase UID, user token, route parameter *values*, or raw exception message text. Route names/templates are the same stable, bounded values used for the metric labels (§6) — never a resolved path.

---

## 8. Structured log alignment (Part 6)

No routine success log was introduced — successful requests are observable via metrics + the trace alone, per metrics-philosophy.md / logs-philosophy.md.

`App\Telemetry\Logging\HttpErrorContextLogTap` — a new Monolog processor "tap", added to every configured log channel by `TelemetryServiceProvider` the exact same way `TraceCorrelationLogTap` (Phase 7A) already is — enriches **existing** exception log records (`context.exception` is a `Throwable`, i.e. Laravel's own `report()`/`Handler::report()` call) with:

```php
[
    'http_method' => $request->method(),
    'http_route' => (new HttpRouteNormalizer)->normalize($request),
    'http_status_code' => HttpExceptionStatus::estimate($exception),
]
```

merged into the record's `extra` bag — `message` and `context` are never touched. It only fires when a route has actually resolved on the request bound to `'request'` in the container, which:

- naturally covers the realistic case (every exception Laravel actually *logs* by default in this app occurs after routing succeeded — 404/405/422/401 are all in Illuminate's `$internalDontReport` list, §2, and are never logged in the first place);
- naturally excludes console/queue contexts, which never carry a resolved HTTP route on the container's `Request` binding, **without** needing to branch on `runningInConsole()` (which is unreliable during CLI-driven feature tests, since PHPUnit/Pest itself runs under the CLI SAPI).

`http_status_code` here is a **best-effort estimate** (`HttpExceptionStatus::estimate()`) computed at `report()` time — before Laravel has rendered the final response — so it may occasionally diverge from the eventual HTTP status for an exception type this mapping does not specifically recognise (defaults to 500, matching the exception handler's own default for unrecognised exceptions). This is a log-context convenience field, not a source of truth for status codes — the metric (§6) and span attribute (§7) always carry the real value.

`trace_id`/`span_id` correlation continues to work exactly as validated in Phase 7A (`TraceCorrelationLogTap`, unchanged) — both taps run independently on every log record and never interfere with each other.

No request body, headers, or other PII are ever read by this tap.

---

## 9. `Log::build()` limitation

Documented in [backend-sdk-foundation.md §8.5](backend-sdk-foundation.md#85-known-limitation-logbuild-on-demand-channels-are-not-tapped) — `TraceCorrelationLogTap` and the new `HttpErrorContextLogTap` are both injected only into channels declared in `config/logging.php` at boot; `Log::build()` on-demand channels are not covered. `back_vibes` does not use `Log::build()` today, so this has no current impact. Documentation-only change, no runtime behavior change, per Part 7's explicit instruction.

---

## 10. Tests (Part 8)

| File | Covers |
| --- | --- |
| `tests/Feature/Telemetry/Http/HttpRequestTelemetryMiddlewareTest.php` | Successful named/dynamic route (1), 404 (2), 405 (3), validation failure (4), auth failure against the app's real `firebase.auth`-protected route (5), unhandled server exception (6), Collector unavailable (7), cardinality safety (8), no double instrumentation (10), `recordException()`'s defensive path exercised directly, and a deliberately-throwing fake `Tracer` proving telemetry failures never surface as an HTTP error. |
| `tests/Unit/Telemetry/Http/HttpTelemetryDependencyRuleTest.php` | Dependency rule (9), scoped to `app/Telemetry/Http` and `app/Http/Middleware/HttpTelemetryMiddleware.php` specifically (in addition to the pre-existing generic scan, which already covers both by walking every `app/` subdirectory). |
| `tests/Unit/Telemetry/Http/HttpRouteNormalizerTest.php` | Route template stability, bounded fallback, no dynamic segments, no query strings, root route. |
| `tests/Unit/Telemetry/Http/HttpOutcomeTest.php` | Status code → outcome and status-code-class mapping, bounded enum surface. |
| `tests/Unit/Telemetry/Http/HttpExceptionStatusTest.php` | Exception → status estimation for `HttpExceptionInterface`, `ValidationException`, `AuthenticationException`, `AuthorizationException`, and the server-error default. |
| `tests/Feature/Telemetry/Http/HttpErrorContextLogTapTest.php` | Tap registered on every channel; enrichment only on exception records with a resolved route; route template never leaks a dynamic segment; console/queue-shaped (routeless) requests untouched; request body/headers/tokens never exported. |

All new tests use the in-memory `Tests\Support\Telemetry\Recording*` fakes (`RecordingTracer`, `RecordingMeter`, `RecordingCounter`, `RecordingHistogram`, `RecordingActiveSpan`) — no real OpenTelemetry SDK, Collector, Prometheus, or Tempo is required for the automated suite, per Part 8's instruction. The one exception ("Collector unavailable") deliberately uses the real Phase 7A bindings against an unreachable OTLP endpoint, mirroring the pattern already established by `TelemetryFailurePolicyTest` in Phase 7A.

---

## 11. Validation results (Part 10)

| Command | Result |
| --- | --- |
| `OTEL_PHP_DISABLED_INSTRUMENTATIONS=all php artisan test tests/Unit/Telemetry tests/Feature/Telemetry` | 75 passed, 215 assertions, 2 pre-existing risky tests (unchanged from Phase 7A, unrelated to this phase) |
| `php artisan test --filter=Http` | 55 passed, 150 assertions |
| `php artisan test` (full suite) | **785 passed**, 2273 assertions — no regressions |
| `./vendor/bin/pint --test` | Passed |

`git diff --stat` in `ixora-infra` for this phase touches only documentation (`docs/**`) — no Collector, Prometheus, Loki, Tempo, Grafana, or OpenTofu file changed.

---

## 12. Known limitations

- **`recordException()` is defensive, not primary.** As established in §5.1, no request in this application's current routing configuration reaches it through a real HTTP call — it is proven correct via a direct unit-style call in the test suite instead. If a future global middleware or Laravel internals change ever bypasses `Illuminate\Routing\Pipeline`'s exception handling, this path is what would fire — but that scenario could not be constructed today to exercise it end-to-end.
- **`http_status_code` in log context is an estimate, not authoritative** (§8) — only relevant for the increasingly rare case where `recordException()`'s defensive path fires; for the primary path the log tap still only sees the raw exception at `report()` time (before rendering), which is an unrelated, pre-existing characteristic of Laravel's exception-reporting order, not something this phase changed.
- **`HttpOutcome::Cancelled` is unused today** — reserved for Phase 7B.2+ (queue/console cancellation semantics) where a genuine "cancelled" signal exists; HTTP status codes alone never produce it.
- **No Grafana dashboard** for these two metrics yet — Phase 9 (Dashboards), out of this phase's scope.

## 13. Remaining work for Phase 7B.2 — Queue + Console

- Manual spans for queue job `handle()` and console command `handle()`, via `Tracer::startSpan()` (not `activeSpan()` — queue/console auto-instrumentation, if enabled, would need its own review analogous to §2 before deciding whether to enrich vs. create).
- `ixora.queue.job.total` / `ixora.queue.job.duration` and `ixora.console.command.total` / `...duration` metrics, following the same label-safety and unit conventions established here (§6).
- Decide whether `HttpErrorContextLogTap`'s pattern (route-presence gating) generalizes to a queue/console equivalent, or whether a job/command-identity-based gate is more appropriate — queue/console contexts have no HTTP route to key off of.
- Explicit non-goal carried forward: no Scheduler, Smart Home, or Push instrumentation in 7B.2 either — those remain 7B.3–7B.5.

---

## Cross-references

- [backend-sdk-foundation.md](backend-sdk-foundation.md) — Phase 7A Telemetry Abstraction Layer, Contracts, dependency rule, log correlation
- [metrics-philosophy.md](../../../architecture/metrics-philosophy.md) · [logs-philosophy.md](../../../architecture/logs-philosophy.md) · [traces-philosophy.md](../../../architecture/traces-philosophy.md)
- [telemetry-naming-convention.md](../../../architecture/telemetry-naming-convention.md) — `ixora.*` namespace, label allowlist, `ixora.http.server.duration` unit
- [telemetry-availability-policy.md](../../../architecture/telemetry-availability-policy.md) — failure isolation
- [ADR-030 — Observability security and privacy](../../../decisions/ADR-030-observability-security-and-privacy.md)
