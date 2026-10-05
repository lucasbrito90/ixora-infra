# Smart Home Capability Governance — CAT-01 Reference

**Status:** Normative  
**Date:** 2026-10-04  
**Governing ADRs:** [ADR-037](../../decisions/ADR-037-canonical-smart-home-device-model.md), [ADR-045](../../decisions/ADR-045-canonical-provider-model.md)  
**Produced by:** CAT-01 (Smart Home Capability / Device Type Governance)  
**Consumed by:** DEV-01 (device state pipeline), BFF/device model, any future capability amendment

This document resolves four modeling questions left open after the CSDM-01–07 track closed. It serves as the normative reference for DEV-01 and for any work that touches the CSDM capability catalog. It does not implement DEV-01, does not alter the Provider/Connection architecture of ADR-045/PRV-01, and does not change any code.

---

## 1. Ratified capabilities — implementable now

These six capabilities are fully decided, coded in `CapabilityId.php`, `CapabilityCatalog.php`, the JSON Schema (`capability.v1.schema.json`), and ratified in `canonical-device-model.md §3`. They are the only capabilities DEV-01 may read, validate, or display.

| Capability id | Access | Operations | Constraint shape | Code references |
| --- | --- | --- | --- | --- |
| `power` | `read_write` | `on`, `off`, `toggle` | `{type: boolean}` | `CapabilityId::Power`, `Operation::On/Off/Toggle` |
| `brightness` | `read_write` | `set` | `{type: number, min: 0, max: 100, step: 1, unit: "percent"}` — fixed by ADR-037 §5 | `CapabilityId::Brightness`, `CapabilityCatalog::canonicalBrightnessConstraint()` |
| `energy` | `read` | — | `{type: number, min: 0, max: null, step: null, unit: "kWh"}` — bounds unknown | `CapabilityId::Energy` |
| `current_temperature` | `read` | — | `{type: number, min: null, max: null, step: null, unit: "celsius"}` — bounds unknown (see §2) | `CapabilityId::CurrentTemperature` |
| `target_temperature` | `read_write` | `set` | `{type: number, min, max, step, unit: "celsius"}` — device-reported bounds | `CapabilityId::TargetTemperature` |
| `hvac_mode` | `read_write` | `set` | `{type: enum, allowed_values: ["off","heat","cool","auto"]}` | `CapabilityId::HvacMode` |

**Rule:** any code that branches on a capability id not in this table is operating outside the ratified vocabulary. No mapper, domain service, or UI component may introduce a new capability id ahead of a contract amendment (§5).

---

## 2. `current_temperature` — confirmed, no model change needed

**Decision (CAT-01):** `current_temperature` already has an adequate canonical representation. No code change, schema change, or ADR amendment is required.

Verification performed against four sources (2026-10-04):

| Source | State |
| --- | --- |
| `back_vibes/app/SmartHome/Canonical/CapabilityId.php` | `case CurrentTemperature = 'current_temperature'` — present |
| `back_vibes/app/SmartHome/Canonical/CapabilityCatalog.php` | `operationsFor(CurrentTemperature)` → `[]`; `constraintTypeFor` → `'number'`; `unitFor` → `Unit::Celsius`; `defaultAccessFor` → `Access::Read` |
| `ixora-infra/contracts/smart-home/capability.v1.schema.json` | `capabilityId` enum includes `"current_temperature"`; `x-catalog` entry: `operations: [], constraint_type: number, unit: celsius, default_access: read` |
| `canonical-device-model.md §3` | Row: `current_temperature \| read \| — \| {type: number, min: null, max: null, step: null, unit: "celsius"}` — Status: **Ratified** |

The `min`/`max`/`step` bounds are legitimately `null`: a thermostat sensor typically has no documented operational range. `unit: "celsius"` is mandatory and known. This is the exact pattern ADR-037 §4 (PO correction 3) exists to support — reporting honest unknowns rather than invented values. DEV-01 must not fill in `min`/`max`/`step` for `current_temperature` if the provider mapper does not supply them.

No conflict was found between documentation and code for this capability.

---

## 3. Camera — explicitly deferred

**Decision (CAT-01, confirming ADR-045 Decision 8, pre-approved 2026-10-04):** Camera is outside the CSDM/Provider/Connection track. It is not a `Capability` in the CSDM sense and is not modeled here.

Rationale:
- A live video stream is not representable as a `Constraint` value (ADR-037 §4 covers `number`, `enum`, and `boolean` — none describes a stream). A camera capability would require a new constraint type, which is a major contract version bump per ADR-037 §9.
- Camera is not an action or measurement in the sense Scenes/Vibes operate on — it is a separate product feature with its own lifecycle, permissions, and UX concerns.
- No provider mapper currently implements camera discovery or streaming.

