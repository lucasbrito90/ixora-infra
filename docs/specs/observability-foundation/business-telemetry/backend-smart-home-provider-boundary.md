# Backend Smart Home Provider Boundary — Phase 7B.4.4 (`back_vibes`)

**Status:** Complete
**Repo:** `back_vibes` (Laravel 13, PHP 8.3+)
**Feature ID:** `observability-foundation/mvp`
**Prerequisite:** [domain-execution-review.md](domain-execution-review.md) (Phase 7B.4.1 — authoritative architectural reference) · [backend-smart-home-dispatch-boundary.md](backend-smart-home-dispatch-boundary.md) (Phase 7B.4.2) · [backend-smart-home-action-execution.md](backend-smart-home-action-execution.md) (Phase 7B.4.3) · [backend-queue-console-instrumentation.md](../mvp/backend-queue-console-instrumentation.md) (Phase 7B.2) · [traces-philosophy.md](../../../architecture/traces-philosophy.md) · [telemetry-naming-convention.md](../../../architecture/telemetry-naming-convention.md)

---

## 1. Purpose

Phase 7B.4.4 is the third **Business Telemetry** boundary implemented in `back_vibes`, immediately downstream of the Action Execution boundary (Phase 7B.4.3). It instruments **only** the provider-specific segment of `App\SmartHome\Adapters\HomeAssistantAdapter::executeAction()` — the mandatory architecture review (§2) required by the brief discovered that this segment is **narrower** than the entire method, and that a naive "wrap the whole method" implementation would have both mis-attributed the `unsupported` outcome and duplicated information the existing HTTP client auto-instrumentation already records.

| In scope | Out of scope (later phases) |
| --- | --- |
| One Business Span, `smart_home.provider`, wrapping domain/payload construction, the authenticated HTTP call, and response interpretation inside `executeAction()` | Business metrics (Phase 7B.4.6) |
| `ixora.provider.device_domain` span attribute | Business logging (Phase 7B.4.7) |
| | Instrumenting `listDevices()`, `readStatus()`, or `testConnection()` (out of the Action Execution pipeline this Business Telemetry effort tracks) |
| | A second/future provider adapter's own instrumentation (added independently when that adapter is built) |

No change was made to `App\SmartHome\Contracts\ProviderAdapter.php`, `App\SmartHome\ProviderAdapterResolver.php`, `App\SmartHome\DTOs\ActionResult.php`, `App\SmartHome\Exceptions\UnsupportedSmartHomeActionException.php`, `App\Jobs\SmartHome\SmartHomeActionJob.php`, `App\Telemetry\SmartHome\SmartHomeActionTelemetry.php`, any domain model, migration, database schema, API response shape, queue configuration, or retry behavior. `git diff --stat` for `back_vibes` in this phase touches only `app/Telemetry/SmartHome/**` (new: `SmartHomeProviderTelemetry.php`, `SmartHomeProviderDeviceDomain.php`), `app/Telemetry/Providers/TelemetryServiceProvider.php` (registration only), `app/SmartHome/Adapters/HomeAssistantAdapter.php` (wraps the post-validation segment of `executeAction()`; the unsupported-action check, `client()`, `baseUrl()`, `domainFor()`, and every other method are byte-for-byte unchanged), and `tests/**`.

This phase does not contradict any Phase 7B.4.1, 7B.4.2, or 7B.4.3 finding — it revisits two of 7B.4.3's own attribute-ownership decisions per the brief's explicit instruction not to "automatically preserve the current implementation simply because it already exists" (§4), and confirms both were already correct.

---

## 2. Mandatory architecture review

The brief required discovering the natural Provider Boundary — not assuming the hierarchy sketch in the brief is correct — **before** writing any span code.

### 2.1 `HomeAssistantAdapter::executeAction()`, read in full

```php
public function executeAction(ProviderConnection $connection, string $deviceId, string $action, array $parameters = []): ActionResult
{
    $service = self::ACTION_SERVICE_MAP[$action] ?? null;

    if ($service === null) {
        throw UnsupportedSmartHomeActionException::forAction($action);   // ← thrown BEFORE any provider I/O
    }

    $domain = $this->domainFor($deviceId);                                // ← pure string parse, HA-specific
    $payload = array_merge(['entity_id' => $deviceId], $parameters);      // ← HA-specific payload shape

    try {
        $response = $this->client($connection)                            // ← decrypts token, builds PendingRequest
            ->post($this->baseUrl($connection)."/api/services/{$domain}/{$service}", $payload);
    } catch (ConnectionException) {
        return new ActionResult(success: false, status_code: null, response: null, error_message: 'Provider connection failed.');
    }

    $body = $response->json();

    return new ActionResult(
        success: $response->successful(),
        status_code: $response->status(),
        response: is_array($body) ? $body : null,
        error_message: $response->successful() ? null : 'Provider returned status '.$response->status().'.',
    );
}
```

No loop, no internal retry — exactly one `Http::...->post(...)` call per invocation, confirmed by reading the method in full. `ConnectionException` (transport-level, e.g. DNS failure or timeout) is caught **inside** `executeAction()` and converted into a normal, non-throwing `ActionResult(success: false, ...)` — it never escapes this method for a transport problem. Only `UnsupportedSmartHomeActionException` (thrown before any of the above) and, in principle, an exception from `$this->client($connection)` itself (e.g. `$connection->decryptedCredentials()` failing) can escape `executeAction()` today; the latter has never been observed to throw in this codebase but is not structurally impossible, so the Provider Boundary's Failure Model (§6) still accounts for it.

