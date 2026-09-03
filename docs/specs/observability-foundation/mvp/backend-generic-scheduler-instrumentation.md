# Backend Generic Scheduler Instrumentation — Phase 7B.3 (`back_vibes`)

**Status:** Complete (Level 1 only — Level 2 deferred, see §1)
**Repo:** `back_vibes` (Laravel 13.20.0, PHP 8.3+)
**Feature ID:** `observability-foundation/mvp`
**Prerequisite:** [backend-sdk-foundation.md](backend-sdk-foundation.md) (Phase 7A) · [backend-http-routing-instrumentation.md](backend-http-routing-instrumentation.md) (Phase 7B.1) · [backend-queue-console-instrumentation.md](backend-queue-console-instrumentation.md) (Phase 7B.2) · [metrics-philosophy.md](../../../architecture/metrics-philosophy.md) · [logs-philosophy.md](../../../architecture/logs-philosophy.md) · [traces-philosophy.md](../../../architecture/traces-philosophy.md) · [telemetry-naming-convention.md](../../../architecture/telemetry-naming-convention.md)

---

## 1. Scope

Phase 7B.3 instruments **only** the generic Laravel Scheduler event-execution boundary of `back_vibes`. It builds exclusively on the Phase 7A Telemetry Contracts and the Phase 7B.1 `Tracer::activeSpan()` addition, and introduces the first caller of `Tracer::startSpan()` in this Telemetry Abstraction Layer — **no contract was modified in this phase**.

The Scheduler area is understood as two conceptual levels; only Level 1 is in scope here:

| Level | Contents | Status |
| --- | --- | --- |
| **Level 1 — Generic Laravel Scheduler** | Scheduled event lifecycle, command/closure/callback/shell events, duration, success/failure, mutex/overlap prevention, reliably-observable skips, foreground/background execution, generic Scheduler telemetry context | **Implemented this phase** |
| **Level 2 — Ixora Domain Scheduling** | Vibe scheduling, `Schedule` model orchestration, schedule execution records, device actions, Smart Home dispatch, Push dispatch, provider execution, domain retries, domain cancellation | **Deferred** — not instrumented, not touched, no domain knowledge added anywhere in `app/Telemetry/Scheduler` (see §21) |

`app/Telemetry/Scheduler` and `App\Telemetry\Logging\SchedulerErrorContextLogTap` contain zero imports of `App\Models\{Schedule,Vibe,ScheduleExecution,User,Device}`, `App\SmartHome\*`, `App\PushNotifications\*`, or `App\Services\Scheduling\*` — enforced by `tests/Unit/Telemetry/Scheduler/SchedulerTelemetryDependencyRuleTest.php` (§18).

**Important codebase finding (§4):** `back_vibes` does not currently run `php artisan schedule:run`/`schedule:work` for its own domain scheduling — Level 2 is implemented today via a custom `schedules:dispatch-loop` Artisan command that polls a `Schedule` Eloquent model and dispatches `schedules:dispatch-due` via `Artisan::call()`, entirely bypassing `Illuminate\Console\Scheduling\Schedule`. This phase's telemetry therefore instruments the **generic Laravel Scheduler framework surface** for forward compatibility and any future/incidental use of `routes/console.php`'s `Schedule::` facade — it does not yet observe `back_vibes`'s actual domain dispatch loop, which remains entirely Console+Queue-telemetry-observable today (Phase 7B.2) and is the concrete groundwork Level 2 will eventually build on.

No Schedule model business logic, Vibe scheduling logic, Smart Home logic, Push logic, provider adapter, queue job business logic, Artisan command business logic, controller, route, model, migration, database schema, API contract, or auth behavior was modified. `git diff --stat` for `back_vibes` in this phase touches only `app/Telemetry/Scheduler/**`, `app/Telemetry/Logging/SchedulerErrorContextLogTap.php`, `app/Telemetry/Providers/TelemetryServiceProvider.php`, `tests/Support/Telemetry/{RecordingTracer.php,TelemetryRecorder.php}`, and `tests/**`.

---

## 2. Scheduler auto-instrumentation review (Part 1)

Reviewed `open-telemetry/opentelemetry-auto-laravel`'s hook set for any `Illuminate\Console\Scheduling\*` class, and re-verified the Phase 7B.2 Console findings against Laravel 13.20.0's actual `vendor/laravel/framework/src/Illuminate/Console/Scheduling/*` source.

