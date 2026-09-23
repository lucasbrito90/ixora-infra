# Canonical Smart Home Device Model — Specification

**Status:** Normative — living document, implements [ADR-037](../../decisions/ADR-037-canonical-smart-home-device-model.md) (**Accepted** 2026-09-08). This is the reference contract implementers code against; it evolves under the versioning rules in §9, not by silent edit.
**Contract version:** `csdm/v1` (not yet released as a standalone schema artifact — CSDM-01 produces it; see [Versioning and evolution](#versioning-and-evolution))
**Governing decision:** [ADR-037](../../decisions/ADR-037-canonical-smart-home-device-model.md), superseding [ADR-033](../../decisions/ADR-033-device-capabilities.md)'s capability shape.
**Audience:** `back_vibes` (capability derivation, validation, persistence), `front_vibes` (schema-driven UI, TypeScript types), the Google Home Android/Kotlin integration ([GH04](google-home/trait-capability-mapping.md)), and any future provider mapper (Tuya or otherwise).

This document and ADR-037 reference each other: **the ADR carries the architectural decisions and their justification; this spec carries the detailed contract, worked examples, and evolution rules** a implementer actually codes against.

---

## 1. Principle

> No provider defines Ixora's canonical semantics. Every provider mapper translates *to* this model on read, and *from* it on write.

```
Provider representation → Provider Mapper → Ixora Canonical Model
Ixora Canonical Command → Provider Mapper → Provider-specific command
```

Nothing downstream of a Provider Mapper — the domain, the API, `front_vibes`, Scenes, Vibes — may reference a provider-specific range, enum, trait name, or service name. If code outside a mapper needs to know a value is `0–255` or `0–254`, or that a trait is called `OnOffTrait`, the boundary has been violated.

---

## 2. Contract overview

### 2.1 Device

```
Device
  id: <Ixora surrogate key>       — internal identity; never a provider ID (unchanged, already correct)
  type: DeviceType                — unchanged (ADR-033/T15); orthogonal to this spec
  capabilities: Map<CapabilityId, Capability>
  state: DeviceState              — §2.5
  connectivity: "online" | "offline" | "unknown"   — unchanged DeviceStatus enum
  metadata: object                — provider-raw passthrough, boundary-only, never authoritative
```

### 2.2 Capability

```ts
interface Capability {
  id: CapabilityId;                 // canonical vocabulary — §3
  access: "read" | "write" | "read_write";
  operations: OperationId[];        // canonical operation names valid for this capability; [] for read-only
  constraints: Constraint | null;   // present only when an operation or the read value takes a typed value
}
```

`operations` and `constraints` are **independent axes**, and neither implies the other. `power` has operations (`on`/`off`/`toggle`) that take **no parameter**, yet still has a constraint (`{type: boolean}`) — the constraint describes the *shape of the capability's value* (what `state.values.power` and any future read return), not the shape of a command argument. `energy` has a constraint with **no operations at all** (`read`-only — nothing to command, but `{type: number, unit: kWh}` still describes what a read returns). `brightness.set` is the case where both align: the constraint describes both the readable value and the one parameter `set` accepts. `constraints: null` is reserved for a capability with no typed value in either direction — no ratified capability in §3 is actually null; it appears only in §8.3's illustrative `color` example, as an explicit placeholder for a constraint type this spec does not yet define (see §2.4).

### 2.3 Operation

An operation is a canonical verb scoped to a capability — `brightness.set`, `power.on`, `power.toggle`. Operations are **not** provider service names. A provider mapper decides, per operation, whether it has a native primitive or must compose one (see §7).

### 2.4 Constraint

```ts
type Constraint =
  | { type: "number"; min: number | null; max: number | null; step: number | null; unit: string }
  | { type: "enum"; allowed_values: string[] }
  | { type: "boolean" };
```

- **`min`/`max`/`step` are each independently nullable; `unit` is not.** `null` means "not known by the provider" and must never be filled with an invented value — a provider mapper that doesn't know a sensor's real range reports `null`, not a guess. `max: null` specifically also covers "no known upper bound" (e.g. cumulative energy — see §8.5), which is a form of "not known." `unit` stays mandatory unconditionally: a numeric value with no meaningful unit is evidence the capability needs a different shape, not evidence `unit` should be optional.
- **Trade-off:** when `min`/`max`/`step` are `null` on a capability whose `access` includes `write`, the validation pipeline (§4.1) cannot enforce that dimension — the corresponding check is skipped, not defaulted, and the value is still type-checked. This is expected and harmless for the `read`-only capabilities in this spec's catalog (`energy`, `current_temperature` — see §3), which never reach write validation at all. It is expected to be rare for `read_write` numeric capabilities (`target_temperature` normally has real, provider-reported bounds — §8.6), and is a disclosed, visible gap if it ever occurs, not a silent one.
- The union is **closed but extensible**: a new case (e.g. a structured color type) is a contract version bump, not a free-form addition by any single mapper — see §9.

### 2.5 DeviceState

Connectivity lives only on `Device` (§2.1) — `DeviceState` does not repeat it. An earlier draft of this spec duplicated `connectivity` here as well; that was a genuine redundancy, corrected so `Device.connectivity` is the single source of truth.

```ts
interface DeviceState {
  values: Partial<Record<CapabilityId, unknown>>;   // e.g. { power: true, brightness: 65 }
  read_at: string;                                   // ISO 8601 timestamp
}
```

`values` is keyed by the same `CapabilityId` vocabulary as `Capability` — a client that already knows a device's capabilities knows exactly which keys `values` can contain, with no separate state vocabulary to learn. A capability absent from `values` means "not read this cycle," not "unsupported" — support is determined by `capabilities`, never by presence in `values`. A consumer that needs both connectivity and functional state reads them from the same parent `Device` object — `Device.connectivity` and `Device.state.values` — never from two competing fields.

This spec does not mandate where or whether `DeviceState` is persisted. It only fixes its shape wherever it is produced (a provider mapper's read path) or consumed (a client displaying current state).

---

## 3. Canonical capability & operation catalog

Closed vocabulary. Adding an entry is a deliberate contract amendment (§9), never an ad hoc string from a provider mapper.

| Capability id | Access | Operations | Constraint shape | Status |
| --- | --- | --- | --- | --- |
| `power` | `read_write` | `on`, `off`, `toggle` | `{type: boolean}` — state value is `true`/`false` | **Ratified** |
| `brightness` | `read_write` | `set` | `{type: number, min: 0, max: 100, step: 1, unit: "percent"}` | **Ratified** |
| `energy` | `read` | — | `{type: number, min: 0, max: null, step: null, unit: "kWh"}` (step typically unknown — see §2.4) | **Ratified** |
| `current_temperature` | `read` | — | `{type: number, min: null, max: null, step: null, unit: "celsius"}` (bounds typically unknown — see §2.4) | **Ratified** |
| `target_temperature` | `read_write` | `set` | `{type: number, min, max, step, unit: "celsius"}` (device-reported bounds — real operational constraint) | **Ratified** |
| `hvac_mode` | `read_write` | `set` | `{type: enum, allowed_values: ["off","heat","cool","auto"]}` | **Ratified** |
| `color` | `read_write` | `set` | *not yet defined* — needs a struct constraint type beyond §2.4's union | **Provisional — see §8.3** |
| `color_temperature` | `read_write` | `set` | `{type: number, min, max, step, unit: "mired"}` (illustrative) | **Provisional — see §8.3** |

"Ratified" entries are decided by ADR-037 and safe to implement. "Provisional" entries are shown in §8.3 only to prove the model *can* represent them — neither is authorized for implementation before its own contract amendment fixes the exact constraint shape (color in particular needs a representation decision — RGB vs. HS vs. xy — this spec does not make that call).

---

## 4. Command contract

```ts
interface IxoraCommand {
  device_id: number;
  capability_id: CapabilityId;
  operation: OperationId;
  parameters?: { value: unknown };   // shape depends on the capability's constraint
}
```

### 4.1 Validation pipeline

```
1. Load device, resolve capability by capability_id.
     → capability_id not present on device            → REJECT (unsupported)
2. Check access permits the operation
     → access = "read" but operation requested          → REJECT (unsupported)
3. Check operation is declared for the capability
     → operation not in capability.operations           → REJECT (unsupported)
4. If the operation takes a parameter, validate parameters.value against capability.constraints
     → number:  type-check as numeric; min <= value (skip if min is null); value <= max (skip if max is null);
                value aligns to step (skip if step is null)
     → enum:    value ∈ allowed_values
     → boolean: value ∈ {true, false}
     → fails   → REJECT (invalid_parameter)
5. Only now: Provider Mapper translates the validated canonical command to a provider-specific call.
```

Step 4 is the fix for the confirmed pre-existing bug (ADR-037 Context §5): `{"brightness": 9999}` is rejected at step 4, before any provider mapper is invoked, regardless of which provider owns the device.

**Null constraint fields degrade, they never default.** A `null` `min`/`max`/`step` means that specific check is skipped — the value is still required to be the right primitive type (a number stays a number). This mostly affects `read`-only capabilities, which never reach step 4 for a write at all since no operation is ever requested against them; it is a real, disclosed reduction in enforcement only in the rare case a `read_write` numeric capability has no reported bounds (§2.4).

### 4.2 Worked validation example

```
Command: { device_id: 42, capability_id: "brightness", operation: "set", parameters: { value: 9999 } }
  1. capability "brightness" present on device 42 → continue
  2. access = read_write, "set" permitted → continue
  3. "set" ∈ operations → continue
  4. constraint = {type: number, min: 0, max: 100, step: 1}; 9999 > 100 → REJECT
```

---

## 5. Provider Mapper contract

Every provider implements exactly one mapper, in its own language (`HomeAssistantAdapter` in PHP, the Google Home integration layer in Kotlin), satisfying two directions:

**Read direction** (provider → canonical): for each device, produce `capabilities: Map<CapabilityId, Capability>` and, on demand, `state: DeviceState`, using only ids/operations/constraint types from §3–§4 — never a provider-native key, range, or enum value.

**Write direction** (canonical → provider): given a validated `IxoraCommand`, translate `(capability_id, operation, parameters)` into whatever the provider's own API expects, including any unit/range conversion (§7).

A mapper **may** implement an operation compositionally when the provider has no native primitive for it (e.g. `power.toggle` on Google Home — read `power`, invert, call the provider's `on`/`off`). This is a full, valid implementation of the canonical operation, not a workaround — see ADR-037 §3 and the worked example in §7.2.

---

## 6. Schema-driven Frontend

**Principle:** `front_vibes` must never contain logic that branches on which provider a device belongs to, in order to decide what controls to show. The UI is derived entirely from the canonical `Capability` objects the API returns for that device — the same contract every provider mapper produces.

This is not a new principle invented here — `front_vibes` has been schema-driven for provider *identity* since v1.4.0-T25 (`GET /api/provider-types` drives the connection form with no hardcoded provider name). This spec extends the same discipline to device *capabilities*.

**What the backend sends is semantics, never UI.** A `Capability` object carries capability id, operations, access, constraints (including units), and — separately — current state. It never carries a component name, a widget type, or any rendering hint. The frontend owns 100% of the decision about *how* to represent a capability visually; the backend owns 100% of the decision about *what* the capability means and *what values are valid*.

### 6.1 Derivation examples

```yaml
brightness:
  operations: [set]
  constraints:
    type: number
    min: 0
    max: 100
    unit: percent
    step: 1
```
→ the frontend *may* render this as a slider (0–100, one tick per `step`), a numeric stepper, or any other control that can express "pick a number in [min, max] by step" — the schema does not mandate which; it only guarantees the range/unit/step needed to build any of them correctly.

```yaml
color:
  operations: [set]
```
→ the frontend *may* render a color picker. (Provisional per §3/§8.3 — shown here only to illustrate the derivation principle, not as an implementable contract yet.)

```yaml
target_temperature:
  access: read_write
  operations: [set]
  constraints:
    type: number
    min: 5
    max: 35
    unit: celsius
```
→ the frontend *may* render a temperature control (stepper, dial, slider) scaled to `[min, max]` in the given unit.

```yaml
hvac_mode:
  operations: [set]
  constraints:
    type: enum
    allowed_values: [off, heat, cool, auto]
```
→ the frontend *may* render a select or segmented control listing `allowed_values`.

### 6.2 Rule of thumb for new UI

If a new `front_vibes` component needs to know the name "Home Assistant," "Google Home," or "Tuya" — or a provider-native range like `0–255` — to decide what to render or what value to send, that is a defect against this spec, not a acceptable shortcut. The only place a provider name may appear in the UI is as a **display attribute** ("this device came from Home Assistant"), exactly as already established by v1.4.0-T26 — never as a branch controlling behavior.

---

## 7. Worked provider mapper examples

### 7.0 Home Assistant — power

Read: HA's entity `state` string (`"on"` / `"off"`) → canonical `power: true` / `false`. Write: canonical `power.on`/`power.off` → HA services `light.turn_on`/`light.turn_off`; `power.toggle` → native `light.toggle`. This is the one conversion the HA mapper must perform that the Google mapper (§7.2) does not need — HA's native representation is a string, Google's is already a boolean.

### 7.1 Home Assistant — brightness

Read: HA attribute `brightness` (0–255, integer) → `brightness: round(raw / 255 * 100)`.
Write: canonical `brightness.set(65)` → HA service call payload `{"brightness": round(65 / 100 * 255)}` = `{"brightness": 166}`.

### 7.2 Google Home — power.toggle (no native command)

Canonical command: `{capability_id: "power", operation: "toggle"}`.
Mapper composition (Kotlin, per GH04's confirmed finding): read `standardTraits.onOff.onOff` (already a Kotlin `Boolean` — no string conversion needed) → invert → call `standardTraits.onOff.on()` or `.off()` accordingly. The canonical command is satisfied; the provider primitive used to satisfy it is an implementation detail invisible above the mapper.

### 7.3 Google Home — brightness

Read: `LevelControl.currentLevel` (0–254) → `brightness: round(raw / 254 * 100)`.
Write: canonical `brightness.set(65)` → `moveToLevel(round(65 / 100 * 254))` = `moveToLevel(165)`.

---

## 8. Full worked device payloads

Illustrative `GET /api/devices/{id}`-shaped payloads — field names for the API envelope are indicative, not a route contract fixed by this spec.

### 8.1 Basic light (on/off only)

```json
{
  "id": 101,
  "type": "lighting",
  "connectivity": "online",
  "capabilities": {
    "power": { "access": "read_write", "operations": ["on", "off", "toggle"], "constraints": { "type": "boolean" } }
  },
  "state": { "values": { "power": true }, "read_at": "2026-09-08T12:00:00Z" }
}
```

### 8.2 Dimmable light

```json
{
  "id": 102,
  "type": "lighting",
  "connectivity": "online",
  "capabilities": {
    "power": { "access": "read_write", "operations": ["on", "off", "toggle"], "constraints": { "type": "boolean" } },
    "brightness": {
      "access": "read_write",
      "operations": ["set"],
      "constraints": { "type": "number", "min": 0, "max": 100, "step": 1, "unit": "percent" }
    }
  },
  "state": { "values": { "power": true, "brightness": 65 }, "read_at": "2026-09-08T12:00:00Z" }
}
```

### 8.3 RGB / color-temperature light — **illustrative, provisional (§3)**

```json
{
  "id": 103,
  "type": "lighting",
  "connectivity": "online",
  "capabilities": {
    "power": { "access": "read_write", "operations": ["on", "off", "toggle"], "constraints": { "type": "boolean" } },
    "brightness": {
      "access": "read_write", "operations": ["set"],
      "constraints": { "type": "number", "min": 0, "max": 100, "step": 1, "unit": "percent" }
    },
    "color_temperature": {
      "access": "read_write", "operations": ["set"],
      "constraints": { "type": "number", "min": 153, "max": 500, "step": 1, "unit": "mired" }
    },
    "color": {
      "access": "read_write", "operations": ["set"],
      "constraints": null
    }
  },
  "state": {
    "values": { "power": true, "brightness": 80, "color_temperature": 300 },
    "read_at": "2026-09-08T12:00:00Z"
  }
}
```
`color`'s `constraints: null` here is a placeholder, not a decision — §2.4's union has no struct-typed case yet. This payload exists to show the *shape* of the model accommodating a fourth, fifth capability on the same device without any new top-level concept, not to authorize implementing color today.

### 8.4 Smart plug

```json
{
  "id": 104,
  "type": "switchable",
  "connectivity": "online",
  "capabilities": {
    "power": { "access": "read_write", "operations": ["on", "off", "toggle"], "constraints": { "type": "boolean" } }
  },
  "state": { "values": { "power": false }, "read_at": "2026-09-08T12:00:00Z" }
}
```

### 8.5 Plug with energy measurement

```json
{
  "id": 105,
  "type": "switchable",
  "connectivity": "online",
  "capabilities": {
    "power": { "access": "read_write", "operations": ["on", "off", "toggle"], "constraints": { "type": "boolean" } },
    "energy": {
      "access": "read",
      "operations": [],
      "constraints": { "type": "number", "min": 0, "max": null, "step": null, "unit": "kWh" }
    }
  },
  "state": { "values": { "power": true, "energy": 12.34 }, "read_at": "2026-09-08T12:00:00Z" }
}
```
`energy.constraints.step` is `null` — the plug reports cumulative energy in kWh with no known resolution; `min: 0`/`unit: "kWh"` are known, `max`/`step` are not, and neither is invented (§2.4).

### 8.6 Thermostat

```json
{
  "id": 106,
  "type": "other",
  "connectivity": "online",
  "capabilities": {
    "current_temperature": {
      "access": "read", "operations": [],
      "constraints": { "type": "number", "min": null, "max": null, "step": null, "unit": "celsius" }
    },
    "target_temperature": {
      "access": "read_write", "operations": ["set"],
      "constraints": { "type": "number", "min": 5, "max": 35, "step": 0.5, "unit": "celsius" }
    },
    "hvac_mode": {
      "access": "read_write", "operations": ["set"],
      "constraints": { "type": "enum", "allowed_values": ["off", "heat", "cool", "auto"] }
    }
  },
  "state": {
    "values": { "current_temperature": 21.5, "target_temperature": 22.0, "hvac_mode": "heat" },
    "read_at": "2026-09-08T12:00:00Z"
  }
}
```
`current_temperature.constraints` has `min`/`max`/`step` all `null` — a thermostat's sensor typically has no documented range — while `unit: "celsius"` is still known. `target_temperature` is the contrasting case: a real, device-enforced range, populated because it genuinely exists. This is the exact distinction §2.4's nullable bounds exist to make representable, applied to the two numeric capabilities on the same device.

---

## 9. Versioning and evolution

The contract (this spec + its JSON Schema artifact, once CSDM-01 produces one) is versioned independently of application releases, `csdm/v<major>.<minor>`.

**Minor version bump — additive, no consumer breakage required:**
- A new capability id added to §3's catalog.
- A new operation added to an existing capability.
- A new optional field on `Capability`, `Constraint`, or `DeviceState`.

**Major version bump — requires the dual-read compatibility path (ADR-037 §8, owned by CSDM-07):**
- A change to an existing capability's constraint shape (e.g. changing brightness's canonical unit or range).
- A new `Constraint` type-union case (e.g. a struct color type) that existing consumers cannot ignore.
- Any change to the meaning of an existing field.

**How to propose a new capability (e.g. unlocking §8.3's `color`):** write a contract amendment (a short ADR-037 addendum or, if the change is structural — like adding a new `Constraint` case — a full ADR amendment) that fixes: the exact capability id, its access, its operation(s), and its constraint's exact shape and unit. Only after that amendment is accepted does a provider mapper implement it. No mapper may introduce a capability id, operation, or constraint shape ahead of a contract decision — that is precisely the failure mode (a provider's shape becoming canonical by default) this whole model exists to prevent.

`contract_version` (or an equivalent schema `$id`) should accompany transmitted/persisted capability and state data so any consumer — backend, `front_vibes`, the Kotlin layer, or a future provider — can detect which contract version it is reading, particularly during a major-version transition window.

---

## 10. Relationship to other documents

- [ADR-037](../../decisions/ADR-037-canonical-smart-home-device-model.md) — the architectural decision and its justification (why this shape, why brightness is 0–100/percent, why no microservice). This spec implements what the ADR decided; it does not re-litigate it.
- [ADR-033](../../decisions/ADR-033-device-capabilities.md) — the superseded capability shape; kept for historical reference and for understanding the legacy data this spec's consumers must read during the transition window (§9, ADR-037 §8).
- [`canonical-device-model-audit.md`](canonical-device-model-audit.md) — the code audit that surfaced the gaps this model closes.
- [GH04 — Google Home trait/device-type mapping](google-home/trait-capability-mapping.md) — the first real provider mapper analysis this spec's shape is validated against (brightness range mismatch, missing native toggle).
