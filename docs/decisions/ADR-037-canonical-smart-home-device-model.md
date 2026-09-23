# ADR-037: Canonical Smart Home Device Model

## Status

**Accepted** (2026-09-08, following three pre-acceptance corrections — see §14) — governs the canonical shape of Device, Capability, Operation, Constraint, and DeviceState across all Smart Home providers. Structurally supersedes [ADR-033](ADR-033-device-capabilities.md)'s capability vocabulary and constraint format; does **not** touch [ADR-032](ADR-032-multi-provider-scope.md)'s extensibility boundary, [ADR-014](ADR-014-device-abstraction-and-deduplication.md)/[ADR-015](ADR-015-vibe-device-action-architecture.md)'s device-type and Vibe-action architecture, or [ADR-036](ADR-036-google-home-execution-model.md)'s execution model. Consumed by the CSDM-01–CSDM-07 implementation track — CSDM-01 may now begin once explicitly authorized (not authorized by this status change alone).

**Companion living spec:** [`docs/specs/smart-home/canonical-device-model.md`](../specs/smart-home/canonical-device-model.md) carries the detailed contract (exact field types, the closed capability/operation catalog, full worked device payloads, the Schema-driven Frontend principle, and versioning/evolution rules) this ADR decides but does not itself spell out at implementation detail. This ADR is the record of *why*; the spec is the reference implementers code against.

**This ADR does not block v1.6.0 (Google Home) tasks P01–P14**, which continue to ship under ADR-033's existing capability shape. It becomes the required gate for any capability family added *after* it is Accepted — see §9.

## Date

2026-09-08

## Context

An architectural audit conducted 2026-09-07 ([`docs/specs/smart-home/canonical-device-model-audit.md`](../specs/smart-home/canonical-device-model-audit.md)) read the actual code — `ProviderAdapter`, `ProviderDevice`, `Device`, `DeviceResource`, `DeviceType`, `ActionType`, `SceneAction`, `HomeAssistantAdapter`, and the capability gate — against ADR-033 and against GH04's Google Home trait mapping. It found, with direct code evidence, that the current capability model answers "which actions does a device support" but does not yet answer "with what parameters, what ranges, what units, in what state" in a provider-neutral way. Specifically:

1. **`devices.capabilities` is a flat map of `capability_key → constraint_object`, and `capability_key` is 1:1 with `ActionType`.** There is no concept of a capability having multiple named operations, and no concept of a read-only capability. A property like "current temperature" (readable, never commanded) or "energy" (readable, continuous) has no schema slot at all.

2. **Only one capability (`can_set_brightness`) has ever had a non-empty constraint object** (`{min, max, step}`), and that shape has no `unit` field and no precedent for enum-valued constraints (e.g. an HVAC mode). It was never exercised against a second shape until this audit.

3. **`ActionType`'s vocabulary (`turn_on`, `turn_off`, `toggle`, `set_brightness`) is Home Assistant's own service vocabulary**, confirmed by `HomeAssistantAdapter::ACTION_SERVICE_MAP`, which is an almost-identity mapping (`toggle → toggle`). GH04 already had to invent a client-side composition (read `onOff`, invert, call `on()`/`off()`) because Google Home's `OnOffTrait` has no native toggle command — the first real evidence that the "canonical" vocabulary was not provider-neutral in practice, only untested against a second provider until now.

4. **`brightness`'s `{min: 0, max: 255, step: 1}` constraint is Home Assistant's own convention**, stated as such in ADR-033 §4 ("matching HA's 0-255 convention"), not derived from any Ixora domain principle. GH04 already flagged that this exact constraint "cannot be reused verbatim for Google Home devices," whose Matter `LevelControl.currentLevel` range is 0–254.

5. **No parameter value is validated against its constraint anywhere in the request lifecycle.** `StoreSceneActionRequest`/`UpdateSceneActionRequest` validate only that `parameters` is an array; `ActionType::isBlockedByDeviceCapabilities()` checks only that the capability *key* is present; `HomeAssistantAdapter::executeAction()` merges `parameters` directly into the outbound HTTP payload (`array_merge(['entity_id' => $deviceId], $parameters)`) with no range check. `{"brightness": 9999}` passes through the entire Ixora stack unvalidated today. This predates Google Home and is independent of it.

