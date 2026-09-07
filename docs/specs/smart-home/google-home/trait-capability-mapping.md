# GH04 — Google Home trait/device-type mapping to ADR-033 capabilities

**Task:** v1.6.0 — GH04 (Mapeamento de traits Google/Matter para capabilities ADR-033)
**Date:** 2026-09-07
**Type:** Mapping specification. No production code.
**Governing decisions:** [ADR-033](../../../decisions/ADR-033-device-capabilities.md) (capability vocabulary), [ADR-036](../../../decisions/ADR-036-google-home-execution-model.md) (Google Home execution model).
**Informed by:** [GH02 results](gh02-results.md) — every class/method/property named below was confirmed either in the SDK's own javadoc or against real compiler output from the actual dependency, and the `OnOffTrait` read/write path was physically exercised on real hardware. Nothing here is invented.

---

## 1. Scope

Minimum viable set per the GH04 card: **light and plug**, mapped to the four capabilities ADR-033 already defines (`can_turn_on`, `can_turn_off`, `can_toggle`, `can_set_brightness`). This document maps **device capabilities only** (ADR-033) — it does not touch provider execution capabilities (ADR-036 Decision 2's `ProviderExecutionCapability`). The two vocabularies are orthogonal and must not be cross-referenced, per ADR-036's own naming rule.

Dedup with Home Assistant is explicitly out of scope and unaffected: [ADR-035](../../../decisions/ADR-035-cross-provider-deduplication.md) still governs — a device visible through both Home Assistant and Google Home appears twice, by design, until a hardware identifier is available.

## 2. Device type mapping

Google/Matter device types confirmed via `com.google.home.matter.standard` (extracted javadoc) map to the existing Ixora `DeviceType` enum (`back_vibes/app/SmartHome/DeviceType.php`) the same way `HomeAssistantAdapter::mapDeviceType()` already does for HA domains — no new Ixora vocabulary is introduced:

| Google/Matter device type | Ixora `DeviceType` | Confidence |
| --- | --- | --- |
| `OnOffLightDevice` | `Lighting` | **Confirmed** — this is the exact type GH02 queried and received 4 real lamps against. |
| `DimmableLightDevice` | `Lighting` | **Confirmed to exist** (`com.google.home.matter.standard.DimmableLightDevice`, javadoc-verified), same category as `OnOffLightDevice` — a light that additionally exposes `LevelControl`. **Not physically exercised** — GH02 queried `has(OnOffLightDevice)`/`has(OnOffPluginUnitDevice)` only; whether the four real lamps also satisfy `has(DimmableLightDevice)` is unconfirmed. Flagged, not assumed. |
| `OnOffPluginUnitDevice` | `Switchable` | **Confirmed to exist** and queried by GH02 (returned `false` for all 5 real devices in that home — no plug was present to confirm positively, only the negative case). |

Any Google/Matter device type outside this set (e.g. `OnOffLightDevice`'s sibling types for locks, thermostats, media, sensors — enumerated in [GH03a's supported device types list](access-gate.md)) falls back to `DeviceType::Other`, mirroring `HomeAssistantAdapter`'s existing fallback rule: unrecognised domains never invent a new Ixora type.