| Question | Finding |
| --- | --- |
| Does the official instrumentation hook `Illuminate\Console\Scheduling\Event`/`CallbackEvent`/`Schedule`/`ScheduleRunCommand`? | **No.** `opentelemetry-auto-laravel`'s hook set (`Hooks\Illuminate\{Console,Queue,Http,...}`) contains no `Hooks\Illuminate\Console\Scheduling\*` namespace at all. No span, no attribute, nothing is ever created for a scheduled-event boundary by auto-instrumentation, in any execution mode. This settles Part 7 in favor of **Strategy B** (create one boundary span) — it is not a choice made over Strategy A, since Strategy A's precondition ("official instrumentation already creates a span covering the entire scheduled event") is false. |
| Does only `schedule:run` receive a console span? | For an in-process (non-background) **command** event only: `Event::run()` → for `runInBackground() === false`, `Illuminate\Console\Scheduling\Event::execute()` still shells out via `Symfony\Component\Process\Process::fromShellCommandline($this->buildCommand())->run()` — i.e. **every** command event, foreground or background, is a genuinely separate OS process. It is that *child* process's own `artisan {command}` invocation that gets the ordinary per-command span from `Hooks\Illuminate\Console\Command::execute()` (Phase 7B.2 §3) — not a span inside `schedule:run`'s own process. `schedule:run` itself gets exactly one `"Command schedule:run"` span, like any other command, and nothing else scheduler-specific. |
| Do inner scheduled commands receive their own command spans? | Yes, but in a **separate process** with a **separate, disconnected trace** — see the next row. |
| Do scheduled closures receive spans? | **No.** A closure/callback event (`Schedule::call()`/`Schedule::job()`) runs via `CallbackEvent::run()` → `Container::call($this->callback, ...)`, entirely in-process, inside `ScheduleRunCommand`'s own process and (per the OTel `Command::execute()` hook, Phase 7B.2 §3) inside `schedule:run`'s own already-active span. No dedicated span exists for the callback itself from either official instrumentation or (before this phase) any custom code. |
| Do scheduled jobs receive queue spans? | `Schedule::job()` dispatches the job via `dispatch()`/`Bus::dispatch()` from inside the same in-process `CallbackEvent::run()` path above. If the job is queued (not `dispatchSync`), Phase 7B.2 §2's findings apply unchanged: the auto-instrumented dispatch/consumer spans described there fire exactly as they would for any other queued dispatch — nothing scheduler-specific changes this. |
| Does `runInBackground()` change span availability? | For a **command** event: no meaningful change — it is already a separate process either way (previous rows); `runInBackground()` only changes whether `Process::run()` blocks (foreground: `->run()`, blocking) or `Process::start()` (background: fire-and-forget, `& > /dev/null 2>&1 &`-style, per `Event::buildCommand()`). For a **callback** event: `CallbackEvent::runInBackground()` **throws `RuntimeException` unconditionally** (`Illuminate\Console\Scheduling\CallbackEvent::runInBackground()` — verified in the installed framework source) — a closure/callback/job event can never run in the background at all. |
| Does `withoutOverlapping()` expose a reliable skip event? | Only indirectly — see §9. No dedicated `ScheduledTaskSkippedBecauseOverlapping`-style event exists; `Event::run()` returns silently (no-op) when the mutex is already held, and `ScheduledTaskStarting`/`ScheduledTaskFinished` still fire around that no-op call exactly as if the event had "run". The only reliable signal is the public `Event::$skippedBecauseOverlapping` boolean property, readable at `ScheduledTaskFinished` time. |
| Does `onOneServer()` expose a reliable skip or lock-failure event? | No dedicated event either. `onOneServer()` composes with the same mutex machinery `withoutOverlapping()` uses (`Event::mutex`/`Illuminate\Console\Scheduling\SchedulingMutex`) — a lost one-server check surfaces as the generic `ScheduledTaskSkipped` event (§9), with no reason property distinguishing it from a paused schedule or a failed `when()`/`skip()` callback. |
| Does `schedule:work` differ from `schedule:run`? | `Illuminate\Console\Scheduling\ScheduleWorkCommand::handle()` is a long-running loop that sleeps until the next whole minute, then internally calls `$this->laravel[Schedule::class]` and dispatches `Artisan::call('schedule:run')` (via `Process`, spawning it as a subprocess) every minute — it does not run events itself. Every scheduled-event lifecycle event this phase listens to therefore still originates from a `schedule:run` process, just one of many spawned repeatedly over `schedule:work`'s lifetime; this is exactly the "repeated ticks must not retain stale context" scenario Part 11/13 require (§13, §17). |
| Which Scheduler events are dispatched? | Exactly five, all in `Illuminate\Console\Events`: `ScheduledTaskStarting`, `ScheduledTaskFinished`, `ScheduledTaskFailed`, `ScheduledTaskSkipped`, `ScheduledBackgroundTaskFinished` — verified against `Illuminate\Console\Scheduling\ScheduleRunCommand` (dispatches the first four) and `Illuminate\Console\Scheduling\ScheduleFinishCommand` (dispatches the fifth). No other Scheduler event class exists in this Laravel version. |
| Exact ordering of Scheduler events | For a normal successful/failing run: `ScheduledTaskStarting` → (event executes) → `ScheduledTaskFinished`. For a skip: `ScheduledTaskSkipped` only — `Starting`/`Finished` never fire (§9). For a foreground command with a non-zero exit code specifically: `ScheduledTaskFinished` fires first (unconditionally, once `Event::run()` returns), **then** `ScheduleRunCommand::runEvent()` throws a synthetic `Exception` and dispatches `ScheduledTaskFailed` for the **same** event — a verified double-fire (§ "Double-fire" finding, `SchedulerExecutionTelemetry`'s class docblock) this phase's terminal-handling logic must not double-count (§17). |
| Exact ordering relative to Console events | `ScheduledTaskStarting` fires **before** `Event::run()`, i.e. before the child process for a command event is even spawned — so it precedes that child process's own `CommandStarting`. `ScheduledTaskFinished`/`Failed` fire in the `schedule:run` process **after** the child process's `Process::run()` call returns (foreground) or immediately after `Process::start()` (background, before the child has necessarily finished at all) — so relative to the *inner* command's own `CommandFinished` (which fires inside the child process), there is no shared-process ordering guarantee for background at all, and for foreground the inner `CommandFinished` always precedes the outer `ScheduledTaskFinished` (different processes, but the inner one has already exited by the time `Process::run()`, blocking, returns). |
| Exact ordering relative to Queue events for scheduled jobs | For a callback/job event (in-process), `ScheduledTaskStarting` fires, then `CallbackEvent::run()` calls `Container::call()`, which for `Schedule::job()` dispatches the job — if queued, the producer-side `Queue` events (Phase 7B.2 §2) fire synchronously inline (payload creation, not execution); if `dispatchSync()`/`sync` connection, the full `JobProcessing`/`JobProcessed` pair (Phase 7B.2 §7.1) also fires inline, nested entirely inside the Starting→Finished window. `ScheduledTaskFinished` fires last. |
| Do event callbacks execute while a command span remains active? | Only for a **callback** event — see the "scheduled closures" row above: yes, `CallbackEvent::run()`'s `Container::call()` executes strictly inside `schedule:run`'s own already-active per-command span (whatever the OTel SDK's ambient "current span" resolves to at that point in the `schedule:run` process). A **command** event's actual execution happens in a disconnected child process (next row) — no span relationship exists between the two processes at all. |
| Do background processes retain or lose trace context? | **Lose it, for a command event.** `Illuminate\Console\Scheduling\Event::buildCommand()`/`CommandBuilder` build a shell command line (and, for background, a `ProcessUtils`-escaped variant with `&`) with no W3C `traceparent` injection anywhere in this class or its `finish()`/`callBeforeCallbacks()` companions (verified by reading the full `Event.php`/`CommandBuilder.php` source in this installed framework version) — no framework mechanism propagates trace context into that child OS process. A span the child's own `Command::execute()` hook starts is therefore always the start of a **new, disconnected trace**, never a child of any span in the `schedule:run` process. A **callback** event, by contrast, never leaves the process, so there is nothing to lose — the ambient context (if any) is simply still active (previous row). |
| Are exceptions propagated or converted into exit codes? | For a **command** event, `Process::run()` captures the child's real exit code as `Event::$exitCode` — the *child* process's own exception (if any) was already turned into a non-zero exit code before `schedule:run` ever sees it; `schedule:run`'s own process never receives a PHP exception object for it (only the synthetic one described two rows up, purely for `ScheduledTaskFailed`'s payload). For a **callback** event, an exception thrown inside the closure/job **does** propagate as a real PHP exception out of `CallbackEvent::run()` — caught by `ScheduleRunCommand::runEvent()`'s own `try`/`catch`, which calls the container's `ExceptionHandler::report()` and dispatches `ScheduledTaskFailed` with the real exception, **without** `ScheduledTaskFinished` ever having fired for that attempt (contrast with the command double-fire case). |
| Do scheduled commands create duplicate generic Console metrics? | No — per Phase 7B.2, `ConsoleCommandTelemetry` listens to `CommandStarting`/`CommandFinished`, which fire once per real Artisan invocation regardless of whether that invocation happened to be launched by `schedule:run`'s child process or a human typing `php artisan foo`. `app/Telemetry/Scheduler` adds no second listener for these events and no second `ixora.console.*` metric anywhere (§3, verified by `SchedulerTelemetryDependencyRuleTest`, §18). |
| Do scheduled queued jobs create duplicate Queue metrics? | No, for the same reason — `QueueExecutionTelemetry` (Phase 7B.2) already owns every `JobProcessing`/`JobProcessed`/etc. dispatch regardless of who called `dispatch()`; nothing in `app/Telemetry/Scheduler` listens to a Queue event. |
| Are closure descriptions stable and bounded? | `Event::$description`, set via `->name()`/`->description()`, is a plain, developer-authored `?string` property with no framework-imposed length bound and no guarantee of staticity — `SchedulerEventNormalizer` therefore treats it as static-by-convention (same assumption `HttpRouteNormalizer`/`ConsoleCommandNormalizer` already make about route/command names, Phase 7B.1/7B.2) and additionally sanitizes + truncates it to a fixed 64-character bound before it can reach a metric label (§4, §13). |

**Conclusion — no existing span or metric represents a scheduled-event boundary anywhere in this stack.** Phase 7B.3 therefore implements **Strategy B**: one new boundary span per executed event, created through `Tracer::startSpan()`, plus the two required `ixora.scheduler.*` metrics (§6). Nothing scheduled-command- or scheduled-job-specific is added to Console or Queue telemetry.

---

## 3. Signal ownership and duplication policy (Part 2)

| Domain | Owns | Never creates |
| --- | --- | --- |
| **Scheduler** (`app/Telemetry/Scheduler`) | The fact that Laravel Scheduler selected and executed an event; scheduled-event duration; scheduled-event outcome; foreground/background mode; event type; overlap-prevention outcome where reliably observable; ambient context for Console classification (§7) | A second `ixora.console.*` metric; a second `ixora.queue.*` metric; a duplicate command span; a duplicate queue-job span |
| **Console** (`app/Telemetry/Console`, Phase 7B.2, unmodified) | Every real Artisan command invocation — `ixora.console.command.total`/`.duration` — regardless of whether the invocation happened to be launched by a scheduled command event's child process | Anything Scheduler-specific |
| **Queue** (`app/Telemetry/Queue`, Phase 7B.2, unmodified) | Every job-execution attempt — `ixora.queue.job.total`/`.duration` — regardless of whether the job happened to be dispatched from a scheduled callback/job event | Anything Scheduler-specific |

The same scheduled command legitimately produces **two** metrics — one `ixora.scheduler.event.total` row (the Scheduler boundary saw the event selected and run) and, in the child process, one `ixora.console.command.total` row (the Console boundary saw the actual `artisan foo` invocation) — these are different boundaries, not duplicates, exactly as Part 2 specifies. The same is true for a scheduled queued job and `ixora.queue.job.total`. Verified directly by dedicated tests (§13, scenarios 4/5/17).

`app/Telemetry/Console/ConsoleCommandTelemetry.php` and `app/Telemetry/Queue/QueueExecutionTelemetry.php` are **byte-for-byte unmodified** by this phase (confirmed: neither file appears in `git diff --stat`, §1) — Phase 7B.2 behavior, metrics, and tests are fully preserved.

---

## 4. Laravel Scheduler usage in `back_vibes` today

`routes/console.php`/`App\Console\Kernel::schedule()` was reviewed for any existing use of the native `Illuminate\Console\Scheduling\Schedule` facade. Finding: `back_vibes` runs domain scheduling through a custom `schedules:dispatch-loop` Artisan command (a long-running polling loop over a `Schedule` Eloquent model, dispatching due work via `Artisan::call('schedules:dispatch-due', ...)`), **not** through `Schedule::command()`/`Schedule::call()`/`Schedule::job()` registrations, and `php artisan schedule:run`/`schedule:work` are not part of this application's current deployment.

This means:

- The `ixora.scheduler.*` metrics and span this phase adds will currently record **zero** events in `back_vibes`'s real production traffic, until/unless a native `Schedule::` entry is registered.
- This is intentional and matches the phase brief precisely: Phase 7B.3 instruments the **generic Laravel Scheduler framework surface** (Level 1) so that any future native schedule entry — or a future Level 2 migration that adopts `Schedule::` instead of the custom loop — is observable for free, without redesigning telemetry later.
- `schedules:dispatch-loop`/`schedules:dispatch-due` remain fully Console-telemetry-observable today (Phase 7B.2, unmodified) — they are ordinary Artisan commands from the framework's point of view.
- No change was made to `schedules:dispatch-loop`, `schedules:dispatch-due`, or any class under `App\Services\Scheduling`/`App\Models\Schedule` — confirmed by `git diff --stat` (§1) and the dependency-rule test (§18).

All lifecycle testing in this phase (§13) therefore constructs a real `Illuminate\Console\Scheduling\Schedule` object directly in tests and dispatches the five lifecycle events against it/its registered events — the same "exercise the real listener without the full infrastructure" approach Phase 7B.2 used for Console events that Laravel suppresses during `APP_ENV=testing` (Phase 7B.2 §3).

---

## 5. Scheduler telemetry components (Part 3)

`app/Telemetry/Scheduler/`:

| Class | Responsibility |
| --- | --- |
| `SchedulerExecutionMode` (enum) | Bounded set: `foreground`, `background`, `unknown` (reserved — every code path today reads the real `Event::$runInBackground` flag, so `unknown` is never actually produced, kept for forward compatibility only). |
| `SchedulerEventType` (enum) | Bounded set: `command`, `shell`, `closure`, `callback`, `unknown`. No dedicated `job` case — see next section for why. |
| `SchedulerOutcome` (enum) | Bounded set: `success`, `failed`, `skipped`, `overlap_prevented`, `background_completed`, `cancelled` (reserved, unused — no Laravel Scheduler event maps to a genuine "cancelled" state today, mirroring `QueueOutcome::Cancelled`/`ConsoleOutcome::Cancelled`), `unknown` (used only when a foreground/background event's exit code is unexpectedly absent). |
| `SchedulerEventNormalizer` | Produces the stable, bounded `event_name`/`event_type` pair described in §8 — never the full shell command, raw arguments/options, closure source, or a dynamic ID. |
| `SchedulerContext` | Immutable-with-`withResult()` value object: `eventName`, `eventType`, `executionMode`, `expression`, `timezone`, `outcome` (nullable until terminal), `exitCode` (nullable). No `Event`/`CallbackEvent`/process/output/domain object is ever stored on it. |
| `SchedulerExecutionTelemetry` | Listens to the five Scheduler lifecycle events (§7), records both metrics (§6), creates/ends the boundary span (§9), classifies outcomes (§10), manages the execution-state stack (§12), and exposes `contextForException()` for `SchedulerErrorContextLogTap` (§11). |

`App\Telemetry\Logging\SchedulerErrorContextLogTap` (§11) lives alongside the other three log taps in `app/Telemetry/Logging/`, matching Phase 7B.2's precedent — not inside `app/Telemetry/Scheduler` itself.

No new shared `TelemetryExecutionContext`/`TelemetryScope`/`TelemetryAttributesBuilder`/`TelemetryNameNormalizer`/`TelemetryOutcome` abstraction was introduced (Part 15) — `SchedulerEventNormalizer` normalizes a genuinely different kind of value (an `Event`/`CallbackEvent` object exposing five different possible identity sources) than `HttpRouteNormalizer` (a URI template), `QueueJobNormalizer` (a class name), or `ConsoleCommandNormalizer` (an Artisan command string), with no real shared logic beyond "return a bounded fallback string" — not enough concrete duplication to justify an extraction, matching Phase 7B.2's identical conclusion (Phase 7B.2 §4).

Neither `app/Telemetry/Scheduler` nor `SchedulerErrorContextLogTap.php` imports anything under the `OpenTelemetry\` namespace or `App\Telemetry\{OpenTelemetry,Noop}\` — enforced by `tests/Unit/Telemetry/Scheduler/SchedulerTelemetryDependencyRuleTest.php` (§18) in addition to the pre-existing generic `tests/Unit/Telemetry/DependencyRuleTest.php`. Where `SchedulerExecutionTelemetry::startBoundarySpan()` needs a stand-in `Span` for the (currently theoretical) case where `Tracer::startSpan()` itself throws, it uses a **local anonymous class** implementing only `App\Telemetry\Contracts\Span` — not `App\Telemetry\Noop\NoopSpan` — specifically to keep this module's dependency surface to Contracts alone (see `SchedulerExecutionTelemetry::inertSpan()`'s docblock).

---

## 6. Metrics (Part 5)

| Metric | Type | Unit | Labels | Purpose |
| --- | --- | --- | --- | --- |
| `ixora.scheduler.event.total` | Counter | `{event}` | `environment`, `service_name`, `event_name`, `event_type`, `execution_mode`, `outcome` | Total scheduled-event executions and terminal outcomes — answers "which scheduled events run", "foreground vs. background", "command/closure/callback/shell", and "which succeed, fail, or get skipped/overlap-prevented". |
| `ixora.scheduler.event.duration` | Histogram | `ms` | same as above | Scheduled-event duration, segmented by outcome. Recorded only when execution actually occurred (never for a generic skip, §9/§13 scenario 9) — reflects real elapsed time from `ScheduledTaskStarting` to the matching terminal event. |

`ixora.scheduler.event.active` (the optional `UpDownCounter`) is **not implemented** — Part 5 requires proof that every start has one reliable terminal event across both foreground and background, that skips don't drift the gauge, and that process termination doesn't leave a stale value. A background event's start (`ScheduledTaskStarting`, in the `schedule:run` process) and its real completion (`ScheduledBackgroundTaskFinished`, in a separate `schedule:finish` process — §7, §14) cannot symmetrically increment/decrement the same in-memory gauge without inventing cross-process state, which Part 8/Part 12 explicitly forbid. See §20 "Known limitations".

**Unit/label-style consistency:** `ms` matches `ixora.http.server.duration`/`ixora.queue.job.duration`/`ixora.console.command.duration`'s platform-wide convention (Phase 7B.1 §6, Phase 7B.2 §5). Labels are underscored (`event_name`, `execution_mode`) matching every prior phase's metric-label convention; span attributes (§9) use the dotted `ixora.scheduler.*` style instead, the same intentional per-signal-type split established since Phase 7B.1.

**Forbidden labels — verified never assigned to either metric** (§13 scenario 13, §16): next-run timestamp, raw cron expression, mutex ID/lock key, process ID, hostname, `Schedule` model ID, Vibe ID, user ID, device ID, queue job ID, command argument/option values, full shell command line, closure file path. `SchedulerEventNormalizer` only ever returns a bounded, sanitized, length-capped (64 chars) string; `expression`/`timezone` are held on `SchedulerContext` for span/log use only (§9, §11) and are **never** passed to `metricLabels()` — verified by reading `SchedulerExecutionTelemetry::metricLabels()` (only six keys: `environment`, `service_name`, `event_name`, `event_type`, `execution_mode`, `outcome`) and by a dedicated cardinality-safety test (§13 scenario 13).

**No duplication with auto-instrumentation:** per §2, `opentelemetry-auto-laravel` emits no Scheduler metrics or spans at all in this configuration — both metrics are net-new, and neither duplicates an existing Console or Queue metric (§3).

---

## 7. Lifecycle integration (Part 7)

Registered directly on the container's event dispatcher inside `TelemetryServiceProvider::registerSchedulerTelemetryListeners()` — the same "this module owns its own wiring" pattern as the Phase 7B.2 Queue/Console listeners — against all five events Laravel dispatches (§2):

| Event | `SchedulerExecutionTelemetry` method | Effect |
| --- | --- | --- |
| `ScheduledTaskStarting` | `scheduledTaskStarting()` | Builds a `SchedulerContext`, starts the boundary span (§9), pushes `{task, context, startedAt, span}` onto the in-memory stack (§12). Span-creation failure is caught locally and never blocks the push (an `inertSpan()` stand-in is used instead) — so a broken `Tracer` degrades only span enrichment, never metrics (Part 12). |
| `ScheduledTaskFinished` | `scheduledTaskFinished()` | Pops the stack; classifies the outcome (§10); records both metrics + ends the span. A pop that finds nothing (already popped by the double-fire case below) is a safe no-op. |
| `ScheduledTaskFailed` | `scheduledTaskFailed()` | Two cases: (1) a frame is still on the stack (a genuine in-flight callback/job exception, or a `before()`-callback exception — `ScheduledTaskFinished` never fired) → pop it, record `failed` + both metrics + `recordException()`; (2) the stack is already empty (the verified `ScheduleRunCommand` double-fire for a failing **foreground command** — `Finished` already recorded the terminal metric with the real exit code) → do **not** record a second metric, only correlate the exception object to the context `Finished` already computed (via the `WeakMap<Event, SchedulerContext>` described in §12) so `SchedulerErrorContextLogTap` still works for this case. |
| `ScheduledTaskSkipped` | `scheduledTaskSkipped()` | No preceding `Starting` ever fired for this attempt (§9) — records `ixora.scheduler.event.total` only (no duration, no span lifecycle), and adds a lightweight `scheduler.event.skipped` event onto whatever span is already active via `Tracer::activeSpan()`, rather than starting a second span nobody would end. |
| `ScheduledBackgroundTaskFinished` | `scheduledBackgroundTaskFinished()` | Fires in a **separate `schedule:finish` process** (§2, §14) whose in-memory stack/WeakMaps start empty — best-effort span enrichment only (`Tracer::activeSpan()`), **no metric recorded** (it would double-count the `background_completed` row `scheduledTaskFinished()` already recorded in the original `schedule:run` process, §10). |

**Why a stack, not a single slot or keyed map (Part 11):** mirrors `App\Telemetry\Queue\QueueExecutionTelemetry`'s established precedent (Phase 7B.2 §7.1). `Illuminate\Console\Scheduling\ScheduleRunCommand` runs due events strictly sequentially (a plain `foreach` over due events, verified in the installed framework source) — nesting is not the normal case — but a scheduled closure/job callback executes in-process and could in principle trigger another scheduled dispatch (e.g. by calling `Artisan::call('schedule:run')` itself from inside a callback). A stack handles that correctly without cross-contaminating an outer event's context, at negligible extra cost over a single slot. Every push is matched by exactly one pop (the two terminal-event handlers above) — a long-running `schedule:work` process (§2's finding that it repeatedly spawns fresh `schedule:run` subprocesses) cannot accumulate stale frames within any single one of those processes, and each spawned `schedule:run` process starts with a fresh, empty stack of its own regardless.

**No Scheduler behavior altered:** the listener never calls into `Event::run()`/`Schedule`'s mutex machinery, never inspects or mutates `Event::$exitCode`/`$skippedBecauseOverlapping` (only *reads* them), and every method body runs inside `safely()` — a `try`/`catch` swallowing any `Throwable` — so a broken `Tracer`/`Meter`/`Counter::add()`/`Histogram::record()` call cannot alter due-event selection, mutex acquisition, event execution, or exit codes (Part 12, verified by §13 scenario 14).

---

## 8. Event normalization (Part 4)

`SchedulerEventNormalizer::type()`/`::name()` implement the required priority order:

1. **`Event::$description`**, when set and non-empty (`->name()`/`->description()`, or the name `Schedule::job()` sets automatically) — sanitized (control/whitespace collapsed) and truncated to 64 characters, prefixed with the type identifier: `command:cleanup-expired-sessions`, `callback:notify-users`.
2. **Artisan command name only**, extracted from `Event::$command` via a conservative regex (`\bartisan[\'"]?\s+([A-Za-z0-9_][A-Za-z0-9_:-]*)`) matching the exact shape `Illuminate\Console\Application::formatCommandString()` produces — never a partial/garbled guess, and never anything following the command name (arguments, options): `command:queue:prune-batches`.
3. **A safe, deterministic executable basename** for a non-Artisan shell event (`Schedule::exec()`), only when the first whitespace-delimited token's `basename()` matches a conservative `^[A-Za-z0-9_.-]+$` charset — otherwise the bare `shell` fallback, never a partial guess: `shell:backup.sh`, or bare `shell`.
4. **A stable event-type fallback** — `closure`, `callback`, or `unknown` — when none of the above apply.

Examples this normalizer actually produces (verified by tests, §13): `command:queue:prune-batches`, `callback:notify-users`, `closure`, `shell:backup.sh`, `unknown`.

Forbidden values — verified never produced (§13 scenario 3/6/12/13): the full shell command line (php binary path, redirects, `sudo -u`), raw arguments/options, closure source code or file path, a dynamic ID interpolated at runtime, a raw email/token/user identifier.

**Cron expressions:** `Event::$expression` is carried on `SchedulerContext::$expression` for span/log use only (§9, §11) — never passed to `metricLabels()` (§6). Cardinality was assessed and judged unbounded-in-practice (an application can register arbitrarily many distinct expressions, and a "*/5 * * * *"-style string offers no natural grouping), so per Part 4's explicit guidance it is excluded from metrics.

**Timezones:** `Event::$timezone` (a `DateTimeZone` or string) is normalized to a plain timezone-name string on `SchedulerContext::$timezone`, for span/log attributes only — never a metric label, per Part 4.

---

## 9. Span strategy (Part 7)

**Strategy B — one Scheduler boundary span per executed event**, created through `Tracer::startSpan()` in `SchedulerExecutionTelemetry::startBoundarySpan()`, called from `scheduledTaskStarting()`:

- **Name:** `scheduler.event {event_name}` — e.g. `scheduler.event command:queue:prune-batches`.
- **Attributes set at start:** `ixora.scheduler.event_name`, `ixora.scheduler.event_type`, `ixora.scheduler.execution_mode`, `ixora.scheduler.scheduled` (always `true`), plus `ixora.scheduler.expression`/`ixora.scheduler.timezone` when non-null.
- **Attributes set at the terminal event:** `ixora.scheduler.outcome`, `ixora.scheduler.exit_code` (when known).
- **Ends exactly once** — via the popped stack frame's own `Span` instance, from whichever terminal handler pops it (`scheduledTaskFinished()` or `scheduledTaskFailed()`'s in-flight branch). A pop that finds nothing never calls `end()` a second time.
- **`setError()`** is called for `outcome === Failed`; **`recordException()`** is called only from `scheduledTaskFailed()`'s in-flight branch (a genuine callback/job exception that has not been recorded onto any other span, since — per §2 — no queue/console auto-instrumented span exists for an in-process callback failure the way it would for a queued job's own consumer span) — never both `setError()`+`recordException()` from the double-fire branch, which performs no span operation at all (the span was already ended by `Finished`).
- **Never a second command span or a second queue-job span** — this span exists only around the Scheduler boundary itself; it does not wrap the inner Console/Queue execution the way a naive "just start a span in `ScheduledTaskStarting` and never touch it again" implementation might accidentally imply. For a callback/job event specifically, this span *is* active for the true duration of the in-process callback (§2), so an inner Console/Queue span, if one existed, would legitimately nest as a child through the same `Tracer::activeSpan()` mechanism Console/Queue telemetry already use — no extra code was needed for this.
- **Fails open:** `startBoundarySpan()` wraps `$this->tracer->startSpan(...)` in its own `try`/`catch`, returning a local `inertSpan()` stand-in on failure (§5) — the stack frame is always pushed, so metrics are unaffected by a broken `Tracer`.

**Never added to this span:** `Schedule` model ID, Vibe ID, user ID, device ID, full command line, arguments, options, shell secrets, closure file path, mutex key, raw exception message as an attribute (only via `recordException()`, at the trace level), serialized event data.

---

## 10. Outcome classification (`SchedulerOutcome`, Parts 5/9)

`SchedulerExecutionTelemetry::classifyOutcome()`, called from `scheduledTaskFinished()`:

1. `Event::$skippedBecauseOverlapping === true` → `overlap_prevented` (the one reliable Part 9 signal, §2/§14).
2. Execution mode is `background` → `background_completed` (the real exit code is not yet known in this process — §14).
3. `Event::$exitCode === null` → `unknown` (defensive fallback; not expected in practice for a foreground event that actually ran).
4. `Event::$exitCode === 0` → `success`; anything else → `failed`.

`scheduledTaskFailed()`'s in-flight branch always records `failed` directly (a thrown exception is unambiguous). `scheduledTaskSkipped()` always records the generic `skipped` outcome — Laravel exposes no reason property for this event (§9), so no more specific classification is guessed.

---

## 11. Structured log alignment (Part 10)

No routine success or skip log was added — successful and skipped scheduled events remain observable via metrics + trace alone, per `logs-philosophy.md`/`metrics-philosophy.md`, matching every prior phase's precedent.

**`App\Telemetry\Logging\SchedulerErrorContextLogTap`**, registered on every log channel by `TelemetryServiceProvider` the same way `TraceCorrelationLogTap`/`HttpErrorContextLogTap`/`QueueErrorContextLogTap`/`ConsoleErrorContextLogTap` already are, enriches an existing exception log record (`context.exception` is a `Throwable`) with:

```php
[
    'scheduler_event' => $context->eventName,
    'scheduler_event_type' => $context->eventType->value,
    'scheduler_execution_mode' => $context->executionMode->value,
    'scheduler_outcome' => $context->outcome?->value,   // when known
    'scheduler_exit_code' => $context->exitCode,          // when known
    'scheduler_timezone' => $context->timezone,            // when non-empty
]
```

Gated by **object identity**, not "the most recently executed event": it calls `SchedulerExecutionTelemetry::contextForException($exception)`, which only returns non-null if *that exact exception object* was seen by `scheduledTaskFailed()` (a `WeakMap<Throwable, SchedulerContext>`) — the same pattern `QueueErrorContextLogTap` uses and for the same reason: in a long-running `schedule:work` deployment (spawning many `schedule:run` processes over time, §2), an ambient "current event" read could attach a stale event's context to a later, unrelated exception. This is why `SchedulerExecutionTelemetry` deliberately exposes no `currentContext()`-style ambient accessor at all (contrast with `ConsoleCommandTelemetry::currentContext()`, which is safe only because a console process runs at most one top-level command, Phase 7B.2 §9) — `contextForException()` is its only read path.

**Never included:** full command, arguments, options, environment variables, tokens, user IDs, `Schedule` model IDs, Vibe IDs, device IDs, payloads, mutex keys, process IDs, raw exception-message duplication.

**Log separation, verified by tests (§13 scenario 16):**

- `SchedulerErrorContextLogTap` never adds `scheduler_*` fields to an HTTP-, Queue-, or Console-context log record, since it only activates for an exception object `SchedulerExecutionTelemetry` has actually seen via `scheduledTaskFailed()`.
- `HttpErrorContextLogTap`/`QueueErrorContextLogTap`/`ConsoleErrorContextLogTap` never gain `scheduler_*`-shaped fields, and never activate for a Scheduler-only failure unless that same exception genuinely also carries an HTTP route, a queue-exception identity match, or active Console context.
- All four taps write only to the record's `extra` bag — `message` and `context` are never touched.

---

## 12. Execution state and process safety (Part 11)

**Chosen structure: a stack** (`array<int, array{task: Event, context: SchedulerContext, startedAt: int, span: Span}>`), plus two `WeakMap`s:

| Structure | Purpose | Why it's bounded/safe |
| --- | --- | --- |
| `$stack` | In-flight scheduled events, pushed by `scheduledTaskStarting()`, popped by exactly one terminal handler | Grows only with genuine call-stack nesting (§7) — never accumulates across unrelated events over a process's lifetime; every entry is removed by a terminal handler before that method returns. No `Request`, job payload, process, or domain object is ever stored on it — only the `Event`/`CallbackEvent` object itself (retained only as long as the frame is on the stack), a `SchedulerContext` (plain strings/enums), a start timestamp, and a `Span`. |
| `$taskContexts` (`WeakMap<Event, SchedulerContext>`) | Lets `scheduledTaskFailed()`'s double-fire branch recover the context `Finished` already computed, without an ambient "current event" slot (§11) | Bounded by the number of distinct `->command()`/`->call()`/`->job()` registrations in the application's schedule (`Illuminate\Console\Scheduling\Schedule` holds these `Event` objects for the process's lifetime anyway) — never unbounded in a long-running process, and entries for events that are no longer referenced anywhere are automatically collected by PHP's `WeakMap` semantics. |
| `$exceptionContexts` (`WeakMap<Throwable, SchedulerContext>`) | The log tap's only read path (§11) | Bounded by PHP's own garbage collector — an entry disappears once the exception object it keys on is no longer referenced anywhere else; cannot grow unbounded even across a `schedule:work` deployment's many spawned `schedule:run` processes, since each such process is itself a fresh PHP process with its own empty maps. |

Verified safe for every scenario Part 11 lists: repeated `schedule:run` (§2's finding that `schedule:work` simply spawns fresh, independent `schedule:run` processes — each starts with empty state by construction, no cross-process leakage possible); multiple events in one tick (each gets its own stack frame, popped independently, §13 scenario 10); nested foreground command execution (§2 — a command event never nests inside this process at all, it is a disconnected child process); background execution (§14); failures (§13 scenario 2); skips (no frame ever pushed, §9); exceptions before a terminal event (`scheduledTaskFailed()`'s in-flight branch); and tests dispatching lifecycle events directly (§4, §13). `SchedulerExecutionTelemetry::activeExecutionCount()` exists solely so tests can assert the stack returns to empty after every terminal path without reflection (§13 scenario 15).

---

## 13. Foreground and background execution (Part 8)

**Foreground:** a command event's child process is launched via blocking `Process::run()` (§2) — by the time `Event::run()` returns and `ScheduledTaskFinished` fires, the child has already fully exited and `Event::$exitCode` holds its real exit code. Duration measured directly (`hrtime(true)` delta across the stack frame's `startedAt`) reflects genuine wall-clock elapsed time for the whole child-process invocation. A callback/job event is *always* effectively "foreground" in this same sense — it never leaves the process at all (§2).

**Background:** a command event launched via `Process::start()` (fire-and-forget, §2) — `ScheduledTaskFinished` fires in the `schedule:run` process **immediately after launch**, with `Event::$exitCode` still `null` (the child hasn't necessarily finished, may not have even started executing yet). This phase's `classifyOutcome()` recognizes this (`execution_mode === background` check, before the null-exit-code check, §10) and records `background_completed` rather than falsely claiming `success`/`failed`/`unknown` — an honest "the launch completed, the real result is not observable in this process" outcome. Duration recorded at this point covers only the **launch phase**, not the background command's real runtime — documented explicitly here and in `SchedulerOutcome::BackgroundCompleted`'s docblock, not glossed over.

The background command's **real** completion is reported later by `artisan schedule:finish` — Laravel's own mechanism (`Illuminate\Console\Scheduling\CommandBuilder::buildBackgroundCommand()` appends a `schedule:finish {mutex_id} {exit_code_file}`-style trailer to the background command line) — always spawned as its own **separate PHP process** with no shared memory with the original `schedule:run` process. `ScheduledBackgroundTaskFinished` fires there; `scheduledBackgroundTaskFinished()` therefore only best-effort-enriches whatever span happens to be active in *that* process (almost certainly none, in practice, since nothing else instruments `schedule:finish`) and records **no metric** — recording one would double-count the `background_completed` row already recorded in the `schedule:run` process (§7, §10).

**No unbounded state, no invented persistence layer, no active-gauge drift:** exactly per Part 8's constraints — confirmed by not implementing `ixora.scheduler.event.active` at all (§6), and by `scheduledBackgroundTaskFinished()` never writing to `$stack`/`$taskContexts`/`$exceptionContexts` (it has none relevant to it in its own fresh process anyway).

**Documented trace-continuity limitation:** per §2, no W3C trace context is ever injected into a command event's child process (foreground or background) — a span the child's own Console auto-instrumentation starts is always the root of a brand-new, disconnected trace. This is a genuine, honestly-documented gap in this Laravel version's framework behavior, not something `app/Telemetry/Scheduler` can close without modifying `Illuminate\Console\Scheduling\Event`/`CommandBuilder` (forbidden — Scheduler business logic, per this phase's Boundary section).

---

## 14. Skips, mutexes, and overlapping (Part 9)

Reviewed `withoutOverlapping()`, `onOneServer()`, maintenance-mode skips, `when()`/`skip()` truth-test callbacks, and mutex acquisition, against the installed `Illuminate\Console\Scheduling\{Event,Schedule,ScheduleRunCommand,SchedulingMutex}` source (§2).

| Case | Reliable signal? | This phase's behavior |
| --- | --- | --- |
| `withoutOverlapping()` — mutex already held | Yes — `Event::$skippedBecauseOverlapping` (public property, set by `Event::run()` itself before returning early) | `outcome=overlap_prevented`, recorded at `ScheduledTaskFinished` time (§10) — `ScheduledTaskStarting`/`Finished` still fire around the no-op `run()` call, so a full metric+span lifecycle still exists, just with this specific outcome. |
| `onOneServer()` — lost the one-server check | No dedicated event or property distinguishing this from any other generic skip | Surfaces as the generic `ScheduledTaskSkipped` event (§7) → `outcome=skipped`, same as every other unreasoned skip below. Never guessed to be `overlap_prevented` without the actual flag. |
| Maintenance-mode skip, `when()`/`skip()` truth-test callback returning false, a paused schedule | No dedicated event or reason exposed | Same as above — `ScheduledTaskSkipped` → `outcome=skipped`. |
| Mutex acquisition failure generally | Same as `onOneServer()` row | Same — `skipped`, never a guessed reason. |

**Telemetry never touches locks:** `SchedulerExecutionTelemetry` only ever *reads* `Event::$skippedBecauseOverlapping`/`$exitCode`/`$runInBackground` — it never calls `Event::mutex`, never queries or mutates a lock, and never releases a mutex. **No mutex name or lock key ever becomes a label, span attribute, or log field** — verified by §13 scenario 10/13 and by `SchedulerContext` having no property that could hold one in the first place.

**No routine log for a skip** — a skip is metric+trace only (`scheduledTaskSkipped()` records the counter and an event on the active span, §7); it never calls `Log::*`/adds an application log entry, per Part 9/Part 10.

---

## 15. Scheduled versus manual commands (Part 6)

Phase 7B.2 identified that generic Console telemetry alone cannot tell a scheduled command apart from a manually-invoked one. This phase evaluated adding a bounded `invocation_source` (`manual`/`scheduler`/`unknown`) label to `ixora.console.command.total`/`.duration`, per the criteria Part 6 requires:

| Criterion | Finding |
| --- | --- |
| Is Scheduler ambient context reliably active when `CommandStarting` fires for the *inner* command? | **No, for the only case that matters in practice.** Per §2, a command event (`Schedule::command()`/`->exec()`) always executes in a **separate OS process** — `CommandStarting` for that inner command fires in a process with no shared PHP memory with `SchedulerExecutionTelemetry`'s in-memory stack in the `schedule:run` process. There is nothing in-process for `ConsoleCommandTelemetry` to read at all. |
| Could the marker survive the process boundary via Laravel's `Context`/`__LARAVEL_CONTEXT` mechanism? | Technically yes, but **rejected** — that same mechanism also propagates into queued-job payloads and ambient log context; piggybacking a Scheduler marker on it risks exactly the cross-signal leakage Part 10/§11 forbid (a Scheduler-context value silently appearing in Queue or Console log/telemetry paths it doesn't belong to), and it is unavailable and untested for command events that are launched via `Process::start()`/`::run()` rather than an in-process `Artisan::call()`, which is what every command event actually is. |
| Is a callback/job event's `CommandStarting`/`CommandFinished` reachable at all? | N/A for the common case — a callback event does not itself invoke an Artisan command unless the callback explicitly calls `Artisan::call()`; if it does, that call *is* in-process and *would* see ambient Scheduler context — but this is a narrow, callback-specific case, not the general "scheduled command" case Part 6 is asking about. |
| Backward compatibility / existing dashboards / existing tests | `ixora.console.command.total`/`.duration`'s label set is exactly what Phase 7B.2 shipped and tested; adding a label that would be `unknown` for the overwhelming majority of real scheduled commands (all of them, per the first row) would not deliver the promised distinction and would add cardinality for no real benefit. |