**What this means for downstream cards:**
- DEV-01 must not include a camera capability in the device state pipeline.
- No `DeviceType` dedicated to camera is introduced in this track.
- No `connection_method` for camera streams is added to ADR-045.
- Design screens that depict cameras (DSG-01 scope) must be updated before any implementation — this was already stated in ADR-045 Decision 8.

**Unblocking condition:** an explicit product decision and a dedicated ADR (or ADR-037 amendment) that defines the constraint shape, the connection mechanism, the credential model, and the UX lifecycle. Camera must not be modeled by analogy with existing capabilities or by extending a general-purpose capability id.

---

## 4. Binary sensors — explicitly deferred

**Decision (CAT-01):** Binary sensor capabilities (`motion`, `occupancy`, `contact`, `presence`, `vibration`, and any similar read-only boolean state) are **not part of the CSDM v1 catalog**. No binary sensor capability id exists in `CapabilityId.php`, `capability.v1.schema.json`, or `canonical-device-model.md §3`, and none will be added here.

**Why the constraint shape already exists but the capability does not:** The `{type: boolean}` constraint is ratified for `power`, and a read-only boolean capability is architecturally representable with `access: "read"`, `operations: []`, `constraints: {type: boolean}`. The mechanism exists. What does not exist — and is deliberately withheld until a contract amendment — is:

1. A canonical `CapabilityId` for each sensor type. `motion` and `occupancy` are semantically distinct sensor classes (a PIR sensor vs. a presence radar); collapsing them under one id would be the same mistake as treating HA's `switch` and `light` as the same device class. Each id is a deliberate domain decision.
2. Provider mapper derivation logic. Neither `HomeAssistantAdapter` nor any Google Home mapper currently derives binary sensor state. Adding a capability id without a mapper that produces it generates misleading empty state.
3. A confirmed DEV-01 requirement. DEV-01's scope (device state pipeline) does not include binary sensor state as a confirmed input. Adding catalog entries speculatively is the failure mode ADR-037 §9 governance rules exist to prevent.

**What this means for DEV-01:** DEV-01 must not read, validate, display, or reference any binary sensor capability. If the device state pipeline encounters a capability id it does not recognise, the existing fail-open policy (ADR-033 §5, preserved by ADR-037) applies — pass it through without blocking.

**Unblocking condition for a future amendment:**
1. Identify the specific sensor class(es) required (at minimum: which provider reports it, what the provider-native representation is, and what the canonical id should be).
2. Write a contract amendment: new id in `capability.v1.schema.json` `$defs.capabilityId` enum, new case in `CapabilityId.php`, new row in `CapabilityCatalog.php`, new row in `canonical-device-model.md §3`.
3. Implement the provider mapper derivation and write boundary tests.
4. Each sensor class that is semantically distinct gets its own id and its own amendment step — bulk-adding `motion, occupancy, contact, presence` in one commit without a per-id justification is not permitted.

---

## 5. Fan speed and volume — continuing deferred (ADR-033)

ADR-033 §3 explicitly deferred `can_set_volume` for `media_player` and fan speed for `fan`, noting that the relevant `supported_features` bit values were unconfirmed from the repository. That deferral stands. Neither capability id appears in the CSDM v1 catalog. DEV-01 must not reference them.

---

## 6. DeviceType vs. capability grouping — canonical distinction

`DeviceType` and `Capability` are **two orthogonal abstractions** that must not be used to infer one from the other. This section is the normative reference for any code that touches both.

### 6.1 DeviceType — display category

`DeviceType` (`back_vibes/app/SmartHome/DeviceType.php`) is a **coarse label for UI rendering** — an icon, a section heading, a display name. It has five values: `lighting`, `switchable`, `media`, `ventilation`, `other`.

- Set once at sync time by the provider adapter's `mapDeviceType()` method (e.g. `HomeAssistantAdapter::mapDeviceType()` maps HA entity domains to these five cases).
- The original provider domain (e.g. `light`, `switch`) is preserved in `devices.metadata['domain']` and is not exposed above the adapter boundary.
- ADR-037 §1 explicitly states: "`type` and `metadata` are untouched by this ADR" — meaning the CSDM did not change `DeviceType` and does not govern it.

### 6.2 Capability — functional property

A `Capability` (`CapabilityId`, `Capability`) describes **what a device can do or what state it holds** in a way that is actionable by the domain (Scenes, Vibes, DEV-01). Capabilities are:

- Derived by the provider mapper at sync time, independent of `DeviceType`.
- Governed by the CSDM catalog (§1 above) — a closed, amendment-driven vocabulary.
- The only source a domain service or UI should consult to decide whether an action is valid or what controls to show.

### 6.3 The rule — no inference in either direction

```
DeviceType  ≠ f(capabilities)
capabilities ≠ f(DeviceType)
```

