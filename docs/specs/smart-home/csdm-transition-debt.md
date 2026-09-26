# CSDM transition — tracked debt (post CSDM-07)

**Status:** Active — documentation only; no implementation authorized here.  
**Governing decision:** [ADR-037 §8](../../decisions/ADR-037-canonical-smart-home-device-model.md) and [addendum §15](../../decisions/ADR-037-canonical-smart-home-device-model.md#15--addendum-transição-csdm-0107-estado-de-fechamento-2026-09-23).  
**Related release note:** [CSDM track — Canonical Smart Home Device Model](../../releases/csdm-canonical-device-model.md).

This is the **single linkable register** for work deliberately deferred after CSDM-07. Paying an item requires the condition stated; do not remove dual-read paths or legacy wire fields until then.

---

## 1. Home Assistant dual-write (`can_*` beside canonical envelope)

| Field | Detail |
| --- | --- |
| **Description** | `HomeAssistantCanonicalMapper::toStoredPayload()` still merges `legacyKeysFor()` ADR-033 keys (`can_turn_on`, `can_set_brightness` with HA scale bounds, etc.) alongside `contract_version` + `capabilities`. |
| **Pay when** | Every consumer that gates actions or renders controls reads the canonical envelope only (backend gate, mobile UI, admin if applicable) — **and** stored rows from HA sync no longer need legacy keys for any in-flight client build. |
| **Owner repo** | `back_vibes` (mapper + persistence path via provider sync). |
| **Risk if kept** | Two shapes on one JSON object; new code might read the wrong half; provider scale can reappear in legacy brightness bounds until sync stops emitting them. |

---

## 2. Legacy command parameters (`brightness` vs canonical `value`)

| Field | Detail |
| --- | --- |
| **Description** | `CommandValidator::LEGACY_PARAMETER_KEYS` and `LegacyCapabilityMapReader::declaredBrightnessBounds()` range-check pre-CSDM scene parameters against device-declared legacy bounds. |
| **Pay when** | Same as §1, plus confirmation that no production/staging rows rely on `{ brightness: N }` in `scene_actions.parameters` (or a one-time migration has converted them to `{ value: N }` in canonical percent). |
| **Owner repo** | `back_vibes`. |
| **Risk if kept** | Two parameter shapes on the wire; clients must not send legacy keys for new work. |

---

## 3. `LegacyCapabilitiesReader` (unused duplicate reader)

| Field | Detail |
| --- | --- |
| **Description** | Class exists at `back_vibes/app/SmartHome/Canonical/LegacyCapabilitiesReader.php`. As of 2026-09-23, **no runtime reference** under `back_vibes/app/` (verified by repository grep — only the class definition matches). Active dual-read uses `LegacyCapabilityMapReader`. |
| **Pay when** | Team confirms no external/tooling import; safe to delete or merge in a dedicated cleanup PR. |
| **Owner repo** | `back_vibes`. |
| **Risk if kept** | Low — confusion for maintainers; two readers with overlapping names. |

---

## 4. Android `BrightnessNormalization.kt` (P09 legacy 0–255 path)

| Field | Detail |
| --- | --- |
| **Description** | `GoogleHomePlugin.kt` still calls `BrightnessNormalization` for legacy `brightness` on `executeAction` / `readDeviceState` while canonical paths use `CanonicalBrightness` (0–254 ↔ 0–100 percent). Verified 2026-09-23: references in `GoogleHomePlugin.kt` and tests in `BrightnessNormalizationTest.kt`. |
| **Pay when** | No client build sends or reads the transitional `brightness` (0–255) plugin field; `brightnessPercent` / canonical `value` is the only path. |
| **Owner repo** | `front_vibes` (Android plugin under `android/app/src/main/java/app/ixora/googlehome/`). |
| **Risk if kept** | Two brightness scales at the native bridge; documentation must keep distinguishing canonical vs legacy fields. |

---

## 5. Retire `ActionType` on the API wire

| Field | Detail |
| --- | --- |
| **Description** | `scene_actions.action_type` remains `turn_on` / `set_brightness` etc. Domain logic **reinterprets** via `ActionTypeTranslation` + `CommandValidator`; enum was not removed. |
| **Pay when** | Explicit **breaking API** decision (new field or versioned endpoint for `(capability_id, operation)`), coordinated across `back_vibes`, `front_vibes`, telemetry, and any external clients. |
| **Owner repo** | Cross-cutting — lead spec/ADR in `ixora-infra`, implement per repo. |
| **Risk if kept** | HA-shaped verbs on the wire despite canonical model internally; acceptable until a deliberate API version bump. |

---

## 6. Real-device E2E — Google Home discovery and scene execute

| Field | Detail |
| --- | --- |
| **Description** | CSDM-07b automated checks and APK install were recorded; **Appium/wdio** pass for canonical-only sync payload, brightness editor 0–100, and Google scene execute was **not** completed (no verified hub/session in that pass). |
| **Evidence stub** | Workspace (not `ixora-infra` repo): [`qa/csdm-07b-front-boundary/summary.md`](../../../../qa/csdm-07b-front-boundary/summary.md) and [`qa/csdm-07b-front-boundary/evidence/`](../../../../qa/csdm-07b-front-boundary/evidence/). |
| **Pay when** | Staging + signed-in Google Home on physical device; optional HA device for mixed scene. |
| **Owner repo** | `qa` (evidence) + `front_vibes` (app under test). |
| **Risk if kept** | Regression in reported-device payload or UI only caught by unit/boundary tests, not full device flow. |

---

## Boundary guards (regression anchors — not debt)

These tests should stay green when touching Smart Home code:

| Repo | Test artifact | Role |
| --- | --- | --- |
| `back_vibes` | `tests/Unit/SmartHome/Canonical/CanonicalBoundaryTest.php` | Scale, provider, mapper, domain (via shared D.1 helpers), extensibility; sentinels. |
| `back_vibes` | `tests/Unit/SmartHome/Canonical/CapabilityContractCoherenceTest.php` | PHP ↔ vendored schema. |
| `back_vibes` | `tests/Unit/SmartHome/ProviderExtensibilityBoundaryTest.php` | ADR-032 D.1 provider slug guard. |
| `front_vibes` | `src/utils/__tests__/canonical-boundary.test.ts` | Domain vs provider frontier; sentinels. |
| `front_vibes` | `src/utils/__tests__/capability-contract-coherence.test.ts` | TS constants ↔ vendored schema. |
| `front_vibes` | `android/.../CanonicalScaleBoundaryTest.kt` | Canonical conversion API only in `CanonicalBrightness.kt`. |