### 2.2 `ProviderAdapter` interface

`executeAction()`'s docblock states the error-handling policy explicitly: *"never throws for transport/HTTP failures (returns failed ActionResult); throws UnsupportedSmartHomeActionException for unmappable actions."* This is the same policy §2.1 confirms by reading the concrete implementation — the interface and the one existing adapter agree.

### 2.3 `ProviderAdapterResolver`

Unchanged since Phase 7B.4.3's own review (`backend-smart-home-action-execution.md` §2.2): a pure in-memory `match()`, no I/O, throwing a plain `InvalidArgumentException` for an unrecognized provider slug **before any adapter — and therefore any Provider span — can exist**. This fact is load-bearing for §4's attribute-ownership conclusion.

### 2.4 `SmartHomeActionTelemetry` (Phase 7B.4.3)

Re-read in full. `wrap()` calls `Tracer::startSpan('smart_home.action', ...)` before invoking its `$execute` closure — which calls `$resolver->forProvider(...)` then `$adapter->executeAction(...)`. Because `startSpan()` activates the new span as the current context for the duration of the call (`Tracer` contract, `backend-sdk-foundation.md`), `smart_home.action` is already the active span by the time `executeAction()` runs — so anything this phase creates inside `executeAction()` will nest under it for free, with zero propagation code.

### 2.5 `SmartHomeActionJob`

Unchanged. Reviewed to confirm nothing else calls `HomeAssistantAdapter::executeAction()` — the only call site in the entire codebase is inside `SmartHomeActionTelemetry::wrap()`'s `$execute` closure in `SmartHomeActionJob::handle()`.

### 2.6 `HttpRequestTelemetry` (Phase 7B.1) — reviewed, and confirmed irrelevant here

`App\Telemetry\Http\HttpRequestTelemetry` instruments the **inbound HTTP server** boundary (`Illuminate\Http\Request` → `SymfonyResponse`, enriching the span `opentelemetry-auto-laravel` already starts for an incoming request). It has no relationship to the **outbound HTTP client** calls `HomeAssistantAdapter` makes to a user's Home Assistant instance — those are a completely different direction, package, and span. Confirmed by reading the class: it consumes `Illuminate\Http\Request`/`Symfony\Component\HttpFoundation\Response`, types that never appear anywhere in `HomeAssistantAdapter` or `ProviderAdapter`.

### 2.7 HTTP client auto-instrumentation — the package that *is* relevant

`composer.json` declares `open-telemetry/opentelemetry-auto-guzzle: ^1.3` (alongside `opentelemetry-auto-laravel` and `opentelemetry-auto-pdo`). `HomeAssistantAdapter` calls `Illuminate\Support\Facades\Http`, Laravel's HTTP client, which is a thin wrapper around `GuzzleHttp\Client` — the exact class this package instruments. Reading `vendor/open-telemetry/opentelemetry-auto-guzzle/src/GuzzleInstrumentation.php` in full:

- It hooks `GuzzleHttp\Client::transfer()` — the low-level method every `Http::...->get()/->post()/...` call reaches internally, regardless of which Laravel-level facade method was called.
- **Span name:** the raw HTTP method (e.g. `"POST"`, `"GET"`) — `$spanBuilder = $instrumentation->tracer()->spanBuilder(sprintf('%s', $request->getMethod()))`.
- **Span kind:** `SpanKind::KIND_CLIENT`.
- **Parent:** `Context::getCurrent()` at the moment `transfer()` is called — i.e. whatever span is currently active in the same PHP process/request. No custom propagation is involved; it uses the SDK's own ambient context exactly like every other auto-instrumentation package in this stack.
- **Attributes already set:** `url.full`, `http.request.method`, `network.protocol.version`, `user_agent.original`, `http.request.body_size`, `server.address`, `server.port`, `url.path`, `code.function.name`, `code.file.path`, `code.line.number` (request-time), and `http.response.status_code`, `network.protocol.version`, `http.response.body_size` (response-time).
- **Error handling:** on a thrown transport exception, `recordException()` + `setStatus(STATUS_ERROR)`; on a 4xx/5xx response, `setStatus(STATUS_ERROR)`. Both already happen with zero code from this phase.
- **Header capture:** opt-in only, via the `otel.instrumentation.http.request_headers`/`response_headers` ini settings. Grepped the entire repository (`config/`, `.env.example`, `collector/config.yaml`) — **neither setting is configured anywhere**, so no header (including `Authorization`) is ever captured by this auto-instrumentation. The Bearer token is safe by configuration, not by luck.

**Conclusion:** an HTTP `CLIENT` span is already created for the one `Http::...->post(...)` call inside the segment this phase instruments, with url/method/status/duration/exception-recording already fully covered by unmodified, pre-existing infrastructure. §4 and §5 use this finding directly to decide what `smart_home.provider` must **not** duplicate.

### 2.8 Is `url.full` for this specific call path safe?

