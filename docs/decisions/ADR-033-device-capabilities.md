# ADR-033: Device capabilities model and validation policy

## Status

**Accepted** — governs the **capabilities vocabulary, serialization, HA derivation, and fallback policy** for Smart Home devices in v1.4.0. Referenced by T13 (capabilities column/DTO), T14 (ProviderAdapter contract extension), T15 (device type model — coordinates on vocabulary), T16 (HomeAssistantAdapter derivation), T20 (capability gate in SceneActionJob).

## Date

2026-09-03

## Context

T01 (`current-state.md`) confirmed that no capabilities exist at any layer today: no DB column on `devices`, no field on the `ProviderDevice` DTO, no method on `ProviderAdapter`, no validation before a `SceneActionJob` dispatches an action. Every device can receive any MVP action type (`turn_on`, `turn_off`, `toggle`) without the system knowing whether the device supports it — the adapter silently receives the call and the provider returns a 4xx or executes the wrong service.

`HomeAssistantAdapter::mapDevice()` (`HomeAssistantAdapter.php:253–280`) already stores `supported_features` (pass-through from HA attributes, when present) and `device_class` in `metadata`, but neither field is interpreted or surfaced.

ADR-032 declares capabilities as out of scope for its own decisions and assigns this ADR as the owner. ADR-032 decision D.2 lists `app/SmartHome/Adapters/` and `ProviderDevice` DTO as expected change sites when capabilities are added, confirming the vocabulary and contract decisions below fit the v1.4.0 structural plan.

`ActionType` today (`ActionType.php:17–20`) holds exactly three cases: `turn_on`, `turn_off`, `toggle`. The `UnsupportedSmartHomeActionException` is already thrown when an action string does not match `ACTION_SERVICE_MAP` in `HomeAssistantAdapter::executeAction()`. `SmartHomeActionOutcome` holds four values: `success`, `failure`, `unsupported`, `unknown` (`SmartHomeActionOutcome.php:22–25`).

The `supported_features` bitmask in HA is an integer whose bit meanings differ per domain. `light` domain bits are documented in the HA developer reference (e.g., bit 1 = BRIGHTNESS, bit 2 = COLOR_TEMP, bit 16 = TRANSITION). `media_player` uses an entirely different set. `switch` and `fan` have their own maps. Treating the integer as a generic, domain-agnostic signal would produce incorrect capability inferences — the derivation table below is therefore organized per domain.

The goal of this ADR is to make the capability gate in T20 **useful in practice**: it must block at least one realistic combination (e.g., `set_brightness` on a switch) rather than always passing because every device appears to support everything.

---

## Decision

### 1 — Capability vocabulary

The Ixora capability vocabulary for v1.4.0 is a **closed set of four strings**, named after what the device can do, not after the provider domain it came from:

| Capability | Meaning | Enables ActionType(s) |
| --- | --- | --- |
| `can_turn_on` | Device can be switched on | `turn_on` |
| `can_turn_off` | Device can be switched off | `turn_off` |
| `can_toggle` | Device can toggle its on/off state | `toggle` |
| `can_set_brightness` | Device can accept a brightness level (0–255 integer) | `set_brightness` (new — decision 3) |

**Relationship to ActionType:** each `ActionType` value requires the corresponding capability to be present before the gate in T20 permits dispatch. The mapping is one-to-one:

| ActionType | Required capability |
| --- | --- |
| `turn_on` | `can_turn_on` |
| `turn_off` | `can_turn_off` |
| `toggle` | `can_toggle` |
| `set_brightness` | `can_set_brightness` |

This is not a flag field — a device may hold any combination (including all four or none). Capability names are Ixora domain vocabulary; they do not embed provider terminology.

Future capabilities (`can_set_color`, `can_set_color_temp`, `can_set_volume`, …) are reserved for post-v1.4.0 ADR amendments. Adding them follows the same pattern: new string in the closed set, new `ActionType` case, new row in this table, new derivation rows in decision 4.

