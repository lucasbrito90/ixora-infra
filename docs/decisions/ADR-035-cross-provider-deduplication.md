# ADR-035: Cross-provider device deduplication policy (v1.4.0)

## Status

**Accepted** — governs **cross-provider device deduplication** for release v1.4.0. Addendum to [ADR-014](ADR-014-device-abstraction-and-deduplication.md); supersedes ADR-014's open note on cross-provider merge for the v1.4.0 scope. Reads in conjunction with [ADR-032](ADR-032-multi-provider-scope.md) decision C.

## Date

2026-09-03

---

## ⚠ T19 CANCELLED

**T19 (cross-provider duplicate detection implementation) is cancelled for v1.4.0.**

This is a scope change for the release. The justification is given in full under Decision 2 below. Summary: there is no physical identity signal available in the stack today, and the only candidate heuristic (name + type) produces near-100% false positives for the primary multi-connection scenario that ADR-032 decision C enables. Implementing detection with that signal produces more UX noise than value.

---

## Context

[ADR-014](ADR-014-device-abstraction-and-deduplication.md) deferred cross-provider device deduplication to a future phase ("not required in MVP"). [ADR-032](ADR-032-multi-provider-scope.md) decision C removed the `UNIQUE (user_id, provider)` constraint on `provider_connections`, making it explicitly possible for a user to have multiple connections of the same provider slug (e.g. two Home Assistant instances: home + office). This permanently breaks the historical functional equivalence between ADR-014's triple key `(user_id, provider, provider_device_id)` and the live connection-scoped key `UNIQUE (provider_connection_id, provider_device_id)`.

**The live deduplication key is `(provider_connection_id, provider_device_id)` and remains authoritative for v1.4.0.** Two devices that share the same `provider_device_id` string but belong to different `provider_connection_id` values are, by design, distinct IXORA device rows — one per connection.

In this context, "duplicity" in this ADR always means: the same **physical** piece of hardware appearing through two or more distinct provider connections. It is never about the same connection.

Three pre-existing audits establish the facts this ADR must not reopen:

| Report | Relevant finding |
| --- | --- |
| [T01 — `current-state.md`](../specs/smart-home/multi-provider/current-state.md) | `HomeAssistantAdapter::mapDevice()` collects: `domain`, `raw_state`, `supported_features` (conditional), `device_class` (conditional). No hardware identifier (MAC, serial, manufacturer UUID) is collected or stored anywhere in the stack. `ProviderDevice` DTO fields: `provider_device_id`, `name`, `type`, `status`, `metadata`, `last_seen_at` — no hardware identity field. |
| [ADR-032](ADR-032-multi-provider-scope.md) decision C | Removing `uq_provider_connections_user_provider` enables multi-instance HA (home + office). Same-provider, multi-connection is the primary v1.4.0 multi-connection use case. |
| [ADR-014](ADR-014-device-abstraction-and-deduplication.md) closing note | "When cross-provider device merge is required, create a new ADR extending this decision with the merge key strategy (e.g. MAC address, Matter device ID)." |

---

## Decision

### 1 — Available identity signals (evidence-based)

**No signal of physical hardware identity exists anywhere in the stack today.**

The following signals were explicitly considered and rejected as identity evidence:

| Signal | Source | Verdict | Reason |
| --- | --- | --- | --- |
| `provider_device_id` | `ProviderDevice.php:23`; HA `entity_id` e.g. `light.living_room` | **Not physical identity** | Provider-internal identifier. If a bulb is removed from Home Assistant and re-added, it may receive a different `entity_id`. Identical `entity_id` strings across two HA connections designate two legitimate, independent device registrations (ADR-032 decision C). |
| `name` | `ProviderDevice.php:24`; sourced from HA `friendly_name` attribute (`HomeAssistantAdapter.php:271-275`) | **Not reliable** | User-defined. Different physical devices may share the same name intentionally (e.g. "Kitchen Light" in home HA and "Kitchen Light" in office HA). Identical names are expected and common in multi-instance deployments — they are not evidence of the same physical device. |
| `type` | `ProviderDevice.php:25`; receives the HA domain string (`HomeAssistantAdapter.php:276`) | **Category, not identity** | Classifies device category (`light`, `switch`, `media_player`, …). Shared by many distinct physical devices. |
| `metadata.domain` | `HomeAssistantAdapter.php:259-260` | **Redundant with `type`** | Derived from `entity_id` via `domainFor()`; identical semantic to `type`. Not identity. |
| `metadata.raw_state` | `HomeAssistantAdapter.php:260` | **State snapshot** | Transient operational value. Not identity. |
| `metadata.supported_features` | `HomeAssistantAdapter.php:263-265` | **Capability bitmask** | Present only when key exists in HA attributes. A bitmask shared by an entire device class (e.g. all color lights return the same value). Not identity. |
| `metadata.device_class` | `HomeAssistantAdapter.php:267-269` | **Sub-category** | Present only when key exists in HA attributes. Narrows the device category (e.g. `motion` within `binary_sensor`). Not identity. |
| MAC / serial / manufacturer UUID / Matter fabric ID | — | **Not collected** | No field in `ProviderDevice` (`ProviderDevice.php:22-29`). No attribute read in `mapDevice()` (`HomeAssistantAdapter.php:253-280`). Absent from `devices` schema (`2026_06_14_000002_harden_devices_table.php:39-47`). Not available in the stack today. |

