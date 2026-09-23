# CSDM track — Canonical Smart Home Device Model

**Track:** CSDM-01 through CSDM-07 (no single product semver — this note covers the canonical contract implementation slice, not a production release).  
**Date:** 2026-09-23  
**Status:** Engineering track **documented closed** on `develop` (see [ADR-037 §15 addendum](../decisions/ADR-037-canonical-smart-home-device-model.md#15--addendum-transição-csdm-0107-estado-de-fechamento-2026-09-23)). **Not a production release.** Platform remains in development/staging per PO decision on Google Home blockers ([v1.6.0 note](v1.6.0-google-home-integration.md)).

---

## Summary for developers

- **Contract:** Shared JSON Schema at `ixora-infra/contracts/smart-home/capability.v1.schema.json` (`x-contract-version` **1.0.0**), vendored byte-identically in `back_vibes` and `front_vibes`.
- **Domain brightness:** Canonical **0–100**, unit **percent** (ADR-037 §5). Provider scales (HA 0–255, Matter 0–254) exist only inside provider mappers / the Android plugin.
- **UI:** Scene/Vibe action editor is schema-driven from device capabilities (CSDM-06); parameters use canonical `{ value }` for set operations.
- **Guards (CSDM-07):** Source-scan boundary tests with deliberate sentinel fixtures in backend (Pest) and front (Vitest + Kotlin unit tests) — see [quality harness](../quality-harness.md#csdm-boundary-tests-baseline).

---

## What changed for users (staging/dev)

- Dimmable devices can expose **brightness 0–100%** in the action editor when the API returns canonical capabilities.
- Google Home device import reports **canonical capability envelopes** to the API (no legacy `can_*` keys generated on the mobile sync path after CSDM-07b).
- Home Assistant devices may still show legacy-shaped capability data until re-sync; the app **reads** both shapes during the transition window.

---

## Repositories and reference PRs

| Repo | PR | Focus |
| --- | --- | --- |
| `back_vibes` | [#49](https://github.com/lucasbrito90/back_vibes/pull/49) | CSDM-07a — `CanonicalBoundaryTest.php`, canonical capability gate fix |
| `front_vibes` | [#25](https://github.com/lucasbrito90/front_vibes/pull/25) | CSDM-07b — vendored schema, Google envelope-only sync, front/Kotlin guards |
| `ixora-infra` | *(this docs PR)* | Transition closure documentation |

---

## Validation (measured 2026-09-23)

| Repo | Command | Result |
| --- | --- | --- |
| `back_vibes` | `composer test` | **1410** passed, **6976** assertions (2 risky, pre-existing) |
| `front_vibes` | `npm run test:unit` | **515** passed, **48** files |
| `front_vibes` Android | `./gradlew testDebugUnitTest` | **BUILD SUCCESSFUL** — **26** JVM unit tests in `testDebugUnitTest` (summed from Gradle XML results) |

Schema identity (all three copies):

```bash
sha256sum ixora-infra/contracts/smart-home/capability.v1.schema.json \
  back_vibes/contracts/smart-home/capability.v1.schema.json \
  front_vibes/contracts/smart-home/capability.v1.schema.json
# 01398064b04ec7bad0afebdebc19ae2aef6b547eb0cfe179b4e285ead722ee1e (each)
```

---

## Transition state

| Closed | Still open (tracked debt) |
| --- | --- |
| Front no longer **generates** legacy Google sync shape | HA mapper still **writes** `can_*` beside envelope |
| Backend gate reads canonical envelope | Wire still uses `action_type` enum strings |
| Boundary tests in CI-local harness | Retire `ActionType` on API — **breaking**, not done |
| | Android `BrightnessNormalization` for legacy 0–255 plugin field |
| | Real-device Google E2E — see [`qa/csdm-07b-front-boundary/`](../../../qa/csdm-07b-front-boundary/summary.md) |

Full debt register: [`docs/specs/smart-home/csdm-transition-debt.md`](../specs/smart-home/csdm-transition-debt.md).

---

## Known limitations

- Same production blockers as [v1.6.0 Google Home integration](v1.6.0-google-home-integration.md#known-limitations) (Console, retention) — unchanged by CSDM.
- Cross-repo schema drift is **not** enforced by CI; manual vendoring + per-repo coherence tests (`contracts/README.md`).