6. **The mobile client does not expose `set_brightness` at all** — `front_vibes/src/utils/device-action.ts`'s `ACTION_TYPES` is `['turn_on', 'turn_off', 'toggle']`. The capability has been derivable and returned by the API since v1.4.0-T16/T17, but no UI has ever existed to act on it.

7. **What already generalizes correctly and must not be re-derived:** the separation between `devices.id` (the internal surrogate key every Scene/Vibe/domain reference uses) and `devices.provider_device_id` (an opaque, per-connection string never referenced outside the adapter/sync layer) — this is already the "canonical model never touches provider identifiers" boundary this ADR extends to *capability semantics*. Likewise, the one-mapper-per-provider pattern (`HomeAssistantAdapter`, and the Kotlin layer GH04 designs for Google Home) is already the "Provider Mapper" this ADR formalizes as a required architectural role, not a new invention.

**Governing principle for this ADR:**

> No provider defines Ixora's canonical semantics. Home Assistant, Google Home, Tuya, or any future provider always map *to* the Ixora canonical model on read, and *from* it on write.

```
Provider representation → Provider Mapper → Ixora Canonical Model
Ixora Canonical Command → Provider Mapper → Provider-specific command
```

A provider's *absence* of a native primitive (e.g. Google Home having no toggle command) is not evidence that the canonical operation cannot exist — it is evidence that the mapper for that provider must implement the operation compositionally. Both a native HA `light.toggle` call and a Google Home read→invert→`on()`/`off()` composition are equally valid implementations of the single canonical `power.toggle` operation.

---

## Decision

### 1 — Device

```
Device
  id                    — Ixora surrogate key (unchanged; already correct — see Context §7)
  type                  — DeviceType (unchanged; ADR-033/T15's enum is orthogonal to this ADR)
  capabilities: Map<CapabilityId, Capability>
  state: DeviceState     — see §6
  connectivity: online | offline | unknown   (unchanged DeviceStatus enum — connectivity only)
  metadata               — provider-raw passthrough, boundary-only (unchanged role)
```

`type` and `metadata` are untouched by this ADR — the audit found no defect in either. Everything below is new or superseding.

### 2 — Capability

```
Capability
  id: string                          — canonical identifier (e.g. "power", "brightness", "energy", "current_temperature")
  access: "read" | "write" | "read_write"
  operations: string[]                — canonical operation names valid for this capability
  constraints: Constraint | null       — present only when the capability accepts a value
```

**`id` is a canonical vocabulary, not a free string.** Like ADR-033's original vocabulary, it stays closed and amendment-driven — adding `"color"` follows the same governance ADR-033 §3 already established for adding a case: a deliberate addition to a maintained list, never an ad hoc string invented by a provider mapper.

**`access` is new.** It is what makes read-only capabilities representable — `energy: { access: "read" }`, `current_temperature: { access: "read" }` — closing audit gap §9/§10 (plug + energy measurement, thermostat's current temperature) without inventing a parallel "sensor" concept. A capability is either something you can read, something you can command, or both; there is no third category.

### 3 — Operations

```
power:
  operations: [on, off, toggle]

brightness:
  operations: [set]

target_temperature:
  operations: [set]

hvac_mode:
  operations: [set]

energy:
  operations: []                      — read-only capabilities have no operations
```

Operations are canonical verbs, decoupled from any provider's service/command names. **`toggle` remains a first-class canonical operation on `power`, regardless of whether a given provider's mapper implements it as a single native call or as a composed read-invert-write.** This is stated explicitly because it is the exact case GH04 already encountered, and because the audit found the opposite assumption (operation = provider verb) silently baked into the current `ActionType` enum.

The operations catalog is closed per capability, following the same governance discipline as capability ids: a new operation on an existing capability, or a new capability, is a deliberate vocabulary amendment — never a provider-specific string surfacing directly in `SceneAction.parameters` or anywhere in the domain.

### 4 — Constraints — typed, not ad hoc

```
Constraint =
  | { type: "number", min: number | null, max: number | null, step: number | null, unit: string }
  | { type: "enum", allowed_values: string[] }
  | { type: "boolean" }
```

This directly closes audit gap §4/§10: today only one untyped shape (`{min, max, step}`, no `unit`, no precedent for enum) exists, discovered by having exactly one implementation (`can_set_brightness`) ever populate it. A closed, tagged union is enough to represent every device family named in this ADR's brief — numeric ranges with units (brightness, temperature), enums (HVAC mode), and booleans (`power`'s readable value — see below).