**Conclusion: there is no physical identity signal available in the stack today.** This conclusion is grounded in code evidence, not assumption.

---

### 2 — Heuristic detection: T19 cancelled

A name + type matching heuristic was evaluated as the only candidate signal for duplicate *detection* (not merge). It is rejected, and **T19 is cancelled**.

#### The candidate heuristic

Two devices belonging to the same user, on different `provider_connection_id` values, with:
- identical `name` after case-insensitive trim, and
- identical `type` (normalized vocabulary per T15)

would be flagged as possible duplicates.

#### Why it is cancelled

**1. Near-100% false positive rate for the primary v1.4.0 use case.**

ADR-032 decision C's primary motivation is enabling a user to connect two Home Assistant instances (home + office). A user with two HA instances will have many devices with identical names and types — "Living Room Light", "Kitchen Switch", "TV" — on both connections. Every such pair satisfies the heuristic. They are not duplicates: they are distinct physical devices in different locations. The heuristic signals "possible duplicate" for every well-named device in a two-instance setup.

No cross-provider adapters (Tuya, Hue, Google Home) ship in v1.4.0 — only Home Assistant and the fake test provider (which exists exclusively in `local`/`testing` environments per ADR-032 decision A). The only real multi-connection scenario in v1.4.0 is multiple HA instances, which is precisely the scenario that produces near-100% false positives.

**2. No genuine true positive is reachable in v1.4.0.**

A genuine true positive would require: the same physical device accessible through two real provider integrations simultaneously. v1.4.0 ships exactly one production provider (Home Assistant). The fake adapter is not a real provider of real devices. There is no runtime context in this release where a genuine physical duplicate would be reachable.

**3. Noise without benefit.**

Signaling that is wrong nearly every time trains users to ignore or dismiss it. A "possible duplicate" flag that fires across every device in a home + office deployment creates UX confusion, support load, and implementation cost (T19) with zero decision support value. The PO decision (below) establishes that sinking effort into a signal that cannot distinguish duplicates from legitimate multi-location setups is not warranted.

**T19 is therefore cancelled for v1.4.0.** No `possible_duplicate` field is added to `devices`. No candidate-duplicate relation table is created. No API surface change is made for duplicate signaling.

If a future release introduces a physical identity signal (see Decision 4), T19 can be re-scoped as T19-v2 against that ADR — starting fresh, not resuming the v1.4.0 card.

---

### 3 — No-merge policy (PO decision — register, not reopen)

**No automatic merge of device records, for any reason, in v1.4.0.**

This is a PO decision. Two device rows are merged automatically only when there is *strong technical evidence* that they represent the same physical equipment (criterion defined in Decision 4). No heuristic based on name, type, domain, device class, or any combination of soft attributes meets that bar. This ADR registers the policy; T07 does not reopen it.

Operationally: the `devices` table unique key `UNIQUE (provider_connection_id, provider_device_id)` (`2026_06_14_000002_harden_devices_table.php:98-101`) is unchanged. No migration alters `devices` schema in this ADR or as a consequence of it.

---

### 4 — Strong evidence criterion and future extension point

For a future release to justify automatic device merge, the following criterion must be met:

> **Two IXORA `devices` rows may be merged automatically if and only if both rows carry the same non-null `hardware_id` value, where `hardware_id` is a hardware-level identifier (MAC address, serial number, Matter fabric ID, or manufacturer-issued UUID) reported by the provider adapter's API and mapped explicitly into the `ProviderDevice` DTO.**

"Same `provider_device_id`" does not qualify. "Same name + type" does not qualify. Only a hardware-level identifier, independently reachable by two different provider adapters, qualifies.

#### Extension point in `ProviderDevice` DTO

When a future provider API exposes a hardware identifier, the `ProviderDevice` DTO (`back_vibes/app/SmartHome/DTOs/ProviderDevice.php`) gains one optional field:

```php
public readonly ?string $hardware_id,   // MAC, serial, Matter fabric ID, or manufacturer UUID
                                         // null when provider does not expose a hardware identifier
```

Adding this field is a **non-breaking, additive change**: existing adapters (including `HomeAssistantAdapter`) set `hardware_id: null`; the sync service stores it in a new nullable `devices.hardware_id` column (added by the future ADR's migration); the merge logic checks `hardware_id IS NOT NULL AND hardware_id = ?`. No data from v1.4.0 device rows is invalidated — they remain as distinct rows with `hardware_id = null`.

**No migration, no new column, no DTO change is made in v1.4.0.** This section is a forward-compatibility specification only.

---

### 5 — Execution behavior of existing device rows

`SceneActionJob` resolves a device by its IXORA `device.id` (via `scene_actions.device_id` FK) and dispatches the provider action through the resolved adapter. It has no awareness of whether any other device row shares a name, type, or future `hardware_id` with the target device.

**No device row is treated differently because another row might represent the same physical equipment.** SceneActions on any device — including one that a future dedup pass might identify as a duplicate — execute exactly as any other action, with no altered routing, skipping, or priority. This behavior is unchanged by this ADR.

---

## Consequences

### Positive

| Outcome | Why it matters |
| --- | --- |
| **No UX confusion from false duplicate flags** | The name+type heuristic would have fired constantly for multi-instance HA users — the primary v1.4.0 scenario. Cancelling T19 avoids that noise. |
| **No accidental data loss** | With no merge logic, no device row is silently removed or reassigned. SceneActions remain stable. |
| **Extension point is defined** | When a real hardware identifier becomes available, the future ADR has a concrete contract (`hardware_id` field + nullable column) that requires no retrofitting of v1.4.0 rows. |
| **ADR-014 debt addressed** | ADR-014's closing note and the existing divergence from its triple key are now formally resolved: connection-scoped key is canonical; cross-provider merge awaits a hardware-identity signal. |

### Negative / tradeoffs

| Tradeoff | Impact |
| --- | --- |
| **No duplicate visibility in v1.4.0** | A user who accidentally syncs the same physical device through two HA connections sees it twice in the Devices tab. Acceptable: this is the same behavior as today, and the user has full control over connections. |
| **T19 removed from release scope** | Any product expectation of duplicate detection in v1.4.0 must be revised. The cancellation reason is documented here with the same evidentiary standard that an implementation decision would require. |
| **Hardware ID collection deferred** | Requires a future investigation of what each provider API exposes, an ADR, and a `ProviderAdapter` contract change. Non-trivial but low-urgency. |

---

## Alternatives considered

| Alternative | Why not chosen |
| --- | --- |
| **Implement name + type heuristic with explicit "high false positive" disclaimer** | The false positive rate for multi-instance HA (the primary v1.4.0 scenario) approaches 100% — not "high", effectively certain. Implementing signal that is wrong by design creates more harm than value. |
| **Scope heuristic to cross-provider-slug only (exclude same-slug connections)** | No cross-provider slugs ship in v1.4.0 production. The heuristic would have zero runtime instances to evaluate. Shipping dead code for zero benefit. |
| **Add `hardware_id` to ProviderDevice now, leave it null for HA** | Premature: introduces a column migration and DTO change with no current data to fill it. The extension point in Decision 4 specifies exactly what to do when a provider exposes the signal — no scaffolding needed before then. |
| **Revert device dedupe key to `(user_id, provider, provider_device_id)`** | Explicitly rejected by ADR-032 decision C. Not reconsidered here. |

---

## Related docs

| Document | Relationship |
| --- | --- |
| [ADR-014](ADR-014-device-abstraction-and-deduplication.md) | Device registry and original dedupe policy — this ADR closes its cross-provider merge deferral for v1.4.0 |
| [ADR-032](ADR-032-multi-provider-scope.md) decision C | Authoritative dedupe key `(provider_connection_id, provider_device_id)`; removal of `uq_provider_connections_user_provider`; T18/T19 governing rule |
| [T01 — `current-state.md`](../specs/smart-home/multi-provider/current-state.md) | Runtime inventory confirming absence of hardware identifiers in DTO and adapter |
| [ADR-012](ADR-012-smart-home-provider-strategy.md) | Provider adapter strategy — no brand-native integrations |
| [ADR-015](ADR-015-vibe-device-action-architecture.md) | Vibe device actions reference IXORA `device.id` — stable across this ADR |
| [ADR-016](ADR-016-smart-home-async-execution.md) | `SceneActionJob` execution — behavior unchanged for all device rows |