**Decision: do not add `invocation_source` to Console metrics in this phase.** This documents the limitation rather than shipping a misleading label, per Part 6's explicit instruction ("If it is not reliable for all relevant execution modes: do not add a misleading label; document the limitation"). `App\Telemetry\Console\ConsoleCommandTelemetry` is **completely unmodified** by this phase (§1, §3) — Phase 7B.2's behavior, metrics, and tests are fully preserved, with zero risk of nested-context leakage or regression.

**What *is* available today:** the question "was this Artisan invocation scheduled or manual" is answerable by cross-referencing `ixora.scheduler.event.total` (`event_type=command`) against `ixora.console.command.total` by event name and a matching time window — coarser than a dedicated label, but accurate and zero-risk. This mirrors Phase 7B.2's own §13 "remaining work" note verbatim, now resolved by this explicit decision rather than left open.

---

## 16. Failure policy (Part 12)

Every `SchedulerExecutionTelemetry` listener method body runs entirely inside `safely()` — a `try`/`catch` swallowing any `Throwable` from normalization, span creation/enrichment, or metric recording. Verified never to affect: due-event selection (the listener never touches `Schedule`'s due-event resolution), event filters/mutex acquisition (never invoked by this module, §14), foreground execution, background process creation (`Process::run()`/`::start()` are never called or wrapped by this module), event callbacks (a callback's real return value/thrown exception is read, never altered), command execution, job dispatch, `Event::$exitCode` (only read, never written), event exception behavior (a real exception is never swallowed by this module — only *this module's own* handling of it is fail-safe), `schedule:run`/`schedule:work` exit behavior.

`Span::startSpan()`'s own failure is specifically guarded (§7, §9's "fails open" bullet, `inertSpan()`) so that a broken `Tracer` degrades only span enrichment, not metric recording — proven directly by §13 scenario 14 (a `Tracer` that throws on every call still yields exactly one `ixora.scheduler.event.total`/`.duration` record with the correct outcome) and scenario 14's sibling test for a `Counter`/`Histogram` that throws (§13).

