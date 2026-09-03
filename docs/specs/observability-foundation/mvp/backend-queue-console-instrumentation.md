# Backend Queue + Console Instrumentation — Phase 7B.2 (`back_vibes`)

**Status:** Complete
**Repo:** `back_vibes` (Laravel 13, PHP 8.3+)
**Feature ID:** `observability-foundation/mvp`
**Prerequisite:** [backend-sdk-foundation.md](backend-sdk-foundation.md) (Phase 7A) · [backend-http-routing-instrumentation.md](backend-http-routing-instrumentation.md) (Phase 7B.1) · [metrics-philosophy.md](../../../architecture/metrics-philosophy.md) · [logs-philosophy.md](../../../architecture/logs-philosophy.md) · [traces-philosophy.md](../../../architecture/traces-philosophy.md) · [telemetry-naming-convention.md](../../../architecture/telemetry-naming-convention.md)

---

## 1. Scope

Phase 7B.2 instruments **only** the generic Laravel queue-execution boundary and the generic Laravel console/Artisan-command boundary of `back_vibes`. It builds exclusively on the Phase 7A Telemetry Contracts and the Phase 7B.1 `Tracer::activeSpan()` addition — **no contract was modified in this phase**.

| In scope | Out of scope (later 7B subphases) |
| --- | --- |
| Generic queue job lifecycle (`JobProcessing`/`JobProcessed`/`JobFailed`/`JobReleasedAfterException`/`JobExceptionOccurred`/`JobTimedOut`) | Scheduler dispatch logic (Phase 7B.3) |
| Generic Artisan/console command lifecycle (`CommandStarting`/`CommandFinished`) | Smart Home provider calls (Phase 7B.4) |
| `ixora.queue.job.*` / `ixora.console.command.*` metrics | Push delivery (Phase 7B.5) |
| Queue/command name + outcome normalization | External providers (Phase 7B.6) |
| Safe queue/console context on existing exception logs | |

No job business logic, command business logic, Scheduler logic, Smart Home logic, Push logic, provider adapter, controller, route, model, database schema, API response, or auth behavior was modified. `git diff --stat` for `back_vibes` in this phase touches only `app/Telemetry/Queue/**`, `app/Telemetry/Console/**`, `app/Telemetry/Logging/{Queue,Console}ErrorContextLogTap.php`, `app/Telemetry/Providers/TelemetryServiceProvider.php`, `tests/Support/Telemetry/{RecordingUpDownCounter.php,TelemetryRecorder.php,RecordingMeter.php}`, and `tests/**`.

---

## 2. Queue auto-instrumentation review (Part 1)

Reviewed `open-telemetry/opentelemetry-auto-laravel`'s `Hooks\Illuminate\Queue\{Queue,SyncQueue,Worker}` and `Hooks\Illuminate\Contracts\Queue\Queue`.

