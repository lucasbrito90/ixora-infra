# Ixora platform documentation

**Official documentation index** for the Ixora ecosystem.  
**Repository:** [`ixora-infra`](../) — central specs, architecture, standards, ADRs, and infrastructure runbooks.

> **Source of truth.** When app-repo copies diverge, **`ixora-infra/docs/` wins**. Update this index when adding or renaming documents.

---

## Quick links

| I need to… | Start here |
| --- | --- |
| Understand the product model | [Architecture map](architecture/architecture-map.md) · [Terminology](#terminology-glossary) |
| Onboard as a developer | [Engineer onboarding](onboarding/onboarding.md) · [Onboarding path](#onboarding-path-for-new-developers) |
| Implement a feature | [Feature design checklist](architecture/feature-design-checklist.md) → [UX principles](architecture/user-experience-principles.md) → [Feature spec template](#8-templates) → [Specs](#1-specs) → related [Architecture](#2-architecture) + [Standards](#3-standards) |
| Design user-facing states or copy | [User experience principles](architecture/user-experience-principles.md) · [Notification architecture](architecture/notification-architecture.md) |
| Design or extend notifications | [Notification architecture](architecture/notification-architecture.md) · [UX principles](architecture/user-experience-principles.md) · [ADR-019](decisions/ADR-019-notification-event-taxonomy.md) · [Push spec](specs/push-notifications/mvp/spec.md) |
| Design or extend observability | [Observability Foundation spec](specs/observability-foundation/mvp/spec.md) · [ADR-028](decisions/ADR-028-observability-platform.md) · [ADR-029](decisions/ADR-029-telemetry-data-model.md) · [ADR-030](decisions/ADR-030-observability-security-and-privacy.md) · [ADR-031](decisions/ADR-031-retention-storage-and-cost-control.md) |
| Change staging infra or deploy | [Infrastructure](#5-infrastructure) · [Operations](#6-operations) · [Quality & testing](#7-quality--testing) |
| Understand a past decision | [ADRs](#4-architecture-decision-records-adrs) |
| Know what we deliberately did **not** build | [Intentionally not implemented](#intentionally-not-implemented) |

---

## Project overview

**Ixora** is a multi-client ambient audio platform: users compose **vibes** (layered sound + visuals) from a **catalog** of **sounds** and **cover bundles**, play them on **mobile**, and admins curate catalog content via a **web panel**.

| Layer | Repository | Role |
| --- | --- | --- |
| **API & domain** | [`back_vibes`](../../back_vibes) | Laravel — auth sync, catalog CRUD, uploads to Spaces, policies, queues |
| **Mobile app** | [`front_vibes`](../../front_vibes) | Ionic + Vue + Capacitor — playback, execution plan, offline download |
| **Admin panel** | [`ixora-admin`](../../ixora-admin) | Nuxt — catalog maintenance, multipart uploads via API |
| **Infra & docs** | [`ixora-infra`](../) | OpenTofu staging stack, **this documentation tree** |

**Identity:** Firebase Authentication (Google, email/password) → JWT → Laravel **`POST /api/auth/sync`** → PostgreSQL **`users`**.  
**Assets:** DigitalOcean Spaces + CDN; **Laravel-only writes** ([ADR-002](decisions/ADR-002-laravel-only-storage-writes.md)).  
**Playback:** **Client-only** — mobile builds an **execution plan** and drives native audio; **no backend play engine**.

**Homologation:** Git branch **`staging`** → DigitalOcean App Platform (API, admin). Mobile uses **`build:staging`** against the staging API.

---

## Repository responsibilities

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   front_vibes   │     │   ixora-admin   │     │   back_vibes    │
│  Mobile client  │     │  Static admin   │     │  Laravel API    │
│  Play + offline │     │  Catalog forms  │     │  Writes + rules │
└────────┬────────┘     └────────┬────────┘     └────────┬────────┘
         │                       │                       │
         └───────────────────────┼───────────────────────┘
                                 │ HTTPS + Firebase JWT
                                 ▼
                    ┌────────────────────────┐
                    │ PostgreSQL + Spaces CDN │
                    └────────────────────────┘
                                 ▲
                    ┌────────────┴────────────┐
                    │      ixora-infra        │
                    │  OpenTofu + docs (here)  │
                    └────────────────────────┘
```

| Repository | Owns | Does **not** own |
| --- | --- | --- |
| **`back_vibes`** | REST API, migrations, Spaces I/O, queue jobs, Firebase token verify | Mobile UI, admin UI, IaC |
| **`front_vibes`** | Player, execution plan, offline manifests, Capacitor native stack | Catalog writes, direct Spaces access |
| **`ixora-admin`** | Admin UX, Nuxt generate static site | Business rules, Spaces credentials |
| **`ixora-infra`** | Staging OpenTofu, central docs, Git Flow standard | Application source (lives in app repos) |

**Detailed boundaries:** [repo-responsibilities.md](architecture/repo-responsibilities.md)

Each repo has its **own** `main`, `develop`, and **`staging`** branches ([Git Flow](standards/git-flow.md)).

---

## Architecture map

**Platform overview (components & flows):** [architecture/architecture-map.md](architecture/architecture-map.md) · [architecture/repo-responsibilities.md](architecture/repo-responsibilities.md)

High-level **document** map by domain. **Bold** = active source of truth; *italic* = planning only.

```
docs/architecture/
├── feature-design-checklist.md      ← Pre-spec checklist — read BEFORE Feature Specification Template
├── domain-validation.md             ← HTTP Policies vs background Domain Validators (ADR-026)
├── asynchronous-orchestration.md    ← Async layering: entrypoint → validator → service → job → provider (ADR-027)
├── notification-architecture.md     ← Platform-wide notification design — types, builders, payload, local vs push (ADR-017, ADR-024)
├── user-experience-principles.md    ← Platform-wide UX — loading, empty, error, microcopy, a11y (ADR-024, ADR-025)
├── backend/
│   ├── staging-digitalocean.md      ← Staging topology (DO App Platform)
│   ├── deploy-pipeline.md           ← Git → OpenTofu → App Platform
│   └── scheduling-model.md          ← *Future automation — NOT shipped*
├── storage/
│   ├── storage-strategy.md          ← Spaces policy, keys, deletion
│   ├── spaces-cdn-policy.md         ← CDN URLs, cache, offline identity
│   ├── mobile-cdn-validation.md   ← Device QA for asset URLs
│   ├── artwork-background-strategy.md
│   └── future-processing-pipeline.md ← *Transcode/resize — NOT shipped*
├── audio/
│   ├── playback-runtime.md          ← Pinia, AudioEngine, FGS, native audio
│   ├── audio-cache.md               ← Streaming cache vs offline download
│   ├── audio-engine-fade-limitations.md
│   └── native-loop-fadein.md
└── mobile/
    └── android-native-customizations.md
```

| Domain | Primary doc | Related specs / ADRs |
| --- | --- | --- |
| **Auth** | [front-vibes-auth-core](standards/front-vibes-auth-core.md) | [ADR-001](decisions/ADR-001-firebase-auth-laravel-sync.md) |
| **Storage / CDN** | [storage-strategy](architecture/storage/storage-strategy.md) · [spaces-cdn-policy](architecture/storage/spaces-cdn-policy.md) | [ADR-002](decisions/ADR-002-laravel-only-storage-writes.md) · [ADR-006](decisions/ADR-006-no-direct-mobile-uploads.md) |
| **Playback** | [playback-runtime](architecture/audio/playback-runtime.md) | [execution-plan](specs/vibes/execution-plan/spec.md) · [ADR-007](decisions/ADR-007-execution-plan-runtime-contract.md) · [ADR-008](decisions/ADR-008-nativeaudio-limitations-over-unstable-dsp.md) |
| **Offline** | [audio-cache](architecture/audio/audio-cache.md) | [offline-download](specs/vibes/offline-download/spec.md) · [ADR-004](decisions/ADR-004-offline-audio-strategy.md) |
| **Presets** | [preset-vibes](specs/preset-vibes/spec.md) | [ADR-003](decisions/ADR-003-preset-import-independent-vibes.md) · [ADR-005](decisions/ADR-005-no-realtime-preset-sync.md) |
| **Scheduler (MVP)** | [scheduler/mvp/spec](specs/scheduler/mvp/spec.md) | [ADR-009](decisions/ADR-009-scheduler-timezone-utc-storage.md) · [ADR-010](decisions/ADR-010-scheduler-idempotency-occurrence-key.md) · [ADR-011](decisions/ADR-011-scheduler-local-notifications-vs-future-fcm.md) |
| **Smart Home (Foundation)** | [smart-home/mvp/spec](specs/smart-home/mvp/spec.md) | [ADR-012](decisions/ADR-012-smart-home-provider-strategy.md) · [ADR-013](decisions/ADR-013-home-assistant-first-provider.md) · [ADR-014](decisions/ADR-014-device-abstraction-and-deduplication.md) · [ADR-015](decisions/ADR-015-vibe-device-action-architecture.md) · [ADR-016](decisions/ADR-016-smart-home-async-execution.md) |
| **Push Notifications (Foundation)** | [push-notifications/mvp/spec](specs/push-notifications/mvp/spec.md) · [notification-architecture](architecture/notification-architecture.md) | [ADR-017](decisions/ADR-017-push-notification-provider-strategy.md) · [ADR-018](decisions/ADR-018-device-token-registration.md) · [ADR-019](decisions/ADR-019-notification-event-taxonomy.md) · [ADR-020](decisions/ADR-020-push-delivery-and-fallback-strategy.md) · [ADR-021](decisions/ADR-021-notification-security-and-privacy.md) · [ADR-011](decisions/ADR-011-scheduler-local-notifications-vs-future-fcm.md) · [asynchronous-orchestration](architecture/asynchronous-orchestration.md) |
| **Scheduler + Smart Home Automations** | [scheduler-smart-home-automations/mvp/spec](specs/scheduler-smart-home-automations/mvp/spec.md) · [operational checklist](operations/scheduler-smart-home-operational-checklist.md) · [E2E QA report](qa/scheduler-smart-home-e2e/summary.md) | [ADR-022](decisions/ADR-022-scheduler-smart-home-automation-model.md) · [ADR-023](decisions/ADR-023-automation-execution-order-and-failure-policy.md) · [ADR-024](decisions/ADR-024-automation-notifications-and-observability.md) · [ADR-025](decisions/ADR-025-automation-mobile-ux.md) · [ADR-026](decisions/ADR-026-automation-execution-security.md) · [ADR-027](decisions/ADR-027-asynchronous-orchestration-pattern.md) · [domain-validation](architecture/domain-validation.md) · [asynchronous-orchestration](architecture/asynchronous-orchestration.md) · [notification-architecture](architecture/notification-architecture.md) · [user-experience-principles](architecture/user-experience-principles.md) |
| **Observability (Foundation)** | [observability-foundation/mvp/spec](specs/observability-foundation/mvp/spec.md) | [ADR-028](decisions/ADR-028-observability-platform.md) · [ADR-029](decisions/ADR-029-telemetry-data-model.md) · [ADR-030](decisions/ADR-030-observability-security-and-privacy.md) · [ADR-031](decisions/ADR-031-retention-storage-and-cost-control.md) · [ADR-024](decisions/ADR-024-automation-notifications-and-observability.md) |
| **Async execution security** | [domain-validation](architecture/domain-validation.md) | [ADR-026](decisions/ADR-026-automation-execution-security.md) · [ADR-010](decisions/ADR-010-scheduler-idempotency-occurrence-key.md) · [ADR-016](decisions/ADR-016-smart-home-async-execution.md) |
| **Async orchestration** | [asynchronous-orchestration](architecture/asynchronous-orchestration.md) | [ADR-027](decisions/ADR-027-asynchronous-orchestration-pattern.md) · [ADR-026](decisions/ADR-026-automation-execution-security.md) · [domain-validation](architecture/domain-validation.md) |
| **Staging ops** | [staging-digitalocean](architecture/backend/staging-digitalocean.md) | [deploy-pipeline](architecture/backend/deploy-pipeline.md) |

---

## Current platform status

*As documented in this tree — May 2026.*

| Area | Status |
| --- | --- |
| **Firebase auth + Laravel sync** | Shipped — all clients |
| **Catalog sounds (admin create)** | Shipped — multipart → Spaces → CDN URLs |
| **Cover bundles (admin create)** | Shipped |
| **Preset vibe catalog + import** | Shipped — copy-on-import, no live sync |
| **User vibes (mobile create/edit)** | Shipped |
| **Vibe sounds (layers)** | Shipped — pivot config on `vibe_sounds` |
| **Mobile playback + mini player** | Shipped — Android primary; `@capgo/native-audio` |
| **Execution plan** | Shipped — client-only ([ADR-007](decisions/ADR-007-execution-plan-runtime-contract.md)) |
| **Offline download** | Shipped — explicit native download + manifests ([ADR-004](decisions/ADR-004-offline-audio-strategy.md)) |
| **Scheduler MVP** | Shipped — recurrence, local notifications, dispatcher ([scheduler/mvp/spec](specs/scheduler/mvp/spec.md)) |
| **Smart Home MVP** | Shipped — provider connections, devices, vibe actions, async HA execution ([smart-home/mvp/spec](specs/smart-home/mvp/spec.md)) |
| **Push Notifications Foundation** | Spec + ADRs 017–021 accepted — **not implemented** ([push-notifications/mvp/spec](specs/push-notifications/mvp/spec.md)) |
| **Scheduler + Smart Home Automations** | Shipped — v1.2.0 ([release notes](releases/v1.2.0-scheduler-smart-home-automations.md)) |
| **Observability Foundation** | Phase 1 — ADRs + Spec ([observability-foundation/mvp/spec](specs/observability-foundation/mvp/spec.md); ADRs 028–031) |
| **Staging environment** | Shipped — DO App Platform + OpenTofu ([staging-digitalocean](architecture/backend/staging-digitalocean.md)) |
| **Safe delete (sounds, cover bundles)** | Shipped — reference-checked Spaces cleanup |
| **Legacy Firebase asset URLs** | May coexist on rows until migration |
| **Production deploy topology** | Documented via Git Flow; prod IaC not in this index’s scope |

---

## Intentionally not implemented

Do **not** build or document these as shipped without a new spec + ADR.

| Capability | Why / pointer |
| --- | --- |
| **Backend playback / scheduler runtime** | Manual mobile play only today — [scheduling-model](architecture/backend/scheduling-model.md) (*planning*); MVP spec in progress — [scheduler/mvp/spec](specs/scheduler/mvp/spec.md) |
| **Time-based vibe automation (shipped)** | Not shipped — schema stubs only; see Scheduler MVP spec + ADRs 009–011 |
| **Preset → vibe realtime sync** | [ADR-005](decisions/ADR-005-no-realtime-preset-sync.md) |
| **Direct client → Spaces uploads** | [ADR-002](decisions/ADR-002-laravel-only-storage-writes.md) · [ADR-006](decisions/ADR-006-no-direct-mobile-uploads.md) |
| **Presigned / signed CDN URLs** | [spaces-cdn-policy](architecture/storage/spaces-cdn-policy.md) |
| **Transcoding, resize pipelines, waveforms** | [future-processing-pipeline](architecture/storage/future-processing-pipeline.md) (*planning*) |
| **Kubernetes, multi-region, blue/green deploy** | [staging-digitalocean](architecture/backend/staging-digitalocean.md) |
| **CDN purge / invalidation API** | [spaces-cdn-policy](architecture/storage/spaces-cdn-policy.md) |
| **Mobile catalog uploads** | Not shipped — read-only asset consumption |
| **JS audio fades / crossfade** | Ignored at runtime — [ADR-008](decisions/ADR-008-nativeaudio-limitations-over-unstable-dsp.md) |
| **Smart Home non-MVP providers** (Alexa, Google Home, Matter, Tuya, Zigbee direct) | Out of scope — future provider ADRs required per integration |
| **FCM / push notifications (shipped)** | Not shipped — spec + ADRs 017–021 accepted; local notifications remain for Scheduler — [push-notifications/mvp/spec](specs/push-notifications/mvp/spec.md) |
| **Observability alerting / PagerDuty** | Out of MVP — dashboards first — [observability-foundation/mvp/spec](specs/observability-foundation/mvp/spec.md) |
| **Direct app → Prometheus/Loki/Tempo** | Forbidden — Collector only — [ADR-028](decisions/ADR-028-observability-platform.md) |
| **Marketing / campaign push** | Out of scope — [ADR-019](decisions/ADR-019-notification-event-taxonomy.md) |
| **iOS / APNs push** | Deferred — Android FCM first — [ADR-017](decisions/ADR-017-push-notification-provider-strategy.md) |
| **Automatic background vibe sync** | [ADR-004](decisions/ADR-004-offline-audio-strategy.md) |

---

## Platform roadmap

Cross-cutting capabilities in delivery order. **Bold** = active spec work; *italic* = shipped.

| # | Capability | Status | Spec / release |
| ---: | --- | --- | --- |
| 1 | Push Notifications Foundation | *Shipped* | [v1.1.0](releases/v1.1.0-push-notifications.md) |
| 2 | Scheduler + Smart Home Automations | *Shipped* | [v1.2.0](releases/v1.2.0-scheduler-smart-home-automations.md) |
| 3 | **Observability Foundation** | **Phase 1 — ADRs + Spec** | [observability-foundation/mvp/spec](specs/observability-foundation/mvp/spec.md) |
| 4 | Smart Home Scenes | Planned | — (Phase 1 ADRs + Spec next) |
| 5 | Multi-provider Smart Home | Planned | — |
| 6 | Analytics | Planned | — |

---

## Terminology glossary

| Term | Definition |
| --- | --- |
| **Vibe** | A **user-owned ambient composition**: metadata + visual URLs + ordered **layers** (`vibe_sounds`) pointing at **catalog sounds**. Played manually on mobile — not executed by the server. |
| **Preset** | An **admin-curated template** (`preset_vibes` + `preset_vibe_sounds`) in the read-only catalog. Users **import** once into a **new independent vibe** — no ongoing link ([ADR-003](decisions/ADR-003-preset-import-independent-vibes.md)). |
| **Execution plan** | Pure **client-side** transform: `VibeSound[]` → ordered **`VibeExecutionLayer[]`** (`play_mode`, timing, `fileUrl`). Built by `buildVibeExecutionPlan` — **not** a server contract ([execution-plan spec](specs/vibes/execution-plan/spec.md)). |
| **Cover bundle** | Reusable **visual kit** (thumbnail, artwork, player background CDN URLs). Admin-managed catalog entity; mobile **copies URL strings** onto vibes — does not auto-sync visuals later. |
| **Offline manifest** | Capacitor **Preferences** documents storing downloaded audio paths + vibe snapshot: `ixora_offline_audio_manifest_v1` (per sound URL) and `offline_vibe_manifest_v1` (vibe metadata for plan rebuild). Exact **`remoteUrl`** match required ([ADR-004](decisions/ADR-004-offline-audio-strategy.md)). |
| **Catalog sound** | Admin-managed **`sounds`** row: audio + thumbnail on CDN, shared across vibes via **`sound_id`** on pivots. Users do not upload catalog audio from mobile today. |
| **Layer** | One **sound attached to a vibe** via `vibe_sounds`: volume, `play_mode` (loop / once / interval), timing fields, `sort_order`. Maps to one **execution plan layer** at play time. |

---

## Onboarding path for new developers

**Full guide:** [onboarding/onboarding.md](onboarding/onboarding.md)

### Day 1 — Context

1. Read [Project overview](#project-overview) and [Terminology](#terminology-glossary).
2. [Git Flow](standards/git-flow.md) — branch rules (**never commit to `develop` / `staging` / `main`**).
3. [ADR-001](decisions/ADR-001-firebase-auth-laravel-sync.md) — how auth works end-to-end.
4. [storage-strategy](architecture/storage/storage-strategy.md) — who touches Spaces.

### Day 2 — Your surface area

| If you work on… | Read next |
| --- | --- |
| **Laravel API** | [api-resource-patterns](standards/api-resource-patterns.md) · [laravel-form-request-patterns](standards/laravel-form-request-patterns.md) · [upload-validation](standards/upload-validation.md) |
| **Admin (Nuxt)** | [admin-form-patterns](standards/admin-form-patterns.md) · [upload-validation](standards/upload-validation.md) |
| **Mobile** | [front-vibes-auth-core](standards/front-vibes-auth-core.md) · [front-vibes-ionic-routing](standards/front-vibes-ionic-routing.md) · [playback-runtime](architecture/audio/playback-runtime.md) |
| **Infra / staging** | [staging-digitalocean](architecture/backend/staging-digitalocean.md) · [deploy-pipeline](architecture/backend/deploy-pipeline.md) · [opentofu/staging README](../opentofu/staging/README.md) |

### Day 3 — Feature work

1. Complete the [Feature design checklist](architecture/feature-design-checklist.md) before drafting a new spec.
2. Review [User experience principles](architecture/user-experience-principles.md) — §12 UX checklist for loading, empty, error, and copy.
3. Find the **spec** in [§1 Specs](#1-specs) (or copy the [template](#8-templates)).
4. Read linked **architecture** + **ADRs**.
5. Create **`feature/…`** from **`develop`**, open PR → **`develop`**.

---

## Recommended reading order

**Full-stack feature (example: new catalog upload field)**

1. Feature **spec** (acceptance criteria)  
2. [upload-validation](standards/upload-validation.md) + [storage-strategy](architecture/storage/storage-strategy.md)  
3. [ADR-002](decisions/ADR-002-laravel-only-storage-writes.md)  
4. [admin-form-patterns](standards/admin-form-patterns.md) if admin UI involved  
5. [mobile-cdn-validation](architecture/storage/mobile-cdn-validation.md) if mobile displays the asset  

**Mobile feature (native behaviour, notifications, offline)**

1. Feature **spec** (acceptance criteria)  
2. [user-experience-principles](architecture/user-experience-principles.md) — loading, empty, error, a11y  
3. [notification-architecture](architecture/notification-architecture.md) if notifications involved  
4. [quality-harness](quality-harness.md) — unit/lint/typecheck/build baseline  
5. [mobile-e2e-testing](testing/mobile-e2e-testing.md) — Appium critical path before release  
6. [mobile-cdn-validation](architecture/storage/mobile-cdn-validation.md) if assets on device  

**Mobile playback change**

1. [execution-plan spec](specs/vibes/execution-plan/spec.md)  
2. [playback-runtime spec](specs/vibes/playback-runtime/spec.md) + [architecture/audio/playback-runtime](architecture/audio/playback-runtime.md)  
3. [ADR-007](decisions/ADR-007-execution-plan-runtime-contract.md) · [ADR-008](decisions/ADR-008-nativeaudio-limitations-over-unstable-dsp.md)  

**Staging deploy or env var**

1. [git-flow](standards/git-flow.md) — `develop` → `staging`  
2. [deploy-pipeline](architecture/backend/deploy-pipeline.md)  
3. [staging-digitalocean](architecture/backend/staging-digitalocean.md)  
4. [opentofu/staging README](../opentofu/staging/README.md)  

**Notification or push change**

1. [notification-architecture](architecture/notification-architecture.md)  
2. [user-experience-principles](architecture/user-experience-principles.md) — §5 Notifications, §6 Microcopy  
3. [ADR-019](decisions/ADR-019-notification-event-taxonomy.md) · [ADR-021](decisions/ADR-021-notification-security-and-privacy.md)  
4. [push-notifications/mvp/spec](specs/push-notifications/mvp/spec.md)  
5. For automation context: [ADR-024](decisions/ADR-024-automation-notifications-and-observability.md) · [asynchronous-orchestration](architecture/asynchronous-orchestration.md)  

**Scheduler + Smart Home operations**

1. [scheduler-smart-home-operational-checklist](operations/scheduler-smart-home-operational-checklist.md)  
2. [staging-digitalocean](architecture/backend/staging-digitalocean.md) — worker topology  
3. [scheduler-smart-home-automations/mvp/spec](specs/scheduler-smart-home-automations/mvp/spec.md)  
4. [E2E QA report — Phase 8](qa/scheduler-smart-home-e2e/summary.md) — automated + on-device pending  

**Observability Foundation**

1. [observability-foundation/mvp/spec](specs/observability-foundation/mvp/spec.md)  
2. [ADR-028](decisions/ADR-028-observability-platform.md) — Collector-only ingestion  
3. [ADR-029](decisions/ADR-029-telemetry-data-model.md) — metrics, logs, traces, events  
4. [ADR-030](decisions/ADR-030-observability-security-and-privacy.md) — redaction and PII  
5. [ADR-031](decisions/ADR-031-retention-storage-and-cost-control.md) — retention and cost  
6. [asynchronous-orchestration](architecture/asynchronous-orchestration.md) — trace spans for async layers  

**Mobile UX or presentation polish**

1. [user-experience-principles](architecture/user-experience-principles.md)  
2. [ADR-025](decisions/ADR-025-automation-mobile-ux.md) if automation-related  
3. [notification-architecture](architecture/notification-architecture.md) if notifications involved  
4. Feature **spec** acceptance criteria for the target screens  

---

# 1. Specs

Feature contracts: **goal, scope, API, acceptance criteria**. Prefer **`spec.md`** for behaviour; **`plan.md`** / **`tasks.md`** for implementation notes where present.

> **New specs:** complete [`architecture/feature-design-checklist.md`](architecture/feature-design-checklist.md) first, review [`architecture/user-experience-principles.md`](architecture/user-experience-principles.md) (§12 UX checklist), then copy [`templates/feature-spec-template.md`](templates/feature-spec-template.md) — Architecture Mapping is **required** before implementation ([ADR-026](decisions/ADR-026-automation-execution-security.md), [ADR-027](decisions/ADR-027-asynchronous-orchestration-pattern.md)).

## Sounds

| Document | Description |
| --- | --- |
| [create-sound/spec.md](specs/sounds/create-sound/spec.md) | Admin multipart create — audio + thumbnail → Spaces → CDN |
| [create-sound/plan.md](specs/sounds/create-sound/plan.md) | Implementation plan |
| [create-sound/tasks.md](specs/sounds/create-sound/tasks.md) | Task checklist |

## Cover bundles

| Document | Description |
| --- | --- |
| [create-cover-bundle/spec.md](specs/covers/create-cover-bundle/spec.md) | Admin create — three images, CDN URLs on row |
| [create-cover-bundle/plan.md](specs/covers/create-cover-bundle/plan.md) | Implementation plan |
| [create-cover-bundle/tasks.md](specs/covers/create-cover-bundle/tasks.md) | Task checklist |

## Preset vibes (catalog templates)

| Document | Description |
| --- | --- |
| [preset-vibes/spec.md](specs/preset-vibes/spec.md) | Curated template catalog — admin CRUD, mobile browse |
| [preset-vibes/import/spec.md](specs/preset-vibes/import/spec.md) | One-time import → independent user vibe |

## Vibes (user compositions)

| Document | Description |
| --- | --- |
| [create-vibe/spec.md](specs/vibes/create-vibe/spec.md) | Mobile create personal vibe + optional cover apply |
| [create-vibe/plan.md](specs/vibes/create-vibe/plan.md) | Implementation plan |
| [create-vibe/tasks.md](specs/vibes/create-vibe/tasks.md) | Task checklist |
| [update-vibe/spec.md](specs/vibes/update-vibe/spec.md) | Patch vibe metadata and visuals |
| [vibe-sounds/spec.md](specs/vibes/vibe-sounds/spec.md) | Layer model — pivot fields, API shape |
| [manage-vibe-sounds/spec.md](specs/vibes/manage-vibe-sounds/spec.md) | Attach/update/detach catalog sounds on a vibe |
| [apply-cover-bundle/spec.md](specs/vibes/apply-cover-bundle/spec.md) | Copy cover bundle CDN URLs onto vibe form |
| [offline-download/spec.md](specs/vibes/offline-download/spec.md) | Explicit download for offline playback |
| [playback-runtime/spec.md](specs/vibes/playback-runtime/spec.md) | Mobile playback behaviour — spec-level |
| [execution-plan/spec.md](specs/vibes/execution-plan/spec.md) | `VibeExecutionLayer[]` contract — client-only |

## Scheduler (MVP — pre-implementation)

| Document | Description |
| --- | --- |
| [scheduler/mvp/spec.md](specs/scheduler/mvp/spec.md) | Time-based vibe reminders — Phase 2 TDD RecurrenceService first; **`monthly` reserved** |
| [scheduler/mvp/plan.md](specs/scheduler/mvp/plan.md) | 10-phase implementation plan |
| [scheduler/mvp/tasks.md](specs/scheduler/mvp/tasks.md) | Task checklist |

## Smart Home (MVP)

| Document | Description |
| --- | --- |
| [smart-home/mvp/spec.md](specs/smart-home/mvp/spec.md) | Device management + vibe action model — Home Assistant first; provider adapter architecture |
| [smart-home/mvp/plan.md](specs/smart-home/mvp/plan.md) | 10-phase implementation plan |
| [smart-home/mvp/tasks.md](specs/smart-home/mvp/tasks.md) | Task checklist |

## Push Notifications (Foundation — pre-implementation)

| Document | Description |
| --- | --- |
| [push-notifications/mvp/spec.md](specs/push-notifications/mvp/spec.md) | FCM device token registry + backend push abstraction — Android first; no campaigns |
| [push-notifications/mvp/plan.md](specs/push-notifications/mvp/plan.md) | 10-phase implementation plan |
| [push-notifications/mvp/tasks.md](specs/push-notifications/mvp/tasks.md) | Task checklist |

## Scheduler + Smart Home Automations (Phase 1 — ADRs + Spec)

| Document | Description |
| --- | --- |
| [scheduler-smart-home-automations/mvp/spec.md](specs/scheduler-smart-home-automations/mvp/spec.md) | Compose Schedule + Vibe + VibeDeviceAction — no automation engine; dispatcher integration + mobile surfacing |
| [scheduler-smart-home-automations/mvp/plan.md](specs/scheduler-smart-home-automations/mvp/plan.md) | 8-phase implementation plan |
| [scheduler-smart-home-automations/mvp/tasks.md](specs/scheduler-smart-home-automations/mvp/tasks.md) | Task checklist |

**ADRs:** [ADR-022](decisions/ADR-022-scheduler-smart-home-automation-model.md) · [ADR-023](decisions/ADR-023-automation-execution-order-and-failure-policy.md) · [ADR-024](decisions/ADR-024-automation-notifications-and-observability.md) · [ADR-025](decisions/ADR-025-automation-mobile-ux.md) · [ADR-026](decisions/ADR-026-automation-execution-security.md)

## Observability Foundation (Phase 1 — ADRs + Spec)

| Document | Description |
| --- | --- |
| [observability-foundation/mvp/spec.md](specs/observability-foundation/mvp/spec.md) | OpenTelemetry Collector pipeline — Prometheus, Loki, Tempo, Grafana; staging VM MVP |
| [observability-foundation/mvp/plan.md](specs/observability-foundation/mvp/plan.md) | 11-phase implementation plan + release |
| [observability-foundation/mvp/tasks.md](specs/observability-foundation/mvp/tasks.md) | Task checklist |

**ADRs:** [ADR-028](decisions/ADR-028-observability-platform.md) · [ADR-029](decisions/ADR-029-telemetry-data-model.md) · [ADR-030](decisions/ADR-030-observability-security-and-privacy.md) · [ADR-031](decisions/ADR-031-retention-storage-and-cost-control.md)

---

# 2. Architecture

System design, boundaries, and runtime behaviour — **not** feature acceptance checklists.

## Cross-cutting

| Document | Status | Description |
| --- | --- | --- |
| [feature-design-checklist.md](architecture/feature-design-checklist.md) | Active | **Pre-spec checklist** — product, domain, architecture, security, failure, and review questions before Feature Specification Template ([ADR-026](decisions/ADR-026-automation-execution-security.md), [ADR-027](decisions/ADR-027-asynchronous-orchestration-pattern.md)) |
| [domain-validation.md](architecture/domain-validation.md) | Active | **HTTP Policies vs Domain Validators** — async execution security ([ADR-026](decisions/ADR-026-automation-execution-security.md)) |
| [asynchronous-orchestration.md](architecture/asynchronous-orchestration.md) | Active | **Async layering** — entrypoint → validator → service → job → provider ([ADR-027](decisions/ADR-027-asynchronous-orchestration-pattern.md); complements [domain-validation](architecture/domain-validation.md)) |
| [notification-architecture.md](architecture/notification-architecture.md) | Active | **Notification design** — platform-wide types, builders, payload rules, local vs push, failure policy ([ADR-017](decisions/ADR-017-push-notification-provider-strategy.md), [ADR-024](decisions/ADR-024-automation-notifications-and-observability.md); complements [asynchronous-orchestration](architecture/asynchronous-orchestration.md)) |
| [user-experience-principles.md](architecture/user-experience-principles.md) | Active | **UX architecture** — loading, empty, error, microcopy, badges, a11y, navigation ([ADR-024](decisions/ADR-024-automation-notifications-and-observability.md), [ADR-025](decisions/ADR-025-automation-mobile-ux.md); complements [feature-design-checklist](architecture/feature-design-checklist.md) and [notification-architecture](architecture/notification-architecture.md)) |

## Backend

| Document | Status | Description |
| --- | --- | --- |
| [repo-responsibilities.md](architecture/repo-responsibilities.md) | Active | **Per-repo ownership** — must/must-not, anti-patterns |
| [staging-digitalocean.md](architecture/backend/staging-digitalocean.md) | Active | Staging DO topology — API, worker, Postgres, Spaces, Firebase |
| [deploy-pipeline.md](architecture/backend/deploy-pipeline.md) | Active | Git Flow → OpenTofu → App Platform delivery |
| [scheduling-model.md](architecture/backend/scheduling-model.md) | *Planning* | Future automation — **not shipped** |

## Storage

| Document | Status | Description |
| --- | --- | --- |
| [storage-strategy.md](architecture/storage/storage-strategy.md) | Active | Spaces access, key layout, safe deletion |
| [spaces-cdn-policy.md](architecture/storage/spaces-cdn-policy.md) | Active | CDN URLs, cache, offline URL identity |
| [mobile-cdn-validation.md](architecture/storage/mobile-cdn-validation.md) | Active | Device QA for HTTPS assets |
| [artwork-background-strategy.md](architecture/storage/artwork-background-strategy.md) | Active | Artwork vs player background selection |
| [future-processing-pipeline.md](architecture/storage/future-processing-pipeline.md) | *Planning* | Future transcode/derivatives — **not shipped** |

## Audio & playback

| Document | Status | Description |
| --- | --- | --- |
| [playback-runtime.md](architecture/audio/playback-runtime.md) | Active | Pinia, services, native audio, FGS |
| [audio-cache.md](architecture/audio/audio-cache.md) | Active | ExoPlayer cache vs offline files |
| [audio-engine-fade-limitations.md](architecture/audio/audio-engine-fade-limitations.md) | Active | Why fades are not applied in JS |
| [native-loop-fadein.md](architecture/audio/native-loop-fadein.md) | Active | Native loop / fade-in constraints |

## Mobile platform

| Document | Status | Description |
| --- | --- | --- |
| [android-native-customizations.md](architecture/mobile/android-native-customizations.md) | Active | Capacitor/Android patches and native hooks |

---

# 3. Standards

Mandatory engineering conventions — use in code review and AI-assisted development.

| Document | Applies to | Description |
| --- | --- | --- |
| [git-flow.md](standards/git-flow.md) | All repos | Branches, merges, staging, multi-repo coordination |
| [upload-validation.md](standards/upload-validation.md) | API + admin | Multipart limits, MIME, Laravel upload flow |
| [admin-form-patterns.md](standards/admin-form-patterns.md) | ixora-admin | Form composables, CDN previews, error UX |
| [api-resource-patterns.md](standards/api-resource-patterns.md) | back_vibes | JSON resource shape, URL fields |
| [laravel-form-request-patterns.md](standards/laravel-form-request-patterns.md) | back_vibes | Validation, authorization hooks |
| [front-vibes-auth-core.md](standards/front-vibes-auth-core.md) | front_vibes | Firebase + API auth lifecycle |
| [front-vibes-ionic-routing.md](standards/front-vibes-ionic-routing.md) | front_vibes | Routes, guards, navigation |

---

# 4. Architecture Decision Records (ADRs)

Accepted decisions with context, tradeoffs, and links to implementation.

| ADR | Title | Summary |
| --- | --- | --- |
| [ADR-001](decisions/ADR-001-firebase-auth-laravel-sync.md) | Firebase auth + Laravel sync | Firebase IdP; JWT verify; `firebase_uid` mapping |
| [ADR-002](decisions/ADR-002-laravel-only-storage-writes.md) | Laravel-only Spaces writes | No direct client uploads; CDN URLs from API |
| [ADR-003](decisions/ADR-003-preset-import-independent-vibes.md) | Preset import = independent copy | No `preset_vibe_id` lineage on user vibes |
| [ADR-004](decisions/ADR-004-offline-audio-strategy.md) | Offline via explicit download | CapacitorHttp + manifests; not ExoPlayer cache alone |
| [ADR-005](decisions/ADR-005-no-realtime-preset-sync.md) | No preset→vibe sync | Catalog edits do not mutate imports |
| [ADR-006](decisions/ADR-006-no-direct-mobile-uploads.md) | No direct mobile Spaces access | Mobile read-only; corollary to ADR-002 |
| [ADR-007](decisions/ADR-007-execution-plan-runtime-contract.md) | Execution plan runtime contract | Client plan is canonical playback input |
| [ADR-008](decisions/ADR-008-nativeaudio-limitations-over-unstable-dsp.md) | Stability over JS DSP | No fades/crossfade in unstable JS path |
| [ADR-009](decisions/ADR-009-scheduler-timezone-utc-storage.md) | Scheduler timezone + UTC storage | IANA per schedule; UTC instants; DST skip/first-wins |
| [ADR-010](decisions/ADR-010-scheduler-idempotency-occurrence-key.md) | Scheduler idempotency | **`occurrence_key`**; unique index; audit ≠ playback |
| [ADR-011](decisions/ADR-011-scheduler-local-notifications-vs-future-fcm.md) | Local notifications vs FCM | Android reminders first; no FCM/offline edit in MVP |
| [ADR-012](decisions/ADR-012-smart-home-provider-strategy.md) | Smart Home provider strategy | Provider adapter architecture; backend authoritative; no direct brand integrations |
| [ADR-013](decisions/ADR-013-home-assistant-first-provider.md) | Home Assistant first provider | HA first; manual base URL + LLAT; no auto-discovery |
| [ADR-014](decisions/ADR-014-device-abstraction-and-deduplication.md) | Device abstraction + deduplication | Unique per `(user_id, provider, provider_device_id)`; `online/offline/unknown` status |
| [ADR-015](decisions/ADR-015-vibe-device-action-architecture.md) | Vibe device action architecture | Vibe owns action list; `turn_on/turn_off/toggle` MVP; failure does not block audio |
| [ADR-016](decisions/ADR-016-smart-home-async-execution.md) | Smart Home async execution | No provider calls in CRUD path; queue worker; audio unaffected by failure |
| [ADR-017](decisions/ADR-017-push-notification-provider-strategy.md) | Push notification provider strategy | FCM first; Android first; backend abstraction; no campaigns |
| [ADR-018](decisions/ADR-018-device-token-registration.md) | Device token registration | `push_tokens` registry; upsert dedupe; multi-device; logout deactivate |
| [ADR-019](decisions/ADR-019-notification-event-taxonomy.md) | Notification event taxonomy | Operational events only; explicit payload schema; no marketing |
| [ADR-020](decisions/ADR-020-push-delivery-and-fallback-strategy.md) | Push delivery and fallback | Async queue; best-effort; local notifications preserved |
| [ADR-021](decisions/ADR-021-notification-security-and-privacy.md) | Notification security and privacy | Minimal payload; no secrets; no cross-user tokens |
| [ADR-022](decisions/ADR-022-scheduler-smart-home-automation-model.md) | Scheduler + Smart Home automation model | No automation engine; Schedule + Vibe + VibeDeviceAction composition |
| [ADR-023](decisions/ADR-023-automation-execution-order-and-failure-policy.md) | Automation execution order and failure policy | Best-effort async; SH failure must not block recurrence |
| [ADR-024](decisions/ADR-024-automation-notifications-and-observability.md) | Automation notifications and observability | Reuse failure events; no success push by default |
| [ADR-025](decisions/ADR-025-automation-mobile-ux.md) | Automation mobile UX | Surface on existing screens; no automation builder in MVP |
| [ADR-026](decisions/ADR-026-automation-execution-security.md) | Automation execution security | Policies = HTTP; Domain Validators = async; platform-wide ([domain-validation](architecture/domain-validation.md)) |
| [ADR-027](decisions/ADR-027-asynchronous-orchestration-pattern.md) | Asynchronous orchestration pattern | Entrypoints orchestrate; validators guard; services decide; jobs work; providers integrate ([asynchronous-orchestration](architecture/asynchronous-orchestration.md)) |
| [ADR-028](decisions/ADR-028-observability-platform.md) | Observability platform | Single OTel Collector; apps export OTLP only; Prometheus/Loki/Tempo via Collector |
| [ADR-029](decisions/ADR-029-telemetry-data-model.md) | Telemetry data model | Metrics, logs, traces, events; `ixora.*` naming; correlation IDs |
| [ADR-030](decisions/ADR-030-observability-security-and-privacy.md) | Observability security and privacy | No PII/secrets in telemetry; Collector redaction; extends ADR-021 |
| [ADR-031](decisions/ADR-031-retention-storage-and-cost-control.md) | Retention and cost control | Metrics 30d / logs 14d / traces 7d; sampling; cardinality limits; single VM |

---

# 5. Infrastructure

OpenTofu-managed staging footprint on DigitalOcean.

| Document | Description |
| --- | --- |
| [opentofu/staging/README.md](../opentofu/staging/README.md) | Prerequisites, `tofu init/plan/apply`, secrets, cost notes |
| [architecture/backend/staging-digitalocean.md](architecture/backend/staging-digitalocean.md) | App Platform apps, VPC, Postgres, Spaces, env vars, CORS |

**Stack path:** `ixora-infra/opentofu/staging/` — VPC, managed PostgreSQL, Spaces bucket, Laravel API + queue worker, Nuxt admin static site.

**Secrets:** never in git — `terraform.tfvars` (gitignored) or `TF_VAR_*`.

---

# 6. Operations

Runbooks for homologation deploy, validation, and coordination.

| Document | Description |
| --- | --- |
| [scheduler-smart-home-operational-checklist.md](operations/scheduler-smart-home-operational-checklist.md) | **Scheduler + Smart Home ops runbook** — workers, queues, env, health checks, failure matrix, deploy/recovery/troubleshooting |
| [scheduler-smart-home-e2e/summary.md](qa/scheduler-smart-home-e2e/summary.md) | **Phase 8 E2E QA report** — happy-path, failure, mobile UX, notification, architecture ADR validation |
| [deploy-pipeline.md](architecture/backend/deploy-pipeline.md) | `feature` → `develop` → `staging`, OpenTofu apply, App Platform, migrations |
| [staging-digitalocean.md](architecture/backend/staging-digitalocean.md) | Runtime topology, queue worker, secrets boundaries |
| [git-flow.md](standards/git-flow.md) | Branch protection rules, multi-repo promotion checklist |
| [mobile-cdn-validation.md](architecture/storage/mobile-cdn-validation.md) | Staging QA checklist for assets on device |
| [admin-form-patterns.md](standards/admin-form-patterns.md) | Admin staging manual checklist (forms/uploads) |

**Typical staging promotion**

```bash
# Per repository, when QA-ready:
git checkout staging && git pull origin staging
git merge --no-ff develop -m "Merge branch 'develop' into staging"
git push origin staging

# When ixora-infra OpenTofu changed:
cd opentofu/staging && tofu plan && tofu apply

# When back_vibes schema changed:
# Run php artisan migrate --force against staging DB (manual — see deploy-pipeline.md)
```

**Default staging URLs**

| Surface | URL |
| --- | --- |
| API | `https://staging-api.ixora-app.app` |
| Admin | `https://staging-admin.ixora-app.app` |

---

# 7. Quality & testing

Minimal local validation commands and real-device mobile E2E standards.

| Document | Description |
| --- | --- |
| [quality-harness.md](quality-harness.md) | **Baseline commands** — back_vibes, ixora-admin, front_vibes (unit, lint, typecheck, build) |
| [mobile-e2e-testing.md](testing/mobile-e2e-testing.md) | **Real-device Android E2E** — Appium + WebdriverIO: when required, what to test, selectors, release criteria, failure triage |

**Appium** is the official gate for native plugins, local/push notifications, offline sync, and release-critical mobile journeys. It complements — does not replace — the quality harness.

---

# 8. Templates

Reusable document scaffolds for spec-driven development. **All new feature specifications must use these templates.**

| Template | Description |
| --- | --- |
| [feature-spec-template.md](templates/feature-spec-template.md) | **Feature Specification Template** — mandatory structure for every new feature spec, including required **Architecture Mapping** (async entrypoint → validator → service → job → provider) per [ADR-026](decisions/ADR-026-automation-execution-security.md) and [ADR-027](decisions/ADR-027-asynchronous-orchestration-pattern.md). Complements [`feature-design-checklist.md`](architecture/feature-design-checklist.md), [`user-experience-principles.md`](architecture/user-experience-principles.md), [`domain-validation.md`](architecture/domain-validation.md), and [`asynchronous-orchestration.md`](architecture/asynchronous-orchestration.md). |

**Workflow:** complete [feature-design-checklist.md](architecture/feature-design-checklist.md) → review [user-experience-principles.md](architecture/user-experience-principles.md) §12 → copy template → `docs/specs/<domain>/<feature>/spec.md` → complete Architecture Mapping → review (§9 of checklist) → implement in phases.

---

## Maintaining this index

When adding documentation:

1. Place files under `docs/specs/`, `docs/architecture/`, `docs/operations/`, `docs/standards/`, `docs/decisions/`, `docs/templates/`, `docs/testing/`, or `docs/onboarding/`.
2. Add a row to the appropriate **§1–§8** table above.
3. **New feature specs:** start from [`architecture/feature-design-checklist.md`](architecture/feature-design-checklist.md), then [`architecture/user-experience-principles.md`](architecture/user-experience-principles.md), then [`templates/feature-spec-template.md`](templates/feature-spec-template.md).
4. Cross-link from related specs/architecture docs.
5. Mark **planning-only** docs clearly — do not list them as shipped in [Current platform status](#current-platform-status).

**Cursor workspace rule:** keep [`.cursor/rules/git-flow.mdc`](../../.cursor/rules/git-flow.mdc) aligned with [git-flow.md](standards/git-flow.md).

---

## External repositories

App repos maintain **copies** of some docs for local discovery — sync from here when policy changes.

| Repo | Example local docs |
| --- | --- |
| `back_vibes` | `docs/storage-strategy.md`, `docs/laravel-spaces-service.md` |
| `front_vibes` | `docs/mobile-cdn-validation.md`, `docs/artwork-background-strategy.md` |
| `ixora-admin` | `docs/upload-validation.md`, `docs/storage-strategy.md` |

---

*Last indexed: documentation tree under `ixora-infra/docs/`. Last updated: 2026-07-05 (observability-foundation Phase 1).*
