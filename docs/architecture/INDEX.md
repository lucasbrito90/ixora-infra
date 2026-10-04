# Architecture — Index

Cross-cutting architecture documents. Load only what your task requires.

## Cross-cutting

| Document | Purpose |
| --- | --- |
| [`architecture-map.md`](architecture-map.md) | Platform overview — components, flows, repo roles |
| [`repo-responsibilities.md`](repo-responsibilities.md) | Per-repo must/must-not, anti-patterns, decision guide |
| [`feature-design-checklist.md`](feature-design-checklist.md) | Pre-spec checklist — required before any new feature spec |
| [`user-experience-principles.md`](user-experience-principles.md) | Platform-wide UX: loading, empty, error, microcopy, a11y |
| [`notification-architecture.md`](notification-architecture.md) | Platform-wide notification design (local + push) |
| [`domain-validation.md`](domain-validation.md) | HTTP Policies vs async Domain Validators (ADR-026) |
| [`asynchronous-orchestration.md`](asynchronous-orchestration.md) | Async layering: entrypoint → validator → service → job → provider (ADR-027) |

## Audio / Playback

| Document | Purpose |
| --- | --- |
| [`audio/playback-runtime.md`](audio/playback-runtime.md) | Pinia, AudioEngine, FGS, native audio |
| [`audio/audio-cache.md`](audio/audio-cache.md) | Streaming cache vs offline download |
| [`audio/audio-engine-fade-limitations.md`](audio/audio-engine-fade-limitations.md) | Why JS fades are not applied |
| [`audio/native-loop-fadein.md`](audio/native-loop-fadein.md) | Native loop / fade-in constraints |

## Storage

| Document | Purpose |
| --- | --- |
| [`storage/storage-strategy.md`](storage/storage-strategy.md) | Spaces access, key layout, safe deletion |
| [`storage/spaces-cdn-policy.md`](storage/spaces-cdn-policy.md) | CDN URLs, cache, offline URL identity |
| [`storage/mobile-cdn-validation.md`](storage/mobile-cdn-validation.md) | Device QA for HTTPS assets |
| [`storage/artwork-background-strategy.md`](storage/artwork-background-strategy.md) | Artwork vs player background selection |
| [`storage/future-processing-pipeline.md`](storage/future-processing-pipeline.md) | **Planning only — not shipped** |

## Mobile / KMP

| Document | Purpose |
| --- | --- |
| [`mobile/kmp-migration-plan.md`](mobile/kmp-migration-plan.md) | Full KMP migration plan (binding with ADR-038, ADR-039, ADR-042) |
| [`mobile/android-native-customizations.md`](mobile/android-native-customizations.md) | Capacitor/Android patches and native hooks |
| [`mobile/kmp-execution-order.md`](mobile/kmp-execution-order.md) | KMP card execution order |

## Backend

| Document | Purpose |
| --- | --- |
| [`backend/staging-digitalocean.md`](backend/staging-digitalocean.md) | Staging topology (DO App Platform) |
| [`backend/deploy-pipeline.md`](backend/deploy-pipeline.md) | Git → OpenTofu → App Platform delivery |
| [`backend/scheduling-model.md`](backend/scheduling-model.md) | **Planning only — not shipped** |

## Observability philosophy (load before writing telemetry)

| Document | Purpose |
| --- | --- |
| [`metrics-philosophy.md`](metrics-philosophy.md) | How to think about metrics |
| [`logs-philosophy.md`](logs-philosophy.md) | How to think about logs |
| [`traces-philosophy.md`](traces-philosophy.md) | How to think about traces |
| [`telemetry-naming-convention.md`](telemetry-naming-convention.md) | Platform-wide naming |
| [`telemetry-decision-guide.md`](telemetry-decision-guide.md) | Which signal to emit |
| [`telemetry-availability-policy.md`](telemetry-availability-policy.md) | Telemetry must never block business logic |
| [`alerting-philosophy.md`](alerting-philosophy.md) | Alert design principles |
| [`recording-rules-philosophy.md`](recording-rules-philosophy.md) | Recording rules design principles |
| [`slo-philosophy.md`](slo-philosophy.md) | SLI/SLO/error budget concepts |
| [`observability-operational-limits.md`](observability-operational-limits.md) | Architectural caps |