A `lighting` device may have only `power` (no `brightness`); a `switchable` device might gain `energy` in the future. The absence of `brightness` on a `lighting` device is not a modeling error — it is real information the mapper produced from the provider's own capability report.

Code that does `if (deviceType === 'lighting') { show brightness slider }` is a defect: it shows a control for a device that the mapper correctly determined does not support brightness. Code that does `if (capabilities.has('brightness')) { type = 'lighting' }` is a defect in the other direction: it overwrites a mapper decision with a domain inference.

**The only permitted pattern:** render controls from `capabilities`, display category/icon from `DeviceType`. Neither flows from the other.

No existing codebase conflict was found between `DeviceType` and capabilities during the inspection for this card. `HomeAssistantAdapter::mapDeviceType()` and `HomeAssistantCanonicalMapper::deriveCapabilities()` are separate methods with no shared logic between their derivations.

---

## 7. Governance rules for capability amendments

The rules below reproduce the minimum needed from `canonical-device-model.md §9` for quick reference. The full text is authoritative.

**A new capability id may be added (minor version bump) when:**
1. A contract amendment fixes: the exact id, its `access`, its `operations`, and its `constraint` shape and `unit`.
2. At least one provider mapper is ready to derive it on the read path.
3. The amendment is accepted before any mapper ships the new id.

**A major version bump is required when:**
- An existing capability's `constraint` shape changes (e.g. changing `brightness` unit or range).
- A new `Constraint` type-union case is added (e.g. a struct color type).
- The dual-read compatibility path from ADR-037 §8 must be active during the transition.

**What no mapper may do unilaterally:**
- Invent a capability id not in the ratified or provisionally defined catalog.
- Produce a constraint shape (`unit`, `type`, `min`/`max`) that contradicts the catalog for that id.
- Add a provider-native literal (HA `light`, Google `OnOffTrait`, Tuya `category`) as a capability id or constraint value.

---

## 8. Decisions taken in this card

1. **`current_temperature` is confirmed adequate.** No model change, schema change, or code change is required. The existing ratified definition (read-only, `{type: number, unit: "celsius"}`, nullable bounds) is correct and complete for DEV-01.

2. **Camera is formally deferred from the CSDM/Provider/Connection track.** This card confirms ADR-045 Decision 8 (pre-approved). Camera is not a `Capability`, has no `DeviceType` in this track, and requires a dedicated product decision and ADR before any implementation.

3. **Binary sensors are explicitly deferred from the CSDM v1 catalog.** No `motion`, `occupancy`, `contact`, `presence`, or similar id is ratified. DEV-01 must not reference them. Unblocking requires: semantic per-id decisions, contract amendment, provider mapper derivation, and boundary tests.

4. **DeviceType and capabilities are orthogonal abstractions.** `DeviceType` is a display category; capabilities are functional properties. Neither may be inferred from the other. No code change is required — the distinction is already respected in the adapter layer.

---

## 9. Items explicitly deferred by this card

| Item | Unblocking condition |
| --- | --- |
| Binary sensor capabilities (`motion`, `occupancy`, `contact`, `presence`, `vibration`, …) | Per-id semantic decision + contract amendment (schema, `CapabilityId.php`, catalog, spec §3) + provider mapper derivation + boundary tests. Each id is a separate amendment. |
| Camera | Explicit product decision + dedicated ADR defining constraint shape, connection mechanism, credential model, and UX lifecycle. DSG-01 must update affected design screens first. |
| Fan speed | Confirm `supported_features` bit value from live HA payload; contract amendment; mapper derivation. |
| `can_set_volume` / media player volume | Same path as fan speed. |
| `color`, `color_temperature` (already provisional in spec §3) | A struct constraint type for `color` requires a major contract version bump. `color_temperature` needs a representation decision (mired vs. Kelvin) fixed in an amendment before any mapper implements it. |

---

## 10. Relationship to other documents

| Document | Relationship |
| --- | --- |
| [`canonical-device-model.md`](canonical-device-model.md) | Authoritative spec for the CSDM contract. This governance doc interprets and annotates it for CAT-01 decisions; it does not supersede it. |
| [ADR-037](../../decisions/ADR-037-canonical-smart-home-device-model.md) | The architectural decision this doc operationalises. §3 (catalog), §4 (constraints), §9 (versioning) are the most relevant sections. |
| [ADR-045](../../decisions/ADR-045-canonical-provider-model.md) | Decision 8 (camera deferred) is confirmed here. §9 lists DEV-01 as depending on Decision 7 (boundary fix). |
| [`csdm-transition-debt.md`](csdm-transition-debt.md) | Post-CSDM-07 tracked debt. Not modified by CAT-01. |
| DEV-01 | The primary consumer of this document. DEV-01 must treat §1's ratified list as the complete set of capabilities it may handle, §3–§5 as the complete set it must not reference, and §6 as the rule governing DeviceType/capability interactions. |