No telemetry exception ever escapes to the caller — confirmed by every scenario in §13 asserting the observed `Event::$exitCode`/dispatched-event behavior is unaffected by a deliberately-broken telemetry dependency. Exceptions are never converted into successful outcomes, and skipped executions are never converted into failures — `classifyOutcome()`/`scheduledTaskSkipped()` each handle exactly one lifecycle event with no cross-talk between them.

---

## 17. Tests (Part 13)

| File | Covers |
| --- | --- |
| `tests/Feature/Telemetry/Scheduler/SchedulerExecutionTelemetryTest.php` | All 18 required scenarios: successful foreground command (1); failed foreground command with span error + exception preserved (2); scheduled closure/callback with bounded name, no source path, no argument leakage (3, two tests — unnamed closure and named callback); scheduled queued job counted once at the Scheduler boundary with no duplicate Queue metric (4); scheduled Artisan command creating no duplicate Console metric (5); manual Artisan command never creating a Scheduler metric (6); outer `schedule:run` + inner event recorded independently with no cross-contamination (7); repeated ticks simulating `schedule:work` recording each event independently with no stale context (8); generic skip counted once with no duration and no routine log (9); `withoutOverlapping()` reporting `overlap_prevented` via the reliable flag only, never a mutex key (10); background event recorded as `background_completed` in `schedule:run`, and `ScheduledBackgroundTaskFinished` only enriching the active span with no second metric (11); unknown event metadata producing bounded fallbacks without throwing (12); cardinality safety — no raw cron expression, full command, arguments, closure path, model/user/device ID, mutex key, or process ID in any metric label (13); a broken `Tracer` never failing the lifecycle (14, plus a sibling test for a broken `Counter`/`Histogram`); execution-state cleanup to empty after success/failure/skip with no leakage to the next event (15); safe logging-context shape covered jointly with the log-tap test file below (16); no double instrumentation — exactly one counter record and at most one duration record per lifecycle, and a stray duplicate `ScheduledTaskFinished` never double-counted (17). |
| `tests/Feature/Telemetry/Scheduler/SchedulerErrorContextLogTapTest.php` | Tap registered on every channel; enrichment only for an exception `SchedulerExecutionTelemetry` actually saw via `scheduledTaskFailed()`; untouched for an unrelated exception or a non-exception record; HTTP/Queue/Console fields never appear on a Scheduler-only failure log and vice versa (16, log separation). |
| `tests/Unit/Telemetry/Scheduler/SchedulerTelemetryDependencyRuleTest.php` | Dependency rule (18), scoped to `app/Telemetry/Scheduler` and `SchedulerErrorContextLogTap` specifically — no `OpenTelemetry\*` import, no `App\Telemetry\{OpenTelemetry,Noop}\*` import, no `App\Models\{Schedule,Vibe,...}`/`SmartHome`/`PushNotifications`/`Services\Scheduling` import — in addition to the pre-existing generic scan (`tests/Unit/Telemetry/DependencyRuleTest.php`). |

