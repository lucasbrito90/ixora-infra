# Smart Home — Index

**Current state:** Home Assistant provider shipped (ADR-013). Multi-provider architecture complete (ADR-032–037). Google Home integration spec complete (ADR-036). Canonical Device Model (CSDM) established.

## Authoritative documents

| Document | Purpose |
| --- | --- |
| [`mvp/spec.md`](mvp/spec.md) | Foundation spec — provider connections, devices, vibe actions, async HA execution |
| [`canonical-device-model.md`](canonical-device-model.md) | CSDM — platform-wide device abstraction |
| [`cat-01-capability-governance.md`](cat-01-capability-governance.md) | CAT-01 governance reference — ratified/provisional/deferred capabilities, DeviceType vs capability distinction. Required reading for DEV-01 and any capability amendment. |
| [`multi-provider/current-state.md`](multi-provider/current-state.md) | Multi-provider current implementation state |
| [`multi-provider/adr-conformance.md`](multi-provider/adr-conformance.md) | Conformance review of multi-provider ADRs |

## ADRs (Smart Home)

ADR-012 through ADR-016 (foundation), ADR-032–037 (multi-provider + CSDM), ADR-022–026 (automations).
All in `ixora-infra/docs/decisions/`.

## Standards

[`../../standards/adding-a-smart-home-provider.md`](../../standards/adding-a-smart-home-provider.md) — required reading before implementing a new provider.

## Google Home

| Document | Status |
| --- | --- |
| [`google-home/access-gate.md`](google-home/access-gate.md) | Access requirements |
| [`google-home/data-retention.md`](google-home/data-retention.md) | Retention compliance |
| [`google-home/trait-capability-mapping.md`](google-home/trait-capability-mapping.md) | GH trait → CSDM mapping |

## Design

| Artifact | Telas | URL |
| --- | --- | --- |
| Smart Home — Conexões & Dispositivos | 132 | https://claude.ai/artifact/AqNLjnRW3tK3aK4mjZRdmD |
| Smart Home — Cenas & Ações | 48 | https://claude.ai/artifact/5axdL4bv4MRd56LrFfFSrF |

Routing completo (todos os 8 artifacts): [`../../specs/design-artifacts.md`](../../specs/design-artifacts.md).

## Specs (historical — implementation complete)

| Document | Status |
| --- | --- |
| [`mvp/plan.md`](mvp/plan.md) | Implementation plan (done) |
| [`mvp/tasks.md`](mvp/tasks.md) | Task checklist (done) |
| [`mvp/schema-review.md`](mvp/schema-review.md) | Schema review (done) |
| [`csdm-transition-debt.md`](csdm-transition-debt.md) | Known CSDM migration debt |
| [`canonical-device-model-audit.md`](canonical-device-model-audit.md) | CSDM audit (historical) |
| [`multi-provider/coupling-map.md`](multi-provider/coupling-map.md) | Coupling analysis |
