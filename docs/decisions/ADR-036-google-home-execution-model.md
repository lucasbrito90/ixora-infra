# ADR-036: Google Home execution model and provider execution capabilities (v1.6.0)

## Status

**Accepted** — governs how **Google Home** is represented in the Smart Home architecture for release v1.6.0. Extends [ADR-012](ADR-012-smart-home-provider-strategy.md) (provider platform strategy) and [ADR-032](ADR-032-multi-provider-scope.md) (multi-provider infrastructure). Reads in conjunction with [ADR-016](ADR-016-smart-home-async-execution.md), [ADR-033](ADR-033-device-capabilities.md), [ADR-034](ADR-034-partial-execution-outcome.md) and [ADR-035](ADR-035-cross-provider-deduplication.md).

**Post-acceptance addendum:** §11 records evidence gathered by GH03a *after* acceptance. It corrects two external constraints stated in §3 and **does not change the decision** — Option C stands, and this ADR remains Accepted.

**Approved by the PO on 2026-09-06**, resolving the three open questions recorded in §10: the scheduling degradation (Decision 5), the release version (**v1.6.0** — v1.5.0 remains reserved for Analytics and its planning is unchanged), and the initial platform scope (Android-only, Decision 11).

## Date

2026-09-06

---

## 1. Problem

IXORA's Smart Home layer is **server-authoritative**: the backend holds provider credentials and executes device commands from a queue worker, with no involvement from the user's phone. Google Home cannot participate in that model, because **the Google Home APIs have no server-side surface for third-party applications**.

A `GoogleHomeAdapter implements ProviderAdapter` is therefore not merely difficult — it is **unimplementable**. Every method of the contract takes a `ProviderConnection` (from which the server decrypts credentials) and returns synchronously from the calling process. Google Home has neither a server-usable credential nor a server-reachable API.

This ADR decides how that difference is represented, without spreading provider conditionals through the domain and without breaking Home Assistant.

---

## 2. Context — how the system works today

All findings below were verified by direct code reading on 2026-09-06, not inferred from documentation.

| Fact | Evidence |
| --- | --- |
| The contract assumes server-side execution | `app/SmartHome/Contracts/ProviderAdapter.php` — all four methods (`listDevices`, `readStatus`, `executeAction`, `testConnection`) take `ProviderConnection $connection` and return synchronously. |
| The server holds the credential | `app/Models/ProviderConnection.php` — `encrypted_credentials` is `$hidden`, written via `setEncryptedCredentials()`, read via `decryptedCredentials()`, "only in the adapter layer". |
| The credential column is **NOT NULL** | `database/migrations/2026_06_14_000001_create_provider_connections_table.php` — `$table->text('encrypted_credentials');`. |
| Only one place executes | `app/Jobs/SmartHome/SceneActionJob.php` resolves the adapter and calls `executeAction()`. `SceneDispatchService` and `VibeSmartHomeDispatchService` carry documented guarantees: *"Never calls ProviderAdapterResolver … Never makes HTTP requests."* |
| Schedules execute with the phone absent | A dedicated DO App Platform worker runs `php artisan schedules:dispatch-loop` (`ixora-infra/opentofu/staging/app-api.tf`), which calls `schedules:dispatch-due` every 60s; `DispatchDueSchedulesCommand` queries `Schedule` where `next_run_at <= now` and dispatches through `VibeSmartHomeDispatchService`. **This works with the app closed, the phone offline, or the phone powered off.** |
| A "skipped action" concept already exists | `VibeSmartHomeDispatchService::dispatch()` skips actions whose device is missing and counts them in `SmartHomeDispatchResult.skipped`. |
| A per-execution correlation id already exists | `VibeSmartHomeDispatchService` generates `scene_execution_id` (UUID) per dispatch. |
| A schedule-time validation seam already exists | `app/SmartHome/Validation/ScheduleAutomationValidator::validate()` walks every scene action before a scheduled run and returns `false` (never throws). **Today it is all-or-nothing: one invalid action invalidates the whole schedule.** |
| Providers are declared in config, not code | `config/smart_home.php` → `adapters` (slug ⇒ FQCN) and `provider_descriptors` (form field shapes). `ProviderAdapterRegistry` resolves via the container. |
| The client is already schema-driven | `ProviderDescriptorRegistry` → `GET /api/provider-types` → `front_vibes` builds the provider picker and connection form from the response (v1.4.0-T25). No literal `home_assistant` in mobile production code. |
| **The registry conflates "known provider" with "has a server-side adapter"** | `ProviderDescriptorRegistry::all()` iterates `ProviderAdapterRegistry::registeredSlugs()`. A provider without a server-side adapter **cannot be exposed at all today**. |
| No provider-level capability concept exists | Verified by grep across `app`, `config`, `database`, `tests`. `ProviderDescriptor` describes connection form fields only. `ADR-033` capabilities are **device**-level. `SchedulerExecutionMode` is Laravel-scheduler telemetry, unrelated. |