All new tests use the in-memory `Tests\Support\Telemetry\Recording*` fakes already established in Phase 7B.1/7B.2. `RecordingTracer::startSpan()` and `TelemetryRecorder::recordStartSpan()`/`$startSpanCalls` were **added in this phase** — this is the first module in the Telemetry Abstraction Layer to call `Tracer::startSpan()` (every prior phase only enriched an already-active span via `activeSpan()`), so the test fakes needed a genuine "start a new, independently-trackable span" capability; `RecordingTracer::startSpan()` now records the call and returns a fresh `RecordingActiveSpan` per invocation (matching a real tracer's behavior — a new span every call) while still funneling `end()`/`setAttributes()`/`setError()`/`recordException()` into the same shared `TelemetryRecorder`, so existing assertions (`spanEndCalls`, `spanErrorCalls`, `spanExceptions`, `mergedSpanAttributes()`) continue to reflect every span, active-span-enrichment and started-spans alike.

No live Collector, Prometheus, Loki, Tempo, Grafana, real background process, Redis, SQS, or database queue worker is required by any test — real background execution (§13) is covered at the event-lifecycle level, per Part 13's explicit allowance ("Where true background execution cannot be deterministic in automated tests, use focused event-level tests and document the limitation").

---

## 18. Validation results (Part 16)

| Command | Result |
| --- | --- |
| `OTEL_PHP_DISABLED_INSTRUMENTATIONS=all php artisan test tests/Unit/Telemetry tests/Feature/Telemetry` | 159 passed, 552 assertions, 2 pre-existing risky tests (Phase 7B.1, unrelated to this phase) |
| `php artisan test --filter=Scheduler` | 48 passed, 220 assertions |
| `php artisan test --filter=Schedule` | 210 passed, 618 assertions |
| `php artisan test --filter=Console` | 34 passed, 108 assertions — Phase 7B.2 unaffected |
| `php artisan test --filter=Queue` | 44 passed, 166 assertions — Phase 7B.2 unaffected |
| `php artisan test` (full suite) | **869 passed**, 2610 assertions, 2 pre-existing risky — no regressions |
| `./vendor/bin/pint --test` | Passed |

`git diff --stat` in `ixora-infra` for this phase's own changes touches only documentation under `docs/specs/observability-foundation/mvp/**` and `docs/README.md` — no Collector, Prometheus, Loki, Tempo, Grafana, or OpenTofu file was changed by this phase. (Pre-existing, unrelated working-tree changes from other work — `docs/operations/collector-hardening-checklist.md`, `docs/architecture/logs-philosophy.md`, `docs/qa/scheduler-smart-home-e2e.md`, `docs/ixora_observability_foundation.html`, `docs/specs/observability-foundation/mvp/collector-validation-report.md` — were left untouched and are not part of this phase's diff.)