For `executeAction()`'s one HTTP call, the URL is always `{base_url}/api/services/{domain}/{service}` — e.g. `https://ha.example.test/api/services/light/turn_on`. `{domain}` and `{service}` are bounded, generic Home-Assistant vocabulary (at most 4 × 3 combinations today), never a specific `entity_id`/`provider_device_id` — those are sent only in the POST **body** (`{'entity_id': deviceId, ...parameters}`), which Guzzle's auto-instrumentation never captures (no body-capture hook exists in `GuzzleInstrumentation.php`). `{base_url}`'s **host** is the user's own Home Assistant instance address — already exported today by this pre-existing, unmodified auto-instrumentation, unrelated to and unaffected by this phase; noted here only for completeness of the security review (§8).

---

## 3. Findings — answering the brief's explicit questions (§1.1–§1.7)

### 3.1 Provider Boundary — where it begins and ends

| Candidate (from the brief) | Verdict |
| --- | --- |
| Entering `executeAction()` | **Rejected.** Would include the unsupported-action check, which performs no provider work and happens for a value (`unsupported`) that must remain readable even when this span cannot exist (see §4.3). |
| After unsupported-action validation | **Chosen as the begin point.** Everything from here onward (`$domain = $this->domainFor($deviceId)`) is genuine, HA-specific provider work. |
| Immediately before the HTTP request | Considered as a *narrower* begin point (deferring the span until after `$payload`/`$domain` are built) — **rejected**: it would arbitrarily split two provider-owned computations (`domainFor()`, payload construction) across the span boundary for no benefit, since both are already fully inside the "after validation, before ActionResult" window and both are Provider-owned per §3.7. |
| Wrapping only the HTTP request | **Rejected as the end point** — see next row; it would end the span before response interpretation, which is also Provider-owned. |
| After `ActionResult` construction | **Chosen as the end point.** This is the natural point where "provider execution" is fully resolved into a business-usable result — domain/payload construction, the HTTP call, and response interpretation are all provider-owned and belong inside one span together. |

