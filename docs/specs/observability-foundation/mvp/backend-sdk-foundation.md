# Backend SDK Foundation — Phase 7A (`back_vibes`)

**Status:** Complete
**Repo:** `back_vibes` (Laravel 13, PHP 8.3+)
**Feature ID:** `observability-foundation/mvp`
**Prerequisite:** [metrics-philosophy.md](../../../architecture/metrics-philosophy.md) · [logs-philosophy.md](../../../architecture/logs-philosophy.md) · [traces-philosophy.md](../../../architecture/traces-philosophy.md) · [telemetry-naming-convention.md](../../../architecture/telemetry-naming-convention.md) · [telemetry-availability-policy.md](../../../architecture/telemetry-availability-policy.md)

---

## 1. Scope

Phase 7A introduces the OpenTelemetry PHP SDK into `back_vibes` and builds a **Telemetry Abstraction Layer** so the rest of the application never depends on the SDK directly. It is deliberately narrow:

| In scope | Out of scope (Phase 7B+) |
| --- | --- |
| SDK evaluation and installation | Scheduler / Smart Home / Push / Marketplace / AI manual spans |
| `app/Telemetry/` module: contracts, OpenTelemetry implementation, No-op implementation | Custom metrics (`ixora.*` counters/histograms) |
| Generic auto-instrumentation (HTTP, routing, console, queue, DB) | Custom structured logs beyond correlation |
| `trace_id` / `span_id` log correlation | Domain-specific span attributes |
| Configuration via environment variables | Grafana dashboards (Phase 9) |
| Failure-policy validation | Alerting (post-MVP) |

No business rule, controller logic, Scheduler, Smart Home, Push, queue logic, database schema, policy, validator, provider, job, command, service, or repository was modified. `git diff --stat` for this phase touches only `app/Telemetry/**`, `bootstrap/providers.php`, `config/telemetry.php`, `.env.example`, `composer.json`/`composer.lock`, and `tests/**/Telemetry/**`.

---

## 2. SDK evaluation

### 2.1 Candidates considered