---

## 19. Known limitations

- **`ixora.scheduler.*` currently records zero real production events** — per §4, `back_vibes` does not register any native `Schedule::` entry today; this phase instruments the generic framework surface for forward compatibility, not a currently-active code path. This is an accepted, intentional characteristic of Level 1, not a defect.
- **No trace continuity across a command event's process boundary, foreground or background** (§2, §13) — a genuine Laravel framework gap (no `traceparent` injection into the shelled-out child process), not something this phase's Contracts-only module can close without editing `Illuminate\Console\Scheduling\Event`/`CommandBuilder` (forbidden).
- **`ixora.scheduler.event.active` is not implemented** (§6) — background lifecycle asymmetry (§13) makes a symmetric gauge unsafe without cross-process state this phase's Failure Policy forbids.
- **`invocation_source` was evaluated and deliberately not added to Console metrics** (§15) — the only reliable channel available (Laravel `Context`) was rejected due to cross-signal leakage risk; the distinction remains answerable only by cross-referencing two metrics by name/time window.
- **A callback/job event can never run in the background** (`CallbackEvent::runInBackground()` throws unconditionally, §2) — `execution_mode` is `background` only for command events; this is a genuine Laravel framework constraint, not a limitation of this phase's telemetry.
- **`SchedulerOutcome::Cancelled` and `SchedulerExecutionMode::Unknown` are reserved but unused today** — no current Laravel Scheduler event maps to a genuine "cancelled" outcome, and `Event::$runInBackground` is always a real, readable boolean in practice. Kept for forward compatibility, mirroring `QueueOutcome::Cancelled`/`ConsoleOutcome::Cancelled`'s identical precedent (Phase 7B.2 §12).
- **No Grafana dashboard** for these two metrics yet — Phase 9 (Dashboards), out of this phase's scope.