**Raw value preservation (equivalent of HA's `metadata['domain']`):** the Google/Matter device type identifier and the raw trait payload must be preserved in `devices.metadata`, never collapsed into `devices.type`. This is the same rule `HomeAssistantAdapter` already follows; a Google adapter would follow it identically, writing e.g. `metadata: {'google_device_type': 'OnOffLightDevice', ...}` — exact key names are an implementation detail for the production task, not decided here.

## 3. Trait → capability mapping

### `can_turn_on`, `can_turn_off`, `can_toggle`

| Google device type | Trait | Confirmed member | Ixora mapping |
| --- | --- | --- | --- |
| `OnOffLightDevice` | `standardTraits.onOff` (Matter `OnOffTrait`, via `com.google.home.matter.standard.OnOff`) | `onOff: Boolean` (state), `on()` / `off()` (suspend commands) | `can_turn_on: {}`, `can_turn_off: {}` |
| `OnOffPluginUnitDevice` | `standardTraits.onOff` (same trait) | same | same |

**`can_toggle` — no direct SDK equivalent, by design.** `OnOffTrait`'s command set (`OnCommand`, `OffCommand`, `OnWithRecallGlobalSceneCommand`, `OnWithTimedOffCommand`, the `WithEffect`/`WithOnOff` variants on `LevelControlTrait`) has **no `toggle()` command** — confirmed by reading the full `OnOffCommands` member list in GH02's javadoc extraction. Unlike Home Assistant, which has a native `light.toggle`/`switch.toggle` service, Google Home's Matter-based API expects the caller to read `onOff` and invoke `on()` or `off()` accordingly. **Recommendation for the production task: derive `can_toggle` the same way `on`/`off` are derived (device has the trait ⇒ toggle is possible), but implement `toggle` client-side as read-then-invert, not as a single SDK call** — this is a real API-shape finding, not a gap in this mapping.

This is confirmed, not hypothesized — unlike ADR-033 §4's Home Assistant table, which marks its `light` brightness-bit derivation as "Hypothesis... must be validated against live payload." **Here, on/off read and both commands were physically exercised on the real lamp (GH02 §5)**; only `can_toggle`'s "no native command" finding and the brightness row below (§3.2) remain unexercised.

### `can_set_brightness`

| Google device type | Trait | Confirmed member | Ixora mapping |
| --- | --- | --- | --- |
| `DimmableLightDevice` | `standardTraits.levelControl` (Matter `LevelControlTrait`, via `com.google.home.matter.standard.LevelControl`) | `currentLevel: UByte?` (state, 0–254 per Matter's `LevelControl` cluster range), `moveToLevel(level: UByte, transitionTime: UShort?, ...)` (suspend command) | `can_set_brightness: { min: 0, max: 254, step: 1 }` |
| `OnOffLightDevice`, `OnOffPluginUnitDevice` | `standardTraits.levelControl` — **present in the generated `StandardTraits` accessor for both types, but not guaranteed non-null per device.** GH02 confirmed `standardTraits.onOff` returns a nullable `OnOff?` at runtime despite the javadoc's Java-view rendering showing a non-null return type (§4 of GH02 results) — the same nullability pattern almost certainly applies to `levelControl`. **Not exercised.** | — | Presence must be checked at runtime (`standardTraits.levelControl != null`), not assumed from the device type alone. |

**Range caveat — `0–254`, not `0–255`.** ADR-033 §4's Home Assistant brightness row uses `{min: 0, max: 255, step: 1}`, matching HA's 0–255 convention. Matter's `LevelControl` cluster's `CurrentLevel` attribute is a `UByte` documented (Matter spec, reflected in the SDK's own `getCurrentLevel(): UByte` accessor) as **0–254**, with `255` reserved as "null/undefined" in the underlying protocol. **A production implementation must not reuse ADR-033's HA-derived `{max: 255}` constraint verbatim for Google Home devices** — this is a genuine cross-provider difference in the same capability's parameter constraint, not a copy-paste value. Flagging this now is exactly the kind of thing this mapping task exists to catch before it becomes a silent off-by-one in device control.

**Confidence: hypothesis, not confirmed.** GH02 exercised on/off only; no brightness command was sent to real hardware, and no device in the discovered set was confirmed to have `LevelControl` non-null. The production task should re-verify this row against a real dimmable device before treating it as production logic — the same discipline ADR-033 §4 already applies to its own HA brightness row.

## 4. `SimplifiedOnOff` — explicitly not used for capability derivation

`com.google.home.google.SimplifiedOnOffTrait` (Google-authored trait, distinct from the Matter-standard `OnOffTrait` used above) was investigated and **excluded from this mapping**. Its own javadoc states: *"This trait provides an enum based on-off extension to the OnOff trait and is only for use with the Automation API."* It exposes only a read-only `onOff: OnOffEnum` attribute (`Off`/`On`/`UnknownValue`/`Unspecified`) and **no commands** — confirmed by the absence of any `SimplifiedOnOffCommands` interface in the SDK. It exists for Automation API condition-matching, not for the discovery/read/execute path this mapping (and GH02) targets. GH02's choice to use the Matter-standard `OnOffTrait` instead was therefore correct, not incidental.

## 5. Fail-open rule

Mirrors ADR-033 §5 exactly — no new policy invented:

- A device whose type isn't recognised (§2) or whose expected trait is present but returns `null` (§3.2) gets **no capability entry for that action**, not a capability with an unverified guess. This matches ADR-033's "capability-absent → gate blocks that action" state — it does **not** mean the device can't be discovered or read; it means an unsupported action is rejected before dispatch, exactly as it already works for Home Assistant.
- `devices.capabilities = null` (the "Unknown" state in ADR-033 §5's three-state table) applies if a production adapter cannot determine trait support at all — never invent a positive capability from device type alone without checking the actual trait provider result, the same discipline `HomeAssistantAdapter::deriveCapabilities()` already follows by reading `supported_features` rather than assuming from `domain` alone.

## 6. Traits that do not fit the current ADR-033 vocabulary

Found while reading the SDK's trait surface (`com.google.home.matter.standard`, `com.google.home.google`) — listed as candidates for a **future ADR-033 amendment**, not added here, per this task's explicit boundary:

| Trait | What it would enable | Note |
| --- | --- | --- |
| `LevelControlTrait`'s `MoveCommand`/`StepCommand` (relative dimming, not absolute `moveToLevel`) | Something like `can_adjust_brightness` (relative) distinct from `can_set_brightness` (absolute) | Not needed for light/plug on/off + absolute brightness; ADR-033 already scoped brightness as absolute (`{min,max,step}`), consistent with HA's `set_brightness`. |
| Matter `ColorControlTrait` (seen referenced in other device types during GH02's exploration, not itself queried) | `can_set_color` / `can_set_color_temp` | **ADR-033 §3 already excludes these from v1.4.0 by name**, citing unconfirmed HA bit semantics. The Google Home side has its own, better-typed `ColorControlTrait` API (not HA's ambiguous bitmask), which may make this easier to add for Google Home than it was for HA — worth noting for whoever amends ADR-033, not a reason to add it here. |
| `Identify` trait (present on both `OnOffLightDevice.StandardTraits` and `OnOffPluginUnitDevice.StandardTraits`) | A "flash to locate" capability | No ADR-033 equivalent exists; not requested by any current Ixora feature (Scenes/Vibes have no "identify device" action). Recorded, not proposed. |
| `google.SimplifiedOnOffTrait` (§4) | N/A for capability derivation | Relevant only if a future task implements Automation API delegation (ADR-036 §5's reserved `automation_delegation` provider execution capability) — a provider-level concern, not a device capability, and explicitly out of scope for v1.6.0. |

None of these are recommended for adoption now. They are recorded so a future ADR-033 amendment starts from confirmed SDK facts instead of re-deriving them.

## 7. What this document does not do

- Does not implement the mapping in code (no adapter, no `deriveCapabilities()` equivalent for Google Home).
- Does not widen the ADR-033 vocabulary — §6 is a candidates list, not a proposal to accept.
- Does not resolve GH03c (the retention question) or decide how/whether the Google device identifiers referenced by this mapping are persisted — that boundary is set by ADR-036 Decision 8 and GH03b/GH03c, untouched here.
- Does not cover locks, cameras, thermostats, or any device type beyond light/plug, per the card's explicit minimum-viable scope.

## 8. Sources

Code (verified 2026-09-06/07): `back_vibes/app/SmartHome/Adapters/HomeAssistantAdapter.php` (`deriveCapabilities()`, `mapDeviceType()`), `back_vibes/app/SmartHome/DeviceType.php`, [ADR-033](../../../decisions/ADR-033-device-capabilities.md), [ADR-035](../../../decisions/ADR-035-cross-provider-deduplication.md), [ADR-036](../../../decisions/ADR-036-google-home-execution-model.md).

SDK (javadoc extracted from the downloaded `play-services-home`/`play-services-home-types` 17.1.0 artifacts during GH02 — see [GH03a](access-gate.md) for why they aren't on Maven): `com.google.home.matter.standard.{OnOffLightDevice, OnOffPluginUnitDevice, DimmableLightDevice, OnOff, OnOffTrait, OnOffCommands, LevelControl, LevelControlTrait, LevelControlCommands}`, `com.google.home.google.{SimplifiedOnOff, SimplifiedOnOffTrait}`. [GH02 results](gh02-results.md) for the physically-verified subset of this API.