**Reasoning, in full:** the unsupported-action check is a pure in-memory lookup against `HomeAssistantAdapter::ACTION_SERVICE_MAP` that returns before any connection use, domain/payload computation, or network I/O — structurally and semantically identical to the three guard clauses Phase 7B.4.3 excluded from `smart_home.action` (§2.5 of that phase's doc). Including it inside `smart_home.provider` would mean a span exists for calls where zero provider work happened, and — more importantly — it is unreachable to give it a meaningful place in this span at all, because §4.3 concludes it must stay attributable even when no Provider span exists. Once past that check, every remaining statement in `executeAction()` — domain derivation, payload construction, the authenticated HTTP call, and response interpretation into `ActionResult` — is Provider-owned work with no natural sub-boundary worth splitting further (§3.7).

### 3.2 HTTP auto-instrumentation — duplication analysis

Already answered in full at §2.7. **No duplication occurs**: `smart_home.provider` records exactly one attribute (`ixora.provider.device_domain`, §5) and sets no url/method/status/duration attribute of its own — enforced by a dedicated test (`SmartHomeProviderTelemetryDependencyRuleTest`'s "records no url, http method, status code, or duration attribute of its own"). The Guzzle `CLIENT` span nests **inside** `smart_home.provider` (because `startSpan()` activates the new span before the wrapped closure — including its one `Http::post()` call — runs), giving a clean three-level nesting (`smart_home.action` → `smart_home.provider` → `POST`) rather than two spans describing the same work at the same level.

### 3.3 Span hierarchy — validated against the actual code, not assumed

```
HTTP Server / Console / Scheduler
  └─ smart_home.dispatch                          (Phase 7B.4.2)
       └─ Queue Consumer ("process {destination}" / sync "process")
            └─ smart_home.action                   (Phase 7B.4.3)
                 └─ smart_home.provider             (Phase 7B.4.4 — this phase)
                      └─ POST (opentelemetry-auto-guzzle, SpanKind::CLIENT)
```

This matches the brief's own sketch exactly, but it is not assumed — `SmartHomeProviderBoundaryIntegrationTest`'s "the smart_home.provider span is started strictly after smart_home.action" test proves the ordering through the real pipeline (`SmartHomeActionJob::handle()` → `ProviderAdapterResolver::forProvider()` → `HomeAssistantAdapter::executeAction()`), and `Http::fake()`'s own request recording (`Http::assertSentCount(1)`) proves exactly one HTTP call happens inside that nesting, with no extra call attributable to telemetry itself.

### 3.4 Provider attribute ownership — `ixora.action.provider`

**Verdict: stays on `smart_home.action` (Phase 7B.4.3's own choice). Not moved.**

Reasoning: `ixora.action.provider` must remain readable for **every** execution attempt this pipeline can produce, including the two cases where a Provider span can never exist at all:

1. **Unsupported action** — `HomeAssistantAdapter::executeAction()` throws before this phase's boundary begins (§3.1); no `smart_home.provider` span is ever created for this outcome.
2. **Unknown provider slug** — `ProviderAdapterResolver::forProvider()` throws `InvalidArgumentException` *before any adapter, and therefore any Provider span, can exist* (§2.3) — there is no concrete `HomeAssistantAdapter` (or any other adapter) instance to even carry the wrap call.

If `ixora.action.provider` were moved to `smart_home.provider` exclusively, both of these outcomes would lose all provider attribution anywhere in the trace — a strict observability regression, not a neutral relocation. `smart_home.action` is the boundary that exists for every attempt regardless of whether provider execution ever starts, so it is the only boundary that can own this fact unconditionally. This is not "preserving the status quo because it already exists" (the brief's explicit caution) — it is a structural necessity demonstrated by the two failure modes above, both exercised directly by `SmartHomeProviderBoundaryIntegrationTest` ("an unsupported action type creates a smart_home.action span but NO smart_home.provider span" and "an unknown provider ... creates no smart_home.provider span").

`smart_home.provider` deliberately does **not** duplicate this attribute under a different name either (e.g. no `ixora.provider.name`) — verified by `SmartHomeProviderTelemetryTest`'s forbidden-attribute test, which explicitly asserts `ixora.provider.name` is never present. In the current single-adapter codebase, `smart_home.provider`'s very existence already implies `home_assistant` (only `HomeAssistantAdapter` calls it); a future second adapter would carry the same implicit identity through its own call site, with no attribute needed to disambiguate a span that already only ever originates from one concrete class.

### 3.5 Retry ownership — `ixora.action.retry`

**Verdict: documented as a redundant, lower-fidelity signal already covered by infrastructure. Left unchanged in `smart_home.action` — no implementation change made, per the brief's own "no implementation change is required unless clearly justified" for this attribute.**

`App\Telemetry\Queue\QueueExecutionTelemetry::recordTerminal()` (Phase 7B.2, re-read for this phase) already sets `ixora.queue.attempt` — `$job->attempts()`, the exact integer — on the active span (the parent Queue Consumer span) at the terminal queue event (`JobProcessed`/`JobFailed`/etc.). `ixora.action.retry` (`$this->attempts() > 1`, a boolean) is derived from the *identical* underlying fact, just coarsened to a boolean and recorded on a child span instead of the parent. This **is** genuine duplication of infrastructure-owned data — unlike, for example, `App\Telemetry\Queue\QueueOutcome` vs. `SmartHomeActionOutcome`, which classify genuinely different concepts (queue-attempt disposition vs. business action result) and therefore are not duplicative of each other.

This attribute has no natural home in the Provider Boundary either — retry is an inherently queue-level (infrastructure) concept, not something a specific provider execution attempt "owns" any more than the Action Boundary does. Given the brief permits leaving it unchanged absent a clear justification for a *specific* new home, and moving/removing an already-shipped, tested Phase 7B.4.3 span attribute is outside this phase's own explicit scope (the Provider Boundary), no code change was made. **Recommendation for a future phase:** remove `ixora.action.retry` from `smart_home.action` once a dedicated cleanup phase (or Phase 7B.4.5) can address it deliberately, since `ixora.queue.attempt` already expresses the same fact with strictly higher fidelity on the parent span.

### 3.6 Unsupported-action ownership

**Verdict: belongs to `smart_home.action` (Phase 7B.4.3's own choice, confirmed correct). Not moved to Provider Boundary, and not "neither."**

The action-type → HA-service mapping (`ACTION_SERVICE_MAP`) that determines "supported" is genuinely Provider-specific knowledge (§3.7) — a different provider could support a different action-type vocabulary entirely. But *temporally*, this decision is made **before** any Provider Boundary work begins (§3.1) — there is no provider execution attempt to attach a span to at the moment this decision is made, and no such span should be manufactured just to hold one attribute. `smart_home.action`, by contrast, already exists for every execution attempt regardless of outcome (Phase 7B.4.3 §2.5) — it is the layer that must express "did the action complete, and if not, why" across the full outcome vocabulary, including outcomes where no provider I/O was ever attempted. Excluding `unsupported` from `smart_home.action`'s vocabulary would leave it with no span at all to be recorded on, since a Provider span never starts for this case. This confirms, rather than merely restates, Phase 7B.4.3's original decision — reached independently in this phase's own review rather than assumed correct because it was already shipped.

### 3.7 Provider vs. HTTP — responsibility classification

| Responsibility | Owner | Where it lives today |
| --- | --- | --- |
| Deciding *which* action types this provider supports (`ACTION_SERVICE_MAP` lookup) | **Provider** (but happens before this phase's boundary — see §3.1/§3.6) | `HomeAssistantAdapter::executeAction()`, before the Provider Boundary begins |
| Entity-domain derivation (`light.foo` → `light`) | **Provider** | `HomeAssistantAdapter::domainFor()`, inside the Provider Boundary |
| Payload construction (HA-specific request shape) | **Provider** | `executeAction()`, inside the Provider Boundary |
| Authentication (which credential, how it's presented — Bearer header) | **Provider** decides *what*; **HTTP Client** performs the *transport act* of attaching/sending it | `HomeAssistantAdapter::client()` decrypts + decides; Guzzle sends |
| URL construction (HA REST API path shape) | **Provider** | `HomeAssistantAdapter::baseUrl()` + inline string interpolation |
| Response interpretation (status/body → `ActionResult.success`/`.error_message`) | **Provider** | `executeAction()`'s post-request logic, inside the Provider Boundary |
| HTTP transport (socket I/O, following the request/response over the wire, protocol-level timeouts) | **HTTP Client** | Guzzle (`GuzzleHttp\Client::transfer()`), already auto-instrumented (§2.7) |
| Deciding *which* provider to use, orchestrating the action, retry policy, logging, push notifications | **Business** | `SmartHomeActionJob::handle()` / `SmartHomeActionTelemetry` (Phase 7B.4.3) |
| Queue transport, trace-context propagation, process lifecycle | **Infrastructure** | `opentelemetry-auto-laravel` queue producer/consumer spans (Phase 7B.2) |

The Provider Boundary this phase implements (`smart_home.provider`) therefore wraps exactly the four Provider-owned rows that occur *after* the unsupported check: domain derivation, payload construction, the (Provider-initiated, HTTP-Client-executed) request, and response interpretation.

---

## 4. Why no outcome or provider-identity attribute is duplicated onto `smart_home.provider`

Beyond §3.4's conclusion about `ixora.action.provider`, this phase also deliberately does **not** add an outcome-style attribute (e.g. `ixora.provider.outcome`) to `smart_home.provider`:

- A returned, non-throwing `ActionResult(success: false, ...)` — the provider responding with a non-2xx status, or a caught `ConnectionException` — already carries its own signal one level deeper: the nested Guzzle `CLIENT` span's own `http.response.status_code`/error status (for a bad HTTP response) or its own `recordException()`/error status (for a caught transport exception, §2.7). A same-trace viewer inspecting `smart_home.provider`'s child span already sees exactly why the call failed.
- In the current single-adapter implementation, "did the provider call succeed" is the *exact same fact* as `smart_home.action`'s own `ixora.action.outcome` (`success`/`failure`) for the non-exception path — `SmartHomeActionJob::handle()`'s `classifyResult` closure maps `$result->success` directly. Duplicating it here would be adding a second attribute, on a second span, expressing a fact the first span already expresses — precisely the kind of duplication §3 of the brief (Telemetry Rules) forbids. This is a different situation from `App\Telemetry\Queue\QueueOutcome` (§3.5), which classifies a genuinely distinct concept from the Action outcome, so recording both is not duplicative there.
- `smart_home.provider` still reflects failure at the **span-status level** (not via a custom attribute) for the one case that is genuinely its own: an exception escaping the wrapped segment entirely (e.g. a credential-decryption failure inside `client()`) — `recordException()` + `setError()`, mirroring the exact policy `HttpRequestTelemetry` already uses for its own active span (only marks an error for a genuine failure, not for an expected/returned failure value) and the exact policy `SmartHomeActionTelemetry` and `SmartHomeDispatchTelemetry` already use.

---

## 5. Boundary

| Aspect | Definition |
| --- | --- |
| **Owns** | Domain derivation (`domainFor()`), payload construction, the authenticated HTTP call, and response interpretation into `ActionResult`, for one `HomeAssistantAdapter::executeAction()` invocation. |
| **Begins** | Immediately after the unsupported-action check passes (`$domain = $this->domainFor($deviceId)`). |
| **Ends** | Immediately before `executeAction()` returns its `ActionResult` (success, or a failed result from either a non-2xx response or a caught `ConnectionException`) — or, in the rare case an unexpected exception escapes the wrapped segment (e.g. `client()`'s credential decryption failing), immediately before that exception propagates out of `executeAction()`. |
| **Never includes** | The unsupported-action check itself (§3.1/§3.6), any code in `SmartHomeActionJob::handle()` (owned by `smart_home.action`, Phase 7B.4.3), any code in `VibeSmartHomeDispatchService::dispatch()` (owned by `smart_home.dispatch`, Phase 7B.4.2), queue transport, logging, or push notifications. |

### Parent span

`App\Telemetry\SmartHome\SmartHomeProviderTelemetry` calls `Tracer::startSpan()`, never `Tracer::activeSpan()` — exactly like `SmartHomeActionTelemetry` and `SmartHomeDispatchTelemetry`. Because `SmartHomeActionTelemetry::wrap()` has already called `startSpan('smart_home.action', ...)` before invoking its `$execute` closure (which reaches `HomeAssistantAdapter::executeAction()`), `smart_home.action` is the active span at the exact moment `SmartHomeProviderTelemetry::wrap()` runs — satisfying "reuse the existing active span" and "never create duplicate root spans" structurally, with zero code in this class needing to know what a "Queue Consumer span" or "Action span" is.

### Relationship with the Action Boundary (Phase 7B.4.3) and the HTTP Client span

`smart_home.action` remains open for the entire duration of `executeAction()` (as documented by Phase 7B.4.3 §4, "Relationship with the future Provider Boundary") — `smart_home.provider` now occupies exactly the portion of that time §5's table describes, nested one level deeper. The Guzzle `CLIENT` span (§2.7) nests one level deeper still, inside `smart_home.provider`, for the exact same reason — `Tracer::startSpan()`'s activation contract, applied transitively three times with zero propagation code added anywhere in this Business Telemetry effort.

---

## 6. Span

| Property | Value |
| --- | --- |
| Name | `smart_home.provider` |
| Count per `executeAction()` invocation that reaches the boundary | Exactly one — verified by `SmartHomeProviderTelemetryTest` ("never creates more than one span per call") and `SmartHomeProviderBoundaryIntegrationTest` (one span per successful/failed execution; zero for unsupported/unknown-provider outcomes). |
| Attributes | `ixora.provider.device_domain` (`light` \| `switch` \| `media_player` \| `fan` \| `other`, reserved) — nothing else. |
| On success (any returned `ActionResult`, success or failure) | `end()` only — no outcome attribute is set (§4); span status remains OK. |
| On an exception escaping the wrapped segment | `recordException()`, `setError()`, then `end()` — the original exception is always rethrown unchanged. |
| Never contains | `action_id`, `device_id`, `entity_id`, `provider_device_id`, `schedule_id`, `vibe_id`, `user_id`, any database ID, provider URLs, IP addresses, headers, tokens, credentials, `authorization`, payloads, JSON, request/response bodies, `ixora.action.outcome`/`.provider`/`.retry` (Action Boundary's own attributes), or any `http.*`/`url.*`/`server.*`/duration attribute (HTTP Client's own attributes, §2.7) — verified directly by `SmartHomeProviderTelemetryTest`'s "never sets a forbidden or duplicated attribute" assertion and `SmartHomeProviderTelemetryDependencyRuleTest`'s "records no url, http method, status code, or duration attribute of its own". |

`ixora.provider.device_domain=other` is a reserved fallback for any entity domain outside the four currently-actionable Home Assistant domains (`light`/`switch`/`media_player`/`fan`, `HomeAssistantAdapter::ACTIONABLE_DOMAINS`) — unreachable today (device sync already filters to only these four domains before an action can target a device) but bounds this attribute's cardinality regardless of future changes to that filter, mirroring the enum-reservation convention already used elsewhere in this Telemetry layer (e.g. `SmartHomeActionProvider::Future`, `SmartHomeActionOutcome::Unknown`).

---

## 7. Fail-open

Every public path through `SmartHomeProviderTelemetry::wrap()` is safe:

- `startSpan()` failure (a broken `Tracer`) falls back to a local inert `Span` implementation (mirrors `SmartHomeActionTelemetry::inertSpan()`/`SmartHomeDispatchTelemetry::inertSpan()` exactly) — `execute()` still runs, and its result (or thrown exception) is still returned/rethrown unchanged.
- Attribute-setting, exception-recording, and span-ending failures are caught and swallowed (`safely()`) — never propagate.
- A genuine exception escaping the wrapped segment is recorded on the span (`recordException()`/`setError()`) and then **always rethrown unmodified** — telemetry observes the failure, it never converts, swallows, or masks it, and it never alters which of `SmartHomeActionTelemetry::wrap()`'s own paths (and, transitively, `SmartHomeActionJob::handle()`'s own `catch` blocks) receives it.

Verified directly by `SmartHomeProviderTelemetryTest`: "a broken Tracer never prevents `wrap()` from running `execute()` or returning its result" and "a broken Tracer combined with a business failure still rethrows the original exception unchanged". Verified end-to-end by `SmartHomeProviderBoundaryIntegrationTest`'s "a broken Tracer never prevents the full pipeline from executing the provider call and returning a result".

---

## 8. Security review

| Forbidden item (per brief §5) | Present anywhere in this phase's new attributes? |
| --- | --- |
| `entity_id` / `provider_device_id` | No — `ixora.provider.device_domain` carries only the entity-domain *category* (`light`/`switch`/`media_player`/`fan`/`other`), never the specific entity id passed into `executeAction()`. Verified by `SmartHomeProviderBoundaryIntegrationTest`'s "no span attribute anywhere in the pipeline ever contains the specific provider_device_id/entity_id" test, which asserts this against a deliberately identifying test fixture value (`light.super_secret_living_room`). |
| `access_token` / `credentials` | No — this phase's code never reads `$connection->decryptedCredentials()` or any credential field; it only receives the already-computed `$domain` string. |
| Headers | No — never touched. The pre-existing Guzzle auto-instrumentation this phase nests under also never captures headers by default (§2.7) — confirmed unrelated to, and unaffected by, this phase's own diff. |
| Request/response body | No — this phase's wrapped closure returns the caller's own `ActionResult` unchanged; `SmartHomeProviderTelemetry` never inspects it. |
| `authorization` | No — never referenced. |
| URLs containing credentials | Not applicable — the Home Assistant token is sent as a Bearer header (`Http::withToken()`), never as a URL query parameter, in the pre-existing, unmodified `client()`/`executeAction()` code this phase wraps but does not alter. |

Every item above is enforced by an automated test, not just documentation: `SmartHomeProviderTelemetryDependencyRuleTest`'s forbidden-import scan (no `App\Models`, no `App\SmartHome`, no `Illuminate\Http`, no `GuzzleHttp`, no `Log`/`DB`/`Http` facade) and `SmartHomeProviderTelemetryTest`'s forbidden-attribute-fragment scan together guarantee this class structurally cannot access, let alone export, any of the above.

---

## 9. What was intentionally excluded

Per the brief, this phase adds none of the following (all reserved for later phases, or explicitly out of this pipeline's scope):

- Any `Counter`/`Histogram`/`UpDownCounter`/observable instrument — no metric of any kind (Phase 7B.4.6). Verified by `SmartHomeProviderTelemetryTest`'s "never records a counter, histogram, or up-down counter" and the dependency-rule tests' ban on importing `Counter`/`Histogram`/`UpDownCounter`/`Meter`.
- Any `LogTap`, structured log enrichment, or logging change of any kind (Phase 7B.4.7). Verified by the dependency-rule tests' ban on any `Log::` usage inside the two new files.
- Any new domain abstraction — no `ProviderExecution`, `ProviderExecutionContext`, `InstrumentedProviderAdapter`, or decorator/pipeline wrapper exists anywhere in this diff. `SmartHomeProviderTelemetry` is injected directly into the one existing concrete adapter, exactly the way `SmartHomeActionTelemetry`/`SmartHomeDispatchTelemetry` are already injected into their respective call sites — no new architectural layer.
- Instrumentation of `HomeAssistantAdapter::listDevices()`, `::readStatus()`, or `::testConnection()` — out of the Action Execution pipeline this Business Telemetry effort tracks (per Phase 7B.4.1's own scope), and not part of the brief for this phase.
- Any database, API, or frontend change. `App\SmartHome\DTOs\ActionResult`'s shape and every method on `HomeAssistantAdapter` other than `executeAction()` are byte-for-byte unchanged.
- Any change to `App\SmartHome\Contracts\ProviderAdapter`, so a second provider adapter is free to add its own `smart_home.provider` wrap call at its own pace, independently, without this phase forcing a shared base class or interface change on it first.

---

## 10. Accepted limitations

- **Per-adapter instrumentation, not interface-level.** Because Provider-specific business decisions (the unsupported-action check, the domain-derivation scheme) live inside each concrete adapter and not in the shared `ProviderAdapter` interface, this phase's `wrap()` call was added directly inside `HomeAssistantAdapter::executeAction()` rather than at an external call site — the one deliberate departure from the "wrap only at the call site, never touch the wrapped file" pattern Phases 7B.4.2/7B.4.3 preferred where possible (§2.1/§3.1 explain why no external call site has the knowledge needed to exclude the unsupported check without duplicating `ACTION_SERVICE_MAP`). A future second adapter (e.g. Tuya, Philips Hue) will need its own, independent `SmartHomeProviderTelemetry` wrap call added the same way — this phase does not generalize the pattern into a shared base class or decorator, per the Architectural Principles' ban on new abstractions.
- **`ixora.provider.device_domain=other` is currently unreachable** — reserved for a domain outside the four currently-actionable Home Assistant domains, which device sync's own existing filtering already prevents from ever reaching `executeAction()` today.
- **`ixora.action.retry` remains a documented, unresolved duplicate of `ixora.queue.attempt`** (§3.5) — this phase's review surfaced the finding and recommends addressing it in a future phase, but made no change to Phase 7B.4.3's own shipped attribute, since no new home for it exists within this phase's own scope (the Provider Boundary).
- **The credential-decryption failure path (`client()` throwing before any HTTP call) is exercised only by the unit-level `SmartHomeProviderTelemetryTest`'s generic exception test, not by a dedicated integration test that forces `ProviderConnection::decryptedCredentials()` itself to throw** — this has never been observed to throw in this codebase's existing `HomeAssistantAdapterTest.php` coverage, and forcing it would require reaching into encryption internals unrelated to this phase's own scope. The Fail-open/rethrow contract (§7) is proven generically (any exception from the wrapped closure) rather than for this one specific, currently-hypothetical source.
- **No fan-in visibility across the four Provider-owned responsibilities individually** (domain derivation vs. payload construction vs. the HTTP call vs. response interpretation, §3.7) — `smart_home.provider` reports them as one atomic unit of "provider execution", not as separately-timed sub-steps; splitting further was considered (§3.1) and rejected as unwarranted granularity for work that is synchronous, fast, and non-branching today.

---

## 11. Future phases

- **Phase 7B.4.5 (or a dedicated cleanup phase):** address the `ixora.action.retry` duplication finding from §3.5 — likely removal from `smart_home.action`, since `ixora.queue.attempt` already expresses the same fact with higher fidelity.
- **A second provider adapter (Tuya, Philips Hue, etc.):** will need its own `SmartHomeProviderTelemetry::wrap()` call added inside its own `executeAction()` implementation, following this phase's pattern independently — no shared infrastructure change is required for `SmartHomeProviderTelemetry` itself to support it (it already accepts any domain-slug string, with `SmartHomeProviderDeviceDomain::fromDomainSlug()`'s `Other` fallback already bounding cardinality for a second provider's own vocabulary).
- **Phase 7B.4.6 — Business metrics:** first `ixora.*`-style business counters/histograms across Dispatch, Action, and now Provider boundaries.
- **Phase 7B.4.7 — Business logging:** first structured log enrichment for Smart Home execution; may reuse `SmartHomeProviderDeviceDomain` for consistent classification once a log tap is introduced.
- **Phase 7B.5 — Push Notifications**, **Phase 7B.6 — External Providers:** unaffected by, and independent of, this phase.

---

## 12. Tests

| File | Covers |
| --- | --- |
| `tests/Unit/Telemetry/SmartHome/SmartHomeProviderTelemetryDependencyRuleTest.php` | The two new files exist; no OpenTelemetry SDK/API import; no concrete Telemetry implementation import; no `App\Models`/`App\SmartHome`/`App\Jobs`/`App\Http\Controllers`/`App\Console\Commands`/`App\PushNotifications`/`Illuminate\Http`/`GuzzleHttp` import; `SmartHomeProviderTelemetry` depends only on `Tracer`/`Span`/`Throwable` (plus the co-located enum, same namespace, no `use` needed); the enum has zero imports; no metric-contract import; no `Log::` usage; no `url.full`/`http.request.method`/`http.response.status_code`/`server.address`/duration attribute is ever set. |
| `tests/Feature/Telemetry/SmartHome/SmartHomeProviderTelemetryTest.php` | Span creation/naming/`device_domain` attribute (all four known domains + unknown-slug normalization); forbidden-attribute exhaustiveness (single allowed key + substring scan + explicit ban on `ixora.provider.name`); span ends exactly once; `execute()` runs strictly before `end()`; no duplicate spans across repeated calls; `startSpan()` used (never `activeSpan()`); exception path records + errors + ends + rethrows unchanged (identity-checked); a normally-returned failure value does **not** mark the span as errored; fail-open under a broken `Tracer` (success and failure sub-cases); zero metrics recorded; `SmartHomeProviderDeviceDomain::fromDomainSlug()` normalization. |
| `tests/Feature/Telemetry/SmartHome/SmartHomeProviderBoundaryIntegrationTest.php` | Real wiring through the full `SmartHomeActionJob::handle()` → `HomeAssistantAdapter::executeAction()` pipeline: a successful execution produces both `smart_home.action` and `smart_home.provider`, correctly nested and tagged; unsupported-action and unknown-provider outcomes produce **no** `smart_home.provider` span at all; a failed `ActionResult` (HTTP 500) and a caught `ConnectionException` each still produce a `smart_home.provider` span that is **not** marked as errored; exactly one provider HTTP call per span with no duplication; no span attribute anywhere in the pipeline ever contains the specific `provider_device_id`; fail-open under a broken `Tracer`. |
| `tests/Unit/SmartHome/HomeAssistantAdapterTest.php` (pre-existing, 26 tests, unmodified assertions) | Still fully green — proves this phase changed no observable adapter behavior (only its `haAdapter()` test helper was updated to pass the new `SmartHomeProviderTelemetry` constructor argument). |
| `tests/Unit/SmartHome/ProviderAdapterResolverTest.php` (pre-existing, unmodified assertions) | Still fully green — only its `makeResolver()` test helper was updated for the same reason. |
| `tests/Feature/Telemetry/SmartHome/SmartHomeActionBoundaryIntegrationTest.php` (pre-existing, Phase 7B.4.3) | Three assertions updated from `spanEndCalls === 1` to `spanEndCalls === 2`, reflecting the now-real nested `smart_home.provider` span ending alongside `smart_home.action` — no other assertion in this file changed. |

Full suite: **960/960 passing** (929 pre-existing at the start of Phase 7B.4.4 + 31 new in this phase), 2 pre-existing risky tests unrelated to this phase (confirmed by running the two new test files in isolation: 31/31, zero risky), `pint --test` clean.

---

## 13. Files touched

**New:**

- `app/Telemetry/SmartHome/SmartHomeProviderTelemetry.php`
- `app/Telemetry/SmartHome/SmartHomeProviderDeviceDomain.php`
- `tests/Unit/Telemetry/SmartHome/SmartHomeProviderTelemetryDependencyRuleTest.php`
- `tests/Feature/Telemetry/SmartHome/SmartHomeProviderTelemetryTest.php`
- `tests/Feature/Telemetry/SmartHome/SmartHomeProviderBoundaryIntegrationTest.php`

**Modified (registration/wiring only, no unrelated business-logic change):**

- `app/Telemetry/Providers/TelemetryServiceProvider.php` — registers the `SmartHomeProviderTelemetry` singleton.
- `app/SmartHome/Adapters/HomeAssistantAdapter.php` — adds a constructor dependency on `SmartHomeProviderTelemetry`; wraps the post-validation segment of `executeAction()` (domain/payload construction through `ActionResult` construction) in `$this->providerTelemetry->wrap(...)`; the unsupported-action check and every other method (`listDevices()`, `readStatus()`, `testConnection()`, `client()`, `baseUrl()`, `domainFor()`, `mapDevice()`, `mapStatus()`, `unknownStatus()`, `parseTimestamp()`, `elapsedMs()`) are byte-for-byte unchanged.
- `tests/Unit/SmartHome/HomeAssistantAdapterTest.php` — `haAdapter()` test helper updated to pass the new constructor argument; no assertion changed.
- `tests/Unit/SmartHome/ProviderAdapterResolverTest.php` — `makeResolver()` test helper updated for the same reason; no assertion changed.
- `tests/Feature/Telemetry/SmartHome/SmartHomeActionBoundaryIntegrationTest.php` — three `spanEndCalls` assertions updated from `1` to `2` to reflect the now-real nested Provider span; no other assertion changed.

**Untouched:**

- `app/SmartHome/Contracts/ProviderAdapter.php`
- `app/SmartHome/ProviderAdapterResolver.php`
- `app/SmartHome/DTOs/ActionResult.php`
- `app/SmartHome/Exceptions/UnsupportedSmartHomeActionException.php`
- `app/Jobs/SmartHome/SmartHomeActionJob.php`
- `app/Telemetry/SmartHome/SmartHomeActionTelemetry.php`
- `app/Telemetry/SmartHome/SmartHomeActionProvider.php`
- `app/Telemetry/SmartHome/SmartHomeActionOutcome.php`
- `app/Telemetry/SmartHome/SmartHomeDispatchEntryPoint.php`
- `app/Telemetry/SmartHome/SmartHomeDispatchTelemetry.php`
- Every domain model and migration.