---

### 2 — Serialization format

Capabilities are stored and transported as a **structured map from capability string to a parameter constraint object**:

```json
{
  "can_turn_on":  {},
  "can_turn_off": {},
  "can_toggle":   {},
  "can_set_brightness": { "min": 0, "max": 255, "step": 1 }
}
```

**Rationale for map over flat list:**

A flat list (`["can_turn_on", "can_turn_off", "can_set_brightness"]`) is sufficient for boolean-capability actions (`turn_on`, `turn_off`, `toggle`) but fails for `set_brightness`, which the caller must know accepts a bounded integer range. Discovering that range at call time — by attempting the action and reading the error — is unusable UX. The map carries the constraint alongside the capability flag with zero additional fields or tables.

An empty object `{}` for boolean capabilities signals "present, no parameter constraints". This is forwards-compatible: a future capability that adds constraint fields does not require a schema change, only a new key in the object.

**DB column:** `devices.capabilities` — `json`, nullable (absent = unknown, see decision 5). The PHP model casts it as `array`. The `ProviderDevice` DTO gains a `capabilities: array` field (nullable; null = provider did not return derivable capability data).

**Transport:** `ProviderDevice::capabilities` passes through sync upsert unchanged. The device API resource exposes the column as-is. No transformation between DB and HTTP response.

**Stress test (set_brightness):** the map format handles `set_brightness` cleanly:

```json
{ "can_set_brightness": { "min": 0, "max": 255, "step": 1 } }
```

A flat list would require either a separate "brightness range" field elsewhere (coupling), or ignoring the range entirely (incomplete contract). The map keeps the constraint co-located with the capability flag. ✓

---

### 3 — ActionType expansion in v1.4.0

**Decision: add exactly `set_brightness` to `ActionType`. No other additions in v1.4.0.**

`ActionType` after v1.4.0 holds four cases: `turn_on`, `turn_off`, `toggle`, `set_brightness`.

**Justification:**

With only `turn_on`/`turn_off`/`toggle`, every device in `ACTIONABLE_DOMAINS` supports all three actions (HA will execute `switch.turn_on` and `light.turn_on` alike). The capability gate in T20 would never actually block a dispatch — `can_turn_on`, `can_turn_off`, and `can_toggle` would be present on every synced device. A gate that never fires provides no regression protection and no observable correctness signal.

`set_brightness` is the smallest expansion that creates a realistic mismatch: a `switch` does not support brightness; a `light` with a dimmable driver does; a `light` without one (e.g., a fixed-output smart bulb) might not. The gate becomes meaningful: `set_brightness` on a `switch` is blocked, on a dimmable `light` it passes. T20 is testable end-to-end.

**Color (`can_set_color`) and color temperature (`can_set_color_temp`) are excluded from v1.4.0** because:
1. They require additional HA supported_features bits (bit 2 = COLOR_TEMP, bits 4/8/16 = various color modes) whose exact semantics across HA versions are not confirmed from the repository alone — T16 would need live payloads to map them safely.
2. Their parameter constraints (color as `{h, s, b}` tuple vs. `{r, g, b}` vs. color name) are not settled in this ADR and would require a second ADR amendment before T16 could implement them.
3. The cost/benefit argument for v1.4.0 is satisfied by brightness alone (see above).

`set_volume` for `media_player` follows the same pattern as `set_brightness` structurally, but its HA `supported_features` mapping is a hypothesis (see decision 4). It is deferred to a post-v1.4.0 amendment.

---

### 4 — Derivation from Home Assistant

`HomeAssistantAdapter::mapDevice()` already stores `supported_features` pass-through in `metadata` when present (`HomeAssistantAdapter.php:263–265`). The derivation logic in T16 reads that value and produces `capabilities` via a per-domain table.

The `supported_features` integer is a bitmask. For `light`, HA documents (developer reference, confirmed from widely-used HA integrations and the Home Assistant source `homeassistant/components/light/__init__.py`):

