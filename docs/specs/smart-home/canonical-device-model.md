# Canonical Smart Home Device Model — Specification

**Status:** Draft — living document, tracks [ADR-037](../../decisions/ADR-037-canonical-smart-home-device-model.md) (currently Proposed). This spec becomes normative once ADR-037 is Accepted; until then it documents the contract the ADR decides, in implementation-ready detail the ADR itself does not carry.
**Contract version:** `csdm/v1` (unreleased — see [Versioning and evolution](#versioning-and-evolution))
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

`operations` and `constraints` are **independent axes**. A capability may have operations with no constraint (`power.toggle` takes no parameter), a constraint with no operations (`energy`, read-only, still needs `{type: number, unit: kWh}` to describe the *readable* value's shape), or both (`brightness.set` needs the constraint to know what values `set` accepts).

### 2.3 Operation

An operation is a canonical verb scoped to a capability — `brightness.set`, `power.on`, `power.toggle`. Operations are **not** provider service names. A provider mapper decides, per operation, whether it has a native primitive or must compose one (see §7).

### 2.4 Constraint

```ts
type Constraint =
  | { type: "number"; min: number; max: number | null; step: number; unit: string }
  | { type: "enum"; allowed_values: string[] }
  | { type: "boolean" };
```

- `max: null` is valid and means "no known upper bound" (e.g. cumulative energy — see §8.5).
- `unit` is required on every `number` constraint. There is no "unitless number" — if a value has no natural unit, that itself is a modeling decision to make explicit (e.g. `unit: "count"`), not an empty string.
- The union is **closed but extensible**: a new case (e.g. a structured color type) is a contract version bump, not a free-form addition by any single mapper — see §9 and §10.5.

### 2.5 DeviceState

```ts
interface DeviceState {
  connectivity: "online" | "offline" | "unknown";
  values: Partial<Record<CapabilityId, unknown>>;   // e.g. { power: "on", brightness: 65 }
  read_at: string;                                   // ISO 8601 timestamp
}
```

`values` is keyed by the same `CapabilityId` vocabulary as `Capability` — a client that already knows a device's capabilities knows exactly which keys `values` can contain, with no separate state vocabulary to learn. A capability absent from `values` means "not read this cycle," not "unsupported" — support is determined by `capabilities`, never by presence in `values`.

This spec does not mandate where or whether `DeviceState` is persisted. It only fixes its shape wherever it is produced (a provider mapper's read path) or consumed (a client displaying current state).

---

## 3. Canonical capability & operation catalog

Closed vocabulary. Adding an entry is a deliberate contract amendment (§9), never an ad hoc string from a provider mapper.

| Capability id | Access | Operations | Constraint shape | Status |
| --- | --- | --- | --- | --- |
| `power` | `read_write` | `on`, `off`, `toggle` | none (boolean-shaped by convention; state value is `"on"`/`"off"`) | **Ratified** |
| `brightness` | `read_write` | `set` | `{type: number, min: 0, max: 100, step: 1, unit: "percent"}` | **Ratified** |
| `energy` | `read` | — | `{type: number, min: 0, max: null, step: 0.01, unit: "kWh"}` | **Ratified** |
| `current_temperature` | `read` | — | `{type: number, min, max, step, unit: "celsius"}` (device-reported bounds) | **Ratified** |
| `target_temperature` | `read_write` | `set` | `{type: number, min, max, step, unit: "celsius"}` | **Ratified** |
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
     → number:  min <= value <= max (if max non-null), value aligns to step
     → enum:    value ∈ allowed_values
     → boolean: value ∈ {true, false}
     → fails   → REJECT (invalid_parameter)
5. Only now: Provider Mapper translates the validated canonical command to a provider-specific call.
```

Step 4 is the fix for the confirmed pre-existing bug (ADR-037 Context §5): `{"brightness": 9999}` is rejected at step 4, before any provider mapper is invoked, regardless of which provider owns the device.

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

### 7.1 Home Assistant — brightness

Read: HA attribute `brightness` (0–255, integer) → `brightness: round(raw / 255 * 100)`.
Write: canonical `brightness.set(65)` → HA service call payload `{"brightness": round(65 / 100 * 255)}` = `{"brightness": 166}`.

### 7.2 Google Home — power.toggle (no native command)

Canonical command: `{capability_id: "power", operation: "toggle"}`.
Mapper composition (Kotlin, per GH04's confirmed finding): read `standardTraits.onOff.onOff` (current boolean) → invert → call `standardTraits.onOff.on()` or `.off()` accordingly. The canonical command is satisfied; the provider primitive used to satisfy it is an implementation detail invisible above the mapper.

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
  "capabilities": {
    "power": { "access": "read_write", "operations": ["on", "off", "toggle"], "constraints": null }
  },
  "state": { "connectivity": "online", "values": { "power": "on" }, "read_at": "2026-09-08T12:00:00Z" }
}
```

### 8.2 Dimmable light

```json
{
  "id": 102,
  "type": "lighting",
  "capabilities": {
    "power": { "access": "read_write", "operations": ["on", "off", "toggle"], "constraints": null },
    "brightness": {
      "access": "read_write",
      "operations": ["set"],
      "constraints": { "type": "number", "min": 0, "max": 100, "step": 1, "unit": "percent" }
    }
  },
  "state": { "connectivity": "online", "values": { "power": "on", "brightness": 65 }, "read_at": "2026-09-08T12:00:00Z" }
}
```

### 8.3 RGB / color-temperature light — **illustrative, provisional (§3)**

```json
{
  "id": 103,
  "type": "lighting",
  "capabilities": {
    "power": { "access": "read_write", "operations": ["on", "off", "toggle"], "constraints": null },
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
    "connectivity": "online",
    "values": { "power": "on", "brightness": 80, "color_temperature": 300 },
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
  "capabilities": {
    "power": { "access": "read_write", "operations": ["on", "off", "toggle"], "constraints": null }
  },
  "state": { "connectivity": "online", "values": { "power": "off" }, "read_at": "2026-09-08T12:00:00Z" }
}
```

### 8.5 Plug with energy measurement

```json
{
  "id": 105,
  "type": "switchable",
  "capabilities": {
    "power": { "access": "read_write", "operations": ["on", "off", "toggle"], "constraints": null },
    "energy": {
      "access": "read",
      "operations": [],
      "constraints": { "type": "number", "min": 0, "max": null, "step": 0.01, "unit": "kWh" }
    }
  },
  "state": { "connectivity": "online", "values": { "power": "on", "energy": 12.34 }, "read_at": "2026-09-08T12:00:00Z" }
}
```

### 8.6 Thermostat

```json
{
  "id": 106,
  "type": "other",
  "capabilities": {
    "current_temperature": {
      "access": "read", "operations": [],
      "constraints": { "type": "number", "min": -20, "max": 60, "step": 0.1, "unit": "celsius" }
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
    "connectivity": "online",
    "values": { "current_temperature": 21.5, "target_temperature": 22.0, "hvac_mode": "heat" },
    "read_at": "2026-09-08T12:00:00Z"
  }
}
```

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