| Question | Finding |
| --- | --- |
| Producer span on `dispatch()` | **No span for a normal, immediate `dispatch()`.** Only three producer-side methods are hooked at the `Illuminate\Contracts\Queue\Queue` level: `bulk()`, `later()` (delayed dispatch), and `pushRaw()`. The method every ordinary `Job::dispatch()` call actually reaches — `push()` — is **not hooked** at the contract/driver level for async connections (database, redis, sqs, beanstalk). |
| Producer span for sync queue | `Hooks\Illuminate\Queue\SyncQueue`'s `push()` hook creates an **`INTERNAL`**-kind span named `"{connection} process"` around the entire synchronous execution (dispatch through to job completion) — this is effectively the only span sync dispatch gets; `bulk`/`later`/`pushRaw` are not part of `SyncQueue`'s normal `dispatch()` path either. |
| Consumer/job execution span | Yes — `Hooks\Illuminate\Queue\Worker`'s `process()` hook wraps every worker-processed job attempt in a **`CONSUMER`**-kind span named `"process {destination}"`. A second, separate `CONSUMER` span (`"receive {destination}"`) wraps `getNextJob()` (queue polling) — discarded via `$scope->detach()` with no attributes when the poll returns no job. |
| Span naming | `process()` hook: `"{messaging.operation.type} {messaging.destination.name}"`, e.g. `"process default"`. `messaging.destination.name` defaults to the literal string `"(anonymous)"` unless the underlying driver is Beanstalkd, Redis, or SQS (see next row). |
| Queue name attribute | `messaging.destination.name` is only set to the real queue name for `BeanstalkdQueue`, `RedisQueue`, and `SqsQueue` drivers (`AttributesBuilder::contextualMessageSystemAttributes()` matches on driver class). **`back_vibes`'s configured driver is `database`** (`config/queue.php`, confirmed in `phpunit.xml` test override to `sync`) — neither `database` nor `sync` is one of those three, so in this application's actual runtime, `messaging.destination.name` on the consumer span is always the unconfigured default `"(anonymous)"`, and `messaging.system` is never set at all. |
| Job class attribute | `messaging.message.job_name`, read from the decoded JSON payload's `displayName` or `job` key — the fully-qualified class name (or `Illuminate\Queue\CallQueuedHandler@call` wrapper string for queued closures/listeners), not a bounded/normalized value. |
| Retry/attempt attribute | `messaging.message.attempts`, read from the payload's `attempts` key (present only after at least one prior attempt; `0`/absent on first attempt). |
| Exception recording | `PostHookTrait::endSpan($exception)` calls `Span::recordException()` + `setStatus(ERROR, $exception->getMessage())` whenever the hooked method's post-hook receives a non-null `$exception`. Traced `Illuminate\Queue\Worker::process()` → `handleJobException()`, confirmed it always ends with `throw $e;` after firing `JobExceptionOccurred`/`JobReleasedAfterException` — so the exception **does** propagate out of `process()` and **is** recorded onto the consumer span for every failing attempt, sync or async. |
| Context propagation, dispatch → worker | Yes, already implemented. `Hooks\Illuminate\Queue\Queue`'s `createPayloadArray()` post-hook calls `TraceContextPropagator::inject($payload)`, adding a W3C `traceparent` (and `tracestate`) key to every job payload at creation time — covering `push`, `bulk`, `later`, `pushRaw` uniformly (they all funnel through `createPayloadArray()`). `Worker::process()`'s pre-hook extracts it back via `TraceContextPropagator::extract($job->payload())` and sets it as the consumer span's parent (`setParentContext()`), unless the job class implements one of the library's own `TracingIsolated`/`TracingLinked` marker interfaces (unused anywhere in `back_vibes`). |
| Sync queue behavior | `SyncQueue::push()`'s `INTERNAL` span (previous rows) is entirely separate from `Worker::process()` — sync jobs never go through `Worker`, so they get exactly one auto-instrumented span, not two. `JobProcessing`/`JobProcessed`/`JobExceptionOccurred` events still fire for sync jobs (`Illuminate\Queue\SyncQueue::push()`/`executeJob()`), confirmed by reading `vendor/laravel/framework/src/Illuminate/Queue/SyncQueue.php`. |
| Failed jobs | `SyncQueue::handleException()` always calls `$job->fail($e)` then rethrows — sync has no release/retry concept. For async drivers, `Worker::handleJobException()` marks the job failed (`markJobAsFailedIf...()`) only once specific thresholds are hit (max tries/exceptions/`shouldRetry()`); otherwise it releases the job back onto the queue in the same `finally` block, then unconditionally rethrows. Either way, `JobFailed` or `JobReleasedAfterException` fires, and the consumer span (async) or `push()` span (sync) records the exception (previous row). |
| Released jobs | `Worker::process()`'s post-hook additionally sets `messaging.message.released` (from `$job->isReleased()`) and `messaging.message.deleted` (from `$job->isDeleted()`) on the consumer span — release is visible on the span even without a dedicated release-outcome span attribute. |
| Timeouts | `JobTimedOut` is dispatched from a `pcntl` `SIGALRM` handler (`Worker::registerTimeoutHandler()`) that calls `exit()` immediately afterward — the worker process terminates before `Worker::process()`'s post-hook can run, so **the consumer span for a timed-out job is never ended by the auto-instrumentation** (it is simply abandoned in-process; the OTel SDK's own shutdown/export path, not this hook, is what would flush anything already buffered). |
| Jobs without a queue name | `Job::getQueue()` returns `null` for a job dispatched without an explicit `->onQueue(...)` call on some driver combinations; `back_vibes`'s own `QueueContext`/`QueueJobNormalizer` (§4) always fall back to the bounded literal `default` — the auto-instrumentation itself does not special-case this beyond the already-covered `messaging.destination.name` behavior above. |

**Conclusion — the existing auto-instrumentation already provides a per-attempt consumer span (async) or per-dispatch internal span (sync), context propagation, and exception recording, but zero metrics, an unnormalized/unbounded job-name attribute, a driver-dependent (frequently absent) queue-name attribute, and no stable outcome classification (success/failed/released/retried/timed_out).** Phase 7B.2 therefore **enriches the existing span** with normalized, bounded `ixora.queue.*` attributes (§6) rather than starting a second span around every job, and adds exactly the two required metrics (§5) plus the optional active-jobs gauge.

---

## 3. Console auto-instrumentation review (Part 1)

Reviewed `Hooks\Illuminate\Console\Command` and `Hooks\Illuminate\Contracts\Console\Kernel`.

