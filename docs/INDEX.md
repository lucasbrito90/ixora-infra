# Ixora Docs — Index

**Navigation entry point.** Read this first; then load only the documents relevant to your task.
Full reference: [`README.md`](README.md) (715 lines — detailed, load only when the index is insufficient).

---

## By task type

| Task | Read first |
| --- | --- |
| New feature (any repo) | [`architecture/feature-design-checklist.md`](architecture/feature-design-checklist.md) → relevant spec in `specs/` |
| Understand repo boundaries | [`architecture/repo-responsibilities.md`](architecture/repo-responsibilities.md) |
| Auth flow | [`standards/front-vibes-auth-core.md`](standards/front-vibes-auth-core.md) + [ADR-001](decisions/ADR-001-firebase-auth-laravel-sync.md) |
| Storage / Spaces / CDN | [`architecture/storage/storage-strategy.md`](architecture/storage/storage-strategy.md) + [ADR-002](decisions/ADR-002-laravel-only-storage-writes.md) |
| Mobile playback / execution plan | [`architecture/audio/playback-runtime.md`](architecture/audio/playback-runtime.md) + [ADR-007](decisions/ADR-007-execution-plan-runtime-contract.md) |
| Offline audio | [`architecture/audio/audio-cache.md`](architecture/audio/audio-cache.md) + [ADR-004](decisions/ADR-004-offline-audio-strategy.md) |
| Scheduler feature | [`specs/scheduler/mvp/spec.md`](specs/scheduler/mvp/spec.md) + ADR-009, ADR-010, ADR-011 |
| Smart Home feature | [`specs/smart-home/INDEX.md`](specs/smart-home/INDEX.md) |
| Push notifications | [`architecture/notification-architecture.md`](architecture/notification-architecture.md) + [`specs/push-notifications/mvp/spec.md`](specs/push-notifications/mvp/spec.md) |
| Observability / telemetry | [`specs/observability-foundation/INDEX.md`](specs/observability-foundation/INDEX.md) |
| KMP / ixora-app | [`architecture/mobile/kmp-migration-plan.md`](architecture/mobile/kmp-migration-plan.md) + ADR-038, ADR-039, ADR-042 |
| Staging deploy / infra | [`architecture/backend/staging-digitalocean.md`](architecture/backend/staging-digitalocean.md) + [`architecture/backend/deploy-pipeline.md`](architecture/backend/deploy-pipeline.md) |
| Admin panel uploads | [`standards/upload-validation.md`](standards/upload-validation.md) + [`standards/admin-form-patterns.md`](standards/admin-form-patterns.md) |
| Laravel API patterns | [`standards/api-resource-patterns.md`](standards/api-resource-patterns.md) + [`standards/laravel-form-request-patterns.md`](standards/laravel-form-request-patterns.md) |
| Git workflow | [`standards/git-flow.md`](standards/git-flow.md) |
| Quality gates | [`quality-harness.md`](quality-harness.md) |
| Past decisions | [`decisions/`](decisions/) — ADR-001 through ADR-044 |

---

## Domain indexes

| Domain | Index |
| --- | --- |
| Architecture (cross-cutting) | [`architecture/INDEX.md`](architecture/INDEX.md) |
| Smart Home | [`specs/smart-home/INDEX.md`](specs/smart-home/INDEX.md) |
| Observability Foundation | [`specs/observability-foundation/INDEX.md`](specs/observability-foundation/INDEX.md) |

---

## Source of truth

| Source | Authority |
| --- | --- |
| **ADRs** (`decisions/ADR-*.md`) | **Accepted architectural decisions** — what the architecture is, intentionally and bindingly. Supersede all prior proposals. |
| **Source code and tests** | Current implementation — what exists today in the codebase. |
| **Current domain docs** | Operational specs and standards (`specs/`, `standards/`, `architecture/`). |
| **Supporting docs** | Plans, tasks, checklists — context, not authority. |
| **Historical / archived** | Read for context only; never cite as current architecture or decision. |

**ADR vs implementation conflict:** When an accepted ADR and the current implementation disagree, do not automatically conclude that the code wins. Instead:
- State that a divergence exists
- Report what the ADR mandates (the architectural decision)
- Report what the implementation does today
- Do not resolve the conflict by inference
- Flag that either the implementation or the documentation needs correction

**No-inference rule:** If required information cannot be established from the above sources, identify what is known, identify what is missing, report the gap, and ask for clarification. Never invent undocumented API contracts, provider behavior, authentication flows, or implementation rules.