**`min`/`max`/`step` are individually nullable; `unit` is not.** A provider mapper frequently knows a numeric capability's unit without knowing its bounds or resolution (a thermostat may report `current_temperature` in Celsius with no documented sensor range; a plug may report `energy` in kWh with no known step size). Forcing an invented `min`/`max`/`step` in that case would smuggle a fabricated provider-side guess into a field this ADR requires to be domain-true — worse than declaring it unknown. `null` on any of the three means "not known," never "unbounded" (unbounded is `max: null` specifically, already the case for `energy` in §12) and never "zero." `unit` stays mandatory unconditionally — a numeric value with a genuinely unknown unit is not representable by this model and is evidence the capability itself needs a different shape, not evidence `unit` should be optional.

**Trade-off, stated explicitly:** when `min`/`max`/`step` are `null` on a `read_write` capability, the validation pipeline (§7) cannot enforce a range for that dimension — the check is skipped, not defaulted. This is accepted deliberately for the read-only capabilities this ADR's brief names (`energy`, `current_temperature`, neither ever reaches a write-validation path since their `access` is `read`), and is expected to be rare for `write`/`read_write` capabilities, whose provider is normally expected to report real operational bounds (as `target_temperature` does in every worked example below). If a provider mapper cannot supply bounds for a *writable* numeric capability, validation for that capability degrades to type-checking only, and that is a known, visible gap — not a silent one — the moment it happens.

`power`'s constraint is `{ type: "boolean" }` (§ below) — not omitted. A `Constraint` is omitted entirely only when a capability has genuinely no associated value at all, which no capability in this ADR's ratified catalog does; `power`'s readable state (`true`/`false`) needs a typed shape exactly as `brightness`'s does, even though its *operations* (`on`/`off`/`toggle`) take no parameters. Operations and constraints are independent — an operation can be parameterless while the capability's state value is still typed (see §12's revised `power` example).

Future constraint types (e.g. a structured color constraint) are explicitly deferred — this ADR defines the mechanism (a tagged union, extensible by adding a case) without pre-designing every future shape, consistent with the instruction not to invent capabilities not yet needed.

### 5 — Brightness is canonically 0–100, unit `percent`

**Adopted, with a domain reason, not a provider-convenience reason:**