| Question | Finding |
| --- | --- |
| Root command span | **Two distinct, independently-gated spans exist**, not one: (1) `Illuminate\Console\Command::execute()`'s hook creates a span named `"Command {name}"` for **every** command run through Symfony's `Command::run()` — unconditional, no CLI-SAPI gating. (2) `Illuminate\Contracts\Console\Kernel::handle()`'s hook creates a coarser `PRODUCER`-kind span named `"Artisan handler"` — but only `if (LaravelInstrumentation::shouldTraceCli())`, which returns `PHP_SAPI !== 'cli' || OTEL_PHP_TRACE_CLI_ENABLED`. `back_vibes` sets neither this env var nor Octane; every real `php artisan …` invocation runs under the `cli` SAPI, so **the "Artisan handler" span is never created in this application's actual runtime** — only the per-command span from (1) exists in practice. |
| Command name attribute | `Command::execute()`'s span name itself is `"Command {$command->getName()}"` (bounded fallback `'unknown'` if `getName()` returns falsy) — no separate `command.name` attribute; the name lives in the span name string. |
| Exit-code attribute | Not a span *attribute* — `Command::execute()`'s post-hook adds a span **event** named `command finished` with an `exit-code` event attribute. `Kernel::handle()`'s post-hook (when it runs at all, see above) instead sets `$span->setStatus(StatusCode::STATUS_ERROR)` whenever `$exitCode !== Command::SUCCESS`. |
| Exception recording | Same `PostHookTrait::endSpan($exception)` pattern as queue (§2) — recorded on whichever of the two spans actually receives a non-null `$exception` from its hooked method's return. |
| Scheduled command behavior | `artisan schedule:run` invokes each due command via `Illuminate\Console\Scheduling\Event::run()`, which for an in-process (non-`runInBackground`) command ultimately calls `Artisan::call()` → `Illuminate\Console\Application::call()` → `$command->run()` — the same `Command::execute()` hook fires for the scheduled command exactly as it would for a direct CLI invocation, nested one level inside `schedule:run`'s own `Command::execute()` span. This phase does not instrument Scheduler domain logic itself (out of scope, Phase 7B.3), but the generic console listener (§4) still observes both the outer `schedule:run` command and, for an in-process scheduled command, the inner one — each as its own `CommandStarting`/`CommandFinished` pair (see §7). |
| Nested command behavior (`$this->call()`) | **No second span, and no second `CommandStarting`/`CommandFinished` pair.** `Illuminate\Console\Concerns\CallsCommands::runCommand()` calls `$command->run()` directly — it never goes through `Illuminate\Console\Application::call()`/Symfony's own `ConsoleEvents::COMMAND`/`TERMINATE` dispatch, and `Command::execute()`'s hook is not re-entered because `run()` bypasses `execute()`'s own dispatch path for this call style. (Verified against `vendor/laravel/framework/src/Illuminate/Console/Concerns/CallsCommands.php`.) |
| `artisan schedule:run` specifically | Gets its own `"Command schedule:run"` span like any other command; nothing scheduler-specific is added by the official instrumentation. |
| Closure commands | `Illuminate\Foundation\Console\ClosureCommand` still extends `Illuminate\Console\Command` and is still invoked through `execute()`, so the hook fires identically; `getName()` reflects whatever name the closure command was registered under (or `NULL`→ the `'unknown'` fallback if registered anonymously). |
| Invalid command names | Symfony's `Application::find()` throws `CommandNotFoundException` **before** any `Command` instance's `execute()` is ever called — no span, no `CommandStarting`/`CommandFinished` event, for either the official instrumentation or this phase's own listener. This is an unavoidable, correctly-bounded gap (there is nothing to instrument — the command object never existed). |

**Verified, empirically confirmed limitation used to design §4/§7:** `CommandStarting`/`CommandFinished` are wired by `Illuminate\Foundation\Console\Kernel::rerouteSymfonyCommandEvents()`, itself gated by `! $this->app->runningUnitTests()`. `back_vibes`'s test suite runs with `APP_ENV=testing`, so **these two events never fire through a real command execution inside this repository's own automated tests** — confirmed by instrumenting a real `$this->artisan(...)` call in a scratch test and observing zero listener invocations. This is why Phase 7B.2's console tests dispatch these events directly (§10) rather than through `$this->artisan()`.

**Conclusion — the per-command span already exists and is unconditional; the coarser producer span effectively does not exist for this application's real deployment shape.** Phase 7B.2 therefore records the two `ixora.console.*` metrics (§5) unconditionally from `CommandStarting`/`CommandFinished`, and best-effort-enriches whatever span `Tracer::activeSpan()` finds active at `CommandFinished` time (§6) — which, given the above, is the per-command span at the exact instant it ends in production, and the framework's own top-level ambient context (usually none/no-op) in this test suite, since these events do not fire in tests at all.

---

## 4. Queue + Console telemetry components (Parts 2–3)

`app/Telemetry/Queue/`:

| Class | Responsibility |
| --- | --- |
| `QueueOutcome` (enum) | Bounded set: `success`, `failed`, `released`, `retried`, `timed_out`, `cancelled` (reserved, unused — no Laravel queue event maps to a genuine "cancelled" state today), `unknown` (reserved, unused — every code path that reaches `QueueExecutionTelemetry::recordTerminal()` always has a concrete outcome already). |
| `QueueJobNormalizer` | `Job::resolveQueuedJobClass()` (the same idiomatic accessor the official `Worker` hook's `resolveName()` sibling uses) → `class_basename()`. Falls back to the bounded constant `unknown` on any failure or empty result — never a serialized payload, UUID, or job ID. |
| `QueueContext` | Immutable value object: `connection`, `queue`, `jobName`, `attempt` — normalized values only, no payload, no domain data. |
| `QueueExecutionTelemetry` | Listens for the queue lifecycle events (§7), records both metrics (§5), enriches the active span (§6), and exposes `currentContext()`/`contextForException()` for `QueueErrorContextLogTap` (§8). |

`app/Telemetry/Console/`:

| Class | Responsibility |
| --- | --- |
| `ConsoleOutcome` (enum) | Bounded set: `success`, `failed`, `cancelled` (reserved, unused — Laravel's console lifecycle does not expose a distinct "cancelled" exit path separate from a non-zero exit code), `unknown` (reserved, unused). `fromExitCode(int): self` maps `0 → success`, anything else `→ failed`. |
| `ConsoleCommandNormalizer` | Trims the Laravel-resolved command name (`schedule:run`, `queue:work`, `migrate`, …) and falls back to the bounded constant `unknown` for an empty/unresolvable name — never the raw `argv` string. |
| `ConsoleContext` | Immutable-with-`withResult()` value object: `command`, `exitCode` (nullable until `CommandFinished`), `outcome` (nullable until `CommandFinished`) — no argument values, option values, or secrets. |
| `ConsoleCommandTelemetry` | Listens for `CommandStarting`/`CommandFinished`, records both metrics (§5), best-effort-enriches the active span (§6), and exposes `currentContext()` for `ConsoleErrorContextLogTap` (§8). |

Neither module contains Scheduler, Smart Home, Push, or provider-adapter domain knowledge, and neither imports anything under the `OpenTelemetry\` namespace or `App\Telemetry\{OpenTelemetry,Noop}\` — enforced by `tests/Unit/Telemetry/QueueConsole/QueueConsoleTelemetryDependencyRuleTest.php` in addition to the pre-existing generic `tests/Unit/Telemetry/DependencyRuleTest.php`.

No new shared "TelemetryAttributesBuilder"/"TelemetryNameNormalizer" abstraction was introduced (Part 13) — `HttpRouteNormalizer`, `QueueJobNormalizer`, and `ConsoleCommandNormalizer` each normalize a genuinely different kind of value (a URI template vs. a PHP class name vs. an Artisan command string) with no real shared logic beyond "return a bounded fallback string", which is not enough duplication to justify an extraction.

---

## 5. Metrics (Parts 4–5)

| Metric | Type | Unit | Labels | Purpose |
| --- | --- | --- | --- | --- |
| `ixora.queue.job.total` | Counter | `{job}` | `environment`, `service_name`, `queue`, `connection`, `job_name`, `outcome` | Total queue job execution attempts — answers "which job classes execute", "which queues are processing work", and (via `outcome`) "which jobs are repeatedly failing". |
| `ixora.queue.job.duration` | Histogram | `ms` | same as above | Job execution duration — answers "how long do jobs take", segmented by outcome. |
| `ixora.queue.job.active` | UpDownCounter | `{job}` | `environment`, `service_name`, `queue`, `connection`, `job_name` | Currently-executing jobs. Every increment (`JobProcessing`) has exactly one matching decrement, from whichever terminal event pops the same stack frame (§7) — verified never to drift by `tests/Feature/Telemetry/Queue/QueueExecutionTelemetryTest.php`'s "long-running worker safety" and "telemetry failure" scenarios, which assert the net sum returns to `0` after every job, including a failing one and one observed through a broken `Tracer`. |
| `ixora.console.command.total` | Counter | `{command}` | `environment`, `service_name`, `command`, `outcome` | Total Artisan command executions — answers "which commands run" and "which succeed or fail". |
| `ixora.console.command.duration` | Histogram | `ms` | same as above | Command execution duration. |

No queue-depth metric was added — Laravel exposes no generic, driver-independent source for it without querying a specific provider (database table row count, Redis `LLEN`, SQS `GetQueueAttributes`, …) or adding new runtime behavior, both explicitly out of scope for this phase (§13 of the HTTP doc's own "remaining work" already flagged this as deferred; confirmed unchanged here).

**Unit choice:** `ms`, matching `ixora.http.server.duration`'s platform-wide convention (Phase 7B.1 §6) so every `ixora.*.duration` histogram stays consistent.

**Label naming:** underscored (`job_name`, `service_name`) matching Phase 7B.1's precedent for metric labels; span attributes (§6) use the dotted `ixora.queue.*`/OTel-semconv style instead, the same intentional per-signal-type split established in Phase 7B.1.

**Forbidden labels — verified never assigned to either queue metric:** `job_id`, `uuid`, `payload`, `user_id`, `schedule_id`, `device_id`, `trace_id`, `span_id`, `exception_message`, `attempt` (per-attempt cardinality is bounded already by `job_name`/`outcome`/`queue`, so the raw retry count is deliberately excluded from labels — it is still visible in the console/queue error-log context, §8, and as a span attribute, §6, where cardinality is not a Prometheus-label concern). Verified never assigned to either console metric: full `argv`, argument values, option values, user input, secrets, environment paths, exception messages. Enforced by `QueueJobNormalizer`/`ConsoleCommandNormalizer` only ever returning a bounded class-basename/command-name string, and directly asserted by the "cardinality safety" / "arguments and options safety" scenarios in both feature test files (§10).

**No duplication with auto-instrumentation:** per §2/§3, `opentelemetry-auto-laravel` emits no queue or console *metrics* in this configuration — only spans. These four metrics are therefore net-new.

---

## 6. Span enrichment (Part 6)

Via `Tracer::activeSpan()` (Phase 7B.1's one additive contract method — unchanged, unmodified in this phase), both telemetry services add attributes to whatever span is already active at their respective terminal lifecycle event:

**Queue** (`QueueExecutionTelemetry::recordTerminal()`, called from `jobProcessed`/`jobFailed`/`jobReleasedAfterException`/`jobTimedOut`):

| Attribute | Source |
| --- | --- |
| `ixora.queue.job_name` | `QueueJobNormalizer::normalize()` |
| `ixora.queue.outcome` | `QueueOutcome::value` |
| `ixora.queue.connection` | The event's `connectionName` |
| `ixora.queue.attempt` | `Job::attempts()` (bounded fallback `0` on failure) |

`Span::setError()` is called when the outcome is `failed` or `timed_out` — no description text, matching `HttpRequestTelemetry`'s precedent for 5xx responses. `Span::recordException()` is **not** called here: per §2, the underlying exception is already recorded onto the auto-instrumented consumer/`push()` span by the official hooks' own `endSpan($exception)` once it propagates out of `Worker::process()`/`SyncQueue::push()` — duplicating it here would double-record the same exception on the same span.

For an async worker, this reaches the real per-attempt consumer span from §2, since `JobProcessing`/`JobProcessed`/`JobFailed`/etc. all fire from inside `Worker::process()`, strictly within the span's start/end window. For sync, it reaches `SyncQueue`'s `INTERNAL` "process" span for the same reason.

**Console** (`ConsoleCommandTelemetry::commandFinished()`):

| Attribute | Source |
| --- | --- |
| `ixora.console.command` | `ConsoleCommandNormalizer::normalize()` |
| `ixora.console.outcome` | `ConsoleOutcome::value` |
| `ixora.console.exit_code` | `CommandFinished::$exitCode` |

`Span::setError()` is called when the outcome is `failed`. As established in §3, `CommandFinished` fires strictly *after* `Command::execute()`'s hook has already ended and detached the per-command span — so in a real CLI process, `activeSpan()` at this point resolves to the OTel SDK's ambient "current span" fallback (effectively a non-recording/invalid span in this application's real deployment shape, since the coarser "Artisan handler" producer span is never created either, §3). This is a documented, accepted limitation (§11), not a defect: metrics (§5) and log context (§8) are entirely unaffected by it, since neither depends on span enrichment succeeding.

**Never added, either domain:** serialized payloads, raw job/command arguments, raw options, tokens, user IDs, emails, Firebase UID, job UUID, exception message text as a *label* (span status description text from the auto-instrumentation's own `endSpan()`, §2, is the one place an exception message legitimately appears — at the trace level, not as a metric label), raw queue payload, database credentials.

---

## 7. Lifecycle integration (Part 7)

### 7.1 Queue

Registered directly on the container's event dispatcher inside `TelemetryServiceProvider::registerQueueTelemetryListeners()` (same "this module owns its own wiring" pattern as Phase 7B.1's middleware registration in `bootstrap/app.php`), against the minimum event set that can express every `QueueOutcome` without double-counting a single attempt:

| Event | `QueueExecutionTelemetry` method | Effect |
| --- | --- | --- |
| `JobProcessing` | `jobProcessing()` | Pushes `{context, startedAt}` onto an in-memory stack; increments the active gauge. |
| `JobProcessed` | `jobProcessed()` | Pops the stack; records `success` (or `released` if `$job->isReleased()` is already true mid-`handle()` — a job that calls `$this->release()` itself, not via a caught exception). |
| `JobExceptionOccurred` | `jobExceptionOccurred()` | **Metrics-neutral** — only associates the exception object with the current stack frame's context in a `WeakMap`, for `QueueErrorContextLogTap` (§8). Fires for every exception, including ones later turned into a release or a retry, so it cannot be used for outcome classification by itself. |
| `JobFailed` | `jobFailed()` | Pops the stack; records `failed`. Also captures the exception→context association defensively (in case `JobExceptionOccurred` was skipped for some driver). |
| `JobReleasedAfterException` | `jobReleasedAfterException()` | Pops the stack; records `retried`. |
| `JobTimedOut` | `jobTimedOut()` | Pops the stack; records `timed_out`. Best-effort only — per §2, this event's dispatch is immediately followed by `exit()` from a signal handler, so there is no guarantee the OTel SDK's export pipeline gets a chance to flush this particular metric point before the process dies; this is a platform-level constraint, not something this listener can work around. |

**Why a stack, not a single slot:** a job's `handle()` can itself dispatch another job synchronously (the `sync` connection's queued closures/jobs execute inline, recursively, inside the outer job's own call stack). A single "current job" slot would let the inner job's `JobProcessed` overwrite/clear the outer job's still-in-flight context. The stack is pushed once per `JobProcessing` and popped by exactly one terminal event per attempt; a terminal event that finds the stack already empty (i.e. this same attempt's frame was already popped by *a different* terminal event — see the next paragraph for why that can legitimately happen) is a safe no-op, never a double record. `tests/Feature/Telemetry/Queue/QueueExecutionTelemetryTest.php`'s "a job that dispatches another job synchronously" scenario exercises exactly this nesting.

**Why both `JobFailed` and `JobProcessed` firing for the same attempt is not a bug:** for a job that calls `$this->fail($e)` from inside its own `handle()` (rather than letting an uncaught exception propagate), Laravel's `Job::fail()` marks the job failed and dispatches `JobFailed` immediately, but `handle()` then returns normally, and `Worker::process()` — unaware anything failed — still calls `raiseAfterJobEvent()`, dispatching `JobProcessed`. `JobFailed`'s listener pops the frame and records `failed`; `JobProcessed`'s listener then finds the stack already empty for that attempt and safely no-ops (the `isReleased()` check inside `jobProcessed()` is only reached if the pop actually returns a frame, which it will not).

**Long-running worker safety:** the stack only ever grows with genuine PHP call-stack nesting (§ previous paragraph) — it never accumulates across unrelated jobs over a worker's lifetime, since every push is matched by exactly one pop (or a no-op if already popped). No `Request` object, job payload, or job instance is ever retained past the terminal event that pops it. The `WeakMap<Throwable, QueueContext>` used for exception→context correlation (§8) is bounded by PHP's own garbage collector — an entry disappears automatically once the exception object it keys on is no longer referenced anywhere else, so it cannot grow unbounded even if a worker runs for days. `tests/Feature/Telemetry/Queue/QueueExecutionTelemetryTest.php`'s "long-running worker safety" scenario asserts `currentContext()` returns to `null` after every one of three consecutive jobs (including a failing one), and that the active-gauge's net sum returns to `0`.

**No queue behavior altered:** the listener never calls `$job->release()`/`fail()`/`delete()` itself, never inspects or mutates the job payload, and every method body runs inside `safely()` (a `try`/`catch` that swallows any `Throwable`) — a broken `Tracer` or `Meter::counter()`/`histogram()`/`upDownCounter()` call site cannot alter retry count, release behavior, or failed-job recording. (`Meter::counter()`/`histogram()`/`upDownCounter()` themselves run once, unguarded, in `QueueExecutionTelemetry`'s constructor — the same precedent already established by `HttpRequestTelemetry` in Phase 7B.1, on the basis that real instrument-creation is local/synchronous and not expected to fail; see Phase 7B.1 doc §5.3 and this phase's "telemetry failure" test, which exercises a broken `Tracer` instead, matching what the class's own `safely()` calls actually guard.)

`Looping` and `WorkerStopping` were reviewed but not used — neither is needed to satisfy any `QueueOutcome`, and per-job timing/counting is already fully expressed by the six events above.

### 7.2 Console

Registered the same way, against `CommandStarting`/`CommandFinished` — the two events the spec names, and (per §3) the only two Laravel dispatches for this purpose at all.

- `commandStarting()` captures a fresh `ConsoleContext` + start time, and resets a `$finishedForCurrent` guard.
- `commandFinished()` computes the outcome from `CommandFinished::$exitCode` via `ConsoleOutcome::fromExitCode()`, records both metrics, enriches whatever span is active (§6), and — guarded by `$finishedForCurrent` — never records the same command attempt twice even if `CommandFinished` were somehow dispatched more than once for it (`tests/Feature/Telemetry/Console/ConsoleCommandTelemetryTest.php`'s "a second, unrelated CommandFinished... is never recorded twice" scenario proves this directly).
- **No stack needed** (contrast with queue, §7.1): `$this->call()`/`$this->callSilent()` never dispatch `CommandStarting`/`CommandFinished` at all (§3, `CallsCommands::runCommand()` calls `$command->run()` directly, bypassing Symfony's own event dispatch) — so this listener only ever observes the single top-level command Laravel/Symfony itself is running, exactly once, no matter how many commands it calls internally.
- **Preserves output/exit behavior:** the listener never touches `$event->output` and never overrides `$event->exitCode`; `commandFinished()`'s entire body runs inside `safely()`, so a broken `Tracer`/`Meter` cannot change the command's exit code or prevent Laravel's own post-command behavior from completing (`ConsoleCommandTelemetryTest`'s "telemetry failure" scenario proves the observed `CommandFinished::$exitCode` is unaffected by a deliberately-throwing `Tracer`).
- **No recursive self-instrumentation:** this listener has no Artisan command of its own to instrument, and it never invokes `Artisan::call()`/`$this->call()` itself, so there is no risk of it re-entering its own listener.
- **Unknown command names:** `ConsoleCommandNormalizer::normalize()` bounds any empty/unresolvable name to the constant `unknown` before it ever reaches a metric label or span attribute (`ConsoleCommandTelemetryTest`'s "unknown command" scenario).

---

## 8. Context propagation (Part 8)

**Queue:** already fully implemented by the official instrumentation (§2) — W3C trace context is injected into every job payload at `createPayloadArray()` time and extracted back by `Worker::process()`'s pre-hook. Phase 7B.2 adds **no second propagation format** and **never mutates a job payload** — `QueueContext`/`QueueJobNormalizer` only ever read from the `Illuminate\Contracts\Queue\Job` object's own accessor methods (`resolveQueuedJobClass()`, `getQueue()`, `attempts()`), never from the raw payload array, and write nothing back to it.

**Console:** commands are normally root traces (no incoming trace context to propagate from — a CLI invocation has no upstream caller). Per §3/§7.2, a nested `$this->call()` never creates a second span or a second event pair in the first place, so there is no "child" execution whose parent context this phase would need to preserve manually — Laravel's own call style already keeps everything inside the single outer `Command::execute()` span's context by construction, with no OTel-specific propagation code involved at all. No custom parent-ID logic was added.

---

## 9. Structured log alignment (Part 9)

No routine success log was added for either domain — successful jobs/commands remain observable via metrics + trace alone, per logs-philosophy.md / metrics-philosophy.md.

Two new Monolog processor "taps", added to every configured log channel by `TelemetryServiceProvider` exactly the same way `TraceCorrelationLogTap` (Phase 7A) and `HttpErrorContextLogTap` (Phase 7B.1) already are:

**`App\Telemetry\Logging\QueueErrorContextLogTap`** — enriches an existing exception log record (`context.exception` is a `Throwable`) with:

```php
[
    'queue' => $context->queue,
    'connection' => $context->connection,
    'job_name' => $context->jobName,
    'attempt' => $context->attempt,
]
```

Gated by **object identity**, not "the most recently processed job": it calls `QueueExecutionTelemetry::contextForException($exception)`, which only returns non-null if *that exact exception object* was seen by `JobExceptionOccurred`/`JobFailed` (§7.1's `WeakMap`). This is deliberately stronger than an ambient "current job" read — in a long-running worker, the job that is "current" by the time a log call actually happens could easily be a different, later job than the one the exception actually belongs to; keying on the exception object itself makes that impossible.

**`App\Telemetry\Logging\ConsoleErrorContextLogTap`** — enriches the same kind of record with:

```php
[
    'command' => $context->command,
    'exit_code' => $context->exitCode,
    'outcome' => $context->outcome->value,
]
```

Gated by `ConsoleCommandTelemetry::currentContext()` being non-null. Unlike the queue tap, this is an ambient "most recently started command" read, not an exception-identity lookup — accepted because (§7.2) there is at most one top-level command per real console process, and `Illuminate\Foundation\Console\Kernel::handle()`'s own uncaught-exception log call happens strictly after `CommandFinished` (Symfony dispatches `ConsoleEvents::TERMINATE` before re-throwing to the Kernel's own catch block), so by the time that log call happens, `commandFinished()` has already filled in the real `exitCode`/`outcome` via `withResult()`.

**Log separation, verified by tests (§10):**

- `HttpErrorContextLogTap` never adds `http_*` fields to a queue- or console-context log record, since it only activates when a `Route` has resolved on the container's bound `Request` — never true for a queue worker or console process.
- `QueueErrorContextLogTap` never adds `queue`/`connection`/`job_name`/`attempt` to an HTTP or console log record, since it only activates for an exception object `QueueExecutionTelemetry` has actually seen.
- `ConsoleErrorContextLogTap` never adds `command`/`exit_code`/`outcome` to an HTTP or queue log record, for the same reason (ambient context only ever gets set from a real `CommandStarting`).
- All three taps write only to the record's `extra` bag — `message` and `context` are never touched, matching every prior-phase tap.

No payload, arguments, options, tokens, emails, user IDs, Firebase UID, or full stack context beyond the existing exception log is ever added by either tap.

---

## 10. Tests (Part 11)

| File | Covers |
| --- | --- |
| `tests/Feature/Telemetry/Queue/QueueExecutionTelemetryTest.php` | Successful job via real `sync` dispatch (1), failed job with exception preserved + span error (2), retried job (`JobReleasedAfterException`) and voluntarily-released job (`JobProcessed`+`isReleased()`) via direct event dispatch (3), two sync dispatches counted exactly twice (4), unresolvable job metadata → bounded fallbacks (5), cardinality safety — no job ID/UUID/payload/schedule/device ID (6), a broken `Tracer` never fails the job and metrics are still recorded (7), lifecycle state returns to `null`/`0` after three consecutive jobs including a failure (8), and a job that synchronously dispatches another job without cross-contaminating either context. |
| `tests/Feature/Telemetry/Queue/QueueErrorContextLogTapTest.php` | Tap registered on every channel; enrichment only for an exception `QueueExecutionTelemetry` actually saw; untouched for an unrelated exception or a non-exception record; HTTP tap adds nothing to a queue-context log and vice versa; a console command in ambient context does not leak into a queue job's log. |
| `tests/Feature/Telemetry/Console/ConsoleCommandTelemetryTest.php` | Successful command via direct `CommandStarting`/`CommandFinished` dispatch, exit code preserved on the span (9), failed command with span error (10), unknown/empty command name → bounded fallback (11), arguments/options never leak into labels or span attributes (12), a broken `Tracer` never changes the observed exit code (13), one lifecycle → exactly one counter/histogram record, and a stray duplicate `CommandFinished` never double-counts (14). |
| `tests/Feature/Telemetry/Console/ConsoleErrorContextLogTapTest.php` | Tap registered on every channel; enrichment only after a command has actually started in this process; untouched before any command context exists or for a non-exception record; HTTP/queue taps add nothing to a console-context log and vice versa (15). |
| `tests/Unit/Telemetry/QueueConsole/QueueConsoleTelemetryDependencyRuleTest.php` | Dependency rule (16), scoped to `app/Telemetry/Queue`, `app/Telemetry/Console`, and both new log taps specifically (in addition to the pre-existing generic scan). |
| `tests/Unit/Telemetry/Queue/{QueueOutcomeTest,QueueJobNormalizerTest,QueueContextTest}.php` | Bounded enum surface; class-basename normalization + `unknown` fallback (including a mocked `Job` whose `resolveQueuedJobClass()` throws); value-object log-context shape. |
| `tests/Unit/Telemetry/Console/{ConsoleOutcomeTest,ConsoleCommandNormalizerTest,ConsoleContextTest}.php` | Bounded enum surface + `fromExitCode()` mapping; command-name trimming + `unknown` fallback; value-object `withResult()`/log-context shape. |

All new tests use the in-memory `Tests\Support\Telemetry\Recording*` fakes already established in Phase 7B.1 (`RecordingTracer`, `RecordingMeter`, `RecordingCounter`, `RecordingHistogram`, `RecordingUpDownCounter` — new in this phase, `RecordingActiveSpan`) — no real OpenTelemetry SDK, Collector, Prometheus, or Tempo is required. Queue scenarios that need an outcome the `sync` connection cannot produce (retried/released, unresolvable metadata) dispatch the real Laravel queue events directly against a `Mockery`-mocked `Illuminate\Contracts\Queue\Job` — the same "exercise the real listener without the full infrastructure" approach `HttpRequestTelemetryMiddlewareTest` already uses for `recordException()`. Console scenarios dispatch `CommandStarting`/`CommandFinished` directly for the reason established in §3 (these events do not fire during `back_vibes`'s own test runs).

---

## 11. Validation results (Part 14)

| Command | Result |
| --- | --- |
| `OTEL_PHP_DISABLED_INSTRUMENTATIONS=all php artisan test tests/Unit/Telemetry tests/Feature/Telemetry` | 126 passed, 393 assertions, 2 pre-existing risky tests (Phase 7B.1's `HttpRequestTelemetryMiddlewareTest`, unrelated to this phase — see that test file) |
| `php artisan test --filter=Queue` | 41 passed, 145 assertions |
| `php artisan test --filter=Console` | 31 passed, 86 assertions |
| `php artisan test` (full suite) | **836 passed**, 2451 assertions — no regressions |
| `./vendor/bin/pint --test` | Passed |

`git diff --stat` in `ixora-infra` for this phase touches only documentation (`docs/**`) — no Collector, Prometheus, Loki, Tempo, Grafana, or OpenTofu file changed.

---

## 12. Known limitations

- **The console per-command span is unreachable from `ConsoleCommandTelemetry` in this test suite** (§3, §6) — `CommandStarting`/`CommandFinished` never fire during `APP_ENV=testing`, so span-enrichment correctness for console is verified through direct unit-level event dispatch (proving the *code path* is correct) rather than an end-to-end `$this->artisan()` call. This is the same category of gap Phase 7B.1 documented for `recordException()`.
- **`ixora.console.*` span attributes will not reach the real per-command span in production either**, strictly speaking — only the ambient/coarser fallback, since `CommandFinished` fires after `Command::execute()`'s span has already ended (§3, §6). Metrics and log context are both unaffected; only the span-attribute enrichment is coarser than originally hoped. A future subphase could close this gap by instead hooking `Command::execute()` directly (as the official instrumentation does) rather than `CommandStarting`/`CommandFinished` — deferred, since it would require either a second OTel-aware hook (outside `app/Telemetry/Console`'s current dependency-rule boundary) or wrapping every command class individually (explicitly disallowed by this phase's boundary).
- **`JobTimedOut`'s metric point is best-effort** (§7.1) — the worker process typically `exit()`s immediately after dispatching this event, leaving no guarantee the OTel SDK's export pipeline gets to flush it.
- **`messaging.destination.name` is `"(anonymous)"` for `back_vibes`'s actual `database`/`sync` queue drivers** (§2) — a pre-existing characteristic of the official auto-instrumentation, not something this phase's `ixora.queue.connection`/queue metric label (which correctly reads the real queue name via `Job::getQueue()`, not the auto-instrumented attribute) is affected by.
- **`QueueOutcome::Cancelled`/`Unknown` and `ConsoleOutcome::Cancelled`/`Unknown` are reserved but unused today** — no current Laravel event maps to a genuine "cancelled" queue/console outcome, and every code path that reaches either class's outcome-recording method always has a concrete, already-known outcome. Kept in the enum for forward compatibility with a future subphase that might introduce one (e.g. a Scheduler-driven cancellation signal), matching `HttpOutcome::Cancelled`'s identical rationale in Phase 7B.1.
- **No Grafana dashboard** for these four metrics yet — Phase 9 (Dashboards), out of this phase's scope.

## 13. Remaining work for Phase 7B.3 — Scheduler

- Instrument `Illuminate\Console\Scheduling\Event` (or the `schedule:run`/`schedule:work` commands specifically) with Scheduler-specific outcome/labels (e.g. distinguishing a scheduled run from a manual one, `withoutOverlapping()` skips, `runInBackground()` behavior) — explicitly out of scope for 7B.2 (§1).
- Decide whether a scheduled, in-process command's `CommandStarting`/`CommandFinished` pair (§3 — it does fire, nested inside `schedule:run`'s own pair) needs a `ixora.console.*` label distinguishing "scheduled" vs. "manually invoked" — the spec's "which commands are scheduled versus manually invoked" question is answerable today only by cross-referencing two rows of `ixora.console.command.total` (`schedule:run` running, and the inner command running inside the same time window) rather than a dedicated label; 7B.3 should decide whether that is sufficient or whether a dedicated attribute is warranted.
- Explicit non-goal carried forward: no Smart Home, Push, or external-provider instrumentation in 7B.3 either — those remain 7B.4–7B.6.

---

## Cross-references

- [backend-sdk-foundation.md](backend-sdk-foundation.md) — Phase 7A Telemetry Abstraction Layer, Contracts, dependency rule, log correlation
- [backend-http-routing-instrumentation.md](backend-http-routing-instrumentation.md) — Phase 7B.1, `Tracer::activeSpan()`, HTTP metrics/label conventions this phase reuses
- [metrics-philosophy.md](../../../architecture/metrics-philosophy.md) · [logs-philosophy.md](../../../architecture/logs-philosophy.md) · [traces-philosophy.md](../../../architecture/traces-philosophy.md)
- [telemetry-naming-convention.md](../../../architecture/telemetry-naming-convention.md) — `ixora.*` namespace, label allowlist, duration unit convention
- [telemetry-availability-policy.md](../../../architecture/telemetry-availability-policy.md) — failure isolation
- [ADR-030 — Observability security and privacy](../../../decisions/ADR-030-observability-security-and-privacy.md)