---

## 20. Level 2 — Ixora Domain Scheduling (deferred)

Explicitly **not implemented, not instrumented, and not touched** in this phase: Vibe scheduling, `Schedule` model orchestration, schedule execution records, device actions, Smart Home dispatch, Push dispatch, provider execution, domain retries, domain cancellation. No class under `App\Models\{Schedule,Vibe,ScheduleExecution}`, `App\SmartHome`, `App\PushNotifications`, or `App\Services\Scheduling` (including `schedules:dispatch-loop`/`schedules:dispatch-due`, §4) was read into or referenced by `app/Telemetry/Scheduler` — enforced by `SchedulerTelemetryDependencyRuleTest` (§17/§18).

Level 2 will be introduced only once the domain execution pipeline itself is instrumented — potentially spread across Phases 7B.4 (Smart Home) through 7B.6 (External Providers), or through a future dedicated subphase once `back_vibes`'s domain dispatch loop (§4) and/or a migration to native `Schedule::` entries is better understood. It is **not** silently folded into Phase 7B.4 by this document — Phase 7B.4's own scope is Smart Home provider-call telemetry specifically (§21), not domain scheduling in general.

---

## 21. Remaining work for Phase 7B.4 — Smart Home

- Instrument Smart Home provider-call execution (dispatch, response handling, retries) with the same Telemetry Contracts-only discipline established since Phase 7A — out of scope for 7B.3.
- Decide, as part of that phase's own design, whether/how a Smart Home dispatch that happens to originate from `back_vibes`'s custom `schedules:dispatch-loop`/`schedules:dispatch-due` domain scheduling (§4) should carry any Scheduler-originated context — this phase deliberately adds no such linkage today, and any future linkage must be designed without adding Smart Home/Vibe/device domain knowledge into `app/Telemetry/Scheduler` (this phase's Boundary remains intact for future phases to build on top of, not around).
- Level 2 (§20) remains available as future groundwork once a phase actually touches domain scheduling execution.
- Explicit non-goals carried forward unchanged: no Push or external-provider instrumentation in 7B.4 either — those remain 7B.5/7B.6.

---

## Cross-references

- [backend-sdk-foundation.md](backend-sdk-foundation.md) — Phase 7A Telemetry Abstraction Layer, Contracts, dependency rule, log correlation
- [backend-http-routing-instrumentation.md](backend-http-routing-instrumentation.md) — Phase 7B.1, `Tracer::activeSpan()`, HTTP metrics/label conventions this phase reuses
- [backend-queue-console-instrumentation.md](backend-queue-console-instrumentation.md) — Phase 7B.2, Queue/Console telemetry this phase's signal-ownership policy builds on and does not duplicate
- [metrics-philosophy.md](../../../architecture/metrics-philosophy.md) · [logs-philosophy.md](../../../architecture/logs-philosophy.md) · [traces-philosophy.md](../../../architecture/traces-philosophy.md)
- [telemetry-naming-convention.md](../../../architecture/telemetry-naming-convention.md) — `ixora.*` namespace, label allowlist, duration unit convention
- [telemetry-availability-policy.md](../../../architecture/telemetry-availability-policy.md) — failure isolation
- [ADR-030 — Observability security and privacy](../../../decisions/ADR-030-observability-security-and-privacy.md)