| Bit (value) | HA constant | Meaning |
| --- | --- | --- |
| 1 (0x01) | `SUPPORT_BRIGHTNESS` | Adjustable brightness |
| 2 (0x02) | `SUPPORT_COLOR_TEMP` | Color temperature |
| 4 (0x04) | `SUPPORT_EFFECT` | Lighting effects |
| 8 (0x08) | `SUPPORT_FLASH` | Flash |
| 16 (0x10) | `SUPPORT_COLOR` | RGB/HS color |
| 32 (0x20) | `SUPPORT_TRANSITION` | Transition duration |
| 128 (0x80) | `SUPPORT_WHITE_VALUE` | White channel |

The exact constant values above are the HA-documented legacy bitmask values, used in HA instances prior to HA 2022.5 (`LightEntityFeature` IntFlag). Post-2022.5 HA, `supported_features` may be reported differently depending on the integration version. **T16 must validate against a live payload before treating these bits as authoritative.**

**Per-domain derivation table:**

| HA domain | Condition | Ixora capability | Confidence |
| --- | --- | --- | --- |
| `light` | always (domain present) | `can_turn_on`, `can_turn_off`, `can_toggle` | **Confirmed** — `light.turn_on`, `light.turn_off`, `light.toggle` are universal HA services |
| `light` | `supported_features & 1` (BRIGHTNESS bit) | `can_set_brightness` | **Hypothesis** — bit value 1 is the BRIGHTNESS flag in the legacy bitmask; must be validated with live payload in T16 before this row is treated as production logic |
| `switch` | always (domain present) | `can_turn_on`, `can_turn_off`, `can_toggle` | **Confirmed** — `switch.turn_on/off/toggle` are unconditional HA services |
| `switch` | any `supported_features` value | (no additional capabilities) | **Confirmed** — `switch` in HA does not expose brightness or color services |
| `media_player` | always (domain present) | `can_turn_on`, `can_turn_off` | **Confirmed** — `media_player.turn_on/off` exist; `toggle` is not a standard `media_player` HA service |
| `media_player` | `supported_features & ?` (VOLUME_SET bit) | `can_set_brightness` → **NOT applicable** | N/A — volume is a different semantic; `set_brightness` must not be inferred for `media_player` |
| `media_player` | `supported_features & ?` (VOLUME_SET bit) | (no v1.4.0 capability; deferred) | **Hypothesis** — `can_set_volume` is the correct future capability; bit value unknown without live payload; T16 declares as not-derivable for v1.4.0 |
| `fan` | always (domain present) | `can_turn_on`, `can_turn_off`, `can_toggle` | **Confirmed** — `fan.turn_on/off/toggle` are standard HA services |
| `fan` | `supported_features & ?` (SET_SPEED bit) | (no v1.4.0 capability; deferred) | **Hypothesis** — fan speed analogous to brightness structurally; bit value unknown without live payload; T16 declares as not-derivable for v1.4.0 |

**Fallback when `supported_features` is absent or zero for `light`:** grant only `can_turn_on`, `can_turn_off`, `can_toggle`. Do not infer `can_set_brightness` — an absent flag is not evidence of support.

**Hypotheses summary for T16:**

1. `light` BRIGHTNESS bit value (1 / 0x01): confirmed in HA legacy docs but must be verified with a real device payload before T16 ships this row as production.
2. `media_player` VOLUME_SET bit value: unknown from repository alone; T16 must not derive `can_set_brightness` for `media_player`.
3. `fan` speed bit value: unknown; T16 defers fan speed capability.
4. Post-2022.5 HA `LightEntityFeature` IntFlag vs. legacy bitmask compatibility: T16 must test against a real HA instance to confirm bit 1 behaves identically.

---

### 5 — Fallback policy

**Policy: capability-absent → permit (fail-open); capability-present-but-mismatched → block.**