- Neither `0–255` (Home Assistant) nor `0–254` (Google Home's Matter `LevelControl`) has any claim to being "the" domain value — both are hardware/protocol artifacts of their respective ecosystems, and privileging either one over the other would repeat exactly the mistake this ADR exists to correct (Context §4).
- **A percentage is the representation the product already needs at the boundary the user actually touches.** Whatever UI eventually renders a brightness control (CSDM-06) needs a human-meaningful value — a slider or a numeric input showing "65%" — not a raw protocol integer. Choosing `0–100/percent` as canonical means the display layer needs no translation step of its own; every provider mapper performs exactly one conversion, on write and on read, and nothing downstream repeats it.
- **Precision loss is real but immaterial.** `255/100 = 2.55` and `254/100 = 2.54` — round-tripping through a percentage cannot always reconstruct the exact original integer. This is accepted deliberately: brightness is a coarse, human-perceived quantity; no product requirement here calls for sub-percent addressability, and a finer canonical grain (e.g. 0–1000) would only reintroduce an arbitrary number without a use case driving it. If a future provider or feature genuinely needs finer-grained brightness control, that is new evidence for a future ADR amendment to reconsider the grain — not a reason to withhold the decision now.
- `step: 1` is the canonical constraint's default; a mapper may report a provider's actual native resolution as metadata for UX purposes (e.g. "this device really only has 10 discrete levels") without that changing the canonical range itself — that refinement is left to CSDM-01's schema design, not decided here.

### 6 — DeviceState — connectivity vs. functional state, formally separated

Connectivity lives on `Device` (§1) and **only** there — `DeviceState` does not repeat it:

```
DeviceState
  values: Map<CapabilityId, value>              — e.g. { power: true, brightness: 65 }
  read_at: timestamp
```

An earlier draft of this ADR duplicated `connectivity` onto `DeviceState` itself. That was a genuine redundancy, not a second source of truth deliberately intended — `Device.connectivity` is authoritative, full stop, and `DeviceState` carries only what §1 calls "functional state." A consumer that needs both simply reads `Device.connectivity` and `Device.state.values` from the same `Device` object; no endpoint or type needs to answer "is this device online" twice.

This directly closes audit gap §5: today "state" is `DeviceStatusResult.raw_state: ?string` plus `attributes: array`, both explicitly provider-raw and never normalized — confirmed by their own naming. `DeviceState.values` is keyed by the same canonical `CapabilityId` vocabulary as `Capability` itself, so a client reading state and a client sending a command share one vocabulary, not two.

**This ADR does not mandate new persistence.** Whether `DeviceState` is persisted, cached with a TTL, or fetched live per request is a decision left to the provider/task that implements each capability family (consistent with ADR-036's existing device-side, live-query model for Google Home) — this ADR only fixes the *shape* `DeviceState` must have wherever it is produced or consumed, so no future provider is tempted to hand back its own raw attribute dictionary as if it were canonical.

### 7 — Command validation pipeline

```
Ixora Command (device_id, capability_id, operation, parameters)
  → validate: capability exists on the device and its access permits the operation;
              operation is declared for that capability;
              parameters conform to the capability's constraint (type, range, step, membership)
  → Provider Mapper: canonical → provider-specific
  → provider command
```

Validation happens **before** the Provider Mapper, against the canonical constraint — not against any provider format. This is the fix for the confirmed, already-existing bug in Context §5 (`brightness: 9999` reaching Home Assistant unvalidated today, independent of Google Home). The Provider Mapper remains a second line of defense (a provider may reject a technically-in-range value for its own reasons), but is no longer the *only* line, which it effectively is today.

For a `number` constraint whose `min`/`max`/`step` are `null` (§4), the corresponding check is skipped rather than defaulted — validation degrades to type-checking for that dimension, not to silent pass-through of the whole value; a non-numeric value is still rejected.

### 8 — Compatibility with ADR-033

**What ADR-033 got right and this ADR keeps unchanged:**
- The closed-vocabulary discipline itself — capabilities are a maintained, deliberate list, never free-form strings. This ADR keeps that discipline; it changes the *shape* each entry carries, not the principle that the set is closed and governed.
- The fail-open policy for absent/unknown capabilities (ADR-033 §5) — still the correct default posture during a gradual migration, and this ADR does not relax or remove it.
- `DeviceType` (T15) is untouched — orthogonal to capability shape.

**What is superseded:**
- The flat `capability_key → constraint_object` map, where the key doubles as the sole operation — replaced by `Capability{id, access, operations, constraints}` (§2–§4).
- `ActionType` as a fixed PHP enum of HA-shaped verbs (`turn_on`/`turn_off`/`toggle`/`set_brightness`) — replaced by validating `(capability_id, operation)` pairs against the schema dynamically (§7). Retiring or reinterpreting `ActionType` is real, visible surgery across `SceneAction` validation and telemetry, and is explicitly assigned to the CSDM-02/CSDM-03 implementation pair, not decided in mechanical detail here.
- `can_set_brightness`'s `{min: 0, max: 255, step: 1}` (unitless, HA-shaped) — replaced by the canonical `{type: "number", min: 0, max: 100, step: 1, unit: "percent"}` (§5).

**Transition strategy:** capabilities are already treated as re-derived, ephemeral data — every provider sync recomputes them (`ProviderDeviceSyncService`'s upsert, `HomeAssistantAdapter::deriveCapabilities()`). This ADR does **not** require a destructive backfill migration of `devices.capabilities`: a device's capability row is naturally replaced in the canonical shape the next time it syncs, under a mapper updated per CSDM-03/04. A version discriminator (§10) lets any consumer detect legacy-shaped vs. canonical-shaped data during the window before every device has re-synced at least once. `SceneAction.parameters` needs no column change — it stays JSON — but its *contents*' meaning changes from "whatever `ActionType` expected" to "whatever the referenced capability's operation and constraint require," and existing rows must be read through a compatibility path until CSDM-07's migration/boundary-test task closes the transition. This ADR decides the strategy; CSDM-07 owns writing it.

### 9 — Relationship to v1.6.0 (Google Home)

**Does not block P01–P14.** Those tasks ship under ADR-033's existing shape — including P09's 0–254→0–255 brightness normalization, which stays exactly as scoped. Retrofitting P09's output to the canonical 0–100/percent shape is CSDM-04's job, after this ADR is Accepted, not a P01–P14 blocker.

**Becomes the required gate for any capability family added after Accepted** — color, color temperature, energy, additional thermostat/fan capabilities, and any device family beyond what P01–P14 already scoped (on/off, toggle, brightness). No such family may be added under ADR-033's legacy shape once this ADR ships; each must be expressed as `Capability{id, access, operations, constraints}` from the start.

### 10 — Versioning

The canonical contract (Capability/Operation/Constraint shapes, and the operation/capability-id vocabulary) is formalized as a **versioned JSON Schema artifact**, checked into the repository as the single source of truth — not a shared runtime library (see §11). Each language (`back_vibes` in PHP, `front_vibes`/Kotlin in Kotlin, the TypeScript frontend) validates against it independently, in its own idiom; CSDM-01 owns producing the first version of that schema and its storage location.

Versioning follows semver against the schema itself: additive changes (a new capability id, a new operation on an existing capability, a new optional field) are minor; changes to an existing constraint's required shape are major and require the dual-read compatibility path of §8/CSDM-07. A `contract_version` (or equivalent schema `$id`/version marker) accompanies persisted/transmitted capability and state data so any consumer can detect which shape it is looking at during the transition window.

### 11 — Not a module, library, or microservice

**Reaffirms the audit's conclusion; no new evidence changes it.** This ADR requires:
- **(A) Evolution inside `back_vibes`**, with the Provider Mapper role formalized exactly as it already exists (one mapper class per provider implementing the canonical contract) — not a new bounded context.
- **A shared *schema*, not shared *code*, between backend and mobile.** PHP and Kotlin do not share a runtime; a "shared library" would be, in practice, the JSON Schema artifact of §10 — which is what this ADR already specifies. No shared code package is introduced.
- **No microservice.** None of the operational criteria that would justify one are present: no need for independent deployment (a mapper only ever runs inside the process that already holds the provider credential, or inside the mobile app — never as a service multiple systems call remotely), no scaling need (mapping is CPU-trivial), no failure-isolation gain beyond what already exists (a mapper's failure is already contained inside its own adapter/plugin), and no plurality of real remote consumers beyond `back_vibes` and `front_vibes`, each of which already has its natural, local mapper. Extracting a service here would be separation for its own sake, which this ADR explicitly rejects as a justification.

---

## Consequences

**Positive**
- Capabilities can finally represent the full range of devices this ADR's brief named — dimmable lights, color, color temperature, plugs with energy measurement, thermostats, fans — without inventing new `can_*` flags disconnected from any schema.
- The confirmed, pre-existing validation gap (unbounded `SceneAction.parameters`) gets a real fix, owned by CSDM-02, using the same constraint objects capabilities already carry.
- `toggle` and any future operation with no native provider primitive have an explicit, principled home: composed in the mapper, canonical in the domain — removing the ad hoc reasoning GH04 had to invent on its own.
- Brightness (and every future numeric capability) carries a `unit`, closing a real ambiguity silently present since ADR-033.

**Negative**
- `ActionType` as a fixed enum is retired/reinterpreted — real, visible change across `SceneAction` validation, telemetry attribute values, and any code pattern-matching on its four cases today.
- A transition window exists where legacy- and canonical-shaped capability data coexist; consumers must be version-aware until CSDM-07 closes it.
- The frontend gains real, currently-missing work (a brightness control did not exist before this ADR either — CSDM-06 is net-new UI, not a rewrite of something broken).

**Risks**
- If CSDM-07's migration/boundary-test task is skipped or rushed, legacy- and canonical-shaped data could silently coexist indefinitely, defeating the point of a single canonical model.
- If a future capability family's real-world shape doesn't fit the three-case `Constraint` union (§4), that is new evidence for an amendment — not a reason to force-fit it into `number`/`enum`/`boolean` today.

**Technical debt accepted**
- The exact backfill/dual-read mechanics are deferred to CSDM-07, not fully specified here.
- Provider-reported native resolution (e.g. "this dimmer only has 10 real steps") is not part of the canonical constraint and is left as a future, optional metadata refinement.

**Future work (not authorized here)**
- `color` and `color_temperature` capabilities (ADR-033 §3 already excluded these; this ADR does not add them either — it only makes them addable later without a second structural rewrite).
- Any provider beyond Home Assistant and Google Home (Tuya, future providers) inherits this contract unchanged — no provider-specific accommodation is anticipated or needed.

---

## 12 — Worked examples

### Home Assistant lamp (dimmable)

Canonical device (post-CSDM-03 mapper):
```
capabilities:
  power:      { access: read_write, operations: [on, off, toggle],
                constraints: { type: boolean } }
  brightness: { access: read_write, operations: [set],
                constraints: { type: number, min: 0, max: 100, step: 1, unit: percent } }
state:
  values: { power: true, brightness: 65 }
```
Mapper (HA side, CSDM-03): `power.on/off` → HA services `light.turn_on`/`light.turn_off`; `power.toggle` → native `light.toggle`; `brightness.set(65)` → HA payload `{"brightness": round(65/100*255)}` = `{"brightness": 166}`. Read path: HA's `state` string (`"on"`/`"off"`) → canonical `power: true`/`false`; `attributes.brightness` (0–255) → canonical `brightness: round(raw/255*100)`.

### Google Home equivalent (same canonical capability, different mapper)

Canonical device is **identical in shape** — same two capabilities, same constraints, same `state.values` keys. Mapper (Google side, CSDM-04, building on GH04/P09): `power.on/off` → `OnOffTrait.on()`/`off()`; `power.toggle` → **no native command** — composed as: read `standardTraits.onOff.onOff`, invert, call `on()` or `off()` accordingly (exactly GH04's already-documented finding, now expressed as the canonical mapper's job rather than an ad hoc workaround). Read path for `power`: `standardTraits.onOff.onOff` is already a Kotlin `Boolean` — this mapper direction needs **no** true/false↔"on"/"off" string conversion at all, unlike the HA mapper, which is a small but real point in favor of a boolean canonical state (§4) over a string one. `brightness.set(65)` → `moveToLevel(round(65/100*254))` = `moveToLevel(165)`. Read path: `LevelControl.currentLevel` (0–254) → canonical `brightness: round(raw/254*100)`.

### Plug with read-only energy

```
capabilities:
  power:  { access: read_write, operations: [on, off, toggle],
            constraints: { type: boolean } }
  energy: { access: read, operations: [],
            constraints: { type: number, min: 0, max: null, step: 0.01, unit: kWh } }
```
`energy` has no `operations` — it is never commanded, only read into `state.values.energy`. No `ActionType`-equivalent exists for it, by design (§2).

### Thermostat

```
capabilities:
  current_temperature: { access: read,       operations: [],
                          constraints: { type: number, min: null, max: null, step: null, unit: celsius } }
  target_temperature:  { access: read_write, operations: [set],
                          constraints: { type: number, min: 5,   max: 35, step: 0.5, unit: celsius } }
  hvac_mode:            { access: read_write, operations: [set],
                          constraints: { type: enum, allowed_values: [off, heat, cool, auto] } }
```
`current_temperature` shows the nullable-bounds case (§4): a thermostat's sensor typically has no documented range, so `min`/`max`/`step` are honestly `null` rather than invented — `unit` (`celsius`) is still mandatory and known. `target_temperature` is the contrasting case: a real, operator-set range the device enforces, so it is populated. This is the exact distinction the PO's third correction (§4) exists to make representable.
Three capabilities, three different constraint shapes (read-only number, read-write number, read-write enum) — exactly the case that had no schema slot before this ADR.

### Command validation (the `brightness: 9999` fix)

```
Command: { device_id: 42, capability_id: "brightness", operation: "set", parameters: { value: 9999 } }
  → capability "brightness" exists on device 42? yes
  → access permits "set" (write/read_write)? yes
  → constraint: type=number, min=0, max=100 → 9999 fails max → REJECTED, before any Provider Mapper call.
```

---

## 13 — Impact on CSDM-01–CSDM-07 (informational — cards not modified by this ADR)

Reviewed against the decisions above. **All seven cards are already substantially aligned** — several already anticipated exact conclusions this ADR reaches independently (CSDM-03's card already states "toggle... continues being an Ixora canonical operation, not a concept inherited from the provider," which §3 confirms verbatim). Two precision recommendations, not corrections:

- **CSDM-04**'s dependency line reads "Google Home v1.6.0 sufficiently stable" — recommend making this concrete: depends specifically on **P09** (the Android integration layer CSDM-04 would extend), not a vague stability judgment call.
- **CSDM-02**/**CSDM-03** should explicitly name "retire/reinterpret the `ActionType` enum" within their stated scope (§8 of this ADR makes that impact explicit; the cards' current wording implies it but doesn't say it, and it's real, visible surgery worth naming so it isn't discovered mid-implementation).

No card is found wrong, redundant, missing, or mis-sized for its assigned model.

**Re-checked after the PO's three pre-acceptance corrections (§4, §6, and power's boolean constraint):** none require a structural change to any of the seven cards. `power` becoming `{type: boolean}` and numeric bounds becoming individually nullable are refinements *within* what CSDM-01 (schema), CSDM-02 (validation), and CSDM-03 (HA mapper) were already scoped to build — none of the three had committed to the pre-correction shapes in a way this invalidates. **CSDM-04 (Google mapper) is mildly easier, not harder**: Google's `OnOffTrait.onOff` is natively a Kotlin `Boolean`, so the boolean canonical state requires no string conversion on that side (§7.0/§7.2), unlike the HA mapper. CSDM-05's own description already frames the distinction as "online/offline/unknown" vs. "power/brightness/temperature," which is precisely the corrected, non-duplicated shape — no rewording needed there either.

---

## 14 — Pre-acceptance corrections (PO, 2026-09-08)

The PO approved this ADR's direction but required three corrections before moving it from Proposed to Accepted. All three are applied throughout the document above (§1, §4, §6, §7, §12); this section is the record of what changed and why, not a duplicate of the reasoning already inline.

1. **`DeviceState` duplicated `connectivity`, which already lives on `Device`.** Corrected: `DeviceState` (§6) now carries only `values` and `read_at`. `Device.connectivity` is the sole source of truth. No architectural impediment was found — the duplication was a genuine oversight, not a deliberate second source of truth.

2. **`power`'s constraint was `null`, with the state value "on"/"off" held together only "by convention."** This partially contradicted this ADR's own point that constraints should be typed, not ad hoc. Corrected: `power`'s constraint is `{type: boolean}`, and its state value is `true`/`false`. No strong reason was found to keep string values — if anything, §12's Google Home example shows the Google mapper needs *no* conversion at all for this field (`OnOffTrait.onOff` is already a Kotlin `Boolean`), while the Home Assistant mapper needs exactly one (HA's `state` string ↔ boolean) either way. Boolean is at least as good a canonical choice as string, and closes the "by convention" gap. `on`/`off`/`toggle` remain the canonical *operations* — this change affects only the *value* representation, not the verbs.

3. **`number` constraints required non-null `min`/`max`/`step`.** This would have forced a provider mapper to invent bounds it does not actually know (e.g. a thermostat's undocumented sensor range) — precisely the kind of fabrication this ADR exists to prevent elsewhere. Corrected: `min`/`max`/`step` are each independently nullable; `unit` remains mandatory (§4). **Trade-off, disclosed rather than hidden:** a `null` bound on a `read_write` numeric capability means the validation pipeline (§7) cannot enforce that dimension for that capability — degrading to type-checking only. This is expected to be rare for genuinely writable capabilities (a device's real operational bounds, like `target_temperature`'s, are normally known) and harmless for `read`-only ones (`energy`, `current_temperature`), which never reach write validation regardless.

No further inconsistency was found while applying these corrections. §13 confirms none of the seven CSDM implementation cards need a structural change as a result.

## Sources

Code (verified 2026-09-07/08): `back_vibes/app/SmartHome/{ActionType.php, Adapters/HomeAssistantAdapter.php, DTOs/{ProviderDevice.php, DeviceStatusResult.php}, DeviceStatus.php}`, `app/Models/{Device.php, SceneAction.php}`, `app/Http/Resources/DeviceResource.php`, `app/Http/Requests/{Store,Update}SceneActionRequest.php`, `database/migrations/2026_09_04_000001_add_capabilities_to_devices_table.php`, `front_vibes/src/utils/device-action.ts`. Internal: [ADR-032](ADR-032-multi-provider-scope.md), [ADR-033](ADR-033-device-capabilities.md), [ADR-036](ADR-036-google-home-execution-model.md), GH04 (`docs/specs/smart-home/google-home/trait-capability-mapping.md`).