### 2.1 What `ProviderExtensibilityBoundaryTest` actually enforces

The prior investigation described this test as freezing 21+ files against modification. **That is not what it does.** Reading `tests/Unit/SmartHome/ProviderExtensibilityBoundaryTest.php`:

- It asserts the D.1 files **exist**, and
- that none of them contains the string `FakeProviderAdapter` or an **assignment-shaped hard-coded provider slug** (`'provider' => 'fake'`, `->provider = 'fake'`, …).

The test's own docblock states the intent: *"Provider-slug detection uses assignment-shaped patterns only (not a bare 'fake' substring) so unrelated English prose in comments cannot false-positive."*

This is a **provider-neutrality guard, not a change-freeze**. The decision it protects — *the domain must not branch on provider identity* — is still valid and this ADR reinforces it. A capability-based check (`$provider->supports(SCHEDULED_EXECUTION)`) passes the guard by construction; `if ($provider === 'google_home')` is exactly what the guard exists to prevent. **The test must be extended, not relaxed** (Decision 9).

---

## 3. Constraints — Google Home APIs

Verified against official documentation, 2026-09-06.

> ⚠ Two rows of this table were later corrected by GH03a — see **§11**. The table is deliberately left exactly as written at acceptance time; corrections are recorded as post-acceptance evidence rather than by rewriting history.