More precisely, three states are defined for a device × action pair at the gate (T20):

| State | Condition | Gate decision | Telemetry outcome |
| --- | --- | --- | --- |
| **Confirmed supported** | `capabilities` column non-null AND required capability key present | Dispatch | `SmartHomeActionOutcome::Success` (if provider succeeds) / `Failure` (if provider fails) |
| **Confirmed unsupported** | `capabilities` column non-null AND required capability key **absent** | Reject — do not dispatch | `SmartHomeActionOutcome::Unsupported` |
| **Unknown** | `capabilities` column null OR not a valid map OR `supported_features` absent/non-numeric at sync time | Dispatch (pass-through) | `SmartHomeActionOutcome::Success` / `Failure` as before — gate invisible |

**Rationale for fail-open unknown case:**

- Blocking on unknown capabilities would silently break every device that existed before T13 runs the backfill migration and every device synced by a provider that does not surface `supported_features`. That is a regression with no recovery path except re-sync.
- The v1.4.0 scope adds the gate *alongside* the existing no-gate path, not as a replacement. Devices with no derivable capabilities continue to behave exactly as today (dispatch, let the adapter decide, receive `success` or `failure` from the provider).
- The gate's value is **precision on the confirmed-unsupported path**: when capabilities are known, a `set_brightness` on a `switch` is rejected *before* a provider call is attempted, which is observable, loggable, and guaranteed consistent across retries.

**Non-numeric or non-parseable `supported_features`:** treat as absent → capabilities for that device remain null → unknown → pass-through. Log a warning during sync but do not fail the device upsert.

**Existing outcomes used — no new outcome needed:**

- Confirmed-unsupported gate rejection maps to `SmartHomeActionOutcome::Unsupported`. This matches the existing semantic: "the action is not mappable/supported" — the only difference is that today this outcome is set by `UnsupportedSmartHomeActionException` thrown inside the adapter, whereas after T20 it can also be set by the gate *before* the adapter is called. The outcome value and its telemetry meaning are identical; no new enum case is required.
- The `Unknown` outcome case (`SmartHomeActionOutcome::Unknown`) remains a classifier-degradation fallback only (documented in `SmartHomeActionOutcome.php:14–18`) and is **not** used for the unknown-capability pass-through. Pass-through produces `Success` or `Failure` depending on the provider response — the gate's absence is not itself an outcome.

---

### 6 — Manual capability override

**Decision: manual override is deferred to T17 (post-T16 implementation); it is not in v1.4.0 scope.**

Rationale: automatic derivation in T16 covers the primary use case (HA devices with machine-readable `supported_features`). A manual override requires UI surface (device detail page or admin), an override field in the `devices` table alongside the auto-derived `capabilities` column, and a merge/precedence rule. Defining that before T16 ships and before field data is available would be speculative. T17 takes T16's live output as its baseline and designs the override UX against real capability distributions. If T16 produces systematically wrong capabilities for a known device category, that is a T17 signal, not a v1.4.0 blocker.

---

## Consequences

### Positive

| Outcome | Why it matters |
| --- | --- |
| **Gate is observable in v1.4.0** | `set_brightness` on a `switch` produces `Unsupported` telemetry; gate is exercisable in tests without synthetic fixtures. |
| **No new telemetry outcome** | `Unsupported` already exists in `SmartHomeActionOutcome`; gate reuses exact same value and log path as `UnsupportedSmartHomeActionException`. |
| **Fail-open preserves v1.3.0 behavior** | Devices synced before T13/T16 or from providers without `supported_features` continue working without re-sync. |
| **Structured map is forwards-compatible** | Adding `can_set_color` with `{ "mode": "hs" }` constraints requires no schema or DTO change; only a new key. |
| **Vocabulary is provider-agnostic** | A future Tuya or Matter adapter maps to the same `can_turn_on` / `can_set_brightness` keys; `SceneActionJob` and the gate never see provider terminology. |