| Package | Maintainer | Verdict |
| --- | --- | --- |
| `open-telemetry/sdk` + `open-telemetry/api` | Official OpenTelemetry (CNCF) | ✅ **Chosen** — reference PHP implementation |
| `open-telemetry/exporter-otlp` | Official OpenTelemetry | ✅ **Chosen** — OTLP/HTTP exporter, matches the Collector (`collector/config.yaml`) |
| `open-telemetry/opentelemetry-auto-laravel` | Official OpenTelemetry (`opentelemetry-php-contrib`) | ✅ **Chosen** — the only Laravel-specific auto-instrumentation package, actively maintained under the OpenTelemetry GitHub org |
| `open-telemetry/opentelemetry-auto-guzzle` | Official OpenTelemetry | ✅ **Chosen** — HTTP client instrumentation (Guzzle backs Laravel's `Http::` facade) |
| `open-telemetry/opentelemetry-auto-pdo` | Official OpenTelemetry | ✅ **Chosen** — raw PDO/database query spans |
| `mismatch/opentelemetry-auto-redis` (a.k.a. `CRC-Mismatch/opentelemetry-auto-redis`) | Independent maintainer, **not** under the `open-telemetry` GitHub org | ❌ **Rejected** — the only PHP-Redis/Predis auto-instrumentation package that exists today is community-maintained with uncertain long-term support; no official alternative exists yet. See §9 "Limitations". |
| Sentry / New Relic / Datadog PHP agents | Vendor-specific commercial APMs | ❌ **Rejected** — locks Ixora into a proprietary backend; contradicts ADR-028 (Collector-only, vendor-neutral pipeline already built in Phases 3–6) |
| `nesbot/carbon`-style ad-hoc timing + custom log fields (no SDK) | N/A | ❌ **Rejected** — would not interoperate with the Collector/Tempo/Prometheus pipeline already deployed; reinvents context propagation, sampling, and OTLP export |

### 2.2 Why the official SDK

- **Official, CNCF-governed:** `open-telemetry/*` packages are maintained by the OpenTelemetry PHP special interest group, not a third party. This is the path OpenTelemetry itself documents for PHP zero-code instrumentation (<https://opentelemetry.io/docs/zero-code/php>).
- **Directly compatible with the existing Collector:** the Collector (Phase 3) already speaks OTLP/HTTP on `:4318` with `bearertokenauth` — `open-telemetry/exporter-otlp` needs zero Collector-side changes.
- **Matches ADR-028/029:** ADR-028 mandates OpenTelemetry as the platform standard and Collector-only ingestion; ADR-029 defines the OTel data model (resource attributes, span/metric/log shape) this SDK produces natively.
- **Long-term support:** `open-telemetry/sdk` reached **stable 1.x** (semver-guaranteed API); this project pins `^1.14` (SDK) / `^1.9` (API) / `^1.4` (OTLP exporter) — all stable, actively released lines (multiple releases per quarter as of 2026).
- **Laravel-specific official package exists:** `opentelemetry-auto-laravel` is the only Laravel package under the `open-telemetry` org, avoiding a maintenance gap.

### 2.3 Trade-offs accepted

| Trade-off | Mitigation |
| --- | --- |
| Auto-instrumentation (`opentelemetry-auto-*`) requires the `ext-opentelemetry` PECL extension to activate its `hook()`-based interception; without it, each package prints a `E_USER_WARNING` and skips registration. | Production Docker image installs the extension (see §8.4). Local/CI environments without the extension set `OTEL_PHP_DISABLED_INSTRUMENTATIONS=all`, which short-circuits the warning *and* is itself a documented, official OTel PHP configuration variable — not a workaround. |
| `google/protobuf` (required by `open-telemetry/gen-otlp-protobuf`, a transitive dependency of `exporter-otlp`) conflicts with the `v5.x` line pulled in by `kreait/laravel-firebase` → `google/gax`. | Resolved via `composer require --with-all-dependencies`, which downgraded `google/protobuf` to `v4.33.6` — satisfies both `google/gax`'s `^3.0\|^4.0` constraint and `gen-otlp-protobuf`'s `^3.3\|^4.0` constraint. No functional impact on Firebase Admin usage (protobuf v4 is backward compatible for the message types Firebase uses). |
| No official Redis auto-instrumentation package exists. | Documented gap (§9); Redis calls are currently untraced. Revisit in a future phase once an official package ships, or add manual spans through the `Tracer` contract without touching this decision. |
| The SDK's zero-code bootstrap (`SdkAutoloader`) runs at Composer class-autoload time, **before** Laravel loads `.env` — `OTEL_*` variables must be real process environment variables, not `.env`-only, for auto-instrumentation/export to activate. | Documented prominently in `.env.example` and §5 below; this is an upstream OpenTelemetry PHP characteristic, not specific to this implementation. `config('telemetry.*')` still reads `.env` normally for the app's own kill switch and diagnostics. |

### 2.4 Compatibility

- PHP 8.3+ (project requirement) — all chosen packages require PHP `^8.1` or newer.
- Laravel 13 — `opentelemetry-auto-laravel` hooks `Illuminate\Contracts\Http\Kernel`, `Illuminate\Contracts\Console\Kernel`, `Illuminate\Console\Command`, `Illuminate\Contracts\Queue\Queue`, `Illuminate\Queue\Worker`, `Illuminate\Queue\SyncQueue`, `Illuminate\Database\Eloquent\Model`, and `Illuminate\Foundation\Application` — all present, unmodified, in this codebase.
- Monolog 3.10 (bundled with Laravel 13) — `TraceCorrelationLogTap` (§6) uses the Monolog 3 `LogRecord` value object API.

---

## 3. Telemetry Abstraction Layer

```
app/Telemetry/
├── Contracts/                         Vendor-neutral interfaces — the ONLY thing domain code may depend on
│   ├── Tracer.php
│   ├── Meter.php
│   ├── Span.php
│   ├── Counter.php / Histogram.php / UpDownCounter.php
│   ├── LoggerCorrelation.php
│   └── TelemetryManager.php
│
├── Context/
│   └── TraceContext.php               Immutable trace_id/span_id value object (never an SDK SpanContext)
│
├── Configuration/
│   └── TelemetryConfig.php            Typed projection of config('telemetry') — no SDK imports
│
├── Resources/
│   └── ResourceAttributes.php         Vendor-neutral resource-attribute value object — no SDK imports
│
├── Logging/
│   └── TraceCorrelationLogTap.php     Monolog processor wiring — depends only on the LoggerCorrelation contract
│
├── OpenTelemetry/                     The ONLY namespace allowed to import OpenTelemetry SDK/API classes
│   ├── OpenTelemetryManager.php
│   ├── OpenTelemetryTracer.php / OpenTelemetrySpan.php
│   ├── OpenTelemetryMeter.php / OpenTelemetryCounter.php / OpenTelemetryHistogram.php / OpenTelemetryUpDownCounter.php
│   └── OpenTelemetryLoggerCorrelation.php
│
├── Noop/                              Zero-dependency fallback — implements every contract, imports nothing telemetry-related
│   ├── NoopTelemetryManager.php
│   ├── NoopTracer.php / NoopSpan.php
│   ├── NoopMeter.php / NoopCounter.php / NoopHistogram.php / NoopUpDownCounter.php
│   └── NoopLoggerCorrelation.php
│
└── Providers/
    └── TelemetryServiceProvider.php   Single wiring point — the only class allowed to reference OpenTelemetryManager directly
```

This matches the structure requested for Phase 7A exactly, plus two additions kept inside the same dependency boundaries:

- **`Noop/`** — required by "Future Compatibility" (a No-op implementation must exist with zero domain changes); it is the safe fallback `TelemetryServiceProvider` binds when telemetry is disabled or bootstrap fails.
- **`Logging/`** — the Monolog processor that performs log correlation (§6); it depends only on the `LoggerCorrelation` contract, never on the SDK.

### 3.1 Dependency Rule enforcement

```
Domain  ──▶  Telemetry Contracts  ──▶  OpenTelemetry Implementation  ──▶  OpenTelemetry SDK
                    ▲
                    └──▶  Noop Implementation   (same contracts, zero SDK dependency)
```

Enforced two ways:

1. **Structurally** — every class outside `app/Telemetry/OpenTelemetry/` that needs telemetry depends on an interface in `app/Telemetry/Contracts/`, resolved from the Laravel container. Nothing in `app/Http`, `app/Jobs`, `app/Console`, `app/Providers` (existing ones), `app/SmartHome`, `app/PushNotifications`, `app/Scheduling`, etc. references `App\Telemetry\OpenTelemetry\*` or any `OpenTelemetry\*` SDK class.
2. **Automated test** — `tests/Unit/Telemetry/DependencyRuleTest.php` scans every `.php` file under `app/` (except `app/Telemetry/OpenTelemetry/`) for a `use OpenTelemetry\...;` import and fails the build if one is found. It also asserts `app/Telemetry/Contracts` and `app/Telemetry/Noop` never import the SDK or `App\Telemetry\OpenTelemetry`, and that `app/Telemetry/OpenTelemetry` classes only import Telemetry-module or SDK types (never a domain contract). This test is part of the standard `composer test` run and therefore part of CI going forward.

### 3.2 Dependency injection

`TelemetryServiceProvider::register()` is the **only** place that decides which concrete class backs `TelemetryManager`:

```php
$this->app->singleton(TelemetryManager::class, function (Application $app) {
    if (! $app['config']->get('telemetry.enabled', true)) {
        return new NoopTelemetryManager();
    }

    try {
        return new OpenTelemetryManager(enabled: true);
    } catch (Throwable) {
        return new NoopTelemetryManager(); // never let bootstrap failure take the app down
    }
});

$this->app->bind(Tracer::class, fn ($app) => $app->make(TelemetryManager::class)->tracer());
$this->app->bind(Meter::class, fn ($app) => $app->make(TelemetryManager::class)->meter());
$this->app->bind(LoggerCorrelation::class, fn ($app) => $app->make(TelemetryManager::class)->loggerCorrelation());
```

Any future consumer type-hints `Tracer`, `Meter`, `LoggerCorrelation`, or `TelemetryManager` in a constructor and lets the container inject it — exactly like every other contract in this codebase (compare `App\PushNotifications\Contracts\PushProvider` + `PushProviderResolver`). Swapping the OpenTelemetry SDK for a Testing/Benchmark/alternative-vendor implementation in Phase 8+ requires editing **only** this one `register()` method.

---

## 4. SDK bootstrap

This is the part of the design that most benefits from favoring the *official* mechanism over a custom one, so it is documented in detail.

### 4.1 Two independent bootstrap paths, by design

| Concern | Owned by | Trigger |
| --- | --- | --- |
| Building the real `TracerProvider` / `MeterProvider` / `Resource` / `Sampler` / OTLP exporter from `OTEL_*` env vars, and registering them as SDK globals | **`\OpenTelemetry\SDK\SdkAutoloader`** (vendor code, `open-telemetry/sdk`) | `OTEL_PHP_AUTOLOAD_ENABLED=true` as a **real process environment variable** |
| Activating each auto-instrumentation package's hooks (`opentelemetry-auto-laravel`, `-guzzle`, `-pdo`) | Each package's own `_register.php` | `ext-opentelemetry` PECL extension loaded (independent of the flag above) |
| Deciding whether `App\Telemetry\Contracts\TelemetryManager` resolves to the OpenTelemetry implementation or the No-op implementation | **`TelemetryServiceProvider`** (this module) | `config('telemetry.enabled')` ← `OTEL_SDK_DISABLED` |
| Reading whatever `TracerProvider`/`MeterProvider` the SDK ended up with (real or its own built-in Noop) | **`OpenTelemetryManager`** (this module) | Always — via `OpenTelemetry\API\Globals::tracerProvider()` / `::meterProvider()` |

`OpenTelemetryManager` **does not build or register a `TracerProvider`/`MeterProvider` itself.** An earlier iteration of this module did (via `Globals::registerInitializer()` called from the service provider), but that runs at Laravel's service-provider-boot time — which is *after* `opentelemetry-auto-laravel`'s `Illuminate\Contracts\Http\Kernel::handle()` pre-hook can already have read `Globals::tracerProvider()` for the very first request. Registering later than that either has no effect (the SDK memoizes `Globals` on first read) or, worse, races the auto-instrumentation hooks depending on request timing. `SdkAutoloader::autoload()` avoids this entirely because it runs at Composer `files`-autoload time — strictly before Laravel, and therefore strictly before any hook — which is exactly why OpenTelemetry ships it as the documented zero-code bootstrap mechanism. `OpenTelemetryManager` and every auto-instrumentation hook now read the *same* globals, populated *once*, in the *right* order.

### 4.2 What `SdkAutoloader::environmentBasedInitializer()` builds (vendor code, referenced not reimplemented)

From `vendor/open-telemetry/sdk/SdkAutoloader.php`, using the exact `OTEL_*` variables listed in §5:

1. `ResourceInfoFactory::defaultResource()` — resource attributes from `OTEL_SERVICE_NAME`, `OTEL_SERVICE_VERSION` (via `OTEL_RESOURCE_ATTRIBUTES`), plus SDK/process/host detectors.
2. `(new ExporterFactory())->create()` — reads `OTEL_TRACES_EXPORTER` (`otlp` in this project) and builds the OTLP/HTTP exporter from `OTEL_EXPORTER_OTLP_ENDPOINT` / `_PROTOCOL` / `_HEADERS`.
3. `(new SamplerFactory())->create()` — reads `OTEL_TRACES_SAMPLER` / `OTEL_TRACES_SAMPLER_ARG`.
4. `(new SpanProcessorFactory())->create($exporter, ...)` — a `BatchSpanProcessor` by default (bounded queue, async export, non-blocking — see §7).
5. Registers everything via `Globals::registerInitializer()` and registers `ShutdownHandler::register($tracerProvider->shutdown(...))` — an automatic best-effort flush on PHP process shutdown, with **no code from this module involved**.

### 4.3 Empirical verification

Bootstrapped manually with `OTEL_PHP_AUTOLOAD_ENABLED=true`, `OTEL_TRACES_SAMPLER=always_on`, `OTEL_TRACES_EXPORTER=otlp`, `OTEL_EXPORTER_OTLP_ENDPOINT=http://127.0.0.1:4318` (a closed port — no Collector running) as real shell-exported variables:

```
$ php artisan tinker --execute="..."
App\Telemetry\OpenTelemetry\OpenTelemetryTracer
[log] telemetry correlation smoke test WITH REAL active span  {"trace_id":"6b329f0c83b65d900061ce6aca8023ed","span_id":"ea285f9d44e30158"}
```

- `Globals::tracerProvider()` resolved to a real `OpenTelemetry\SDK\Trace\TracerProvider` (not the SDK's built-in Noop).
- A real, valid `trace_id`/`span_id` pair was generated and — via `TraceCorrelationLogTap` (§6) — appeared in the log line's `extra` bag, with the original message untouched.
- See §7 for what happened when that span tried to export to the (deliberately unreachable) endpoint.

---

## 5. Configuration

Every value is environment-driven; nothing is hardcoded. `config/telemetry.php` is the Laravel-native, `config()`-accessible projection of the same variables the SDK reads directly (see §4.1 for why there are two readers of the same source of truth).

| Variable | Purpose | Default |
| --- | --- | --- |
| `OTEL_SDK_DISABLED` | Master kill switch — `true` forces `NoopTelemetryManager` | `false` |
| `OTEL_SERVICE_NAME` | `service.name` — must be `back_vibes-api` or `back_vibes-worker` (telemetry-naming-convention.md §3) | `back_vibes-api` |
| `OTEL_SERVICE_VERSION` | `service.version` | `${APP_VERSION}` → `unknown` |
| `APP_VERSION` | Release tag, set at deploy time | *(unset locally)* |
| `OTEL_SERVICE_NAMESPACE` | `service.namespace` | `ixora` |
| `APP_ENV` | Mapped to `deployment.environment` (`production`/`staging`/anything else → `development`) | `local` → `development` |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | Collector OTLP/HTTP endpoint — Collector only, never Prometheus/Loki/Tempo directly (ADR-028) | *(empty)* |
| `OTEL_EXPORTER_OTLP_PROTOCOL` | `http/protobuf` (default) or `http/json` — gRPC intentionally not used (§9) | `http/protobuf` |
| `OTEL_EXPORTER_OTLP_HEADERS` | `Authorization=Bearer <OTEL_INGEST_API_KEY_BACKEND>` for the Collector's `bearertokenauth/backend` extension | *(empty)* |
| `OTEL_RESOURCE_ATTRIBUTES` | Extra `key=value,key=value` resource attributes | *(empty)* |
| `OTEL_TRACES_SAMPLER` / `OTEL_TRACES_SAMPLER_ARG` | Head sampling, mirrors the Collector's `probabilistic_sampler` | `parentbased_traceidratio` / `0.10` |
| `OTEL_PHP_AUTOLOAD_ENABLED` | Enables the zero-code `SdkAutoloader` bootstrap (§4) — **must be a real process env var** | `false` |
| `OTEL_TRACES_EXPORTER` / `OTEL_METRICS_EXPORTER` | Which exporter `SdkAutoloader` builds (`otlp` or `none`) | `otlp` |
| `OTEL_PHP_DISABLED_INSTRUMENTATIONS` | Set to `all` wherever `ext-opentelemetry` is absent, to silence the startup warning and skip hook registration | *(empty)* |
| `OTEL_PROPAGATORS` | Context propagation format | `tracecontext,baggage` |

Full annotated template: [`.env.example`](../../../../back_vibes/.env.example) (back_vibes repo) §"Observability — OpenTelemetry". Laravel-side projection: [`config/telemetry.php`](../../../../back_vibes/config/telemetry.php).

---

## 6. Resource attributes

`App\Telemetry\Resources\ResourceAttributes` (a plain value object, zero SDK imports) documents and is asserted in tests against the exact attribute set `ResourceInfoFactory::defaultResource()` builds at SDK bootstrap time:

| Attribute | Source |
| --- | --- |
| `service.name` | `OTEL_SERVICE_NAME` |
| `service.version` | `OTEL_SERVICE_VERSION` (falls back to `APP_VERSION`) |
| `service.namespace` | `OTEL_SERVICE_NAMESPACE` |
| `deployment.environment` | Mapped from `APP_ENV` — restricted to `development`/`staging`/`production` (telemetry-naming-convention.md §4) |
| `telemetry.sdk.language` | Set automatically by the SDK to `php` |
| `telemetry.sdk.name` | Set automatically by the SDK to `opentelemetry` |
| `telemetry.sdk.version` | Set automatically by the SDK to the installed `open-telemetry/sdk` version |

The last three are populated by the SDK's own `Detectors\Sdk` resource detector — Phase 7A does not, and must not, set them manually (doing so would risk drifting from the actual installed SDK version).

---

## 7. Auto instrumentation

| Signal | Package | Hooked classes |
| --- | --- | --- |
| HTTP requests / Laravel routing | `opentelemetry-auto-laravel` | `Illuminate\Contracts\Http\Kernel`, `Illuminate\Foundation\Application` |
| Console commands | `opentelemetry-auto-laravel` | `Illuminate\Contracts\Console\Kernel`, `Illuminate\Console\Command`, `Illuminate\Foundation\Console\ServeCommand` |
| Queue workers | `opentelemetry-auto-laravel` | `Illuminate\Contracts\Queue\Queue`, `Illuminate\Queue\Queue`, `Illuminate\Queue\SyncQueue`, `Illuminate\Queue\Worker` |
| Database (Eloquent) | `opentelemetry-auto-laravel` | `Illuminate\Database\Eloquent\Model` |
| Database (raw PDO) | `opentelemetry-auto-pdo` | `PDO`, `PDOStatement` |
| HTTP client | `opentelemetry-auto-guzzle` | Guzzle handler stack (backs Laravel's `Http::` facade) |
| Exceptions | `opentelemetry-auto-laravel` | Recorded on the active span by the HTTP/Console Kernel hooks when a request/command fails |
| Redis | — | **Not enabled** — see §9 |

No manual spans, no custom metrics, and no domain instrumentation were added anywhere in this phase. Every span above is created entirely by vendor `hook()` calls against framework classes — `App\Telemetry\Contracts\Tracer::startSpan()` is not called by any Ixora code yet (Phase 7B is the first permitted caller).

Auto-instrumentation only activates when the `opentelemetry` PECL extension is loaded (§2.3, §8.4); in its absence the packages register nothing and the application behaves exactly as before Phase 7A — no auto spans, no auto exceptions-on-spans, but the Telemetry Abstraction Layer, contracts, and log correlation plumbing all still resolve correctly (validated by the test suite, §10).

---

## 8. Logging correlation

### 8.1 Mechanism

`App\Telemetry\Logging\TraceCorrelationLogTap` is a Laravel log "tap" (the same mechanism Laravel exposes via `'tap' => [...]` in `config/logging.php`) that pushes a Monolog processor onto a channel's underlying logger:

```php
$monolog->pushProcessor(static function (LogRecord $record): LogRecord {
    $correlation = app(LoggerCorrelation::class)->current(); // ['trace_id' => ..., 'span_id' => ...] or []
    $record->extra = array_merge($record->extra, $correlation);
    return $record;
});
```

`TelemetryServiceProvider::boot()` adds this tap to **every** configured channel (`config('logging.channels.*.tap')`) programmatically — `config/logging.php` itself is never edited. Because it is a Monolog *processor*, it runs once per log call, at the moment the record is built, and reads whichever span is active *at that instant* — not a static value set once per request.

### 8.2 What changes in a log line

- **Message:** never modified — `TraceCorrelationLogTap` never touches `$record->message` or `$record->context`.
- **`extra` bag:** gains `trace_id` and `span_id` keys **only when a span is active**; otherwise untouched (`[]`), exactly matching logs-philosophy.md §6 ("`trace_id` — When span active", "`span_id` — When span active").

Verified end-to-end (§4.3): the same log call produced `{"trace_id":"...","span_id":"..."}` in `extra` with a live SDK span, and `{}` with no active span (default in this environment) — the original message string was byte-for-byte identical in both cases.

### 8.3 Failure isolation

`LoggerCorrelation::current()` is called inside a `try`/`catch` inside the processor itself — if resolving the correlation contract throws for any reason, the processor returns the record unchanged. Logging can never fail because of telemetry (telemetry-availability-policy.md).

### 8.4 Production dependency

Auto-instrumentation and full log correlation coverage both benefit from the `opentelemetry` PECL extension being present in the runtime image; the production Docker image is expected to install it (e.g. via `pecl install opentelemetry` or `install-php-extensions opentelemetry`) as part of the App Platform / Docker build — this is an infrastructure change outside `back_vibes` application code and outside Phase 7A's boundary, tracked as **remaining work for Phase 7B/deploy**.

---

## 9. Limitations

- **No Redis auto-instrumentation.** No package under the official `open-telemetry` GitHub org instruments PHP-Redis/Predis; the only existing package (`mismatch/opentelemetry-auto-redis`) is independently maintained with unclear long-term support, so it was excluded per the SDK-evaluation mandate to avoid uncertain-maintenance community packages. Redis operations are currently untraced. Revisit once an official package exists, or add manual Redis spans through the `Tracer` contract in a later phase without any change to this module's public surface.
- **gRPC OTLP not used.** `OTEL_EXPORTER_OTLP_PROTOCOL` defaults to `http/protobuf` (matching the Collector's `:4318` HTTP receiver) to avoid requiring the `ext-grpc` PHP extension in addition to `ext-opentelemetry`. The Collector also exposes gRPC on `:4317` if a future phase needs it.
- **`.env`-only local setups will not see zero-code auto-instrumentation or SDK export.** `OTEL_PHP_AUTOLOAD_ENABLED` and the other `OTEL_*` bootstrap variables must be real process/OS environment variables (§4.1) — a plain `.env` file loaded by Laravel is not enough, because the SDK's autoloader runs before Laravel's `Dotenv` does. This is an upstream OpenTelemetry PHP characteristic (documented at <https://opentelemetry.io/docs/zero-code/php>), not specific to this implementation. `config('telemetry.*')` (and therefore the app's own enable/disable decision, tests, and diagnostics) is unaffected — it reads `.env` normally through Laravel's config system.
- **No manual spans, no custom metrics, no custom logs.** By design — Phase 7A is infrastructure only. `Tracer::startSpan()`, `Meter::counter()/histogram()/upDownCounter()`, and any domain-specific log field beyond `trace_id`/`span_id` are Phase 7B+ work.
- **Exceptions are only recorded where the auto-instrumentation hooks already run** (HTTP/console kernels) — a caught-and-swallowed exception deep in domain code that never reaches those kernels will not appear on a span until Phase 7B adds manual instrumentation.

## 10. Future manual instrumentation (Phase 7B+)

Every future addition — Scheduler dispatch spans, Smart Home provider call spans, Push delivery spans, `ixora.*` metrics, structured domain logs — is expected to:

1. Type-hint `Tracer`, `Meter`, and/or `LoggerCorrelation` from `App\Telemetry\Contracts` (never anything from `App\Telemetry\OpenTelemetry` or `OpenTelemetry\*`).
2. Follow [metrics-philosophy.md](../../../architecture/metrics-philosophy.md), [logs-philosophy.md](../../../architecture/logs-philosophy.md), [traces-philosophy.md](../../../architecture/traces-philosophy.md), and [telemetry-naming-convention.md](../../../architecture/telemetry-naming-convention.md) for signal choice, naming, and attribute design.
3. Require **zero changes** to `app/Telemetry/Contracts/*`, `TelemetryServiceProvider`, or any existing call site — the abstraction layer is already stable for this.

---

## 11. Testing

See §"Tests added" in the Phase 7A final report for the full list. Summary:

| Test file | Validates |
| --- | --- |
| `tests/Unit/Telemetry/DependencyRuleTest.php` | No `OpenTelemetry\*` import outside `app/Telemetry/OpenTelemetry`; Contracts/Noop stay SDK-free; OpenTelemetry implementation imports nothing but SDK + Telemetry-module types |
| `tests/Feature/Telemetry/TelemetryBootstrapTest.php` | Provider registers; `Globals` accessors never throw; `flush()` never throws; app boots with telemetry enabled or disabled |
| `tests/Feature/Telemetry/TelemetryConfigurationTest.php` | `config('telemetry')` loads; `TelemetryConfig::fromArray()` maps every key; `deployment.environment` restricted to the three allowed values; resource attributes present and free of forbidden fields (ADR-030); `service_name` matches the naming convention |
| `tests/Feature/Telemetry/TelemetryContractResolutionTest.php` | `TelemetryManager`/`Tracer`/`Meter`/`LoggerCorrelation` resolve to the OpenTelemetry implementation by default and to the No-op implementation when disabled; singleton behavior; span lifecycle never throws |
| `tests/Feature/Telemetry/TelemetryLoggingCorrelationTest.php` | Every channel receives the tap; `trace_id`/`span_id` land in `extra` when a span is active, message untouched; nothing added when no span is active; a broken `LoggerCorrelation` fails open |
| `tests/Feature/Telemetry/TelemetryFailurePolicyTest.php` | An HTTP request succeeds with an unreachable OTLP endpoint configured; `flush()` returns quickly and never throws; a "job" completes normally with telemetry disabled mid-flight |

Run with: `OTEL_PHP_DISABLED_INSTRUMENTATIONS=all php artisan test tests/Unit/Telemetry tests/Feature/Telemetry` (the env var avoids the `ext-opentelemetry`-absent startup warning described in §2.3/§8.4 in environments without the PECL extension; it has no effect on the Telemetry module's own tests, only on the auto-instrumentation packages).

---

## Cross-references

- [ADR-028 — Observability platform](../../../decisions/ADR-028-observability-platform.md)
- [ADR-029 — Telemetry data model](../../../decisions/ADR-029-telemetry-data-model.md)
- [ADR-030 — Observability security and privacy](../../../decisions/ADR-030-observability-security-and-privacy.md)
- [telemetry-availability-policy.md](../../../architecture/telemetry-availability-policy.md)
- [telemetry-naming-convention.md](../../../architecture/telemetry-naming-convention.md)
- [metrics-philosophy.md](../../../architecture/metrics-philosophy.md) · [logs-philosophy.md](../../../architecture/logs-philosophy.md) · [traces-philosophy.md](../../../architecture/traces-philosophy.md)
- [telemetry-decision-guide.md](../../../architecture/telemetry-decision-guide.md)
- [collector/config.yaml](../../../../collector/config.yaml) — OTLP receivers this SDK exports to