| Constraint | Consequence for IXORA | Source |
| --- | --- | --- |
| Home APIs are mobile SDKs only (Android Kotlin, iOS Swift). No REST/cloud API lets a third-party backend read or command a user's devices. | `GoogleHomeAdapter implements ProviderAdapter` is impossible. | [apis/overview](https://developers.home.google.com/apis) |
| HomeGraph API is cloud-to-cloud, for **device makers** exposing their own devices **to** Google. SDM API covers Nest only. | Neither is a substitute. IXORA is not a device maker. | [home-graph](https://developers.home.google.com/reference/home-graph/rest), [nest/device-access](https://developers.google.com/nest/device-access/api) |
| OAuth consent is granted in-app, per **structure**, with sensitive device types granted individually. No documented server-usable refresh token. | Authorization state lives on the device. | [android/permissions](https://developers.home.google.com/apis/android/permissions) |
| Third-party cloud-to-cloud devices (Tuya, Hue, Surplife…) appear in the same unified model. | One integration reaches many brands — the strategic premise holds. | [android/data-model](https://developers.home.google.com/apis/android/data-model) |
| Matter devices already in the user's home are covered; Matter takes precedence over a cloud-to-cloud analog. | A dedicated `MatterProvider` can be deferred (Decision 10). | [android/data-model](https://developers.home.google.com/apis/android/data-model) |
| Traits derive from Matter clusters (`OnOff`, `LevelControl`) plus `Google*` traits; support must be checked **per device**, per attribute/command. | Maps onto ADR-033's closed vocabulary; see GH04. | [android/data-model](https://developers.home.google.com/apis/android/data-model) |
| Automations created via the Automation API run on **Google's** infrastructure and persist even if the third-party app is uninstalled. Time-based starters exist, including cron-like recurrence. Requires the structure to have an address configured. | The only supported path to "executes without the app". | [android/automation](https://developers.home.google.com/apis/android/automation) |
| Automation quotas: 64 automations/structure; **64 instances per developer per structure**; **128 executions per developer per structure per day**. | Hard ceiling on any schedule-delegation design. | [android/automation](https://developers.home.google.com/apis/android/automation) |
| Direct commands (Device API) require the app running with the SDK initialised. Background/terminated/offline execution is **not documented** — treat as unsupported. | Manual execution only, on-device. | [apis/overview](https://developers.home.google.com/apis) |
| Data retention: **maximum 10 days** from receipt. No AI training. No monetisation/redistribution without written approval. No aggregating control across multiple homes. | Directly conflicts with indefinite `devices` persistence (Decision 8). | [policies](https://developers.home.google.com/policies) |
| Production requires Google Home Developer Console + Cloud project + OAuth verification + **certification per device type**. | Timeline not controlled by IXORA (GH03). | [policies](https://developers.home.google.com/policies) |
| No Capacitor plugin exists (official or community). Android SDK GA v1.10.1; iOS GA, iOS 17+, App Attest ⇒ real device only. | Custom native bridge required (GH02). `front_vibes` has no iOS project at all. | [android/sdk](https://developers.home.google.com/apis/android/sdk), [ios/sdk](https://developers.home.google.com/apis/ios/sdk) |

---

## 4. Alternatives considered

| | A — Google Home without scheduling | B — Delegate schedules to Automation API | **C — Hybrid provider execution model** | D — Do not adopt Google Home |
| --- | --- | --- | --- | --- |
| **Shape** | Google Home works only while the app is open. The difference is implicit. | IXORA mirrors each schedule as a Google automation. | Providers declare their execution capabilities; the domain asks the capability, never the identity. | Keep Home Assistant only; revisit Tuya Cloud later. |
| **Product impact** | Schedules silently do nothing for Google devices. | Schedules work for Google devices, decoupled from IXORA audio. | Schedules work where supported; the gap is surfaced before the user commits. | No broadening of device reach. |
| **Scheduler impact** | Silent partial execution — the worst outcome. | Two execution engines, two sources of truth. | Explicit skip + explicit warning. | None. |
| **Architecture cost** | Lowest, but the difference leaks as tribal knowledge and eventually as `if provider ===`. | Highest: reconciliation, drift, deletes, failures, timezone, quotas, idempotency across two systems. | Moderate: one declarative vocabulary, reusing existing seams. | Zero. |
| **Blocking defects** | Violates "do not hide real capability differences". | 64 automations and 128 executions/structure/day are hard ceilings; **a Google automation cannot be time-coupled to IXORA audio playback**, which is what a Vibe is. Duplicated state (PostgreSQL × Google) with no transactional boundary. | — | Abandons the ADR-012-aligned path and the multi-brand reach that motivated the change. |
| **Verdict** | Rejected as an end state (it is C without the declarative model). | **Deferred, not rejected** — preserved as a future capability value. | **Adopted** | Rejected, with explicit re-entry triggers. |

**Why B is deferred rather than adopted now.** Beyond quotas, the semantic mismatch is decisive: a Vibe is an *audio experience with accompanying device actions*. Delegating the device half to a Google automation puts the two halves under two independent clocks — Google's engine fires the lights whether or not the phone ever played the sound, and IXORA cannot observe or correct that. Adding a second source of truth for scheduling, to gain partial coverage of one provider, is disproportionate for v1.6.0. Decision 2 reserves `automation_delegation` as a capability so this can be added later without re-architecting.

**Re-entry triggers for D.** If certification does not cover the device types IXORA needs, if the scheduling limitation proves unacceptable in user testing, or if the retention/monetisation policies conflict with the business model, then Tuya Cloud (server-side, schedulable, fits the existing contract unchanged) becomes the architecturally cheaper option. This ADR does not close that door.

---

## 5. Decision

### Decision 1 — Adopt Option C: hybrid provider execution model

Providers are **not** assumed to be functionally interchangeable. Each provider declares, statically, which execution capabilities it offers. The domain queries capabilities; it never branches on provider identity.

> Home Assistant remains IXORA's server-side, schedulable provider. Google Home is introduced as a **complementary** integration with its own execution capabilities. Google Home does not replace Home Assistant, and Home Assistant's behaviour does not change.

### Decision 2 — Introduce `ProviderExecutionCapability` as a closed vocabulary

Following the precedent of [ADR-033](ADR-033-device-capabilities.md) (closed vocabulary, fail-safe default), this ADR defines a **closed** set of provider-level execution capabilities:

| Capability | Meaning |
| --- | --- |
| `device_discovery` | The provider can enumerate the user's devices. |
| `state_read` | Current device state can be read. |
| `interactive_execution` | Commands can be executed while the user is present in the app. |
| `server_side_execution` | The backend can execute commands using stored credentials, with no client involved. |
| `scheduled_execution` | Commands can be executed by a backend-initiated schedule with the app closed. Implies `server_side_execution`. |
| `automation_delegation` | Recurring intent can be handed to the provider's own automation engine. **Reserved; unused in v1.6.0.** |

Declared values for v1.6.0:

- **Home Assistant** — `device_discovery`, `state_read`, `interactive_execution`, `server_side_execution`, `scheduled_execution`.
- **Google Home** — `device_discovery`, `state_read`, `interactive_execution`.

**Naming rule.** The `can_*` prefix is reserved for **device** capabilities (ADR-033). Provider execution capabilities use bare snake_case identifiers under a distinct type. The two vocabularies must never be merged or cross-validated: a device may be dimmable (`can_set_brightness`) while its provider cannot be scheduled — these are orthogonal facts.

**Placement.** Capabilities are static per provider slug and belong with the existing declarative metadata: `config/smart_home.php` → `provider_descriptors`, surfaced through `ProviderDescriptor` and `GET /api/provider-types`. They are **not** per-connection, not user-editable, and not persisted per device. This reuses the channel the mobile client already consumes.

### Decision 3 — `ProviderAdapter` is unchanged, and is redefined as the *server-side* execution contract

The contract is **not** widened to accommodate Google Home. Instead its meaning is made explicit: `ProviderAdapter` is the contract for providers that declare `server_side_execution`. Google Home does not implement it.

**Required structural change:** `ProviderDescriptorRegistry::all()` currently derives the provider list from `ProviderAdapterRegistry::registeredSlugs()`, so a provider without a server-side adapter cannot be registered or exposed at all. Provider **identity/metadata** must be decoupled from **server-side adapter** registration: `config/smart_home.php` gains a provider registry that is the source of truth for known slugs, of which `adapters` is a subset. This is additive; Home Assistant's resolution path is untouched.

### Decision 4 — `ProviderConnection` is retained; credentials become optional

No new top-level entity (`SmartHomeIntegration` or similar) is introduced. A second concept would fork ownership, policies, device relations and the sync path for no proven gain. `ProviderConnection` remains the single anchor of "this user's link to this provider", and `Device.provider_connection_id` and the ADR-032 dedupe key `(provider_connection_id, provider_device_id)` remain unchanged.

Two adjustments follow, both to be specified by derived tasks:

1. `encrypted_credentials` must become **nullable**. For a provider without `server_side_execution`, the server holds no credential — a placeholder value must not be invented.
2. `status` / `last_tested_at` semantics change for such providers. The server cannot call `testConnection()`, so connection health for a device-side provider is **reported by the client**, not derived by the server. A connection whose health has never been reported is `unknown`, not `connected`.

### Decision 5 — Scheduler semantics: skip explicitly, warn early, never silently

**⚠ This decision changes user-visible product behaviour. Approved by the PO on 2026-09-06 as a known and accepted limitation of the release — it is not a defect.**

When a schedule fires:

1. Actions whose provider declares `scheduled_execution` execute exactly as today.
2. Actions whose provider does **not** are **not executed**, and are recorded with a distinct, first-class outcome (extending the ADR-034 outcome vocabulary — for example `skipped_unsupported`) and counted in the existing `SmartHomeDispatchResult.skipped`. They must be distinguishable from failures and from "device missing"; a skip is not an error and must not consume retries or raise the Smart Home failure alert.
3. The user is warned **before** committing the configuration — at minimum when adding a device action and when creating or enabling a schedule for a Vibe containing such actions.

Two alternatives were rejected. **Silent partial execution** was rejected because the user would believe a schedule works when it does not. **All-or-nothing rejection** was rejected because one unsupported lamp would cancel a working humidifier; note this diverges from `ScheduleAutomationValidator`'s current all-or-nothing return, which the derived task must therefore adjust — under provider-neutral logic only.

**Approved product statement:** *In v1.6.0, a scheduled Vibe will not actuate Google Home devices. Only manual, in-app execution reaches them.*

### Decision 6 — Mixed-provider Vibes are permitted

A Vibe may combine actions across providers. Behaviour is asymmetric by execution mode, and that asymmetry is surfaced, not hidden:

- **Manual, app in foreground:** all actions execute — server-side providers via the existing queue path, device-side providers on the phone.
- **Scheduled:** only actions from providers with `scheduled_execution` execute; the rest are skipped per Decision 5.

For the canonical example (Sleep Vibe: rain audio + Google Home lamp + Home Assistant humidifier), a scheduled 22:00 run plays audio and turns on the humidifier; the lamp is skipped and recorded as such, and the user was told this when building the Vibe.

### Decision 7 — Mobile/backend boundary

- **`back_vibes` is the plan of record.** Vibes, Scenes, Schedules, provider registry and capability metadata, device rows, validation, execution records, telemetry, notifications.
- **`front_vibes` owns the Google Home runtime.** Google authorization/consent, the Home SDK, discovery, command execution, state reads for that provider.
- **No circular dependency.** The backend never calls the mobile app and never depends on it being reachable. The mobile app pulls what it needs and **reports results back**; the backend accepts reports and reconciles.
- **Correlation reuses `scene_execution_id`**, the UUID already generated per dispatch by `VibeSmartHomeDispatchService`. Device-reported results must be **idempotent on `(scene_execution_id, scene_action_id)`**, mirroring the scheduler's existing `occurrence_key` discipline (ADR-010).
- Reported results are **untrusted client input**: authorization, ownership and shape are validated server-side like any other request; a client may only report on its own user's actions.

### Decision 8 — Security, privacy and retention

- Google OAuth tokens **never leave the device** and are never transmitted to or stored by `back_vibes`. No bypass of this platform constraint may be designed.
- The backend stores the minimum needed to reference a device: provider device identifier, and the metadata required to render and act on it.
- **Retention.** Google-derived data (device names, types, state snapshots sourced from the Home APIs) is subject to Google's 10-day maximum. IXORA-owned data (that the user configured an action against a device, and the execution record of that action) is IXORA's own and is **not** subject to that limit. The boundary is: *facts obtained from the Home APIs expire; facts the user authored in IXORA do not.* A derived task must define the expiry mechanism for Google-sourced device metadata and confirm that an expired-metadata device degrades gracefully rather than breaking a Scene. Revocation (in Google MyAccount or the Home app) must be detected on app start and must purge the corresponding derived data.

### Decision 9 — Extend `ProviderExtensibilityBoundaryTest`; do not relax it

The guard protects a still-valid decision. It must be **extended** so that D.1 files may not hard-code *any* registered provider slug — not just `fake` — which closes the gap that would otherwise let `'google_home'` be written into the domain. Capability-based logic in those files remains permitted and is the intended pattern.

### Decision 10 — Matter and Tuya

- **Matter:** Google Home already exposes Matter devices present in the user's home, with Matter taking precedence over cloud-to-cloud analogs. A dedicated `MatterProvider` is **deferred** with no significant roadmap loss. To be revisited only if IXORA needs to *commission* hardware or to reach Matter devices not present in any Google structure.
- **Tuya:** postponed, not abandoned. Under this model Tuya Cloud would declare `device_discovery`, `state_read`, `interactive_execution`, `server_side_execution`, `scheduled_execution` — implementing `ProviderAdapter` unchanged, exactly as Home Assistant does. **This is the model's main validation: Tuya requires no new concept.** Tuya remains the architecturally cheaper answer whenever server-side scheduling for a given brand is a hard requirement.

### Decision 11 — Android-only for this release, without foreclosing iOS

The first implementation targets **Android only**. `front_vibes` has an established Android base, already performs native→JS bridging, and the Home SDK is Kotlin-first; restricting scope proves the architecture and the integration experience before the work is duplicated in Swift.

**iOS is explicitly out of scope for v1.6.0 — and the architecture must not foreclose it.** Concretely:

- No Android-specific concept may enter the domain. `back_vibes` must not learn about Android, Kotlin, Play Services or SDK versions; from the backend's point of view there is a provider whose execution happens on a client, not a provider that executes "on Android".
- The capability vocabulary (Decision 2) describes *where* execution happens, never *on which mobile OS*. There is no `android_execution` capability and there must never be one.
- The device-side result reporting contract (Decision 7) is platform-neutral: an iOS client must be able to satisfy it later without a second endpoint or a schema change.
- The intended future shape is one Google Home integration with two platform implementations behind it:

```
Google Home integration
├── Android implementation   (v1.6.0)
└── iOS implementation       [future — not scoped]
```

Platform-specific code is therefore confined to `front_vibes`' native layer. Any derived task that would push an Android-specific assumption into `back_vibes`, into the API contract, or into the capability vocabulary must stop and report instead.

---

## 6. Validation against current and future providers

| Provider | Adapter contract | Declared capabilities | New concepts required |
| --- | --- | --- | --- |
| Home Assistant | `ProviderAdapter` (unchanged) | discovery, state, interactive, server-side, scheduled | none |
| Google Home | none (device-side runtime) | discovery, state, interactive | nullable credentials; client-reported health/results |
| Tuya Cloud (future) | `ProviderAdapter` | discovery, state, interactive, server-side, scheduled | none |
| SmartThings / Hue / Govee cloud (future) | `ProviderAdapter` | as above, per platform | none |
| Alexa (future) | likely none server-side | discovery, interactive, possibly `automation_delegation` | none beyond this ADR |
| Matter direct (future) | undetermined | local/interactive | would need its own ADR |

The vocabulary is not Google-shaped: it distinguishes *where execution can happen*, which is the actual axis of variation across all six.

---

## 7. Kotlin Multiplatform — evidence only

**No migration is recommended or authorised by this ADR.** Evidence recorded for a future decision:

- The Home SDK is Kotlin-first (coroutines/`Flow`); Android bridge estimated at ~450–700 lines of Kotlin, concentrated in trait mapping rather than the bridge itself.
- iOS would require a parallel Swift implementation of the same mapping, plus App Attest (no simulator), App Groups and a MatterExtension — and `front_vibes` has no iOS project today.
- `front_vibes` has no custom Capacitor plugin and no Kotlin, though `MainActivity.java` already performs native→JS bridging, so the capability is not absent.
- Duplicated trait mapping across Kotlin and Swift is precisely the class of code KMP would share.

**Classification: moderate.** Enough to warrant revisiting if mobile-native integrations multiply; not enough to justify acting now, particularly while the app ships Android-only.

---

## 8. Consequences

**Positive**

- Real capability differences become explicit, declarative data instead of tribal knowledge.
- The domain gains no provider conditionals; the neutrality guard is strengthened rather than weakened.
- `ProviderAdapter`, `SceneActionJob`, the queue path and every Home Assistant behaviour remain untouched.
- Existing seams are reused: `skipped`, `scene_execution_id`, `ProviderDescriptor`, `GET /api/provider-types`, `ScheduleAutomationValidator`.
- Tuya, SmartThings and similar cloud providers require no new concept.
- Aligns with ADR-012: Google Home is an aggregator platform, which ADR-012 permits, unlike a brand-native Tuya integration.

**Negative**

- **A scheduled Vibe does not actuate Google Home devices.** This is a genuine product regression relative to a user's expectation and cannot be engineered away.
- Providers are no longer uniform; the frontend must render capability-derived states and warnings.
- A second execution path (device-side) now exists, with weaker guarantees than the queue: no server retries, no server-side timeout, results arriving late or never.
- Google-derived data needs an expiry mechanism that IXORA-owned data does not, inside a `devices` table shared with Home Assistant rows.
- Connection health for device-side providers depends on client reports and may be stale.

**Risks**

- Users may not internalise the scheduling limitation despite warnings, producing "my lights didn't turn on" reports. Mitigation: surface at configuration time, and in the execution record.
- Certification scope may exclude needed device types — discovered only in GH03, and outside IXORA's control.
- Device-side result reporting is a new untrusted input surface; it must be authorised and idempotent.
- Automation quotas would bind quickly if `automation_delegation` is adopted later — the design must not assume headroom.

**Technical debt accepted**

- Two execution models coexist with asymmetric guarantees.
- `ScheduleAutomationValidator`'s all-or-nothing semantics must be revised for per-action skipping.
- Telemetry loses the Queue Consumer span parent for device-side executions; the observability shape for that path is undefined by this ADR.

**Future work (not authorised here)**

- `automation_delegation` via the Automation API, if the scheduling gap proves unacceptable.
- `MatterProvider`, if commissioning or non-Google Matter reach is required.
- Tuya Cloud, per the re-entry triggers in §4.
- iOS support for the Google Home runtime.

---

## 9. Impact on downstream tasks

- **GH02 (Capacitor + Home SDK spike)** — unblocked and unchanged in shape. Add one acceptance requirement: the spike must confirm that consent state and device state can be *reported back* to the backend, since Decision 7 depends on it.
- **GH03 (certification, OAuth, retention)** — gains a hard requirement from Decision 8: it must produce the concrete boundary between Google-derived and IXORA-owned data, per column, and the proposed expiry mechanism.
- **GH04 (trait → capability mapping)** — unchanged, and reinforced: it maps **device** capabilities (ADR-033) only and must not reference provider execution capabilities, per the naming rule in Decision 2.
- **New work implied, not yet carded** (deliberately not created until this ADR is approved): decouple provider registry from adapter registry; make credentials nullable; add capability metadata to descriptors and the API; per-action skip outcome; capability-aware validation and UX warnings; device-side result reporting endpoint; extend the boundary test.

---

## 10. Decisions resolved by the PO (2026-09-06)

The three questions this ADR opened are closed. They are recorded here rather than deleted, so the reasoning remains auditable.

1. **Scheduling degradation — APPROVED.** A scheduled Vibe will not actuate Google Home devices in this release. Non-schedulable actions are skipped with an explicit outcome, consume no retry, raise no false failure alert, and do not prevent compatible actions (e.g. Home Assistant) from executing. The user is informed before confirming the schedule. This is a known and accepted limitation of the release, not a bug.
2. **Version numbering — RESOLVED as v1.6.0.** Google Home Integration ships as **v1.6.0**. v1.5.0 stays reserved for Analytics as recorded in v1.3.0 and v1.4.0-T06, and the Analytics plan is **not** altered to accommodate Google Home. Tuya remains **Deferred / Backlog** — not removed, not archived.
3. **Initial platform scope — CONFIRMED Android-only.** See Decision 11 for the constraint that keeps a future iOS implementation open.

---

## 11. Post-acceptance evidence — GH03a (2026-09-06)

Recorded after this ADR was accepted, from the GH03a investigation ([`specs/smart-home/google-home/access-gate.md`](../specs/smart-home/google-home/access-gate.md)). **The architectural decision is unchanged.** Option C stands; §5's decisions stand; this section corrects external constraints that were stated incorrectly or incompletely in §3, and records one favourable correction.

### A — Production registration is unavailable; development access is not

§3 implied that certification and OAuth verification are processes IXORA can begin. **That premise was wrong.** Per official documentation consulted in GH03a:

- **Developer Console registration is *not* required for development or testing** — verbatim: *"Google Home Developer Console registration is not required to test and use the Home APIs."*
- **Production registration/verification is not available.** Confirmed verbatim on two independent official pages: *"The Google Home Developer Console is not yet available for registration."* Parts of the official get-started flow remain marked **"Coming soon"** (device-type approval; Play Store launch).
- Consequently there is an **external blocker on release**, outside IXORA's control, with no published date. This ADR does not estimate one.
- **This does not block GH02.** The development spike is unaffected.

The distinction this section establishes, and which all derived work must respect:

| | Status |
| --- | --- |
| **Development access** | 🟢 Available today. No Console registration, no certification. Ceiling of 100 test users while unverified. |
| **Production verification** | 🔴 Unavailable. External dependency, no published date. |

Release posture that follows: *validate now, build reusable foundations, defer release-specific investment, and monitor the external gate separately.* Work whose only value appears once production access exists — certification submission, verification workflow, store/publishing work, Google-specific production hardening — is deferred rather than cancelled.

### B — SDK distribution is outside the standard channel

The Android Home APIs SDK is **not** part of Google's standard Maven distribution: *"The Home APIs in this open beta are not yet part of the standard libraries provided by Google for development."* The libraries must be downloaded and hosted locally (artifact `home.android.sdk_GHP_1_10_1`, in a GCS bucket of the `home-api-public-beta` project). GA-quality SDK, non-standard distribution channel.

Recorded as a **dependency-management, supply-chain and build-reproducibility concern, and a GH02 setup requirement** — deliberately **not** characterised as a blocker. GH02 determines the real impact and reports it.

### C — Device-type approval does not gate development (favourable correction)

§3 implied device-type certification could constrain the spike. It does not. An unverified app receives **all supported device types and all devices in the granted structure**; verification *restricts* that set to what was approved in the Console, rather than granting access. Certification is a production concern only.

**Four distinct processes must never be conflated** — §3 and derived cards must name which one they mean:

1. **Home APIs app verification** (OAuth brand verification for the app);
2. **Google Home device-type approval** (in the Developer Console, for Home APIs);
3. **Matter hardware certification** (Google states it "only certifies hardware devices and not, for example, apps, software, or IoT systems");
4. **Cloud-to-cloud integration certification** (for device manufacturers exposing devices *to* Google).

Only 1 and 2 apply to IXORA, and only for production.

---

## Sources

Code (verified 2026-09-06): `back_vibes/app/SmartHome/Contracts/ProviderAdapter.php`, `app/Models/ProviderConnection.php`, `app/SmartHome/ProviderDescriptorRegistry.php`, `app/SmartHome/DTOs/ProviderDescriptor.php`, `app/SmartHome/Services/VibeSmartHomeDispatchService.php`, `app/SmartHome/Validation/ScheduleAutomationValidator.php`, `app/Jobs/SmartHome/SceneActionJob.php`, `app/Console/Commands/DispatchDueSchedulesCommand.php`, `config/smart_home.php`, `tests/Unit/SmartHome/ProviderExtensibilityBoundaryTest.php`, `database/migrations/2026_06_14_000001_create_provider_connections_table.php`, `ixora-infra/opentofu/staging/app-api.tf`.

Google (verified 2026-09-06): [Home APIs overview](https://developers.home.google.com/apis) · [Android data model](https://developers.home.google.com/apis/android/data-model) · [Permissions](https://developers.home.google.com/apis/android/permissions) · [Automation API](https://developers.home.google.com/apis/android/automation) · [Android SDK](https://developers.home.google.com/apis/android/sdk) · [iOS SDK](https://developers.home.google.com/apis/ios/sdk) · [Policies](https://developers.home.google.com/policies) · [Quota management](https://developers.home.google.com/apis/android/quota-management) · [HomeGraph API](https://developers.home.google.com/reference/home-graph/rest) · [Nest Device Access](https://developers.google.com/nest/device-access/api)