### Negative / tradeoffs

| Tradeoff | Impact |
| --- | --- |
| **Fail-open for unknown** | Gate provides no protection for devices with null capabilities. This is intentional and bounded: once T16 syncs a device with derivable `supported_features`, capabilities are populated and the gate activates. |
| **Derivation hypotheses in T16** | BRIGHTNESS bit (light), VOLUME_SET (media_player), speed (fan) need live-payload validation before production merge of T16. |
| **`toggle` confirmed-unsupported on media_player** | `media_player` does not receive `can_toggle` per the derivation table. A user with a scene action `toggle` on a `media_player` will hit `Unsupported` after T20 activates, where today it would dispatch and let HA return an error. This is a minor behavior change on an already-broken path. |
| **Manual override deferred** | Users cannot correct a wrong auto-derived capability in v1.4.0. A device incorrectly missing `can_set_brightness` can still use brightness via the fail-open unknown path if `capabilities` is left null (by removing the capability row), but that is not a graceful solution. T17 owns this. |

---

## Alternatives considered

| Alternative | Why not chosen |
| --- | --- |
| **Flat string array `["can_turn_on", "can_set_brightness"]`** | Cannot carry parameter constraints (range for `set_brightness`) co-located. Requires separate column or a parallel constraint map — more tables, same information. |
| **Capability-per-column (`can_brightness BOOLEAN`, etc.)** | Schema change per capability; no forwards-compatibility; ALTER TABLE required for every new capability. |
| **Bitmask integer on `devices`** | Encodes HA bit semantics into IXORA storage; non-self-documenting; bit meaning changes when IXORA vocabulary expands. |
| **Block on unknown (fail-closed fallback)** | Breaks every existing device on upgrade; requires T13 backfill to complete successfully before any action dispatch works; eliminates the gradual rollout path. |
| **Add `can_set_color` alongside `can_set_brightness`** | Color parameter schema (`{h, s, b}` / `{r, g, b}` / named) is not settled; HA color_mode feature flag semantics differ per HA version; high ambiguity for marginal v1.4.0 gain. |
| **New `SmartHomeActionOutcome::CapabilityBlocked`** | Not needed — `Unsupported` already means "the action is not mappable/supported by this device"; gate rejection is semantically identical. Adding a new outcome would require telemetry changes (metric label set, dependency-rule tests, Grafana dashboard). |

---

## Related docs

| Document | Relationship |
| --- | --- |
| [`specs/smart-home/multi-provider/current-state.md`](../specs/smart-home/multi-provider/current-state.md) | T01 — confirms zero capabilities anywhere today; confirms `metadata` stores `supported_features` pass-through |
| [`decisions/ADR-032-multi-provider-scope.md`](ADR-032-multi-provider-scope.md) | v1.4.0 infrastructure anchor; decision D.2 lists adapter and DTO as expected change sites |
| `back_vibes/app/SmartHome/ActionType.php` | Current action vocabulary (`turn_on`, `turn_off`, `toggle`); gains `set_brightness` in T11 |
| `back_vibes/app/SmartHome/Adapters/HomeAssistantAdapter.php` | `ACTIONABLE_DOMAINS`, `mapDevice()`, `supported_features` pass-through — derivation source for T16 |
| `back_vibes/app/Telemetry/SmartHome/SmartHomeActionOutcome.php` | `Unsupported` case reused for gate rejection; no new case added |
| `back_vibes/app/SmartHome/Exceptions/UnsupportedSmartHomeActionException.php` | Existing exception; T20 may reuse or throw a parallel mechanism using same outcome |
| [ADR-012](ADR-012-smart-home-provider-strategy.md) | Provider adapter architecture; capabilities vocabulary must stay provider-agnostic per ADR-012 |
| [ADR-015](ADR-015-vibe-device-action-architecture.md) | Original MVP action model; `set_brightness` extends beyond its scope |
